import Testing
import AppKit
import ApplicationServices
import CanopyCore
@testable import Canopy

@MainActor
final class FakeWindows: WindowManaging {
    var trusted = true
    var preservesUnlistedWindows = false
    var destroyedWindowIDs = Set<String>()
    var windowAliases: [String:String] = [:]
    var preferredInitialPaneSize = CGSize.zero
    var windows: [String: DiscoveredWindow] = [:]
    var moves: [(String, LayoutRect)] = []
    var restores: [String] = []
    var frames: [String: LayoutRect] = [:]
    var raised: [String] = []
    var activated: [String] = []
    var restoreFailures: Set<String> = []
    var permissionRequests = 0
    var runningBundleIDs: Set<String> = ["fixture.a","fixture.b","fixture.c"]
    var minimizeRequests: [(String,Bool)] = []
    var focused: String?
    var frontmostProcessID: pid_t?
    var discoveredTitles: [String:String] = [:]
    var verificationCount = 0
    var operations: [String] = []
    var deferMoves = false
    var minimums: [String:CGSize] = [:]
    func minimumSize(_ key: String) -> CGSize? { minimums[key] }

    init() {
        for (index, key) in ["a", "b", "c"].enumerated() {
            let frame = LayoutRect(x: Double(70 + index * 40), y: 70, width: 700, height: 500)
            let record = WindowRecord(id: key, bundleID: "fixture.\(key)", app: "Fixture \(key)",
                title: "Window \(key)", ordinal: 0, originalFrame: frame)
            windows[key] = DiscoveredWindow(record: record, element: AXUIElementCreateApplication(pid_t(index + 1000)),
                pid: pid_t(index + 1000), minimized: false, icon: nil)
            frames[key] = frame
        }
    }
    func requestPermission() { permissionRequests += 1 }
    func discover(saved: [WindowRecord], excluded: Set<String>) -> [DiscoveredWindow] {
        windows.values.filter { !excluded.contains($0.record.bundleID) }.sorted { $0.id < $1.id }.map { window in
            var result = window
            if let record = saved.first(where: { $0.id == result.id }) { result.record = record }
            if let title = discoveredTitles[result.id] { result.record.title = title }
            return result
        }
    }
    func frame(of element: AXUIElement) -> LayoutRect? {
        windows.values.first { CFEqual($0.element, element) }.flatMap { frames[$0.id] }
    }
    func move(_ key: String, to rect: LayoutRect) -> Bool {
        operations.append("move:\(key)"); moves.append((key,rect)); if deferMoves { return false }; frames[key] = rect; return true
    }
    func raise(_ key: String, activate: Bool) {
        operations.append("raise:\(key):\(activate)"); raised.append(key)
        if activate { activated.append(key) }
    }
    func focusedWindow() -> String? { focused }
    func setMinimized(_ key: String,_ value: Bool) -> Bool {
        guard windows[key] != nil else { return false }
        operations.append("minimize:\(key):\(value)"); minimizeRequests.append((key,value)); windows[key]?.minimized = value; windows[key]?.onScreen = !value; return true
    }
    func verifyMove(_ key: String,to rect: LayoutRect) -> Bool {
        verificationCount += 1
        guard windows[key] != nil else { return true }
        guard let actual = frames[key] else { return false }
        return abs(actual.x-rect.x.rounded()) < 3 && abs(actual.y-rect.y.rounded()) < 3
            && abs(actual.width-rect.width.rounded()) < 3 && abs(actual.height-rect.height.rounded()) < 3
    }
    func restore(_ records: [WindowRecord]) -> Set<String> {
        restores.append(contentsOf: records.map(\.id))
        for record in records where !restoreFailures.contains(record.id) { frames[record.id] = record.originalFrame }
        return restoreFailures.intersection(records.map(\.id)).union(Set(records.map(\.id)).subtracting(windows.keys))
    }
}

@MainActor
func makeStore(demo: Bool = false, bridge: FakeWindows) -> (WorkspaceStore, URL) {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("canopy-tests-\(UUID().uuidString)")
    let store = WorkspaceStore(demo: demo, bridge: bridge, storageURL: directory.appendingPathComponent("workspace.json"),screens: { fixtureDisplays })
    return (store, directory)
}

