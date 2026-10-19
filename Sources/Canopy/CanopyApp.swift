import SwiftUI
import AppKit
import Carbon
import Darwin

@main
struct CanopyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var store: WorkspaceStore
    init() {
        let arguments = ProcessInfo.processInfo.arguments
        let fixture = arguments.contains("--test-fixture") || Bundle.main.object(forInfoDictionaryKey: "CanopyFixtureTesting") as? Bool == true
        let support = FileManager.default.urls(for: .applicationSupportDirectory,in: .userDomainMask)[0]
        let url = fixture ? support.appendingPathComponent("Canopy/TestSessions/fixture-workspace.json") : nil
        _store = StateObject(wrappedValue: WorkspaceStore(demo: arguments.contains("--demo") || fixture,
            bridge: fixture ? WindowBridge(allowedBundles: ["org.canopywm.Fixture"]) : nil,storageURL: url))
    }
    var body: some Scene {
        WindowGroup("Canopy", id: "workspace") {
            WorkspaceRoot(store: store,delegate: delegate)
        }.defaultSize(width: 1160, height: 760)
            .commands {
                CommandGroup(after: .newItem) {
                    Button("Recover Interrupted Session") { store.recoverWindows() }
                        .disabled(store.isDemo || store.pendingRecovery.isEmpty)
                }
                CommandGroup(replacing: .undoRedo) {
                    Button("Undo Layout Change") { store.undo() }.keyboardShortcut("z").disabled(!store.canUndo)
                    Button("Redo Layout Change") { store.redo() }.keyboardShortcut("z", modifiers: [.command, .shift]).disabled(!store.canRedo)
                }
            }
        MenuBarExtra("Canopy", systemImage: "square.split.2x2") { MenuContent(store: store) }
        Settings { SettingsView(store: store) }
    }
}

private struct WorkspaceRoot: View {
    @ObservedObject var store: WorkspaceStore
    let delegate: AppDelegate
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        WorkspaceView(store: store).onAppear {
            delegate.connect(store)
            store.onOpenWorkspace = {
                openWindow(id: "workspace"); NSApp.activate(ignoringOtherApps: true)
            }
        }
    }
}

private struct MenuContent: View {
    @ObservedObject var store: WorkspaceStore
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button("Open Workspace") { openWindow(id: "workspace"); NSApp.activate(ignoringOtherApps: true) }
        Divider()
        Menu("Workspaces") {
            Button("Previous Workspace") { store.performCommand("workspace-previous") }
            Button("Next Workspace") { store.performCommand("workspace-next") }
            Divider()
            ForEach(Array((store.current?.grids ?? []).enumerated()),id: \.element.id) { index,grid in
                Button(grid.name) { store.selectWorkspaceGrid(grid.id,activate: true) }
            }
        }
        Button("Show Everything") { store.showEverything() }
        Button("Desktop") { store.focusDesktop() }
        Button("Zoomable Overview") { store.onRequestCamera?() }.disabled(!store.isArranging)
        Button("Step Out") { store.zoomOut() }
        Button("Step In") { store.zoomIn() }
        Button("Back") { store.navigateHistory(back: true) }.disabled(!(store.current?.history.canGoBack ?? false))
        Button("Forward") { store.navigateHistory(back: false) }.disabled(!(store.current?.history.canGoForward ?? false))
        Menu("Saved Views") {
            ForEach(1...9, id: \.self) { slot in
                Button("View \(slot)") { store.recallView(slot) }.disabled(store.current?.savedViews[String(slot)] == nil)
            }
        }
        Divider()
        if store.isDemo { Button("Use My Windows") { store.useRealWindows(); openWindow(id: "workspace") } }
        else {
            Button("Apply Grid") { store.applyCurrentGrid() }.disabled(!store.hasPermission || store.currentGridWindowIDs.isEmpty)
            Button("Resume Layout") { store.resume() }.disabled(store.isArranging || !store.hasPermission)
            if !store.pendingRecovery.isEmpty { Button("Recover Interrupted Session") { store.recoverWindows() } }
            Button("Restore All Managed Windows") { store.floatAll() }.disabled(!store.hasWindowsToRestore)
        }
        Divider()
        SettingsLink { Text("Settings…") }
        Button("Quit Canopy") { NSApp.terminate(nil) }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private weak var store: WorkspaceStore?
    private var hotKeys: HotKeys?
    private var desktop: DesktopCoordinator?
    private var screenObserver: NSObjectProtocol?
    private var queuedURLs: [URL] = []
    private var signals: [DispatchSourceSignal] = []
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        for number in [SIGTERM,SIGINT] {
            signal(number,SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number,queue: .main)
            source.setEventHandler { NSApp.terminate(nil) }; source.resume(); signals.append(source)
        }
        if let icon = Bundle.main.path(forResource: "Canopy",ofType: "icns") { NSApp.applicationIconImage = NSImage(contentsOfFile: icon) }
        NSAppleEventManager.shared().setEventHandler(self,andSelector: #selector(receiveURL(_:reply:)),forEventClass: AEEventClass(kInternetEventClass),andEventID: AEEventID(kAEGetURL))
        NSApp.activate(ignoringOtherApps: true)
    }
    func connect(_ store: WorkspaceStore) {
        // Opening a menu-bar window manager should keep the user's active
        // Desktop. Switching to its old Space immediately pauses arrangement.
        DispatchQueue.main.async {
            for window in NSApp.windows where window.title == "Canopy" {
                window.collectionBehavior.insert(.moveToActiveSpace)
            }
        }
        guard self.store == nil else { return }
        self.store = store
        hotKeys = HotKeys(store: store)
        desktop = DesktopCoordinator(store: store)
        store.onRequestCamera = { [weak self] in self?.desktop?.showCamera() }
        store.onRequestPreviews = { [weak self] value in self?.desktop?.enablePreviews(value) }
        store.onPreferencesChanged = { [weak self,weak store] in
            guard let store else { return }; self?.hotKeys?.configure(store: store)
        }
        for url in queuedURLs { store.handleURL(url) }; queuedURLs = []
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak store] _ in
                Task { @MainActor in store?.synchronizeScreens() }
            }
    }
    @objc private func receiveURL(_ event: NSAppleEventDescriptor,reply: NSAppleEventDescriptor) {
        guard let raw = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,let url = URL(string: raw) else { return }
        if let store { store.handleURL(url) } else { queuedURLs.append(url) }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) {
        store?.shutdown(); hotKeys?.stop(); desktop?.stop()
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        NSAppleEventManager.shared().removeEventHandler(forEventClass: AEEventClass(kInternetEventClass),andEventID: AEEventID(kAEGetURL))
        for source in signals { source.cancel() }; signals = []
    }
}
