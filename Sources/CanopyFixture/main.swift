import AppKit

final class FixtureWindow: NSWindow {
    override func accessibilityFrame() -> NSRect { frame }
    override func isAccessibilityMinimized() -> Bool { isMiniaturized }
    override func setAccessibilityMinimized(_ minimized: Bool) {
        if minimized { miniaturize(nil) } else { deminiaturize(nil) }
    }
    override func setAccessibilityFrame(_ frame: NSRect) {
        // The bare AppKit fixture must implement the writable frame contract:
        // NSWindow's inherited AX frame setter did not apply size changes here.
        // Respect the fixture's declared minimum just as a real app would.
        guard frame.origin.x.isFinite,frame.origin.y.isFinite,
              frame.width.isFinite,frame.height.isFinite,frame.width > 0,frame.height > 0 else { return }
        var target = frame
        target.size.width = max(minSize.width,target.width)
        target.size.height = max(minSize.height,target.height)
        target.origin.y = frame.maxY-target.height
        setFrame(target,display: true)
    }
}

final class FixtureDelegate: NSObject,NSApplicationDelegate {
    var windows: [NSWindow] = []
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        let menu = NSMenu(),appMenu = NSMenu()
        let root = NSMenuItem(); root.submenu = appMenu; menu.addItem(root)
        appMenu.addItem(withTitle: "Quit Fixture",action: #selector(NSApplication.terminate(_:)),keyEquivalent: "q")
        NSApp.mainMenu = menu
        for index in 0..<3 {
            let window = FixtureWindow(contentRect: NSRect(x: 100+index*110,y: 180+index*70,width: 640,height: 400),
                styleMask: [.titled,.closable,.miniaturizable,.resizable],backing: .buffered,defer: false)
            window.title = index >= 1 ? "Duplicate fixture title" : "Canopy Fixture \(index+1)"
            window.minSize = NSSize(width: index == 1 ? 420 : 280,height: 180)
            window.identifier = NSUserInterfaceItemIdentifier("canopy-fixture-\(index)")
            window.setAccessibilityIdentifier("canopy-fixture-\(index)")
            window.isReleasedWhenClosed = false
            let content = NSStackView(); content.orientation = .vertical; content.alignment = .leading
            content.edgeInsets = NSEdgeInsets(top: 24,left: 24,bottom: 24,right: 24)
            let title = NSTextField(labelWithString: "Native window fixture \(index+1)")
            title.font = .systemFont(ofSize: 24,weight: .semibold)
            let details = NSTextField(wrappingLabelWithString: "Use these disposable windows to check docking, tab strips, seams, zooming, minimization, and restoration. This helper has no Accessibility or Screen Recording access.")
            let editor = NSTextField(string: "Rename me or edit this sample content.")
            let rename = NSButton(title: "Change Window Title",target: self,action: #selector(renameWindow(_:))); rename.tag = index
            let report = NSButton(title: "Export Window Frames",target: self,action: #selector(exportFrames))
            for view in [title,details,editor,rename,report] { content.addArrangedSubview(view) }
            // Keep the content stack independent of the window's root sizing.
            let rootView = NSView(frame: NSRect(x: 0,y: 0,width: 640,height: 400))
            rootView.autoresizingMask = [.width,.height]
            content.translatesAutoresizingMaskIntoConstraints = false
            rootView.addSubview(content)
            NSLayoutConstraint.activate([
                content.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
                content.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
                content.topAnchor.constraint(equalTo: rootView.topAnchor)
            ])
            window.contentView = rootView; window.makeKeyAndOrderFront(nil); windows.append(window)
        }
        NSApp.activate(ignoringOtherApps: true)
    }
    @objc func renameWindow(_ sender: NSButton) { windows[sender.tag].title = "Renamed Fixture \(sender.tag+1)" }
    @objc func exportFrames() {
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        let data: [[String:Any]] = windows.map { window in
            ["id": window.identifier?.rawValue ?? "", "title": window.title,
             "x": window.frame.minX,"y": top-window.frame.maxY,"width": window.frame.width,"height": window.frame.height,
             "minimized": window.isMiniaturized,"visible": window.isVisible]
        }
        do {
            let support = FileManager.default.urls(for: .applicationSupportDirectory,in: .userDomainMask)[0]
            let file = support.appendingPathComponent("Canopy/TestSessions/fixture-frames.json")
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(),withIntermediateDirectories: true)
            try JSONSerialization.data(withJSONObject: data,options: [.prettyPrinted,.sortedKeys]).write(to: file,options: .atomic)
        } catch { NSAlert(error: error).runModal() }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

let app = NSApplication.shared,delegate = FixtureDelegate()
app.delegate = delegate
withExtendedLifetime(delegate) { app.run() }