@Test @MainActor
func pausedStoreNeverMovesOrRestoresWindowsOnQuit() throws {
    let bridge = FakeWindows(), (store, directory) = makeStore(bridge: bridge)
    defer { try? FileManager.default.removeItem(at: directory) }
    #expect(store.records.count == 3)
    store.dock("a", target: nil, edge: .right)
    store.showEverything(); store.saveView(1); store.refresh(); store.shutdown()
    #expect(bridge.moves.isEmpty)
    #expect(bridge.restores.isEmpty)
}

@Test @MainActor
func temporarilyMissingOccludedWindowsKeepTheirTreeAndRestorationBaseline() throws {
    let bridge = FakeWindows(), (store,directory) = makeStore(bridge: bridge)
    defer { store.shutdown(); try? FileManager.default.removeItem(at: directory) }
    store.arrange()
    let baseline = store.record("b")!.originalFrame
    store.focus(store.current!.root!.leaf(containing: "a")!.id)
    #expect(store.occludedWindows.contains("b"))
    let minimized = bridge.windows.removeValue(forKey: "b")!
    store.refresh()
    #expect(store.current?.root?.leaf(containing: "b") != nil)
    #expect(store.record("b")?.originalFrame == baseline)
    #expect(store.movedWindows.contains("b"))
    bridge.windows["b"] = minimized
    store.refresh(); store.floatAll()
    #expect(bridge.frames["b"] == baseline)
    #expect(bridge.windows["b"]?.minimized == false)
    #expect(!store.hasWindowsToRestore)
}

@Test @MainActor
func nativePlacementVerificationWaitsForSettledFramesAndReportsPersistentFailures() async throws {
    let bridge = FakeWindows(), (store,directory) = makeStore(bridge: bridge)
    defer { store.shutdown(); try? FileManager.default.removeItem(at: directory) }
    bridge.deferMoves = true
    store.arrange()
    #expect(store.message == nil)
    for (key,rect) in bridge.moves { bridge.frames[key] = rect }
    let settledDeadline = Date().addingTimeInterval(5)
    while bridge.verificationCount < bridge.moves.count,Date() < settledDeadline {
        try await Task.sleep(nanoseconds: 20_000_000)
    }
    #expect(store.message == nil)
    #expect(bridge.verificationCount >= bridge.moves.count)
    store.beginResize()
    store.resize(store.current!.root!.id,ratio: 0.4,finished: true)
    let verificationDeadline = Date().addingTimeInterval(5)
    while store.message == nil,Date() < verificationDeadline {
        try await Task.sleep(nanoseconds: 20_000_000)
    }
    #expect(store.message?.contains("previous layout") == true)
    #expect(store.isArranging)
    #expect(store.hasWindowsToRestore)
    #expect(bridge.windows.values.allSatisfy { !$0.minimized })
}

@Test @MainActor
func rejectedResizeRestoresTheBaselineAndRemovesDesktopControls() async throws {
    let bridge = FakeWindows(), (store,directory) = makeStore(bridge: bridge)
    defer { store.shutdown(); try? FileManager.default.removeItem(at: directory) }
    let baseline = bridge.frames
    bridge.deferMoves = true
    var controlsVisible = false
    store.onLayoutDidApply = { _ in controlsVisible = true }
    store.onPause = { controlsVisible = false }
    store.arrange()
    #expect(controlsVisible)
    // Native verification retries asynchronously. A fixed sleep can wake
    // before its MainActor task on a loaded CI host; wait for the actual pause.
    let restoreDeadline = Date().addingTimeInterval(5)
    while store.isArranging,Date() < restoreDeadline {
        try await Task.sleep(nanoseconds: 20_000_000)
    }
    #expect(!controlsVisible)
    #expect(!store.isArranging)
    #expect(bridge.frames == baseline)
    #expect(bridge.minimizeRequests.isEmpty)
    #expect(store.message?.contains("Your windows were restored") == true)
}

@Test @MainActor
func initialArrangementThatCannotFitLeavesNativeWindowsUntouched() throws {
    let bridge = FakeWindows()
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let store = WorkspaceStore(bridge: bridge,storageURL: directory.appendingPathComponent("workspace.json"),screens: {
        [DisplayDescriptor(id: "small",name: "Small",frame: LayoutRect(width: 200,height: 100))]
    })
    defer { store.shutdown(); try? FileManager.default.removeItem(at: directory) }
    store.arrange()
    #expect(!store.isArranging)
    #expect(bridge.moves.isEmpty)
    #expect(bridge.minimizeRequests.isEmpty)
    #expect(store.message?.contains("Not enough room") == true)
}

