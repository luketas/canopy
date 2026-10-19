import Foundation

public extension LayoutRect {
    var maxX: Double { x + width }
    var maxY: Double { y + height }
    var area: Double { max(0, width) * max(0, height) }
    var isValid: Bool { [x, y, width, height].allSatisfy(\.isFinite) && width > 0 && height > 0 }
    func contains(x px: Double, y py: Double) -> Bool { px >= x && px <= maxX && py >= y && py <= maxY }
    func contains(_ other: LayoutRect) -> Bool { other.x >= x && other.y >= y && other.maxX <= maxX && other.maxY <= maxY }
    func intersection(_ other: LayoutRect) -> LayoutRect? {
        let left = max(x, other.x), top = max(y, other.y)
        let right = min(maxX, other.maxX), bottom = min(maxY, other.maxY)
        guard right > left, bottom > top else { return nil }
        return LayoutRect(x: left, y: top, width: right-left, height: bottom-top)
    }
    func inset(_ amount: Double) -> LayoutRect {
        let a = min(max(0, amount), max(0, min(width, height) / 2 - 0.5))
        return LayoutRect(x: x+a, y: y+a, width: width-2*a, height: height-2*a)
    }
    func interpolated(to other: LayoutRect, progress: Double) -> LayoutRect {
        let t = min(1, max(0, progress))
        return LayoutRect(x: x+(other.x-x)*t, y: y+(other.y-y)*t,
                          width: width+(other.width-width)*t, height: height+(other.height-height)*t)
    }
}

public struct SplitSeam: Equatable, Sendable {
    public var node: String
    public var axis: SplitAxis
    public var ratio: Double
    public var parent: LayoutRect
    public var rect: LayoutRect
}

public extension LayoutNode {
    func frames(in rect: LayoutRect, gap: Double = 8, unavailable: Set<String> = []) -> [String: LayoutRect] {
        guard occupiesSpace(unavailable: unavailable) else { return [:] }
        var result = [id: rect]
        if isLeaf { return result }
        let live = children.filter { $0.occupiesSpace(unavailable: unavailable) }
        if live.count == 1 { result.merge(live[0].frames(in: rect, gap: gap, unavailable: unavailable)) { _, new in new }; return result }
        guard live.count == 2 else { return result }
        let pair = partition(rect, gap: gap)
        result.merge(live[0].frames(in: pair.0, gap: gap, unavailable: unavailable)) { _, new in new }
        result.merge(live[1].frames(in: pair.1, gap: gap, unavailable: unavailable)) { _, new in new }
        return result
    }
    func seams(in rect: LayoutRect, gap: Double = 8, unavailable: Set<String> = []) -> [SplitSeam] {
        guard !isLeaf else { return [] }
        let live = children.filter { $0.occupiesSpace(unavailable: unavailable) }
        if live.count == 1 { return live[0].seams(in: rect, gap: gap, unavailable: unavailable) }
        guard live.count == 2 else { return [] }
        let pair = partition(rect, gap: gap)
        let seam = axis == .horizontal
            ? LayoutRect(x: pair.0.maxX, y: rect.y, width: max(1, pair.1.x-pair.0.maxX), height: rect.height)
            : LayoutRect(x: rect.x, y: pair.0.maxY, width: rect.width, height: max(1, pair.1.y-pair.0.maxY))
        return [SplitSeam(node: id, axis: axis, ratio: ratio, parent: rect, rect: seam)]
            + live[0].seams(in: pair.0, gap: gap, unavailable: unavailable)
            + live[1].seams(in: pair.1, gap: gap, unavailable: unavailable)
    }
    private func partition(_ rect: LayoutRect, gap: Double) -> (LayoutRect, LayoutRect) {
        let extent = axis == .horizontal ? rect.width : rect.height
        let gutter = min(max(0, gap), max(0, extent-2))
        let size = max(0, (extent-gutter)*ratio)
        var a = rect, b = rect
        if axis == .horizontal { a.width = size; b.x += size+gutter; b.width = max(0, extent-size-gutter) }
        else { a.height = size; b.y += size+gutter; b.height = max(0, extent-size-gutter) }
        return (a,b)
    }
    func bestFrame(for camera: LayoutRect, in world: LayoutRect, gap: Double = 8, unavailable: Set<String> = []) -> String {
        let frames = frames(in: world, gap: gap, unavailable: unavailable)
        return frames.filter { $0.value.contains(x: camera.midX, y: camera.midY) }
            .min { left, right in
                func score(_ rect: LayoutRect) -> Double {
                    abs(log(max(1, rect.area) / max(1, camera.area)))
                        + hypot(rect.midX-camera.midX, rect.midY-camera.midY) / max(1, hypot(world.width, world.height))
                }
                let l = score(left.value), r = score(right.value)
                return abs(l-r) < 0.000001 ? left.key < right.key : l < r
            }?.key ?? id
    }
}

