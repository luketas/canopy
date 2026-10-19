import SwiftUI
import ServiceManagement
import Carbon

struct SettingsView: View {
    @ObservedObject var store: WorkspaceStore
    @State private var loginEnabled = SMAppService.mainApp.status == .enabled
    @State private var loginMessage: String?
    var body: some View {
        TabView {
            general.tabItem { Label("General",systemImage: "gearshape") }
            shortcuts.tabItem { Label("Shortcuts",systemImage: "keyboard") }
            workspace.tabItem { Label("Workspace",systemImage: "square.split.2x2") }
        }.padding(12).frame(width: 560,height: 660)
    }
    private var general: some View {
        Form {
            Section("Desktop") {
                Toggle("Dock by dragging window title bars",isOn: preference(\.desktopDocking))
                Toggle("Require Option for grid-window drags",isOn: preference(\.dockingRequiresOption))
                    .disabled(!store.preferences.desktopDocking)
                Text("Floating windows dock without a modifier: drop into an empty slot, on an edge to split, or in the center to add a tab.").font(.caption).foregroundStyle(.secondary)
                Toggle("Show desktop tab strips",isOn: preference(\.showTabStrips))
                Toggle("Option-pinch and wallpaper gestures",isOn: preference(\.globalGestures))
                Text("Global gestures open Overview after macOS delivers the first event. Use the Overview button for exclusive camera input.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Animate zoom and layout edits",isOn: preference(\.animations))
                Text("Workspace switches bring the selected grid forward. Inactive windows keep their positions behind the workspace background; no minimizing or transition animation.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Text("Window gap")
                    Slider(value: Binding(get: { store.gap },set: store.updateGap),in: 0...32,step: 1)
                    Text("\(Int(store.gap)) pt").monospacedDigit().frame(width: 44)
                }
            }
            Section("Previews") {
                Toggle("Show window contents",isOn: Binding(get: { store.preferences.previewsEnabled },set: { store.onRequestPreviews?($0) }))
                Text("Optional Screen Recording access supplies still images kept only in memory. No video or files are recorded.")
                    .font(.caption).foregroundStyle(.secondary)
                if let status = store.previewStatus { Text(status).font(.caption).foregroundStyle(.secondary) }
                HStack {
                    Text("Use a miniature below")
                    Stepper("\(Int(store.preferences.minimumWidth)) × \(Int(store.preferences.minimumHeight)) pt",
                        value: preference(\.minimumWidth),in: 100...600,step: 20)
                }
                Stepper("Minimum height: \(Int(store.preferences.minimumHeight)) pt",value: preference(\.minimumHeight),in: 80...400,step: 10)
            }
            Section("Startup and permissions") {
                Toggle("Launch at login",isOn: Binding(get: { loginEnabled },set: updateLogin))
                if let loginMessage { Text(loginMessage).font(.caption).foregroundStyle(.secondary) }
                if SMAppService.mainApp.status == .requiresApproval {
                    Button("Open Login Items Settings") { SMAppService.openSystemSettingsLoginItems() }
                }
                LabeledContent("Accessibility",value: store.hasPermission ? "Enabled" : "Required for window control")
                Button("Open Accessibility Settings") { openPrivacy("Privacy_Accessibility") }
                Button("Open Screen Recording Settings") { openPrivacy("Privacy_ScreenCapture") }
            }
        }.formStyle(.grouped)
    }
    private var shortcuts: some View {
        Form {
            Section {
                Text("Workspace shortcuts switch whole grids from any app. Pane shortcuts navigate inside the current grid. Click a shortcut, then press your new combination. Escape cancels; Delete disables it. Use at least one modifier key.")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(store.preferences.shortcuts) { binding in
                    HStack {
                        Text(binding.title)
                        Spacer()
                        ShortcutRecorder(value: binding,onRecord: store.changeShortcut).frame(width: 145,height: 26)
                    }
                }
            }
            Section {
                Button("Restore Default Shortcuts") { store.updatePreferences { $0.shortcuts = ShortcutBinding.defaults } }
                if let status = store.shortcutStatus { Text(status).font(.caption).foregroundStyle(.secondary) }
            }
        }.formStyle(.grouped)
    }
    private var workspace: some View {
        Form {
            Section("Workspace file") {
                Button("Export Workspace…") { store.showExportPanel() }
                Button("Import Workspace…") { store.showImportPanel() }.disabled(store.isDemo)
                Button("Show Workspace in Finder") { NSWorkspace.shared.activateFileViewerSelecting([store.persistenceURL]) }
                Button("Back Up and Reset Workspace") { store.resetWorkspace() }.disabled(store.isDemo)
                Text("Imports start paused. Reset preserves the previous file in the Backups folder.").font(.caption).foregroundStyle(.secondary)
            }
            if !store.pendingRecovery.isEmpty {
                Section("Interrupted session") {
                    Text("\(store.pendingRecovery.count) windows have a saved restoration baseline.")
                    Button("Recover Windows") { store.recoverWindows() }.disabled(store.isDemo || !store.hasPermission)
                }
            }
            Section("Excluded apps") {
                if store.excludedApps.isEmpty { Text("Right-click a window in the workspace to exclude its app.").foregroundStyle(.secondary) }
                ForEach(store.excludedApps.sorted(),id: \.self) { bundle in
                    HStack { Text(bundle); Spacer(); Button("Include") { store.includeApp(bundle) } }
                }
            }
            Section("About") {
                Text("Canopy \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") · MIT licensed").font(.callout.weight(.medium))
                Text("An independent open source nested window manager inspired by TrellisWM. Window metadata and preview images stay on this Mac.")
                    .font(.caption).foregroundStyle(.secondary)
                if let message = store.message { Text(message).font(.caption).textSelection(.enabled) }
            }
        }.formStyle(.grouped)
    }
    private func preference<T>(_ key: WritableKeyPath<UserPreferences,T>) -> Binding<T> {
        Binding(get: { store.preferences[keyPath: key] },set: { value in store.updatePreferences { $0[keyPath: key] = value } })
    }
    private func openPrivacy(_ anchor: String) {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")!)
    }
    private func updateLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginEnabled = SMAppService.mainApp.status == .enabled
            loginMessage = SMAppService.mainApp.status == .requiresApproval ? "Approve Canopy in Login Items to finish enabling startup." : nil
        } catch { loginEnabled = SMAppService.mainApp.status == .enabled; loginMessage = error.localizedDescription }
    }
}

