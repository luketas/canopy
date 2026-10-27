import AppKit
import CanopyCore

struct DesktopLayoutPlan {
    var display: DisplayDescriptor
    var root: LayoutNode
    var placements: [CanopyCore.WindowPlacement]
    var nativePlacements: [CanopyCore.WindowPlacement]
    var frames: [String:LayoutRect]
    var seams: [SplitSeam]
    var miniatureNodes: Set<String>
    var managedWindows: Set<String>
    var world: LayoutRect
}

@MainActor
extension WorkspaceStore {
    static func automaticArrangement(_ leaves: [LayoutNode],in frame: LayoutRect,preferred: CGSize) -> LayoutNode? {
        let capacity = max(1,Int(frame.width/max(1,preferred.width))*Int(frame.height/max(1,preferred.height)))
        guard leaves.count > capacity else { return balancedArrangement(leaves,in: frame) }
        let desktop = leaves.filter { $0.allWindows.allSatisfy(isDesktop) }
        let windows = leaves.filter { !$0.allWindows.allSatisfy(isDesktop) }
        guard !windows.isEmpty else { return balancedArrangement(desktop,in: frame) }
        let slots = max(1,capacity-desktop.count)
        var groups = capacity == 1 ? [] : desktop
        var offset = 0
        for slot in 0..<min(slots,windows.count) {
            let count = Int(ceil(Double(windows.count-offset)/Double(slots-slot)))
            let members = Array(windows[offset..<offset+count])
            if members.count == 1 { groups.append(members[0]) }
            else { groups.append(LayoutNode(windows: members.flatMap(\.allWindows),active: members[0].activeWindow)) }
            offset += count
        }
        return balancedArrangement(groups,in: frame)
    }
    static func balancedArrangement(_ leaves: [LayoutNode],in frame: LayoutRect) -> LayoutNode? {
        guard leaves.count > 1 else { return leaves.first }
        let aspect = frame.width/max(1,frame.height)
        let columns = min(leaves.count,max(1,Int(sqrt(Double(leaves.count)*aspect/1.6).rounded())))
        var groups: [LayoutNode] = []
        var offset = 0
        for column in 0..<columns {
            let count = Int(ceil(Double(leaves.count-offset)/Double(columns-column)))
            groups.append(stackedArrangement(Array(leaves[offset..<offset+count]),axis: .vertical))
            offset += count
        }
        return stackedArrangement(groups,axis: .horizontal)
    }
    private static func stackedArrangement(_ nodes: [LayoutNode],axis: SplitAxis) -> LayoutNode {
        if nodes.count == 1 { return nodes[0] }
        let count = (nodes.count+1)/2
        return LayoutNode(first: stackedArrangement(Array(nodes.prefix(count)),axis: axis),
                          second: stackedArrangement(Array(nodes.dropFirst(count)),axis: axis),
                          axis: axis,ratio: Double(count)/Double(nodes.count))
    }
    func performCommand(_ id: String,at pointer: CGPoint? = nil) {
        if !isDemo {
            let point = pointer ?? DesktopCoordinator.screenPoint()
            if let display = displayDescriptors.first(where: { $0.monitorBounds.contains(x: point.x,y: point.y) }) { selectedDisplay = display.id }
        }
        switch id {
        case "everything": showEverything()
        case "desktop": focusDesktop()
        case "zoom-out": zoomOut()
        case "zoom-in": focusTowardPointer()
        case "frame": frameFocusedWindow()
        case "auto-layout":
            if isDemo { useRealWindows() }
            if !isDemo { autoLayoutCurrentMonitor() }
        case "workspace-previous": cycleWorkspace(-1)
        case "workspace-next": cycleWorkspace(1)
        case "previous": selectNeighbor(-1)
        case "next": selectNeighbor(1)
        case "back": navigateHistory(back: true)
        case "forward": navigateHistory(back: false)
        default:
            if id.hasPrefix("workspace."),let slot = Int(id.dropFirst(10)),let grids = current?.grids,grids.indices.contains(slot-1) { selectWorkspaceGrid(grids[slot-1].id,activate: true) }
            if id.hasPrefix("view."),let slot = Int(id.dropFirst(5)) { recallView(slot) }
            if id.hasPrefix("save."),let slot = Int(id.dropFirst(5)) { saveView(slot) }
        }
    }
    func desktopViewport(_ descriptor: DisplayDescriptor) -> LayoutRect {
        let frame = descriptor.frame
        let top = isDemo ? 0 : DesktopWorkspaceBar.height
        return LayoutRect(x: frame.x,y: frame.y+top,width: frame.width,height: max(1,frame.height-top)).inset(gap)
    }
    func desktopPlans() -> [DesktopLayoutPlan] {
        let descriptors = displayDescriptors.filter { !isArranging || arrangedDisplayIDs?.contains($0.id) != false }
        var owners: [String:String] = [:]
        // Saved layouts can share a physical window across displays, including
        // disconnected displays. Place it once, preferring the selected display.
        let priority = descriptors.filter { $0.id == selectedDisplay } + descriptors.filter { $0.id != selectedDisplay }
        for descriptor in priority {
            for key in displays.first(where: { $0.id == descriptor.id })?.root?.allWindows ?? [] where owners[key] == nil {
                owners[key] = descriptor.id
            }
        }
        return descriptors.compactMap { descriptor in
            guard let workspace = displays.first(where: { $0.id == descriptor.id }) else { return nil }
            let unavailable = self.unavailable.union(owners.filter { $0.value != descriptor.id }.map(\.key))
            let root = workspace.root ?? LayoutNode(emptyColumn: "empty-workspace-\(descriptor.id)")
            let viewport = desktopViewport(descriptor)
            let world = LayoutRect(width: viewport.width,height: viewport.height)
            let requestedFocus = workspace.focus.flatMap(root.node) ?? root
            let hasVisibleWindows = requestedFocus.allWindows.contains { !unavailable.contains($0) }
            let focus = workspace.cameraFrame == nil && hasVisibleWindows ? requestedFocus : root
            let camera = workspace.cameraFrame.map { CameraViewport(frame: $0) }
            let logical = camera == nil ? viewport : world
            let projected: (LayoutRect) -> LayoutRect = { camera?.project($0,into: viewport) ?? $0 }
            let placements = focus.placements(in: logical,gap: gap,unavailable: unavailable).map { placement in
                var p = placement; p.rect = projected(p.rect); return p
            }
            let frames = focus.frames(in: logical,gap: gap,unavailable: unavailable).mapValues(projected)
            var native: [CanopyCore.WindowPlacement] = []
            var mini = Set<String>()
            var managed = Set(root.allWindows.filter { !Self.isDesktop($0) })
            for p in placements where p.isActive {
                if Self.isDesktop(p.window) { continue }
                let leaf = root.node(p.node)
                let strip = preferences.showTabStrips && (leaf?.windows.count ?? 0) > 1 ? 28.0 : 0
                let rect = LayoutRect(x: p.rect.x,y: p.rect.y+strip,width: p.rect.width,height: max(1,p.rect.height-strip))
                let minimum = bridge.minimumSize(p.window) ?? .zero
                if viewport.contains(p.rect), rect.width >= max(preferences.minimumWidth,minimum.width), rect.height >= max(preferences.minimumHeight,minimum.height) {
                    var n = p; n.rect = rect; native.append(n)
                } else { mini.insert(p.node) }
            }
            // Floating windows live on the Desktop plane. When zoomed out that plane
            // becomes one miniature; focusing it restores usable native frames.
            let desktop = placements.first { Self.isDesktop($0.window) }
            let floats = floatingRecords.filter { record in
                let frame = movedWindows.contains(record.id) ? record.originalFrame : bridge.windows[record.id].flatMap { bridge.frame(of: $0.element) } ?? record.originalFrame
                return descriptor.frame.contains(x: frame.midX,y: frame.midY)
            }
            if let desktop {
                managed.formUnion(floats.map(\.id))
                let r = desktop.rect
                if r.width < preferences.minimumWidth || r.height < preferences.minimumHeight || !viewport.contains(r) {
                    mini.insert(desktop.node)
                } else {
                    for record in floats {
                        let original = record.originalFrame
                        let rect = CameraViewport(frame: descriptor.frame).project(original,into: r)
                        if rect.width >= preferences.minimumWidth, rect.height >= preferences.minimumHeight, r.contains(rect) {
                            native.append(CanopyCore.WindowPlacement(window: record.id,node: desktop.node,rect: rect,isActive: true))
                        } else { mini.insert(desktop.node) }
                    }
                }
            }
            var seams = focus.seams(in: logical,gap: gap,unavailable: unavailable)
            for i in seams.indices { seams[i].rect = projected(seams[i].rect); seams[i].parent = projected(seams[i].parent) }
            var collapsed: [String] = []
            for (id,rect) in frames.sorted(by: { $0.value.area > $1.value.area }) {
                guard let node = focus.node(id),!node.isLeaf,(rect.width < 140 || rect.height < 100),
                      !collapsed.contains(where: { focus.node($0)?.node(id) != nil }) else { continue }
                collapsed.append(id)
            }
            for group in collapsed {
                guard let node = focus.node(group) else { continue }
                let keys = Set(node.allWindows)
                native.removeAll { keys.contains($0.window) }
                mini = Set(mini.filter { node.node($0) == nil }); mini.insert(group)
                seams.removeAll { node.node($0.node) != nil }
            }
            return DesktopLayoutPlan(display: descriptor,root: focus,placements: placements,nativePlacements: native,frames: frames,
                seams: seams,miniatureNodes: mini,managedWindows: managed,world: world)
        }
    }

