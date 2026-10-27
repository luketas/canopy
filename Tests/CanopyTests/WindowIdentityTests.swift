import Testing
import AppKit
import CanopyCore
@testable import Canopy

private let chromeBundle = "com.google.Chrome"
private let chromeFrame = LayoutRect(x: 50,y: 80,width: 900,height: 650)

private func chromeRecord(_ id: String,number: UInt32,title: String = "New Tab",pid: Int32 = 4321) -> WindowRecord {
    WindowRecord(id: id,bundleID: chromeBundle,app: "Google Chrome",title: title,ordinal: 0,
                 originalFrame: chromeFrame,axIdentifier: "ChromeWindow",nativeWindowNumber: number,nativeProcessID: pid)
}
private func chromeFingerprint(_ title: String = "New Incognito Tab",ordinal: Int = 0) -> WindowFingerprint {
    WindowFingerprint(bundle: chromeBundle,title: title,ordinal: ordinal,identifier: "ChromeWindow",frame: chromeFrame)
}

@Test(arguments: [[0,1,2],[0,2,1],[1,0,2],[1,2,0],[2,0,1],[2,1,0]])
func openingTwoIncognitoWindowsCannotStealTheManagedChromeWindowsIdentity(order: [Int]) {
    let normal = chromeRecord("managed-chrome",number: 100)
    // This soft match is strong enough to trigger the old discovery bug even
    // though WindowServer says the incognito window is a different window.
    #expect(WindowMatcher.match(chromeFingerprint(),candidates: [(normal.id,normal.fingerprint)]) == normal.id)
    var claimed = Set<String>(),records: [UInt32:WindowRecord] = [:]
    for index in order {
        let number = UInt32(100+index)
        let record = WindowIdentity.record(for: index == 0 ? chromeFingerprint("New Tab") : chromeFingerprint(),
            app: "Google Chrome",processID: 4321,nativeNumber: number,session: index == 0 ? normal : nil,
            saved: [normal],liveIDs: [normal.id],claimed: claimed)
        #expect(claimed.insert(record.id).inserted)
        records[number] = record
    }
    #expect(records.count == 3)
    #expect(records[100]?.id == normal.id)
    #expect(records[101]?.id != normal.id && records[102]?.id != normal.id)
    #expect(Set(records.values.map(\.id)).count == 3)
}

@Test
func repeatedIncognitoTitlesAndReorderedAxListsRetainNativeWindowIdentity() throws {
    let saved = [chromeRecord("normal",number: 100),chromeRecord("private-a",number: 101,title: "New Incognito Tab"),chromeRecord("private-b",number: 102,title: "New Incognito Tab")]
    var claimed = Set<String>()
    for (ordinal,old) in saved.reversed().enumerated() {
        let record = WindowIdentity.record(for: chromeFingerprint("New Tab",ordinal: ordinal),app: "Google Chrome",
            processID: 4321,nativeNumber: old.nativeWindowNumber,session: nil,saved: saved,
            liveIDs: Set(saved.map(\.id)),claimed: claimed)
        #expect(record.id == old.id)
        #expect(record.originalFrame == old.originalFrame)
        #expect(claimed.insert(record.id).inserted)
    }
}

@Test
func unavailableNativeLookupDoesNotBorrowALiveChromeWindowsRecordOrNativeNumber() {
    let normal = chromeRecord("normal",number: 100)
    let record = WindowIdentity.record(for: chromeFingerprint(),app: "Google Chrome",processID: 4321,
        nativeNumber: nil,session: nil,saved: [normal],liveIDs: [normal.id],claimed: [])
    #expect(record.id != normal.id)
    #expect(record.nativeWindowNumber == nil && record.nativeProcessID == nil)
    // A soft reconnect after an app restart can retain a saved grid slot, but
    // it must not inherit the old process's native WindowServer number.
    let relaunched = WindowIdentity.record(for: chromeFingerprint("New Tab"),app: "Google Chrome",processID: 9876,
        nativeNumber: nil,session: nil,saved: [normal],liveIDs: [],claimed: [])
    #expect(relaunched.id == normal.id)
    #expect(relaunched.nativeWindowNumber == nil && relaunched.nativeProcessID == nil)
}

