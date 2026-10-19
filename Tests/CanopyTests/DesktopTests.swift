import Testing
import Foundation
import AppKit
import CanopyCore
@testable import Canopy

let fixtureDisplays = [DisplayDescriptor(id: "test-display",name: "Fixture display",frame: LayoutRect(width: 1280,height: 800))]

@Test @MainActor
func desktopPlaneControlDoesNotCoverFloatingApplicationContent() {
    let plane = LayoutRect(x: 8,y: 30,width: 1800,height: 1000)
    let control = DesktopCoordinator.desktopControlRect(in: plane)
    #expect(control.width <= 120 && control.height <= 32)
    #expect(!control.contains(x: plane.midX,y: plane.midY))
}

@Test @MainActor
func initialArrangementUsesUsableBalancedPanesOnAnUltrawideDisplay() throws {
    let leaves = ["desktop:test","chrome","finder","textedit"].map { LayoutNode(window: $0) }
    let root = try #require(WorkspaceStore.balancedArrangement(leaves,in: LayoutRect(width: 3440,height: 1410)))
    let placements = root.placements(in: LayoutRect(width: 3424,height: 1394),gap: 8)
    #expect(placements.count == 4)
    #expect(placements.allSatisfy { $0.rect.height >= 469 && $0.rect.width >= 800 })
    #expect(Set(root.allWindows) == Set(leaves.flatMap(\.allWindows)))
}

@Test @MainActor
func sixInitialPanesUseThreeColumnsInsteadOfAThinThirdRow() throws {
    let leaves = (0..<6).map { LayoutNode(window: "window-\($0)") }
    let root = try #require(WorkspaceStore.balancedArrangement(leaves,in: LayoutRect(width: 3440,height: 1410)))
    let placements = root.placements(in: LayoutRect(width: 3424,height: 1394),gap: 8)
    #expect(placements.count == 6)
    #expect(placements.allSatisfy { $0.rect.height >= 611 && $0.rect.width >= 960 })
}

@Test @MainActor
func explicitlyOpeningAMinimizedWindowMakesItUsableWithoutStartingArrangement() throws {
    let bridge = FakeWindows(); bridge.windows["c"]?.minimized = true
    let (store,directory) = makeStore(bridge: bridge)
    defer { store.shutdown(); try? FileManager.default.removeItem(at: directory) }
    store.openWindow("c")
    #expect(bridge.windows["c"]?.minimized == false)
    #expect(bridge.raised.contains("c"))
    #expect(!store.isArranging)
    #expect(bridge.moves.isEmpty)
}

@Test @MainActor
func crowdedInitialArrangementUsesUsableNativeTabsInsteadOfMiniatures() throws {
    let leaves = [LayoutNode(window: "desktop:test")]+(0..<8).map { LayoutNode(window: "window-\($0)") }
    let root = try #require(WorkspaceStore.automaticArrangement(leaves,in: LayoutRect(width: 3424,height: 1394),preferred: CGSize(width: 1000,height: 650)))
    let placements = root.placements(in: LayoutRect(width: 3424,height: 1394),gap: 8)
    #expect(Set(root.allWindows) == Set(leaves.flatMap(\.allWindows)))
    #expect(placements.filter(\.isActive).count == 6)
    #expect(placements.filter(\.isActive).allSatisfy { $0.rect.width >= 1000 && $0.rect.height >= 650 })
}

@Test @MainActor
func floatingAWindowFromASinglePaneLayoutKeepsItVisible() throws {
    let bridge = FakeWindows(); bridge.preferredInitialPaneSize = CGSize(width: 1000,height: 650)
    let (store,directory) = makeStore(bridge: bridge)
    defer { store.shutdown(); try? FileManager.default.removeItem(at: directory) }
    let original = bridge.frames["b"]
    store.arrange()
    #expect(store.current?.root?.allWindows.contains(where: WorkspaceStore.isDesktop) == false)
    store.floatWindow("b")
    #expect(!store.occludedWindows.contains("b"))
    #expect(bridge.windows["b"]?.minimized == false)
    #expect(bridge.frames["b"] == original)
}

@Test @MainActor
func layoutNotificationsKeepArrangingWhenManagedWindowsAreStillVisible() async throws {
    let bridge = FakeWindows(),(store,directory) = makeStore(bridge: bridge)
    defer { store.shutdown(); try? FileManager.default.removeItem(at: directory) }
    store.arrange(); store.handleSpaceChange()
    #expect(store.isArranging)
    for key in Array(bridge.windows.keys) { bridge.windows[key]?.onScreen = false }
    store.handleSpaceChange()
    let deadline = Date().addingTimeInterval(5)
    while store.isArranging,Date() < deadline { try await Task.sleep(nanoseconds: 20_000_000) }
    #expect(!store.isArranging)
}

