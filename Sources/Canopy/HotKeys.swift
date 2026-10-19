import AppKit
import Carbon
import Foundation

@MainActor
final class HotKeys {
    private var references: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?
    private var actions: [UInt32: () -> Void] = [:]
    private var registered: [(ShortcutBinding,UInt32)] = []
    private var nextID: UInt32 = 1
    private var failures: [String] = []
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var lastEvents: [UInt32:TimeInterval] = [:]

    init(store: WorkspaceStore) {
        let callback: EventHandlerUPP = { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            let result = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard result == noErr else { return result }
            let manager = Unmanaged<HotKeys>.fromOpaque(context).takeUnretainedValue()
            let actionID = id.id,time = GetEventTime(event)
            Task { @MainActor in manager.fire(actionID,time: time) }
            return noErr
        }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), callback, 1, &eventType,
                            Unmanaged.passUnretained(self).toOpaque(), &handler)
        // Carbon handles physical global hotkeys. AppKit also covers directly
        // delivered key events and keeps shortcuts usable in accessory windows.
        // Never consume a recorder's event, or a chord another app registered.
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            MainActor.assumeIsolated {
                if let recorder = NSApp.keyWindow?.firstResponder as? RecorderButton,recorder.recording { return event }
                guard let self,let id = self.match(event) else { return event }
                self.fire(id,time: event.timestamp); return nil
            }
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self,let id = self.match(event) else { return }
                self.fire(id,time: event.timestamp)
            }
        }
        configure(store: store)
    }
    private func match(_ event: NSEvent) -> UInt32? {
        registered.first { $0.0.matches(keyCode: event.keyCode,flags: event.modifierFlags) }?.1
    }
    private func fire(_ id: UInt32,time: TimeInterval) {
        // Carbon and AppKit can observe the same physical event. Timestamp
        // deduplication preserves real key repeat without switching twice.
        if let previous = lastEvents[id],abs(time-previous) < 0.01 { return }
        lastEvents[id] = time
        actions[id]?()
    }
    func configure(store: WorkspaceStore) {
        for reference in references { UnregisterEventHotKey(reference) }
        references = []; actions = [:]; registered = []; failures = []; lastEvents = [:]; nextID = 1
        for binding in store.preferences.shortcuts where binding.enabled {
            register(binding) { [weak store] in store?.performCommand(binding.id) }
        }
        store.shortcutStatus = failures.isEmpty ? nil : "Unavailable shortcuts: \(failures.joined(separator: ", ")). Another app may already use them."
    }
    private func register(_ binding: ShortcutBinding,action: @escaping () -> Void) {
        let id = nextID; nextID += 1
        var reference: EventHotKeyRef?
        let result = RegisterEventHotKey(binding.keyCode,binding.modifiers,EventHotKeyID(signature: 0x43414E50,id: id),GetApplicationEventTarget(),0,&reference)
        if result == noErr,let reference {
            references.append(reference); actions[id] = action; registered.append((binding,id))
        } else { failures.append(binding.title) }
    }
    func stop() {
        for reference in references { UnregisterEventHotKey(reference) }
        references = []; registered = []; actions = [:]
        if let handler { RemoveEventHandler(handler); self.handler = nil }
        if let localMonitor { NSEvent.removeMonitor(localMonitor); self.localMonitor = nil }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor); self.globalMonitor = nil }
    }
}

extension ShortcutBinding {
    func matches(keyCode: UInt16,flags: NSEvent.ModifierFlags) -> Bool {
        guard enabled,self.keyCode == UInt32(keyCode) else { return false }
        var carbon: UInt32 = 0
        if flags.contains(.command) { carbon |= UInt32(cmdKey) }
        if flags.contains(.control) { carbon |= UInt32(controlKey) }
        if flags.contains(.option) { carbon |= UInt32(optionKey) }
        if flags.contains(.shift) { carbon |= UInt32(shiftKey) }
        return modifiers == carbon
    }
}
