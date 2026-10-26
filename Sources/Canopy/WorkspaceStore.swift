import AppKit
import SwiftUI
import CanopyCore

struct WorkspaceGrid: Codable, Identifiable, Equatable {
    var id = UUID().uuidString
    var name: String
    var root: LayoutNode?
    var focus: String?
    var savedViews: [String:String] = [:]
    var history = ViewHistory()
    var cameraFrame: LayoutRect?
    var savedFrames: [String:LayoutRect]?
    var historyFrames: [String:LayoutRect]?
}

struct DisplayWorkspace: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var grids: [WorkspaceGrid]
    var activeGridID: String
    private var gridIndex: Int { grids.firstIndex { $0.id == activeGridID } ?? 0 }
    var root: LayoutNode? { get { grids[gridIndex].root } set { grids[gridIndex].root = newValue } }
    var focus: String? { get { grids[gridIndex].focus } set { grids[gridIndex].focus = newValue } }
    var savedViews: [String:String] { get { grids[gridIndex].savedViews } set { grids[gridIndex].savedViews = newValue } }
    var history: ViewHistory { get { grids[gridIndex].history } set { grids[gridIndex].history = newValue } }
    var cameraFrame: LayoutRect? { get { grids[gridIndex].cameraFrame } set { grids[gridIndex].cameraFrame = newValue } }
    var savedFrames: [String:LayoutRect]? { get { grids[gridIndex].savedFrames } set { grids[gridIndex].savedFrames = newValue } }
    var historyFrames: [String:LayoutRect]? { get { grids[gridIndex].historyFrames } set { grids[gridIndex].historyFrames = newValue } }
    var allGridWindows: Set<String> { Set(grids.flatMap { $0.root?.allWindows ?? [] }) }
    init(id: String,name: String,root: LayoutNode? = nil,focus: String? = nil) {
        self.id = id; self.name = name
        let grid = WorkspaceGrid(name: "Grid 1",root: root,focus: focus)
        grids = [grid]; activeGridID = grid.id
    }
    private enum CodingKeys: String,CodingKey { case id,name,grids,activeGridID,root,focus,savedViews,history,cameraFrame,savedFrames,historyFrames }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self,forKey: .id); name = try c.decode(String.self,forKey: .name)
        if let saved = try c.decodeIfPresent([WorkspaceGrid].self,forKey: .grids) {
            grids = saved; activeGridID = try c.decode(String.self,forKey: .activeGridID)
            guard !grids.isEmpty,grids.count <= 32,Set(grids.map(\.id)).count == grids.count,
                  grids.contains(where: { $0.id == activeGridID }),grids.allSatisfy({ !$0.id.isEmpty && !$0.name.isEmpty && $0.name.count <= 60 }) else {
                throw DecodingError.dataCorruptedError(forKey: .grids,in: c,debugDescription: "Invalid workspace tabs")
            }
        } else {
            var grid = WorkspaceGrid(name: "Grid 1",root: try c.decodeIfPresent(LayoutNode.self,forKey: .root),focus: try c.decodeIfPresent(String.self,forKey: .focus))
            grid.savedViews = try c.decodeIfPresent([String:String].self,forKey: .savedViews) ?? [:]
            grid.history = try c.decodeIfPresent(ViewHistory.self,forKey: .history) ?? ViewHistory()
            grid.cameraFrame = try c.decodeIfPresent(LayoutRect.self,forKey: .cameraFrame)
            grid.savedFrames = try c.decodeIfPresent([String:LayoutRect].self,forKey: .savedFrames)
            grid.historyFrames = try c.decodeIfPresent([String:LayoutRect].self,forKey: .historyFrames)
            grids = [grid]; activeGridID = grid.id
        }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id,forKey: .id); try c.encode(name,forKey: .name)
        try c.encode(grids,forKey: .grids); try c.encode(activeGridID,forKey: .activeGridID)
    }
}

struct WorkspaceSnapshot: Codable {
    var version = 4
    var displays: [DisplayWorkspace] = []
    var records: [WindowRecord] = []
    var excludedApps: Set<String> = []
    var gap: Double = 8
    var preferences: UserPreferences?
    var recoveryWindows: [WindowRecord]?
    var recoveryMinimized: Set<String>?
}

@MainActor
final class WorkspaceStore: ObservableObject {
    @Published var displays: [DisplayWorkspace] = []
    @Published var records: [WindowRecord] = []
    @Published var selectedDisplay = ""
    @Published var selectedWindow: String?
    @Published var isDemo = false
    @Published var isArranging = false
    // nil is the usual all-display session. A quick-layout session starts only
    // on its target monitor and can add monitors without enrolling the others.
    var arrangedDisplayIDs: Set<String>?
    private(set) var layoutDisplayScope: String?
    @Published var hasPermission = false
    @Published var message: String?
    @Published var excludedApps: Set<String> = []
    @Published var gap: Double = 8
    @Published var shortcutStatus: String?
    @Published var preferences = UserPreferences()
    @Published var pendingRecovery: [WindowRecord] = []
    @Published var previews: [String:NSImage] = [:]
    @Published var previewStatus: String?
    @Published var dormantWindows = Set<String>()
    var onWorkspaceSwitch: ((@escaping () -> Void) -> Void)?
    private(set) var workspaceSwitchPending = false
    private var workspaceSwitchGeneration = 0
    var onLayoutWillApply: (([DesktopLayoutPlan]) -> Void)?
    var onLayoutDidApply: (([DesktopLayoutPlan]) -> Void)?
    var onPause: (() -> Void)?
    var onPreferencesChanged: (() -> Void)?
    var onRequestCamera: (() -> Void)?
    var onOpenWorkspace: (() -> Void)?
    var onRequestPreviews: ((Bool) -> Void)?
    private(set) var bridge: any WindowManaging
    private var timer: Timer?
    private var layoutVerification: Task<Void,Never>?
    private var verifiedLayouts: [DisplayWorkspace]?
    private var spaceVerification: Task<Void,Never>?
    private var spaceTransitionPending = false
    private var undoStack: [[DisplayWorkspace]] = []
    private var redoStack: [[DisplayWorkspace]] = []
    private var realSnapshot: WorkspaceSnapshot?
    private var lastAvailability = Set<String>()
    var movedWindows = Set<String>()
    // Kept only for restoring sessions created by older minimizing builds.
    var managerMinimized = Set<String>()
    var occludedWindows = Set<String>()
    #if DEBUG
    var lastNativeMoveCount = 0
    #endif
    private var placementTargets: [String:LayoutRect] = [:]
    private var layoutFocusedWindow: String?
    private var gridActivationHistory: [String] = []
    var recoveryMinimized = Set<String>()
    private let screenProvider: () -> [DisplayDescriptor]
    private var events: WindowEvents?
    private var destroyedWindows = Set<String>()
    var interactiveDrag = false
    private(set) var isResizing = false
    private(set) var applyingGeometryOnly = false
    private var lastNativeVisible = Set<String>()
    private var resizeWork: Timer?
    @Published var draggedWindow: String?
    @Published var editorDropTarget: String?
    @Published var editorDropEdge: DockEdge?
    var editorTargets: [String:EditorDropTarget] = [:]
    var displayDescriptors: [DisplayDescriptor] {
        isDemo ? [DisplayDescriptor(id: "demo",name: "Demo workspace",frame: LayoutRect(width: 1440,height: 900))] : screenProvider()
    }
    private var canPersist = true
    private var storageWarning: String?
    let persistenceURL: URL

