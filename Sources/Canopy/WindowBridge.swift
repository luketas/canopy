import AppKit
import ApplicationServices
import CanopyCore
import Darwin

// macOS exposes no public AX-to-WindowServer identifier conversion. Resolve
// the optional SPI at runtime so removing it cannot prevent the app launching.
private enum NativeWindowResolver {
    typealias Lookup = @convention(c) (AXUIElement,UnsafeMutablePointer<CGWindowID>) -> Int32
    static let lookup: Lookup? = {
        guard let handle = dlopen(nil,RTLD_LAZY) else { return nil }
        defer { dlclose(handle) }
        guard let symbol = dlsym(handle,"_AXUIElementGetWindow") else { return nil }
        return unsafeBitCast(symbol,to: Lookup.self)
    }()
    static func number(_ element: AXUIElement) -> CGWindowID? {
        guard let lookup else { return nil }
        var number: CGWindowID = 0
        return lookup(element,&number) == 0 && number != 0 ? number : nil
    }
}

struct WindowRecord: Codable, Identifiable, Equatable {
    var id: String
    var bundleID: String
    var app: String
    var title: String
    var ordinal: Int
    var originalFrame: LayoutRect
    var axIdentifier: String?
    var document: String?
    var nativeWindowNumber: UInt32?
    var nativeProcessID: Int32?
    var identity: String { "\(bundleID)|\(title)|\(ordinal)" }
    var fingerprint: WindowFingerprint {
        WindowFingerprint(bundle: bundleID,title: title,ordinal: ordinal,identifier: axIdentifier,document: document,frame: originalFrame)
    }
}

struct DiscoveredWindow: Identifiable {
    var record: WindowRecord
    var element: AXUIElement
    var pid: pid_t
    var minimized: Bool
    var icon: NSImage?
    var windowNumber: CGWindowID?
    var fullScreen: Bool = false
    var onScreen: Bool = true
    var id: String { record.id }
}

@MainActor
protocol WindowManaging: AnyObject {
    var windows: [String: DiscoveredWindow] { get }
    var trusted: Bool { get }
    var runningBundleIDs: Set<String> { get }
    var preservesUnlistedWindows: Bool { get }
    var visibleWindowIDs: Set<String> { get }
    var preferredInitialPaneSize: CGSize { get }
    var destroyedWindowIDs: Set<String> { get }
    var windowAliases: [String:String] { get }
    var frontmostProcessID: pid_t? { get }
    func requestPermission()
    @discardableResult func forgetWindow(_ key: String) -> Bool
    func discover(saved: [WindowRecord], excluded: Set<String>) -> [DiscoveredWindow]
    func frame(of element: AXUIElement) -> LayoutRect?
    func move(_ key: String, to rect: LayoutRect) -> Bool
    func raise(_ key: String, activate: Bool)
    func restore(_ records: [WindowRecord]) -> Set<String>
    func setMinimized(_ key: String, _ value: Bool) -> Bool
    func focusedWindow() -> String?
    func focusedWindow(in processID: pid_t) -> String?
    func windowKey(for element: AXUIElement,processID: pid_t) -> String?
    func minimumSize(_ key: String) -> CGSize?
    func beginLiveResize(_ keys: Set<String>)
    func endLiveResize()
    func resizeLiveWindows(_ frames: [String:LayoutRect])
    func verifyMove(_ key: String, to rect: LayoutRect) -> Bool
}

