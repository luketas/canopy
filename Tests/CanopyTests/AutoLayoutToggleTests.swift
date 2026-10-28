import AppKit
import CanopyCore
import Testing
@testable import Canopy

@Test @MainActor
func autoLayoutShortcutTogglesOnOffAndOnWithoutDeletingSavedGrids() throws {
    let bridge = FakeWindows(),(store,directory) = makeStore(bridge: bridge)
    defer { store.shutdown(); try? FileManager.default.removeItem(at: directory) }
    let original = bridge.frames
    let pointer = CGPoint(x: 200,y: 200)
    var pauses = 0
    store.onPause = { pauses += 1 }
    store.performCommand("auto-layout",at: pointer)
    #expect(store.isArranging && store.autoLayoutWillRestore)
    #expect(bridge.frames != original)
    let savedGrids = store.displays
    bridge.moves = []
    store.performCommand("auto-layout",at: pointer)
    #expect(!store.isArranging && !store.hasWindowsToRestore && !store.autoLayoutWillRestore)
    #expect(bridge.frames == original)
    #expect(bridge.moves.isEmpty)
    #expect(Set(bridge.restores) == ["a","b","c"])
    #expect(store.displays == savedGrids)
    #expect(pauses == 1)
    store.refresh(); store.synchronizeScreens()
    #expect(!store.isArranging && bridge.moves.isEmpty)
    // A manual move while off becomes the next session's restoration baseline.
    let manual = LayoutRect(x: 120,y: 110,width: 500,height: 400)
    bridge.frames["a"] = manual
    store.performCommand("auto-layout",at: pointer)
    #expect(store.isArranging)
    #expect(store.record("a")?.originalFrame == manual)
    store.performCommand("auto-layout",at: pointer)
    #expect(!store.isArranging)
    #expect(bridge.frames["a"] == manual)
}

@Test @MainActor
func autoLayoutShortcutRestoresAnArrangementStartedByTheApplyButtonAcrossAllMonitors() throws {
    let bridge = FakeWindows()
    let right = fixtureDisplays[0]
    let left = DisplayDescriptor(id: "left",name: "Left",frame: LayoutRect(x: -1440,y: 0,width: 1440,height: 900))
    bridge.frames["a"] = LayoutRect(x: -1300,y: 100,width: 500,height: 500)
    bridge.frames["b"] = LayoutRect(x: -700,y: 100,width: 500,height: 500)
    let original = bridge.frames
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("canopy-toggle-\(UUID().uuidString)")
    let store = WorkspaceStore(bridge: bridge,storageURL: directory.appendingPathComponent("workspace.json"),screens: { [right,left] })
    defer { store.shutdown(); try? FileManager.default.removeItem(at: directory) }
    store.displays[0].root = LayoutNode(window: "c")
    store.displays[1].root = LayoutNode(first: LayoutNode(window: "a"),second: LayoutNode(window: "b"),axis: .horizontal)
    store.arrange(enrollAvailable: false)
    bridge.moves = []; bridge.restores = []
    // Restore matches the button's global scope, even when the pointer moves.
    store.performCommand("auto-layout",at: CGPoint(x: -600,y: 300))
    #expect(!store.isArranging)
    #expect(bridge.frames == original)
    #expect(Set(bridge.restores) == ["a","b","c"])
    #expect(bridge.moves.isEmpty)
}

@Test @MainActor
func autoLayoutShortcutReleasesPausedLayoutsAndRetriesIncompleteRestoration() throws {
    let bridge = FakeWindows(),(store,directory) = makeStore(bridge: bridge)
    defer { store.shutdown(); try? FileManager.default.removeItem(at: directory) }
    let original = bridge.frames
    let pointer = CGPoint(x: 200,y: 200)
    store.performCommand("auto-layout",at: pointer)
    store.pauseForSpaceChange()
    #expect(!store.isArranging && store.autoLayoutWillRestore)
    bridge.restoreFailures = ["a"]
    bridge.moves = []
    store.performCommand("auto-layout",at: pointer)
    #expect(!store.isArranging && store.hasWindowsToRestore && store.autoLayoutWillRestore)
    #expect(store.message?.contains("could not be restored") == true)
    #expect(bridge.moves.isEmpty)
    bridge.restoreFailures = []; bridge.restores = []
    store.performCommand("auto-layout",at: pointer)
    #expect(!store.isArranging && !store.hasWindowsToRestore && !store.autoLayoutWillRestore)
    #expect(bridge.restores == ["a"])
    #expect(bridge.frames == original)
}

