import AppKit
import CanopyCore

@MainActor
final class DesktopTabsView: FlippedOverlayView {
    let node: LayoutNode
    weak var store: WorkspaceStore?
    var onSelect: ((String) -> Void)?
    var onBeginDrag: (([String],Bool,CGPoint) -> Void)?
    var onDrag: ((CGPoint) -> Void)?
    var onEndDrag: ((CGPoint) -> Void)?
    var onTracking: ((Bool) -> Void)?
    private var down: NSPoint?
    private var selected: String?
    private var wholeGroup = false
    private var dragging = false
    init(node: LayoutNode,store: WorkspaceStore) {
        self.node = node; self.store = store; super.init(frame: .zero)
        setAccessibilityElement(true); setAccessibilityRole(.tabGroup)
        setAccessibilityLabel("Window tabs: \(node.windows.compactMap { store.record($0)?.app }.joined(separator: ", "))")
    }
    required init?(coder: NSCoder) { return nil }
    private var tabWidth: CGFloat { max(1,(bounds.width-18)/CGFloat(max(1,node.windows.count))) }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill(); NSBezierPath(roundedRect: bounds,xRadius: 5,yRadius: 5).fill()
        NSColor.secondaryLabelColor.setFill()
        for y in [8.0,13.0,18.0] { NSBezierPath(ovalIn: NSRect(x: 7,y: y,width: 3,height: 3)).fill() }
        for (index,key) in node.windows.enumerated() {
            let rect = NSRect(x: 18+CGFloat(index)*tabWidth,y: 0,width: tabWidth,height: bounds.height)
            if key == node.activeWindow { NSColor.selectedContentBackgroundColor.withAlphaComponent(0.18).setFill(); NSBezierPath(rect: rect).fill() }
            if let icon = store?.icon(key) { image(icon,in: NSRect(x: rect.minX+7,y: 6,width: 16,height: 16)) }
            text(store?.record(key)?.app ?? "Window",in: NSRect(x: rect.minX+28,y: 6,width: max(1,rect.width-34),height: 18),weight: key == node.activeWindow ? .semibold : .regular)
        }
    }
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow,from: nil)
        down = point; wholeGroup = point.x < 18 || event.modifierFlags.contains(.shift)
        let index = min(node.windows.count-1,max(0,Int((point.x-18)/tabWidth)))
        selected = node.windows[index]; dragging = false; onTracking?(true)
    }
    override func mouseDragged(with event: NSEvent) {
        guard let down,let selected else { return }
        let point = convert(event.locationInWindow,from: nil)
        guard hypot(point.x-down.x,point.y-down.y) > 5 else { return }
        let screen = DesktopCoordinator.screenPoint()
        if !dragging { dragging = true; onBeginDrag?(wholeGroup ? node.windows : [selected],wholeGroup,screen) }
        onDrag?(screen)
    }
    override func mouseUp(with event: NSEvent) {
        onTracking?(false)
        if dragging { onEndDrag?(DesktopCoordinator.screenPoint()) }
        else if let selected { onSelect?(selected) }
        down = nil; selected = nil; dragging = false
    }
    override func accessibilityPerformIncrement() -> Bool { chooseNeighbor(1); return true }
    override func accessibilityPerformDecrement() -> Bool { chooseNeighbor(-1); return true }
    override func accessibilityChildren() -> [Any]? {
        node.windows.enumerated().map { index,key in
            let element = AccessibleWindowTab()
            element.setAccessibilityRole(.radioButton)
            element.setAccessibilityLabel(store?.record(key)?.app ?? "Window")
            element.setAccessibilityValue(key == node.activeWindow ? 1 : 0)
            element.setAccessibilityParent(self)
            let rect = NSRect(x: 18+CGFloat(index)*tabWidth,y: 0,width: tabWidth,height: bounds.height)
            if let window { element.setAccessibilityFrame(window.convertToScreen(convert(rect,to: nil))) }
            element.press = { [weak self] in self?.onSelect?(key) }
            return element
        }
    }
    private func chooseNeighbor(_ delta: Int) {
        let current = node.windows.firstIndex(of: node.activeWindow ?? "") ?? 0
        onSelect?(node.windows[(current+delta+node.windows.count)%node.windows.count])
    }
}

@MainActor
private final class AccessibleWindowTab: NSAccessibilityElement {
    var press: (() -> Void)?
    override func accessibilityPerformPress() -> Bool { press?(); return true }
}

