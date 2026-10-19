import Testing
import AppKit
import CanopyCore
@testable import Canopy

@Test @MainActor
func explicitColumnsKeepEmptyDropTargetsWithoutPhantomWindows() throws {
    let root = try #require(WorkspaceStore.columnPreset([LayoutNode(window: "a"),LayoutNode(window: "b")],count: 4))
    #expect(root.layoutColumns.count == 4)
    #expect(root.allWindows.sorted() == ["a","b"])
    #expect(root.layoutColumns.filter(\.isSpacer).count == 2)
    #expect(root.frames(in: LayoutRect(width: 1600,height: 900)).count == root.nodeCount)
    var copy = try JSONDecoder().decode(LayoutNode.self,from: JSONEncoder().encode(root))
    let empty = try #require(copy.layoutColumns.first { $0.isSpacer })
    let docked = copy.dock(window: "c",at: empty.id,edge: .tab)
    #expect(docked)
    #expect(copy.layoutColumns.count == 4)
    #expect(copy.allWindows.sorted() == ["a","b","c"])
    copy = try #require(copy.removing(window: "c"))
    #expect(copy.layoutColumns.count == 4)
    #expect(copy.layoutColumns.filter(\.isSpacer).count == 2)
}

@Test @MainActor
func columnsSupportStackingOwnColumnUndoAndAddingIntoEmptySlots() throws {
    let bridge = FakeWindows(),(store,directory) = makeStore(bridge: bridge)
    defer { store.shutdown(); try? FileManager.default.removeItem(at: directory) }
    store.addWindowsToCurrentGrid(["a","b"]); store.setGridColumnCount(3)
    #expect(store.gridColumns.count == 3)
    store.addWindowsToCurrentGrid(["c"])
    #expect(store.gridColumns.count == 3); #expect(store.gridColumns.allSatisfy { $0.allWindows.count == 1 })
    let first = try #require(store.gridColumns.first?.columnID)
    store.stackWindow("b",inColumn: first)
    #expect(store.gridColumns.count == 3)
    #expect(store.gridColumns.first?.allWindows == ["a","b"])
    #expect(store.gridColumns[1].isSpacer)
    #expect(store.giveWindowOwnColumn("b"))
    #expect(store.gridColumns.count == 4)
    #expect(store.gridColumns.contains { $0.allWindows == ["b"] })
    #expect(Set(store.gridColumns.compactMap(\.columnID)).count == 4)
    store.undo(); #expect(store.gridColumns.count == 3)
    #expect(store.gridColumns.first?.allWindows == ["a","b"])
    store.removeWindowFromCurrentGrid("a"); store.removeWindowFromCurrentGrid("b")
    #expect(store.gridColumns.count == 3)
}

@Test @MainActor
func fourColumnsAdaptToKnownNativeMinimumsWithoutLosingTheFourthColumn() throws {
    let bridge = FakeWindows(); bridge.minimums["a"] = CGSize(width: 960,height: 660)
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let store = WorkspaceStore(bridge: bridge,storageURL: directory.appendingPathComponent("workspace.json"),screens: {
        [DisplayDescriptor(id: "wide",name: "Wide",frame: LayoutRect(width: 3440,height: 1440))]
    })
    defer { store.shutdown(); try? FileManager.default.removeItem(at: directory) }
    store.addWindowsToCurrentGrid(["a","b","c"]); store.setGridColumnCount(4); store.applyCurrentGrid()
    #expect(store.gridColumns.count == 4)
    let plan = try #require(store.desktopPlans().first)
    #expect(plan.nativePlacements.first { $0.window == "a" }!.rect.width >= 960)
    #expect(plan.nativePlacements.allSatisfy { $0.rect.y >= DesktopWorkspaceBar.height+store.gap })
    #expect(Set(plan.nativePlacements.map(\.window)) == ["a","b","c"])
    #expect(plan.managedWindows == ["a","b","c"])
}

@Test @MainActor
func desktopWorkspaceBarExposesSwitchesAndNeverCoversAppFrames() throws {
    let bridge = FakeWindows(),(store,directory) = makeStore(bridge: bridge)
    defer { store.shutdown(); try? FileManager.default.removeItem(at: directory) }
    store.addWindowsToCurrentGrid(["a"]); let first = try #require(store.current?.activeGridID)
    store.addWorkspaceGrid(); store.addWindowsToCurrentGrid(["b"])
    let grids = try #require(store.current?.grids),selected = try #require(store.current?.activeGridID)
    let bar = DesktopWorkspaceBar(grids: grids,active: selected)
    bar.frame = NSRect(x: 0,y: 0,width: 1280,height: DesktopWorkspaceBar.height)
    var pressed: String?
    bar.onSelect = { pressed = $0 }
    let children = try #require(bar.accessibilityChildren())
    #expect(children.count == 3)
    let button = try #require(children[0] as? NSButton)
    button.performClick(nil)
    #expect(pressed == first)
    store.applyCurrentGrid()
    let plan = try #require(store.desktopPlans().first)
    #expect(plan.placements.allSatisfy { $0.rect.y >= DesktopWorkspaceBar.height })
}

@Test @MainActor
func movingAnEntireColumnIntoAStackThenBackKeepsUniqueDropTargets() throws {
    var root = try #require(WorkspaceStore.columnPreset([LayoutNode(window: "a"),LayoutNode(window: "b")],count: 2))
    let columnIDs = root.layoutColumns.map { $0.id }
    let stacked = root.dock(window: "b",at: columnIDs[0],edge: .bottom)
    #expect(stacked)
    func ids(_ node: LayoutNode) -> [String] { [node.id]+node.children.flatMap(ids) }
    #expect(Set(ids(root)).count == root.nodeCount)
    #expect(root.node(columnIDs[1])?.isSpacer == true)
    let unstacked = root.dock(window: "b",at: columnIDs[1],edge: .tab)
    #expect(unstacked)
    #expect(root.layoutColumns.map(\.allWindows) == [["a"],["b"]])
    #expect(Set(ids(root)).count == root.nodeCount)
    let reloaded = try JSONDecoder().decode(LayoutNode.self,from: JSONEncoder().encode(root))
    #expect(reloaded.layoutColumns.count == 2)
}

@Test @MainActor
func columnPresetsIgnoreUnavailableMembershipAndUndoRestoresIt() throws {
    let bridge = FakeWindows(),(store,directory) = makeStore(bridge: bridge)
    defer { store.shutdown(); try? FileManager.default.removeItem(at: directory) }
    store.addWindowsToCurrentGrid(["a","b","c"])
    bridge.windows["b"]?.onScreen = false
    store.setGridColumnCount(3)
    #expect(store.currentGridWindowIDs == ["a","c"])
    #expect(store.gridColumns.filter(\.isSpacer).count == 1)
    store.undo(); #expect(store.currentGridWindowIDs == ["a","b","c"])
}
