import Foundation

enum AppResidualScanner {
    // Only user-library locations. A matching vendor folder is never selected as a whole.
    static let libraryLocations = [
        "Application Support", "Caches", "Preferences", "Containers", "Group Containers",
        "Saved Application State", "Logs", "LaunchAgents", "Internet Plug-Ins",
        "PreferencePanes", "QuickLook", "Application Scripts", "WebKit", "Cookies",
        "HTTPStorages", "Autosave Information", "Services", "Spotlight", "Screen Savers"
    ]

    static func scan(for app: InstalledApp, library: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library")) -> [ScanItem] {
        let name = app.name.lowercased()
        let bundleID = app.bundleID.lowercased()
        var seen = Set<String>()
        var result: [ScanItem] = []

        func matches(_ filename: String) -> Bool {
            let value = filename.lowercased()
            if value == name || value == name + ".plist" || value == name + ".savedstate" { return true }
            guard !bundleID.isEmpty else { return false }
            return value == bundleID || value.hasPrefix(bundleID + ".") || value.hasPrefix(bundleID + "-")
        }

        func append(_ url: URL, reason: String) {
            guard seen.insert(url.path).inserted else { return }
            result.append(ScanItem(url: url, bytes: FileScanner.size(of: url), category: "应用关联文件", note: reason, selected: false))
        }

        for location in libraryLocations {
            if Task<Never, Never>.isCancelled { break }
            let directory = library.appendingPathComponent(location)
            let children = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey], options: [])) ?? []
            for child in children {
                if Task<Never, Never>.isCancelled { break }
                if matches(child.lastPathComponent) { append(child, reason: location); continue }
                // Apps often store their own files one level below a shared vendor folder.
                guard ["Application Support", "Caches", "Logs", "Group Containers"].contains(location),
                      (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
                let nested = (try? FileManager.default.contentsOfDirectory(at: child, includingPropertiesForKeys: nil)) ?? []
                for candidate in nested where matches(candidate.lastPathComponent) {
                    append(candidate, reason: "\(location)/\(child.lastPathComponent)")
                }
            }
        }
        return result.sorted { $0.url.path < $1.url.path }
    }
}