@MainActor
final class DesktopSeamView: FlippedOverlayView {
    private(set) var seam: SplitSeam
    var onBegin: (() -> Void)?
    var onResize: ((Double,Bool) -> Void)?
    private var down: CGPoint?
    private var downSeam: SplitSeam?
    init(seam: SplitSeam) {
        self.seam = seam; super.init(frame: .zero)
        setAccessibilityElement(true); setAccessibilityRole(.slider)
        setAccessibilityLabel("Resize \(seam.axis.rawValue) space split")
        setAccessibilityValue(seam.ratio)
    }
    required init?(coder: NSCoder) { return nil }
    override func resetCursorRects() { addCursorRect(bounds,cursor: seam.axis == .horizontal ? .resizeLeftRight : .resizeUpDown) }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.withAlphaComponent(0.75).setFill(); NSBezierPath(rect: bounds).fill()
        NSColor.secondaryLabelColor.withAlphaComponent(0.45).setFill()
        let r = seam.axis == .horizontal ? NSRect(x: max(0,bounds.width/2-1.5),y: max(0,bounds.height/2-16),width: 3,height: min(32,bounds.height))
            : NSRect(x: max(0,bounds.width/2-16),y: max(0,bounds.height/2-1.5),width: min(32,bounds.width),height: 3)
        NSBezierPath(roundedRect: r,xRadius: 1.5,yRadius: 1.5).fill()
    }
    override func mouseDown(with event: NSEvent) {
        onBegin?(); down = DesktopCoordinator.screenPoint(); downSeam = seam
        if event.clickCount >= 2 { onResize?(0.5,true); down = nil; downSeam = nil }
    }
    override func mouseDragged(with event: NSEvent) { if let ratio = ratio() { onResize?(ratio,false) } }
    override func mouseUp(with event: NSEvent) { if let ratio = ratio() { onResize?(ratio,true) }; down = nil; downSeam = nil }
    private func ratio() -> Double? {
        guard let down,let seam = downSeam else { return nil }
        let current = DesktopCoordinator.screenPoint()
        let delta = seam.axis == .horizontal ? current.x-down.x : current.y-down.y
        let extent = seam.axis == .horizontal ? seam.parent.width-seam.rect.width : seam.parent.height-seam.rect.height
        return seam.ratio+delta/max(1,extent)
    }
    func update(seam: SplitSeam) {
        self.seam = seam; setAccessibilityValue(seam.ratio); needsDisplay = true
    }
    override func accessibilityPerformIncrement() -> Bool { onBegin?(); onResize?(min(0.9,seam.ratio+0.05),true); return true }
    override func accessibilityPerformDecrement() -> Bool { onBegin?(); onResize?(max(0.1,seam.ratio-0.05),true); return true }
}

@MainActor
final class DesktopCameraView: FlippedOverlayView {
    let root: LayoutNode
    let display: DisplayDescriptor
    let world: LayoutRect
    var camera: CameraViewport
    weak var store: WorkspaceStore?
    var onFocus: ((String) -> Void)?
    var onFrame: ((LayoutRect) -> Void)?
    var onCancel: (() -> Void)?
    private var down: NSPoint?
    private var last: NSPoint?
    private var framing = false
    private var selection: NSRect?
    private var settleTimer: Timer?
    private var monitor: Any?

