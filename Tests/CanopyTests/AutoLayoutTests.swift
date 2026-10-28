import Testing
import AppKit
import Carbon
import CanopyCore
@testable import Canopy

@MainActor
private func addAutoWindow(_ key: String,to bridge: FakeWindows,frame: LayoutRect) {
    let record = WindowRecord(id: key,bundleID: "fixture.\(key)",app: "Fixture \(key)",title: key,ordinal: 0,originalFrame: frame)
    bridge.windows[key] = DiscoveredWindow(record: record,element: AXUIElementCreateApplication(pid_t(2000+bridge.windows.count)),pid: pid_t(2000+bridge.windows.count),minimized: false,icon: nil)
    bridge.frames[key] = frame
}

@MainActor
private func autoStore(_ bridge: FakeWindows,screens: [DisplayDescriptor]) -> (WorkspaceStore,URL) {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("canopy-auto-tests-\(UUID().uuidString)")
    return (WorkspaceStore(bridge: bridge,storageURL: directory.appendingPathComponent("workspace.json"),screens: { screens }),directory)
}

@Test(arguments: [2,4], [800.0,1280.0,3440.0]) @MainActor
func autoLayoutMakesTwoEqualColumnsAndFourEqualQuadrants(count: Int,width: Double) throws {
    let bridge = FakeWindows()
    bridge.windows = [:]; bridge.frames = [:]
    let screen = DisplayDescriptor(id: "target",name: "Target",frame: LayoutRect(width: width,height: width == 800 ? 1600 : 1000))
    for index in 0..<count { addAutoWindow("w\(index)",to: bridge,frame: LayoutRect(x: 30,y: 70,width: 500,height: 600)) }
    let (store,directory) = autoStore(bridge,screens: [screen])
    defer { store.shutdown(); try? FileManager.default.removeItem(at: directory) }
    store.autoLayoutCurrentMonitor()
    let root = try #require(store.current?.root)
    let viewport = store.desktopViewport(screen)
    let cells = root.placements(in: viewport,gap: store.gap)
    #expect(store.isArranging)
    #expect(cells.count == count)
    #expect(Set(cells.map { $0.rect.x }).count == 2)
    #expect(Set(cells.map { $0.rect.y }).count == (count == 4 ? 2 : 1))
    #expect(cells.allSatisfy { abs($0.rect.width-(viewport.width-store.gap)/2) < 0.01 })
    #expect(cells.allSatisfy { abs($0.rect.height-(count == 4 ? (viewport.height-store.gap)/2 : viewport.height)) < 0.01 })
    #expect(bridge.moves.count == count)
    #expect(bridge.minimizeRequests.isEmpty)
}

@Test @MainActor
func explicitAutoLayoutCanArrangeAnAdditionalMonitorWithoutChangingExistingOnes() throws {
    let bridge = FakeWindows()
    let left = DisplayDescriptor(id: "left",name: "Left",frame: LayoutRect(x: -1440,y: -150,width: 1440,height: 1000))
    let right = fixtureDisplays[0]
    bridge.frames["a"] = LayoutRect(x: -1300,y: 40,width: 500,height: 600)
    bridge.frames["b"] = LayoutRect(x: -700,y: 40,width: 500,height: 600)
    let (store,directory) = autoStore(bridge,screens: [right,left])
    defer { store.shutdown(); try? FileManager.default.removeItem(at: directory) }
    store.displays[0].root = LayoutNode(window: "c")
    store.displays[1].root = LayoutNode(window: "a")
    store.arrange(enrollAvailable: false)
    let other = store.displays[0]
    // A manual resize elsewhere must not be corrected by this local action.
    bridge.frames["c"] = LayoutRect(x: 150,y: 120,width: 600,height: 500)
    let otherFrame = bridge.frames["c"]
    bridge.moves = []; bridge.raised = []; bridge.restores = []; bridge.minimizeRequests = []
    bridge.focused = "c"; store.selectedDisplay = left.id
    var scopes: [String?] = []
    store.onLayoutWillApply = { _ in scopes.append(store.layoutDisplayScope) }
    store.autoLayoutCurrentMonitor()
    #expect(store.selectedDisplay == left.id)
    #expect(Set(store.currentGridWindowIDs) == ["a","b"])
    #expect(store.displays[0] == other)
    #expect(bridge.frames["c"] == otherFrame)
    #expect(Set(bridge.moves.map(\.0)) == ["a","b"])
    #expect(!bridge.raised.contains("c"))
    #expect(bridge.restores.isEmpty && bridge.minimizeRequests.isEmpty)
    #expect(scopes == [left.id])
    #expect(store.canUndo)
}

