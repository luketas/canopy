import AppKit
import Carbon
import Testing
@testable import Canopy

@Test @MainActor
func shortcutEditsPersistWithoutRearrangingNativeWindows() throws {
    let bridge = FakeWindows(), (store,directory) = makeStore(bridge: bridge)
    defer { store.shutdown(); try? FileManager.default.removeItem(at: directory) }
    store.arrange()
    bridge.operations.removeAll()
    let layouts = store.displays, originalPreferences = store.preferences
    var notifications = 0
    store.onPreferencesChanged = { notifications += 1 }
    var shortcut = try #require(store.preferences.shortcuts.first { $0.id == "workspace-next" })
    shortcut.keyCode = 40; shortcut.key = "K"; shortcut.modifiers = UInt32(controlKey | cmdKey)
    #expect(store.changeShortcut(shortcut))
    store.setShortcutEnabled("auto-layout",enabled: false)
    #expect(notifications == 2)
    #expect(bridge.operations.isEmpty)
    #expect(store.displays == layouts)
    #expect(store.preferences.animations == originalPreferences.animations)
    let reloaded = WorkspaceStore(bridge: FakeWindows(),storageURL: store.persistenceURL,screens: { fixtureDisplays })
    defer { reloaded.shutdown() }
    #expect(reloaded.preferences.shortcuts.first { $0.id == shortcut.id } == shortcut)
    #expect(reloaded.preferences.shortcuts.first { $0.id == "auto-layout" }?.enabled == false)
}

@Test @MainActor
func shortcutResetAndEnableRejectConflictsAndPreserveOtherActions() throws {
    let (store,directory) = makeStore(bridge: FakeWindows())
    defer { store.shutdown(); try? FileManager.default.removeItem(at: directory) }
    let auto = try #require(store.preferences.shortcuts.first { $0.id == "auto-layout" })
    var next = try #require(store.preferences.shortcuts.first { $0.id == "workspace-next" })
    store.setShortcutEnabled(auto.id,enabled: false)
    next.keyCode = auto.keyCode; next.modifiers = auto.modifiers; next.key = auto.key
    #expect(store.changeShortcut(next))
    store.setShortcutEnabled(auto.id,enabled: true)
    #expect(store.preferences.shortcuts.first { $0.id == auto.id }?.enabled == false)
    #expect(store.shortcutConfigurationError?.contains(next.title) == true)
    store.resetShortcut(auto.id)
    #expect(store.preferences.shortcuts.first { $0.id == auto.id }?.enabled == false)
    store.resetShortcut(next.id)
    store.resetShortcut(auto.id)
    #expect(store.preferences.shortcuts == ShortcutBinding.defaults)
    store.setShortcutEnabled(auto.id,enabled: false)
    store.restoreDefaultShortcuts()
    #expect(store.preferences.shortcuts == ShortcutBinding.defaults)
    #expect(store.shortcutConfigurationError == nil)
}

@Test @MainActor
func invalidShortcutCannotBeSavedOrAdded() throws {
    let (store,directory) = makeStore(bridge: FakeWindows())
    defer { store.shutdown(); try? FileManager.default.removeItem(at: directory) }
    let original = store.preferences.shortcuts
    var binding = original[0]
    binding.modifiers = 0; #expect(!store.changeShortcut(binding))
    binding = original[0]; binding.keyCode = 128; #expect(!store.changeShortcut(binding))
    binding = original[0]; binding.id = "unknown"; #expect(!store.changeShortcut(binding))
    binding = original[0]; binding.key = ""; #expect(!store.changeShortcut(binding))
    #expect(store.preferences.shortcuts == original)
}

@Test @MainActor
func demoShortcutSettingsSaveOnlyRealWorkspaceMetadata() throws {
    let bridge = FakeWindows(), (store,directory) = makeStore(bridge: bridge)
    defer { store.shutdown(); try? FileManager.default.removeItem(at: directory) }
    store.dock("a",target: nil,edge: .right)
    store.persist()
    let saved = store.snapshot
    store.enterDemo()
    store.setShortcutEnabled("auto-layout",enabled: false)
    let disk = try JSONDecoder().decode(WorkspaceSnapshot.self,from: Data(contentsOf: store.persistenceURL))
    #expect(disk.displays == saved.displays)
    #expect(disk.records == saved.records)
    #expect(disk.preferences?.shortcuts.first { $0.id == "auto-layout" }?.enabled == false)
    store.useRealWindows()
    #expect(store.preferences.shortcuts.first { $0.id == "auto-layout" }?.enabled == false)
}

