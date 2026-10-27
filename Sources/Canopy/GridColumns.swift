import AppKit
import CanopyCore

@MainActor
extension WorkspaceStore {
    var gridColumns: [LayoutNode] { current?.root?.layoutColumns ?? [] }

    static func columnLayout(_ columns: [LayoutNode],widths: [Double]? = nil,gap: Double = 8) -> LayoutNode? {
        guard !columns.isEmpty else { return nil }
        if columns.count == 1 { return columns[0] }
        let split = (columns.count+1)/2
        let sizes = widths ?? Array(repeating: 1,count: columns.count)
        let left = Array(columns.prefix(split)),right = Array(columns.dropFirst(split))
        let a = Array(sizes.prefix(split)),b = Array(sizes.dropFirst(split))
        // Widths include each column's content; nested separators also consume space.
        let first = a.reduce(0,+)+(widths == nil ? 0 : Double(a.count-1)*gap)
        let second = b.reduce(0,+)+(widths == nil ? 0 : Double(b.count-1)*gap)
        return LayoutNode(first: columnLayout(left,widths: widths == nil ? nil : a,gap: gap)!,
                          second: columnLayout(right,widths: widths == nil ? nil : b,gap: gap)!,
                          axis: .horizontal,ratio: first/(first+second))
    }
    static func columnPreset(_ leaves: [LayoutNode],count: Int) -> LayoutNode? {
        guard (1...8).contains(count) else { return nil }
        func stack(_ nodes: [LayoutNode]) -> LayoutNode {
            if nodes.count == 1 { var item = nodes[0]; item.columnID = nil; return item }
            let split = (nodes.count+1)/2
            return LayoutNode(first: stack(Array(nodes.prefix(split))),second: stack(Array(nodes.dropFirst(split))),axis: .vertical,ratio: Double(split)/Double(nodes.count))
        }
        var columns: [LayoutNode] = []; var offset = 0
        for index in 0..<count {
            let take = Int(ceil(Double(leaves.count-offset)/Double(count-index)))
            if take == 0 { columns.append(LayoutNode(emptyColumn: UUID().uuidString)) }
            else {
                var column = stack(Array(leaves[offset..<offset+take]))
                column.columnID = UUID().uuidString; columns.append(column); offset += take
            }
        }
        return columnLayout(columns)
    }
    func setGridColumnCount(_ count: Int) {
        guard (1...4).contains(count),let i = displays.firstIndex(where: { $0.id == selectedDisplay }) else { return }
        var leaves: [LayoutNode] = []; var seen = Set<String>()
        if let root = current?.root {
            for key in root.allWindows where !Self.isDesktop(key) && !unavailable.contains(key) {
                if var leaf = root.leaf(containing: key),seen.insert(leaf.id).inserted {
                    for missing in leaf.allWindows where unavailable.contains(missing) {
                        if let pruned = leaf.removing(window: missing) { leaf = pruned }
                    }
                    leaves.append(leaf)
                }
            }
        }
        checkpoint(); displays[i].root = Self.columnPreset(leaves,count: count)
        displays[i].focus = displays[i].root?.id; displays[i].cameraFrame = nil
        _ = fitExplicitColumnWidths(); commit()
    }
    func column(containing nodeID: String) -> LayoutNode? {
        gridColumns.first { $0.node(nodeID) != nil }
    }
    func stackWindow(_ key: String,inColumn columnID: String) {
        guard let target = gridColumns.first(where: { $0.columnID == columnID }) else { return }
        dock(key,target: target.id,edge: .bottom)
    }
    @discardableResult
    func giveWindowOwnColumn(_ key: String,beside targetNode: String? = nil,before: Bool = false) -> Bool {
        guard record(key) != nil,!Self.isDesktop(key),!isAlwaysFloating(key),isDemo || !unavailable.contains(key),
              let i = displays.firstIndex(where: { $0.id == selectedDisplay }) else { return false }
        var columns = gridColumns
        if columns.isEmpty {
            guard let root = current?.root else { addWindowsToCurrentGrid([key]); return true }
            var previous = root.removing(window: key)
            if previous == nil { return false }
            previous?.columnID = UUID().uuidString; columns = [previous!]
        }
        let source = columns.first { $0.allWindows.contains(key) }
        let target = targetNode.flatMap { id in columns.first { $0.node(id) != nil }?.columnID }
        if source?.allWindows == [key],target == nil || target == source?.columnID { return false }
        guard columns.count < 8 || source?.allWindows == [key] else { return false }
        checkpoint()
        columns = columns.compactMap { column in
            guard column.allWindows.contains(key) else { return column }
            return column.allWindows == [key] ? nil : column.removing(window: key)
        }
        var item = LayoutNode(window: key); item.columnID = UUID().uuidString
        let targetIndex = target.flatMap { id in columns.firstIndex { $0.columnID == id } }
        let insertion = targetIndex.map { $0+(before ? 0 : 1) } ?? (before ? 0 : columns.count)
        columns.insert(item,at: min(insertion,columns.count))
        displays[i].root = Self.columnLayout(columns)
        displays[i].focus = displays[i].root?.id; displays[i].cameraFrame = nil
        selectedWindow = key; _ = fitExplicitColumnWidths(); commit(); return true
    }
    /// After a settled AX rejection, the bridge may have learned a real minimum.
    /// Widen that column before falling back to the usual verified-layout rollback.
    @discardableResult
    func fitExplicitColumnWidths() -> Bool {
        guard !isDemo,let i = displays.firstIndex(where: { $0.id == selectedDisplay }),
              let root = current?.root,let descriptor = displayDescriptors.first(where: { $0.id == selectedDisplay }) else { return false }
        let frame = desktopViewport(descriptor)
        let columns = root.layoutColumns
        guard columns.count > 1,Set(root.allWindows) == Set(columns.flatMap(\.allWindows)) else { return false }
        let frames = root.frames(in: frame,gap: gap,unavailable: unavailable)
        let minima = columns.map { column in
            column.isSpacer ? 80.0 : max(preferences.minimumWidth,column.allWindows.filter { !unavailable.contains($0) }.compactMap { bridge.minimumSize($0)?.width }.max() ?? 0)
        }
        guard columns.indices.contains(where: { index in frames[columns[index].id].map { $0.width+2 < minima[index] } ?? false }) else { return false }
        var remaining = frame.width-Double(columns.count-1)*gap
        guard minima.reduce(0,+) <= remaining else { return false }
        var widths = Array(repeating: 0.0,count: columns.count),pending = Set(columns.indices)
        while !pending.isEmpty {
            let equal = remaining/Double(pending.count)
            let fixed = pending.filter { minima[$0] > equal }
            if fixed.isEmpty { for index in pending { widths[index] = equal }; break }
            for index in fixed { widths[index] = minima[index]; remaining -= minima[index]; pending.remove(index) }
        }
        displays[i].root = Self.columnLayout(columns,widths: widths,gap: gap)
        displays[i].focus = displays[i].root?.id
        return true
    }
    func addToExplicitColumns(_ keys: [String],root: LayoutNode) -> LayoutNode {
        var result = root
        for key in keys where !result.allWindows.contains(key) {
            let columns = result.layoutColumns
            guard let target = columns.first(where: \.isSpacer) ?? columns.min(by: { $0.allWindows.count < $1.allWindows.count }) else { continue }
            _ = result.dock(window: key,at: target.id,edge: .bottom)
        }
        return result
    }
}
