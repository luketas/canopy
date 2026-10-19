import Testing
import AppKit
@testable import Canopy

@MainActor
final class FakePreviewProvider: PreviewCapturing {
    var authorized = true
    var permissionRequests = 0
    var captureCalls = 0
    var delay = false
    func requestPermission() -> Bool { permissionRequests += 1; return authorized }
    func capture(_ windows: [DiscoveredWindow],limit: Int) async throws -> [String:NSImage] {
        captureCalls += 1
        if delay { try await Task.sleep(for: .milliseconds(40)) }
        return Dictionary(uniqueKeysWithValues: windows.prefix(limit).map { window in
            (window.id,NSImage(size: NSSize(width: 100,height: 100)))
        })
    }
}

@Test @MainActor
func previewCacheDoesNotRequestPermissionOrCaptureWithoutExplicitAuthorization() async throws {
    let provider = FakePreviewProvider(); provider.authorized = false
    let cache = PreviewCache(provider: provider)
    cache.update(windows: Array(FakeWindows().windows.values),enabled: true)
    try await Task.sleep(for: .milliseconds(5))
    #expect(provider.captureCalls == 0); #expect(provider.permissionRequests == 0)
    #expect(cache.images.isEmpty); cache.stop()
}

@Test @MainActor
func previewCacheBoundsMemoryAndDoesNotRecaptureOnEveryUIUpdate() async throws {
    let provider = FakePreviewProvider(),cache = PreviewCache(provider: provider,budget: 40001,maximumEntries: 1)
    let windows = Array(FakeWindows().windows.values)
    cache.update(windows: windows,enabled: true)
    try await Task.sleep(for: .milliseconds(10))
    #expect(cache.images.count == 1)
    for _ in 0..<20 { cache.update(windows: windows,enabled: true) }
    try await Task.sleep(for: .milliseconds(5))
    #expect(provider.captureCalls == 1)
    cache.stop(); #expect(cache.images.isEmpty)
}

@Test @MainActor
func stoppingPreviewsRejectsAnInFlightCapture() async throws {
    let provider = FakePreviewProvider(); provider.delay = true
    let cache = PreviewCache(provider: provider)
    cache.update(windows: Array(FakeWindows().windows.values),enabled: true)
    await Task.yield(); cache.stop()
    try await Task.sleep(for: .milliseconds(50))
    #expect(cache.images.isEmpty)
}
