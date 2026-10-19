import AppKit
import CanopyCore

@MainActor
final class DesktopWorkspaceBar: FlippedOverlayView {
    static let height = 32.0
    private(set) var grids: [WorkspaceGrid]
    private(set) var active: String
    var onSelect: ((String) -> Void)?
    var onOpen: (() -> Void)?
    private var buttons: [NSButton] = []
    private let edit = NSButton(title: "Edit Grids",target: nil,action: nil)

    init(grids: [WorkspaceGrid],active: String) {
        self.grids = grids; self.active = active
        super.init(frame: .zero)
        setAccessibilityElement(true); setAccessibilityRole(.tabGroup)
        setAccessibilityLabel("Canopy workspace tabs")
        edit.isBordered = false; edit.font = .systemFont(ofSize: 12,weight: .medium)
        edit.target = self; edit.action = #selector(openEditor)
        addSubview(edit); rebuildButtons(); update(grids: grids,active: active)
    }
    required init?(coder: NSCoder) { nil }
    var tabWidth: CGFloat { max(36,min(180,(bounds.width-110)/CGFloat(max(1,grids.count)))) }
    func update(grids: [WorkspaceGrid],active: String) {
        let changed = self.grids.map { [$0.id,$0.name] } != grids.map { [$0.id,$0.name] }
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
            addSubview(button); return button
        }
    }
    override func layout() {
        super.layout()
        for (index,button) in buttons.enumerated() {
            button.frame = NSRect(x: CGFloat(index)*tabWidth+12,y: 3,width: tabWidth-24,height: bounds.height-6)
        }
        edit.frame = NSRect(x: bounds.width-110,y: 0,width: 110,height: bounds.height)
    }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill(); NSBezierPath(rect: bounds).fill()
        if let index = grids.firstIndex(where: { $0.id == active }) {
            let rect = NSRect(x: CGFloat(index)*tabWidth+3,y: 3,width: tabWidth-6,height: bounds.height-6)
            NSColor.controlAccentColor.withAlphaComponent(0.18).setFill()
            NSBezierPath(roundedRect: rect,xRadius: 5,yRadius: 5).fill()
        }
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    @objc private func selectGrid(_ sender: NSButton) {
        guard grids.indices.contains(sender.tag) else { return }
        let id = grids[sender.tag].id
        update(grids: grids,active: id)
        onSelect?(id)
    }
    @objc private func openEditor() { onOpen?() }
    override func accessibilityChildren() -> [Any]? { buttons + [edit] }
}