@Test @MainActor
func unavailableOwnedWindowsStayRetryableThroughRestore() throws {
    let bridge = FakeWindows(), (store,directory) = makeStore(bridge: bridge)
    defer { store.shutdown(); try? FileManager.default.removeItem(at: directory) }
    store.arrange()
    store.focus(store.current!.root!.leaf(containing: "a")!.id)
    let hidden = bridge.windows.removeValue(forKey: "b")!
    store.refresh(); store.floatAll()
    #expect(store.hasWindowsToRestore)
    #expect(store.movedWindows.contains("b"))
    #expect(store.message?.contains("could not be restored") == true)
    bridge.windows["b"] = hidden
    store.refresh(); store.floatAll()
    #expect(!store.hasWindowsToRestore)
    #expect(bridge.windows["b"]?.minimized == false)
}

@Test @MainActor
func offSpaceWindowsRetainSavedLayoutAcrossAnEmptyNativeWindowList() throws {
    let bridge = FakeWindows(); bridge.preservesUnlistedWindows = true
    let (store,directory) = makeStore(bridge: bridge)
    defer { store.shutdown(); try? FileManager.default.removeItem(at: directory) }
    store.arrange(); store.floatAll()
    let leaf = store.current?.root?.leaf(containing: "b")?.id
    let window = bridge.windows.removeValue(forKey: "b")!
    store.refresh()
    #expect(store.dormantWindows.contains("b"))
    #expect(store.current?.root?.leaf(containing: "b")?.id == leaf)
    bridge.windows["b"] = window; store.refresh()
    #expect(!store.dormantWindows.contains("b"))
    #expect(store.current?.root?.leaf(containing: "b")?.id == leaf)
}

@Test @MainActor
func soleRecoveryEntryReconnectsAfterBrowserTitleAndDocumentChange() throws {
    let bridge = FakeWindows(),(store,directory) = makeStore(bridge: bridge)
    defer { store.shutdown(); try? FileManager.default.removeItem(at: directory) }
    var entry = bridge.windows["a"]!.record
    entry.id = "previous-session"; entry.originalFrame = LayoutRect(x: 12,y: 34,width: 800,height: 650)
    entry.title = "Old page"; entry.document = "https://example.com/old"
    store.pendingRecovery = [entry]
    store.recoverWindows()
    #expect(store.pendingRecovery.isEmpty)
    #expect(bridge.frames["a"] == entry.originalFrame)
}

@Test @MainActor
func absentRecoveryAppDoesNotPreventArrangingAvailableApplications() throws {
    let bridge = FakeWindows(),(store,directory) = makeStore(bridge: bridge)
    defer { store.shutdown(); try? FileManager.default.removeItem(at: directory) }
    var entry = bridge.windows["a"]!.record
    entry.id = "absent"; entry.bundleID = "fixture.absent"
    store.pendingRecovery = [entry]
    store.arrange()
    #expect(store.isArranging)
    #expect(store.pendingRecovery == [entry])
    #expect(Set(bridge.moves.map(\.0)) == ["a","b","c"])
}

@Test @MainActor
func demoCommandsDoNotTouchTheDesktopOrWriteState() {
    let bridge = FakeWindows(), (store, directory) = makeStore(demo: true, bridge: bridge)
    defer { store.shutdown() }
    #expect(store.records.count == 4)
    #expect(store.current?.root?.allWindows.count == 5)
    store.arrange(); store.zoomIn(); store.saveView(1); store.showEverything(); store.recallView(1)
    store.floatWindow("demo-browser"); store.undo(); store.redo(); store.floatAll()
    #expect(bridge.moves.isEmpty)
    #expect(bridge.restores.isEmpty)
    #expect(!FileManager.default.fileExists(atPath: directory.path))
}

@Test @MainActor
func permissionDenialKeepsDemoAndRequestsPermissionOnlyOnExplicitAction() {
    let bridge = FakeWindows(); bridge.trusted = false
    let (store, _) = makeStore(bridge: bridge)
    defer { store.shutdown() }
    #expect(store.isDemo)
    #expect(bridge.permissionRequests == 0)
    store.useRealWindows()
    #expect(bridge.permissionRequests == 1)
    #expect(store.isDemo)
    #expect(bridge.moves.isEmpty)
    #expect(store.message?.contains("Accessibility") == true)
}