struct ShortcutRecorder: NSViewRepresentable {
    var value: ShortcutBinding
    var onRecord: (ShortcutBinding) -> Bool
    func makeNSView(context: Context) -> RecorderButton { RecorderButton(value: value,onRecord: onRecord) }
    func updateNSView(_ view: RecorderButton,context: Context) { view.value = value; view.onRecord = onRecord; if !view.recording { view.title = value.label } }
}

final class RecorderButton: NSButton {
    var value: ShortcutBinding
    var onRecord: (ShortcutBinding) -> Bool
    var recording = false
    init(value: ShortcutBinding,onRecord: @escaping (ShortcutBinding) -> Bool) {
        self.value = value; self.onRecord = onRecord; super.init(frame: .zero)
        title = value.label; bezelStyle = .rounded; setButtonType(.momentaryPushIn)
        target = self; action = #selector(beginRecording); setAccessibilityLabel("Record shortcut for \(value.title)")
    }
    required init?(coder: NSCoder) { return nil }
    override var acceptsFirstResponder: Bool { true }
    @objc private func beginRecording() { recording = true; title = "Press shortcut…"; window?.makeFirstResponder(self) }
    override func resignFirstResponder() -> Bool { recording = false; title = value.label; return true }
    override func keyDown(with event: NSEvent) {
        guard recording else { super.keyDown(with: event); return }
        if event.keyCode == 53 { recording = false; title = value.label; return }
        var result = value
        if event.keyCode == 51 || event.keyCode == 117 { result.enabled = false }
        else {
            let flags = event.modifierFlags.intersection([.control,.option,.command,.shift])
            guard !flags.isEmpty else { title = "Use a modifier"; return }
            var modifiers: UInt32 = 0
            if flags.contains(.control) { modifiers |= UInt32(controlKey) }
            if flags.contains(.option) { modifiers |= UInt32(optionKey) }
            if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
            if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
            let special: [UInt16:String] = [49:"Space",36:"Return",123:"←",124:"→",125:"↓",126:"↑",48:"Tab"]
            result.keyCode = UInt32(event.keyCode); result.modifiers = modifiers
            result.key = special[event.keyCode] ?? event.charactersIgnoringModifiers?.uppercased() ?? "Key \(event.keyCode)"
            result.enabled = true
        }
        if onRecord(result) { value = result }
        recording = false; title = value.label
    }
}
