import Foundation

public enum SplitAxis: String, Codable, Sendable { case horizontal, vertical }
public enum DockEdge: String, CaseIterable, Sendable { case left, right, top, bottom, tab }

/// Logical coordinates use a top-left origin, like macOS Accessibility coordinates.
public struct LayoutRect: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    public init(x: Double = 0, y: Double = 0, width: Double, height: Double) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }
    public var midX: Double { x + width / 2 }
    public var midY: Double { y + height / 2 }
}

/// Binary splits form an unbounded tree; a leaf holds one or more cross-app tabs.
public struct LayoutNode: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public private(set) var windows: [String]
    public private(set) var activeWindow: String?
    public private(set) var children: [LayoutNode]
    public private(set) var axis: SplitAxis
    public var columnID: String?
    public private(set) var isSpacer = false
    public private(set) var ratio: Double

    private enum CodingKeys: String, CodingKey { case id, windows, activeWindow, children, axis, ratio, columnID, isSpacer }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        windows = try values.decode([String].self, forKey: .windows)
        activeWindow = try values.decodeIfPresent(String.self, forKey: .activeWindow)
        children = try values.decode([LayoutNode].self, forKey: .children)
        axis = try values.decode(SplitAxis.self, forKey: .axis)
        ratio = Self.clampedRatio(try values.decode(Double.self, forKey: .ratio))
        columnID = try values.decodeIfPresent(String.self,forKey: .columnID)
        isSpacer = try values.decodeIfPresent(Bool.self,forKey: .isSpacer) ?? false
        guard !id.isEmpty,
              ((children.isEmpty && !windows.isEmpty && !isSpacer) || (children.count == 2 && windows.isEmpty && !isSpacer) || (children.isEmpty && windows.isEmpty && isSpacer)),
              columnID == nil || columnID?.isEmpty == false,
              Set(allWindows).count == allWindows.count,
              Set(allNodeIDs).count == allNodeIDs.count,
              allWindows.allSatisfy({ !$0.isEmpty }) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid split or duplicate window in layout"))
        }
        if children.isEmpty && !windows.contains(activeWindow ?? "") { activeWindow = windows.first }
        if !children.isEmpty { activeWindow = nil }
    }

    public init(window: String, id: String = UUID().uuidString) {
        self.id = id; windows = [window]; activeWindow = window
        children = []; axis = .horizontal; ratio = 0.5
    }
    public init(first: LayoutNode, second: LayoutNode, axis: SplitAxis,
                ratio: Double = 0.5, id: String = UUID().uuidString) {
        self.id = id; windows = []; activeWindow = nil
        children = [first, second]; self.axis = axis
        self.ratio = Self.clampedRatio(ratio)
    }
    public init(windows: [String], active: String? = nil, id: String = UUID().uuidString) {
        precondition(!windows.isEmpty && Set(windows).count == windows.count)
        self.id = id; self.windows = windows; activeWindow = active.flatMap { windows.contains($0) ? $0 : nil } ?? windows[0]
        children = []; axis = .horizontal; ratio = 0.5
    }
    public init(emptyColumn id: String = UUID().uuidString) {
        self.id = UUID().uuidString; columnID = id; isSpacer = true
        windows = []; activeWindow = nil; children = []; axis = .horizontal; ratio = 0.5
    }
    public var layoutColumns: [LayoutNode] {
        if columnID != nil { return [self] }
        return children.flatMap(\.layoutColumns)
    }
    public func occupiesSpace(unavailable: Set<String>) -> Bool {
        columnID != nil || isSpacer || children.contains { $0.occupiesSpace(unavailable: unavailable) } || windows.contains { !unavailable.contains($0) }
    }
    public var isLeaf: Bool { children.isEmpty }
    public var allWindows: [String] { isLeaf ? windows : children.flatMap(\.allWindows) }
    public var nodeCount: Int { 1 + children.reduce(0) { $0 + $1.nodeCount } }
    private var allNodeIDs: [String] { [id]+children.flatMap(\.allNodeIDs) }
    public func node(_ target: String) -> LayoutNode? {
        if id == target { return self }
        for child in children {
            if let found = child.node(target) { return found }
        }
        return nil
    }
    public func leaf(containing window: String) -> LayoutNode? {
        if windows.contains(window) { return self }
        for child in children {
            if let found = child.leaf(containing: window) { return found }
        }
        return nil
    }
    public func path(to target: String) -> [String]? {
        if id == target { return [id] }
        for child in children {
            if let path = child.path(to: target) { return [id] + path }
        }
        return nil
    }
    public mutating func update(_ target: String, _ edit: (inout LayoutNode) -> Void) {
        if id == target { edit(&self); return }
        for index in children.indices { children[index].update(target, edit) }
    }
    public mutating func select(window: String) {
        if windows.contains(window) { activeWindow = window }
        for index in children.indices { children[index].select(window: window) }
    }
    public mutating func resize(node: String, ratio: Double) {
        update(node) { $0.ratio = Self.clampedRatio(ratio) }
    }
    private static func clampedRatio(_ ratio: Double) -> Double {
        ratio.isFinite ? min(0.9, max(0.1, ratio)) : 0.5
    }
    private func emptyColumnReplacement() -> LayoutNode? {
        guard let columnID else { return nil }
        var empty = LayoutNode(emptyColumn: columnID); empty.id = id; return empty
    }
    /// Returns nil for an empty branch, collapsing redundant splits.
    public func removing(window: String) -> LayoutNode? {
        guard allWindows.contains(window) else { return self }
        var result = self
        if isLeaf {
            result.windows.removeAll { $0 == window }
            guard !result.windows.isEmpty else { return emptyColumnReplacement() }
            if result.activeWindow == window { result.activeWindow = result.windows.first }
        } else {
            result.children = children.compactMap { $0.removing(window: window) }
            if result.children.isEmpty { return emptyColumnReplacement() }
            if result.children.count == 1 {
                var survivor = result.children[0]
                if let columnID { survivor.columnID = columnID }
                return survivor
            }
        }
        return result
    }
    public func remappingWindow(_ old: String,to replacement: String) -> LayoutNode {
        guard old != replacement,let leaf = leaf(containing: old) else { return self }
        if allWindows.contains(replacement) { return removing(window: old)! }
        var result = self
        result.update(leaf.id) { node in
            node.windows = node.windows.map { $0 == old ? replacement : $0 }
            if node.activeWindow == old { node.activeWindow = replacement }
        }
        return result
    }
    /// Moving is transactional: an invalid target never drops the source window.
    @discardableResult
    public mutating func dock(window: String, at target: String, edge: DockEdge) -> Bool {
        let source = leaf(containing: window)
        var item = source?.windows == [window] ? source! : LayoutNode(window: window)
        item.columnID = nil
        return dock(subtree: item, at: target, edge: edge)
    }

    @discardableResult
    public mutating func dock(subtree item: LayoutNode, at target: String, edge: DockEdge) -> Bool {
        guard let targetNode = node(target) else { return false }
        if edge == .tab && (!targetNode.isLeaf || !item.isLeaf) { return false }
        let moving = Set(item.allWindows)
        if !targetNode.isSpacer && Set(targetNode.allWindows).isSubset(of: moving) { return false }
        // A target split may collapse when the source is one of its children.
        // Keep the surviving subtree's identity so a screen-edge move docks beside
        // the whole remaining space, rather than beside an arbitrary descendant.
        var remainingTarget: LayoutNode? = targetNode
        var remainingTree: LayoutNode? = self
        for window in item.allWindows {
            remainingTarget = remainingTarget?.removing(window: window)
            remainingTree = remainingTree?.removing(window: window)
        }
        let survivingTarget = remainingTarget?.id
        guard var tree = remainingTree else { return false }
        // Removing a marked column's final app preserves an empty drop slot.
        // Detach moving identities from those surviving slots before insertion.
        func detached(_ original: LayoutNode) -> LayoutNode {
            var result = original
            if tree.node(result.id) != nil { result.id = UUID().uuidString }
            result.columnID = nil
            result.children = original.children.map(detached)
            return result
        }
        let inserted = detached(item)
        let resolvedID: String
        if tree.node(target) != nil { resolvedID = target }
        else if let survivor = survivingTarget, tree.node(survivor) != nil { resolvedID = survivor }
        else { return false }
        tree.update(resolvedID) { node in
            let column = node.columnID
            node.columnID = nil
            if node.isSpacer { node = inserted }
            else if edge == .tab {
                node.windows += inserted.windows.filter { !node.windows.contains($0) }
                node.activeWindow = inserted.activeWindow
            } else {
                let before = edge == .left || edge == .top
                let splitAxis: SplitAxis = edge == .left || edge == .right ? .horizontal : .vertical
                node = LayoutNode(first: before ? inserted : node, second: before ? node : inserted, axis: splitAxis)
            }
            node.columnID = column
        }
        self = tree
        return true
    }

    public func placements(in rect: LayoutRect, gap: Double = 8,
                           unavailable: Set<String> = []) -> [WindowPlacement] {
        let available = allWindows.filter { !unavailable.contains($0) }
        guard !available.isEmpty || occupiesSpace(unavailable: unavailable) else { return [] }
        if isSpacer { return [] }
        if isLeaf {
            let visible = windows.filter { !unavailable.contains($0) }
            guard !visible.isEmpty else { return [] }
            let selected = visible.contains(activeWindow ?? "") ? activeWindow! : visible[0]
            return visible.map { WindowPlacement(window: $0, node: id, rect: rect, isActive: $0 == selected) }
        }
        let live = children.filter { $0.occupiesSpace(unavailable: unavailable) }
        if live.count == 1 { return live[0].placements(in: rect, gap: gap, unavailable: unavailable) }
        guard live.count == 2 else { return [] }
        let horizontal = axis == .horizontal
        let extent = horizontal ? rect.width : rect.height
        let gutter = min(max(gap, 0), max(0, extent - 2))
        let firstSize = max(0, (extent - gutter) * ratio)
        var first = rect, second = rect
        if horizontal {
            first.width = firstSize
            second.x += firstSize + gutter
            second.width = max(0, extent - firstSize - gutter)
        } else {
            first.height = firstSize
            second.y += firstSize + gutter
            second.height = max(0, extent - firstSize - gutter)
        }
        return live[0].placements(in: first, gap: gap, unavailable: unavailable)
             + live[1].placements(in: second, gap: gap, unavailable: unavailable)
    }
}

