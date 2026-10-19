import AppKit
import Combine
import CanopyCore

extension LayoutRect {
    var nsRect: NSRect { NSRect(x: x,y: y,width: width,height: height) }
}

@MainActor
final class OverlayPanel: NSPanel {
    init(rect: LayoutRect, interactive: Bool, view: NSView) {
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        super.init(contentRect: NSRect(x: rect.x,y: top-rect.maxY,width: max(1,rect.width),height: max(1,rect.height)),
            styleMask: [.borderless,.nonactivatingPanel],backing: .buffered,defer: false)
        isOpaque = false; backgroundColor = .clear; hasShadow = false
        animationBehavior = .none
        level = .floating; hidesOnDeactivate = false; isReleasedWhenClosed = false
        collectionBehavior = [.transient,.ignoresCycle]
        ignoresMouseEvents = !interactive; contentView = view
        setAccessibilityLabel("Canopy desktop controls")
    }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class DesktopCoordinator {
    private weak var store: WorkspaceStore?
    let previews = PreviewCache()
    private var tokens: [AnyCancellable] = []
    private var globalMonitor: Any?
    private var keyMonitor: Any?
    private var panels: [OverlayPanel] = []
    private var workspaceBackgrounds: [String: OverlayPanel] = [:]
    private var layerRestack: Timer?
    private var backgroundGeneration = 0
    private var switchingWorkspace = false
    #if DEBUG
    private var layerChecks: [[String:Any]] = []
    private var nativeAuditStarted = false
    private var backgroundOrderCalls = 0
    private var resizeOrderBaseline: Int?
    private var resizeFrameCount = 0
    private var dragTrace: [[String:Any]] = []
    #endif
    private var workspaceBars: [String: OverlayPanel] = [:]
    private var dockPreview: OverlayPanel?
    private var cameraPanel: OverlayPanel?
    private var cameraView: DesktopCameraView?
    private var transitions: [OverlayPanel] = []
    private var oldPlans: [DesktopLayoutPlan] = []
    private var pendingPlans: [DesktopLayoutPlan] = []
    private var updateWork: DispatchWorkItem?
    private var transitionGeneration = 0
    private var nativeDragPoll: Timer?
    private var dragging: DragSession?
    private var isInteracting = false
    private var framingFromDesktop = false

    private struct DragSession {
        var keys: [String]
        var wholeGroup: Bool
        var original: LayoutRect
        var start: CGPoint
        var originDisplay: String?
        var explicit: Bool
        var floating = false
        var didMove = false
        var intent: DockIntent?
    }

    init(store: WorkspaceStore) {
        self.store = store
        store.onWorkspaceSwitch = { [weak self] apply in
            guard let self else { apply(); return }
            self.cancelTransitions()
            self.switchingWorkspace = true
            #if DEBUG
            let started = ProcessInfo.processInfo.systemUptime
            #endif
            NSAnimationContext.beginGrouping()
            NSAnimationContext.current.duration = 0
            NSAnimationContext.current.allowsImplicitAnimation = false
            defer { NSAnimationContext.endGrouping(); self.switchingWorkspace = false }
            apply()
            #if DEBUG
            let elapsed = ProcessInfo.processInfo.systemUptime-started
            DispatchQueue.main.asyncAfter(deadline: .now()+0.33) { [weak self] in self?.recordLayerCheck(elapsed: elapsed) }
            #endif
        }
        store.onLayoutWillApply = { [weak self] plans in self?.prepare(plans) }
        store.onLayoutDidApply = { [weak self] plans in self?.finish(plans) }
        store.onPause = { [weak self] in self?.hideDesktop() }
        previews.onImagesChanged = { [weak self,weak store] in
            guard let self,let store else { return }
            store.previews = self.previews.images; store.previewStatus = self.previews.status
            self.cameraView?.needsDisplay = true
            for panel in self.panels { panel.contentView?.needsDisplay = true }
        }
        store.objectWillChange.sink { [weak self] _ in self?.scheduleUpdate() }.store(in: &tokens)
        for name in [NSWindow.didBecomeKeyNotification,NSWindow.willCloseNotification,NSWindow.didMiniaturizeNotification,NSWindow.didDeminiaturizeNotification] {
            NotificationCenter.default.publisher(for: name).sink { [weak self] notification in
                if (notification.object as? NSWindow)?.title == "Canopy" { self?.scheduleUpdate() }
            }.store(in: &tokens)
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown,.leftMouseDragged,.leftMouseUp,.magnify]) { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
        }
        update()
    }