extension WindowManaging {
    func beginLiveResize(_ keys: Set<String>) {}
    func endLiveResize() {}
    func resizeLiveWindows(_ frames: [String:LayoutRect]) { for (key,rect) in frames { _ = move(key,to: rect) } }
    var destroyedWindowIDs: Set<String> { [] }
    var windowAliases: [String:String] { [:] }
    @discardableResult func forgetWindow(_ key: String) -> Bool { true }
    var preservesUnlistedWindows: Bool { false }
    var preferredInitialPaneSize: CGSize { .zero }
    var visibleWindowIDs: Set<String> { Set(windows.values.filter { $0.onScreen && !$0.minimized }.map(\.id)) }
    var runningBundleIDs: Set<String> { Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)) }
    func setMinimized(_ key: String, _ value: Bool) -> Bool { false }
    func focusedWindow() -> String? { nil }
    var frontmostProcessID: pid_t? { focusedWindow().flatMap { windows[$0]?.pid } }
    func focusedWindow(in processID: pid_t) -> String? {
        focusedWindow().flatMap { windows[$0]?.pid == processID ? $0 : nil }
    }
    func windowKey(for element: AXUIElement,processID: pid_t) -> String? {
        windows.values.first { $0.pid == processID && CFEqual($0.element,element) }?.id
    }
    func minimumSize(_ key: String) -> CGSize? { nil }
    func verifyMove(_ key: String,to rect: LayoutRect) -> Bool {
        guard let element = windows[key]?.element else { return true }
        guard let actual = frame(of: element) else { return false }
        return abs(actual.x-rect.x.rounded()) < 3 && abs(actual.y-rect.y.rounded()) < 3
            && abs(actual.width-rect.width.rounded()) < 3 && abs(actual.height-rect.height.rounded()) < 3
    }
}