@Test @MainActor
func autoLayoutStartsOnlyOneMonitorAndSkipsOtherSpacesMinimizedFullscreenAndInactiveGridWindows() throws {
    let bridge = FakeWindows()
    for key in ["a","b"] { bridge.frames[key] = LayoutRect(x: 80,y: 100,width: 500,height: 500) }
    bridge.frames["c"] = LayoutRect(x: -1000,y: 0,width: 600,height: 500)
    let local = fixtureDisplays[0]
    let other = DisplayDescriptor(id: "other",name: "Other",frame: LayoutRect(x: -1440,y: -200,width: 1440,height: 1000))
    for key in ["space","minimized","fullscreen","inactive","excluded"] {
        addAutoWindow(key,to: bridge,frame: LayoutRect(x: 80,y: 100,width: 500,height: 500))
    }
    bridge.windows["space"]?.onScreen = false
    bridge.windows["minimized"]?.minimized = true
    bridge.windows["fullscreen"]?.fullScreen = true
    let (store,directory) = autoStore(bridge,screens: [local,other])
    defer { store.shutdown(); try? FileManager.default.removeItem(at: directory) }
    store.excludedApps.insert("fixture.excluded")
    store.occludedWindows.insert("inactive")
    store.displays[1].root = LayoutNode(window: "c")
    let otherGrid = store.displays[1]
    let otherFrame = bridge.frames["c"]
    store.autoLayoutCurrentMonitor()
    #expect(store.currentGridWindowIDs == ["a","b"])
    #expect(store.arrangedDisplayIDs == [local.id])
    #expect(store.desktopPlans().map { $0.display.id } == [local.id])
    // Later notifications and normal layout updates must not enroll that monitor.
    store.refresh(); store.applyLayout()
    #expect(store.displays[1] == otherGrid)
    #expect(bridge.frames["c"] == otherFrame)
    #expect(Set(bridge.moves.map(\.0)) == ["a","b"])
    #expect(!bridge.raised.contains("c"))
    #expect(bridge.minimizeRequests.isEmpty)
}

@Test @MainActor
func emptyOrUnfitAutoLayoutDoesNotChangeOrMoveAnything() throws {
    let bridge = FakeWindows(),(store,directory) = makeStore(bridge: bridge)
    defer { store.shutdown(); try? FileManager.default.removeItem(at: directory) }
    for key in bridge.windows.keys { bridge.windows[key]?.onScreen = false }
    let old = store.displays
    store.autoLayoutCurrentMonitor()
    #expect(store.displays == old && !store.isArranging && !store.canUndo)
    #expect(bridge.moves.isEmpty)
    for key in bridge.windows.keys { bridge.windows[key]?.onScreen = true }
    bridge.minimums["a"] = CGSize(width: 1200,height: 800)
    store.autoLayoutCurrentMonitor()
    #expect(store.displays == old && !store.isArranging && !store.canUndo)
    #expect(bridge.moves.isEmpty)
    #expect(store.message?.contains("minimum sizes") == true)
}

@Test @MainActor
func autoLayoutShortcutMigratesWithoutReplacingAUsersBinding() throws {
    let binding = try #require(ShortcutBinding.defaults.first { $0.id == "auto-layout" })
    #expect(binding.keyCode == 0 && binding.modifiers == UInt32(controlKey | optionKey))
    #expect(binding.matches(keyCode: 0,flags: [.control,.option]))
    let old = ShortcutBinding.defaults.filter { $0.id != "auto-layout" }
    #expect(ShortcutBinding.addingMissingDefaults(to: old).contains(binding))
    var custom = binding; custom.enabled = false; custom.keyCode = 1; custom.key = "S"
    #expect(ShortcutBinding.addingMissingDefaults(to: old+[custom]).first { $0.id == "auto-layout" } == custom)
    var conflict = old[0]; conflict.keyCode = binding.keyCode; conflict.modifiers = binding.modifiers
    #expect(ShortcutBinding.addingMissingDefaults(to: [conflict]).first { $0.id == "auto-layout" }?.enabled == false)
}

