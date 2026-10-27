import AppKit
import CanopyCore

@MainActor
final class DesktopWorkspaceBar: FlippedOverlayView {
    static let height = 32.0
    private(set) var grids: [WorkspaceGrid]
    private(set) var active: String
    var onSelect: ((String) -> Void)?
    var onOpen: (() -> Void)?
    var onSettings: (() -> Void)?
    private var buttons: [NSButton] = []
    private let edit = NSButton(title: "Edit Grids",target: nil,action: nil)
    private let settings = NSButton(title: "Settings",target: nil,action: nil)
    private let scroll = NSScrollView()
    private let tabs = WorkspaceTabSurface()
    private var revealSelection = true
    private let actionsWidth: CGFloat = 210

    init(grids: [WorkspaceGrid],active: String) {
        self.grids = grids; self.active = active
        super.init(frame: .zero)
        setAccessibilityElement(true); setAccessibilityRole(.tabGroup)
        setAccessibilityLabel("Canopy workspace tabs")
        edit.isBordered = false; edit.font = .systemFont(ofSize: 12,weight: .medium)
        edit.target = self; edit.action = #selector(openEditor)
        settings.isBordered = false; settings.font = .systemFont(ofSize: 12,weight: .medium)
        settings.image = NSImage(systemSymbolName: "gearshape",accessibilityDescription: nil)
        settings.imagePosition = .imageLeading; settings.imageScaling = .scaleProportionallyDown
        settings.target = self; settings.action = #selector(openSettings)
        settings.toolTip = "Grid appearance, selector position, keyboard shortcuts, and floating apps"
        settings.setAccessibilityLabel("Settings")
        settings.setAccessibilityHelp(settings.toolTip)
        scroll.drawsBackground = false; scroll.borderType = .noBorder
        scroll.hasHorizontalScroller = false; scroll.hasVerticalScroller = false
        scroll.documentView = tabs
        addSubview(scroll); addSubview(edit); addSubview(settings)
        rebuildButtons(); update(grids: grids,active: active)
    }
    required init?(coder: NSCoder) { nil }
    var tabWidth: CGFloat { max(90,min(180,max(0,bounds.width-actionsWidth)/CGFloat(max(1,grids.count)))) }
    func update(grids: [WorkspaceGrid],active: String) {
        let changed = self.grids.map { [$0.id,$0.name] } != grids.map { [$0.id,$0.name] }
        if changed || self.active != active { revealSelection = true }
        self.grids = grids; self.active = active
        if changed { rebuildButtons() }
        for (index,button) in buttons.enumerated() {
            button.state = grids[index].id == active ? .on : .off
            button.font = .systemFont(ofSize: 12,weight: button.state == .on ? .semibold : .regular)
        }
        setAccessibilityValue(grids.first { $0.id == active }?.name)
        needsLayout = true; needsDisplay = true
    }
    private func rebuildButtons() {
        buttons.forEach { $0.removeFromSuperview() }
        buttons = grids.enumerated().map { index,grid in
            let button = NSButton(title: grid.name,target: self,action: #selector(selectGrid(_:)))
            button.tag = index; button.isBordered = false; button.alignment = .left
            button.setButtonType(.toggle); button.setAccessibilityRole(.radioButton)
            button.setAccessibilityLabel("Workspace \(grid.name)")
            button.lineBreakMode = .byTruncatingTail; button.toolTip = grid.name
            tabs.addSubview(button); return button
        }
    }
    override func layout() {
        super.layout()
        scroll.frame = NSRect(x: 0,y: 0,width: max(0,bounds.width-actionsWidth),height: bounds.height)
        tabs.frame = NSRect(x: 0,y: 0,width: max(scroll.bounds.width,CGFloat(grids.count)*tabWidth),height: bounds.height)
        for (index,button) in buttons.enumerated() {
            button.frame = NSRect(x: CGFloat(index)*tabWidth+12,y: 3,width: tabWidth-24,height: bounds.height-6)
        }
        edit.frame = NSRect(x: max(0,bounds.width-actionsWidth),y: 0,width: 110,height: bounds.height)
        settings.frame = NSRect(x: max(110,bounds.width-100),y: 0,width: 100,height: bounds.height)
        if let index = grids.firstIndex(where: { $0.id == active }) {
            tabs.selection = NSRect(x: CGFloat(index)*tabWidth+3,y: 3,width: tabWidth-6,height: bounds.height-6)
            if revealSelection { tabs.scrollToVisible(NSRect(x: CGFloat(index)*tabWidth,y: 0,width: tabWidth,height: bounds.height)) }
        } else { tabs.selection = nil }
        revealSelection = false; tabs.needsDisplay = true
    }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill(); NSBezierPath(rect: bounds).fill()
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    @objc private func selectGrid(_ sender: NSButton) {
        guard grids.indices.contains(sender.tag) else { return }
        let id = grids[sender.tag].id
        update(grids: grids,active: id)
        onSelect?(id)
    }
    @objc private func openEditor() { onOpen?() }
    @objc private func openSettings() { onSettings?() }
    override func accessibilityChildren() -> [Any]? { buttons + [edit,settings] }
}

@MainActor
private final class WorkspaceTabSurface: FlippedOverlayView {
    var selection: NSRect?
    override func draw(_ dirtyRect: NSRect) {
        guard let selection else { return }
        NSColor.controlAccentColor.withAlphaComponent(0.18).setFill()
        NSBezierPath(roundedRect: selection,xRadius: 5,yRadius: 5).fill()
    }
}