    init(demo: Bool = false, bridge: (any WindowManaging)? = nil, storageURL: URL? = nil,
         screens: (() -> [DisplayDescriptor])? = nil) {
        self.bridge = bridge ?? WindowBridge()
        screenProvider = screens ?? { NSScreen.screens.map { screen in
            let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
            let uuid = number.flatMap { CGDisplayCreateUUIDFromDisplayID($0.uint32Value)?.takeRetainedValue() }
            let id = uuid.flatMap { CFUUIDCreateString(nil,$0) as String? } ?? number?.stringValue ?? screen.localizedName
            let top = NSScreen.screens.first?.frame.maxY ?? screen.frame.maxY
            let bounds = LayoutRect(x: screen.frame.minX,y: top-screen.frame.maxY,width: screen.frame.width,height: screen.frame.height)
            return DisplayDescriptor(id: id,name: screen.localizedName,frame: WindowBridge.usableFrame(screen),legacyID: number?.stringValue,bounds: bounds)
        } }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        persistenceURL = storageURL ?? support.appendingPathComponent("Canopy/workspace.json")
        load()
        if (self.bridge as? WindowBridge)?.allowedBundles != nil { preferences.globalGestures = false }
        hasPermission = self.bridge.trusted
        synchronizeScreens()
        if demo || !hasPermission { enterDemo() }
        else { refresh() }
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        if self.bridge is WindowBridge {
            let observer = WindowEvents()
            observer.onChange = { [weak self] in self?.refresh() }
            observer.onFocusChange = { [weak self] in self?.routeFocusedWindowToWorkspace() }
            observer.onSpaceChanged = { [weak self] in self?.handleSpaceChange() }
            observer.onDestroyed = { [weak self] element in
                guard let self else { return }
                let key = self.bridge.windows.values.first(where: { CFEqual($0.element,element) })?.id
                #if DEBUG
                let note = "destroyed: matched=\(key != nil)\n"
                try? note.write(to: FileManager.default.temporaryDirectory.appendingPathComponent("canopy-destroyed.txt"),atomically: true,encoding: .utf8)
                #endif
                guard let key else { return }
                if self.bridge.forgetWindow(key) { self.destroyedWindows.insert(key) }
            }
            events = observer
            if !isDemo { observer.synchronize(self.bridge.windows) }
        }
    }

    var current: DisplayWorkspace? { displays.first { $0.id == selectedDisplay } }
    var focusedNode: LayoutNode? {
        guard let root = current?.root else { return nil }
        return current?.focus.flatMap(root.node) ?? root
    }
    var visibleFocusedNode: LayoutNode? {
        func visible(_ candidate: LayoutNode?) -> LayoutNode? {
            var node = candidate
            if !isDemo { for key in unavailable { node = node?.removing(window: key) } }
            return node
        }
        return visible(focusedNode) ?? visible(current?.root)
    }
    var listedRecords: [WindowRecord] {
        isDemo ? records : records.filter { bridge.windows[$0.id] != nil && !unavailable.contains($0.id) }
    }
    var breadcrumbs: [LayoutNode] {
        guard let root = current?.root, let focus = focusedNode, let path = root.path(to: focus.id) else { return [] }
        return path.compactMap(root.node)
    }
    var canUndo: Bool { !undoStack.isEmpty }
    var isFixtureTesting: Bool { (bridge as? WindowBridge)?.allowedBundles != nil }
    var canRedo: Bool { !redoStack.isEmpty }
    var hasWindowsToRestore: Bool { !movedWindows.isEmpty || !managerMinimized.isEmpty }
    static func isDesktop(_ key: String) -> Bool { key.hasPrefix("desktop:") }
    var availableRecords: [WindowRecord] { isDemo ? records : records.filter { bridge.windows[$0.id] != nil && !unavailable.contains($0.id) } }
    var floatingRecords: [WindowRecord] {
        let managed = Set(displays.flatMap { $0.root?.allWindows ?? [] })
        return availableRecords.filter { !managed.contains($0.id) && !unavailable.contains($0.id) }
    }
    var minimized: Set<String> {
        isDemo ? [] : Set(bridge.windows.values.filter(\.minimized).map(\.id)).subtracting(managerMinimized)
    }
    var unavailable: Set<String> {
        if isDemo { return [] }
        let elsewhere = bridge.windows.values.filter { $0.fullScreen || (!$0.onScreen && !$0.minimized && !managerMinimized.contains($0.id)) }.map(\.id)
        return minimized.union(dormantWindows).union(elsewhere)
    }
    func record(_ key: String) -> WindowRecord? {
        if Self.isDesktop(key) { return WindowRecord(id: key,bundleID: "org.canopywm.desktop",app: "Desktop",title: "Floating windows and wallpaper",ordinal: 0,originalFrame: LayoutRect(width: 800,height: 600)) }
        return records.first { $0.id == key }
    }
    func openWindow(_ key: String) {
        guard let record = record(key) else { return }
        selectedWindow = key
        if let index = displays.firstIndex(where: { $0.root?.leaf(containing: key) != nil }),
           let leaf = displays[index].root?.leaf(containing: key) {
            selectedDisplay = displays[index].id
            displays[index].root?.select(window: key); focus(leaf.id)
        }
        guard !isDemo else { return }
        if bridge.windows[key]?.minimized == true { _ = bridge.setMinimized(key,false) }
        if bridge.windows[key] != nil { bridge.raise(key,activate: true) }
        NSRunningApplication.runningApplications(withBundleIdentifier: record.bundleID).first?.activate(options: [])
    }
    func icon(_ key: String) -> NSImage? { bridge.windows[key]?.icon }

    func enterDemo() {
        if !isDemo {
            if isArranging || hasWindowsToRestore { floatAll() }
            guard !hasWindowsToRestore else { return }
            realSnapshot = snapshot
        }
        isDemo = true; isArranging = false; selectedWindow = nil
        records = [
            WindowRecord(id: "demo-code", bundleID: "demo.editor", app: "Editor", title: "canopy / Layout.swift", ordinal: 0,
                originalFrame: LayoutRect(width: 900, height: 600)),
            WindowRecord(id: "demo-browser", bundleID: "demo.browser", app: "Browser", title: "Project documentation", ordinal: 0,
                originalFrame: LayoutRect(width: 900, height: 600)),
            WindowRecord(id: "demo-terminal", bundleID: "demo.terminal", app: "Terminal", title: "swift test", ordinal: 0,
                originalFrame: LayoutRect(width: 600, height: 400)),
            WindowRecord(id: "demo-notes", bundleID: "demo.notes", app: "Notes", title: "Ideas for the next release", ordinal: 0,
                originalFrame: LayoutRect(width: 600, height: 400))
        ]
        let code = LayoutNode(window: records[0].id)
        var reference = LayoutNode(window: records[1].id)
        _ = reference.dock(window: records[3].id, at: reference.id, edge: .tab)
        reference.select(window: records[1].id)
        let tools = LayoutNode(first: reference, second: LayoutNode(window: records[2].id), axis: .vertical, ratio: 0.62)
        let work = LayoutNode(first: code, second: tools, axis: .horizontal, ratio: 0.6)
        let root = LayoutNode(first: work,second: LayoutNode(window: "desktop:demo"),axis: .vertical,ratio: 0.85)
        displays = [DisplayWorkspace(id: "demo", name: "Demo workspace", root: root, focus: root.id)]
        displays[0].history.visit(root.id)
        selectedDisplay = "demo"; undoStack = []; redoStack = []
        dormantWindows = []
        message = nil
        onPause?()
    }

    func useRealWindows() {
        guard bridge.trusted else {
            bridge.requestPermission()
            message = "Enable Canopy in System Settings → Privacy & Security → Accessibility, then click Use My Windows again."
            return
        }
        if isDemo, let saved = realSnapshot { restoreSnapshot(saved) }
        isDemo = false; hasPermission = true; isArranging = false
        undoStack = []; redoStack = []; selectedWindow = nil; message = storageWarning
        synchronizeScreens(); refresh()
    }

