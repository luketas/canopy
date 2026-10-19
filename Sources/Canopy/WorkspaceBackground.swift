import AppKit
import ImageIO
import Darwin
import CanopyCore

/// This is a stacking surface, not a screenshot or an input proxy. Native app
/// windows stay live above/below it and receive their own mouse/keyboard input.
@MainActor
final class WorkspaceBackgroundView: NSView {
    private var wallpaper: NSImage?
    init(display: DisplayDescriptor) {
        let screen = NSScreen.screens.first {
            let number = $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
            return number?.stringValue == display.legacyID
        } ?? NSScreen.screens.first
        let url = screen.flatMap { NSWorkspace.shared.desktopImageURL(for: $0) }
        super.init(frame: .zero)
        setAccessibilityElement(false)
        // Some desktop photos take seconds to decode even as thumbnails.
        // Never make the first Apply or a workspace switch wait for wallpaper.
        if let url {
            Task { [weak self] in
                let image = await Task.detached(priority: .utility) { () -> CGImage? in
                    guard let source = CGImageSourceCreateWithURL(url as CFURL,nil) else { return nil }
                    return CGImageSourceCreateThumbnailAtIndex(source,0,[
                        kCGImageSourceCreateThumbnailFromImageAlways:true,
                        kCGImageSourceCreateThumbnailWithTransform:true,
                        kCGImageSourceThumbnailMaxPixelSize:4096,
                        kCGImageSourceShouldCacheImmediately:true] as CFDictionary)
                }.value
                guard let self,let image else { return }
                self.wallpaper = NSImage(cgImage: image,size: NSSize(width: image.width,height: image.height))
                self.needsDisplay = true
            }
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var isOpaque: Bool { true }
    override var acceptsFirstResponder: Bool { false }
    override func mouseDown(with event: NSEvent) {} // Never click through to an inactive app.
    override func rightMouseDown(with event: NSEvent) {}
    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedWhite: 0.16,alpha: 1).setFill()
        bounds.fill()
        guard let wallpaper,wallpaper.size.width > 0,wallpaper.size.height > 0 else { return }
        let scale = max(bounds.width/wallpaper.size.width,bounds.height/wallpaper.size.height)
        let size = NSSize(width: wallpaper.size.width*scale,height: wallpaper.size.height*scale)
        wallpaper.draw(in: NSRect(x: bounds.midX-size.width/2,y: bounds.midY-size.height/2,width: size.width,height: size.height),
                       from: .zero,operation: .copy,fraction: 1)
    }
}

/// Order only Canopy's own surface relative to WindowServer IDs. AppKit's
/// relative ordering can be constrained to the active application group.
/// Resolve optional SPI at runtime, as with the AX window-ID resolver.
enum NativeWorkspaceStacking {
    typealias Connection = @convention(c) () -> Int32
    typealias Create = @convention(c) (Int32) -> Unmanaged<CFTypeRef>?
    typealias Order = @convention(c) (CFTypeRef,UInt32,Int32,UInt32) -> Int32
    typealias Commit = @convention(c) (CFTypeRef,Int32) -> Int32
    private static let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight",RTLD_LAZY)
    private static func resolve<T>(_ name: String,_ type: T.Type) -> T? {
        guard let handle,let symbol = dlsym(handle,name) else { return nil }
        return unsafeBitCast(symbol,to: T.self)
    }
    private static let connection = resolve("SLSMainConnectionID",Connection.self)
    private static let create = resolve("SLSTransactionCreate",Create.self)
    private static let order = resolve("SLSTransactionOrderWindow",Order.self)
    private static let commit = resolve("SLSTransactionCommit",Commit.self)
    static func place(_ window: NSWindow,below other: UInt32) -> Bool {
        guard let connection,let create,let order,let commit,
              let transaction = create(connection())?.takeRetainedValue() else { return false }
        guard order(transaction,UInt32(window.windowNumber),-1,other) == 0 else { return false }
        return commit(transaction,1) == 0
    }
}