    func dock(_ keys: [String], intent: DockIntent, wholeGroup: Bool = false) {
        guard !keys.isEmpty,keys.allSatisfy({ record($0) != nil && !Self.isDesktop($0) && !isAlwaysFloating($0) }),
              let destinationIndex = displays.firstIndex(where: { $0.id == intent.display }) else { return }
        let item: LayoutNode
        if wholeGroup, let source = displays.compactMap({ $0.root?.leaf(containing: keys[0]) }).first,
           Set(source.windows) == Set(keys) { item = source }
        else { item = LayoutNode(windows: keys,active: keys[0]) }
        let existing = displays[destinationIndex].root
        var destination = existing ?? LayoutNode(emptyColumn: "initial-column-\(intent.display)")
        let target = existing == nil ? destination.id : intent.target ?? destination.id
        if let node = destination.node(target), node.allWindows.contains(where: Self.isDesktop), intent.edge == .tab { return }
        guard destination.dock(subtree: item,at: target,edge: intent.edge) else { return }
        checkpoint()
        for i in displays.indices where i != destinationIndex {
            for g in displays[i].grids.indices {
                for key in keys { displays[i].grids[g].root = displays[i].grids[g].root?.removing(window: key) }
            }
        }
        displays[destinationIndex].root = destination
        displays[destinationIndex].focus = destination.id; displays[destinationIndex].cameraFrame = nil
        selectedDisplay = intent.display; selectedWindow = keys[0]
        commit()
    }