    func refresh(applyingLayout: Bool = true) {
        hasPermission = bridge.trusted
        guard !isDemo else { return }
        guard hasPermission else {
            if isArranging { isArranging = false; message = "Accessibility access was removed. Re-enable it to restore or arrange windows." }
            return
        }
        guard !interactiveDrag else { return }
        let oldRecords = records
        let oldLayouts = displays
        var savedIDs = Set<String>()
        let candidates = (pendingRecovery+records.filter { movedWindows.contains($0.id) }+records)
            .filter { savedIDs.insert($0.id).inserted }
        let discovered = bridge.discover(saved: candidates, excluded: excludedApps)
        for (alias,canonical) in bridge.windowAliases where alias != canonical {
            for i in displays.indices {
                for g in displays[i].grids.indices {
                    if dormantWindows.contains(canonical) && !dormantWindows.contains(alias) {
                        displays[i].grids[g].root = displays[i].grids[g].root?.removing(window: canonical)
                    }
                    displays[i].grids[g].root = displays[i].grids[g].root?.remappingWindow(alias,to: canonical)
                }
            }
            if movedWindows.remove(alias) != nil { movedWindows.insert(canonical) }
            if managerMinimized.remove(alias) != nil { managerMinimized.insert(canonical) }
            if occludedWindows.remove(alias) != nil { occludedWindows.insert(canonical) }
            if recoveryMinimized.remove(alias) != nil { recoveryMinimized.insert(canonical) }
            for i in pendingRecovery.indices where pendingRecovery[i].id == alias { pendingRecovery[i].id = canonical }
            if selectedWindow == alias { selectedWindow = canonical }
        }
        var recoveryIDs = Set<String>()
        pendingRecovery = pendingRecovery.filter { recoveryIDs.insert($0.id).inserted }
        let closed = destroyedWindows.union(bridge.destroyedWindowIDs)
        movedWindows.subtract(closed); managerMinimized.subtract(closed); recoveryMinimized.subtract(closed); occludedWindows.subtract(closed)
        pendingRecovery.removeAll { closed.contains($0.id) }
        if !closed.isEmpty,message?.hasSuffix("then retry Restore Windows.") == true {
            message = movedWindows.isEmpty ? nil : "\(movedWindows.count) windows could not be restored. Check their apps and Accessibility permission, then retry Restore Windows."
        }
        let live = Set(discovered.map(\.id))
        let absent = records.filter {
            !live.contains($0.id) && bridge.windowAliases[$0.id] == nil && !excludedApps.contains($0.bundleID) && !closed.contains($0.id)
                && (bridge.preservesUnlistedWindows || !bridge.runningBundleIDs.contains($0.bundleID) || movedWindows.contains($0.id) || managerMinimized.contains($0.id) || occludedWindows.contains($0.id))
        }
        records = discovered.map(\.record)+absent
        dormantWindows = Set(absent.map(\.id))
        let retained = Set(records.map(\.id))
        var changed = records != oldRecords
        for index in displays.indices {
            for g in displays[index].grids.indices {
                for missing in (displays[index].grids[g].root?.allWindows ?? []).filter({ !retained.contains($0) && !Self.isDesktop($0) }) {
                    displays[index].grids[g].root = displays[index].grids[g].root?.removing(window: missing); changed = true
                }
            }
            normalizeFocus(index)
        }
        if let selected = selectedWindow, !live.contains(selected) { selectedWindow = nil }
        let availability = live.subtracting(unavailable)
        let routed = applyingLayout && routeFocusedWindowToWorkspace(requireNewFocus: true)
        // A title/document change updates the inspector, not desktop stacking.
        // Re-covering apps for metadata-only AX notifications causes flashing.
        if applyingLayout,!routed,isArranging && (displays != oldLayouts || lastAvailability != availability) { applyLayout() }
        lastAvailability = availability
        destroyedWindows = []
        events?.synchronize(bridge.windows)
        if changed { persist() }
    }

    /// Dock clicks, app activation, and native window selection navigate to
    /// the owning Canopy grid. They never enroll a window into another grid.
    @discardableResult func routeFocusedWindowToWorkspace(requireNewFocus: Bool = false) -> Bool {
        guard isArranging,!isDemo,!interactiveDrag,!workspaceSwitchPending,!spaceTransitionPending,
              let key = bridge.focusedWindow(),(!requireNewFocus || key != layoutFocusedWindow),let window = bridge.windows[key],
              window.onScreen,!window.minimized,!window.fullScreen else { return false }
        // Prefer an already active arrangement for shared windows.
        let connected = Set(displayDescriptors.map(\.id))
        let eligible = displays.indices.filter { connected.contains(displays[$0].id) }
        let active = eligible.first { displays[$0].root?.leaf(containing: key) != nil }
        var destination: (display: Int,grid: String)?
        if let active { destination = (active,displays[active].activeGridID) }
        else {
            let candidates = eligible.flatMap { i in
                displays[i].grids.filter { $0.root?.leaf(containing: key) != nil }.map { (display: i,grid: $0.id) }
            }
            destination = candidates.min { a,b in
                (gridActivationHistory.firstIndex(of: a.grid) ?? Int.max) < (gridActivationHistory.firstIndex(of: b.grid) ?? Int.max)
            }
        }
        guard let destination,
              let g = displays[destination.display].grids.firstIndex(where: { $0.id == destination.grid }),
              let leaf = displays[destination.display].grids[g].root?.leaf(containing: key) else { return false }
        let switching = displays[destination.display].activeGridID != destination.grid
        if !switching,lastNativeVisible.contains(key) { selectedWindow = key; return false }
        displays[destination.display].grids[g].root?.select(window: key)
        let grid = displays[destination.display].grids[g]
        if grid.focus.flatMap({ grid.root?.node($0) })?.allWindows.contains(key) != true || grid.cameraFrame != nil {
            displays[destination.display].grids[g].focus = leaf.id
            displays[destination.display].grids[g].cameraFrame = nil
        }
        selectedDisplay = displays[destination.display].id
        if switching { selectWorkspaceGrid(destination.grid,activate: true) }
        else { selectedWindow = key; applyLayout(activating: key) }
        return true
    }

    func synchronizeScreens(applyingLayout: Bool = true) {
        guard !isDemo else { return }
        for screen in screenProvider() {
            let key = screen.id
            if let legacy = screen.legacyID, let i = displays.firstIndex(where: { $0.id == legacy }) { displays[i].id = key }
            if !displays.contains(where: { $0.id == key }) {
                displays.append(DisplayWorkspace(id: key, name: screen.name))
            }
        }
        let liveIDs = Set(screenProvider().map(\.id))
        if !liveIDs.contains(selectedDisplay) { selectedDisplay = screenProvider().first?.id ?? "" }
        // Keep disconnected arrangements as dormant display workspaces. The OS moves
        // their windows to a live monitor; restoration always clamps to visible bounds.
        if applyingLayout,isArranging { applyLayout() }
    }

    func screenID(_ screen: NSScreen) -> String {
        let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        return number?.stringValue ?? screen.localizedName
    }
    var connectedDisplays: [DisplayWorkspace] {
        if isDemo { return displays }
        let ids = Set(screenProvider().map(\.id))
        return displays.filter { ids.contains($0.id) }
    }

    func autoLayoutCurrentMonitor() {
        guard !isDemo,bridge.trusted else { useRealWindows(); return }
        guard !interactiveDrag,!workspaceSwitchPending,!spaceTransitionPending else { return }
        // Discovery must not route focus to another grid or reapply other
        // monitors before we have resolved this command's local window set.
        synchronizeScreens(applyingLayout: false); refresh(applyingLayout: false)
        guard let index = displays.firstIndex(where: { $0.id == selectedDisplay }),
              let descriptor = displayDescriptors.first(where: { $0.id == selectedDisplay }) else { return }
        let descriptors = displayDescriptors
        let windows = listedRecords.filter { record in
            guard let window = bridge.windows[record.id],window.onScreen,!window.minimized,!window.fullScreen,
                  !occludedWindows.contains(record.id),let frame = bridge.frame(of: window.element),frame.isValid else { return false }
            // Largest intersection assigns a straddling window to one monitor;
            // no fallback may pull a window from an unrelated display.
            return descriptors.max { a,b in
                Self.overlapArea(frame,a.monitorBounds) < Self.overlapArea(frame,b.monitorBounds)
            }.map { $0.id == descriptor.id && Self.overlapArea(frame,$0.monitorBounds) > 0 } ?? false
        }
        guard !windows.isEmpty else { message = "No available windows on this monitor's current Desktop."; return }
        // Fixed counts make two windows side by side and four exactly 2×2,
        // including on portrait and ultrawide monitors.
        let columns = min(8,Int(ceil(sqrt(Double(windows.count)))))
        guard let root = Self.columnPreset(windows.map { LayoutNode(window: $0.id) },count: columns) else { return }
        let placements = root.placements(in: desktopViewport(descriptor),gap: gap)
        guard placements.allSatisfy({ placement in
            let minimum = bridge.minimumSize(placement.window) ?? .zero
            return placement.rect.width >= max(preferences.minimumWidth,minimum.width)
                && placement.rect.height >= max(preferences.minimumHeight,minimum.height)
        }) else { message = "These windows cannot fit on this monitor at their minimum sizes. Remove a window and try Auto Layout again."; return }
        let previous = displays
        checkpoint()
        // Retain off-Desktop and otherwise unavailable members without taking
        // geometry from the currently visible windows. Other grid tabs stay intact.
        var parked = displays[index].root
        let available = Set(listedRecords.map(\.id))
        for key in parked?.allWindows ?? [] where available.contains(key) || Self.isDesktop(key) {
            parked = parked?.removing(window: key)
        }
        displays[index].root = parked.map { LayoutNode(first: root,second: $0,axis: .horizontal) } ?? root
        displays[index].focus = root.id; displays[index].cameraFrame = nil
        normalizeFocus(index)
        selectedWindow = windows.first?.id; message = storageWarning
        // Adopt only this monitor's interrupted-session baselines. Recovering
        // the whole journal here would move windows on other monitors first.
        let enrolled = Set(windows.map(\.id))
        for recovery in pendingRecovery where enrolled.contains(recovery.id) {
            if let i = records.firstIndex(where: { $0.id == recovery.id }) { records[i].originalFrame = recovery.originalFrame }
            movedWindows.insert(recovery.id)
        }
        pendingRecovery.removeAll { enrolled.contains($0.id) }
        recoveryMinimized.subtract(enrolled)
        if !isArranging { arrangedDisplayIDs = [descriptor.id] }
        else if arrangedDisplayIDs != nil { arrangedDisplayIDs?.insert(descriptor.id) }
        isArranging = true
        persist(); applyLayout(on: descriptor.id,rollback: previous)
    }
    private static func overlapArea(_ a: LayoutRect,_ b: LayoutRect) -> Double {
        max(0,min(a.maxX,b.maxX)-max(a.x,b.x))*max(0,min(a.maxY,b.maxY)-max(a.y,b.y))
    }

