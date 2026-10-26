import Testing
import AppKit
import CanopyCore
@testable import Canopy

@MainActor
private func activationStore() throws -> (WorkspaceStore,FakeWindows,URL,String,String) {
    let bridge = FakeWindows(),(store,directory) = makeStore(bridge: bridge)
    store.addWindowsToCurrentGrid(["a"]); store.applyCurrentGrid()
    let owner = try #require(store.current?.activeGridID)
    store.addWorkspaceGrid(); store.addWindowsToCurrentGrid(["b"])
    let current = try #require(store.current?.activeGridID)
    bridge.focused = "b"; bridge.frontmostProcessID = bridge.windows["b"]?.pid
    return (store,bridge,directory,owner,current)
}

@MainActor
private func waitForGrid(_ id: String,store: WorkspaceStore) async throws {
    let deadline = Date().addingTimeInterval(5)
    while store.current?.activeGridID != id,Date() < deadline {
        try await Task.sleep(nanoseconds: 20_000_000)
    }
    #expect(store.current?.activeGridID == id)
}

@Test @MainActor
func applicationActivationWaitsForFrontmostPidAndFocusedWindowToSettle() async throws {
    let (store,bridge,directory,owner,current) = try activationStore()
    defer { store.shutdown(); try? FileManager.default.removeItem(at: directory) }
    let pid = try #require(bridge.windows["a"]?.pid)
    // Workspace activation arrives while both frontmost app and focus still
    // describe the outgoing app. This must not resolve against that app.
    store.handleNativeActivation(processID: pid)
    #expect(store.current?.activeGridID == current)
    bridge.frontmostProcessID = pid; bridge.focused = nil
    try await Task.sleep(nanoseconds: 100_000_000)
    #expect(store.current?.activeGridID == current)
    bridge.focused = "a"
    try await waitForGrid(owner,store: store)
    #expect(store.currentGridWindowIDs == ["a"])
    #expect(store.current?.grids.first { $0.id == current }?.root?.allWindows == ["b"])
}

@Test @MainActor
func anAlreadyActiveAppDockClickIsRecheckedWhenItsFocusChangesLate() async throws {
    let (store,bridge,directory,owner,current) = try activationStore()
    defer { store.shutdown(); try? FileManager.default.removeItem(at: directory) }
    let pid = try #require(bridge.windows["a"]?.pid)
    bridge.windows["b"]?.pid = pid; bridge.frontmostProcessID = pid
    // Both windows belong to the same application. Its first response still
    // names the visible window, and no second application activation is sent.
    bridge.focused = "b"; store.handleNativeActivation(processID: pid)
    #expect(store.current?.activeGridID == current)
    try await Task.sleep(nanoseconds: 100_000_000)
    bridge.focused = "a"
    try await waitForGrid(owner,store: store)
}

@Test @MainActor
func missingFocusAttributesUseOnlyAnUnambiguousFreshlyDiscoveredAppWindow() async throws {
    let (store,bridge,directory,owner,_) = try activationStore()
    defer { store.shutdown(); try? FileManager.default.removeItem(at: directory) }
    bridge.focused = nil; bridge.frontmostProcessID = bridge.windows["a"]?.pid
    store.handleNativeActivation(processID: bridge.frontmostProcessID)
    try await waitForGrid(owner,store: store)
    #expect(bridge.activated.last == "a")
}

@Test @MainActor
func ambiguousAppWindowsWithoutFocusedAttributesDoNotChooseAnArbitraryGrid() async throws {
    let (store,bridge,directory,_,current) = try activationStore()
    defer { store.shutdown(); try? FileManager.default.removeItem(at: directory) }
    let pid = try #require(bridge.windows["a"]?.pid)
    bridge.windows["c"]?.pid = pid; bridge.focused = nil; bridge.frontmostProcessID = pid
    store.handleNativeActivation(processID: pid)
    try await Task.sleep(nanoseconds: 1_600_000_000)
    #expect(store.current?.activeGridID == current)
}

@Test @MainActor
func delayedVisibilityAfterUnminimizingDoesNotLoseTheActivation() async throws {
    let (store,bridge,directory,owner,current) = try activationStore()
    defer { store.shutdown(); try? FileManager.default.removeItem(at: directory) }
    bridge.frontmostProcessID = bridge.windows["a"]?.pid; bridge.focused = "a"
    bridge.windows["a"]?.minimized = true; bridge.windows["a"]?.onScreen = false
    store.handleNativeActivation(processID: bridge.frontmostProcessID)
    #expect(store.current?.activeGridID == current)
    bridge.windows["a"]?.minimized = false; bridge.windows["a"]?.onScreen = true
    try await waitForGrid(owner,store: store)
}