@Test @MainActor
func arrangementRestoresTheFrameFromImmediatelyBeforeTheFirstMove() throws {
    let bridge = FakeWindows(), (store, directory) = makeStore(bridge: bridge)
    defer { store.shutdown(); try? FileManager.default.removeItem(at: directory) }
    let changed = LayoutRect(x: 110, y: 120, width: 600, height: 450)
    bridge.frames["a"] = changed
    store.arrange()
    #expect(store.isArranging)
    #expect(bridge.moves.count == 3)
    #expect(store.record("a")?.originalFrame == changed)
    store.refresh()
    #expect(store.record("a")?.originalFrame == changed)
    store.floatAll()
    #expect(bridge.frames["a"] == changed)
    #expect(Set(bridge.restores) == ["a", "b", "c"])
    #expect(!store.isArranging)
    #expect(!store.hasWindowsToRestore)
}

@Test @MainActor
func restoreFailuresRemainRetryableWhilePaused() throws {
    let bridge = FakeWindows(), (store, directory) = makeStore(bridge: bridge)
    defer { store.shutdown(); try? FileManager.default.removeItem(at: directory) }
    store.arrange(); bridge.restoreFailures = ["a"]
    store.floatAll()
    #expect(store.hasWindowsToRestore)
    #expect(!store.isArranging)
    bridge.restoreFailures = []; bridge.restores = []
    store.floatAll()
    #expect(bridge.restores == ["a"])
    #expect(!store.hasWindowsToRestore)
}

@Test @MainActor
func invalidDockDoesNotLoseSourceAndUndoRestoresTheTree() {
    let bridge = FakeWindows(), (store, _) = makeStore(demo: true, bridge: bridge)
    defer { store.shutdown() }
    let before = store.current?.root
    store.dock("demo-code", target: "missing", edge: .left)
    #expect(store.current?.root == before)
    let target = store.current!.root!.leaf(containing: "demo-browser")!.id
    store.dock("demo-code", target: target, edge: .tab)
    #expect(store.current?.root?.allWindows.count == 5)
    #expect(store.current?.root?.leaf(containing: "demo-browser")?.windows.contains("demo-code") == true)
    store.undo()
    #expect(store.current?.root == before)
}

@Test @MainActor
func relaunchPreservesLayoutButStartsPaused() throws {
    let bridge = FakeWindows(), (store, directory) = makeStore(bridge: bridge)
    defer { try? FileManager.default.removeItem(at: directory) }
    store.arrange(); store.saveView(1)
    let root = store.current?.root
    store.shutdown(); bridge.moves = []; bridge.restores = []
    let restored = WorkspaceStore(bridge: bridge, storageURL: directory.appendingPathComponent("workspace.json"),screens: { fixtureDisplays })
    defer { restored.shutdown() }
    #expect(restored.current?.root == root)
    #expect(!restored.isArranging)
    #expect(restored.current?.savedViews["1"] != nil)
    #expect(bridge.moves.isEmpty)
    #expect(bridge.restores.isEmpty)
}

@Test @MainActor
func closedWindowsPruneTheTreeButMinimizedWindowsRetainTheirSlot() throws {
    let bridge = FakeWindows(), (store, directory) = makeStore(bridge: bridge)
    defer { store.shutdown(); try? FileManager.default.removeItem(at: directory) }
    store.arrange()
    let originalLeaf = store.current?.root?.leaf(containing: "a")?.id
    bridge.windows["a"]?.minimized = true
    store.refresh()
    #expect(store.current?.root?.leaf(containing: "a")?.id == originalLeaf)
    #expect(store.minimized.contains("a"))
    bridge.windows.removeValue(forKey: "b"); bridge.destroyedWindowIDs.insert("b")
    store.refresh()
    #expect(store.current?.root?.allWindows.contains("b") == false)
    #expect(store.current?.root?.allWindows.contains("a") == true)
}

@Test @MainActor
func demoArrangeURLCannotActivateRealWindowManagement() {
    let bridge = FakeWindows(), (store, _) = makeStore(demo: true, bridge: bridge)
    defer { store.shutdown() }
    store.handleURL(URL(string: "canopy://arrange")!)
    store.handleURL(URL(string: "canopy://resume")!)
    #expect(store.isDemo)
    #expect(!store.isArranging)
    #expect(bridge.moves.isEmpty)
}