@Test @MainActor
func rejectedAutoLayoutRestoresOnlyItsMonitor() async throws {
    let bridge = FakeWindows()
    let right = fixtureDisplays[0]
    let left = DisplayDescriptor(id: "left",name: "Left",frame: LayoutRect(x: -1440,y: 0,width: 1440,height: 900))
    bridge.frames["a"] = LayoutRect(x: -1300,y: 100,width: 500,height: 500)
    bridge.frames["b"] = LayoutRect(x: -700,y: 100,width: 500,height: 500)
    let (store,directory) = autoStore(bridge,screens: [right,left])
    defer { store.shutdown(); try? FileManager.default.removeItem(at: directory) }
    store.displays[0].root = LayoutNode(window: "c")
    store.arrange(enrollAvailable: false)
    let other = store.displays[0],otherFrame = bridge.frames["c"]
    bridge.moves = []; bridge.restores = []; bridge.raised = []
    bridge.deferMoves = true
    store.selectedDisplay = left.id; store.autoLayoutCurrentMonitor()
    let deadline = Date().addingTimeInterval(5)
    while store.message?.contains("Auto Layout paused") != true,Date() < deadline {
        try await Task.sleep(nanoseconds: 20_000_000)
    }
    #expect(store.message?.contains("Auto Layout paused") == true)
    #expect(store.isArranging)
    #expect(store.arrangedDisplayIDs == [right.id])
    #expect(store.displays[0] == other && bridge.frames["c"] == otherFrame)
    #expect(!bridge.moves.contains { $0.0 == "c" } && !bridge.restores.contains("c") && !bridge.raised.contains("c"))
}

@Test @MainActor
func pointerInMenuBarAndWindowStraddlingDisplaysUsePhysicalMonitorBounds() throws {
    let bridge = FakeWindows()
    let left = DisplayDescriptor(id: "left",name: "Left",frame: LayoutRect(x: -1440,y: 24,width: 1440,height: 850),bounds: LayoutRect(x: -1440,y: 0,width: 1440,height: 900))
    bridge.frames["a"] = LayoutRect(x: -500,y: 100,width: 600,height: 500)
    bridge.frames["b"] = LayoutRect(x: -80,y: 100,width: 600,height: 500)
    let (store,directory) = autoStore(bridge,screens: fixtureDisplays+[left])
    defer { store.shutdown(); try? FileManager.default.removeItem(at: directory) }
    let other = bridge.frames["b"]
    store.performCommand("auto-layout",at: CGPoint(x: -600,y: 10))
    #expect(store.selectedDisplay == left.id)
    #expect(store.currentGridWindowIDs == ["a"])
    #expect(bridge.frames["b"] == other)
    #expect(bridge.moves.map(\.0) == ["a"])
}

@Test @MainActor
func autoLayoutKeepsOtherTabsAndUnavailableMembersAndCanBeUndone() throws {
    let bridge = FakeWindows(),(store,directory) = makeStore(bridge: bridge)
    defer { store.shutdown(); try? FileManager.default.removeItem(at: directory) }
    store.addWindowsToCurrentGrid(["c"])
    let originalTab = try #require(store.current?.grids.first)
    store.addWorkspaceGrid(); store.addWindowsToCurrentGrid(["a","c"])
    let before = store.displays
    bridge.windows["c"]?.onScreen = false
    store.autoLayoutCurrentMonitor()
    #expect(store.currentGridWindowIDs == ["a","b","c"])
    #expect(store.current?.grids.first == originalTab)
    #expect(Set(store.desktopPlans().flatMap(\.nativePlacements).map(\.window)) == ["a","b"])
    #expect(!bridge.moves.contains { $0.0 == "c" })
    store.undo()
    #expect(store.displays == before)
    #expect(bridge.restores.contains("b"))
}

@Test @MainActor
func autoLayoutAdoptsOnlyTargetMonitorsRecoveryWithoutMovingTheRest() throws {
    let bridge = FakeWindows()
    let other = DisplayDescriptor(id: "other",name: "Other",frame: LayoutRect(x: -1440,y: 0,width: 1440,height: 900))
    bridge.frames["c"] = LayoutRect(x: -1000,y: 100,width: 500,height: 500)
    let (store,directory) = autoStore(bridge,screens: fixtureDisplays+[other])
    defer { store.shutdown(); try? FileManager.default.removeItem(at: directory) }
    var baseline = try #require(store.record("a"))
    baseline.originalFrame = LayoutRect(x: 30,y: 50,width: 300,height: 400)
    let otherBaseline = try #require(store.record("c"))
    store.pendingRecovery = [baseline,otherBaseline]
    store.autoLayoutCurrentMonitor()
    #expect(store.record("a")?.originalFrame == baseline.originalFrame)
    #expect(store.pendingRecovery.map(\.id) == ["c"])
    #expect(bridge.restores.isEmpty)
    #expect(!bridge.moves.contains { $0.0 == "c" })
}