public struct WindowPlacement: Equatable, Sendable {
    public var window: String
    public var node: String
    public var rect: LayoutRect
    public var isActive: Bool
    public init(window: String,node: String,rect: LayoutRect,isActive: Bool) {
        self.window = window; self.node = node; self.rect = rect; self.isActive = isActive
    }
}

public struct ViewHistory: Codable, Equatable, Sendable {
    public private(set) var entries: [String] = []
    public private(set) var index: Int = -1
    public init() {}
    private enum CodingKeys: String, CodingKey { case entries, index }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        entries = try values.decode([String].self, forKey: .entries)
        index = try values.decode(Int.self, forKey: .index)
        guard entries.count <= 100,
              (entries.isEmpty && index == -1) || entries.indices.contains(index) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid navigation history"))
        }
    }
    public var current: String? { entries.indices.contains(index) ? entries[index] : nil }
    public var canGoBack: Bool { index > 0 }
    public var canGoForward: Bool { index + 1 < entries.count }
    public mutating func visit(_ node: String) {
        guard current != node else { return }
        entries = Array(entries.prefix(index + 1)) + [node]
        if entries.count > 100 { entries.removeFirst(entries.count - 100) }
        index = entries.count - 1
    }
    public mutating func back() -> String? {
        guard canGoBack else { return nil }; index -= 1; return current
    }
    public mutating func forward() -> String? {
        guard canGoForward else { return nil }; index += 1; return current
    }
}
