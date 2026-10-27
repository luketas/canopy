import AppKit
import CanopyCore
import Testing
@testable import Canopy

@Test
func olderPreferencesKeepTheirValuesAndDefaultToTopGridOverlay() throws {
    var preferences = UserPreferences()
    preferences.desktopDocking = false
    preferences.showTabStrips = false
    preferences.minimumWidth = 360
    preferences.shortcuts[0].enabled = false
    var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(preferences)) as? [String:Any])
    json.removeValue(forKey: "showGridOverlay")
    json.removeValue(forKey: "workspaceBarPosition")
    let decoded = try JSONDecoder().decode(UserPreferences.self,from: JSONSerialization.data(withJSONObject: json))
    #expect(decoded == preferences)
    #expect(decoded.showGridOverlay)
    #expect(decoded.workspaceBarPosition == .top)
}

@Test(arguments: WorkspaceBarPosition.allCases) @MainActor
func selectorReservesTheCorrectEdgeOnOffsetMonitors(position: WorkspaceBarPosition) throws {
    let screen = DisplayDescriptor(id: "offset",name: "Offset",frame: LayoutRect(x: -1600,y: -220,width: 1600,height: 1000))
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("canopy-appearance-\(UUID().uuidString)")
    let store = WorkspaceStore(bridge: FakeWindows(),storageURL: directory.appendingPathComponent("workspace.json"),screens: { [screen] })
    defer { store.shutdown(); try? FileManager.default.removeItem(at: directory) }
    store.updatePreferences { $0.workspaceBarPosition = position }
    let viewport = store.desktopViewport(screen)
    #expect(screen.frame.contains(viewport))
    #expect(viewport.x == screen.frame.x+store.gap)
    if position == .hidden {
        #expect(store.workspaceBarFrame(screen) == nil)
        #expect(viewport == screen.frame.inset(store.gap))
    } else {
        let bar = try #require(store.workspaceBarFrame(screen))
        #expect(bar.height == DesktopWorkspaceBar.height)
        #expect(screen.frame.contains(bar))
        #expect(bar.intersection(viewport) == nil)
        #expect(viewport.height == screen.frame.height-bar.height-2*store.gap)
        if position == .top {
            #expect(bar.y == screen.frame.y)
            #expect(viewport.y == bar.maxY+store.gap)
        } else {
            #expect(bar.maxY == screen.frame.maxY)
            #expect(viewport.maxY == bar.y-store.gap)
            #expect(viewport.y == screen.frame.y+store.gap)
        }
    }
}

@Test @MainActor
func windowsOnlyUsesNativeSlotsWithoutPaneTabInsetsOrMiniatures() throws {
    let bridge = FakeWindows(), (store,directory) = makeStore(bridge: bridge)
    defer { store.shutdown(); try? FileManager.default.removeItem(at: directory) }
    let tabs = LayoutNode(windows: ["a","b"],active: "a")
    let root = LayoutNode(first: tabs,second: LayoutNode(window: "c"),axis: .horizontal,ratio: 0.1)
    store.displays[0].root = root; store.displays[0].focus = root.id
    let grid = try #require(store.desktopPlans().first)
    #expect(grid.miniatureNodes.contains(tabs.id))
    bridge.minimums["a"] = CGSize(width: 250,height: 180)
    store.updatePreferences { $0.showGridOverlay = false; $0.workspaceBarPosition = .bottom }
    let plan = try #require(store.desktopPlans().first)
    #expect(plan.miniatureNodes.isEmpty)
    #expect(!store.preferences.showsPaneTabStrips)
    #expect(store.preferences.showTabStrips) // retain the user's grid-mode choice
    #expect(Set(plan.nativePlacements.map(\.window)) == ["a","c"])
    let a = try #require(plan.nativePlacements.first { $0.window == "a" })
    let slot = try #require(plan.placements.first { $0.window == "a" })
    #expect(a.rect.y == slot.rect.y)
    #expect(a.rect.height == slot.rect.height)
    #expect(a.rect.width >= 250)
    #expect(plan.nativePlacements.allSatisfy { store.desktopViewport(plan.display).contains($0.rect) })
    store.updatePreferences { $0.showGridOverlay = true }
    #expect(store.preferences.showsPaneTabStrips)
    #expect(store.desktopPlans().first?.miniatureNodes.contains(tabs.id) == true)
}

