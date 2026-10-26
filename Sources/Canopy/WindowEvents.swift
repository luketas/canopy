import AppKit
import ApplicationServices

/// AX notifications drive updates; the store retains a slow watchdog for apps with incomplete AX support.
@MainActor
final class WindowEvents {
    private var observers: [pid_t: AXObserver] = [:]
    private var watched: [pid_t: [AXUIElement]] = [:]
    private var workspaceTokens: [NSObjectProtocol] = []
    private var pending: DispatchWorkItem?
    private var mouseMonitor: Any?
    var onChange: (() -> Void)?
    var onDestroyed: ((AXUIElement) -> Void)?
    var onSpaceChanged: (() -> Void)?
    var onFocusChange: ((pid_t?,AXUIElement?) -> Void)?

    init() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification,NSWorkspace.didTerminateApplicationNotification,
                     NSWorkspace.didActivateApplicationNotification,NSWorkspace.didUnhideApplicationNotification] {
            workspaceTokens.append(center.addObserver(forName: name,object: nil,queue: .main) { [weak self] notification in
                let pid = (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
                Task { @MainActor in
                    if name == NSWorkspace.didActivateApplicationNotification || name == NSWorkspace.didUnhideApplicationNotification { self?.onFocusChange?(pid,nil) }
                    self?.schedule()
                }
            })
        }
        workspaceTokens.append(center.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification,object: nil,queue: .main) { [weak self] _ in
            Task { @MainActor in self?.onSpaceChanged?(); self?.schedule() }
        })
        // Clicking the Dock icon of the already active app may emit neither
        // application activation nor AX focus change. Reconcile after the click
        // without intercepting it or polling every application's windows.
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.onFocusChange?(NSWorkspace.shared.frontmostApplication?.processIdentifier,nil)
            }
        }
    }
    func synchronize(_ windows: [String:DiscoveredWindow]) {
        let applications = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular && $0.processIdentifier != getpid() }
        let pids = Set(applications.map(\.processIdentifier))
        for pid in Array(observers.keys) where !pids.contains(pid) { remove(pid) }
        for app in applications {
            let pid = app.processIdentifier
            if observers[pid] == nil {
                var observer: AXObserver?
                let callback: AXObserverCallback = { _,element,notification,context in
                    guard let context else { return }
                    let object = Unmanaged<WindowEvents>.fromOpaque(context).takeUnretainedValue()
                    let destroyed = notification as String == kAXUIElementDestroyedNotification as String
                    let focused = [kAXFocusedWindowChangedNotification,kAXMainWindowChangedNotification,
                                   kAXWindowCreatedNotification,kAXWindowDeminiaturizedNotification].contains(notification as String)
                    var pid: pid_t = 0
                    AXUIElementGetPid(element,&pid)
                    Task { @MainActor in
                        if destroyed { object.onDestroyed?(element) }
                        if focused { object.onFocusChange?(pid,element) }
                        object.schedule()
                    }
                }
                guard AXObserverCreate(pid,callback,&observer) == .success, let observer else { continue }
                observers[pid] = observer
                CFRunLoopAddSource(CFRunLoopGetMain(),AXObserverGetRunLoopSource(observer),.commonModes)
                let root = AXUIElementCreateApplication(pid)
                for name in [kAXWindowCreatedNotification,kAXFocusedWindowChangedNotification,kAXMainWindowChangedNotification] {
                    _ = AXObserverAddNotification(observer,root,name as CFString,Unmanaged.passUnretained(self).toOpaque())
                }
            }
            guard let observer = observers[pid] else { continue }
            let current = windows.values.filter { $0.pid == pid }.map(\.element)
            let previous = watched[pid] ?? []
            for element in current where !previous.contains(where: { CFEqual($0,element) }) {
                for name in [kAXMovedNotification,kAXResizedNotification,kAXTitleChangedNotification,
                             kAXWindowMiniaturizedNotification,kAXWindowDeminiaturizedNotification,kAXUIElementDestroyedNotification] {
                    _ = AXObserverAddNotification(observer,element,name as CFString,Unmanaged.passUnretained(self).toOpaque())
                }
            }
            watched[pid] = current
        }
    }
    private func schedule() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.onChange?() }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now()+0.1,execute: work)
    }
    private func remove(_ pid: pid_t) {
        if let observer = observers.removeValue(forKey: pid) {
            CFRunLoopRemoveSource(CFRunLoopGetMain(),AXObserverGetRunLoopSource(observer),.commonModes)
        }
        watched.removeValue(forKey: pid)
    }
    func stop() {
        pending?.cancel(); pending = nil
        for pid in Array(observers.keys) { remove(pid) }
        for token in workspaceTokens { NSWorkspace.shared.notificationCenter.removeObserver(token) }
        workspaceTokens = []
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor); self.mouseMonitor = nil }
    }
}
