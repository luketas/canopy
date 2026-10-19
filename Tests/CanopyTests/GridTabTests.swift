import Testing
import AppKit
import CanopyCore
@testable import Canopy

@Test @MainActor
func workspaceGridsRetainIndependentTreesAndNavigationThroughRelaunch() throws {
    let bridge = FakeWindows(),(store,directory) = makeStore(bridge: bridge)
    defer { store.shutdown(); try? FileManager.default.removeItem(at: directory) }
    store.arrange(); let first = try #require(store.current?.activeGridID),original = try #require(store.current?.root)
    store.saveView(1); store.addWorkspaceGrid(duplicating: true)
    let second = try #require(store.current?.activeGridID)
    let target = try #require(store.current?.root?.leaf(containing: "a")?.id)
    store.dock("b",target: target,edge: .tab); let different = store.current?.root
    #expect(different != original)
    store.focus(target); store.saveView(2)
    store.selectWorkspaceGrid(first)
    #expect(store.current?.root == original)
    #expect(store.current?.savedViews["2"] == nil)
    #expect(store.current?.savedViews["1"] != nil)
    store.selectWorkspaceGrid(second)
    #expect(store.current?.root == different)
    #expect(store.current?.focus == target)
    store.renameWorkspaceGrid(second,name: "Research")
    try WorkspaceStore.validate(store.snapshot)
    store.persist(); store.floatAll()
    let loaded = WorkspaceStore(bridge: bridge,storageURL: store.persistenceURL,screens: { fixtureDisplays })
    defer { loaded.shutdown() }
    #expect(loaded.current?.grids.count == 2)
    #expect(loaded.current?.activeGridID == second)
    #expect(loaded.current?.root == different)
    #expect(loaded.current?.grids.last?.name == "Research")
}

@Test @MainActor
func gridCloseRestoresOnlyExclusiveWindowsAndUndoRestoresTheTab() throws {
    let bridge = FakeWindows(),(store,directory) = makeStore(bridge: bridge)
    defer { store.shutdown(); try? FileManager.default.removeItem(at: directory) }
    store.arrange(); let first = try #require(store.current?.activeGridID)
    store.addWorkspaceGrid(duplicating: true); let second = try #require(store.current?.activeGridID)
    store.floatWindow("b"); store.floatWindow("c")
    #expect(store.movedWindows.contains("b")) // The first grid still owns it.
    store.closeWorkspaceGrid(first)
    #expect(store.current?.activeGridID == second)
    #expect(!store.movedWindows.contains("b"))
    #expect(!store.occludedWindows.contains("b"))
    store.undo(); #expect(store.current?.grids.count == 2)
    #expect(store.current?.grids.first?.root?.allWindows.contains("b") == true)
    store.closeWorkspaceGrid(second); store.closeWorkspaceGrid(first)
    #expect(store.current?.grids.count == 1)
}

@Test @MainActor
func closedWindowsDisappearFromInactiveGridTabsToo() throws {
    let bridge = FakeWindows(),(store,directory) = makeStore(bridge: bridge)
    defer { store.shutdown(); try? FileManager.default.removeItem(at: directory) }
    store.arrange(); store.addWorkspaceGrid(duplicating: true)
    bridge.windows.removeValue(forKey: "b"); bridge.destroyedWindowIDs.insert("b"); store.refresh()
    #expect(store.current?.grids.allSatisfy { $0.root?.allWindows.contains("b") != true } == true)
    store.floatAll(); #expect(!store.hasWindowsToRestore)
}