    func focusDesktop() {
        let key = "desktop:\(selectedDisplay)"
        if let leaf = current?.root?.leaf(containing: key) { focus(leaf.id) }
        else { floatAll() }
    }

    func frameFocusedWindow() {
        guard let key = bridge.focusedWindow() ?? selectedWindow,
              let display = displays.first(where: { $0.root?.leaf(containing: key) != nil }),
              let leaf = display.root?.leaf(containing: key) else { return }
        selectedDisplay = display.id; selectedWindow = key; toggleFocus(leaf.id)
    }

    func focusTowardPointer() {
        let pointer = NSEvent.mouseLocation
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        let x = pointer.x,y = top-pointer.y
        for plan in desktopPlans() where plan.display.frame.contains(x: x,y: y) {
            if let node = plan.frames.filter({ $0.value.contains(x: x,y: y) }).min(by: { $0.value.area < $1.value.area })?.key {
                selectedDisplay = plan.display.id; focus(node); return
            }
        }
        zoomIn()
    }

    func setCameraFrame(_ rect: LayoutRect, display: String? = nil) {
        guard rect.isValid,let i = displays.firstIndex(where: { $0.id == (display ?? selectedDisplay) }) else { return }
        if displays[i].cameraFrame != rect {
            let token = "frame:\(UUID().uuidString)"
            if displays[i].historyFrames == nil { displays[i].historyFrames = [:] }
            displays[i].historyFrames?[token] = rect; displays[i].history.visit(token)
            let retained = Set(displays[i].history.entries)
            displays[i].historyFrames = displays[i].historyFrames?.filter { retained.contains($0.key) }
        }
        displays[i].focus = displays[i].root?.id; displays[i].cameraFrame = rect; persist(); applyLayout()
    }

    func updatePreferences(_ edit: (inout UserPreferences) -> Void) {
        var copy = preferences; edit(&copy)
        copy.minimumWidth = min(600,max(100,copy.minimumWidth)); copy.minimumHeight = min(400,max(80,copy.minimumHeight))
        copy.animationDuration = min(1,max(0.1,copy.animationDuration))
        preferences = copy; persist(); onPreferencesChanged?(); applyLayout()
    }

    func recoverWindows() {
        guard !isDemo,hasPermission else { return }
        // A browser's title and document can both change while Canopy is
        // closed. Reconnect a sole recovery entry to a sole available app
        // window; leave multiple-window cases unresolved rather than guessing.
        for i in pendingRecovery.indices where bridge.windows[pendingRecovery[i].id] == nil {
            let entry = pendingRecovery[i]
            let candidates = bridge.windows.values.filter { $0.record.bundleID == entry.bundleID && !unavailable.contains($0.id) }
            if candidates.count == 1,records.filter({ $0.bundleID == entry.bundleID }).count == 1,
               pendingRecovery.filter({ $0.bundleID == entry.bundleID }).count == 1,
               let candidate = candidates.first {
                pendingRecovery[i].id = candidate.id
            }
        }
        for key in recoveryMinimized where bridge.setMinimized(key,false) { recoveryMinimized.remove(key) }
        let present = pendingRecovery.filter { bridge.windows[$0.id] != nil && !unavailable.contains($0.id) }
        let failures = bridge.restore(present)
        let succeeded = Set(present.map(\.id)).subtracting(failures)
        pendingRecovery.removeAll { succeeded.contains($0.id) }
        persist()
        message = pendingRecovery.isEmpty ? nil : "\(pendingRecovery.count) windows still need recovery. Reopen their apps or re-enable Accessibility, then retry."
    }
}
