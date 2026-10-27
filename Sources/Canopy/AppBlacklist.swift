import AppKit
import UniformTypeIdentifiers

struct BlacklistApp: Identifiable {
    var id: String
    var name: String
}

@MainActor
extension WorkspaceStore {
    var blacklistedApplications: [BlacklistApp] {
        excludedApps.map { BlacklistApp(id: $0,name: blacklistAppName($0)) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    var applicationsToBlacklist: [BlacklistApp] {
        var seen = Set<String>()
        return NSWorkspace.shared.runningApplications.compactMap { app in
            guard app.activationPolicy != .prohibited,let bundle = app.bundleIdentifier,
                  bundle != "org.canopywm.Canopy",!excludedApps.contains(bundle),seen.insert(bundle).inserted else { return nil }
            return BlacklistApp(id: bundle,name: app.localizedName ?? bundle)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    func blacklistAppName(_ bundle: String) -> String {
        if let name = NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first?.localizedName { return name }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle),let info = Bundle(url: url) {
            return info.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                ?? info.object(forInfoDictionaryKey: "CFBundleName") as? String ?? url.deletingPathExtension().lastPathComponent
        }
        if bundle == "cc.ffitch.shottr" { return "Shottr" }
        return records.first { $0.bundleID == bundle }?.app ?? bundle
    }
    func chooseAppsToBlacklist() {
        let panel = NSOpenPanel()
        panel.title = "Choose Apps to Always Float"
        panel.prompt = "Always Float"
        panel.allowedContentTypes = [.applicationBundle]
        panel.canChooseDirectories = false; panel.canChooseFiles = true
        panel.allowsMultipleSelection = true; panel.treatsFilePackagesAsDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications",isDirectory: true)
        panel.begin { [weak self] response in
            guard response == .OK,let self else { return }
            for url in panel.urls {
                if let id = Bundle(url: url)?.bundleIdentifier { self.excludeApp(id) }
            }
        }
    }
}
