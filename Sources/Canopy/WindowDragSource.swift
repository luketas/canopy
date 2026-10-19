import AppKit
import SwiftUI
import CanopyCore

struct EditorDropTarget {
    var id: String
    var node: String?
    var window: Int
    var frame: CGRect
    var gridID: String? = nil
    var removesWindow = false
    var columnID: String? = nil
}

@MainActor
extension WorkspaceStore {
    func beginEditorDrag(_ key: String) {
        guard record(key) != nil,!Self.isDesktop(key) else { return }
        draggedWindow = key; interactiveDrag = true
    }
    func updateEditorDrag(_ point: CGPoint,window: Int) {
        guard let key = draggedWindow else { return }
        let target = editorTargets.values.filter { $0.window == window && $0.frame.contains(point) && ($0.node == nil || current?.root?.node($0.node!) != nil) && (!$0.removesWindow || currentGridWindowIDs.contains(key)) && ($0.gridID == nil || $0.gridID != current?.activeGridID) }
            .min { $0.frame.width*$0.frame.height < $1.frame.width*$1.frame.height }
        guard let target else { editorDropTarget = nil; editorDropEdge = nil; return }
        if let node = target.node,let leaf = current?.root?.node(node),leaf.windows == [key] {
            editorDropTarget = nil; editorDropEdge = nil; return
        }
        let edge = Self.editorEdge(at: point,in: target.frame)
        if editorDropTarget != target.id { editorDropTarget = target.id }
        if editorDropEdge != edge { editorDropEdge = edge }
    }
    static func editorEdge(at point: CGPoint,in frame: CGRect) -> DockEdge {
        let x = (point.x-frame.minX)/max(1,frame.width),y = (frame.maxY-point.y)/max(1,frame.height)
        let nearest = [(DockEdge.left,x),(.right,1-x),(.top,y),(.bottom,1-y)].min { $0.1 < $1.1 }!
        return nearest.1 < 0.24 ? nearest.0 : .tab
    }
    func finishEditorDrag(_ point: CGPoint,window: Int) {
        updateEditorDrag(point,window: window)
        let key = draggedWindow,edge = editorDropEdge
        let target = editorTargets.values.first { $0.id == editorDropTarget && $0.window == window }
        cancelEditorDrag()
        if let key,let edge,let target {
            if target.removesWindow { removeWindowFromCurrentGrid(key) }
            else if let grid = target.gridID { transferWindow(key,toGrid: grid) }
            else if let column = target.columnID { stackWindow(key,inColumn: column) }
            else { dock(key,target: target.node,edge: edge) }
        }
    }
    func cancelEditorDrag() {
        draggedWindow = nil; editorDropTarget = nil; editorDropEdge = nil; interactiveDrag = false
    }
}

/// Keep editor drags in the editor's mouse sequence. Starting an OS pasteboard
/// drag here can lose mouse-up inside SwiftUI scroll views and leave a preview.
struct WindowDragSource: NSViewRepresentable {
    var key: String
    var label: String
    var store: WorkspaceStore
    var excludesZoomButton = false
    var excludedTrailingWidth: CGFloat = 0
    var onSelect: () -> Void
    var onOpen: () -> Void
    func makeNSView(context: Context) -> WindowDragView { WindowDragView() }
    func updateNSView(_ view: WindowDragView,context: Context) {
        view.key = key; view.toolTip = "Drag \(label) to move it. Double-click to focus."
        view.excludedTrailingWidth = excludedTrailingWidth
        view.excludesZoomButton = excludesZoomButton
        view.onStart = { store.beginEditorDrag(key) }
        view.onMove = { point,window in store.updateEditorDrag(point,window: window) }
        view.onDrop = { point,window in store.finishEditorDrag(point,window: window) }
        view.onCancel = { store.cancelEditorDrag() }
        view.onSelect = onSelect; view.onOpen = onOpen
    }
}

final class WindowDragView: NSView {
    var key = ""
    var excludesZoomButton = false
    var excludedTrailingWidth: CGFloat = 0
    var onStart: (() -> Void)?
    var onMove: ((CGPoint,Int) -> Void)?
    var onDrop: ((CGPoint,Int) -> Void)?
    var onCancel: (() -> Void)?
    var onSelect: (() -> Void)?
    var onOpen: (() -> Void)?
    private var down: NSEvent?
    private var didDrag = false
    override var acceptsFirstResponder: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point,from: superview)
        if excludedTrailingWidth > 0 && local.x >= bounds.width-excludedTrailingWidth { return nil }
        if excludesZoomButton && local.x > bounds.width-64 && local.y > bounds.height-64 { return nil }
        return super.hitTest(point)
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func resetCursorRects() { addCursorRect(bounds,cursor: .openHand) }
    override func mouseDown(with event: NSEvent) {
        down = event; didDrag = false; window?.makeFirstResponder(self)
    }
    override func mouseDragged(with event: NSEvent) {
        guard let down,!WorkspaceStore.isDesktop(key),!key.isEmpty else { return }
        guard didDrag || hypot(event.locationInWindow.x-down.locationInWindow.x,event.locationInWindow.y-down.locationInWindow.y) >= 4 else { return }
        if !didDrag { didDrag = true; onStart?() }
        onMove?(event.locationInWindow,window?.windowNumber ?? -1)
    }
    override func mouseUp(with event: NSEvent) {
        guard let down else { return }
        self.down = nil
        if didDrag { onDrop?(event.locationInWindow,window?.windowNumber ?? -1) }
        else if down.clickCount >= 2 { onOpen?() }
        else { onSelect?() }
        didDrag = false
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { down = nil; didDrag = false; onCancel?() }
        else { super.keyDown(with: event) }
    }
}

struct EditorDropRegion: NSViewRepresentable {
    var id: String
    var node: String?
    var gridID: String? = nil
    var removesWindow = false
    var columnID: String? = nil
    var store: WorkspaceStore
    func makeNSView(context: Context) -> EditorDropRegionView { EditorDropRegionView() }
    func updateNSView(_ view: EditorDropRegionView,context: Context) {
        view.id = id; view.node = node; view.gridID = gridID; view.removesWindow = removesWindow; view.columnID = columnID; view.store = store
        DispatchQueue.main.async { [weak view] in view?.synchronize() }
    }
    static func dismantleNSView(_ view: EditorDropRegionView,coordinator: ()) { view.store?.editorTargets.removeValue(forKey: view.token) }
}
final class EditorDropRegionView: NSView {
    let token = UUID().uuidString
    var id = ""
    var node: String?
    var gridID: String?
    var removesWindow = false
    var columnID: String?
    weak var store: WorkspaceStore?
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); synchronize() }
    override func setFrameSize(_ newSize: NSSize) { super.setFrameSize(newSize); synchronize() }
    override func setFrameOrigin(_ newOrigin: NSPoint) { super.setFrameOrigin(newOrigin); synchronize() }
    override func layout() { super.layout(); synchronize() }
    func synchronize() {
        guard let window,!id.isEmpty,bounds.width > 0,bounds.height > 0 else { return }
        store?.editorTargets[token] = EditorDropTarget(id: id,node: node,window: window.windowNumber,frame: convert(bounds,to: nil),gridID: gridID,removesWindow: removesWindow,columnID: columnID)
    }
}