    init(root: LayoutNode,display: DisplayDescriptor,world: LayoutRect,camera: CameraViewport,store: WorkspaceStore) {
        self.root = root; self.display = display; self.world = world; self.camera = camera; self.store = store
        super.init(frame: .zero)
        setAccessibilityElement(true); setAccessibilityRole(.group); setAccessibilityLabel("Zoomable desktop. Pinch to zoom, scroll to pan, Shift-drag to frame, Escape to cancel.")
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == 53 { self.onCancel?(); return nil }
            if event.keyCode == 36 { self.settle(); return nil }
            return event
        }
    }
    required init?(coder: NSCoder) { return nil }
    private var viewport: LayoutRect { LayoutRect(width: bounds.width,height: bounds.height) }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill(); NSBezierPath(rect: bounds).fill()
        guard let store else { return }
        let unavailable = store.unavailable
        let placements = root.placements(in: world,gap: store.gap,unavailable: unavailable).filter(\.isActive)
        NSGraphicsContext.saveGraphicsState(); NSBezierPath(rect: bounds).addClip()
        for placement in placements {
            let rect = camera.project(placement.rect,into: viewport).nsRect
            guard rect.intersects(bounds) else { continue }
            NSColor.controlBackgroundColor.setFill(); NSBezierPath(roundedRect: rect,xRadius: 8,yRadius: 8).fill()
            if let preview = store.previews[placement.window] { image(preview,in: rect.insetBy(dx: 3,dy: 3)) }
            else if let icon = store.icon(placement.window) ?? NSImage(systemSymbolName: WorkspaceStore.isDesktop(placement.window) ? "desktopcomputer" : "macwindow",accessibilityDescription: nil) {
                let side = max(10,min(64,min(rect.width,rect.height)*0.4))
                image(icon,in: NSRect(x: rect.midX-side/2,y: rect.midY-side/2,width: side,height: side))
            }
            if rect.width > 130 && rect.height > 70 {
                let strip = NSRect(x: rect.minX,y: rect.minY,width: rect.width,height: 28)
                NSColor.windowBackgroundColor.withAlphaComponent(0.94).setFill(); NSBezierPath(rect: strip).fill()
                text(store.record(placement.window)?.app ?? "Window",in: strip.insetBy(dx: 10,dy: 5),weight: .medium)
            }
            NSColor.separatorColor.setStroke(); NSBezierPath(roundedRect: rect,xRadius: 8,yRadius: 8).stroke()
        }
        if let selection {
            NSColor.controlAccentColor.withAlphaComponent(0.18).setFill(); NSBezierPath(rect: selection).fill()
            NSColor.controlAccentColor.setStroke(); let path = NSBezierPath(rect: selection); path.lineWidth = 2; path.stroke()
        }
        NSGraphicsContext.restoreGraphicsState()
        let help = NSRect(x: 16,y: bounds.height-40,width: min(620,bounds.width-32),height: 28)
        NSColor.windowBackgroundColor.withAlphaComponent(0.92).setFill(); NSBezierPath(roundedRect: help,xRadius: 6,yRadius: 6).fill()
        text("Pinch to zoom · Scroll to pan · Shift-drag to frame · Double-click a space · Esc to cancel",in: help.insetBy(dx: 10,dy: 6),color: .secondaryLabelColor)
    }
    override func magnify(with event: NSEvent) {
        let point = convert(event.locationInWindow,from: nil)
        consumeMagnification(event.magnification,at: point,ended: event.phase == .ended || event.phase == .cancelled)
    }
    func consumeMagnification(_ value: Double,atScreen point: CGPoint,ended: Bool) {
        consumeMagnification(value,at: NSPoint(x: point.x-display.frame.x,y: point.y-display.frame.y),ended: ended)
    }
    private func consumeMagnification(_ value: Double,at point: NSPoint,ended: Bool) {
        settleTimer?.invalidate()
        camera.zoom(by: max(0.1,1+value),anchorX: point.x/max(1,bounds.width),anchorY: point.y/max(1,bounds.height),world: world)
        needsDisplay = true
        if ended { scheduleSettle() }
    }
    override func scrollWheel(with event: NSEvent) {
        let point = convert(event.locationInWindow,from: nil)
        if event.modifierFlags.contains(.option) {
            camera.zoom(by: exp(-event.scrollingDeltaY*0.015),anchorX: point.x/max(1,bounds.width),anchorY: point.y/max(1,bounds.height),world: world)
        } else { camera.pan(dx: event.scrollingDeltaX,dy: event.scrollingDeltaY,viewport: viewport,world: world) }
        needsDisplay = true; scheduleSettle()
    }
    override func mouseDown(with event: NSEvent) {
        settleTimer?.invalidate()
        let point = convert(event.locationInWindow,from: nil)
        if event.clickCount >= 2 {
            let worldPoint = camera.worldPoint(x: point.x,y: point.y,viewport: viewport)
            let id = root.frames(in: world,gap: store?.gap ?? 8,unavailable: store?.unavailable ?? [])
                .filter { $0.value.contains(x: worldPoint.x,y: worldPoint.y) }.min { $0.value.area < $1.value.area }?.key
            if let id { onFocus?(id) }; return
        }
        down = point; last = point; framing = event.modifierFlags.contains(.shift); selection = nil
    }
    override func mouseDragged(with event: NSEvent) {
        guard let down,let last else { return }
        let point = convert(event.locationInWindow,from: nil)
        if framing { selection = NSRect(x: min(down.x,point.x),y: min(down.y,point.y),width: abs(point.x-down.x),height: abs(point.y-down.y)) }
        else { camera.pan(dx: point.x-last.x,dy: point.y-last.y,viewport: viewport,world: world) }
        self.last = point; needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        if framing,let selection,selection.width >= 20,selection.height >= 20 {
            let a = camera.worldPoint(x: selection.minX,y: selection.minY,viewport: viewport)
            let b = camera.worldPoint(x: selection.maxX,y: selection.maxY,viewport: viewport)
            onFrame?(LayoutRect(x: a.x,y: a.y,width: b.x-a.x,height: b.y-a.y))
        } else if down != nil { scheduleSettle() }
        down = nil; last = nil; selection = nil; framing = false
    }
    func beginScreenFrame(_ point: CGPoint) {
        down = NSPoint(x: point.x-display.frame.x,y: point.y-display.frame.y)
        last = down; framing = true; selection = nil; settleTimer?.invalidate()
    }
    func updateScreenFrame(_ point: CGPoint) {
        guard let down else { return }
        let x = point.x-display.frame.x,y = point.y-display.frame.y
        selection = NSRect(x: min(down.x,x),y: min(down.y,y),width: abs(x-down.x),height: abs(y-down.y))
        needsDisplay = true
    }
    func finishScreenFrame(_ point: CGPoint) {
        updateScreenFrame(point)
        if let selection,selection.width >= 20,selection.height >= 20 {
            let a = camera.worldPoint(x: selection.minX,y: selection.minY,viewport: viewport)
            let b = camera.worldPoint(x: selection.maxX,y: selection.maxY,viewport: viewport)
            onFrame?(LayoutRect(x: a.x,y: a.y,width: b.x-a.x,height: b.y-a.y))
        } else { onCancel?() }
        down = nil; last = nil; selection = nil; framing = false
    }
    private func scheduleSettle() {
        settleTimer?.invalidate()
        settleTimer = Timer.scheduledTimer(withTimeInterval: 0.25,repeats: false) { [weak self] _ in
            Task { @MainActor in self?.settle() }
        }
    }
    private func settle() { onFocus?(root.bestFrame(for: camera.frame,in: world,gap: store?.gap ?? 8,unavailable: store?.unavailable ?? [])) }
    func commitCamera() { settle() }
    func stop() {
        settleTimer?.invalidate(); settleTimer = nil
        if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
    }
}

