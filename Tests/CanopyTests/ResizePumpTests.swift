import Testing
import Foundation
import CanopyCore
@testable import Canopy

private final class ResizePumpLog: @unchecked Sendable {
    private let lock = NSLock()
    private var frames: [Double] = []
    private var mainThread = false
    func record(_ width: Double) {
        lock.lock(); defer { lock.unlock() }
        frames.append(width); mainThread = mainThread || Thread.isMainThread
    }
    func observeThread() {
        lock.lock(); defer { lock.unlock() }; mainThread = mainThread || Thread.isMainThread
    }
    var snapshot: ([Double],Bool) {
        lock.lock(); defer { lock.unlock() }; return (frames,mainThread)
    }
}

@Test @MainActor
func slowNativeResizeDoesNotBlockInputOrReplayIntermediatePointerPositions() async throws {
    let log = ResizePumpLog(),release = DispatchSemaphore(value: 0)
    defer { release.signal() }
    let pump = LatestResizePump { frames in
        guard let frame = frames["window"] else { return }
        log.record(frame.width)
        if frame.width == 100 { _ = release.wait(timeout: .now()+5) }
    }
    pump.submit(["window":LayoutRect(width: 100,height: 600)])
    let deadline = Date().addingTimeInterval(5)
    while log.snapshot.0.isEmpty,Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
    #expect(log.snapshot.0 == [100]) // Input is running while the native worker waits.
    for width in 101...300 { pump.submit(["window":LayoutRect(width: Double(width),height: 600)]) }
    #expect(log.snapshot.0 == [100])
    release.signal(); pump.finish { log.observeThread() }
    #expect(log.snapshot.0 == [100,300])
    #expect(!log.snapshot.1)
    let completed = log.snapshot.0
    try await Task.sleep(for: .milliseconds(30))
    #expect(log.snapshot.0 == completed) // The finish fence leaves no late writes.
}