@Test @MainActor
func miniatureAndDesktopControlsRespondToAnOrdinaryClick() throws {
    let bridge = FakeWindows(),(store,directory) = makeStore(bridge: bridge)
    defer { store.shutdown(); try? FileManager.default.removeItem(at: directory) }
    let click = try #require(NSEvent.mouseEvent(with: .leftMouseDown,location: .zero,modifierFlags: [],timestamp: 0,windowNumber: 0,context: nil,eventNumber: 0,clickCount: 1,pressure: 1))
    var miniatureOpened = false, desktopOpened = false
    let miniature = MiniatureView(node: LayoutNode(window: "a"),store: store) { miniatureOpened = true }
    let desktop = DesktopPlaceView { desktopOpened = true }
    miniature.mouseDown(with: click); desktop.mouseDown(with: click)
    #expect(miniatureOpened && desktopOpened)
}

@Test @MainActor
func inactiveTabsAndOffCameraWindowsStayLiveBehindWorkspaceBackground() throws {
    let bridge = FakeWindows(),(store,directory) = makeStore(bridge: bridge)
    defer { store.shutdown(); try? FileManager.default.removeItem(at: directory) }
    store.arrange()
    let leaf = store.current!.root!.leaf(containing: "a")!
    store.dock("b",target: leaf.id,edge: .tab)
    #expect(store.occludedWindows.contains("a"))
    #expect(!store.minimized.contains("a"))
    store.selectTab("a")
    #expect(!store.occludedWindows.contains("a"))
    #expect(store.occludedWindows.contains("b"))
    store.focus(store.current!.root!.leaf(containing: "a")!.id)
    #expect(store.occludedWindows.contains("c"))
    store.floatAll()
    #expect(store.occludedWindows.isEmpty)
    #expect(bridge.windows.values.allSatisfy { !$0.minimized })
}

@Test @MainActor
func userMinimizedWindowsAreNeverUnminimizedByRestore() throws {
    let bridge = FakeWindows(); bridge.windows["c"]?.minimized = true
    let (store,directory) = makeStore(bridge: bridge)
    defer { store.shutdown(); try? FileManager.default.removeItem(at: directory) }
    store.arrange(); store.floatAll()
    #expect(bridge.windows["c"]?.minimized == true)
    #expect(!bridge.minimizeRequests.contains { $0.0 == "c" && !$0.1 })
}

@Test @MainActor
func terminatedAppsKeepTheirLayoutAndReconnectWhenTheyReturn() throws {
    let bridge = FakeWindows(),(store,directory) = makeStore(bridge: bridge)
    defer { store.shutdown(); try? FileManager.default.removeItem(at: directory) }
    store.arrange()
    let window = bridge.windows["a"]!,leaf = store.current!.root!.leaf(containing: "a")!.id
    bridge.windows.removeValue(forKey: "a"); bridge.runningBundleIDs.remove("fixture.a"); store.refresh()
    #expect(store.dormantWindows.contains("a"))
    #expect(store.current?.root?.leaf(containing: "a")?.id == leaf)
    bridge.windows["a"] = window; bridge.runningBundleIDs.insert("fixture.a"); store.refresh()
    #expect(!store.dormantWindows.contains("a"))
    #expect(store.current?.root?.leaf(containing: "a")?.id == leaf)
}

@Test @MainActor
func crashJournalRecoversFramesAndOwnedMinimizationWithoutAutoMovingOnLaunch() throws {
    let bridge = FakeWindows(),(store,directory) = makeStore(bridge: bridge)
    defer { store.shutdown(); try? FileManager.default.removeItem(at: directory) }
    let original = bridge.frames
    store.arrange(); store.focus(store.current!.root!.leaf(containing: "a")!.id)
    let bytes = try Data(contentsOf: directory.appendingPathComponent("workspace.json"))
    let journal = directory.appendingPathComponent("crashed.json"); try bytes.write(to: journal)
    bridge.moves = []; bridge.restores = []
    let recovered = WorkspaceStore(bridge: bridge,storageURL: journal,screens: { fixtureDisplays })
    defer { recovered.shutdown() }
    #expect(!recovered.pendingRecovery.isEmpty)
    #expect(bridge.moves.isEmpty); #expect(bridge.restores.isEmpty)
    recovered.recoverWindows()
    #expect(recovered.pendingRecovery.isEmpty)
    #expect(bridge.frames == original)
    #expect(bridge.windows.values.allSatisfy { !$0.minimized })
}

@Test @MainActor
func crossDisplayDockingUsesNegativeCoordinatesAndConservesOneCopy() throws {
    let bridge = FakeWindows()
    let screens = fixtureDisplays+[DisplayDescriptor(id: "left",name: "Left",frame: LayoutRect(x: -1440,y: -200,width: 1440,height: 900))]
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let store = WorkspaceStore(bridge: bridge,storageURL: directory.appendingPathComponent("workspace.json"),screens: { screens })
    defer { store.shutdown(); try? FileManager.default.removeItem(at: directory) }
    store.arrange()
    let intent = DockIntent(display: "left",target: nil,edge: .left,preview: screens[1].frame)
    store.dock(["a"],intent: intent)
    #expect(store.displays.flatMap { $0.root?.allWindows ?? [] }.filter { $0 == "a" }.count == 1)
    #expect(store.displays.first { $0.id == "left" }?.root?.allWindows.contains("a") == true)
    #expect((bridge.frames["a"]?.x ?? 0) < 0)
}

