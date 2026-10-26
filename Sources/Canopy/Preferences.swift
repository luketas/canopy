import Foundation
import Carbon
import CanopyCore

struct ShortcutBinding: Codable, Equatable, Identifiable {
    var id: String
    var keyCode: UInt32
    var modifiers: UInt32
    var key: String
    var enabled: Bool = true
    var label: String {
        var result = ""
        if modifiers & UInt32(controlKey) != 0 { result += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { result += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { result += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { result += "⌘" }
        return enabled ? result+key : "Disabled"
    }
    var title: String {
        switch id {
        case "everything": return "Show everything"
        case "desktop": return "Focus Desktop"
        case "zoom-out": return "Step out"
        case "zoom-in": return "Step toward pointer"
        case "frame": return "Frame focused window"
        case "auto-layout": return "Auto Layout Current Monitor"
        case "workspace-previous": return "Previous workspace"
        case "workspace-next": return "Next workspace"
        case "previous": return "Previous pane"
        case "next": return "Next pane"
        case "back": return "Back"
        case "forward": return "Forward"
        default:
            if id.hasPrefix("workspace.") { return "Workspace \(id.dropFirst(10))" }
            return id.hasPrefix("save.") ? "Save view \(id.dropFirst(5))" : "Recall view \(id.dropFirst(5))"
        }
    }
    static var defaults: [ShortcutBinding] {
        let m = UInt32(controlKey | optionKey)
        var result = [("everything",49,"Space"),("desktop",2,"D"),("zoom-out",126,"↑"),("zoom-in",125,"↓"),
                      ("frame",36,"Return"),("auto-layout",0,"A"),("previous",123,"←"),("next",124,"→"),("back",33,"["),("forward",30,"]")]
            .map { ShortcutBinding(id: $0.0,keyCode: UInt32($0.1),modifiers: m,key: $0.2) }
        for (i,code) in [18,19,20,21,23,22,26,28,25].enumerated() {
            result.append(ShortcutBinding(id: "view.\(i+1)",keyCode: UInt32(code),modifiers: m,key: "\(i+1)"))
            result.append(ShortcutBinding(id: "save.\(i+1)",keyCode: UInt32(code),modifiers: m | UInt32(shiftKey),key: "\(i+1)"))
        }
        let workspaceModifiers = m | UInt32(cmdKey)
        result.append(ShortcutBinding(id: "workspace-previous",keyCode: 48,modifiers: UInt32(optionKey | shiftKey),key: "Tab"))
        result.append(ShortcutBinding(id: "workspace-next",keyCode: 48,modifiers: UInt32(optionKey),key: "Tab"))
        for (i,code) in [18,19,20,21,23,22,26,28,25].enumerated() {
            result.append(ShortcutBinding(id: "workspace.\(i+1)",keyCode: UInt32(code),modifiers: workspaceModifiers,key: "\(i+1)"))
        }
        return result
    }
    static func addingMissingDefaults(to existing: [ShortcutBinding]) -> [ShortcutBinding] {
        var result = existing
        let oldModifiers = UInt32(controlKey | optionKey | cmdKey)
        for i in result.indices {
            let oldCode: UInt32? = result[i].id == "workspace-previous" ? 123 : result[i].id == "workspace-next" ? 124 : nil
            guard let oldCode,result[i].enabled,result[i].keyCode == oldCode,result[i].modifiers == oldModifiers,
                  let replacement = defaults.first(where: { $0.id == result[i].id }),
                  !result.contains(where: { $0.id != replacement.id && $0.enabled && $0.keyCode == replacement.keyCode && $0.modifiers == replacement.modifiers }) else { continue }
            result[i] = replacement
        }
        for var binding in defaults where !existing.contains(where: { $0.id == binding.id }) {
            if result.contains(where: { $0.enabled && $0.keyCode == binding.keyCode && $0.modifiers == binding.modifiers }) { binding.enabled = false }
            result.append(binding)
        }
        return result
    }
}

struct UserPreferences: Codable, Equatable {
    var previewsEnabled = false
    var desktopDocking = true
    var dockingRequiresOption = true
    var animations = true
    var animationDuration = 0.46
    var minimumWidth = 220.0
    var minimumHeight = 150.0
    var showTabStrips = true
    var globalGestures = true
    var shortcuts = ShortcutBinding.defaults
}

struct DisplayDescriptor: Equatable, Identifiable {
    var id: String
    var name: String
    var frame: CanopyCore.LayoutRect
    var legacyID: String? = nil
    var bounds: CanopyCore.LayoutRect? = nil
    var monitorBounds: CanopyCore.LayoutRect { bounds ?? frame }
}
