import Carbon
import Foundation

extension ShortcutBinding {
    static let sections = ["Workspaces", "Layout and navigation", "Recall saved views", "Save views"]
    var section: String {
        if id.hasPrefix("workspace") { return Self.sections[0] }
        if id.hasPrefix("view.") { return Self.sections[2] }
        if id.hasPrefix("save.") { return Self.sections[3] }
        return Self.sections[1]
    }
    var isDefault: Bool { Self.defaults.first { $0.id == id } == self }
}

extension WorkspaceStore {
    func recordShortcut(_ id: String, recording: Bool) {
        if recording {
            guard preferences.shortcuts.contains(where: { $0.id == id }) else { return }
            recordingShortcutID = id
            shortcutConfigurationError = nil
        } else {
            guard recordingShortcutID == id else { return }
            recordingShortcutID = nil
        }
        onPreferencesChanged?()
    }

    @discardableResult
    func changeShortcut(_ binding: ShortcutBinding) -> Bool {
        let allowed = UInt32(controlKey | optionKey | cmdKey | shiftKey)
        guard let index = preferences.shortcuts.firstIndex(where: { $0.id == binding.id }),
              ShortcutBinding.defaults.contains(where: { $0.id == binding.id }),
              binding.keyCode < 128, !binding.key.isEmpty, binding.key.count <= 24,
              binding.modifiers & ~allowed == 0,
              !binding.enabled || binding.modifiers != 0 else {
            shortcutConfigurationError = "Choose a key with Control, Option, Command, or Shift."
            return false
        }
        if binding.enabled, let conflict = preferences.shortcuts.first(where: {
            $0.id != binding.id && $0.enabled && $0.keyCode == binding.keyCode && $0.modifiers == binding.modifiers
        }) {
            shortcutConfigurationError = "\(binding.label) is assigned to \(conflict.title). Choose another shortcut or disable that action first."
            return false
        }
        preferences.shortcuts[index] = binding
        saveShortcutChanges()
        return true
    }

    func setShortcutEnabled(_ id: String, enabled: Bool) {
        guard var binding = preferences.shortcuts.first(where: { $0.id == id }) else { return }
        binding.enabled = enabled
        changeShortcut(binding)
    }

    func resetShortcut(_ id: String) {
        guard let binding = ShortcutBinding.defaults.first(where: { $0.id == id }) else { return }
        changeShortcut(binding)
    }

    func restoreDefaultShortcuts() {
        preferences.shortcuts = ShortcutBinding.defaults
        saveShortcutChanges()
    }

    private func saveShortcutChanges() {
        shortcutConfigurationError = nil
        persistPreferences()
        onPreferencesChanged?()
        // Keyboard preferences never change window geometry or stacking.
    }
}