public struct CameraViewport: Codable, Equatable, Sendable {
    public var frame: LayoutRect
    public init(frame: LayoutRect) { self.frame = frame }
    public func project(_ rect: LayoutRect, into viewport: LayoutRect) -> LayoutRect {
        let sx = viewport.width / max(1, frame.width), sy = viewport.height / max(1, frame.height)
        return LayoutRect(x: viewport.x+(rect.x-frame.x)*sx, y: viewport.y+(rect.y-frame.y)*sy,
                          width: rect.width*sx, height: rect.height*sy)
    }
    public func worldPoint(x: Double, y: Double, viewport: LayoutRect) -> (x: Double, y: Double) {
        (frame.x+(x-viewport.x)/max(1,viewport.width)*frame.width,
         frame.y+(y-viewport.y)/max(1,viewport.height)*frame.height)
    }
    public mutating func zoom(by scale: Double, anchorX: Double, anchorY: Double, world: LayoutRect) {
        guard scale.isFinite, scale > 0, world.isValid else { return }
        let ax = min(1,max(0,anchorX)), ay = min(1,max(0,anchorY))
        let width = min(world.width*2, max(world.width/32, frame.width/scale))
        let height = width * frame.height/max(1,frame.width)
        frame.x += (frame.width-width)*ax; frame.y += (frame.height-height)*ay
        frame.width = width; frame.height = height
        constrain(to: world)
    }
    public mutating func pan(dx: Double, dy: Double, viewport: LayoutRect, world: LayoutRect) {
        guard dx.isFinite, dy.isFinite else { return }
        frame.x -= dx/max(1,viewport.width)*frame.width
        frame.y -= dy/max(1,viewport.height)*frame.height
        constrain(to: world)
    }
    public mutating func constrain(to world: LayoutRect) {
        frame.x = min(world.maxX-frame.width*0.1, max(world.x-frame.width*0.9, frame.x))
        frame.y = min(world.maxY-frame.height*0.1, max(world.y-frame.height*0.9, frame.y))
    }
}

public struct DockIntent: Equatable, Sendable {
    public var display: String
    public var target: String?
    public var edge: DockEdge
    public var preview: LayoutRect
    public init(display: String, target: String?, edge: DockEdge, preview: LayoutRect) {
        self.display = display; self.target = target; self.edge = edge; self.preview = preview
    }
}

public enum DockResolver {
    public static func resolve(x: Double, y: Double, display: String, screen: LayoutRect,
                               root: LayoutNode?, frames: [String: LayoutRect], excluding: Set<String> = [],
                               screenEdge: Double = 28) -> DockIntent? {
        guard screen.contains(x: x,y: y) else { return nil }
        if root?.isSpacer == true {
            return DockIntent(display: display,target: root?.id,edge: .tab,preview: screen)
        }
        let distances: [(DockEdge,Double)] = [(.left,x-screen.x),(.right,screen.maxX-x),(.top,y-screen.y),(.bottom,screen.maxY-y)]
        if let edge = distances.min(by: { $0.1 < $1.1 }), edge.1 <= screenEdge {
            return DockIntent(display: display, target: root?.id, edge: edge.0, preview: half(screen,edge: edge.0))
        }
        guard let root else { return DockIntent(display: display,target: nil,edge: .right,preview: screen) }
        let targets = frames.filter { id,rect in
            let near = x >= rect.x-12 && x <= rect.maxX+12 && y >= rect.y-12 && y <= rect.maxY+12
            guard near,let node = root.node(id),node.isLeaf else { return false }
            return node.isSpacer || !node.allWindows.allSatisfy(excluding.contains)
        }
        guard let target = targets.min(by: { a,b in
            func distance(_ r: LayoutRect) -> Double {
                let dx = max(r.x-x,0,x-r.maxX),dy = max(r.y-y,0,y-r.maxY)
                return dx*dx+dy*dy
            }
            let da = distance(a.value),db = distance(b.value)
            return da != db ? da < db : a.value.area != b.value.area ? a.value.area < b.value.area : a.key < b.key
        }) else { return nil }
        let r = target.value
        if root.node(target.key)?.isSpacer == true {
            return DockIntent(display: display,target: target.key,edge: .tab,preview: r)
        }
        let nx = (x-r.x)/max(1,r.width), ny = (y-r.y)/max(1,r.height)
        let d: [(DockEdge,Double)] = [(.left,nx),(.right,1-nx),(.top,ny),(.bottom,1-ny)]
        let nearest = d.min { $0.1 < $1.1 }!
        let edge: DockEdge = nearest.1 < 0.24 ? nearest.0 : .tab
        return DockIntent(display: display,target: target.key,edge: edge,preview: edge == .tab ? r : half(r,edge: edge))
    }
    private static func half(_ rect: LayoutRect, edge: DockEdge) -> LayoutRect {
        switch edge {
        case .left: return LayoutRect(x: rect.x,y: rect.y,width: rect.width/2,height: rect.height)
        case .right: return LayoutRect(x: rect.midX,y: rect.y,width: rect.width/2,height: rect.height)
        case .top: return LayoutRect(x: rect.x,y: rect.y,width: rect.width,height: rect.height/2)
        case .bottom: return LayoutRect(x: rect.x,y: rect.midY,width: rect.width,height: rect.height/2)
        case .tab: return rect
        }
    }
}
