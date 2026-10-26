import Testing
import AppKit
import Carbon
import CanopyCore
@testable import Canopy

@Test @MainActor
func workspaceCyclingSkipsEmptyAndUnavailableGrids() throws {
    let bridge = FakeWindows(),(store,directory) = makeStore(bridge: bridge)
    defer { store.shutdown(); try? FileManager.default.removeItem(at: directory) }
    let empty = try #require(store.current?.activeGridID)
    store.addWorkspaceGrid(); store.addWindowsToCurrentGrid(["a"])
    let first = try #require(store.current?.activeGridID)
    store.addWorkspaceGrid(); store.addWindowsToCurrentGrid(["b"])
    let second = try #require(store.current?.activeGridID)
    store.selectWorkspaceGrid(empty); store.cycleWorkspace(1)
    #expect(store.current?.activeGridID == first)
    store.cycleWorkspace(1); #expect(store.current?.activeGridID == second)
    store.cycleWorkspace(1); #expect(store.current?.activeGridID == first)
    bridge.windows["b"]?.onScreen = false
    store.cycleWorkspace(-1); #expect(store.current?.activeGridID == first)
}

@Test @MainActor
func workspaceShortcutMigrationPreservesCustomizationAndDisabledBindings() {
    var original = ShortcutBinding.defaults.filter { !$0.id.hasPrefix("workspace") }
    original[0].enabled = false
    original[1].keyCode = 48; original[1].modifiers = UInt32(optionKey | shiftKey)
    let migrated = ShortcutBinding.addingMissingDefaults(to: original)
    #expect(Array(migrated.prefix(original.count)) == original)
    #expect(migrated.first { $0.id == "workspace-previous" }?.enabled == false)
    #expect(migrated.first { $0.id == "workspace-next" }?.enabled == true)
    #expect(ShortcutBinding.addingMissingDefaults(to: migrated) == migrated)
    let defaults = ShortcutBinding.defaults.map { "\($0.keyCode):\($0.modifiers)" }
    #expect(Set(defaults).count == defaults.count)
}

@Test @MainActor
func workspaceCommandsWrapSelectDirectlyAndKeepPaneNavigationSeparate() throws {
    let bridge = FakeWindows(),(store,directory) = makeStore(bridge: bridge)
    defer { store.shutdown(); try? FileManager.default.removeItem(at: directory) }
    store.arrange(); let first = try #require(store.current?.activeGridID)
    store.addWorkspaceGrid(); store.addWindowsToCurrentGrid(["b"])
    let second = try #require(store.current?.activeGridID)
    store.performCommand("workspace-next"); #expect(store.current?.activeGridID == first)
    store.performCommand("workspace-previous"); #expect(store.current?.activeGridID == second)
    #expect(bridge.activated.last == "b")
    store.performCommand("workspace.1"); #expect(store.current?.activeGridID == first)
    store.performCommand("next"); #expect(store.current?.activeGridID == first)
    store.floatAll(); bridge.moves = []
    store.performCommand("workspace.2"); #expect(store.current?.activeGridID == second)
    #expect(bridge.moves.isEmpty); #expect(!store.isArranging)
}

@Test @MainActor
func workspaceSwitchDefersNativeWritesAndRejectsStaleOrCancelledCommits() throws {
    let bridge = FakeWindows(),(store,directory) = makeStore(bridge: bridge)
    defer { store.shutdown(); try? FileManager.default.removeItem(at: directory) }
    store.arrange(); let first = try #require(store.current?.activeGridID)
    store.addWorkspaceGrid(); store.addWindowsToCurrentGrid(["b"])
    let second = try #require(store.current?.activeGridID)
    var commits: [() -> Void] = []
    store.onWorkspaceSwitch = { commits.append($0) }
    bridge.moves = []
    store.selectWorkspaceGrid(first); store.refresh()
    #expect(store.workspaceSwitchPending); #expect(bridge.moves.isEmpty)
    store.selectWorkspaceGrid(second)
    commits[0](); #expect(store.workspaceSwitchPending); #expect(bridge.moves.isEmpty)
    commits[1](); #expect(!store.workspaceSwitchPending); #expect(bridge.moves.isEmpty)
    store.selectWorkspaceGrid(first); store.floatAll(); bridge.moves = []
    commits[2](); #expect(!store.workspaceSwitchPending); #expect(bridge.moves.isEmpty)
}

@Test @MainActor
func workspaceShortcutMatchingRequiresEveryModifierAndIgnoresCapsLock() throws {
    let binding = try #require(ShortcutBinding.defaults.first { $0.id == "workspace-next" })
    #expect(binding.matches(keyCode: 48,flags: [.option]))
    #expect(binding.matches(keyCode: 48,flags: [.option,.capsLock]))
    #expect(!binding.matches(keyCode: 48,flags: [.control,.option]))
    #expect(!binding.matches(keyCode: 48,flags: [.option,.shift]))
    #expect(!binding.matches(keyCode: 49,flags: [.option]))
}