    private func scheduleUpdate() {
        updateWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.update() }
        updateWork = work; DispatchQueue.main.asyncAfter(deadline: .now()+0.08,execute: work)
    }
    private func update() {
        guard let store else { return }
        let visible = NSApp.windows.contains { $0.title == "Canopy" && $0.isVisible && !$0.isMiniaturized }
        previews.update(windows: Array(store.bridge.windows.values),enabled: store.preferences.previewsEnabled && !store.isDemo && (store.isArranging || visible))
        if store.previewStatus != previews.status { store.previewStatus = previews.status }
        guard store.isArranging,!store.isDemo,store.hasPermission else { hideDesktop(); return }
        if keyMonitor == nil {
            keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if event.keyCode == 53,self.dragging != nil {
                        self.nativeDragPoll?.invalidate(); self.nativeDragPoll = nil
                        self.dragging = nil; self.dockPreview?.close(); self.dockPreview = nil
                        self.isInteracting = false; self.store?.interactiveDrag = false
                        self.store?.applyLayout(); self.scheduleUpdate(); return
                    }
                    guard self.cameraPanel != nil else { return }
                    if event.keyCode == 53 { self.closeCamera(); self.scheduleUpdate() }
                    else if event.keyCode == 36 { self.cameraView?.commitCamera() }
                }
            }
        }
        if isFullScreenApplication { store.cancelPendingWorkspaceSwitch(); for panel in panels + Array(workspaceBars.values) + Array(workspaceBackgrounds.values) { panel.orderOut(nil) }; closeCamera(); return }
        guard !isInteracting,!store.interactiveDrag,cameraPanel == nil else { return }
        positionBackgroundsBehindActive(store.desktopPlans())
        installControls(store.desktopPlans())
    }
    private var isFullScreenApplication: Bool {
        guard let store,let key = store.bridge.focusedWindow() else { return false }
        return store.bridge.windows[key]?.fullScreen == true
    }
    private func prepare(_ plans: [DesktopLayoutPlan]) {
        cancelTransitions()
        if store?.applyingGeometryOnly == true {
            #if DEBUG
            if resizeOrderBaseline == nil { resizeOrderBaseline = backgroundOrderCalls; resizeFrameCount = 0 }
            resizeFrameCount += 1
            #endif
            backgroundGeneration += 1; layerRestack?.invalidate(); layerRestack = nil
            return
        }
        stackWorkspaceBackgrounds(plans)
        guard !switchingWorkspace else { return }
        guard let store,!isInteracting,!store.interactiveDrag,cameraPanel == nil,store.preferences.animations,
              !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,!oldPlans.isEmpty else { return }
        for plan in plans {
            let previous = oldPlans.first { $0.display.id == plan.display.id }
            guard let previous else { continue }
            guard DesktopTransitionView.shouldAnimate(old: previous,new: plan,images: store.previews) else { continue }
            let view = DesktopTransitionView(old: previous,new: plan,store: store,duration: store.preferences.animationDuration)
            let panel = OverlayPanel(rect: plan.display.frame,interactive: false,view: view)
            transitions.append(panel); panel.orderFrontRegardless(); view.displayIfNeeded()
        }
    }
    /// A normal-level surface separates live inactive windows from the active grid.
    /// It consumes empty-area clicks so they cannot reach windows behind it.
    private func stackWorkspaceBackgrounds(_ plans: [DesktopLayoutPlan]) {
        guard store != nil else { return }
        for id in Array(workspaceBackgrounds.keys) where !plans.contains(where: { $0.display.id == id }) {
            workspaceBackgrounds.removeValue(forKey: id)?.close()
        }
        for plan in plans {
            let rect = plan.display.frame
            let panel: OverlayPanel
            if let existing = workspaceBackgrounds[plan.display.id] { panel = existing }
            else {
                panel = OverlayPanel(rect: rect,interactive: true,view: WorkspaceBackgroundView(display: plan.display))
                panel.title = "Canopy workspace background"
                panel.level = .normal; panel.isFloatingPanel = false
                panel.isOpaque = true
                panel.setAccessibilityElement(false)
                workspaceBackgrounds[plan.display.id] = panel
            }
            let top = NSScreen.screens.first?.frame.maxY ?? 0
            panel.setFrame(NSRect(x: rect.x,y: top-rect.maxY,width: rect.width,height: rect.height),display: false)
            panel.orderFrontRegardless()
            #if DEBUG
            backgroundOrderCalls += 1
            #endif
        }
    }
    private var floatingWindows: [DiscoveredWindow] {
        guard let store else { return [] }
        let managed = Set(store.displays.flatMap { $0.allGridWindows })
        return store.bridge.windows.values.filter { !managed.contains($0.id) && $0.onScreen && !$0.minimized && !$0.fullScreen }
    }
    private func raiseFloatingWindows(_ plans: [DesktopLayoutPlan]) {
        guard let store else { return }
        let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly,.excludeDesktopElements],kCGNullWindowID) as? [[String:Any]] ?? []
        let floating = floatingWindows
        for item in info.reversed() {
            guard let number = (item[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                  let window = floating.first(where: { $0.windowNumber == number }) else { continue }
            store.bridge.raise(window.id,activate: false)
        }
        // Floating windows are common to all grids. Keep the selected grid
        // in front of them after the destination app has been activated.
        for placement in plans.flatMap(\.nativePlacements) { store.bridge.raise(placement.window,activate: false) }
    }
    private func positionBackgroundsBehindActive(_ plans: [DesktopLayoutPlan]) {
        guard let store else { return }
        let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly,.excludeDesktopElements],kCGNullWindowID) as? [[String:Any]] ?? []
        let order = info.compactMap { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value }
        for plan in plans {
            let floating = floatingWindows.filter { window in
                store.bridge.frame(of: window.element).map { plan.display.frame.contains(x: $0.midX,y: $0.midY) } ?? false
            }
            let active = Set(plan.nativePlacements.compactMap { store.bridge.windows[$0.window]?.windowNumber } + floating.compactMap(\.windowNumber))
            if let last = order.last(where: active.contains) {
                if let background = workspaceBackgrounds[plan.display.id] {
                    #if DEBUG
                    backgroundOrderCalls += 1
                    #endif
                    if !NativeWorkspaceStacking.place(background,below: last) {
                        background.order(.below,relativeTo: Int(last))
                    }
                }
            }
        }
    }
    private func settleNativeStack(_ plans: [DesktopLayoutPlan]) {
        layerRestack?.invalidate()
        let generation = backgroundGeneration
        let until = ProcessInfo.processInfo.systemUptime+0.3
        let timer = Timer(timeInterval: 1.0/60,repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self,self.backgroundGeneration == generation,self.store?.isArranging == true,
                      !self.isFullScreenApplication else { timer.invalidate(); return }
                guard let store = self.store else { timer.invalidate(); return }
                let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly,.excludeDesktopElements],kCGNullWindowID) as? [[String:Any]] ?? []
                let order = info.compactMap { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value }
                let desired = plans.flatMap(\.nativePlacements).compactMap { store.bridge.windows[$0.window]?.windowNumber } + self.floatingWindows.compactMap(\.windowNumber)
                let hidden = store.occludedWindows.compactMap { store.bridge.windows[$0]?.windowNumber }
                let lastVisible = desired.compactMap { order.firstIndex(of: $0) }.max() ?? -1
                let firstHidden = hidden.compactMap { order.firstIndex(of: $0) }.min() ?? Int.max
                if firstHidden < lastVisible { self.raiseFloatingWindows(plans) }
                self.positionBackgroundsBehindActive(plans)
                if ProcessInfo.processInfo.systemUptime >= until { timer.invalidate() }
            }
        }
        layerRestack = timer
        RunLoop.main.add(timer,forMode: .common)
    }
    #if DEBUG
    private func recordLayerCheck(elapsed: Double) {
        guard let store else { return }
        let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly,.excludeDesktopElements],kCGNullWindowID) as? [[String:Any]] ?? []
        let order = info.compactMap { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value }
        let rows = store.desktopPlans().map { plan -> [String:Any] in
            let surface = workspaceBackgrounds[plan.display.id].flatMap { order.firstIndex(of: UInt32($0.windowNumber)) }
            let active = plan.nativePlacements.compactMap { store.bridge.windows[$0.window] }
            let floats = floatingWindows.filter { window in
                store.bridge.frame(of: window.element).map { plan.display.frame.contains(x: $0.midX,y: $0.midY) } ?? false
            }
            let inactive = store.occludedWindows.compactMap { store.bridge.windows[$0] }.filter { window in
                store.bridge.frame(of: window.element).map { plan.display.frame.contains(x: $0.midX,y: $0.midY) } ?? false
            }
            return ["activeCount":active.count,"inactiveCount":inactive.count,
                "floatingCount":floats.count,
                "floatingAboveBackground":floats.allSatisfy { window in
                    guard let surface,let number = window.windowNumber,let index = order.firstIndex(of: number) else { return false }
                    return index < surface && !window.minimized
                },
                "surfaceIndex":surface ?? -1,
                "surfaceLevel":workspaceBackgrounds[plan.display.id]?.level.rawValue ?? -1,
                "surfaceServerLevel":workspaceBackgrounds[plan.display.id].flatMap { panel in info.first { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value == UInt32(panel.windowNumber) }?[kCGWindowLayer as String] } ?? -1,
                "activeServerLevels":active.map { w in info.first { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value == w.windowNumber }?[kCGWindowLayer as String] as? Int ?? -1 },
                "activeIndices":active.map { $0.windowNumber.flatMap { order.firstIndex(of: $0) } ?? -1 },
                "inactiveIndices":inactive.map { $0.windowNumber.flatMap { order.firstIndex(of: $0) } ?? -1 },
                "activeAppsHidden":active.map { NSRunningApplication(processIdentifier: $0.pid)?.isHidden ?? false },
                "activeAboveBackground":active.allSatisfy { window in
                    guard let surface,let number = window.windowNumber,let index = order.firstIndex(of: number) else { return false }
                    return index < surface && !window.minimized
                },
                "inactiveBelowBackground":inactive.allSatisfy { window in
                    guard let surface,let number = window.windowNumber,let index = order.firstIndex(of: number) else { return false }
                    return index > surface && !window.minimized
                }]
        }
        layerChecks.append(["grid":store.currentGridName,"nativeMoveCalls":store.lastNativeMoveCount,"managedWindowsMinimized":store.movedWindows.compactMap { store.bridge.windows[$0] }.filter(\.minimized).count,"nativeTransactionMilliseconds":elapsed*1000,"displays":rows])
        layerChecks = Array(layerChecks.suffix(50))
        if let data = try? JSONSerialization.data(withJSONObject: layerChecks,options: [.sortedKeys]) {
            try? data.write(to: FileManager.default.temporaryDirectory.appendingPathComponent("canopy-layer-checks.json"),options: .atomic)
        }
    }
    #endif
    private func finish(_ plans: [DesktopLayoutPlan]) {
        if store?.applyingGeometryOnly == true {
            pendingPlans = plans; oldPlans = plans
            updateControlFrames(plans)
            if store?.interactiveDrag == false {
                installControls(plans)
                #if DEBUG
                let report: [String:Any] = ["geometryUpdates":resizeFrameCount,
                    "workspaceBackgroundOrdersDuringResize":backgroundOrderCalls-(resizeOrderBaseline ?? backgroundOrderCalls),
                    "nativeWindowCount":plans.flatMap(\.nativePlacements).count]
                if let data = try? JSONSerialization.data(withJSONObject: report,options: [.sortedKeys]) {
                    try? data.write(to: FileManager.default.temporaryDirectory.appendingPathComponent("canopy-live-resize.json"),options: .atomic)
                }
                resizeOrderBaseline = nil
                #endif
            }
            return
        }
        #if DEBUG
        if !nativeAuditStarted,Bundle.main.object(forInfoDictionaryKey: "CanopyNativeSwitchAudit") as? Bool == true {
            nativeAuditStarted = true
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self,let store = self.store,store.isArranging,let workspace = store.current,workspace.grids.count >= 2 else { return }
                let grids = Array(workspace.grids.prefix(2))
                for index in 0..<8 {
                    guard store.isArranging else { break }
                    store.selectWorkspaceGrid(grids[index%2].id,activate: true)
                    try? await Task.sleep(nanoseconds: 400_000_000)
                }
            }
        }
        #endif
        pendingPlans = plans; oldPlans = plans
        raiseFloatingWindows(plans)
        positionBackgroundsBehindActive(plans)
        backgroundGeneration += 1
        let generation = backgroundGeneration
        settleNativeStack(plans)
        // AX activation can enqueue its final restack. Correct only our own
        // surface on the next turn; never replay a stale workspace or move apps.
        DispatchQueue.main.async { [weak self] in
            guard let self,self.backgroundGeneration == generation,self.store?.isArranging == true else { return }
            self.positionBackgroundsBehindActive(plans)
        }
        if NSWorkspace.shared.frontmostApplication?.processIdentifier == getpid() {
            for window in NSApp.windows where window.isVisible && window.title == "Canopy" { window.orderFront(nil) }
        }
        if transitions.isEmpty { if !isInteracting { installControls(plans) }; return }
        let token = transitionGeneration
        var remaining = transitions.count
        for panel in transitions {
            guard let view = panel.contentView as? DesktopTransitionView else { continue }
            view.start { [weak self,weak panel] in
                panel?.close(); remaining -= 1
                guard let self,remaining == 0,token == self.transitionGeneration else { return }
                self.transitions = []; self.installControls(self.pendingPlans)
            }
        }
    }
    private func updateControlFrames(_ plans: [DesktopLayoutPlan]) {
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        for panel in panels {
            var rect: LayoutRect?
            if let view = panel.contentView as? DesktopSeamView,
               let seam = plans.flatMap(\.seams).first(where: { $0.node == view.seam.node }) {
                view.update(seam: seam); rect = seam.rect
            } else if let view = panel.contentView as? DesktopTabsView,
                      let frame = plans.compactMap({ $0.frames[view.node.id] }).first {
                rect = LayoutRect(x: frame.x,y: frame.y,width: frame.width,height: 28)
            } else if let view = panel.contentView as? MiniatureView {
                rect = plans.compactMap { $0.frames[view.node.id] }.first
            }
            if let rect { panel.setFrame(NSRect(x: rect.x,y: top-rect.maxY,width: rect.width,height: rect.height),display: false) }
        }
    }
    private func installControls(_ plans: [DesktopLayoutPlan]) {
        guard let store,!isInteracting,!store.interactiveDrag,cameraPanel == nil,store.isArranging,!isFullScreenApplication else { return }
        for panel in panels { panel.close() }; panels = []
        for id in Array(workspaceBars.keys) where !plans.contains(where: { $0.display.id == id }) {
            workspaceBars.removeValue(forKey: id)?.close()
        }
        for plan in plans {
            if let workspace = store.displays.first(where: { $0.id == plan.display.id }) {
                let bar = (workspaceBars[plan.display.id]?.contentView as? DesktopWorkspaceBar) ?? DesktopWorkspaceBar(grids: workspace.grids,active: workspace.activeGridID)
                bar.update(grids: workspace.grids,active: workspace.activeGridID)
                bar.onSelect = { [weak store] id in store?.selectedDisplay = plan.display.id; store?.selectWorkspaceGrid(id,activate: true) }
                bar.onOpen = { [weak store] in store?.onOpenWorkspace?() }
                let rect = LayoutRect(x: plan.display.frame.x,y: plan.display.frame.y,width: plan.display.frame.width,height: DesktopWorkspaceBar.height)
                let panel = workspaceBars[plan.display.id] ?? OverlayPanel(rect: rect,interactive: true,view: bar)
                let top = NSScreen.screens.first?.frame.maxY ?? 0
                panel.setFrame(NSRect(x: rect.x,y: top-rect.maxY,width: rect.width,height: rect.height),display: true)
                panel.title = "Canopy Workspaces"
                panel.setAccessibilityLabel("Canopy Workspaces")
                workspaceBars[plan.display.id] = panel; panel.orderFrontRegardless()
                #if DEBUG
                let diagnostic: [String:Any] = ["windowNumber":panel.windowNumber,"frame":[rect.x,rect.y,rect.width,rect.height],"gridNames":workspace.grids.map(\.name)]
                if let data = try? JSONSerialization.data(withJSONObject: diagnostic,options: [.sortedKeys]) {
                    try? data.write(to: FileManager.default.temporaryDirectory.appendingPathComponent("canopy-workspace-bar.json"),options: .atomic)
                }
                #endif
            }
            for id in plan.miniatureNodes {
                guard let rect = plan.frames[id]?.intersection(plan.display.frame),let node = plan.root.node(id) else { continue }
                let view = MiniatureView(node: node,store: store) { [weak store] in
                    store?.selectedDisplay = plan.display.id; store?.focus(id)
                }
                addPanel(rect: rect,view: view)
            }
            for placement in plan.placements where placement.isActive && !plan.miniatureNodes.contains(where: { plan.root.node($0)?.node(placement.node) != nil }) {
                guard let node = plan.root.node(placement.node) else { continue }
                if WorkspaceStore.isDesktop(placement.window) {
                    let view = DesktopPlaceView { [weak store] in
                        guard let store else { return }
                        store.selectedDisplay = plan.display.id
                        if store.current?.focus == node.id { store.navigateHistory(back: true) } else { store.focus(node.id) }
                    }
                    // Floating apps occupy this plane. A full-plane panel
                    // would intercept their clicks, even with a translucent fill.
                    if node.id != plan.root.id {
                        addPanel(rect: Self.desktopControlRect(in: placement.rect),view: view)
                    }
                } else if node.windows.count > 1 && store.preferences.showTabStrips {
                    let rect = LayoutRect(x: placement.rect.x,y: placement.rect.y,width: placement.rect.width,height: 28)
                    let view = DesktopTabsView(node: node,store: store)
                    view.onSelect = { [weak self,weak store] key in
                        self?.isInteracting = false; store?.selectedDisplay = plan.display.id; store?.selectTab(key,activate: true)
                    }
                    view.onBeginDrag = { [weak self,weak store] keys,group,point in
                        store?.selectedDisplay = plan.display.id; self?.beginOverlayDrag(keys,wholeGroup: group,point: point)
                    }
                    view.onDrag = { [weak self] point in self?.updateDrag(point,option: true) }
                    view.onEndDrag = { [weak self] point in self?.endDrag(point) }
                    view.onTracking = { [weak self] value in self?.isInteracting = value }
                    addPanel(rect: rect,view: view)
                }
            }
            for seam in plan.seams where seam.rect.intersection(plan.display.frame) != nil {
                let view = DesktopSeamView(seam: seam)
                view.onBegin = { [weak self,weak store] in
                    self?.isInteracting = true
                    store?.selectedDisplay = plan.display.id; store?.beginResize()
                }
                view.onResize = { [weak self,weak store] ratio,finished in
                    if finished { self?.isInteracting = false }
                    store?.resize(seam.node,ratio: ratio,finished: finished)
                }
                addPanel(rect: seam.rect,view: view)
            }
        }
    }
    private func addPanel(rect: LayoutRect,view: NSView) {
        let panel = OverlayPanel(rect: rect,interactive: true,view: view)
        panels.append(panel); panel.orderFrontRegardless()
    }
    static func desktopControlRect(in rect: LayoutRect) -> LayoutRect {
        LayoutRect(x: rect.x,y: rect.y,width: min(120,rect.width),height: min(32,rect.height))
    }
    private func cancelTransitions() {
        transitionGeneration += 1
        for panel in transitions {
            (panel.contentView as? DesktopTransitionView)?.stop()
            panel.close()
        }
        transitions = []
    }
    private func hideDesktop() {
        store?.cancelPendingWorkspaceSwitch()
        backgroundGeneration += 1
        layerRestack?.invalidate(); layerRestack = nil
        for panel in workspaceBackgrounds.values { panel.orderOut(nil); panel.close() }; workspaceBackgrounds = [:]
        cancelTransitions()
        for panel in panels { panel.close() }
        panels = []; oldPlans = []
        for panel in workspaceBars.values { panel.close() }; workspaceBars = [:]
        dockPreview?.close(); dockPreview = nil
        closeCamera()
        nativeDragPoll?.invalidate(); nativeDragPoll = nil
        dragging = nil; isInteracting = false; store?.interactiveDrag = false
    }

    static func screenPoint(_ point: NSPoint = NSEvent.mouseLocation) -> CGPoint {
        CGPoint(x: point.x,y: (NSScreen.screens.first?.frame.maxY ?? 0)-point.y)
    }
    private func windowAt(_ point: CGPoint) -> DiscoveredWindow? {
        guard let store else { return nil }
        let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let order = CGWindowListCopyWindowInfo([.optionOnScreenOnly,.excludeDesktopElements],kCGNullWindowID) as? [[String:Any]] ?? []
        let ranks = Dictionary(order.enumerated().compactMap { index,item -> (CGWindowID,Int)? in
            guard let number = (item[kCGWindowNumber as String] as? NSNumber)?.uint32Value else { return nil }
            return (number,index)
        },uniquingKeysWith: min)
        // An app from another Canopy grid can be brought forward through the
        // Dock and dragged into this grid. Its old membership must not prevent
        // hit testing. Native stacking chooses the actually visible source;
        // clicks on our covering background never reach this global monitor.
        return store.bridge.windows.values.filter { !$0.minimized && !$0.fullScreen && $0.onScreen && $0.windowNumber.map { ranks[$0] != nil } == true && store.bridge.frame(of: $0.element)?.contains(x: point.x,y: point.y) == true }
            .sorted { a,b in
                let ar = a.windowNumber.flatMap { ranks[$0] } ?? Int.max,br = b.windowNumber.flatMap { ranks[$0] } ?? Int.max
                if ar != br { return ar < br }
                if (a.pid == front) != (b.pid == front) { return a.pid == front }
                return a.id < b.id
            }.first
    }
    private func handle(_ event: NSEvent) {
        // Global events can arrive after the pointer has moved again. Use the
        // event's WindowServer position for hit testing, not the latest cursor.
        let point = event.cgEvent?.location ?? Self.screenPoint()
        #if DEBUG
        if event.type == .leftMouseDown {
            if dragTrace.count > 60 { dragTrace.removeFirst(dragTrace.count-60) }
            dragTrace.append(["phase":"down","point":[point.x,point.y],"arranging":store?.isArranging ?? false,
                "trusted":store?.hasPermission ?? false,"fullScreen":isFullScreenApplication])
            writeDragTrace()
        }
        #endif
        guard let store,store.isArranging,!store.isDemo,store.hasPermission,!isFullScreenApplication else { return }
        if framingFromDesktop,event.type == .leftMouseDragged { cameraView?.updateScreenFrame(point); return }
        if framingFromDesktop,event.type == .leftMouseUp { cameraView?.finishScreenFrame(point); framingFromDesktop = false; return }
        if event.type == .magnify {
            guard store.preferences.globalGestures,event.modifierFlags.contains(.option) || windowAt(point) == nil else { return }
            if cameraPanel == nil { showCamera(at: point) }
            cameraView?.consumeMagnification(event.magnification,atScreen: point,ended: event.phase == .ended || event.phase == .cancelled)
            return
        }
        if event.type == .leftMouseDown {
            let window = windowAt(point)
            #if DEBUG
            dragTrace.append(["phase":"hit","window":window?.record.bundleID ?? "none",
                "frame":window.flatMap { store.bridge.frame(of: $0.element) }.map { [$0.x,$0.y,$0.width,$0.height] } ?? [],
                "docking":store.preferences.desktopDocking])
            writeDragTrace()
            #endif
            if window == nil,event.modifierFlags.contains(.shift),store.preferences.globalGestures {
                showCamera(at: point); framingFromDesktop = cameraView != nil; cameraView?.beginScreenFrame(point); return
            }
            if event.clickCount == 2,store.preferences.globalGestures {
                if window == nil { store.focusDesktop(); return }
                if let window,let frame = store.bridge.frame(of: window.element),point.y < frame.y+30,
                   let display = store.displays.first(where: { $0.root?.leaf(containing: window.id) != nil }),let leaf = display.root?.leaf(containing: window.id) {
                    store.selectedDisplay = display.id; store.toggleFocus(leaf.id); return
                }
            }
            // Unified toolbars have app-specific draggable regions, often below
            // the first 34 points. Arm on the window, then require actual native
            // frame movement before showing a preview or changing membership.
            guard store.preferences.desktopDocking,let window,let frame = store.bridge.frame(of: window.element) else { return }
            let display = store.displayDescriptors.first { $0.frame.contains(x: frame.midX,y: frame.midY) }?.id
            dragging = DragSession(keys: [window.id],wholeGroup: false,original: frame,start: point,originDisplay: display,
                explicit: false,floating: !store.currentGridWindowIDs.contains(window.id))
            nativeDragPoll?.invalidate()
            let poll = Timer(timeInterval: 1.0/60,repeats: true) { [weak self] timer in
                MainActor.assumeIsolated {
                    guard let self,self.dragging != nil else { timer.invalidate(); return }
                    let point = Self.screenPoint()
                    if NSEvent.pressedMouseButtons & 1 == 0 { self.endDrag(point) }
                    else { self.updateDrag(point,option: NSEvent.modifierFlags.contains(.option)) }
                }
            }
            nativeDragPoll = poll; RunLoop.main.add(poll,forMode: .common)
        } else if event.type == .leftMouseDragged { updateDrag(point,option: event.modifierFlags.contains(.option)) }
        else if event.type == .leftMouseUp { endDrag(point) }
    }
    private func beginOverlayDrag(_ keys: [String],wholeGroup: Bool,point: CGPoint) {
        guard let store,let first = keys.first else { return }
        let original = store.bridge.windows[first].flatMap { store.bridge.frame(of: $0.element) } ?? LayoutRect(x: point.x,y: point.y,width: 300,height: 200)
        dragging = DragSession(keys: keys,wholeGroup: wholeGroup,original: original,start: point,originDisplay: store.selectedDisplay,explicit: true)
        isInteracting = true; store.interactiveDrag = true
    }
    private func updateDrag(_ point: CGPoint,option: Bool) {
        guard let store,var session = dragging,session.explicit || hypot(point.x-session.start.x,point.y-session.start.y) >= 5 else { return }
        if !session.explicit,let first = session.keys.first,let window = store.bridge.windows[first],let frame = store.bridge.frame(of: window.element) {
            guard abs(frame.x-session.original.x)+abs(frame.y-session.original.y) >= 3 else { return }
        }
        session.didMove = true; isInteracting = true; store.interactiveDrag = true
        #if DEBUG
        if dragging?.didMove == false { dragTrace.append(["phase":"moved","floating":session.floating]); writeDragTrace() }
        #endif
        if session.floating || option || !store.preferences.dockingRequiresOption || session.explicit {
            session.intent = store.desktopPlans().lazy.compactMap { plan in
                DockResolver.resolve(x: point.x,y: point.y,display: plan.display.id,screen: store.desktopViewport(plan.display),
                    root: plan.root,frames: plan.frames,excluding: Set(session.keys))
            }.first
            if let intent = session.intent,let target = intent.target,
               store.displays.first(where: { $0.id == intent.display })?.root?.node(target)?.allWindows.contains(where: WorkspaceStore.isDesktop) == true,
               intent.edge == .tab { session.intent = nil }
        } else { session.intent = nil }
        let previous = dragging?.intent
        dragging = session
        guard previous != session.intent else { return }
        guard let intent = session.intent else { dockPreview?.orderOut(nil); return }
        let empty = intent.target.flatMap { target in store.desktopPlans().first { $0.display.id == intent.display }?.root.node(target)?.isSpacer } ?? true
        let label = empty ? "Fill slot" : intent.edge == .tab ? "Add to slot as tab" : "Split \(intent.edge.rawValue)"
        let panel: OverlayPanel
        if let existing = dockPreview { panel = existing; (panel.contentView as? DockPreviewView)?.label = label }
        else { panel = OverlayPanel(rect: intent.preview,interactive: false,view: DockPreviewView(label: label)); dockPreview = panel }
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        panel.setFrame(NSRect(x: intent.preview.x,y: top-intent.preview.maxY,width: intent.preview.width,height: intent.preview.height),display: false)
        panel.contentView?.needsDisplay = true; panel.orderFrontRegardless()
    }
    private func endDrag(_ point: CGPoint) {
        nativeDragPoll?.invalidate(); nativeDragPoll = nil
        if dragging != nil { updateDrag(point,option: dragging?.explicit == true || NSEvent.modifierFlags.contains(.option)) }
        guard let store,let session = dragging else { isInteracting = false; return }
        #if DEBUG
        dragTrace.append(["phase":"up","point":[point.x,point.y],"moved":session.didMove,"edge":session.intent?.edge.rawValue ?? "none"])
        writeDragTrace()
        #endif
        dragging = nil; isInteracting = false; store.interactiveDrag = false
        dockPreview?.close(); dockPreview = nil
        guard session.didMove else { scheduleUpdate(); return }
        if let intent = session.intent { store.dock(session.keys,intent: intent,wholeGroup: session.wholeGroup) }
        else if let destination = store.displayDescriptors.first(where: { $0.frame.contains(x: point.x,y: point.y) }),
                destination.id != session.originDisplay,let root = store.displays.first(where: { $0.id == destination.id })?.root {
            store.dock(session.keys,intent: DockIntent(display: destination.id,target: root.id,edge: .right,preview: destination.frame),wholeGroup: session.wholeGroup)
        } else {
            for key in session.keys { store.floatWindow(key,preserveCurrent: !session.explicit) }
        }
        store.refresh(); scheduleUpdate()
    }
    #if DEBUG
    private func writeDragTrace() {
        guard let data = try? JSONSerialization.data(withJSONObject: dragTrace,options: [.sortedKeys]) else { return }
        try? data.write(to: FileManager.default.temporaryDirectory.appendingPathComponent("canopy-native-drag.json"),options: .atomic)
    }
    #endif

    func showCamera(at point: CGPoint? = nil) {
        let pointer = point ?? Self.screenPoint()
        guard let store,store.isArranging,!store.isDemo,let display = store.displayDescriptors.first(where: { $0.frame.contains(x: Double(pointer.x),y: Double(pointer.y)) }),
              let workspace = store.displays.first(where: { $0.id == display.id }),let root = workspace.root else { return }
        closeCamera()
        for panel in panels + Array(workspaceBars.values) { panel.orderOut(nil) }
        let world = LayoutRect(width: display.frame.width,height: display.frame.height)
        let focus = workspace.cameraFrame ?? workspace.focus.flatMap { root.frames(in: world,gap: store.gap,unavailable: store.unavailable)[$0] } ?? world
        let view = DesktopCameraView(root: root,display: display,world: world,camera: CameraViewport(frame: focus),store: store)
        view.onFocus = { [weak self,weak store] id in
            self?.closeCamera(); store?.selectedDisplay = display.id; store?.focus(id)
        }
        view.onFrame = { [weak self,weak store] rect in
            self?.closeCamera(); store?.selectedDisplay = display.id; store?.setCameraFrame(rect,display: display.id)
        }
        view.onCancel = { [weak self] in self?.closeCamera(); self?.scheduleUpdate() }
        let panel = OverlayPanel(rect: display.frame,interactive: true,view: view)
        cameraView = view; cameraPanel = panel; panel.orderFrontRegardless()
    }
    private func closeCamera() { cameraView?.stop(); cameraPanel?.close(); cameraPanel = nil; cameraView = nil; framingFromDesktop = false }
    func enablePreviews(_ enabled: Bool) {
        guard let store else { return }
        if enabled && !previews.authorized && !previews.requestPermission() {
            store.message = "Enable Canopy under Privacy & Security → Screen Recording, then enable previews again."
            return
        }
        store.updatePreferences { $0.previewsEnabled = enabled }; update()
    }
    func stop() {
        updateWork?.cancel(); previews.stop(); hideDesktop(); tokens = []
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor); self.globalMonitor = nil }
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor); self.keyMonitor = nil }
    }
}