@Test @MainActor
func autoLayoutShortcutReleasesAfterExternalMonitorDisconnectAndCanStartOnLaptop() throws {
    let bridge = FakeWindows()
    let laptop = fixtureDisplays[0]
    let external = DisplayDescriptor(id: "external",name: "External",frame: LayoutRect(x: -2560,y: -200,width: 2560,height: 1440))
    var screens = [laptop,external]
    bridge.frames["a"] = LayoutRect(x: -2400,y: 100,width: 1200,height: 900)
    bridge.frames["b"] = LayoutRect(x: -1100,y: 100,width: 1000,height: 900)
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("canopy-disconnect-\(UUID().uuidString)")
    let store = WorkspaceStore(bridge: bridge,storageURL: directory.appendingPathComponent("workspace.json"),screens: { screens })
    defer { store.shutdown(); try? FileManager.default.removeItem(at: directory) }
    store.performCommand("auto-layout",at: CGPoint(x: -600,y: 300))
    #expect(store.arrangedDisplayIDs == [external.id])
    let externalGrid = try #require(store.current)
    // Simulate macOS migrating windows to the remaining display on unplug.
    screens = [laptop]; bridge.restoreBounds = [laptop.frame]
    for key in ["a","b"] { bridge.frames[key] = LayoutRect(x: 80,y: 80,width: 800,height: 600) }
    store.synchronizeScreens()
    #expect(store.autoLayoutWillRestore)
    bridge.moves = []; bridge.restores = []
    store.performCommand("auto-layout",at: CGPoint(x: 200,y: 200))
    #expect(!store.isArranging && !store.hasWindowsToRestore)
    #expect(bridge.moves.isEmpty)
    #expect(Set(bridge.restores) == ["a","b"])
    #expect(bridge.frames.values.allSatisfy(laptop.frame.contains))
    #expect(store.displays.first { $0.id == external.id } == externalGrid)
    store.refresh(); store.synchronizeScreens()
    #expect(bridge.moves.isEmpty)
    store.performCommand("auto-layout",at: CGPoint(x: 200,y: 200))
    #expect(store.isArranging && store.arrangedDisplayIDs == [laptop.id])
    #expect(store.desktopPlans().allSatisfy { $0.display.id == laptop.id })
}

@Test @MainActor
func releaseShortcutCancelsAnInFlightWorkspaceSwitch() throws {
    let bridge = FakeWindows(),(store,directory) = makeStore(bridge: bridge)
    defer { store.shutdown(); try? FileManager.default.removeItem(at: directory) }
    store.arrange()
    let first = try #require(store.current?.activeGridID)
    store.addWorkspaceGrid(); store.addWindowsToCurrentGrid(["b"])
    var pending: (() -> Void)?
    store.onWorkspaceSwitch = { pending = $0 }
    store.selectWorkspaceGrid(first)
    #expect(store.workspaceSwitchPending)
    store.performCommand("auto-layout",at: CGPoint(x: 200,y: 200))
    #expect(!store.isArranging && !store.workspaceSwitchPending)
    bridge.moves = []
    let commit = try #require(pending)
    commit()
    #expect(!store.isArranging && bridge.moves.isEmpty)
}

@Test
func autoLayoutDispatchFiresOncePerHoldAndAcceptsTheNextPhysicalPress() {
    var state = HotKeyDispatchState()
    let first = state.shouldFire(7,time: 1,repeats: false)
    let duplicate = state.shouldFire(7,time: 1.005,repeats: false)
    let carbonRepeat = state.shouldFire(7,time: 1.5,repeats: false)
    let appKitRepeat = state.shouldFire(7,time: 1.8,repeats: false,isRepeat: true)
    #expect(first && !duplicate && !carbonRepeat && !appKitRepeat)
    state.release(7)
    let staleRepeat = state.shouldFire(7,time: 2,repeats: false,isRepeat: true)
    let nextPress = state.shouldFire(7,time: 3,repeats: false)
    #expect(!staleRepeat && nextPress)
    state.release(7)
    let thirdPress = state.shouldFire(7,time: 4,repeats: false)
    #expect(thirdPress)
}

@Test
func navigationShortcutsKeepTheirKeyRepeatAndDuplicateDeliveryIsIgnored() {
    var state = HotKeyDispatchState()
    let first = state.shouldFire(2,time: 1,repeats: true)
    let duplicate = state.shouldFire(2,time: 1.005,repeats: true)
    let repeatPress = state.shouldFire(2,time: 1.5,repeats: true,isRepeat: true)
    let togglePress = state.shouldFire(3,time: 1.5,repeats: false)
    #expect(first && !duplicate && repeatPress && togglePress)
    state.release(3)
    let lateDuplicate = state.shouldFire(3,time: 1.505,repeats: false)
    let secondToggle = state.shouldFire(3,time: 2,repeats: false)
    #expect(!lateDuplicate && secondToggle)
}
