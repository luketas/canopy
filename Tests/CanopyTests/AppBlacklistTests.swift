import Testing
import AppKit
import CanopyCore
@testable import Canopy

@Test @MainActor
func blacklistingAnAppRemovesEveryGridMembershipAndRestoresItsWindowOnce() throws {
    let bridge = FakeWindows(),(store,directory) = makeStore(bridge: bridge)
    defer { store.shutdown(); try? FileManager.default.removeItem(at: directory) }
    let baseline = bridge.frames["c"]
    store.addWindowsToCurrentGrid(["a","c"]); store.applyCurrentGrid()
    store.addWorkspaceGrid(); store.addWindowsToCurrentGrid(["b","c"])
    bridge.restores = []; bridge.moves = []; bridge.raised = []; bridge.activated = []
    store.excludeApp("fixture.c")
    #expect(store.excludedApps.contains("fixture.c"))
    #expect(store.displays.allSatisfy { !$0.allGridWindows.contains("c") })
    #expect(bridge.restores == ["c"] && bridge.frames["c"] == baseline)
    #expect(!store.movedWindows.contains("c") && !store.occludedWindows.contains("c"))
    #expect(!store.listedRecords.contains { $0.id == "c" })
    #expect(store.records.contains { $0.id == "c" } && bridge.windows["c"] != nil)
    #expect(!bridge.moves.contains { $0.0 == "c" })
    #expect(bridge.raised.last == "c" && bridge.activated.isEmpty)
    store.undo()
    #expect(store.displays.allSatisfy { !$0.allGridWindows.contains("c") })
}

@Test @MainActor
func blacklistedAppsStayAboveGridSwitchesAndCannotBeDockedOrAutoArranged() throws {
    let bridge = FakeWindows(),(store,directory) = makeStore(bridge: bridge)
    defer { store.shutdown(); try? FileManager.default.removeItem(at: directory) }
    store.excludeApp("fixture.c")
    store.addWindowsToCurrentGrid(["a"]); store.applyCurrentGrid()
    let first = try #require(store.current?.activeGridID)
    store.addWorkspaceGrid(); store.addWindowsToCurrentGrid(["b"])
    bridge.moves = []; bridge.restores = []; bridge.raised = []; bridge.minimizeRequests = []
    store.selectWorkspaceGrid(first,activate: true)
    #expect(bridge.raised.last == "c")
    let before = store.displays
    store.addWindowsToCurrentGrid(["c"])
    store.dock("c",target: store.current?.root?.id,edge: .right)
    store.dock(["c"],intent: DockIntent(display: "test-display",target: store.current?.root?.id,edge: .bottom,preview: fixtureDisplays[0].frame))
    #expect(!store.giveWindowOwnColumn("c"))
    #expect(store.displays == before)
    store.autoLayoutCurrentMonitor()
    #expect(store.currentGridWindowIDs == ["a"])
    #expect(store.current?.grids.contains { $0.root?.allWindows == ["b"] } == true)
    #expect(!store.desktopPlans().flatMap(\.nativePlacements).contains { $0.window == "c" })
    #expect(!bridge.moves.contains { $0.0 == "c" })
    #expect(!bridge.restores.contains("c") && bridge.minimizeRequests.isEmpty)
    #expect(bridge.raised.last == "c")
}

@Test @MainActor
func aNewBlacklistedWindowIsTrackedForFloatingButCannotActivateAnotherGrid() throws {
    let bridge = FakeWindows(),(store,directory) = makeStore(bridge: bridge)
    defer { store.shutdown(); try? FileManager.default.removeItem(at: directory) }
    store.addWindowsToCurrentGrid(["a"]); store.applyCurrentGrid()
    store.addWorkspaceGrid(); store.addWindowsToCurrentGrid(["b"])
    store.excludeApp("fixture.c")
    let grid = store.current?.activeGridID
    // Recreate a utility window after launch. Its bundle rule must apply to
    // future windows rather than just the IDs present when it was blacklisted.
    let removed = bridge.windows.removeValue(forKey: "c")
    var fresh = try #require(removed)
    fresh.record.id = "fresh-utility"; bridge.windows[fresh.id] = fresh
    let oldFrame = bridge.frames.removeValue(forKey: "c")
    bridge.frames[fresh.id] = oldFrame
    bridge.moves = []; bridge.raised = []; bridge.activated = []
    store.refresh()
    bridge.focused = fresh.id; bridge.frontmostProcessID = fresh.pid
    store.handleNativeActivation(processID: fresh.pid)
    #expect(store.current?.activeGridID == grid)
    #expect(store.alwaysFloatingWindows.map(\.id) == [fresh.id])
    #expect(!store.availableRecords.contains { $0.id == fresh.id })
    #expect(bridge.raised.last == fresh.id && bridge.activated.isEmpty)
    #expect(!bridge.moves.contains { $0.0 == fresh.id })
}