@MainActor
class FlippedOverlayView: NSView {
    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var acceptsFirstResponder: Bool { true }
    func text(_ text: String,in rect: NSRect,size: CGFloat = 12,color: NSColor = .labelColor,weight: NSFont.Weight = .regular) {
        let style = NSMutableParagraphStyle(); style.lineBreakMode = .byTruncatingTail
        (text as NSString).draw(in: rect,withAttributes: [.font:NSFont.systemFont(ofSize: size,weight: weight),.foregroundColor:color,.paragraphStyle:style])
    }
    func image(_ image: NSImage,in rect: NSRect) { image.draw(in: rect,from: .zero,operation: .sourceOver,fraction: 1,respectFlipped: true,hints: [.interpolation:NSImageInterpolation.high]) }
}

@MainActor
final class MiniatureView: FlippedOverlayView {
    let node: LayoutNode
    weak var store: WorkspaceStore?
    let onFocus: () -> Void
    init(node: LayoutNode,store: WorkspaceStore,onFocus: @escaping () -> Void) {
        self.node = node; self.store = store; self.onFocus = onFocus; super.init(frame: .zero)
        setAccessibilityElement(true); setAccessibilityRole(.button); setAccessibilityLabel("Zoom into \(store.record(node.activeWindow ?? "")?.app ?? "space")")
    }
    required init?(coder: NSCoder) { return nil }
    override func accessibilityPerformPress() -> Bool { onFocus(); return true }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.controlBackgroundColor.setFill(); NSBezierPath(roundedRect: bounds,xRadius: 8,yRadius: 8).fill()
        guard let store else { return }
        let key = node.activeWindow ?? node.allWindows.first ?? ""
        if let preview = store.previews[key] { image(preview,in: bounds.insetBy(dx: 3,dy: 3)) }
        else if let icon = store.icon(key) ?? NSImage(systemSymbolName: WorkspaceStore.isDesktop(key) ? "desktopcomputer" : "square.split.2x2",accessibilityDescription: nil) {
            let side = max(12,min(48,min(bounds.width,bounds.height)-18))
            image(icon,in: NSRect(x: (bounds.width-side)/2,y: (bounds.height-side)/2,width: side,height: side))
        }
        if !node.isLeaf {
            NSColor.separatorColor.setStroke()
            let frames = node.frames(in: LayoutRect(width: bounds.width,height: bounds.height),gap: 2)
            for rect in frames.values { NSBezierPath(rect: rect.nsRect).stroke() }
        }
        if bounds.width > 120 && bounds.height > 70 {
            NSColor.windowBackgroundColor.withAlphaComponent(0.92).setFill(); NSBezierPath(rect: NSRect(x: 0,y: bounds.height-24,width: bounds.width,height: 24)).fill()
            text(store.record(key)?.app ?? "Space",in: NSRect(x: 10,y: bounds.height-21,width: bounds.width-20,height: 18),weight: .medium)
        }
    }
    override func mouseDown(with event: NSEvent) { onFocus() }
    override func keyDown(with event: NSEvent) { if event.keyCode == 36 { onFocus() } else { super.keyDown(with: event) } }
}