@Test @MainActor
func windowsOnlyDoesNotCollapseSmallNestedGroupsIntoInvisibleCards() throws {
    let (store,directory) = makeStore(bridge: FakeWindows())
    defer { store.shutdown(); try? FileManager.default.removeItem(at: directory) }
    let nested = LayoutNode(first: LayoutNode(window: "a"),second: LayoutNode(window: "b"),axis: .vertical)
    let root = LayoutNode(first: nested,second: LayoutNode(window: "c"),axis: .horizontal,ratio: 0.05)
    store.displays[0].root = root; store.displays[0].focus = root.id
    #expect(store.desktopPlans().first?.miniatureNodes.contains(nested.id) == true)
    store.updatePreferences { $0.showGridOverlay = false }
    let plan = try #require(store.desktopPlans().first)
    #expect(plan.miniatureNodes.isEmpty)
    #expect(Set(plan.nativePlacements.map(\.window)) == ["a","b","c"])
}

@Test @MainActor
func windowsOnlyFramesRespectNativeMinimumsAndDoNotPullOffscreenPanesIntoView() {
    let viewport = LayoutRect(x: -1500,y: 40,width: 1400,height: 800)
    let small = LayoutRect(x: -160,y: 800,width: 60,height: 40)
    let rect = WorkspaceStore.windowsOnlyFrame(small,minimum: CGSize(width: 300,height: 200),in: viewport)
    #expect(rect == LayoutRect(x: -400,y: 640,width: 300,height: 200))
    #expect(WorkspaceStore.windowsOnlyFrame(LayoutRect(x: 50,y: 10,width: 200,height: 200),minimum: .zero,in: viewport) == nil)
}

@Test @MainActor
func windowsOnlyAndHiddenSelectorPreserveWorkspaceCommandsAndRestore() throws {
    let bridge = FakeWindows(), (store,directory) = makeStore(bridge: bridge)
    defer { store.shutdown(); try? FileManager.default.removeItem(at: directory) }
    let originals = bridge.frames
    store.updatePreferences { $0.showGridOverlay = false; $0.workspaceBarPosition = .hidden }
    store.arrange()
    let first = try #require(store.current?.activeGridID)
    store.addWorkspaceGrid(); store.addWindowsToCurrentGrid(["b"])
    let second = try #require(store.current?.activeGridID)
    store.performCommand("workspace.1",at: CGPoint(x: 200,y: 200))
    #expect(store.current?.activeGridID == first)
    store.performCommand("workspace-next",at: CGPoint(x: 200,y: 200))
    #expect(store.current?.activeGridID == second)
    #expect(bridge.activated.last == "b")
    #expect(bridge.minimizeRequests.isEmpty)
    #expect(store.workspaceBarFrame(fixtureDisplays[0]) == nil)
    store.floatAll()
    #expect(!store.isArranging)
    #expect(bridge.frames == originals)
}

@Test @MainActor
func appearanceSettingsPersistInDemoWithoutReplacingRealLayouts() throws {
    let bridge = FakeWindows(), (store,directory) = makeStore(bridge: bridge)
    defer { store.shutdown(); try? FileManager.default.removeItem(at: directory) }
    store.dock("a",target: nil,edge: .right)
    store.persist()
    let real = store.snapshot
    store.enterDemo()
    store.updatePreferences { $0.showGridOverlay = false; $0.workspaceBarPosition = .bottom }
    let saved = try JSONDecoder().decode(WorkspaceSnapshot.self,from: Data(contentsOf: store.persistenceURL))
    #expect(saved.displays == real.displays)
    #expect(saved.records == real.records)
    #expect(saved.preferences?.showGridOverlay == false)
    #expect(saved.preferences?.workspaceBarPosition == .bottom)
    let reloaded = WorkspaceStore(bridge: FakeWindows(),storageURL: store.persistenceURL,screens: { fixtureDisplays })
    defer { reloaded.shutdown() }
    #expect(!reloaded.isDemo)
    #expect(!reloaded.preferences.showGridOverlay)
    #expect(reloaded.preferences.workspaceBarPosition == .bottom)
    let export = directory.appendingPathComponent("export.json")
    try reloaded.exportWorkspace(to: export)
    try WorkspaceStore.validate(JSONDecoder().decode(WorkspaceSnapshot.self,from: Data(contentsOf: export)))
}