    func arrange(enrollAvailable: Bool = true) {
        guard isDemo || hasPermission else { useRealWindows(); return }
        if !isDemo {
            refresh()
            guard !availableRecords.isEmpty else { return }
        }
        if !isDemo, !pendingRecovery.isEmpty {
            recoverWindows()
            // Keep unavailable apps in the journal without preventing other
            // windows on this Desktop from being arranged.
            guard !pendingRecovery.contains(where: { bridge.windows[$0.id] != nil && !unavailable.contains($0.id) }) else { return }
            message = storageWarning
        }
        arrangedDisplayIDs = nil
        checkpoint()
        var balancedDisplays = Set(displays.filter { workspace in
            workspace.root?.allWindows.filter { !unavailable.contains($0) }.allSatisfy(Self.isDesktop) ?? true
        }.map(\.id))
        if !isDemo {
            for i in displays.indices {
                let desktops = (displays[i].root?.allWindows ?? []).filter(Self.isDesktop)
                for key in desktops { displays[i].root = displays[i].root?.removing(window: key) }
                if !desktops.isEmpty { balancedDisplays.insert(displays[i].id) }
                normalizeFocus(i)
            }
        }
        for i in displays.indices where isDemo && displays[i].root == nil {
            displays[i].root = LayoutNode(window: "desktop:\(displays[i].id)")
        }
        for record in floatingRecords where enrollAvailable && !minimized.contains(record.id) {
            let destination: String
            if isDemo { destination = selectedDisplay }
            else {
                let rect = bridge.windows[record.id].flatMap { bridge.frame(of: $0.element) } ?? record.originalFrame
                destination = screenProvider().first(where: { screen in
                    let r = screen.frame
                    return rect.midX >= r.x && rect.midX <= r.x + r.width && rect.midY >= r.y && rect.midY <= r.y + r.height
                })?.id ?? selectedDisplay
            }
            guard let i = displays.firstIndex(where: { $0.id == destination }) else { continue }
            balancedDisplays.insert(destination)
            if let root = displays[i].root {
                let axis: SplitAxis = root.allWindows.count.isMultiple(of: 2) ? .vertical : .horizontal
                displays[i].root = LayoutNode(first: root, second: LayoutNode(window: record.id), axis: axis,
                    ratio: Double(root.allWindows.count) / Double(root.allWindows.count + 1))
            } else { displays[i].root = LayoutNode(window: record.id) }
            displays[i].focus = displays[i].root?.id
        }
        for i in displays.indices where balancedDisplays.contains(displays[i].id) {
            guard let root = displays[i].root,
                  let frame = displayDescriptors.first(where: { $0.id == displays[i].id })?.frame else { continue }
            let active = root.allWindows.filter { !unavailable.contains($0) }
            var seen = Set<String>()
            let leaves = active.compactMap { root.leaf(containing: $0) }.filter { seen.insert($0.id).inserted }
            let hint = bridge.preferredInitialPaneSize
            let preferred = CGSize(width: max(preferences.minimumWidth,hint.width),height: max(preferences.minimumHeight,hint.height))
            let balanced = Self.automaticArrangement(leaves,in: frame.inset(gap),preferred: preferred)
            var parked: LayoutNode? = root
            for key in active { parked = parked?.removing(window: key) }
            if let balanced,let parked {
                // Other Desktops retain their tree without consuming geometry
                // in the layout being created on this Desktop.
                displays[i].root = LayoutNode(first: balanced,second: parked,axis: .horizontal)
            } else { displays[i].root = balanced ?? parked }
            displays[i].focus = displays[i].root?.id
        }
        if !isDemo {
            // The initial arrangement must keep every active app usable.
            // A cramped saved tree should never hide apps behind miniatures.
            let plans = desktopPlans()
            let active = Set(plans.flatMap(\.placements).filter { $0.isActive && !Self.isDesktop($0.window) }.map(\.window))
            let native = Set(plans.flatMap(\.nativePlacements).map(\.window))
            guard active.isSubset(of: native) else {
                if isArranging { floatAll() }
                message = "Not enough room to arrange every window at a usable size. Focus a smaller group or remove windows from the layout, then try again."
                persist(); return
            }
            isArranging = true
        }
        commit()
    }

    func dock(_ key: String, target: String?, edge: DockEdge) {
        if !gridColumns.isEmpty,edge == .left || edge == .right {
            _ = giveWindowOwnColumn(key,beside: target,before: edge == .left); return
        }
        guard record(key) != nil,!Self.isDesktop(key),isDemo || !unavailable.contains(key), let index = displays.firstIndex(where: { $0.id == selectedDisplay }) else { return }
        if let target, displays[index].root?.node(target) == nil { return }
        if let target, edge == .tab, displays[index].root?.node(target)?.isLeaf != true { return }
        if let target,edge == .tab,displays[index].root?.node(target)?.allWindows.contains(where: Self.isDesktop) == true {
            floatWindow(key); return
        }
        // Prepare the destination before touching another display's source tree.
        let previousFocus = displays[index].focus
        var destination = displays[index].root
        if destination == nil { destination = LayoutNode(window: key) }
        else {
            guard destination!.dock(window: key, at: target ?? destination!.id, edge: edge) else { return }
        }
        checkpoint()
        for i in displays.indices where i != index {
            for g in displays[i].grids.indices { displays[i].grids[g].root = displays[i].grids[g].root?.removing(window: key) }
            normalizeFocus(i)
        }
        displays[index].root = destination
        if edge != .tab, let target, target == previousFocus,
           let path = destination?.path(to: target), path.count > 1 {
            // Keep a newly created split visible when docking into a zoomed leaf.
            displays[index].focus = path[path.count - 2]
        }
        normalizeFocus(index)
        selectedWindow = key
        commit()
    }

    func floatWindow(_ key: String, preserveCurrent: Bool = false) {
        guard !Self.isDesktop(key) else { return }
        checkpoint()
        for i in displays.indices { displays[i].root = displays[i].root?.removing(window: key); normalizeFocus(i) }
        if !isDemo, movedWindows.contains(key),!displays.contains(where: { $0.allGridWindows.contains(key) }), let record = record(key) {
            if managerMinimized.contains(key), bridge.setMinimized(key,false) { managerMinimized.remove(key) }
            if preserveCurrent || bridge.restore([record]).isEmpty { movedWindows.remove(key) }
        }
        if preserveCurrent,let i = records.firstIndex(where: { $0.id == key }),let element = bridge.windows[key]?.element,
           let frame = bridge.frame(of: element) { records[i].originalFrame = frame }
        commit()
    }