private func shortcutEvent(_ code: UInt16, flags: NSEvent.ModifierFlags = [], type: NSEvent.EventType = .keyDown, characters: String = "") throws -> NSEvent {
    try #require(NSEvent.keyEvent(with: type,location: .zero,modifierFlags: flags,timestamp: 1,
        windowNumber: 0,context: nil,characters: characters,charactersIgnoringModifiers: characters,isARepeat: false,keyCode: code))
}

@Test @MainActor
func recorderCapturesTabAndWaitsForReleaseBeforeResumingHotkeys() throws {
    let (store,directory) = makeStore(bridge: FakeWindows())
    defer { store.shutdown(); try? FileManager.default.removeItem(at: directory) }
    let binding = try #require(store.preferences.shortcuts.first { $0.id == "workspace-next" })
    var configurations: [String?] = []
    store.onPreferencesChanged = { configurations.append(store.recordingShortcutID) }
    let recorder = RecorderButton(value: binding,onRecord: store.changeShortcut,
        onRecordingChanged: { store.recordShortcut(binding.id,recording: $0) })
    recorder.beginRecording()
    #expect(store.recordingShortcutID == binding.id)
    #expect(recorder.performKeyEquivalent(with: try shortcutEvent(48,flags: [.option,.control],characters: "\t")))
    #expect(recorder.value.key == "Tab")
    #expect(recorder.value.modifiers == UInt32(optionKey | controlKey))
    #expect(recorder.recording)
    #expect(configurations == [binding.id,binding.id])
    recorder.keyDown(with: try shortcutEvent(40,flags: [.command],characters: "k"))
    #expect(recorder.value.key == "Tab")
    recorder.keyUp(with: try shortcutEvent(40,type: .keyUp))
    #expect(recorder.recording)
    recorder.keyUp(with: try shortcutEvent(48,type: .keyUp))
    #expect(!recorder.recording)
    #expect(store.recordingShortcutID == nil)
    #expect(configurations == [binding.id,binding.id,nil])
}

@Test @MainActor
func recorderRetriesConflictsAndUnmodifiedKeysThenCapturesArrow() throws {
    let (store,directory) = makeStore(bridge: FakeWindows())
    defer { store.shutdown(); try? FileManager.default.removeItem(at: directory) }
    let binding = try #require(store.preferences.shortcuts.first { $0.id == "workspace-next" })
    let recorder = RecorderButton(value: binding,onRecord: store.changeShortcut,
        onRecordingChanged: { store.recordShortcut(binding.id,recording: $0) })
    recorder.beginRecording()
    recorder.keyDown(with: try shortcutEvent(0,characters: "a"))
    #expect(recorder.recording)
    #expect(recorder.value == binding)
    recorder.keyDown(with: try shortcutEvent(0,flags: [.control,.option],characters: "a"))
    #expect(store.shortcutConfigurationError?.contains("Auto Layout") == true)
    #expect(recorder.recording)
    #expect(recorder.performKeyEquivalent(with: try shortcutEvent(124,flags: [.command,.shift])))
    #expect(recorder.value.key == "→")
    #expect(store.shortcutConfigurationError == nil)
    recorder.keyUp(with: try shortcutEvent(124,type: .keyUp))
    #expect(!recorder.recording)
}

@Test @MainActor
func recorderCancellationDisableAndTeardownRestoreHotkeys() throws {
    let binding = ShortcutBinding.defaults[0]
    var states: [Bool] = [], saved: [ShortcutBinding] = []
    let recorder = RecorderButton(value: binding,onRecord: { saved.append($0); return true },onRecordingChanged: { states.append($0) })
    recorder.beginRecording()
    recorder.keyDown(with: try shortcutEvent(53))
    #expect(!recorder.recording)
    #expect(saved.isEmpty)
    recorder.beginRecording()
    recorder.keyDown(with: try shortcutEvent(51))
    #expect(saved.count == 1)
    #expect(saved.first?.enabled == false)
    #expect(recorder.recording)
    _ = recorder.resignFirstResponder()
    #expect(!recorder.recording)
    recorder.beginRecording()
    recorder.viewDidMoveToWindow() // removing a recorder from its window
    #expect(!recorder.recording)
    #expect(states == [true,false,true,false,true,false])
}

@Test @MainActor
func oldRecorderCannotResumeHotkeysWhileAnotherRecorderOwnsCapture() {
    let (store,directory) = makeStore(bridge: FakeWindows())
    defer { store.shutdown(); try? FileManager.default.removeItem(at: directory) }
    store.recordShortcut("workspace-next",recording: true)
    store.recordShortcut("auto-layout",recording: true)
    store.recordShortcut("workspace-next",recording: false)
    #expect(store.recordingShortcutID == "auto-layout")
    store.recordShortcut("auto-layout",recording: false)
    #expect(store.recordingShortcutID == nil)
}