@Test @MainActor
func minimizedAndOffDesktopBlacklistedAppsAreNeverRaisedOrUnminimized() throws {
    let bridge = FakeWindows(),(store,directory) = makeStore(bridge: bridge)
    defer { store.shutdown(); try? FileManager.default.removeItem(at: directory) }
    store.excludeApp("fixture.c"); store.addWindowsToCurrentGrid(["a"]); store.applyCurrentGrid()
    bridge.raised = []; bridge.minimizeRequests = []
    bridge.windows["c"]?.minimized = true
    store.applyLayout(); store.raiseAlwaysFloatingWindows()
    #expect(!bridge.raised.contains("c") && bridge.minimizeRequests.isEmpty)
    bridge.windows["c"]?.minimized = false; bridge.windows["c"]?.onScreen = false
    store.applyLayout(); store.raiseAlwaysFloatingWindows()
    #expect(!bridge.raised.contains("c"))
}

@Test @MainActor
func shottrIsSeededOnceAndAnExplicitRemovalSurvivesRelaunch() throws {
    let bridge = FakeWindows(),(store,directory) = makeStore(bridge: bridge)
    defer { store.shutdown(); try? FileManager.default.removeItem(at: directory) }
    #expect(store.excludedApps.contains("cc.ffitch.shottr"))
    #expect(store.blacklistedApplications.contains { $0.id == "cc.ffitch.shottr" && $0.name == "Shottr" })
    store.includeApp("cc.ffitch.shottr"); store.persist()
    let reloaded = WorkspaceStore(bridge: bridge,storageURL: directory.appendingPathComponent("workspace.json"),screens: { fixtureDisplays })
    defer { reloaded.shutdown() }
    #expect(!reloaded.excludedApps.contains("cc.ffitch.shottr"))
    #expect(reloaded.snapshot.floatingAppsVersion == 1)
    var legacy = store.snapshot; legacy.floatingAppsVersion = nil
    store.restoreSnapshot(legacy)
    #expect(store.excludedApps.contains("cc.ffitch.shottr"))
}

@Test @MainActor
func allowingAnAppAgainMakesItAvailableWithoutAutomaticallyAddingItToAGrid() throws {
    let bridge = FakeWindows(),(store,directory) = makeStore(bridge: bridge)
    defer { store.shutdown(); try? FileManager.default.removeItem(at: directory) }
    store.addWindowsToCurrentGrid(["a","c"]); store.applyCurrentGrid()
    store.excludeApp("fixture.c")
    store.includeApp("fixture.c")
    #expect(store.availableRecords.contains { $0.id == "c" })
    #expect(!store.currentGridWindowIDs.contains("c"))
    store.addWindowsToCurrentGrid(["c"])
    #expect(store.currentGridWindowIDs.contains("c"))
}

@Test @MainActor
func importingABlacklistPrunesAllStoredGridMembershipBeforeAnyNativeMovement() throws {
    let bridge = FakeWindows(),(store,directory) = makeStore(bridge: bridge)
    defer { store.shutdown(); try? FileManager.default.removeItem(at: directory) }
    store.addWindowsToCurrentGrid(["a","c"])
    store.addWorkspaceGrid(); store.addWindowsToCurrentGrid(["b","c"])
    var state = store.snapshot; state.excludedApps.insert("fixture.c")
    let roundTrip = try JSONDecoder().decode(WorkspaceSnapshot.self,from: JSONEncoder().encode(state))
    try WorkspaceStore.validate(roundTrip)
    bridge.moves = []
    store.restoreSnapshot(roundTrip)
    #expect(store.displays.allSatisfy { !$0.allGridWindows.contains("c") })
    #expect(bridge.moves.isEmpty)
    #expect(store.excludedApps.contains("fixture.c"))
}

@Test @MainActor
func scopedAutoLayoutNeverRaisesABlacklistedWindowOnAnotherMonitor() throws {
    let bridge = FakeWindows()
    let left = DisplayDescriptor(id: "left",name: "Left",frame: LayoutRect(x: -1440,y: 0,width: 1440,height: 900))
    bridge.frames["c"] = LayoutRect(x: -1000,y: 100,width: 500,height: 500)
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let store = WorkspaceStore(bridge: bridge,storageURL: directory.appendingPathComponent("workspace.json"),screens: { fixtureDisplays+[left] })
    defer { store.shutdown(); try? FileManager.default.removeItem(at: directory) }
    store.excludeApp("fixture.c"); store.addWindowsToCurrentGrid(["a"]); store.applyCurrentGrid()
    bridge.moves = []; bridge.raised = []
    store.autoLayoutCurrentMonitor()
    #expect(!bridge.moves.contains { $0.0 == "c" } && !bridge.raised.contains("c"))
    #expect(store.currentGridWindowIDs == ["a","b"])
}