@MainActor
final class DesktopTransitionView: FlippedOverlayView {
    let old: DesktopLayoutPlan
    let new: DesktopLayoutPlan
    weak var store: WorkspaceStore?
    let duration: Double
    private var progress = 0.0
    private var timer: Timer?
    init(old: DesktopLayoutPlan,new: DesktopLayoutPlan,store: WorkspaceStore,duration: Double) {
        self.old = old; self.new = new; self.store = store; self.duration = duration; super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { return nil }
    static func shouldAnimate(old: DesktopLayoutPlan,new: DesktopLayoutPlan,images: [String:NSImage]) -> Bool {
        let before = Dictionary(old.placements.filter(\.isActive).map { ($0.window,$0.rect) },uniquingKeysWith: { a,_ in a })
        // Tab selection has no geometric motion. Native windows handle the
        // content replacement without an opaque display-sized cover.
        return new.placements.contains { $0.isActive && images[$0.window] != nil && before[$0.window] != nil && before[$0.window] != $0.rect }
    }
    override func draw(_ dirtyRect: NSRect) {
        let previous = Dictionary(old.placements.filter(\.isActive).map { ($0.window,$0.rect) },uniquingKeysWith: { a,_ in a })
        let future = Dictionary(new.placements.filter(\.isActive).map { ($0.window,$0.rect) },uniquingKeysWith: { a,_ in a })
        for key in Set(previous.keys).union(future.keys).sorted() {
            guard let preview = store?.previews[key] else { continue }
            let from = previous[key] ?? future[key]!,to = future[key] ?? previous[key]!
            let rect = from.interpolated(to: to,progress: progress)
            let local = NSRect(x: rect.x-new.display.frame.x,y: rect.y-new.display.frame.y,width: rect.width,height: rect.height)
            let alpha = future[key] == nil ? 1-progress : previous[key] == nil ? progress : 1
            NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current?.cgContext.setAlpha(alpha)
            image(preview,in: local)
            NSGraphicsContext.restoreGraphicsState()
        }
    }
    func start(completion: @escaping () -> Void) {
        timer?.invalidate()
        let start = ProcessInfo.processInfo.systemUptime
        let animationTimer = Timer(timeInterval: 1/60,repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self else { timer.invalidate(); return }
                let t = min(1,(ProcessInfo.processInfo.systemUptime-start)/max(0.01,self.duration))
                self.progress = 1-pow(1-t,3); self.needsDisplay = true
                if t >= 1 { timer.invalidate(); self.timer = nil; completion() }
            }
        }
        timer = animationTimer
        RunLoop.main.add(animationTimer,forMode: .common)
    }
    var isRunning: Bool { timer != nil }
    func stop() { timer?.invalidate(); timer = nil }
    override func viewWillMove(toWindow newWindow: NSWindow?) { if newWindow == nil { stop() } }
}