@MainActor
final class DesktopPlaceView: FlippedOverlayView {
    let onFocus: () -> Void
    init(onFocus: @escaping () -> Void) {
        self.onFocus = onFocus; super.init(frame: .zero)
        setAccessibilityElement(true); setAccessibilityRole(.button); setAccessibilityLabel("Focus Desktop; activate again to go back")
    }
    required init?(coder: NSCoder) { return nil }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.withAlphaComponent(0.75).setFill(); NSBezierPath(roundedRect: bounds,xRadius: 8,yRadius: 8).fill()
        if let icon = NSImage(systemSymbolName: "desktopcomputer",accessibilityDescription: nil) {
            image(icon,in: NSRect(x: 8,y: 7,width: 18,height: 18))
        }
        text("Desktop",in: NSRect(x: 32,y: 7,width: max(0,bounds.width-36),height: 18))
    }
    override func mouseDown(with event: NSEvent) { onFocus() }
    override func accessibilityPerformPress() -> Bool { onFocus(); return true }
}

@MainActor
final class DockPreviewView: FlippedOverlayView {
    var label: String
    init(label: String) { self.label = label; super.init(frame: .zero) }
    required init?(coder: NSCoder) { return nil }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.controlAccentColor.withAlphaComponent(0.22).setFill()
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 2,dy: 2),xRadius: 10,yRadius: 10); path.fill()
        NSColor.controlAccentColor.setStroke(); path.lineWidth = 3; path.stroke()
        text(label,in: NSRect(x: 16,y: 16,width: bounds.width-32,height: 24),size: 15,weight: .semibold)
    }
}
