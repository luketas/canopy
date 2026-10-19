import AppKit
import ScreenCaptureKit

@MainActor
protocol PreviewCapturing {
    var authorized: Bool { get }
    func requestPermission() -> Bool
    func capture(_ windows: [DiscoveredWindow], limit: Int) async throws -> [String:NSImage]
}

@MainActor
final class ScreenPreviews: PreviewCapturing {
    var authorized: Bool { CGPreflightScreenCaptureAccess() }
    func requestPermission() -> Bool { CGRequestScreenCaptureAccess() }

    func capture(_ windows: [DiscoveredWindow], limit: Int) async throws -> [String:NSImage] {
        // Never let the content API produce an unexpected permission prompt.
        guard authorized else { return [:] }
        let content = try await SCShareableContent.excludingDesktopWindows(true,onScreenWindowsOnly: false)
        var images: [String:NSImage] = [:]
        for entry in windows.prefix(max(0,limit)) {
            guard !Task.isCancelled, authorized else { break }
            guard let window = content.windows.first(where: { candidate in
                if let number = entry.windowNumber { return candidate.windowID == number }
                return candidate.owningApplication?.processID == entry.pid && candidate.title == entry.record.title
            }) else { continue }
            let ratio = min(1, 900/max(1,max(window.frame.width,window.frame.height)))
            let configuration = SCStreamConfiguration()
            configuration.width = max(1,Int(window.frame.width*ratio))
            configuration.height = max(1,Int(window.frame.height*ratio))
            configuration.showsCursor = false
            configuration.ignoreShadowsSingleWindow = true
            let filter = SCContentFilter(desktopIndependentWindow: window)
            do {
                let cgImage = try await SCScreenshotManager.captureImage(contentFilter: filter,configuration: configuration)
                images[entry.id] = NSImage(cgImage: cgImage,size: NSSize(width: window.frame.width,height: window.frame.height))
            } catch {
                // A closed or protected window must not abort the rest of a capture batch.
                if !authorized { throw error }
            }
        }
        return images
    }
}

@MainActor
final class PreviewCache: ObservableObject {
    @Published private(set) var images: [String:NSImage] = [:]
    @Published private(set) var status: String?
    private let provider: any PreviewCapturing
    private var timestamps: [String:Date] = [:]
    private var costs: [String:Int] = [:]
    private var generation = 0
    private var task: Task<Void,Never>?
    private var timer: Timer?
    private var windows: [DiscoveredWindow] = []
    private let budget: Int
    private let maximumEntries: Int
    var onImagesChanged: (() -> Void)?

    init(provider: (any PreviewCapturing)? = nil, budget: Int = 64*1024*1024, maximumEntries: Int = 64) {
        self.provider = provider ?? ScreenPreviews(); self.budget = max(1,budget); self.maximumEntries = max(1,maximumEntries)
    }
    var authorized: Bool { provider.authorized }
    func requestPermission() -> Bool { provider.requestPermission() }
    func update(windows: [DiscoveredWindow], enabled: Bool) {
        self.windows = windows
        guard enabled else { stop(); return }
        guard provider.authorized else {
            stop(); status = "Enable Screen Recording in System Settings to use window previews."
            return
        }
        let live = Set(windows.map(\.id))
        for id in Array(images.keys) where !live.contains(id) { evict(id) }
        if timer == nil {
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            }
            refresh()
        }
    }
    func refresh() {
        guard task == nil, provider.authorized, !windows.isEmpty else { return }
        let now = Date()
        let batch = windows.filter { now.timeIntervalSince(timestamps[$0.id] ?? .distantPast) > 2 }
            .sorted { (timestamps[$0.id] ?? .distantPast) < (timestamps[$1.id] ?? .distantPast) }
        guard !batch.isEmpty else { return }
        let token = generation
        task = Task { [weak self] in await self?.captureBatch(batch,token: token) }
    }
    private func captureBatch(_ batch: [DiscoveredWindow],token: Int) async {
            defer { if token == generation { task = nil } }
            do {
                let captured = try await provider.capture(batch,limit: 6)
                guard !Task.isCancelled, token == generation else { return }
                for (id,image) in captured {
                    let pixels = image.representations.first
                    let width: Int = pixels?.pixelsWide ?? Int(image.size.width)
                    let height: Int = pixels?.pixelsHigh ?? Int(image.size.height)
                    let cost: Int = max(1,width*height*4)
                    guard cost <= budget else { continue }
                    images[id] = image; costs[id] = cost; timestamps[id] = Date()
                }
                // Avoid retrying a protected window on every tick.
                for window in batch.prefix(6) where captured[window.id] == nil { timestamps[window.id] = Date() }
                while images.count > maximumEntries || costs.values.reduce(0, { $0+$1 }) > budget {
                    guard let oldest = images.keys.min(by: { (timestamps[$0] ?? .distantPast) < (timestamps[$1] ?? .distantPast) }) else { break }
                    evict(oldest)
                }
                status = nil; onImagesChanged?()
            } catch {
                guard token == generation else { return }
                status = "Window previews could not be refreshed: \(error.localizedDescription)"
                if !provider.authorized { stop() }
            }
    }
    private func evict(_ id: String) { images.removeValue(forKey: id); costs.removeValue(forKey: id); timestamps.removeValue(forKey: id) }
    func stop() {
        let hadImages = !images.isEmpty
        generation += 1; task?.cancel(); task = nil; timer?.invalidate(); timer = nil
        windows = []; if hadImages { images = [:] }; timestamps = [:]; costs = [:]
        if hadImages { onImagesChanged?() }
    }
    func stopTimer() { timer?.invalidate(); timer = nil }
}