@Test
func aClaimedOrReusedSessionReferenceCannotProduceADuplicateRecordId() {
    let old = chromeRecord("normal",number: 100)
    let claimed = WindowIdentity.record(for: chromeFingerprint(),app: "Google Chrome",processID: 4321,
        nativeNumber: 100,session: old,saved: [old],liveIDs: [old.id],claimed: [old.id])
    #expect(claimed.id != old.id)
    let reused = WindowIdentity.record(for: chromeFingerprint(),app: "Google Chrome",processID: 4321,
        nativeNumber: 101,session: old,saved: [old],liveIDs: [old.id],claimed: [])
    #expect(reused.id != old.id && reused.nativeWindowNumber == 101)
    let continued = WindowIdentity.record(for: chromeFingerprint("New document"),app: "Google Chrome",processID: 4321,
        nativeNumber: nil,session: old,saved: [old],liveIDs: [old.id],claimed: [])
    #expect(continued.id == old.id && continued.nativeWindowNumber == 100)
}

@Test
func ambiguousRecoveryCandidatesStaySeparateInsteadOfUsingAnOrdinalIdentityFallback() {
    let a = chromeRecord("a",number: 100,pid: 1000),b = chromeRecord("b",number: 101,pid: 1000)
    let record = WindowIdentity.record(for: chromeFingerprint("New Tab"),app: "Google Chrome",processID: 4321,
        nativeNumber: 200,session: nil,saved: [a,b],liveIDs: [],claimed: [])
    #expect(record.id != a.id && record.id != b.id)
}

@Test @MainActor
func duplicateRecordIdsCannotCrashTheInventoryOrDiscardDistinctIncognitoWindows() throws {
    let bridge = FakeWindows()
    var a = try #require(bridge.windows["a"]),b = try #require(bridge.windows["b"]),c = try #require(bridge.windows["c"])
    a.windowNumber = 100; b.windowNumber = 101; c.windowNumber = 102
    b.pid = a.pid; c.pid = a.pid
    b.record.id = a.id; c.record.id = a.id
    b.record.originalFrame = a.record.originalFrame; c.record.originalFrame = a.record.originalFrame
    let inventory = WindowBridge.discoveryInventory([a,b,c],currentFrame: { bridge.frame(of: $0) })
    #expect(inventory.count == 3)
    #expect(Set(inventory.values.compactMap(\.windowNumber)) == [100,101,102])
    #expect(inventory[a.id]?.windowNumber == 100)
    #expect(inventory.values.first { $0.windowNumber == 101 }?.record.originalFrame == bridge.frames["b"])
    #expect(inventory.values.first { $0.windowNumber == 102 }?.record.originalFrame == bridge.frames["c"])
    var sameWindow = b; sameWindow.windowNumber = a.windowNumber
    #expect(WindowBridge.discoveryInventory([a,sameWindow],currentFrame: { bridge.frame(of: $0) }).count == 1)
}

@Test @MainActor
func incognitoWindowChurnKeepsTheRegularChromeGridAndRestorationBaseline() throws {
    let bridge = FakeWindows()
    let original = try #require(bridge.windows["a"])
    let normal = chromeRecord("normal",number: 100)
    var native = original; native.record = normal; native.windowNumber = 100; native.pid = 4321
    bridge.windows = [normal.id:native]; bridge.frames = [normal.id:chromeFrame]
    bridge.runningBundleIDs = [chromeBundle]
    let (store,directory) = makeStore(bridge: bridge)
    defer { store.shutdown(); try? FileManager.default.removeItem(at: directory) }
    store.addWindowsToCurrentGrid([normal.id]); store.applyCurrentGrid()
    let grid = store.current,baseline = store.record(normal.id)?.originalFrame
    var privateIDs = Set<String>()
    var claimed: Set<String> = [normal.id]
    for index in 1...2 {
        let record = WindowIdentity.record(for: chromeFingerprint(),app: "Google Chrome",processID: 4321,
            nativeNumber: UInt32(100+index),session: nil,saved: store.records,liveIDs: [normal.id],claimed: claimed)
        claimed.insert(record.id); privateIDs.insert(record.id)
        var window = native; window.record = record; window.windowNumber = record.nativeWindowNumber
        // Distinct fake AX handles model separate native Chrome windows.
        window.element = AXUIElementCreateApplication(pid_t(5000+index))
        bridge.windows[record.id] = window; bridge.frames[record.id] = chromeFrame
    }
    store.refresh()
    #expect(store.records.count == 3)
    #expect(store.current == grid && store.currentGridWindowIDs == [normal.id])
    #expect(store.record(normal.id)?.originalFrame == baseline)
    for key in privateIDs { bridge.windows.removeValue(forKey: key); bridge.frames.removeValue(forKey: key) }
    bridge.destroyedWindowIDs = privateIDs; store.refresh()
    #expect(store.records.map(\.id) == [normal.id])
    #expect(store.current == grid && store.record(normal.id)?.originalFrame == baseline)
    #expect(!bridge.moves.contains { privateIDs.contains($0.0) })
}
