import SwiftUI
import ServiceManagement
import Carbon

struct SettingsView: View {
    @ObservedObject var store: WorkspaceStore
    @State private var loginEnabled = SMAppService.mainApp.status == .enabled
    @State private var loginMessage: String?
    var body: some View {
        TabView(selection: $store.settingsSection) {
            general.tabItem { Label("General",systemImage: "gearshape") }.tag("general")
            shortcuts.tabItem { Label("Shortcuts",systemImage: "keyboard") }.tag("shortcuts")
            floatingApps.tabItem { Label("Floating Apps",systemImage: "rectangle.on.rectangle") }.tag("floating")
            workspace.tabItem { Label("Workspace",systemImage: "square.split.2x2") }.tag("workspace")
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
        VStack(alignment: .leading, spacing: 10) {
            Text("Click a shortcut and press a new combination with a modifier key. Escape cancels; Delete disables. Changes save automatically and work from any app.")
                .font(.callout).foregroundStyle(.secondary)
            if let error = store.shortcutConfigurationError {
                Text(error).font(.callout).foregroundStyle(.red).accessibilityLabel("Shortcut conflict: \(error)")
            }
            if let status = store.shortcutStatus {
                Text(status).font(.caption).foregroundStyle(.secondary)
            }
            Form {
                ForEach(ShortcutBinding.sections,id: \.self) { section in
                    Section(section) {
                        ForEach(store.preferences.shortcuts.filter { $0.section == section }) { binding in
                            HStack(spacing: 8) {
                                Toggle(binding.title,isOn: Binding(get: {
                                    store.preferences.shortcuts.first { $0.id == binding.id }?.enabled ?? false
                                },set: { store.setShortcutEnabled(binding.id,enabled: $0) }))
                                    .toggleStyle(.checkbox)
                                Spacer(minLength: 4)
                                ShortcutRecorder(value: binding,onRecord: store.changeShortcut,
                                    onRecordingChanged: { store.recordShortcut(binding.id,recording: $0) })
                                    .frame(width: 145,height: 26)
                                Button { store.resetShortcut(binding.id) } label: {
                                    Image(systemName: "arrow.counterclockwise")
                                }.buttonStyle(.borderless).disabled(binding.isDefault)
                                    .help("Reset \(binding.title) to its default shortcut")
                                    .accessibilityLabel("Reset \(binding.title)")
                            }
                        }
                    }
                }
            }.formStyle(.grouped)
            Button("Restore All Defaults") { store.restoreDefaultShortcuts() }
        }.padding(8)
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
            Section("About") {
                Text("Canopy \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") · MIT licensed").font(.callout.weight(.medium))
                Text("An independent open source nested window manager inspired by TrellisWM. Window metadata and preview images stay on this Mac.")
                    .font(.caption).foregroundStyle(.secondary)
                if let message = store.message { Text(message).font(.caption).textSelection(.enabled) }
            }
        }.formStyle(.grouped)
    }
    private var floatingApps: some View {
        Form {
            Section("Always Floating Apps") {
                Text("These apps stay above the grid. Canopy never arranges or docks their windows. Shottr is included by default.")
                    .font(.callout).foregroundStyle(.secondary)
                HStack {
                    Button("Add App…") { store.chooseAppsToBlacklist() }
                    Menu("Running Apps") {
                        ForEach(store.applicationsToBlacklist) { app in
                            Button(app.name) { store.excludeApp(app.id) }
                        }
                    }
                }
                ForEach(store.blacklistedApplications) { app in
                    HStack {
                        Text(app.name)
                        Spacer()
                        Button("Allow in Grids") { store.includeApp(app.id) }
                            .accessibilityLabel("Allow \(app.name) in grids")
                    }
                }
                if store.excludedApps.isEmpty { Text("No apps are blacklisted.").foregroundStyle(.secondary) }
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
    var onRecordingChanged: (Bool) -> Void
    func makeNSView(context: Context) -> RecorderButton {
        RecorderButton(value: value,onRecord: onRecord,onRecordingChanged: onRecordingChanged)
    }
    func updateNSView(_ view: RecorderButton,context: Context) {
        view.value = value; view.onRecord = onRecord; view.onRecordingChanged = onRecordingChanged
        if !view.recording { view.title = value.label }
    }
    static func dismantleNSView(_ view: RecorderButton,coordinator: ()) { view.finishRecording() }
}

final class RecorderButton: NSButton {
    var value: ShortcutBinding
    var onRecord: (ShortcutBinding) -> Bool
    var onRecordingChanged: (Bool) -> Void
    private(set) var recording = false
    private var pendingKeyUp: UInt16?
    private var resignObserver: NSObjectProtocol?
    init(value: ShortcutBinding,onRecord: @escaping (ShortcutBinding) -> Bool,onRecordingChanged: @escaping (Bool) -> Void) {
        self.value = value; self.onRecord = onRecord; self.onRecordingChanged = onRecordingChanged; super.init(frame: .zero)
        title = value.label; bezelStyle = .rounded; setButtonType(.momentaryPushIn)
        target = self; action = #selector(beginRecording); setAccessibilityLabel("Record shortcut for \(value.title)")
    }
    required init?(coder: NSCoder) { return nil }
    deinit { if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) } }
    override var acceptsFirstResponder: Bool { true }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver); self.resignObserver = nil }
        guard let window else { finishRecording(); return }
        resignObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification,object: window,queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.finishRecording() }
        }
    }
    @objc func beginRecording() {
        guard !recording else { return }
        window?.makeFirstResponder(self)
        recording = true; pendingKeyUp = nil; title = "Press shortcut…"; onRecordingChanged(true)
    }
    func finishRecording() {
        guard recording else { return }
        recording = false; pendingKeyUp = nil; title = value.label; onRecordingChanged(false)
    }
    override func resignFirstResponder() -> Bool { finishRecording(); return true }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard recording, event.type == .keyDown else { return super.performKeyEquivalent(with: event) }
        keyDown(with: event); return true
    }
    override func keyUp(with event: NSEvent) {
        if recording, pendingKeyUp == event.keyCode { finishRecording() }
        else { super.keyUp(with: event) }
    }
    override func keyDown(with event: NSEvent) {
        guard recording else { super.keyDown(with: event); return }
        if event.keyCode == 53 { finishRecording(); return }
        guard pendingKeyUp == nil, !event.isARepeat else { return }
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
        if onRecord(result) {
            value = result; title = value.label
            // Re-register only after release so this press cannot also invoke
            // the action just assigned, including when the key repeats.
            pendingKeyUp = event.keyCode
        } else { title = "Try another shortcut…" }
    }
}