@Test @MainActor
func exportImportPreservesLayoutAndPreferencesButNeverActivatesIt() throws {
    let bridge = FakeWindows(),(store,directory) = makeStore(bridge: bridge)
    defer { store.shutdown(); try? FileManager.default.removeItem(at: directory) }
    store.arrange(); store.updatePreferences { $0.dockingRequiresOption = false }
    let root = store.current?.root,export = directory.appendingPathComponent("export.json")
    try store.exportWorkspace(to: export)
    let exported = try JSONDecoder().decode(WorkspaceSnapshot.self,from: Data(contentsOf: export))
    #expect(exported.recoveryWindows?.isEmpty == true)
    store.floatWindow("a"); try store.importWorkspace(from: export)
    #expect(!store.isArranging)
    #expect(store.current?.root == root)
    #expect(!store.preferences.dockingRequiresOption)
    #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("Backups").path))
}

@Test @MainActor
func freeCameraSavedViewRoundTripsItsFramingRectangle() {
    let bridge = FakeWindows(),(store,_) = makeStore(demo: true,bridge: bridge)
    defer { store.shutdown() }
    let frame = LayoutRect(x: 100,y: 80,width: 600,height: 400)
    store.setCameraFrame(frame); store.saveView(3); store.showEverything(); store.recallView(3)
    #expect(store.current?.cameraFrame == frame)
}

@Test @MainActor
func shortcutConflictsAreRejectedWithoutChangingPreferences() {
    let bridge = FakeWindows(),(store,_) = makeStore(demo: true,bridge: bridge)
    defer { store.shutdown() }
    let old = store.preferences.shortcuts
    var conflicting = old[0]; conflicting.keyCode = old[1].keyCode; conflicting.modifiers = old[1].modifiers
    #expect(!store.changeShortcut(conflicting))
    #expect(store.preferences.shortcuts == old)
}

@Test @MainActor
func freeCameraFramesParticipateInBackAndForwardHistory() {
    let bridge = FakeWindows(),(store,_) = makeStore(demo: true,bridge: bridge)
    defer { store.shutdown() }
    let frame = LayoutRect(x: 150,y: 50,width: 600,height: 400)
    store.setCameraFrame(frame); store.showEverything(); store.navigateHistory(back: true)
    #expect(store.current?.cameraFrame == frame)
    store.navigateHistory(back: false); #expect(store.current?.cameraFrame == nil)
}

@Test @MainActor
func reopeningAnInactiveTabThroughItsAppSelectsThatTab() throws {
    let bridge = FakeWindows(),(store,directory) = makeStore(bridge: bridge)
    defer { store.shutdown(); try? FileManager.default.removeItem(at: directory) }
    store.arrange(); let target = store.current!.root!.leaf(containing: "a")!.id
    store.dock("b",target: target,edge: .tab)
    #expect(store.occludedWindows.contains("a"))
    bridge.windows["a"]?.minimized = false; bridge.windows["a"]?.onScreen = true; bridge.focused = "a"
    store.refresh()
    #expect(store.current?.root?.leaf(containing: "a")?.activeWindow == "a")
    #expect(!store.occludedWindows.contains("a"))
}

@Test @MainActor
func changingMacOSSpacesPausesWithoutMovingWindowsOnAnotherDesktop() throws {
    let bridge = FakeWindows(),(store,directory) = makeStore(bridge: bridge)
    defer { store.shutdown(); try? FileManager.default.removeItem(at: directory) }
    store.arrange(); let frames = bridge.frames; bridge.moves = []
    store.pauseForSpaceChange(); store.refresh()
    #expect(!store.isArranging); #expect(bridge.moves.isEmpty); #expect(bridge.frames == frames)
    #expect(store.hasWindowsToRestore)
}

@Test @MainActor
func urlCommandsCanDockUndoAndSelectSavedViewsWithoutLeavingDemo() {
    let bridge = FakeWindows(),(store,_) = makeStore(demo: true,bridge: bridge)
    defer { store.shutdown() }
    let root = store.current!.root!,target = root.leaf(containing: "demo-browser")!.id
    store.handleURL(URL(string: "canopy://dock?window=demo-code&target=\(target)&edge=tab")!)
    #expect(store.current?.root?.leaf(containing: "demo-browser")?.windows.contains("demo-code") == true)
    store.handleURL(URL(string: "canopy://undo")!)
    #expect(store.current?.root == root)
    #expect(store.isDemo); #expect(bridge.moves.isEmpty)
}