@Test @MainActor
func aManualGridSelectionCancelsTheOutstandingActivationRequest() async throws {
    let (store,bridge,directory,_,current) = try activationStore()
    defer { store.shutdown(); try? FileManager.default.removeItem(at: directory) }
    bridge.frontmostProcessID = bridge.windows["a"]?.pid; bridge.focused = nil
    store.handleNativeActivation(processID: bridge.frontmostProcessID)
    store.addWorkspaceGrid()
    let chosen = try #require(store.current?.activeGridID)
    #expect(chosen != current)
    bridge.focused = "a"
    try await Task.sleep(nanoseconds: 1_600_000_000)
    #expect(store.current?.activeGridID == chosen)
}

@Test @MainActor
func backgroundAxNotificationsCannotOverrideTheFrontmostAppsPendingActivation() async throws {
    let (store,bridge,directory,owner,_) = try activationStore()
    defer { store.shutdown(); try? FileManager.default.removeItem(at: directory) }
    bridge.frontmostProcessID = bridge.windows["a"]?.pid; bridge.focused = nil
    store.handleNativeActivation(processID: bridge.frontmostProcessID)
    let background = try #require(bridge.windows["b"])
    store.handleNativeActivation(processID: background.pid,element: background.element)
    bridge.focused = "a"
    try await waitForGrid(owner,store: store)
}

@Test @MainActor
func revealingAWindowOutsideAnOwnersZoomRestoresItsWholeGrid() throws {
    let bridge = FakeWindows(),(store,directory) = makeStore(bridge: bridge)
    defer { store.shutdown(); try? FileManager.default.removeItem(at: directory) }
    store.addWindowsToCurrentGrid(["a","b"]); store.applyCurrentGrid()
    let owner = try #require(store.current?.activeGridID)
    store.focus(try #require(store.current?.root?.leaf(containing: "a")?.id))
    store.addWorkspaceGrid(); store.addWindowsToCurrentGrid(["c"])
    bridge.focused = "b"; bridge.frontmostProcessID = bridge.windows["b"]?.pid
    store.handleNativeActivation(processID: bridge.frontmostProcessID)
    #expect(store.current?.activeGridID == owner)
    #expect(store.current?.focus == store.current?.root?.id)
    #expect(Set(store.desktopPlans().flatMap(\.nativePlacements).map(\.window)) == ["a","b"])
}

@Test @MainActor
func focusIdentityUsesStableNativeIdAndProcessInsteadOfAxReferenceIdentity() throws {
    let bridge = FakeWindows()
    bridge.windows["a"]?.windowNumber = 1234
    bridge.windows["b"]?.windowNumber = 1234 // Same number in the wrong process cannot win.
    let windows = Array(bridge.windows.values)
    let pid = try #require(bridge.windows["a"]?.pid)
    #expect(WindowBridge.resolveFocusIdentity(processID: pid,number: 1234,frame: nil,windows: windows,frames: [:]) == "a")
    #expect(WindowBridge.resolveFocusIdentity(processID: pid,number: 9999,frame: bridge.frames["a"],windows: windows,frames: bridge.frames) == nil)
    #expect(WindowBridge.resolveFocusIdentity(processID: pid,number: nil,frame: bridge.frames["a"],windows: windows,frames: bridge.frames) == "a")
    bridge.windows["b"]?.pid = pid; bridge.frames["b"] = bridge.frames["a"]
    #expect(WindowBridge.resolveFocusIdentity(processID: pid,number: nil,frame: bridge.frames["a"],windows: Array(bridge.windows.values),frames: bridge.frames) == nil)
}

@Test @MainActor
func aNewerAppActivationSupersedesAnUnresolvedOlderRequest() async throws {
    let (store,bridge,directory,_,current) = try activationStore()
    defer { store.shutdown(); try? FileManager.default.removeItem(at: directory) }
    let firstPid = try #require(bridge.windows["a"]?.pid)
    bridge.frontmostProcessID = firstPid; bridge.focused = nil
    store.handleNativeActivation(processID: firstPid)
    let latestPid = try #require(bridge.windows["b"]?.pid)
    bridge.frontmostProcessID = latestPid
    store.handleNativeActivation(processID: latestPid)
    bridge.focused = "b"
    try await Task.sleep(nanoseconds: 1_600_000_000)
    #expect(store.current?.activeGridID == current)
    #expect(!bridge.activated.contains("a"))
}