    func floatAll() {
        cancelPendingWorkspaceSwitch()
        resizeWork?.invalidate(); resizeWork = nil; isResizing = false; bridge.endLiveResize()
        verifiedLayouts = nil
        cancelEditorDrag()
        spaceVerification?.cancel(); spaceTransitionPending = false
        layoutVerification?.cancel()
        isArranging = false
        placementTargets = [:]
        onPause?()
        if !isDemo {
            refresh()
            for key in managerMinimized where bridge.setMinimized(key,false) { managerMinimized.remove(key) }
            let failures = bridge.restore(records.filter { movedWindows.contains($0.id) })
            movedWindows = failures.union(managerMinimized)
            message = !movedWindows.isEmpty ? "\(movedWindows.count) windows could not be restored. Check their apps and Accessibility permission, then retry Restore Windows." : nil
        }
        occludedWindows = []
        persist()
    }

    func resume() {
        guard !isDemo && hasPermission else { return }
        refresh()
        isArranging = true; applyLayout()
    }
    func pauseForSpaceChange() {
        cancelPendingWorkspaceSwitch()
        guard isArranging,!isDemo else { return }
        resizeWork?.invalidate(); resizeWork = nil; isResizing = false; bridge.endLiveResize()
        cancelEditorDrag()
        isArranging = false; onPause?(); persist()
        message = "Arranging paused after switching macOS Spaces. Return to the original Desktop to resume or restore your windows."
    }
    func handleSpaceChange() {
        guard isArranging,!isDemo else { refresh(); return }
        // macOS can post the notification while windows are being minimized
        // for zoom/tab changes. Keep working when a managed native window
        // remains visibly on this Desktop; pause when the desktop changed away.
        if !bridge.visibleWindowIDs.isDisjoint(with: movedWindows) { refresh(); return }
        // During a Space animation WindowServer can briefly report no visible
        // app windows. Freeze native writes and overlays until it settles.
        spaceVerification?.cancel(); layoutVerification?.cancel()
        spaceTransitionPending = true; onPause?()
        spaceVerification = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: 600_000_000) } catch { return }
            guard let self,!Task.isCancelled,self.isArranging else { return }
            self.refresh()
            self.spaceTransitionPending = false
            if self.bridge.visibleWindowIDs.isDisjoint(with: self.movedWindows) { self.pauseForSpaceChange() }
            else { self.applyLayout() }
        }
    }

    func focus(_ node: String) {
        guard let i = displays.firstIndex(where: { $0.id == selectedDisplay }), displays[i].root?.node(node) != nil else { return }
        displays[i].focus = node; displays[i].cameraFrame = nil; displays[i].history.visit(node)
        persist(); applyLayout()
    }
    func toggleFocus(_ node: String) {
        if current?.focus == node && current?.cameraFrame == nil {
            if current?.history.canGoBack == true { navigateHistory(back: true) }
            if current?.focus == node && current?.cameraFrame == nil { showEverything() }
        } else { focus(node) }
    }
    func showEverything() { if let root = current?.root { focus(root.id) } }
    func zoomOut() {
        if current?.cameraFrame != nil { showEverything(); return }
        guard let root = current?.root, let id = focusedNode?.id, let path = root.path(to: id), path.count > 1 else { return }
        focus(path[path.count - 2])
    }
    func zoomIn() {
        if let selected = selectedWindow, let leaf = current?.root?.leaf(containing: selected) { focus(leaf.id) }
        else if let first = focusedNode?.children.first { focus(first.id) }
    }
    func navigateHistory(back: Bool) {
        guard let i = displays.firstIndex(where: { $0.id == selectedDisplay }) else { return }
        while let id = back ? displays[i].history.back() : displays[i].history.forward() {
            if let frame = displays[i].historyFrames?[id] { displays[i].cameraFrame = frame; displays[i].focus = displays[i].root?.id; break }
            if displays[i].root?.node(id) != nil { displays[i].focus = id; displays[i].cameraFrame = nil; break }
        }
        persist(); applyLayout()
    }
    func saveView(_ slot: Int) {
        guard (1...9).contains(slot), let focus = focusedNode?.id, let i = displays.firstIndex(where: { $0.id == selectedDisplay }) else { return }
        displays[i].savedViews[String(slot)] = focus
        if let frame = displays[i].cameraFrame {
            if displays[i].savedFrames == nil { displays[i].savedFrames = [:] }
            displays[i].savedFrames?[String(slot)] = frame
        } else { displays[i].savedFrames?.removeValue(forKey: String(slot)) }
        persist()
    }
    func recallView(_ slot: Int) {
        if let id = current?.savedViews[String(slot)], current?.root?.node(id) != nil {
            let frame = current?.savedFrames?[String(slot)]
            if let frame { setCameraFrame(frame) } else { focus(id) }
        }
        else { message = "View \(slot) is empty. Zoom into a space and save it first." }
    }
    func selectTab(_ key: String,activate: Bool = false) {
        guard let i = displays.firstIndex(where: { $0.id == selectedDisplay }) else { return }
        displays[i].root?.select(window: key); selectedWindow = key
        persist(); applyLayout(activating: activate ? key : nil)
    }
    func selectNeighbor(_ direction: Int) {
        let ids = focusedNode?.placements(in: LayoutRect(width: 1000, height: 700), unavailable: minimized)
            .filter { $0.isActive && !Self.isDesktop($0.window) }.map(\.window) ?? []
        guard !ids.isEmpty else { return }
        let old = ids.firstIndex(of: selectedWindow ?? "") ?? 0
        selectedWindow = ids[(old + direction + ids.count) % ids.count]
        if isArranging && !isDemo, let key = selectedWindow { bridge.raise(key, activate: true) }
    }
    func beginResize() {
        if message?.hasPrefix("An app could not fit that edit") == true { message = nil }
        if !interactiveDrag { checkpoint() }
        if !isResizing,isArranging,!isDemo { bridge.beginLiveResize(lastNativeVisible) }
        interactiveDrag = true; isResizing = true
        layoutVerification?.cancel()
    }
    func resize(_ node: String, ratio: Double, finished: Bool) {
        guard let i = displays.firstIndex(where: { $0.id == selectedDisplay }) else { return }
        let value = isDemo ? ratio : constrainedResize(node,ratio: ratio)
        displays[i].root?.resize(node: node, ratio: value)
        if finished {
            resizeWork?.invalidate(); resizeWork = nil
            interactiveDrag = false
            commit() // Keep resize phase through the final geometry write.
            isResizing = false; bridge.endLiveResize()
        } else if resizeWork == nil {
            let work = Timer(timeInterval: 1.0/60,repeats: false) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.resizeWork = nil
                    guard self.isResizing else { return }
                    self.applyLayout()
                }
            }
            resizeWork = work; RunLoop.main.add(work,forMode: .common)
        }
    }
    private func constrainedResize(_ id: String,ratio: Double) -> Double {
        guard let plan = desktopPlans().first(where: { $0.display.id == selectedDisplay }),
              let node = plan.root.node(id),node.children.count == 2,let frame = plan.frames[id] else { return ratio }
        func minimum(_ node: LayoutNode) -> CGSize {
            let live = node.allWindows.filter { !unavailable.contains($0) }
            guard !live.isEmpty else { return .zero }
            if node.isLeaf {
                let sizes = live.map { bridge.minimumSize($0) ?? .zero }
                let strip = preferences.showTabStrips && live.count > 1 ? 28.0 : 0
                return CGSize(width: max(preferences.minimumWidth,sizes.map(\.width).max() ?? 0),
                              height: max(preferences.minimumHeight,sizes.map(\.height).max() ?? 0)+strip)
            }
            let sizes = node.children.filter { !$0.allWindows.allSatisfy(unavailable.contains) }.map(minimum)
            if sizes.count == 1 { return sizes[0] }
            return node.axis == .horizontal
                ? CGSize(width: sizes.reduce(0) { $0+$1.width }+gap,height: sizes.map(\.height).max() ?? 0)
                : CGSize(width: sizes.map(\.width).max() ?? 0,height: sizes.reduce(0) { $0+$1.height }+gap)
        }
        let first = minimum(node.children[0]),second = minimum(node.children[1])
        let extent = max(1,(node.axis == .horizontal ? frame.width : frame.height)-gap)
        let lower = max(0.1,(node.axis == .horizontal ? first.width : first.height)/extent)
        let upper = min(0.9,1-(node.axis == .horizontal ? second.width : second.height)/extent)
        return lower <= upper ? min(upper,max(lower,ratio)) : node.ratio
    }
    func undo() {
        guard let state = undoStack.popLast() else { return }
        let oldManaged = Set(displays.flatMap { $0.allGridWindows })
        redoStack.append(displays); displays = state
        pruneMissingWindows(); restoreNewlyFloating(oldManaged); commit()
    }
    func redo() {
        guard let state = redoStack.popLast() else { return }
        let oldManaged = Set(displays.flatMap { $0.allGridWindows })
        undoStack.append(displays); displays = state
        pruneMissingWindows(); restoreNewlyFloating(oldManaged); commit()
    }
    private func restoreNewlyFloating(_ previous: Set<String>) {
        let current = Set(displays.flatMap { $0.allGridWindows })
        if !isDemo {
            let removed = previous.subtracting(current).intersection(movedWindows)
            occludedWindows.subtract(removed)
            for key in removed { placementTargets.removeValue(forKey: key) }
            for key in removed.intersection(managerMinimized) where bridge.setMinimized(key,false) { managerMinimized.remove(key) }
            let failures = bridge.restore(records.filter { removed.contains($0.id) })
            movedWindows.subtract(removed.subtracting(failures))
        }
    }
    func excludeApp(_ bundle: String) {
        let removed = records.filter { $0.bundleID == bundle }
        for record in removed { floatWindow(record.id) }
        excludedApps.insert(bundle); refresh(); persist()
    }
    func includeApp(_ bundle: String) { excludedApps.remove(bundle); refresh(); persist() }
    func updateGap(_ value: Double) { gap = min(32, max(0, value)); persist(); applyLayout() }

    func applyLayout(activating keyToActivate: String? = nil,on displayID: String? = nil,rollback: [DisplayWorkspace]? = nil) {
        guard !workspaceSwitchPending else { return }
        guard isArranging, !isDemo, bridge.trusted, !spaceTransitionPending else { return }
        if !isResizing,let focused = bridge.focusedWindow(),let window = bridge.windows[focused],window.fullScreen {
            let monitor = bridge.frame(of: window.element).flatMap { frame in
                displayDescriptors.max { Self.overlapArea(frame,$0.monitorBounds) < Self.overlapArea(frame,$1.monitorBounds) }?.id
            }
            if displayID == nil || monitor == displayID { onPause?(); return }
        }
        layoutVerification?.cancel()
        let plans = desktopPlans()
        layoutDisplayScope = displayID
        defer { layoutDisplayScope = nil }
        let affectedPlans = plans.filter { displayID == nil || $0.display.id == displayID }
        let native = affectedPlans.flatMap(\.nativePlacements)
        let previouslyMoved = movedWindows
        let previousOcclusion = occludedWindows
        let previousFrames = displayID == nil ? [:] : Dictionary(native.compactMap { placement -> (String,LayoutRect)? in
            guard let element = bridge.windows[placement.window]?.element,let frame = bridge.frame(of: element) else { return nil }
            return (placement.window,frame)
        },uniquingKeysWith: { first,_ in first })
        let visible = Set(native.map(\.window))
        applyingGeometryOnly = isResizing && visible == lastNativeVisible
        defer { applyingGeometryOnly = false }
        if isResizing,!applyingGeometryOnly { bridge.endLiveResize() }
        let affectedDisplays = Set(affectedPlans.map { $0.display.id })
        let managed = Set(displays.filter { affectedDisplays.contains($0.id) }.flatMap { $0.allGridWindows }).subtracting(unavailable).filter { key in
            guard let window = bridge.windows[key] else { return false }
            guard let displayID else { return true }
            if visible.contains(key) { return true }
            guard let frame = bridge.frame(of: window.element) else { return false }
            return displayDescriptors.max { Self.overlapArea(frame,$0.monitorBounds) < Self.overlapArea(frame,$1.monitorBounds) }?.id == displayID
        }
        for key in managed where !applyingGeometryOnly && (displayID == nil || visible.contains(key)) {
                if !movedWindows.contains(key) {
                    // Capture immediately before the first move this session, never from an old saved frame.
                    if let i = records.firstIndex(where: { $0.id == key }),
                       let element = bridge.windows[key]?.element,
                       let frame = bridge.frame(of: element) { records[i].originalFrame = frame }
                    movedWindows.insert(key)
                }
        }
        // Save restoration baselines before touching the desktop, including a first arrangement.
        if !applyingGeometryOnly { persist() }
        onLayoutWillApply?(plans)
        // Upgrade older sessions once. Workspace changes never minimize windows.
        if !applyingGeometryOnly {
            for key in managerMinimized where (displayID == nil || managed.contains(key)) && bridge.setMinimized(key,false) { managerMinimized.remove(key) }
        }
        var moved = 0
        if applyingGeometryOnly {
            bridge.resizeLiveWindows(Dictionary(native.map { ($0.window,$0.rect) },uniquingKeysWith: { _,new in new }))
            for placement in native { placementTargets[placement.window] = placement.rect }
        } else {
            for placement in native {
                let current = bridge.windows[placement.window].flatMap { bridge.frame(of: $0.element) }
                if placementTargets[placement.window] != placement.rect || current.map({ !WindowBridge.frameFitsCell($0,in: placement.rect) }) != false {
                    _ = bridge.move(placement.window,to: placement.rect); moved += 1
                    placementTargets[placement.window] = placement.rect
                }
            }
        }
        if displayID == nil { occludedWindows = managed.subtracting(visible) }
        else { occludedWindows.subtract(managed); occludedWindows.formUnion(managed.subtracting(visible)) }
        // Activate before raising peers: raising a background app while the
        // outgoing app is still active can leave it below that outgoing app.
        if !applyingGeometryOnly {
            if let keyToActivate,visible.contains(keyToActivate) { bridge.raise(keyToActivate,activate: true) }
            for placement in native { bridge.raise(placement.window,activate: false) }
            if let keyToActivate,visible.contains(keyToActivate) { bridge.raise(keyToActivate,activate: false) }
            layoutFocusedWindow = bridge.focusedWindow()
        }
        lastNativeVisible = Set(plans.flatMap(\.nativePlacements).map(\.window))
        if isResizing,!applyingGeometryOnly { bridge.beginLiveResize(visible) }
        #if DEBUG
        lastNativeMoveCount = moved
        let diagnostic: [String:Any] = ["time":ProcessInfo.processInfo.systemUptime,"grid":currentGridName,"moves":moved,
            "visible":native.count,"occluded":occludedWindows.count,"minimizations":0]
        if !isResizing,let data = try? JSONSerialization.data(withJSONObject: diagnostic,options: [.sortedKeys]) {
            try? data.write(to: FileManager.default.temporaryDirectory.appendingPathComponent("canopy-layer-switch.json"),options: .atomic)
        }
        #endif
        if !applyingGeometryOnly { persist() }
        onLayoutDidApply?(plans)
        guard !interactiveDrag else { return }
        let appliedLayouts = displays
        layoutVerification = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: 800_000_000) } catch { return }
            guard let self,!Task.isCancelled,self.isArranging else { return }
            let failures = native.filter { !self.bridge.verifyMove($0.window,to: $0.rect) }.count
            guard !Task.isCancelled else { return }
            if failures > 0 {
                if let displayID {
                    // A rejected quick layout may pause only its own monitor.
                    // Never use the global restore path for a monitor-local edit.
                    if let old = (rollback ?? self.verifiedLayouts)?.first(where: { $0.id == displayID }),
                       let index = self.displays.firstIndex(where: { $0.id == displayID }) { self.displays[index] = old }
                    let newlyMoved = visible.subtracting(previouslyMoved)
                    let failedRestores = self.bridge.restore(self.records.filter { newlyMoved.contains($0.id) })
                    self.movedWindows.subtract(newlyMoved.subtracting(failedRestores))
                    for (key,frame) in previousFrames where previouslyMoved.contains(key) { _ = self.bridge.move(key,to: frame) }
                    for key in visible { self.placementTargets.removeValue(forKey: key) }
                    self.occludedWindows.subtract(managed); self.occludedWindows.formUnion(previousOcclusion.intersection(managed))
                    self.arrangedDisplayIDs = Set(plans.map { $0.display.id }).subtracting([displayID])
                    self.isArranging = self.arrangedDisplayIDs?.isEmpty == false
                    if let rollback,self.undoStack.last == rollback { self.undoStack.removeLast() }
                    self.verifiedLayouts = nil
                    self.message = "Auto Layout paused on this monitor because an app resisted resizing. Other monitors were left alone."
                    if self.isArranging {
                        self.layoutDisplayScope = displayID
                        let remaining = self.desktopPlans()
                        self.onLayoutWillApply?(remaining); self.onLayoutDidApply?(remaining)
                        self.layoutDisplayScope = nil
                    } else { self.onPause?() }
                    self.persist(); return
                }
                if self.fitExplicitColumnWidths() { self.persist(); self.applyLayout(); return }
                if let previous = self.verifiedLayouts {
                    self.verifiedLayouts = nil
                    let failedManaged = Set(self.displays.flatMap { $0.allGridWindows })
                    self.displays = previous
                    self.restoreNewlyFloating(failedManaged)
                    if self.undoStack.last == previous { self.undoStack.removeLast() }
                    self.onPause?()
                    self.message = "An app could not fit that edit. The previous layout is still active."
                    self.commit()
                    return
                }
                // Stop overlays before restoring. Never turn an unsuccessful
                // resize into a miniature that hides the user's actual app.
                self.floatAll()
                let recovery = self.message
                self.message = "Arrangement paused because \(failures) windows resisted resizing. " + (recovery ?? "Your windows were restored.")
            } else { self.verifiedLayouts = appliedLayouts }
        }
    }

    func handleURL(_ url: URL) {
        guard url.scheme == "canopy" else { return }
        let components = URLComponents(url: url,resolvingAgainstBaseURL: false)
        let query = Dictionary((components?.queryItems ?? []).map { ($0.name,$0.value ?? "") },uniquingKeysWith: { _,new in new })
        if let display = query["display"] {
            guard let match = displays.first(where: { $0.id == display || $0.name == display }) else { message = "The requested display is not available."; return }
            selectedDisplay = match.id
        }
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        switch url.host {
        case "arrange": if !isDemo { applyCurrentGrid() }
        case "float":
            if !path.isEmpty,record(path) != nil { floatWindow(path) } else { floatAll() }
        case "pause": floatAll()
        case "resume": resume()
        case "everything": showEverything()
        case "desktop": focusDesktop()
        case "frame": frameFocusedWindow()
        case "zoom-in": zoomIn()
        case "zoom-out": zoomOut()
        case "back": navigateHistory(back: true)
        case "forward": navigateHistory(back: false)
        case "next": selectNeighbor(1)
        case "previous": selectNeighbor(-1)
        case "undo": undo()
        case "redo": redo()
        case "overview": onRequestCamera?()
        case "recover": recoverWindows()
        case "view": if let slot = Int(path) { recallView(slot) }
        case "save": if let slot = Int(path) { saveView(slot) }
        case "clear-view":
            if let slot = Int(path),(1...9).contains(slot),let i = displays.firstIndex(where: { $0.id == selectedDisplay }) {
                displays[i].savedViews.removeValue(forKey: path); displays[i].savedFrames?.removeValue(forKey: path); persist()
            }
        case "focus":
            if current?.root?.node(path) != nil { focus(path) }
        case "select": if record(path) != nil { selectTab(path) }
        case "dock":
            let key = query["window"].flatMap { $0 == "focused" ? bridge.focusedWindow() ?? selectedWindow : $0 } ?? selectedWindow
            guard let key,record(key) != nil,let edge = DockEdge(rawValue: query["edge"] ?? "right") else { message = "Dock requires a valid window and edge."; return }
            let target = query["target"] ?? focusedNode?.id
            if query["group"] == "true",let source = displays.compactMap({ $0.root?.leaf(containing: key) }).first {
                dock(source.windows,intent: DockIntent(display: selectedDisplay,target: target,edge: edge,preview: LayoutRect(width: 1,height: 1)),wholeGroup: true)
            } else { dock(key,target: target,edge: edge) }
        default: message = "Unknown command. Supported commands are listed in the README."
        }
    }
    func shutdown() {
        layoutVerification?.cancel()
        timer?.invalidate()
        if !isDemo { floatAll(); persist() }
        events?.stop(); onPause?()
    }
    func checkpoint() {
        if message?.hasPrefix("An app could not fit that edit") == true { message = nil }
        undoStack.append(displays); if undoStack.count > 40 { undoStack.removeFirst() }; redoStack = []
    }
    func commit() { persist(); applyLayout() }
    private func pruneMissingWindows() {
        let live = Set(records.map(\.id))
        for i in displays.indices {
            for g in displays[i].grids.indices {
                for key in displays[i].grids[g].root?.allWindows ?? [] where !live.contains(key) && !Self.isDesktop(key) {
                    displays[i].grids[g].root = displays[i].grids[g].root?.removing(window: key)
                }
            }
            normalizeFocus(i)
        }
    }
    private func normalizeFocus(_ i: Int) {
        for g in displays[i].grids.indices {
            let root = displays[i].grids[g].root
            if let focus = displays[i].grids[g].focus,root?.node(focus) == nil { displays[i].grids[g].focus = root?.id }
            displays[i].grids[g].savedViews = displays[i].grids[g].savedViews.filter { root?.node($0.value) != nil }
        }
    }
    var currentGridName: String { current?.grids.first { $0.id == current?.activeGridID }?.name ?? "Grid" }
    var currentGridWindowIDs: Set<String> { Set(current?.root?.allWindows.filter { !Self.isDesktop($0) } ?? []) }
    func applyCurrentGrid() {
        guard !currentGridWindowIDs.isEmpty else { return }
        arrange(enrollAvailable: false)
    }
    func addWindowsToCurrentGrid(_ keys: [String]) {
        guard let i = displays.firstIndex(where: { $0.id == selectedDisplay }) else { return }
        let eligible = Set(availableRecords.map(\.id))
        var seen = currentGridWindowIDs
        let added = keys.filter { eligible.contains($0) && seen.insert($0).inserted }
        guard !added.isEmpty else { return }
        checkpoint()
        if let root = displays[i].root,!root.layoutColumns.isEmpty {
            displays[i].root = addToExplicitColumns(added,root: root)
            displays[i].focus = displays[i].root?.id; displays[i].cameraFrame = nil
            selectedWindow = added.last; _ = fitExplicitColumnWidths(); commit(); return
        }
        var leaves: [LayoutNode] = []; var leafIDs = Set<String>()
        if let root = displays[i].root {
            for key in root.allWindows {
                if let leaf = root.leaf(containing: key),leafIDs.insert(leaf.id).inserted { leaves.append(leaf) }
            }
        }
        leaves += added.map { LayoutNode(window: $0) }
        let frame = displayDescriptors.first { $0.id == selectedDisplay }?.frame ?? LayoutRect(width: 1280,height: 800)
        let hint = bridge.preferredInitialPaneSize
        displays[i].root = Self.automaticArrangement(leaves,in: frame.inset(gap),preferred: CGSize(width: max(preferences.minimumWidth,hint.width),height: max(preferences.minimumHeight,hint.height)))
        displays[i].focus = displays[i].root?.id; displays[i].cameraFrame = nil
        selectedWindow = added.last; commit()
    }
    func removeWindowFromCurrentGrid(_ key: String) {
        guard currentGridWindowIDs.contains(key),let i = displays.firstIndex(where: { $0.id == selectedDisplay }) else { return }
        checkpoint(); let previous = Set(displays.flatMap { $0.allGridWindows })
        displays[i].root = displays[i].root?.removing(window: key); normalizeFocus(i)
        if selectedWindow == key { selectedWindow = nil }
        restoreNewlyFloating(previous); commit()
    }
    func transferWindow(_ key: String,toGrid gridID: String) {
        guard !Self.isDesktop(key),availableRecords.contains(where: { $0.id == key }),
              let i = displays.firstIndex(where: { $0.id == selectedDisplay }),gridID != displays[i].activeGridID,
              let g = displays[i].grids.firstIndex(where: { $0.id == gridID }) else { return }
        checkpoint()
        let alreadyThere = displays[i].grids[g].root?.allWindows.contains(key) == true
        if !alreadyThere {
            let root = displays[i].grids[g].root
            if let root,!root.layoutColumns.isEmpty {
                displays[i].grids[g].root = addToExplicitColumns([key],root: root)
            } else {
            var leaves: [LayoutNode] = []; var seen = Set<String>()
            for member in root?.allWindows ?? [] {
                if let leaf = root?.leaf(containing: member),seen.insert(leaf.id).inserted { leaves.append(leaf) }
            }
            leaves.append(LayoutNode(window: key))
            let frame = displayDescriptors.first { $0.id == selectedDisplay }?.frame ?? LayoutRect(width: 1280,height: 800)
            let hint = bridge.preferredInitialPaneSize
            displays[i].grids[g].root = Self.automaticArrangement(leaves,in: frame.inset(gap),preferred: CGSize(width: max(preferences.minimumWidth,hint.width),height: max(preferences.minimumHeight,hint.height)))
        }
        }
        displays[i].root = displays[i].root?.removing(window: key); normalizeFocus(i)
        displays[i].activeGridID = gridID
        displays[i].focus = displays[i].root?.id; displays[i].cameraFrame = nil
        selectedWindow = key; verifiedLayouts = nil; commit()
    }
    func addWorkspaceGrid(duplicating: Bool = false) {
        guard let i = displays.firstIndex(where: { $0.id == selectedDisplay }),displays[i].grids.count < 32 else { return }
        cancelEditorDrag(); checkpoint()
        var grid = duplicating ? displays[i].grids.first { $0.id == displays[i].activeGridID }! : WorkspaceGrid(name: "",root: nil,focus: nil)
        grid.id = UUID().uuidString
        let names = Set(displays[i].grids.map(\.name)); var number = 1
        while names.contains("Grid \(number)") { number += 1 }
        grid.name = "Grid \(number)"
        displays[i].grids.append(grid); displays[i].activeGridID = grid.id
        verifiedLayouts = nil; selectedWindow = nil; commit()
    }
    func cancelPendingWorkspaceSwitch() {
        workspaceSwitchGeneration += 1; workspaceSwitchPending = false
    }
    func cycleWorkspace(_ delta: Int) {
        guard let workspace = current else { return }
        let live = Set(listedRecords.map(\.id))
        let grids = workspace.grids.filter { $0.root?.allWindows.contains(where: { live.contains($0) && !Self.isDesktop($0) }) == true }
        guard !grids.isEmpty else { return }
        let index = grids.firstIndex { $0.id == workspace.activeGridID } ?? (delta >= 0 ? -1 : 0)
        let destination = (index+delta%grids.count+grids.count)%grids.count
        selectWorkspaceGrid(grids[destination].id,activate: true)
    }
    func selectWorkspaceGrid(_ id: String,activate: Bool = false) {
        guard let i = displays.firstIndex(where: { $0.id == selectedDisplay }),displays[i].activeGridID != id,
              displays[i].grids.contains(where: { $0.id == id }) else { return }
        resizeWork?.invalidate(); resizeWork = nil; isResizing = false; bridge.endLiveResize()
        cancelEditorDrag(); displays[i].activeGridID = id
        gridActivationHistory.removeAll { $0 == id }; gridActivationHistory.insert(id,at: 0)
        gridActivationHistory = Array(gridActivationHistory.prefix(64))
        verifiedLayouts = nil; selectedWindow = nil; layoutVerification?.cancel(); persist()
        workspaceSwitchGeneration += 1; let generation = workspaceSwitchGeneration
        let apply = { [weak self] in
            guard let self,self.workspaceSwitchGeneration == generation else { return }
            self.workspaceSwitchPending = false
            let native = self.desktopPlans().first { $0.display.id == self.selectedDisplay }?.nativePlacements ?? []
            let focused = self.bridge.focusedWindow()
            let key = native.first { $0.window == focused }?.window ?? native.first?.window
            self.applyLayout(activating: activate ? key : nil)
        }
        if isArranging,!isDemo,let onWorkspaceSwitch {
            workspaceSwitchPending = true; onWorkspaceSwitch(apply)
        } else { apply() }
    }
    func renameWorkspaceGrid(_ id: String,name: String) {
        let value = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60))
        guard !value.isEmpty,let i = displays.firstIndex(where: { $0.id == selectedDisplay }),
              let g = displays[i].grids.firstIndex(where: { $0.id == id }),displays[i].grids[g].name != value else { return }
        checkpoint(); displays[i].grids[g].name = value; commit()
    }
    func closeWorkspaceGrid(_ id: String) {
        guard let i = displays.firstIndex(where: { $0.id == selectedDisplay }),displays[i].grids.count > 1,
              let g = displays[i].grids.firstIndex(where: { $0.id == id }) else { return }
        cancelEditorDrag(); checkpoint()
        let previous = Set(displays.flatMap { $0.allGridWindows })
        displays[i].grids.remove(at: g)
        if displays[i].activeGridID == id { displays[i].activeGridID = displays[i].grids[min(g,displays[i].grids.count-1)].id }
        restoreNewlyFloating(previous); verifiedLayouts = nil; commit()
    }
    var snapshot: WorkspaceSnapshot {
        var recovery = records.filter { movedWindows.contains($0.id) }
        recovery += pendingRecovery.filter { entry in !recovery.contains { $0.id == entry.id } }
        return WorkspaceSnapshot(displays: displays,records: records,excludedApps: excludedApps,gap: gap,
            preferences: preferences,recoveryWindows: recovery,recoveryMinimized: managerMinimized.union(recoveryMinimized))
    }
    func restoreSnapshot(_ state: WorkspaceSnapshot) {
        displays = state.displays; records = state.records; excludedApps = state.excludedApps; gap = state.gap
        preferences = state.preferences ?? UserPreferences()
        preferences.shortcuts = ShortcutBinding.addingMissingDefaults(to: preferences.shortcuts)
        pendingRecovery = state.recoveryWindows ?? []; recoveryMinimized = state.recoveryMinimized ?? []
    }
    private func load() {
        guard FileManager.default.fileExists(atPath: persistenceURL.path) else { return }
        do {
            let size = (try FileManager.default.attributesOfItem(atPath: persistenceURL.path)[.size] as? NSNumber)?.intValue ?? 0
            guard size <= 8*1024*1024 else { throw CocoaError(.fileReadTooLarge) }
            let state = try JSONDecoder().decode(WorkspaceSnapshot.self, from: Data(contentsOf: persistenceURL))
            guard (1...4).contains(state.version) else {
                canPersist = false
                message = "This workspace was saved by a newer version of Canopy. Saving is disabled to preserve it."
                storageWarning = message
                return
            }
            try Self.validate(state)
            restoreSnapshot(state)
        } catch {
            canPersist = false
            message = "The saved workspace could not be read. Saving is disabled to preserve the file: \(error.localizedDescription)"
            storageWarning = message
        }
    }
    func resetWorkspace() {
        guard !isDemo else { return }
        if !pendingRecovery.isEmpty { recoverWindows(); guard pendingRecovery.isEmpty else { return } }
        floatAll(); guard !hasWindowsToRestore else { return }
        do {
            let backup = try backupWorkspace()
            canPersist = true; storageWarning = nil; displays = []; records = []; pendingRecovery = []; recoveryMinimized = []
            synchronizeScreens(); refresh(); persist()
            message = backup.map { "Workspace reset. The previous file is preserved at \($0.path)." } ?? "Workspace reset."
        } catch { message = "Could not back up the workspace: \(error.localizedDescription)" }
    }
    func storageWasReplaced() { canPersist = true; storageWarning = nil }
    func persist() {
        guard !isDemo, canPersist else { return }
        do {
            try FileManager.default.createDirectory(at: persistenceURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(snapshot).write(to: persistenceURL, options: .atomic)
        } catch { message = "Could not save this workspace: \(error.localizedDescription)" }
    }
}
