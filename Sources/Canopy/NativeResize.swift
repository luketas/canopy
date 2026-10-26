import Foundation
import ApplicationServices
import CanopyCore

/// Owns one in-flight batch and one replaceable destination. AX IPC never
/// runs on the input/rendering thread, and old pointer positions cannot queue up.
final class LatestResizePump: @unchecked Sendable {
    private let queue = DispatchQueue(label: "org.canopywm.resize",qos: .userInteractive)
    private let lock = NSLock()
    private var pending: [String:LayoutRect]?
    private var running = false
    private let apply: @Sendable ([String:LayoutRect]) -> Void

    init(apply: @escaping @Sendable ([String:LayoutRect]) -> Void) { self.apply = apply }
    func submit(_ frames: [String:LayoutRect]) {
        lock.lock(); pending = frames
        let start = !running; running = true; lock.unlock()
        if start { queue.async { self.consume() } }
    }
    private func consume() {
        while true {
            lock.lock()
            guard let frames = pending else { running = false; lock.unlock(); return }
            pending = nil; lock.unlock()
            apply(frames)
        }
    }
    /// Fence before restore, workspace changes, or final readback. Once this
    /// returns, no resize from this gesture can move a window later.
    func finish(_ finalize: @escaping @Sendable () -> Void = {}) {
        // DispatchQueue.sync may execute its block on the calling thread.
        // Enqueue the readback explicitly so even finalization stays off main.
        let completed = DispatchSemaphore(value: 0)
        queue.async { finalize(); completed.signal() }
        completed.wait()
    }
}

struct NativeResizeWindow: @unchecked Sendable {
    let element: AXUIElement
    let pid: pid_t
}

/// Mutable AX state is confined to LatestResizePump's serial queue.
final class NativeResizeState: @unchecked Sendable {
    let windows: [String:NativeResizeWindow]
    private var enhancedApplications: [pid_t:AXUIElement] = [:]
    private var initialized = false
    private var lastFrames: [String:LayoutRect] = [:]
    private(set) var originals: [String:LayoutRect] = [:]
    private(set) var targets: [String:LayoutRect] = [:]
    private(set) var actual: [String:LayoutRect] = [:]
    private(set) var batches = 0
    private(set) var writes = 0
    private(set) var frameReads = 0
    private(set) var longestBatchMilliseconds = 0.0
    private(set) var nativeWorkOnMainThread = false

    init(windows: [String:NativeResizeWindow]) { self.windows = windows }
    private func initialize() {
        guard !initialized else { return }; initialized = true
        for pid in Set(windows.values.map(\.pid)) {
            let app = AXUIElementCreateApplication(pid)
            _ = AXUIElementSetMessagingTimeout(app,0.15)
            var value: CFTypeRef?
            if AXUIElementCopyAttributeValue(app,"AXEnhancedUserInterface" as CFString,&value) == .success,
               value as? Bool == true,
               AXUIElementSetAttributeValue(app,"AXEnhancedUserInterface" as CFString,kCFBooleanFalse) == .success {
                enhancedApplications[pid] = app
            }
        }
    }
    func apply(_ frames: [String:LayoutRect]) {
        nativeWorkOnMainThread = nativeWorkOnMainThread || Thread.isMainThread
        let started = ProcessInfo.processInfo.systemUptime
        initialize(); batches += 1
        for key in frames.keys.sorted() {
            guard let window = windows[key],let target = frames[key] else { continue }
            if lastFrames[key] == nil {
                _ = AXUIElementSetMessagingTimeout(window.element,0.15)
                frameReads += 1
                let before = Self.frame(window.element)
                originals[key] = before; lastFrames[key] = before
            }
            let before = lastFrames[key]
            var point = CGPoint(x: target.x.rounded(),y: target.y.rounded())
            var size = CGSize(width: max(80,target.width.rounded()),height: max(60,target.height.rounded()))
            if before.map({ abs($0.x-point.x) >= 0.5 || abs($0.y-point.y) >= 0.5 }) ?? true,
               let value = AXValueCreate(.cgPoint,&point) {
                _ = AXUIElementSetAttributeValue(window.element,kAXPositionAttribute as CFString,value); writes += 1
            }
            if before.map({ abs($0.width-size.width) >= 0.5 || abs($0.height-size.height) >= 0.5 }) ?? true,
               let value = AXValueCreate(.cgSize,&size) {
                _ = AXUIElementSetAttributeValue(window.element,kAXSizeAttribute as CFString,value); writes += 1
            }
            targets[key] = target
            lastFrames[key] = LayoutRect(x: point.x,y: point.y,width: size.width,height: size.height)
        }
        longestBatchMilliseconds = max(longestBatchMilliseconds,(ProcessInfo.processInfo.systemUptime-started)*1000)
    }
    func finish() {
        nativeWorkOnMainThread = nativeWorkOnMainThread || Thread.isMainThread
        for (key,target) in targets {
            guard let window = windows[key] else { continue }
            frameReads += 1
            guard var readback = Self.frame(window.element) else { continue }
            // Some apps move their origin when growing. Correct it once at
            // release instead of repeatedly reading and fighting every frame.
            if abs(readback.x-target.x.rounded()) >= 0.5 || abs(readback.y-target.y.rounded()) >= 0.5 {
                var point = CGPoint(x: target.x.rounded(),y: target.y.rounded())
                if let value = AXValueCreate(.cgPoint,&point) {
                    _ = AXUIElementSetAttributeValue(window.element,kAXPositionAttribute as CFString,value); writes += 1
                    frameReads += 1; readback = Self.frame(window.element) ?? readback
                }
            }
            actual[key] = readback
        }
        for application in enhancedApplications.values {
            _ = AXUIElementSetAttributeValue(application,"AXEnhancedUserInterface" as CFString,kCFBooleanTrue)
        }
        enhancedApplications = [:]
    }
    static func frame(_ element: AXUIElement) -> LayoutRect? {
        var values: CFArray?
        guard AXUIElementCopyMultipleAttributeValues(element,[kAXPositionAttribute,kAXSizeAttribute] as CFArray,[],&values) == .success,
              let values = values as? [AXValue],values.count == 2,
              CFGetTypeID(values[0]) == AXValueGetTypeID(),CFGetTypeID(values[1]) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero,size = CGSize.zero
        guard AXValueGetValue(values[0],.cgPoint,&point),AXValueGetValue(values[1],.cgSize,&size) else { return nil }
        return LayoutRect(x: point.x,y: point.y,width: size.width,height: size.height)
    }
}