@Test @MainActor
func oldWorkspaceCycleDefaultsMigrateWithoutOverwritingCustomOrDisabledShortcuts() throws {
    var old = ShortcutBinding.defaults
    let next = try #require(old.firstIndex { $0.id == "workspace-next" })
    let previous = try #require(old.firstIndex { $0.id == "workspace-previous" })
    old[next] = ShortcutBinding(id: "workspace-next",keyCode: 124,modifiers: UInt32(controlKey | optionKey | cmdKey),key: "→")
    old[previous].enabled = false
    let updated = ShortcutBinding.addingMissingDefaults(to: old)
    #expect(updated[next].keyCode == 48 && updated[next].modifiers == UInt32(optionKey))
    #expect(updated[previous] == old[previous])
    old[next].keyCode = 7
    #expect(ShortcutBinding.addingMissingDefaults(to: old)[next] == old[next])
}

@Test @MainActor
func returningToIndependentWorkspaceOnlyRestacksLiveWindows() throws {
    let bridge = FakeWindows(),(store,directory) = makeStore(bridge: bridge)
    defer { store.shutdown(); try? FileManager.default.removeItem(at: directory) }
    store.addWorkspaceGrid(); store.addWindowsToCurrentGrid(["a"])
    let first = try #require(store.current?.activeGridID)
    store.applyCurrentGrid()
    store.addWorkspaceGrid(); store.addWindowsToCurrentGrid(["b","c"])
    let second = try #require(store.current?.activeGridID)
    let frames = bridge.frames
    bridge.moves = []; bridge.minimizeRequests = []
    for _ in 0..<20 {
        store.selectWorkspaceGrid(first,activate: true)
        #expect(store.occludedWindows == ["b","c"])
        store.selectWorkspaceGrid(second,activate: true)
        #expect(store.occludedWindows == ["a"])
    }
    #expect(bridge.moves.isEmpty)
    #expect(bridge.minimizeRequests.isEmpty)
    #expect(bridge.frames == frames)
    #expect(bridge.windows.values.allSatisfy { !$0.minimized })
    store.floatAll()
    #expect(store.occludedWindows.isEmpty)
    #expect(!store.hasWindowsToRestore)
}

@Test @MainActor
func changedWorkspaceGeometryIsAppliedOnceAndNotReplayedOnReturn() throws {
    let bridge = FakeWindows(),(store,directory) = makeStore(bridge: bridge)
    defer { store.shutdown(); try? FileManager.default.removeItem(at: directory) }
    store.addWorkspaceGrid(); store.addWindowsToCurrentGrid(["a"]); store.applyCurrentGrid()
    let first = try #require(store.current?.activeGridID)
    store.addWorkspaceGrid(); store.addWindowsToCurrentGrid(["b"])
    let second = try #require(store.current?.activeGridID)
    store.selectWorkspaceGrid(first)
    // A manually moved app must be corrected even on a previously visited grid.
    bridge.frames["a"]?.x += 50
    bridge.moves = []
    store.selectWorkspaceGrid(second); store.selectWorkspaceGrid(first)
    #expect(bridge.moves.map(\.0) == ["a"])
    bridge.moves = []
    store.selectWorkspaceGrid(second); store.selectWorkspaceGrid(first)
    #expect(bridge.moves.isEmpty)
}

@Test @MainActor
func workspaceActivationPrecedesRaisingCompanionWindows() throws {
    let bridge = FakeWindows(),(store,directory) = makeStore(bridge: bridge)
    defer { store.shutdown(); try? FileManager.default.removeItem(at: directory) }
    store.addWorkspaceGrid(); store.addWindowsToCurrentGrid(["a"]); store.applyCurrentGrid()
    store.addWorkspaceGrid(); store.addWindowsToCurrentGrid(["b","c"])
    let destination = try #require(store.current?.activeGridID)
    store.performCommand("workspace-previous")
    bridge.operations = []
    store.selectWorkspaceGrid(destination,activate: true)
    let activation = try #require(bridge.operations.firstIndex(of: "raise:b:true"))
    let companion = try #require(bridge.operations.firstIndex(of: "raise:c:false"))
    #expect(activation < companion)
    #expect(bridge.operations.last == "raise:b:false")
}

@Test @MainActor
func workspaceBackgroundConsumesEmptyAreaClicksWithoutTakingKeyboardFocus() {
    let view = WorkspaceBackgroundView(display: fixtureDisplays[0])
    view.frame = NSRect(x: 0,y: 0,width: 200,height: 160)
    #expect(view.hitTest(NSPoint(x: 100,y: 80)) === view)
    #expect(!view.acceptsFirstResponder)
    #expect(view.isOpaque)
}
