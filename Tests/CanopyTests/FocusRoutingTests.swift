import Testing
import AppKit
import CanopyCore
@testable import Canopy

@Test @MainActor
func delayedDiscoveryDoesNotReturnToTheOutgoingGridAfterSelectingAnEmptyGrid() throws {
    let bridge = FakeWindows(),(store,directory) = makeStore(bridge: bridge)
    defer { store.shutdown(); try? FileManager.default.removeItem(at: directory) }
    store.addWindowsToCurrentGrid(["a"]); bridge.focused = "a"; store.applyCurrentGrid()
    let first = store.current?.activeGridID
    store.addWorkspaceGrid(); let empty = store.current?.activeGridID
    store.refresh()
    #expect(store.current?.activeGridID == empty)
    // A real activation notification remains able to select that same app.
    #expect(store.routeFocusedWindowToWorkspace())
    #expect(store.current?.activeGridID == first)
}

@Test @MainActor
func changingAWindowTitleDoesNotRestackTheDesktop() throws {
    let bridge = FakeWindows(),(store,directory) = makeStore(bridge: bridge)
    defer { store.shutdown(); try? FileManager.default.removeItem(at: directory) }
    store.addWindowsToCurrentGrid(["a","b"]); store.applyCurrentGrid(); store.refresh()
    var layoutApplications = 0
    store.onLayoutWillApply = { _ in layoutApplications += 1 }
    bridge.moves = []; bridge.raised = []; bridge.discoveredTitles["a"] = "Changed document title"
    store.refresh()
    #expect(store.record("a")?.title == "Changed document title")
    #expect(layoutApplications == 0 && bridge.moves.isEmpty && bridge.raised.isEmpty)
}

@Test @MainActor
func activatingAnInactiveGridWindowSelectsItsGridWithoutMovingMembership() throws {
    let bridge = FakeWindows(),(store,directory) = makeStore(bridge: bridge)
    defer { store.shutdown(); try? FileManager.default.removeItem(at: directory) }
    store.addWindowsToCurrentGrid(["a"]); store.applyCurrentGrid()
    let first = try #require(store.current?.activeGridID)
    store.addWorkspaceGrid(); store.addWindowsToCurrentGrid(["b"])
    let second = try #require(store.current?.activeGridID)
    bridge.focused = "a"
    #expect(store.routeFocusedWindowToWorkspace())
    #expect(store.current?.activeGridID == first)
    #expect(store.current?.root?.allWindows == ["a"])
    #expect(store.current?.grids.first { $0.id == second }?.root?.allWindows == ["b"])
    #expect(bridge.activated.last == "a")
    let moves = bridge.moves.count
    #expect(!store.routeFocusedWindowToWorkspace())
    #expect(bridge.moves.count == moves)
}

@Test @MainActor
func sharedWindowsStayInTheCurrentGridAndUnassignedAppsStayFloating() throws {
    let bridge = FakeWindows(),(store,directory) = makeStore(bridge: bridge)
    defer { store.shutdown(); try? FileManager.default.removeItem(at: directory) }
    store.addWindowsToCurrentGrid(["a"]); store.applyCurrentGrid()
    store.addWorkspaceGrid(); store.addWindowsToCurrentGrid(["a","b"])
    let selected = store.current?.activeGridID
    bridge.focused = "a"; _ = store.routeFocusedWindowToWorkspace()
    #expect(store.current?.activeGridID == selected)
    bridge.focused = "c"
    #expect(!store.routeFocusedWindowToWorkspace())
    #expect(store.current?.activeGridID == selected)
    #expect(!store.currentGridWindowIDs.contains("c"))
}

@Test @MainActor
func focusRoutingRespectsPausedStateAndMacOSDesktopBoundaries() throws {
    let bridge = FakeWindows(),(store,directory) = makeStore(bridge: bridge)
    defer { store.shutdown(); try? FileManager.default.removeItem(at: directory) }
    store.addWindowsToCurrentGrid(["a"]); store.applyCurrentGrid()
    store.addWorkspaceGrid(); store.addWindowsToCurrentGrid(["b"])
    let selected = store.current?.activeGridID
    bridge.focused = "a"; bridge.windows["a"]?.onScreen = false
    #expect(!store.routeFocusedWindowToWorkspace())
    #expect(store.current?.activeGridID == selected)
    bridge.windows["a"]?.onScreen = true; store.floatAll(); bridge.moves = []
    #expect(!store.routeFocusedWindowToWorkspace())
    #expect(store.current?.activeGridID == selected && bridge.moves.isEmpty)
}

@Test @MainActor
func externalActivationRevealsTheSelectedTabWithinItsExistingGrid() throws {
    let bridge = FakeWindows(),(store,directory) = makeStore(bridge: bridge)
    defer { store.shutdown(); try? FileManager.default.removeItem(at: directory) }
    store.addWindowsToCurrentGrid(["a","b"]); store.applyCurrentGrid()
    let target = try #require(store.current?.root?.leaf(containing: "a")?.id)
    store.dock("b",target: target,edge: .tab)
    let grid = store.current?.activeGridID
    bridge.focused = "a"
    #expect(store.routeFocusedWindowToWorkspace())
    #expect(store.current?.activeGridID == grid)
    #expect(store.current?.root?.leaf(containing: "a")?.activeWindow == "a")
    #expect(!store.occludedWindows.contains("a"))
}
