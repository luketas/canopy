import Testing
import AppKit
import CanopyCore
@testable import Canopy

@Test @MainActor
func newGridsStartEmptyAndApplyNeverEnrollsUnchosenApps() throws {
    let bridge = FakeWindows(),(store,directory) = makeStore(bridge: bridge)
    defer { store.shutdown(); try? FileManager.default.removeItem(at: directory) }
    store.addWorkspaceGrid(); #expect(store.current?.root == nil)
    store.addWindowsToCurrentGrid(["a","a","missing"])
    #expect(store.currentGridWindowIDs == ["a"])
    store.applyCurrentGrid()
    #expect(store.currentGridWindowIDs == ["a"])
    #expect(!bridge.moves.contains { $0.0 == "b" || $0.0 == "c" })
    store.addWorkspaceGrid(); store.addWindowsToCurrentGrid(["b"]); store.applyCurrentGrid()
    #expect(store.currentGridWindowIDs == ["b"])
    #expect(store.current?.grids.dropLast().last?.root?.allWindows == ["a"])
    #expect(store.occludedWindows.contains("a"))
    store.floatAll(); #expect(!store.hasWindowsToRestore)
}

@Test @MainActor
func removingFromOneGridPreservesOtherGridsAndUndoRestoresMembership() throws {
    let bridge = FakeWindows(),(store,directory) = makeStore(bridge: bridge)
    defer { store.shutdown(); try? FileManager.default.removeItem(at: directory) }
    store.addWindowsToCurrentGrid(["a","b"]); store.addWorkspaceGrid(duplicating: true)
    store.removeWindowFromCurrentGrid("a")
    #expect(store.currentGridWindowIDs == ["b"])
    #expect(store.current?.grids.first?.root?.allWindows.contains("a") == true)
    store.applyCurrentGrid(); #expect(store.currentGridWindowIDs == ["b"])
    store.removeWindowFromCurrentGrid("b"); #expect(store.currentGridWindowIDs.isEmpty)
    store.undo(); #expect(store.currentGridWindowIDs == ["b"])
}

@Test @MainActor
func removalReleasesAnUnsharedNativeWindowAtItsBaseline() throws {
    let bridge = FakeWindows(),(store,directory) = makeStore(bridge: bridge)
    defer { store.shutdown(); try? FileManager.default.removeItem(at: directory) }
    let baseline = bridge.frames["a"]
    store.addWindowsToCurrentGrid(["a"]); store.applyCurrentGrid()
    store.removeWindowFromCurrentGrid("a")
    #expect(!store.movedWindows.contains("a")); #expect(bridge.frames["a"] == baseline)
    #expect(store.currentGridWindowIDs.isEmpty)
    #expect(bridge.windows["a"]?.minimized == false)
}

@Test @MainActor
func editorDragsMoveBetweenGridTabsAndRemoveWithoutMutatingOtherGrids() throws {
    let bridge = FakeWindows(),(store,directory) = makeStore(bridge: bridge)
    defer { store.shutdown(); try? FileManager.default.removeItem(at: directory) }
    store.addWindowsToCurrentGrid(["a","b"]); let first = try #require(store.current?.activeGridID)
    store.addWorkspaceGrid(); let second = try #require(store.current?.activeGridID)
    store.selectWorkspaceGrid(first)
    store.editorTargets["tab"] = EditorDropTarget(id: "grid:\(second)",node: nil,window: 9,frame: CGRect(x: 0,y: 0,width: 120,height: 30),gridID: second)
    store.beginEditorDrag("a"); store.finishEditorDrag(CGPoint(x: 60,y: 15),window: 9)
    #expect(store.current?.activeGridID == second); #expect(store.currentGridWindowIDs == ["a"])
    #expect(store.current?.grids.first?.root?.allWindows == ["b"])
    store.editorTargets["remove"] = EditorDropTarget(id: "remove-current-grid",node: nil,window: 9,frame: CGRect(x: 0,y: 100,width: 200,height: 60),removesWindow: true)
    store.beginEditorDrag("a"); store.finishEditorDrag(CGPoint(x: 100,y: 130),window: 9)
    #expect(store.currentGridWindowIDs.isEmpty)
    #expect(store.current?.grids.first?.root?.allWindows == ["b"])
    store.undo(); #expect(store.currentGridWindowIDs == ["a"])
}

@Test @MainActor
func editorRowControlsAreNotCoveredByTheirDragSurface() {
    let parent = NSView(frame: NSRect(x: 0,y: 0,width: 220,height: 48))
    let drag = WindowDragView(frame: parent.bounds); drag.excludedTrailingWidth = 32; parent.addSubview(drag)
    #expect(drag.hitTest(NSPoint(x: 100,y: 24)) === drag)
    #expect(drag.hitTest(NSPoint(x: 208,y: 24)) == nil)
}

@Test @MainActor
func transfersBalanceTheDestinationInsteadOfSqueezingItsExistingColumns() throws {
    let bridge = FakeWindows(); bridge.preferredInitialPaneSize = CGSize(width: 1000,height: 650)
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let store = WorkspaceStore(bridge: bridge,storageURL: directory.appendingPathComponent("workspace.json"),screens: {
        [DisplayDescriptor(id: "wide",name: "Wide",frame: LayoutRect(width: 3440,height: 1410))]
    })
    defer { store.shutdown(); try? FileManager.default.removeItem(at: directory) }
    store.addWindowsToCurrentGrid(["a","b"]); let destination = try #require(store.current?.activeGridID)
    store.addWorkspaceGrid(); store.addWindowsToCurrentGrid(["c"])
    store.transferWindow("c",toGrid: destination)
    let placements = try #require(store.current?.root).placements(in: LayoutRect(width: 3424,height: 1394),gap: 8)
    #expect(placements.count == 3)
    #expect(placements.allSatisfy { $0.rect.width >= 960 && $0.rect.height >= 660 })
    #expect(store.current?.grids.last?.root == nil)
}