@MainActor
final class WindowBridge: WindowManaging {
    var preferredInitialPaneSize: CGSize { CGSize(width: 1000,height: 650) }
    var preservesUnlistedWindows: Bool { true }
    var visibleWindowIDs: Set<String> {
        let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly,.excludeDesktopElements],kCGNullWindowID) as? [[String:Any]] ?? []
        let numbers = Set(info.compactMap { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value })
        return Set(windows.values.filter { $0.windowNumber.map(numbers.contains) ?? false }.map(\.id))
    }
    let allowedBundles: Set<String>?
    init(allowedBundles: Set<String>? = nil) { self.allowedBundles = allowedBundles }
    private(set) var windows: [String: DiscoveredWindow] = [:]
    private var invalidatedWindows: [String:DiscoveredWindow] = [:]
    private(set) var destroyedWindowIDs = Set<String>()
    private(set) var windowAliases: [String:String] = [:]
    private var observedMinimums: [String:CGSize] = [:]
    private var liveResizing = false
    private var resizeState: NativeResizeState?
    private var resizePump: LatestResizePump?
    private var resizeAttempts: [String:(target: LayoutRect,before: LayoutRect)] = [:]
    func minimumSize(_ key: String) -> CGSize? { observedMinimums[key] }
    private var pendingMinimization: [String:(value: Bool,until: Date)] = [:]
    #if DEBUG
    private var moveDiagnostics: [[String:Any]] = []
    #endif
    private func observedMinimized(_ element: AXUIElement,key: String?,fallback: Bool = false) -> Bool {
        if let key,let pending = pendingMinimization[key],pending.until > Date() { return pending.value }
        return attribute(element,kAXMinimizedAttribute) as? Bool ?? fallback
    }
    var trusted: Bool { AXIsProcessTrusted() }
    @discardableResult func forgetWindow(_ key: String) -> Bool {
        let number = windows[key]?.record.nativeWindowNumber
        let info = CGWindowListCopyWindowInfo(.optionAll,kCGNullWindowID) as? [[String:Any]] ?? []
        let stillPresent = number.map { number in info.contains { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value == number } } ?? false
        if stillPresent { invalidatedWindows[key] = windows[key] }
        else { invalidatedWindows.removeValue(forKey: key) }
        windows.removeValue(forKey: key)
        observedMinimums.removeValue(forKey: key)
        resizeAttempts.removeValue(forKey: key)
        pendingMinimization.removeValue(forKey: key)
        return !stillPresent
    }

    func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func discover(saved: [WindowRecord], excluded: Set<String>) -> [DiscoveredWindow] {
        guard trusted else { return [] }
        destroyedWindowIDs = []
        windowAliases = [:]
        let previous = invalidatedWindows.merging(windows) { _,live in live }
        let running = Set(NSWorkspace.shared.runningApplications.filter { !$0.isTerminated }.map(\.processIdentifier))
        let liveIDs = Set(previous.values.filter { running.contains($0.pid) }.map(\.id))
        var found: [DiscoveredWindow] = []
        var claimed = Set<String>()
        var claimedNative: [String:String] = [:]
        #if DEBUG
        var diagnostics: [[String:Any]] = []
        defer {
            if let data = try? JSONSerialization.data(withJSONObject: diagnostics,options: [.prettyPrinted,.sortedKeys]) {
                try? data.write(to: FileManager.default.temporaryDirectory.appendingPathComponent("canopy-discovery.json"),options: .atomic)
            }
        }
        #endif
        let cgWindows = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String:Any]] ?? []
        let onScreenInfo = CGWindowListCopyWindowInfo([.optionOnScreenOnly,.excludeDesktopElements],kCGNullWindowID) as? [[String:Any]] ?? []
        let onScreenNumbers = Set(onScreenInfo.filter { ($0[kCGWindowLayer as String] as? Int) == 0 }
            .compactMap { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value })
        let windowOwners = Set(cgWindows.compactMap { item -> pid_t? in
            guard (item[kCGWindowLayer as String] as? Int) == 0,
                  let bounds = item[kCGWindowBounds as String] as? [String:Any],
                  let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary),frame.width > 80,frame.height > 60,
                  let pid = item[kCGWindowOwnerPID as String] as? Int else { return nil }
            return pid_t(pid)
        })
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy != .prohibited
            && (app.activationPolicy == .regular || windowOwners.contains(app.processIdentifier)
                || app.bundleIdentifier.map(excluded.contains) == true) {
            guard app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
                  !app.isTerminated, let bundle = app.bundleIdentifier,
                  allowedBundles?.contains(bundle) ?? true else { continue }
            let alwaysFloating = excluded.contains(bundle)
            let root = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(root, 0.15)
            var rawWindows: CFTypeRef?
            let windowsResult = AXUIElementCopyAttributeValue(root,kAXWindowsAttribute as CFString,&rawWindows)
            #if DEBUG
            diagnostics.append(["bundle":bundle,"hidden":app.isHidden,"active":app.isActive,"windowsResult":windowsResult.rawValue,"count":(rawWindows as? [AXUIElement])?.count ?? -1])
            #endif
            var elements = rawWindows as? [AXUIElement] ?? []
            let children = attribute(root,kAXChildrenAttribute) as? [AXUIElement] ?? []
            let alternatives = children.filter { attribute($0,kAXRoleAttribute) as? String == kAXWindowRole }
                + [attribute(root,kAXMainWindowAttribute),attribute(root,kAXFocusedWindowAttribute)].compactMap { value -> AXUIElement? in
                    guard let value,CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
                    return (value as! AXUIElement)
                }
            for element in alternatives where !elements.contains(where: { CFEqual($0,element) }) { elements.append(element) }
            let preferred = [attribute(root,kAXFocusedWindowAttribute),attribute(root,kAXMainWindowAttribute)].compactMap { value -> AXUIElement? in
                guard let value,CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
                return (value as! AXUIElement)
            }
            var ordered: [AXUIElement] = []
            for element in preferred+elements where !ordered.contains(where: { CFEqual($0,element) }) { ordered.append(element) }
            elements = ordered
            // Stale AX references can coexist with a new reference for the same
            // native window. Prefer the one whose frame matches WindowServer.
            elements = elements.enumerated().map { index,element -> (Int,AXUIElement,Bool) in
                AXUIElementSetMessagingTimeout(element,0.15)
                let exact = NativeWindowResolver.number(element).map { number in cgWindows.contains {
                    ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value == number
                        && ($0[kCGWindowOwnerPID as String] as? Int) == Int(app.processIdentifier)
                } } ?? frame(of: element).map { frame in cgWindows.contains { item in
                    guard (item[kCGWindowOwnerPID as String] as? Int) == Int(app.processIdentifier),
                          (item[kCGWindowLayer as String] as? Int) == 0,
                          let bounds = item[kCGWindowBounds as String] as? [String:Any],
                          let r = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { return false }
                    return abs(r.minX-frame.x) < 3 && abs(r.minY-frame.y) < 3 && abs(r.width-frame.width) < 3 && abs(r.height-frame.height) < 3
                } } ?? false
                return (index,element,exact)
            }.sorted { $0.2 != $1.2 ? $0.2 : $0.0 < $1.0 }.map { $0.1 }
            var occurrences: [String: Int] = [:]
            for element in elements {
                AXUIElementSetMessagingTimeout(element, 0.15)
                let prior = previous.values.first { $0.pid == app.processIdentifier && CFEqual($0.element,element) }
                let isMinimized = observedMinimized(element,key: prior?.id,fallback: prior?.minimized ?? false)
                #if DEBUG
                var moveSettable: DarwinBoolean = false
                let moveResult = AXUIElementIsAttributeSettable(element,kAXPositionAttribute as CFString,&moveSettable)
                let diagnosticFrame = frame(of: element)
                diagnostics.append(["bundle":bundle,"subrole":attribute(element,kAXSubroleAttribute) as? String ?? "missing","frame":diagnosticFrame.map { [$0.x,$0.y,$0.width,$0.height] } ?? [],"minimized":isMinimized,"movableResult":moveResult.rawValue,"movable":moveSettable.boolValue])
                #endif
                let subrole = attribute(element,kAXSubroleAttribute) as? String
                guard subrole == kAXStandardWindowSubrole || (isMinimized && subrole == kAXDialogSubrole)
                        || (alwaysFloating && attribute(element,kAXRoleAttribute) as? String == kAXWindowRole),
                      let frame = frame(of: element) ?? (isMinimized ? prior?.record.originalFrame : nil), frame.width > 80, frame.height > 60 else { continue }
                var settable: DarwinBoolean = false
                let canMove = AXUIElementIsAttributeSettable(element,kAXPositionAttribute as CFString,&settable) == .success && settable.boolValue
                guard alwaysFloating || isMinimized || canMove else { continue }
                let title = attribute(element, kAXTitleAttribute) as? String ?? "Untitled window"
                let ordinal = occurrences[title, default: 0]
                occurrences[title] = ordinal + 1
                let identifier = attribute(element, kAXIdentifierAttribute) as? String
                let document = attribute(element, kAXDocumentAttribute) as? String
                let fingerprint = WindowFingerprint(bundle: bundle,title: title,ordinal: ordinal,identifier: identifier,document: document,frame: frame)
                let sessionRecord = prior?.record
                let exactNativeMatches = cgWindows.filter { item in
                    guard (item[kCGWindowOwnerPID as String] as? Int) == Int(app.processIdentifier),
                          (item[kCGWindowLayer as String] as? Int) == 0,
                          let bounds = item[kCGWindowBounds as String] as? [String:Any],
                          let r = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { return false }
                    return abs(r.minX-frame.x) < 3 && abs(r.minY-frame.y) < 3 && abs(r.width-frame.width) < 3 && abs(r.height-frame.height) < 3
                }
                let stableNumber = NativeWindowResolver.number(element)
                    ?? (exactNativeMatches.count == 1 ? (exactNativeMatches[0][kCGWindowNumber as String] as? NSNumber)?.uint32Value : nil)
                let record = WindowIdentity.record(for: fingerprint,app: app.localizedName ?? bundle,
                    processID: app.processIdentifier,nativeNumber: stableNumber,session: sessionRecord,
                    saved: saved,liveIDs: liveIDs,claimed: claimed)
                let nativeNumber = record.nativeWindowNumber
                if let nativeNumber,claimedNative["\(app.processIdentifier):\(nativeNumber)"] != nil { continue }
                #if DEBUG
                diagnostics.append(["bundle":bundle,"nativeNumber":nativeNumber.map(Int.init) ?? -1,
                                    "onCurrentDesktop":nativeNumber.map(onScreenNumbers.contains) ?? false])
                #endif
                claimed.insert(record.id)
                if let nativeNumber { claimedNative["\(app.processIdentifier):\(nativeNumber)"] = record.id }
                found.append(DiscoveredWindow(record: record, element: element, pid: app.processIdentifier,
                    minimized: isMinimized, icon: app.icon,
                    windowNumber: nativeNumber,
                    fullScreen: attribute(element,"AXFullScreen") as? Bool ?? false,
                    onScreen: nativeNumber.map(onScreenNumbers.contains) ?? false))
            }
        }
        // AXWindows can omit minimized windows and windows on another Space.
        // Keep known live elements; absence from that list is not destruction.
        for old in previous.values where !claimed.contains(old.id) && running.contains(old.pid)
            && (allowedBundles?.contains(old.record.bundleID) ?? true) {
            if let number = old.windowNumber,let canonical = claimedNative["\(old.pid):\(number)"] {
                windowAliases[old.id] = canonical; continue
            }
            let cgWindow = cgWindows.first { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value == old.windowNumber }
            var role: CFTypeRef?
            let roleResult = AXUIElementCopyAttributeValue(old.element,kAXRoleAttribute as CFString,&role)
            if roleResult == .invalidUIElement {
                if cgWindow == nil { destroyedWindowIDs.insert(old.id); invalidatedWindows.removeValue(forKey: old.id) }
                else { invalidatedWindows[old.id] = old }
                continue
            }
            #if DEBUG
            diagnostics.append(["bundle":old.record.bundleID,"retainedCandidate":true,"cgPresent":cgWindow != nil,"role":attribute(old.element,kAXRoleAttribute) as? String ?? "missing"])
            #endif
            guard attribute(old.element,kAXRoleAttribute) as? String == kAXWindowRole || cgWindow != nil else { continue }
            let actual = attribute(old.element,kAXMinimizedAttribute) as? Bool ?? old.minimized
            let pending = pendingMinimization[old.id].map { $0.until > Date() } ?? false
            var retained = old
            retained.record = saved.first { $0.id == old.id } ?? old.record
            retained.minimized = observedMinimized(old.element,key: old.id,fallback: actual)
            #if DEBUG
            diagnostics.append(["bundle":old.record.bundleID,"retainedMinimized":retained.minimized])
            #endif
            retained.onScreen = !retained.minimized && (pending || old.windowNumber.map(onScreenNumbers.contains) == true)
            found.append(retained); claimed.insert(old.id)
        }
        windows = Self.discoveryInventory(found,currentFrame: { self.frame(of: $0) })
        found = Array(windows.values)
        for window in found {
            guard let number = window.record.nativeWindowNumber else { continue }
            for old in saved where old.id != window.id && old.nativeWindowNumber == number && old.nativeProcessID == window.pid {
                windowAliases[old.id] = window.id
            }
        }
        invalidatedWindows = invalidatedWindows.filter { !claimed.contains($0.key) && windowAliases[$0.key] == nil && running.contains($0.value.pid) }
        pendingMinimization = pendingMinimization.filter { windows[$0.key] != nil && $0.value.until > Date() }
        return found.sorted {
            ($0.record.app.localizedLowercase, $0.record.title.localizedLowercase, $0.record.ordinal)
                < ($1.record.app.localizedLowercase, $1.record.title.localizedLowercase, $1.record.ordinal)
        }
    }

    /// Preserve distinct physical windows even if a future discovery edge case
    /// reuses a record ID; dictionary construction must never terminate the app.
    static func discoveryInventory(_ discovered: [DiscoveredWindow],currentFrame: (AXUIElement) -> LayoutRect?) -> [String:DiscoveredWindow] {
        var result: [String:DiscoveredWindow] = [:]
        for var window in discovered {
            if let previous = result[window.id] {
                let previousNumber = previous.windowNumber ?? previous.record.nativeWindowNumber
                let number = window.windowNumber ?? window.record.nativeWindowNumber
                let conflictingNumbers = previousNumber != nil && number != nil && previousNumber != number
                let sameNativeWindow = number != nil && number == previousNumber
                if previous.pid == window.pid && !conflictingNumbers && (sameNativeWindow || CFEqual(previous.element,window.element)) { continue }
                repeat { window.record.id = UUID().uuidString } while result[window.id] != nil
                if let frame = currentFrame(window.element) { window.record.originalFrame = frame }
            }
            result[window.id] = window
        }
        return result
    }

    func frame(of element: AXUIElement) -> LayoutRect? {
        guard let position = attribute(element, kAXPositionAttribute), CFGetTypeID(position) == AXValueGetTypeID(),
              let size = attribute(element, kAXSizeAttribute), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero, dimensions = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &point),
              AXValueGetValue(size as! AXValue, .cgSize, &dimensions) else { return nil }
        return LayoutRect(x: point.x, y: point.y, width: dimensions.width, height: dimensions.height)
    }

    func beginLiveResize(_ keys: Set<String>) {
        endLiveResize(); liveResizing = true
        let state = NativeResizeState(windows: Dictionary(uniqueKeysWithValues: keys.compactMap { key in
            windows[key].map { (key,NativeResizeWindow(element: $0.element,pid: $0.pid)) }
        }))
        resizeState = state; resizePump = LatestResizePump { state.apply($0) }
    }
    func resizeLiveWindows(_ frames: [String:LayoutRect]) { resizePump?.submit(frames) }
    func endLiveResize() {
        if let state = resizeState,let pump = resizePump {
            pump.finish { state.finish() }
            for (key,target) in state.targets {
                if let before = state.originals[key] { resizeAttempts[key] = (target,before) }
            }
            #if DEBUG
            let report: [String:Any] = ["nativeBatches":state.batches,"attributeWrites":state.writes,
                "frameReads":state.frameReads,"longestNativeBatchMilliseconds":state.longestBatchMilliseconds,
                "nativeWorkOnMainThread":state.nativeWorkOnMainThread,"windows":state.targets.keys.sorted(),
                "finalReadbacks":state.actual.mapValues { [$0.x,$0.y,$0.width,$0.height] }]
            if let data = try? JSONSerialization.data(withJSONObject: report,options: [.sortedKeys]) {
                try? data.write(to: FileManager.default.temporaryDirectory.appendingPathComponent("canopy-native-resize.json"),options: .atomic)
            }
            #endif
        }
        resizePump = nil; resizeState = nil; liveResizing = false
        #if DEBUG
        flushMoveDiagnostics()
        #endif
    }
    #if DEBUG
    private func flushMoveDiagnostics() {
        if let data = try? JSONSerialization.data(withJSONObject: moveDiagnostics,options: [.prettyPrinted,.sortedKeys]) {
            try? data.write(to: FileManager.default.temporaryDirectory.appendingPathComponent("canopy-moves.json"),options: .atomic)
        }
    }
    #endif
    @discardableResult
    func move(_ key: String, to rect: LayoutRect) -> Bool {
        guard let window = windows[key] else { return true }
        if resizeAttempts[key]?.target == rect,let actual = frame(of: window.element),Self.frameFitsCell(actual,in: rect) { return true }
        if resizeAttempts[key]?.target != rect,let before = frame(of: window.element) {
            resizeAttempts[key] = (rect,before)
        }
        let application = AXUIElementCreateApplication(window.pid)
        let enhancedUI = attribute(application,"AXEnhancedUserInterface") as? Bool == true
        if enhancedUI {
            _ = AXUIElementSetAttributeValue(application,"AXEnhancedUserInterface" as CFString,kCFBooleanFalse)
        }
        defer {
            if enhancedUI {
                _ = AXUIElementSetAttributeValue(application,"AXEnhancedUserInterface" as CFString,kCFBooleanTrue)
            }
        }
        var point = CGPoint(x: rect.x.rounded(), y: rect.y.rounded())
        var size = CGSize(width: max(80, rect.width.rounded()), height: max(60, rect.height.rounded()))
        guard let p = AXValueCreate(.cgPoint, &point), let s = AXValueCreate(.cgSize, &size) else { return false }
        let before = frame(of: window.element)
        let needsPosition = before.map { abs($0.x-point.x) >= 0.5 || abs($0.y-point.y) >= 0.5 } ?? true
        let needsSize = before.map { abs($0.width-size.width) >= 0.5 || abs($0.height-size.height) >= 0.5 } ?? true
        let firstMove = needsPosition ? AXUIElementSetAttributeValue(window.element,kAXPositionAttribute as CFString,p) : .success
        let resized = needsSize ? AXUIElementSetAttributeValue(window.element,kAXSizeAttribute as CFString,s) : .success
        guard var actual = frame(of: window.element) else { return false }
        // Only correct position again when the app actually clamped it.
        let correctPosition = abs(actual.x-point.x) >= 0.5 || abs(actual.y-point.y) >= 0.5
        let moved = correctPosition ? AXUIElementSetAttributeValue(window.element,kAXPositionAttribute as CFString,p) : .success
        if correctPosition,let readback = frame(of: window.element) { actual = readback }
        #if DEBUG
        moveDiagnostics.append(["bundle":window.record.bundleID,"requested":[point.x,point.y,size.width,size.height],"actual":[actual.x,actual.y,actual.width,actual.height],"results":[firstMove.rawValue,resized.rawValue,moved.rawValue]])
        moveDiagnostics = Array(moveDiagnostics.suffix(50))
        if !liveResizing { flushMoveDiagnostics() }
        #endif
        _ = moved; _ = resized
        return Self.frameFitsCell(actual,in: rect)
    }

    // System Settings and other utilities cap one or both dimensions. A
    // smaller native window at the requested origin remains usable without
    // covering adjacent cells; a window that exceeds its cell must roll back.
    static func frameFitsCell(_ actual: LayoutRect,in target: LayoutRect) -> Bool {
        abs(actual.x-target.x.rounded()) < 3 && abs(actual.y-target.y.rounded()) < 3
            && actual.width >= 80 && actual.height >= 60
            && actual.width <= target.width.rounded()+2 && actual.height <= target.height.rounded()+2
    }

    func verifyMove(_ key: String,to rect: LayoutRect) -> Bool {
        guard let window = windows[key] else { return true }
        if let actual = frame(of: window.element),Self.frameFitsCell(actual,in: rect) { return true }
        // A newly deminiaturized window may reject the first write while the
        // Dock animates. Retry once after the store's settling delay.
        if move(key,to: rect) { return true }
        if let actual = frame(of: window.element),let before = resizeAttempts[key]?.before,
           abs(actual.x-rect.x.rounded()) < 3,abs(actual.y-rect.y.rounded()) < 3 {
            // Only the overflowing axes establish a settled native constraint.
            // Never turn the entire retained frame into a minimum size.
            var minimum = observedMinimums[key] ?? .zero
            if actual.width > rect.width.rounded()+2 && actual.width < before.width-2 { minimum.width = max(minimum.width,actual.width) }
            if actual.height > rect.height.rounded()+2 && actual.height < before.height-2 { minimum.height = max(minimum.height,actual.height) }
            if minimum != .zero { observedMinimums[key] = minimum }
        }
        // A rejected write does not establish a minimum size. The app may
        // still have its previous frame or be unable to resize at all.
        return false
    }

    func raise(_ key: String, activate: Bool = false) {
        guard let window = windows[key], !window.minimized else { return }
        if activate { NSRunningApplication(processIdentifier: window.pid)?.activate(options: []) }
        _ = AXUIElementPerformAction(window.element, kAXRaiseAction as CFString)
    }

    @discardableResult
    func setMinimized(_ key: String, _ value: Bool) -> Bool {
        guard let window = windows[key] else { return false }
        let result = AXUIElementSetAttributeValue(window.element,kAXMinimizedAttribute as CFString,value as CFBoolean)
        let actual = attribute(window.element,kAXMinimizedAttribute) as? Bool ?? !value
        guard result == .success || actual == value else { return false }
        // Successful AX writes acknowledge a request, not the completion of
        // the Dock animation. Keep ownership through that transition.
        pendingMinimization[key] = (value,Date().addingTimeInterval(1))
        windows[key]?.minimized = value; windows[key]?.onScreen = !value
        return true
    }

    var frontmostProcessID: pid_t? { NSWorkspace.shared.frontmostApplication?.processIdentifier }
    func focusedWindow() -> String? {
        frontmostProcessID.flatMap { focusedWindow(in: $0) }
    }
    func focusedWindow(in processID: pid_t) -> String? {
        let root = AXUIElementCreateApplication(processID)
        AXUIElementSetMessagingTimeout(root,0.15)
        for name in [kAXFocusedWindowAttribute,kAXMainWindowAttribute] {
            guard let value = attribute(root,name),CFGetTypeID(value) == AXUIElementGetTypeID() else { continue }
            if let key = windowKey(for: value as! AXUIElement,processID: processID) { return key }
            // A known focused window must not be replaced by a stale main
            // window from a different grid while discovery catches up.
            if name == kAXFocusedWindowAttribute { return nil }
        }
        return nil
    }
    func windowKey(for element: AXUIElement,processID: pid_t) -> String? {
        let candidates = windows.values.filter { $0.pid == processID }
        if let exact = candidates.first(where: { CFEqual($0.element,element) }) { return exact.id }
        let number = NativeWindowResolver.number(element)
        if let number { return Self.resolveFocusIdentity(processID: processID,number: number,frame: nil,windows: candidates,frames: [:]) }
        guard let actual = frame(of: element) else { return nil }
        let frames = Dictionary(candidates.compactMap { candidate -> (String,LayoutRect)? in
            frame(of: candidate.element).map { (candidate.id,$0) }
        },uniquingKeysWith: { first,_ in first })
        return Self.resolveFocusIdentity(processID: processID,number: nil,frame: actual,windows: candidates,frames: frames)
    }
    static func resolveFocusIdentity(processID: pid_t,number: CGWindowID?,frame: LayoutRect?,windows: [DiscoveredWindow],frames: [String:LayoutRect]) -> String? {
        let candidates = windows.filter { $0.pid == processID }
        if let number {
            let matches = candidates.filter { ($0.windowNumber ?? $0.record.nativeWindowNumber) == number }
            return matches.count == 1 ? matches[0].id : nil
        }
        guard let frame else { return nil }
        let matches = candidates.filter { candidate in
            guard let other = frames[candidate.id] else { return false }
            return abs(frame.x-other.x) < 2 && abs(frame.y-other.y) < 2
                && abs(frame.width-other.width) < 2 && abs(frame.height-other.height) < 2
        }
        return matches.count == 1 ? matches[0].id : nil
    }

    @discardableResult
    func restore(_ records: [WindowRecord]) -> Set<String> {
        var failures = Set<String>()
        for record in records {
            guard windows[record.id] != nil else { failures.insert(record.id); continue }
            if !move(record.id, to: visibleFrame(record.originalFrame)) { failures.insert(record.id) }
        }
        return failures
    }

    /// A disconnected monitor must never strand a restored window offscreen.
    func visibleFrame(_ rect: LayoutRect) -> LayoutRect {
        let screens = NSScreen.screens.map(Self.usableFrame)
        guard let screen = screens.first(where: {
            rect.midX >= $0.x && rect.midX <= $0.x + $0.width && rect.midY >= $0.y && rect.midY <= $0.y + $0.height
        }) ?? screens.first else { return rect }
        let width = min(rect.width, screen.width), height = min(rect.height, screen.height)
        return LayoutRect(x: min(max(rect.x, screen.x), screen.x + screen.width - width),
                          y: min(max(rect.y, screen.y), screen.y + screen.height - height), width: width, height: height)
    }

    static func usableFrame(_ screen: NSScreen) -> LayoutRect {
        let primaryTop = NSScreen.screens.first?.frame.maxY ?? screen.frame.maxY
        return LayoutRect(x: screen.visibleFrame.minX, y: primaryTop - screen.visibleFrame.maxY,
                          width: screen.visibleFrame.width, height: screen.visibleFrame.height)
    }

    private func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }
}
