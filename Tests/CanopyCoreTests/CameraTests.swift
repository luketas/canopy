import XCTest
@testable import CanopyCore

final class CameraTests: XCTestCase {
    func testPointerZoomPreservesTheWorldPointUnderThePointer() {
        let world = LayoutRect(width: 1600,height: 1000),screen = LayoutRect(width: 800,height: 500)
        var camera = CameraViewport(frame: world)
        let before = camera.worldPoint(x: 200,y: 100,viewport: screen)
        camera.zoom(by: 2,anchorX: 0.25,anchorY: 0.2,world: world)
        let after = camera.worldPoint(x: 200,y: 100,viewport: screen)
        XCTAssertEqual(before.x,after.x,accuracy: 0.001); XCTAssertEqual(before.y,after.y,accuracy: 0.001)
        XCTAssertEqual(camera.frame.width,800)
    }
    func testProjectionAndInverseAgreeOnNegativeDisplayCoordinates() {
        let world = LayoutRect(x: 100,y: 200,width: 400,height: 300)
        let screen = LayoutRect(x: -1440,y: -900,width: 1440,height: 900)
        let camera = CameraViewport(frame: world)
        let projected = camera.project(LayoutRect(x: 200,y: 300,width: 100,height: 50),into: screen)
        let inverse = camera.worldPoint(x: projected.x,y: projected.y,viewport: screen)
        XCTAssertEqual(inverse.x,200,accuracy: 0.001); XCTAssertEqual(inverse.y,300,accuracy: 0.001)
    }
    func testDockResolverPrioritizesScreenEdgesAndExcludesTheSource() {
        let screen = LayoutRect(width: 1200,height: 800)
        let a = LayoutNode(window: "a"),b = LayoutNode(window: "b")
        let root = LayoutNode(first: a,second: b,axis: .horizontal)
        let frames = root.frames(in: screen)
        XCTAssertEqual(DockResolver.resolve(x: 2,y: 400,display: "display",screen: screen,root: root,frames: frames)?.target,root.id)
        XCTAssertEqual(DockResolver.resolve(x: 900,y: 400,display: "display",screen: screen,root: root,frames: frames)?.edge,.tab)
        XCTAssertNil(DockResolver.resolve(x: 300,y: 400,display: "display",screen: screen,root: root,frames: frames,excluding: ["a"]))
    }
    func testGroupMoveConservesTabsAndGroupIdentity() {
        let group = LayoutNode(windows: ["a","b"],active: "b")
        let other = LayoutNode(window: "c")
        var root = LayoutNode(first: group,second: other,axis: .horizontal)
        XCTAssertTrue(root.dock(subtree: group,at: root.id,edge: .bottom))
        XCTAssertEqual(root.children[1],group)
        XCTAssertEqual(Set(root.allWindows),["a","b","c"])
        XCTAssertFalse(root.dock(subtree: group,at: group.id,edge: .left))
    }
    func testSeamsAndFramesMatchThePlacementPartition() {
        let root = LayoutNode(first: LayoutNode(window: "a"),second: LayoutNode(window: "b"),axis: .horizontal,ratio: 0.3)
        let screen = LayoutRect(width: 1000,height: 600)
        let seam = root.seams(in: screen,gap: 10)[0],p = root.placements(in: screen,gap: 10)
        XCTAssertEqual(seam.rect.x,p[0].rect.maxX)
        XCTAssertEqual(seam.rect.maxX,p[1].rect.x)
        XCTAssertEqual(root.frames(in: screen,gap: 10)[p[0].node],p[0].rect)
    }
    func testBestCameraFrameFindsNestedSpace() {
        let child = LayoutNode(first: LayoutNode(window: "a"),second: LayoutNode(window: "b"),axis: .vertical)
        let root = LayoutNode(first: child,second: LayoutNode(window: "c"),axis: .horizontal)
        let world = LayoutRect(width: 1600,height: 1000)
        let frame = root.frames(in: world)[child.id]!
        XCTAssertEqual(root.bestFrame(for: frame,in: world),child.id)
    }
    func testWindowMatchingUsesDocumentsAndRejectsAmbiguousCandidates() {
        let frame = LayoutRect(width: 700,height: 500)
        let incoming = WindowFingerprint(bundle: "editor",title: "Renamed",ordinal: 0,document: "file:///work/a.swift",frame: frame)
        let old = WindowFingerprint(bundle: "editor",title: "Old",ordinal: 0,document: "file:///work/a.swift",frame: frame)
        XCTAssertEqual(WindowMatcher.match(incoming,candidates: [("a",old)]),"a")
        XCTAssertNil(WindowMatcher.match(incoming,candidates: [("a",old),("b",old)]))
    }
    func testInvalidCameraInputDoesNotCorruptGeometry() {
        let world = LayoutRect(width: 1000,height: 600)
        var camera = CameraViewport(frame: world)
        camera.zoom(by: .nan,anchorX: 0.5,anchorY: 0.5,world: world)
        XCTAssertEqual(camera.frame,world)
        for _ in 0..<200 { camera.zoom(by: 100,anchorX: 0.5,anchorY: 0.5,world: world) }
        XCTAssertTrue(camera.frame.isValid); XCTAssertGreaterThanOrEqual(camera.frame.width,world.width/32)
    }
}