@Test @MainActor
func legacyDisplayWorkspaceMigratesToOneGridWithoutLosingItsTree() throws {
    let data = Data(#"{"id":"old","name":"Display","root":{"id":"leaf","windows":["a"],"activeWindow":"a","children":[],"axis":"horizontal","ratio":0.5},"focus":"leaf","savedViews":{"1":"leaf"},"history":{"entries":["leaf"],"index":0}}"#.utf8)
    let display = try JSONDecoder().decode(DisplayWorkspace.self,from: data)
    #expect(display.grids.count == 1)
    #expect(display.root?.allWindows == ["a"])
    #expect(display.focus == "leaf")
    #expect(display.savedViews["1"] == "leaf")
    #expect(display.history.current == "leaf")
}

@Test @MainActor
func tabChangesNeverCreateDisplayTransitionsEvenWithPreviews() throws {
    let bridge = FakeWindows(),(store,directory) = makeStore(bridge: bridge)
    defer { store.shutdown(); try? FileManager.default.removeItem(at: directory) }
    store.arrange(); let target = try #require(store.current?.root?.leaf(containing: "a")?.id)
    store.dock("b",target: target,edge: .tab)
    let old = try #require(store.desktopPlans().first)
    store.selectTab("a"); let new = try #require(store.desktopPlans().first)
    let image = NSImage(size: NSSize(width: 20,height: 20))
    #expect(!DesktopTransitionView.shouldAnimate(old: old,new: new,images: ["a":image,"b":image]))
    #expect(!DesktopTransitionView.shouldAnimate(old: old,new: new,images: [:]))
    let view = DesktopTransitionView(old: old,new: new,store: store,duration: 0.1)
    view.frame = NSRect(x: 0,y: 0,width: 100,height: 80)
    let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil,pixelsWide: 100,pixelsHigh: 80,bitsPerSample: 8,samplesPerPixel: 4,hasAlpha: true,isPlanar: false,colorSpaceName: .deviceRGB,bytesPerRow: 400,bitsPerPixel: 32))
    let bytes = try #require(bitmap.bitmapData); bytes.initialize(repeating: 0,count: 32000)
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    view.draw(view.bounds); NSGraphicsContext.restoreGraphicsState()
    #expect(stride(from: 3,to: 32000,by: 4).allSatisfy { bytes[$0] == 0 })
}

@Test @MainActor
func interruptedAnimationTimersStopAndTheNextTransitionCompletes() async throws {
    let bridge = FakeWindows(),(store,directory) = makeStore(bridge: bridge)
    defer { store.shutdown(); try? FileManager.default.removeItem(at: directory) }
    store.arrange(); let plan = try #require(store.desktopPlans().first)
    let view = DesktopTransitionView(old: plan,new: plan,store: store,duration: 0.03)
    var completions = 0
    for _ in 0..<25 { view.start { completions += 1 }; view.stop() }
    #expect(!view.isRunning)
    view.start { completions += 1 }
    let deadline = Date().addingTimeInterval(2)
    while view.isRunning,Date() < deadline { try await Task.sleep(nanoseconds: 20_000_000) }
    #expect(completions == 1); #expect(!view.isRunning)
}

@Test @MainActor
func tabReplacementIsRaisedWithoutMinimizingEitherTab() throws {
    let bridge = FakeWindows(),(store,directory) = makeStore(bridge: bridge)
    defer { store.shutdown(); try? FileManager.default.removeItem(at: directory) }
    store.arrange(); let target = try #require(store.current?.root?.leaf(containing: "a")?.id)
    store.dock("b",target: target,edge: .tab)
    bridge.operations = []; store.selectTab("a")
    #expect(bridge.operations.contains("raise:a:false"))
    #expect(bridge.minimizeRequests.isEmpty)
    #expect(store.occludedWindows.contains("b"))
}

@Test @MainActor
func editorTabsKeepEditorFocusWhileDesktopTabsActivateWithoutMinimizing() throws {
    let bridge = FakeWindows(),(store,directory) = makeStore(bridge: bridge)
    defer { store.shutdown(); try? FileManager.default.removeItem(at: directory) }
    store.arrange(); let target = try #require(store.current?.root?.leaf(containing: "a")?.id)
    store.dock("b",target: target,edge: .tab)
    bridge.operations = []; bridge.activated = []
    store.selectTab("a"); #expect(bridge.activated.isEmpty)
    bridge.operations = []; store.selectTab("b",activate: true)
    #expect(bridge.activated == ["b"])
    #expect(bridge.operations.contains("raise:b:true"))
    #expect(bridge.minimizeRequests.isEmpty)
    #expect(store.occludedWindows.contains("a"))
}
