import XCTest
@testable import CanopyCore

final class LayoutTests: XCTestCase {
    let screen = LayoutRect(x: 20, y: 30, width: 1200, height: 800)

    func testLeafFillsAvailableRect() {
        let leaf = LayoutNode(window: "a")
        XCTAssertEqual(leaf.placements(in: screen).first?.rect, screen)
    }
    func testHorizontalSplitHasExactGapAndPreservesBounds() {
        let root = LayoutNode(first: LayoutNode(window: "a"), second: LayoutNode(window: "b"), axis: .horizontal, ratio: 0.6)
        let placements = root.placements(in: screen, gap: 10)
        XCTAssertEqual(placements[0].rect.width, 714, accuracy: 0.001)
        XCTAssertEqual(placements[1].rect.x - placements[0].rect.x - placements[0].rect.width, 10, accuracy: 0.001)
        XCTAssertEqual(placements[1].rect.x + placements[1].rect.width, screen.x + screen.width, accuracy: 0.001)
    }
    func testVerticalSplitHasExactGap() {
        let root = LayoutNode(first: LayoutNode(window: "a"), second: LayoutNode(window: "b"), axis: .vertical)
        let p = root.placements(in: screen, gap: 8)
        XCTAssertEqual(p[0].rect.height, 396)
        XCTAssertEqual(p[1].rect.y, 434)
    }
    func testAllFourDockEdgesPlaceTheNewWindowOnThatSide() {
        for edge in [DockEdge.left, .right, .top, .bottom] {
            var root = LayoutNode(window: "a")
            XCTAssertTrue(root.dock(window: "b", at: root.id, edge: edge))
            let p = root.placements(in: screen)
            let a = p.first { $0.window == "a" }!.rect, b = p.first { $0.window == "b" }!.rect
            switch edge {
            case .left: XCTAssertLessThan(b.x, a.x)
            case .right: XCTAssertGreaterThan(b.x, a.x)
            case .top: XCTAssertLessThan(b.y, a.y)
            case .bottom: XCTAssertGreaterThan(b.y, a.y)
            case .tab: XCTFail("Not an edge")
            }
        }
    }
    func testTabGroupHasOneActiveWindowAndIdenticalFrames() {
        var root = LayoutNode(window: "a")
        XCTAssertTrue(root.dock(window: "b", at: root.id, edge: .tab))
        let p = root.placements(in: screen)
        XCTAssertEqual(p.count, 2)
        XCTAssertEqual(p.filter(\.isActive).map(\.window), ["b"])
        XCTAssertEqual(p[0].rect, p[1].rect)
        root.select(window: "a")
        XCTAssertEqual(root.placements(in: screen).filter(\.isActive).map(\.window), ["a"])
    }
    func testNestedDockingOnlyChangesItsTarget() {
        let left = LayoutNode(window: "a")
        let right = LayoutNode(window: "b")
        var root = LayoutNode(first: left, second: right, axis: .horizontal)
        XCTAssertTrue(root.dock(window: "c", at: right.id, edge: .bottom))
        XCTAssertEqual(root.children[0], left)
        XCTAssertEqual(root.children[1].axis, .vertical)
        XCTAssertEqual(root.allWindows, ["a", "b", "c"])
        XCTAssertEqual(root.path(to: right.id)?.count, 3)
    }
    func testMoveDoesNotDuplicateAWindow() {
        let a = LayoutNode(window: "a"), b = LayoutNode(window: "b")
        var root = LayoutNode(first: a, second: b, axis: .horizontal)
        XCTAssertTrue(root.dock(window: "a", at: b.id, edge: .tab))
        XCTAssertTrue(root.isLeaf)
        XCTAssertEqual(Set(root.allWindows), ["a", "b"])
        XCTAssertEqual(root.allWindows.count, 2)
    }
    func testTearTabOutIntoSplit() {
        var root = LayoutNode(window: "a")
        _ = root.dock(window: "b", at: root.id, edge: .tab)
        XCTAssertTrue(root.dock(window: "b", at: root.id, edge: .right))
        XCTAssertFalse(root.isLeaf)
        XCTAssertEqual(root.children.map(\.allWindows), [["a"], ["b"]])
    }
    func testMoveToRootEdgePreservesTheWholeSurvivingSubtree() {
        let tools = LayoutNode(first: LayoutNode(window: "b"), second: LayoutNode(window: "c"), axis: .vertical)
        var root = LayoutNode(first: LayoutNode(window: "a"), second: tools, axis: .horizontal)
        XCTAssertTrue(root.dock(window: "a", at: root.id, edge: .right))
        XCTAssertEqual(root.children[0], tools)
        XCTAssertEqual(root.children[1].windows, ["a"])
    }
    func testInvalidTargetLeavesTheEntireTreeIntact() {
        var root = LayoutNode(first: LayoutNode(window: "a"), second: LayoutNode(window: "b"), axis: .horizontal)
        let before = root
        XCTAssertFalse(root.dock(window: "a", at: "missing", edge: .right))
        XCTAssertEqual(root, before)
        XCTAssertFalse(root.dock(window: "a", at: root.id, edge: .tab))
        XCTAssertEqual(root, before)
    }
    func testDockingSingleWindowOnItselfIsNoOp() {
        var root = LayoutNode(window: "a")
        let before = root
        XCTAssertFalse(root.dock(window: "a", at: root.id, edge: .right))
        XCTAssertEqual(root, before)
    }
    func testRemovingLastWindowReturnsNil() { XCTAssertNil(LayoutNode(window: "a").removing(window: "a")) }
    func testRemovingLeafCollapsesSplitAndKeepsSurvivorIdentity() {
        let survivor = LayoutNode(window: "b")
        let root = LayoutNode(first: LayoutNode(window: "a"), second: survivor, axis: .horizontal)
        XCTAssertEqual(root.removing(window: "a"), survivor)
    }
    func testRemovingActiveTabSelectsAnotherTab() {
        var root = LayoutNode(window: "a")
        _ = root.dock(window: "b", at: root.id, edge: .tab)
        XCTAssertEqual(root.removing(window: "b")?.activeWindow, "a")
    }
    func testMinimizedBranchTemporarilyGivesSpaceToItsNeighbor() {
        let a = LayoutNode(window: "a"), b = LayoutNode(window: "b")
        let root = LayoutNode(first: a, second: b, axis: .horizontal)
        let hidden = root.placements(in: screen, unavailable: ["a"])
        XCTAssertEqual(hidden.map(\.window), ["b"])
        XCTAssertEqual(hidden[0].rect, screen)
        XCTAssertEqual(root.placements(in: screen).count, 2)
        XCTAssertEqual(root.children[0].id, a.id)
    }
    func testMinimizedActiveTabFallsBackWithoutChangingSavedSelection() {
        var root = LayoutNode(window: "a")
        _ = root.dock(window: "b", at: root.id, edge: .tab)
        XCTAssertEqual(root.placements(in: screen, unavailable: ["b"]).filter(\.isActive).map(\.window), ["a"])
        XCTAssertEqual(root.activeWindow, "b")
        XCTAssertEqual(root.placements(in: screen).filter(\.isActive).map(\.window), ["b"])
    }
    func testFullyUnavailableTreeProducesNoPlacements() {
        XCTAssertTrue(LayoutNode(window: "a").placements(in: screen, unavailable: ["a"]).isEmpty)
    }
    func testRatioClampingAndTinyRectNeverProduceNegativeSizes() {
        var root = LayoutNode(first: LayoutNode(window: "a"), second: LayoutNode(window: "b"), axis: .horizontal, ratio: .nan)
        XCTAssertEqual(root.ratio, 0.5)
        root.resize(node: root.id, ratio: 100)
        XCTAssertEqual(root.ratio, 0.9)
        for p in root.placements(in: LayoutRect(width: 1, height: 1), gap: 100) {
            XCTAssertGreaterThanOrEqual(p.rect.width, 0)
            XCTAssertGreaterThanOrEqual(p.rect.height, 0)
        }
    }
    func testPersistenceRoundTripPreservesNestedTabsAndStableIDs() throws {
        var root = LayoutNode(window: "a")
        _ = root.dock(window: "b", at: root.id, edge: .tab)
        _ = root.dock(window: "c", at: root.id, edge: .bottom)
        let data = try JSONEncoder().encode(root)
        let restored = try JSONDecoder().decode(LayoutNode.self, from: data)
        XCTAssertEqual(restored, root)
        XCTAssertEqual(restored.placements(in: screen), root.placements(in: screen))
    }
    func testMalformedSplitAndDuplicateWindowsAreRejected() throws {
        let a = LayoutNode(window: "a")
        let malformed = LayoutNode(first: a, second: a, axis: .horizontal)
        XCTAssertThrowsError(try JSONDecoder().decode(LayoutNode.self, from: JSONEncoder().encode(malformed)))
        var data = try JSONSerialization.jsonObject(with: JSONEncoder().encode(a)) as! [String: Any]
        data["children"] = [data]
        XCTAssertThrowsError(try JSONDecoder().decode(LayoutNode.self, from: JSONSerialization.data(withJSONObject: data)))
    }
    func testCorruptHistoryCannotCreateAnOutOfBoundsNavigationIndex() {
        let invalid = Data("{\"entries\":[\"a\"],\"index\":-100}".utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(ViewHistory.self, from: invalid))
    }
    func testDuplicateNodeIDsAreRejectedEvenWhenWindowIDsAreDifferent() throws {
        let a = LayoutNode(window: "a")
        let b = LayoutNode(window: "b",id: a.id)
        let root = LayoutNode(first: a,second: b,axis: .horizontal)
        XCTAssertThrowsError(try JSONDecoder().decode(LayoutNode.self,from: JSONEncoder().encode(root)))
    }
    func testHistoryBackForwardAndVisitTrimFuture() {
        var history = ViewHistory()
        history.visit("a"); history.visit("b"); history.visit("c")
        XCTAssertEqual(history.back(), "b")
        XCTAssertEqual(history.forward(), "c")
        _ = history.back(); history.visit("d")
        XCTAssertEqual(history.entries, ["a", "b", "d"])
        XCTAssertFalse(history.canGoForward)
        history.visit("d"); XCTAssertEqual(history.entries.count, 3)
    }
    func testHistoryIsBounded() {
        var history = ViewHistory()
        for i in 0..<200 { history.visit(String(i)) }
        XCTAssertEqual(history.entries.count, 100)
        XCTAssertEqual(history.current, "199")
        XCTAssertEqual(history.entries.first, "100")
    }
    func testRepeatedNestedMovesConserveEveryWindow() {
        var root = LayoutNode(window: "0")
        for i in 1..<40 { XCTAssertTrue(root.dock(window: String(i), at: root.id, edge: i.isMultiple(of: 2) ? .bottom : .right)) }
        let expected = Set((0..<40).map(String.init))
        for i in 0..<40 {
            let next = String((i + 1) % 40), target = root.leaf(containing: next)!.id
            XCTAssertTrue(root.dock(window: String(i), at: target, edge: i.isMultiple(of: 3) ? .tab : .left))
            XCTAssertEqual(Set(root.allWindows), expected)
            XCTAssertEqual(root.allWindows.count, 40)
            for placement in root.placements(in: screen) {
                XCTAssertTrue(placement.rect.x.isFinite)
                XCTAssertGreaterThanOrEqual(placement.rect.width, 0)
            }
        }
    }
}
