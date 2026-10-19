import Testing
import AppKit
import CanopyCore
@testable import Canopy

@Test @MainActor
func liveResizeCoalescesWritesAndNeverRaisesOrMinimizesApps() async throws {
    let bridge = FakeWindows(),(store,directory) = makeStore(bridge: bridge)
    defer { store.shutdown(); try? FileManager.default.removeItem(at: directory) }
    store.arrange()
    let root = try #require(store.current?.root)
    let saved = try Data(contentsOf: store.persistenceURL)
    var phases: [Bool] = []
    store.onLayoutWillApply = { _ in phases.append(store.applyingGeometryOnly) }
    store.onLayoutDidApply = { _ in phases.append(store.applyingGeometryOnly) }
    bridge.moves = []; bridge.raised = []; bridge.minimizeRequests = []
    store.beginResize()
    for step in 0..<100 { store.resize(root.id,ratio: 0.35+Double(step)*0.001,finished: false) }
    #expect(bridge.moves.isEmpty)
    #expect(try Data(contentsOf: store.persistenceURL) == saved)
    let deadline = Date().addingTimeInterval(5)
    while phases.isEmpty,Date() < deadline { try await Task.sleep(nanoseconds: 10_000_000) }
    #expect(bridge.moves.count <= 3)
    #expect(!phases.isEmpty && phases.allSatisfy { $0 })
    store.resize(root.id,ratio: 0.45,finished: true)
    #expect(!store.isResizing && !store.interactiveDrag)
    #expect(phases.allSatisfy { $0 })
    #expect(bridge.raised.isEmpty)
    #expect(bridge.minimizeRequests.isEmpty)
    #expect(try Data(contentsOf: store.persistenceURL) != saved)
    store.undo()
    #expect(store.current?.root == root)
}

@Test @MainActor
func finalResizeFlushesLatestRatioAndPauseCancelsQueuedGeometry() async throws {
    let bridge = FakeWindows(),(store,directory) = makeStore(bridge: bridge)
    defer { store.shutdown(); try? FileManager.default.removeItem(at: directory) }
    store.arrange(); let root = try #require(store.current?.root)
    store.beginResize(); store.resize(root.id,ratio: 0.4,finished: false)
    store.resize(root.id,ratio: 0.6,finished: true)
    #expect(store.current?.root?.ratio == 0.6)
    let expected = store.desktopPlans().flatMap(\.nativePlacements)
    #expect(expected.allSatisfy { bridge.frames[$0.window] == $0.rect })
    store.beginResize(); store.resize(root.id,ratio: 0.3,finished: false)
    store.floatAll(); let restored = bridge.frames; bridge.moves = []
    try await Task.sleep(nanoseconds: 60_000_000)
    #expect(bridge.moves.isEmpty && bridge.frames == restored)
    #expect(!store.isResizing)
}

@Test @MainActor
func floatingWindowFillsAnEmptyColumnAndKeepsOtherSlots() throws {
    let bridge = FakeWindows(),(store,directory) = makeStore(bridge: bridge)
    defer { store.shutdown(); try? FileManager.default.removeItem(at: directory) }
    store.addWorkspaceGrid(); store.addWindowsToCurrentGrid(["a"]); store.setGridColumnCount(3)
    let plan = try #require(store.desktopPlans().first)
    let empty = try #require(plan.root.layoutColumns.first { $0.isSpacer })
    let frame = try #require(plan.frames[empty.id])
    let intent = try #require(DockResolver.resolve(x: frame.midX,y: frame.midY,display: plan.display.id,
        screen: store.desktopViewport(plan.display),root: plan.root,frames: plan.frames,excluding: ["b"]))
    #expect(intent.edge == .tab && intent.preview == frame)
    store.dock(["b"],intent: intent)
    #expect(store.currentGridWindowIDs == ["a","b"])
    #expect(store.current?.root?.layoutColumns.count == 3)
    #expect(store.current?.root?.layoutColumns.filter(\.isSpacer).count == 1)
}

@Test @MainActor
func floatingWindowCanStartAnEmptyGridUsingItsEphemeralDropTarget() throws {
    let bridge = FakeWindows(),(store,directory) = makeStore(bridge: bridge)
    defer { store.shutdown(); try? FileManager.default.removeItem(at: directory) }
    store.addWorkspaceGrid()
    let plan = try #require(store.desktopPlans().first)
    let frame = store.desktopViewport(plan.display)
    let intent = try #require(DockResolver.resolve(x: frame.midX,y: frame.midY,display: plan.display.id,
        screen: frame,root: plan.root,frames: plan.frames,excluding: ["b"]))
    store.dock(["b"],intent: intent)
    #expect(store.current?.root?.allWindows == ["b"])
    #expect(store.current?.root?.allWindows.contains(where: WorkspaceStore.isDesktop) == false)
}

@Test @MainActor
func dockingAWindowFromAnotherGridPreservesItsOtherArrangement() throws {
    let bridge = FakeWindows(),(store,directory) = makeStore(bridge: bridge)
    defer { store.shutdown(); try? FileManager.default.removeItem(at: directory) }
    store.addWindowsToCurrentGrid(["a","b"])
    let originalGrid = try #require(store.current?.activeGridID)
    let originalTree = try #require(store.current?.root)
    store.addWorkspaceGrid(); store.addWindowsToCurrentGrid(["a"])
    store.occludedWindows.insert("b")
    let plan = try #require(store.desktopPlans().first)
    store.dock(["b"],intent: DockIntent(display: plan.display.id,target: plan.root.id,edge: .tab,preview: plan.world))
    #expect(store.currentGridWindowIDs == ["a","b"])
    #expect(store.current?.grids.first { $0.id == originalGrid }?.root == originalTree)
    store.undo()
    #expect(store.currentGridWindowIDs == ["a"])
    #expect(store.current?.grids.first { $0.id == originalGrid }?.root == originalTree)
}

@Test @MainActor
func gapDropsSplitTheNearestSlotAndScreenEdgesWrapTheVisibleGrid() throws {
    let bridge = FakeWindows(),(store,directory) = makeStore(bridge: bridge)
    defer { store.shutdown(); try? FileManager.default.removeItem(at: directory) }
    store.addWorkspaceGrid(); store.addWindowsToCurrentGrid(["a","b"]); store.setGridColumnCount(2)
    let plan = try #require(store.desktopPlans().first)
    let seam = try #require(plan.seams.first)
    let target = try #require(DockResolver.resolve(x: seam.rect.midX,y: seam.rect.midY,display: plan.display.id,
        screen: store.desktopViewport(plan.display),root: plan.root,frames: plan.frames,excluding: ["c"]))
    #expect(target.edge == .left || target.edge == .right)
    store.dock(["c"],intent: target)
    #expect(store.currentGridWindowIDs == ["a","b","c"])
    #expect(store.current?.root?.nodeCount == 5)
    store.undo()
    let restored = try #require(store.desktopPlans().first)
    let viewport = store.desktopViewport(restored.display)
    let screenDrop = try #require(DockResolver.resolve(x: viewport.midX,y: viewport.y+1,display: restored.display.id,
        screen: viewport,root: restored.root,frames: restored.frames,excluding: ["c"]))
    #expect(screenDrop.target == restored.root.id && screenDrop.edge == .top)
    store.dock(["c"],intent: screenDrop)
    #expect(store.current?.root?.axis == .vertical)
    #expect(store.current?.root?.children.last?.allWindows == restored.root.allWindows)
    #expect(store.current?.root?.children.first?.allWindows == ["c"])
}
