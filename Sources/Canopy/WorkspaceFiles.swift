import AppKit
import UniformTypeIdentifiers
import CanopyCore
import Carbon

@MainActor
extension WorkspaceStore {
    static func validate(_ state: WorkspaceSnapshot) throws {
        guard (1...4).contains(state.version),state.records.count <= 2000,state.displays.count <= 32 else { throw CocoaError(.fileReadCorruptFile) }
        let ids = state.records.map(\.id),displayIDs = state.displays.map(\.id)
        let managed = state.displays.flatMap { $0.allGridWindows }
        guard Set(ids).count == ids.count,Set(displayIDs).count == displayIDs.count,
              Set(managed).count == managed.count,Set(managed.filter { !isDesktop($0) }).isSubset(of: Set(ids)),
              state.gap.isFinite,(0...32).contains(state.gap),
              state.records.allSatisfy({ !$0.id.isEmpty && $0.originalFrame.isValid }),
              state.displays.allSatisfy({ workspace in
                  !workspace.grids.isEmpty && workspace.grids.count <= 32 && workspace.grids.allSatisfy { grid in
                      (grid.cameraFrame?.isValid ?? true) && (grid.savedFrames?.values.allSatisfy(\.isValid) ?? true)
                          && (grid.historyFrames?.values.allSatisfy(\.isValid) ?? true)
                  }
              }) else { throw CocoaError(.fileReadCorruptFile) }
        if let p = state.preferences {
            let allowed = Set(ShortcutBinding.defaults.map(\.id)),bindings = p.shortcuts
            let allowedModifiers = UInt32(cmdKey | controlKey | optionKey | shiftKey)
            let enabled = bindings.filter(\.enabled).map { "\($0.keyCode):\($0.modifiers)" }
            guard p.animationDuration.isFinite,(0.1...1).contains(p.animationDuration),
                  p.minimumWidth.isFinite,(100...600).contains(p.minimumWidth),
                  p.minimumHeight.isFinite,(80...400).contains(p.minimumHeight),
                  Set(bindings.map(\.id)).count == bindings.count,bindings.allSatisfy({ binding in
                      allowed.contains(binding.id) && binding.keyCode < 128 && binding.key.count <= 24
                          && (!binding.enabled || (binding.modifiers & allowedModifiers != 0 && binding.modifiers & ~allowedModifiers == 0))
                  }),
                  Set(enabled).count == enabled.count else { throw CocoaError(.fileReadCorruptFile) }
        }
        let recovery = state.recoveryWindows ?? []
        guard recovery.count <= 2000,Set(recovery.map(\.id)).count == recovery.count,
              recovery.allSatisfy({ $0.originalFrame.isValid }) else { throw CocoaError(.fileReadCorruptFile) }
    }

    func exportWorkspace(to url: URL) throws {
        var state = snapshot
        // An exported layout is a template, not the current machine's crash journal.
        state.recoveryWindows = []; state.recoveryMinimized = []
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted,.sortedKeys]
        try encoder.encode(state).write(to: url,options: .atomic)
    }
    func importWorkspace(from url: URL) throws {
        let data = try Data(contentsOf: url)
        guard data.count <= 8*1024*1024 else { throw CocoaError(.fileReadTooLarge) }
        let state = try JSONDecoder().decode(WorkspaceSnapshot.self,from: data)
        try Self.validate(state)
        guard !isDemo else { message = "Switch to your real workspace before importing a layout."; return }
        floatAll()
        guard !hasWindowsToRestore else { throw CocoaError(.fileWriteUnknown) }
        try backupWorkspace()
        storageWasReplaced()
        restoreSnapshot(state); pendingRecovery = []; recoveryMinimized = []
        selectedWindow = nil; isArranging = false
        synchronizeScreens(); refresh(); persist(); onPreferencesChanged?()
        message = "Workspace imported. It is paused; choose Resume Layout when you're ready."
    }
    @discardableResult
    func backupWorkspace() throws -> URL? {
        guard FileManager.default.fileExists(atPath: persistenceURL.path) else { return nil }
        let directory = persistenceURL.deletingLastPathComponent().appendingPathComponent("Backups")
        try FileManager.default.createDirectory(at: directory,withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent("workspace-\(Int(Date().timeIntervalSince1970))-\(UUID().uuidString.prefix(6)).json")
        try FileManager.default.copyItem(at: persistenceURL,to: destination)
        return destination
    }
    func showExportPanel() {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = "Canopy-workspace.json"
        panel.begin { [weak self] response in
            guard response == .OK,let url = panel.url else { return }
            do { try self?.exportWorkspace(to: url) } catch { self?.message = "Could not export workspace: \(error.localizedDescription)" }
        }
    }
    func showImportPanel() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = false
        panel.begin { [weak self] response in
            guard response == .OK,let url = panel.url else { return }
            do { try self?.importWorkspace(from: url) } catch { self?.message = "Could not import workspace: \(error.localizedDescription)" }
        }
    }
}
