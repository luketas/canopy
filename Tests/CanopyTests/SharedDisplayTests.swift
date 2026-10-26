import Testing
import AppKit
import CanopyCore
@testable import Canopy

@Test @MainActor
func sharedDisplayLayoutsRoundTripWithoutInvalidatingTheWorkspace() throws {
    let bridge = FakeWindows(),(store,directory) = makeStore(bridge: bridge)
    defer { store.shutdown(); try? FileManager.default.removeItem(at: directory) }
    store.addWindowsToCurrentGrid(["a"])
    store.displays.append(DisplayWorkspace(id: "disconnected",name: "Previous monitor",root: LayoutNode(window: "a")))
    let state = store.snapshot
    try WorkspaceStore.validate(state)
    let decoded = try JSONDecoder().decode(WorkspaceSnapshot.self,from: JSONEncoder().encode(state))
    try WorkspaceStore.validate(decoded)
    #expect(decoded.displays.map(\.allGridWindows) == [["a"],["a"]])
}

@Test @MainActor
func sharedWindowsHaveOneNativePlacementAcrossConnectedDisplays() throws {
    let bridge = FakeWindows(),directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let store = WorkspaceStore(bridge: bridge,storageURL: directory.appendingPathComponent("workspace.json"),screens: {
        [DisplayDescriptor(id: "left",name: "Left",frame: LayoutRect(x: 0,y: 0,width: 1400,height: 900)),
         DisplayDescriptor(id: "right",name: "Right",frame: LayoutRect(x: 1400,y: 0,width: 1400,height: 900))]
    })
    defer { store.shutdown(); try? FileManager.default.removeItem(at: directory) }
    store.displays[0].root = LayoutNode(window: "a"); store.displays[1].root = LayoutNode(window: "a")
    store.selectedDisplay = "right"
    let plans = store.desktopPlans()
    #expect(plans.flatMap(\.nativePlacements).map(\.window) == ["a"])
    #expect(plans.first { $0.display.id == "right" }?.nativePlacements.first?.window == "a")
    #expect(store.displays.map(\.allGridWindows) == [["a"],["a"]])
}

@Test @MainActor
func disconnectedDisplayMembershipDoesNotHijackAppActivation() throws {
    let bridge = FakeWindows(),(store,directory) = makeStore(bridge: bridge)
    defer { store.shutdown(); try? FileManager.default.removeItem(at: directory) }
    store.addWindowsToCurrentGrid(["a"]); store.applyCurrentGrid()
    let owner = store.current?.activeGridID
    store.addWorkspaceGrid(); store.addWindowsToCurrentGrid(["b"])
    store.displays.insert(DisplayWorkspace(id: "disconnected",name: "Previous monitor",root: LayoutNode(window: "a")),at: 0)
    bridge.focused = "a"
    #expect(store.routeFocusedWindowToWorkspace())
    #expect(store.current?.id == "test-display" && store.current?.activeGridID == owner)
}