@Test @MainActor
func unreadableWorkspaceIsNeverOverwritten() throws {
    let bridge = FakeWindows()
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("canopy-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("workspace.json"), bytes = Data("{invalid json".utf8)
    try bytes.write(to: url)
    let store = WorkspaceStore(bridge: bridge, storageURL: url,screens: { fixtureDisplays })
    #expect(store.message?.contains("Saving is disabled") == true)
    store.dock("a", target: nil, edge: .right); store.saveView(1); store.shutdown()
    #expect(try Data(contentsOf: url) == bytes)
}

@Test @MainActor
func undoCannotResurrectAClosedWindow() throws {
    let bridge = FakeWindows(), (store, directory) = makeStore(bridge: bridge)
    defer { store.shutdown(); try? FileManager.default.removeItem(at: directory) }
    store.arrange(); store.floatWindow("a")
    bridge.windows.removeValue(forKey: "a")
    store.refresh(); store.undo()
    #expect(store.current?.root?.allWindows.contains("a") == false)
}

@Test @MainActor
func dockingIntoZoomedLeafKeepsTheNewSplitInView() {
    let bridge = FakeWindows(), (store, _) = makeStore(demo: true, bridge: bridge)
    defer { store.shutdown() }
    let leaf = store.current!.root!.leaf(containing: "demo-browser")!
    store.focus(leaf.id)
    store.dock("demo-code", target: leaf.id, edge: .left)
    #expect(store.focusedNode?.allWindows.contains("demo-code") == true)
    #expect(store.focusedNode?.allWindows.contains("demo-browser") == true)
    #expect(store.focusedNode?.isLeaf == false)
}

@Test @MainActor
func arrangingLegacyDesktopTreeGivesAllGridSpaceToRealApps() throws {
    let bridge = FakeWindows(),(store,directory) = makeStore(bridge: bridge)
    defer { store.shutdown(); try? FileManager.default.removeItem(at: directory) }
    let desktop = LayoutNode(window: "desktop:test-display")
    var root = desktop
    for key in ["a","b","c"] { root = LayoutNode(first: root,second: LayoutNode(window: key),axis: .horizontal,ratio: 0.85) }
    store.displays[0].root = root; store.displays[0].focus = root.id
    store.arrange()
    #expect(store.current?.root?.allWindows.sorted() == ["a","b","c"])
    #expect(store.desktopPlans().flatMap(\.nativePlacements).count == 3)
    #expect(store.desktopPlans().flatMap(\.nativePlacements).allSatisfy { $0.rect.width > 400 })
}

@Test @MainActor
func nativeCellAcceptsFixedWidthButRejectsOverlapAndWrongPosition() {
    let cell = LayoutRect(x: 1151,y: 38,width: 1135,height: 693)
    #expect(WindowBridge.frameFitsCell(LayoutRect(x: 1151,y: 38,width: 723,height: 693),in: cell))
    #expect(!WindowBridge.frameFitsCell(LayoutRect(x: 1151,y: 38,width: 1200,height: 693),in: cell))
    #expect(!WindowBridge.frameFitsCell(LayoutRect(x: 397,y: 267,width: 723,height: 611),in: cell))
}

@Test @MainActor
func dormantSavedWindowsDoNotAppearAsLivePreviewPanes() throws {
    let bridge = FakeWindows(),(store,directory) = makeStore(bridge: bridge)
    defer { store.shutdown(); try? FileManager.default.removeItem(at: directory) }
    store.arrange(); store.floatAll()
    bridge.preservesUnlistedWindows = true; bridge.windows.removeValue(forKey: "b"); store.refresh()
    #expect(store.records.contains { $0.id == "b" })
    #expect(!store.listedRecords.contains { $0.id == "b" })
    #expect(store.visibleFocusedNode?.allWindows.contains("b") == false)
}

@Test @MainActor
func offDesktopAppsAreExcludedFromTheGridAndNativeWrites() throws {
    let bridge = FakeWindows(),(store,directory) = makeStore(bridge: bridge)
    defer { store.shutdown(); try? FileManager.default.removeItem(at: directory) }
    store.arrange(); store.floatAll(); bridge.moves = []; bridge.minimizeRequests = []
    bridge.windows["b"]?.onScreen = false
    let baseline = bridge.frames["b"]
    store.refresh(); store.arrange()
    #expect(!store.listedRecords.contains { $0.id == "b" })
    #expect(store.visibleFocusedNode?.allWindows.contains("b") == false)
    #expect(!bridge.moves.contains { $0.0 == "b" })
    #expect(!bridge.minimizeRequests.contains { $0.0 == "b" })
    #expect(bridge.frames["b"] == baseline)
}

@Test @MainActor
func transientEmptyVisibilityDoesNotPauseOrMoveOtherDesktopWindows() async throws {
    let bridge = FakeWindows(),(store,directory) = makeStore(bridge: bridge)
    defer { store.shutdown(); try? FileManager.default.removeItem(at: directory) }
    store.arrange()
    for key in Array(bridge.windows.keys) { bridge.windows[key]?.onScreen = false }
    bridge.moves = []; bridge.raised = []
    store.handleSpaceChange(); store.refresh()
    #expect(bridge.moves.isEmpty)
    for key in Array(bridge.windows.keys) { bridge.windows[key]?.onScreen = true }
    let deadline = Date().addingTimeInterval(5)
    while bridge.raised.isEmpty,Date() < deadline { try await Task.sleep(nanoseconds: 20_000_000) }
    #expect(store.isArranging)
    #expect(bridge.moves.isEmpty) // Stable frames need only restacking.
    #expect(!bridge.raised.isEmpty)
}

@Test @MainActor
func confirmedClosedWindowsLeaveNoPaneOrRestorationJournalEntry() throws {
    let bridge = FakeWindows(),(store,directory) = makeStore(bridge: bridge)
    defer { store.shutdown(); try? FileManager.default.removeItem(at: directory) }
    store.arrange(); bridge.preservesUnlistedWindows = true
    bridge.windows.removeValue(forKey: "b"); bridge.destroyedWindowIDs.insert("b"); store.refresh()
    #expect(!store.records.contains { $0.id == "b" })
    #expect(store.current?.root?.allWindows.contains("b") == false)
    #expect(!store.movedWindows.contains("b"))
    #expect(store.snapshot.recoveryWindows?.contains { $0.id == "b" } == false)
    store.floatAll(); #expect(!store.hasWindowsToRestore)
}

@Test @MainActor
func recallingAnOffDesktopLeafDoesNotHideCurrentDesktopApps() throws {
    let bridge = FakeWindows(),(store,directory) = makeStore(bridge: bridge)
    defer { store.shutdown(); try? FileManager.default.removeItem(at: directory) }
    store.arrange(); store.floatAll()
    let leaf = try #require(store.current?.root?.leaf(containing: "b"))
    store.focus(leaf.id); store.saveView(2); store.showEverything()
    bridge.windows["b"]?.onScreen = false; store.refresh(); store.arrange()
    bridge.minimizeRequests = []; bridge.moves = []
    store.recallView(2)
    #expect(Set(store.desktopPlans().flatMap(\.nativePlacements).map(\.window)) == ["a","c"])
    #expect(bridge.minimizeRequests.isEmpty)
    #expect(!bridge.moves.contains { $0.0 == "b" })
}

@Test @MainActor
func resizeDragUpdatesNativeWindowsAndCreatesOneUndoStep() async throws {
    let bridge = FakeWindows(),(store,directory) = makeStore(bridge: bridge)
    defer { store.shutdown(); try? FileManager.default.removeItem(at: directory) }
    store.arrange(); let original = try #require(store.current?.root)
    bridge.moves = []
    store.beginResize(); store.resize(original.id,ratio: 0.55,finished: false)
    let deadline = Date().addingTimeInterval(5)
    while bridge.moves.isEmpty,Date() < deadline { try await Task.sleep(nanoseconds: 10_000_000) }
    #expect(!bridge.moves.isEmpty)
    store.resize(original.id,ratio: 0.6,finished: true); store.undo()
    #expect(store.current?.root == original)
    #expect(!store.interactiveDrag)
}

@Test @MainActor
func seamResizeRespectsNativeMinimumsAndLeavesTheOtherAxisAlone() throws {
    let bridge = FakeWindows(),(store,directory) = makeStore(bridge: bridge)
    defer { store.shutdown(); try? FileManager.default.removeItem(at: directory) }
    store.arrange(); let root = try #require(store.current?.root)
    for key in root.children[0].allWindows { bridge.minimums[key] = CGSize(width: 500,height: 0) }
    store.beginResize(); store.resize(root.id,ratio: 0.1,finished: true)
    let placements = store.desktopPlans().flatMap(\.nativePlacements)
    #expect(placements.filter { root.children[0].allWindows.contains($0.window) }.allSatisfy { $0.rect.width >= 499.5 })
    #expect(store.isArranging)
}

@Test @MainActor
func editorMouseDragTabsThenTearsOutWithoutChangingWindowsUntilDrop() throws {
    let bridge = FakeWindows(),(store,directory) = makeStore(bridge: bridge)
    defer { store.shutdown(); try? FileManager.default.removeItem(at: directory) }
    store.arrange(); let original = try #require(store.current?.root)
    let leaf = try #require(original.leaf(containing: "a"))
    store.editorTargets["target"] = EditorDropTarget(id: leaf.id,node: leaf.id,window: 9,frame: CGRect(x: 100,y: 100,width: 200,height: 200))
    bridge.moves = []
    store.beginEditorDrag("b"); store.updateEditorDrag(CGPoint(x: 200,y: 200),window: 9)
    #expect(store.editorDropEdge == .tab); #expect(bridge.moves.isEmpty)
    store.finishEditorDrag(CGPoint(x: 200,y: 200),window: 9)
    #expect(store.current?.root?.leaf(containing: "a")?.windows == ["a","b"])
    #expect(!store.interactiveDrag); #expect(store.editorDropTarget == nil)
    store.beginEditorDrag("b"); store.finishEditorDrag(CGPoint(x: 200,y: 295),window: 9)
    #expect(store.current?.root?.leaf(containing: "a")?.windows == ["a"])
    #expect(store.current?.root?.allWindows.sorted() == ["a","b","c"])
    store.undo(); #expect(store.current?.root?.leaf(containing: "a")?.windows == ["a","b"])
    store.undo(); #expect(store.current?.root == original)
}

@Test @MainActor
func editorDragCancellationAndWrongWindowLeaveTheLayoutAlone() throws {
    let bridge = FakeWindows(),(store,directory) = makeStore(bridge: bridge)
    defer { store.shutdown(); try? FileManager.default.removeItem(at: directory) }
    store.arrange(); let original = try #require(store.current?.root),leaf = try #require(original.leaf(containing: "a"))
    store.editorTargets["target"] = EditorDropTarget(id: leaf.id,node: leaf.id,window: 9,frame: CGRect(x: 100,y: 100,width: 200,height: 200))
    bridge.moves = []
    store.beginEditorDrag("b"); store.updateEditorDrag(CGPoint(x: 200,y: 200),window: 9); store.cancelEditorDrag()
    #expect(store.editorDropTarget == nil); #expect(!store.interactiveDrag)
    store.beginEditorDrag("b"); store.finishEditorDrag(CGPoint(x: 200,y: 200),window: 10)
    #expect(store.current?.root == original); #expect(bridge.moves.isEmpty)
}

@Test @MainActor
func immediateRestoreRefreshesAJustClosedWindowBeforeUsingTheJournal() throws {
    let bridge = FakeWindows(),(store,directory) = makeStore(bridge: bridge)
    defer { store.shutdown(); try? FileManager.default.removeItem(at: directory) }
    store.arrange(); bridge.windows.removeValue(forKey: "b"); bridge.destroyedWindowIDs.insert("b")
    store.floatAll()
    #expect(!store.hasWindowsToRestore); #expect(store.message == nil)
    #expect(store.snapshot.recoveryWindows?.isEmpty == true)
}

@Test @MainActor
func lateClosureNotificationClearsTheRestoreFailureBanner() throws {
    let bridge = FakeWindows(),(store,directory) = makeStore(bridge: bridge)
    defer { store.shutdown(); try? FileManager.default.removeItem(at: directory) }
    bridge.preservesUnlistedWindows = true
    store.arrange(); bridge.windows.removeValue(forKey: "b")
    store.floatAll()
    #expect(store.hasWindowsToRestore)
    #expect(store.message?.contains("could not be restored") == true)
    bridge.destroyedWindowIDs.insert("b"); store.refresh()
    #expect(!store.hasWindowsToRestore)
    #expect(store.message == nil)
    #expect(store.snapshot.recoveryWindows?.isEmpty == true)
}

@Test @MainActor
func doubleClickFocusReturnsToThePreviousLayoutOnTheSecondUse() throws {
    let bridge = FakeWindows(),(store,directory) = makeStore(demo: true,bridge: bridge)
    defer { store.shutdown(); try? FileManager.default.removeItem(at: directory) }
    let root = try #require(store.current?.root),leaf = try #require(root.leaf(containing: "demo-code"))
    store.toggleFocus(leaf.id); #expect(store.current?.focus == leaf.id)
    store.toggleFocus(leaf.id); #expect(store.current?.focus == root.id)
}

@Test @MainActor
func nativeEditorDragSurfaceLeavesTheZoomButtonClickable() {
    let parent = NSView(frame: NSRect(x: 0,y: 0,width: 300,height: 250))
    let surface = WindowDragView(frame: parent.bounds); surface.excludesZoomButton = true
    parent.addSubview(surface)
    #expect(surface.hitTest(NSPoint(x: 280,y: 230)) == nil)
    #expect(surface.hitTest(NSPoint(x: 150,y: 100)) === surface)
}

@Test @MainActor
func undoingANewInactiveTabRestoresItAsAVisibleFloatingWindow() throws {
    let bridge = FakeWindows(),(store,directory) = makeStore(bridge: bridge)
    defer { store.shutdown(); try? FileManager.default.removeItem(at: directory) }
    store.arrange()
    let frame = LayoutRect(x: 90,y: 90,width: 500,height: 400)
    let record = WindowRecord(id: "new",bundleID: "fixture.new",app: "New",title: "New",ordinal: 0,originalFrame: frame)
    bridge.windows["new"] = DiscoveredWindow(record: record,element: AXUIElementCreateApplication(1004),pid: 1004,minimized: false,icon: nil)
    bridge.frames["new"] = frame; store.refresh()
    store.dock("new",target: store.current?.root?.leaf(containing: "a")?.id,edge: .tab); store.selectTab("a")
    #expect(store.occludedWindows.contains("new"))
    store.undo()
    #expect(bridge.windows["new"]?.minimized == false)
    #expect(bridge.frames["new"] == frame)
    #expect(!store.occludedWindows.contains("new"))
    #expect(store.floatingRecords.contains { $0.id == "new" })
}

@Test @MainActor
func nativeWindowAliasesCollapseDuplicatePanesAndKeepTheOriginalBaseline() throws {
    let bridge = FakeWindows(),(store,directory) = makeStore(bridge: bridge)
    defer { store.shutdown(); try? FileManager.default.removeItem(at: directory) }
    store.arrange(); let baseline = try #require(store.record("a")?.originalFrame)
    var alias = try #require(bridge.windows["a"]); alias.record.id = "alias"; alias.record.originalFrame = LayoutRect(width: 1000,height: 700)
    bridge.windows["alias"] = alias; store.refresh()
    let aliasLeaf = LayoutNode(window: "alias")
    store.displays[0].root = LayoutNode(first: aliasLeaf,second: try #require(store.current?.root),axis: .horizontal)
    store.movedWindows.insert("alias"); store.dormantWindows.insert("a")
    bridge.windows.removeValue(forKey: "alias"); bridge.windowAliases["alias"] = "a"; store.refresh()
    #expect(store.current?.root?.allWindows.sorted() == ["a","b","c"])
    #expect(store.current?.root?.leaf(containing: "a")?.id == aliasLeaf.id)
    #expect(!store.records.contains { $0.id == "alias" })
    #expect(store.record("a")?.originalFrame == baseline)
    #expect(store.snapshot.recoveryWindows?.contains { $0.id == "alias" } == false)
    store.floatAll(); #expect(bridge.frames["a"] == baseline)
}

@Test @MainActor
func doubleClickReturnSkipsHistoryFromReplacedLayoutNodes() throws {
    let bridge = FakeWindows(),(store,directory) = makeStore(demo: true,bridge: bridge)
    defer { store.shutdown(); try? FileManager.default.removeItem(at: directory) }
    let root = try #require(store.current?.root),leaf = try #require(root.leaf(containing: "demo-code"))
    store.displays[0].history = ViewHistory(); store.displays[0].history.visit("removed-root")
    store.focus(leaf.id); store.toggleFocus(leaf.id)
    #expect(store.current?.focus == root.id)
}
