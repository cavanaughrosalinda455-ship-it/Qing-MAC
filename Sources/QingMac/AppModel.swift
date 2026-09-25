import AppKit
import Foundation

struct InstalledApp: Identifiable, Sendable {
    var id: String { url.path }
    let url: URL
    let name: String
    let bundleID: String
    let bytes: Int64
}

struct ExtensionItem: Identifiable, Sendable {
    var id: String { url.path }
    let url: URL
    let kind: String
}

struct PermissionEntry: Identifiable, Sendable {
    var id: String { client + "|" + service }
    let client: String
    let service: String
    let authorization: Int

    var serviceName: String {
        let names = [
            "kTCCServiceCamera": "相机", "kTCCServiceMicrophone": "麦克风",
            "kTCCServiceScreenCapture": "屏幕录制", "kTCCServiceAccessibility": "辅助功能",
            "kTCCServiceSystemPolicyAllFiles": "完全磁盘访问", "kTCCServiceSystemPolicyDesktopFolder": "桌面文件夹",
            "kTCCServiceSystemPolicyDocumentsFolder": "文稿文件夹", "kTCCServiceSystemPolicyDownloadsFolder": "下载文件夹",
            "kTCCServiceAddressBook": "通讯录", "kTCCServiceCalendar": "日历",
            "kTCCServicePhotos": "照片", "kTCCServiceAppleEvents": "自动化",
            "kTCCServiceListenEvent": "输入监控", "kTCCServiceBluetoothAlways": "蓝牙"
        ]
        return names[service] ?? service.replacingOccurrences(of: "kTCCService", with: "")
    }

    var statusName: String {
        switch authorization {
        case 2: "已允许"
        case 0: "已拒绝"
        default: "受限或待确认"
        }
    }
}

struct LoginAgent: Identifiable, Sendable {
    var id: String { url.path }
    let url: URL
    let enabled: Bool
}

enum FileSortMode: String, CaseIterable {
    case size = "按大小"
    case lastAccessed = "按最近访问"
}

struct SmartCheck: Identifiable, Sendable {
    let id: String
    let title: String
    let detail: String
    let symbol: String
    let destination: SidebarPage
}

struct SmartScanResult: Sendable {
    let report: ScanReport
    let checks: [SmartCheck]
}

@MainActor
@Observable final class AppModel {
    var page: SidebarPage = .overview
    var groups: [ScanGroup] = []
    var scanIssues: [ScanIssue] = []
    var smartChecks: [SmartCheck] = []
    var scanIsRunning = false
    var scanProgress = 0.0
    var scanProgressLabel = ""
    private var scanTask: Task<SmartScanResult, Never>?
    private var scanID = UUID()
    var status = "点击扫描，了解可清理的空间"
    var confirmation: OperationConfirmation?
    var apps: [InstalledApp] = []
    var extensions: [ExtensionItem] = []
    var safariExtensions = ""
    var wifiNetworks: [String] = []
    var wifiInterface = "en0"
    var selectedWiFi = Set<String>()
    var permissionEntries: [PermissionEntry] = []
    var permissionError = ""
    var loginAgents: [LoginAgent] = []
    var xprotectStatus = ""
    var malwareItems: [ScanItem] = []
    var malwareScanRunning = false
    private var malwareScanID = UUID()
    var malwareScanMessage = ""
    var fileRoot = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
    var fileItems: [ScanItem] = []
    var fileSort: FileSortMode = .size
    var fileMode: SidebarPage = .large
    var fileScanRunning = false
    var fileCleanupRunning = false
    private var fileScanID = UUID()
    var selectedApp: InstalledApp?
    var appResiduals: [ScanItem] = []
    var residualScanRunning = false
    private var residualScanID = UUID()
    var maintenanceOutput = ""
    var cleanupInProgress = false
    var lastCleanupItems: [ScanItem] = []

    var totalBytes: Int64 { groups.reduce(0) { $0 + $1.bytes } }
    var selectedBytes: Int64 { groups.flatMap(\.items).filter(\.selected).reduce(0) { $0 + $1.bytes } }
    var displayedFileItems: [ScanItem] {
        guard fileMode == .large else { return fileItems }
        switch fileSort {
        case .size: return fileItems.sorted { $0.bytes > $1.bytes }
        case .lastAccessed:
            return fileItems.sorted {
                let left = $0.lastAccessed ?? .distantPast
                let right = $1.lastAccessed ?? .distantPast
                return left == right ? $0.bytes > $1.bytes : left < right
            }
        }
    }

    func scan(_ page: SidebarPage) {
        scanTask?.cancel()
        let id = UUID()
        scanID = id
        scanIsRunning = true
        scanProgress = 0
        scanProgressLabel = "准备扫描"
        groups = []
        scanIssues = []
        smartChecks = []
        lastCleanupItems = []
        status = "正在扫描…"
        let definitions: [ScanDefinition]
        switch page {
        case .mail: definitions = ScanCatalog.mail
        case .privacy: definitions = ScanCatalog.privacy
        case .trash:
            definitions = ScanCatalog.trash
        case .junk: definitions = ScanCatalog.junkWithTemporaryScreenshots
        default: definitions = ScanCatalog.junkWithTemporaryScreenshots + ScanCatalog.mail
        }
        let task = Task.detached(priority: .userInitiated) { [self] in
            let report = FileScanner.scanDetailed(definitions) { completed, total, title in
                Task { @MainActor in
                    guard self.scanID == id, self.scanIsRunning else { return }
                    self.scanProgress = Double(completed) / Double(max(total + (page == .overview ? 1 : 0), 1))
                    self.scanProgressLabel = "已扫描 \(title) · \(completed)/\(total)"
                }
            }
            guard page == .overview, !Task<Never, Never>.isCancelled else {
                return SmartScanResult(report: report, checks: [])
            }
            Task { @MainActor in
                guard self.scanID == id, self.scanIsRunning else { return }
                self.scanProgressLabel = "正在检查防护与性能状态…"
            }
            let checks = Self.readSmartChecks()
            return SmartScanResult(report: report, checks: checks)
        }
        scanTask = task
        Task {
            let result = await task.value
            guard scanID == id, !task.isCancelled else { return }
            groups = result.report.groups
            scanIssues = result.report.issues
            smartChecks = result.checks
            scanIsRunning = false
            scanProgress = 1
            scanTask = nil
            if result.report.groups.allSatisfy(\.items.isEmpty) {
                status = result.report.issues.isEmpty ? "没有找到可清理的项目" : "部分目录无法读取，请查看下方说明"
            } else {
                status = "扫描完成 · \(SpaceFormat.size(totalBytes)) · 可取消不想清理的项目"
            }
        }
    }

    func cancelScan() {
        scanTask?.cancel()
        scanTask = nil
        scanID = UUID()
        scanIsRunning = false
        scanProgress = 0
        scanProgressLabel = ""
        groups = []
        scanIssues = []
        smartChecks = []
        status = "已取消扫描"
    }

    private nonisolated static func readSmartChecks() -> [SmartCheck] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let agents = (try? FileManager.default.contentsOfDirectory(at: home.appendingPathComponent("Library/LaunchAgents"), includingPropertiesForKeys: nil)) ?? []
        let agentCount = agents.filter { $0.pathExtension == "plist" }.count
        let privacyReport = FileScanner.scanDetailed(ScanCatalog.privacy)
        let privacyCount = privacyReport.groups.flatMap(\.items).count
        let privacyDetail = privacyReport.issues.isEmpty
            ? "发现 \(privacyCount) 个历史记录或网站数据文件，可单独查看"
            : "发现 \(privacyCount) 个文件；\(privacyReport.issues.count) 处无法读取，请单独查看"
        let free = (try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?.volumeAvailableCapacityForImportantUsage
        let engine = ["/opt/homebrew/bin/clamscan", "/usr/local/bin/clamscan"].contains { FileManager.default.isExecutableFile(atPath: $0) }
        return [
            SmartCheck(id: "malware", title: "恶意软件", detail: engine ? "可运行 ClamAV 签名扫描；尚未在本次智能扫描中执行" : "未安装 ClamAV；尚未进行恶意软件扫描", symbol: "shield.lefthalf.filled", destination: .malware),
            SmartCheck(id: "privacy", title: "浏览器隐私", detail: privacyDetail, symbol: "eye.slash", destination: .privacy),
            SmartCheck(id: "login", title: "登录项目", detail: "发现 \(agentCount) 个当前用户的传统启动代理", symbol: "bolt", destination: .optimization),
            SmartCheck(id: "disk", title: "磁盘空间", detail: free.map { "可用 \(SpaceFormat.size($0))" } ?? "无法读取可用空间", symbol: "internaldrive", destination: .space)
        ]
    }

    func toggleItem(groupID: String, itemID: String) {
        guard let group = groups.firstIndex(where: { $0.id == groupID }),
              let item = groups[group].items.firstIndex(where: { $0.id == itemID }) else { return }
        groups[group].items[item].selected.toggle()
    }

    func setAllScanSelection(_ selected: Bool) {
        for groupIndex in groups.indices {
            for itemIndex in groups[groupIndex].items.indices {
                groups[groupIndex].items[itemIndex].selected = selected
            }
        }
    }

    func toggleFileItem(_ id: String) {
        guard let index = fileItems.firstIndex(where: { $0.id == id }) else { return }
        if fileMode == .duplicates && fileItems[index].note == "保留原件" { return }
        fileItems[index].selected.toggle()
    }

    func requestCleanup(permanent: Bool = false) {
        let chosen = groups.flatMap(\.items).filter(\.selected)
        guard !chosen.isEmpty else { status = "请先选择项目"; return }
        confirmation = .init(title: permanent ? "清空所选废纸篓项目？" : "将所选项目移到废纸篓？",
                             detail: "共 \(chosen.count) 项，\(SpaceFormat.size(chosen.reduce(0) { $0 + $1.bytes }))。\(permanent ? "删除后无法恢复。" : "关闭相关应用后清理效果更完整。")",
                             button: permanent ? "永久删除" : "移到废纸篓") { [weak self] in
            self?.performCleanup(chosen, permanent: permanent)
        }
    }

    private func performCleanup(_ items: [ScanItem], permanent: Bool) {
        cleanupInProgress = true
        Task {
            let result = await Task.detached(priority: .userInitiated) { () -> ([ScanItem], [String]) in
                var succeeded: [ScanItem] = []
                var failures: [String] = []
                for item in items {
                    do {
                        if permanent { try FileManager.default.removeItem(at: item.url) }
                        else { try FileManager.default.trashItem(at: item.url, resultingItemURL: nil) }
                        succeeded.append(item)
                    } catch { failures.append("\(item.name)：\(error.localizedDescription)") }
                }
                return (succeeded, failures)
            }.value
            let succeededIDs = Set(result.0.map(\.id))
            for groupIndex in groups.indices {
                groups[groupIndex].items.removeAll { succeededIDs.contains($0.id) }
            }
            lastCleanupItems = result.0
            cleanupInProgress = false
            status = "已处理 \(result.0.count) 项" + (result.1.isEmpty ? "" : "；\(result.1.count) 项失败：\(result.1.prefix(2).joined(separator: "、"))")
        }
    }

    func loadApps() {
        Task {
            apps = await Task.detached(priority: .userInitiated) { () -> [InstalledApp] in
                let paths = ["/Applications", NSString(string: "~/Applications").expandingTildeInPath]
                let urls = paths.flatMap { (try? FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: $0), includingPropertiesForKeys: nil)) ?? [] }
                return urls.filter { $0.pathExtension == "app" }.map { url in
                    let bundle = Bundle(url: url)
                    return InstalledApp(url: url, name: url.deletingPathExtension().lastPathComponent,
                                        bundleID: bundle?.bundleIdentifier ?? "", bytes: FileScanner.size(of: url))
                }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            }.value
        }
    }

    func inspectApp(_ app: InstalledApp) {
        let id = UUID()
        residualScanID = id
        selectedApp = app
        appResiduals = []
        residualScanRunning = true
        Task {
            let result = await Task.detached(priority: .userInitiated) { AppResidualScanner.scan(for: app) }.value
            guard residualScanID == id else { return }
            appResiduals = result
            residualScanRunning = false
        }
    }

    func toggleAppResidual(_ id: String) {
        guard let index = appResiduals.firstIndex(where: { $0.id == id }) else { return }
        appResiduals[index].selected.toggle()
    }

    func selectSafeAppResiduals() {
        let safeLocations = ["Caches", "Preferences", "Saved Application State", "WebKit", "HTTPStorages"]
        for index in appResiduals.indices {
            appResiduals[index].selected = safeLocations.contains { appResiduals[index].note.hasPrefix($0) }
        }
    }

    func requestFullUninstall(_ app: InstalledApp) {
        let chosen = selectedApp?.id == app.id ? appResiduals.filter(\.selected) : []
        confirmation = .init(title: "卸载 \(app.name) 和所选关联文件？",
                             detail: "应用及 \(chosen.count) 个关联文件将移到废纸篓。请先退出应用，核对所选路径。",
                             button: "卸载并移到废纸篓") { [weak self] in
            guard let self else { return }
            let targets = [app.url] + chosen.map(\.url)
            Task {
                let failures = await Task.detached(priority: .userInitiated) { () -> [String] in
                    var failed: [String] = []
                    for url in targets {
                        do { try FileManager.default.trashItem(at: url, resultingItemURL: nil) }
                        catch { failed.append(url.lastPathComponent) }
                    }
                    return failed
                }.value
                if !FileManager.default.fileExists(atPath: app.url.path) { self.apps.removeAll { $0.id == app.id } }
                self.appResiduals.removeAll { !FileManager.default.fileExists(atPath: $0.url.path) }
                self.status = failures.isEmpty ? "已移走应用和 \(chosen.count) 个关联文件" : "有 \(failures.count) 项未能移走：\(failures.prefix(2).joined(separator: "、"))"
            }
        }
    }

    func requestResetSelectedResiduals(_ app: InstalledApp) {
        guard selectedApp?.id == app.id else { return }
        let chosen = appResiduals.filter(\.selected)
        guard !chosen.isEmpty else { status = "请先选择要重置的关联文件"; return }
        confirmation = .init(title: "重置 \(app.name) 的所选数据？",
                             detail: "将 \(chosen.count) 个缓存或设置移到废纸篓，应用本体保留。请确认其中没有需要保留的本地数据。",
                             button: "重置所选") { [weak self] in
            guard let self else { return }
            Task {
                let failures = await Task.detached(priority: .userInitiated) { () -> Int in
                    var count = 0
                    for item in chosen {
                        do { try FileManager.default.trashItem(at: item.url, resultingItemURL: nil) }
                        catch { count += 1 }
                    }
                    return count
                }.value
                self.appResiduals.removeAll { !FileManager.default.fileExists(atPath: $0.url.path) }
                self.status = failures == 0 ? "已重置所选关联文件" : "有 \(failures) 项未能重置"
            }
        }
    }

    func requestUninstall(_ app: InstalledApp) {
        confirmation = .init(title: "卸载 \(app.name)？", detail: "应用将移到废纸篓。应用数据会保留，可另行重置。", button: "移到废纸篓") { [weak self] in
            do {
                try FileManager.default.trashItem(at: app.url, resultingItemURL: nil)
                self?.apps.removeAll { $0.id == app.id }
                self?.status = "已将 \(app.name) 移到废纸篓"
            } catch { self?.status = error.localizedDescription }
        }
    }

    func resetPaths(for app: InstalledApp) -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var paths = [home.appendingPathComponent("Library/Application Support/\(app.name)"),
                     home.appendingPathComponent("Library/Saved Application State/\(app.bundleID).savedState"),
                     home.appendingPathComponent("Library/Preferences/\(app.bundleID).plist"),
                     home.appendingPathComponent("Library/Caches/\(app.bundleID)")]
        if !app.bundleID.isEmpty { paths.append(home.appendingPathComponent("Library/Containers/\(app.bundleID)")) }
        return paths.filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    func requestReset(_ app: InstalledApp) {
        let paths = resetPaths(for: app)
        guard !paths.isEmpty else { status = "没有找到 \(app.name) 的常见用户数据"; return }
        confirmation = .init(title: "重置 \(app.name)？", detail: "将 \(paths.count) 处偏好设置、缓存或容器数据移到废纸篓。可能删除登录状态与本地文档，请先退出应用。", button: "重置应用") { [weak self] in
            var failed = 0
            for url in paths { do { try FileManager.default.trashItem(at: url, resultingItemURL: nil) } catch { failed += 1 } }
            self?.status = failed == 0 ? "已重置 \(app.name)" : "部分数据未能移动：\(failed) 项"
        }
    }

    func loadExtensions() {
        let paths = ["~/Library/PreferencePanes", "/Library/PreferencePanes", "~/Library/Internet Plug-Ins", "/Library/Internet Plug-Ins", "~/Library/QuickLook", "/Library/QuickLook", "~/Library/Safari/Extensions"]
        extensions = paths.flatMap { path -> [ExtensionItem] in
            let url = FileScanner.expanded(path)
            let children = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []
            return children.map { ExtensionItem(url: $0, kind: url.lastPathComponent) }
        }
        Task {
            safariExtensions = await Task.detached(priority: .utility) {
                let modern = Shell.run("/usr/bin/pluginkit", ["-mAvvv", "-p", "com.apple.Safari.web-extension"])
                let classic = Shell.run("/usr/bin/pluginkit", ["-mAvvv", "-p", "com.apple.Safari.extension"])
                return [modern, classic].filter { !$0.isEmpty }.joined(separator: "\n")
            }.value
        }
    }

    func requestRemoveExtension(_ item: ExtensionItem) {
        let homeLibrary = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library").path + "/"
        guard item.url.path.hasPrefix(homeLibrary) else { status = "系统级扩展请在系统设置中管理"; return }
        confirmation = .init(title: "移走 \(item.url.lastPathComponent)？", detail: "用户安装的扩展将移到废纸篓。相关应用可能需要重启才能反映变化。", button: "移到废纸篓") { [weak self] in
            do {
                try FileManager.default.trashItem(at: item.url, resultingItemURL: nil)
                self?.extensions.removeAll { $0.id == item.id }
                self?.status = "已移走 \(item.url.lastPathComponent)"
            } catch { self?.status = error.localizedDescription }
        }
    }

    func loadWiFi() {
        Task {
            let result = await Task.detached { () -> (String, [String]) in
                let hardware = Shell.run("/usr/sbin/networksetup", ["-listallhardwareports"])
                let lines = hardware.components(separatedBy: .newlines)
                var interface = "en0"
                for (index, line) in lines.enumerated() where line.contains("Hardware Port: Wi-Fi") {
                    if index + 1 < lines.count { interface = lines[index + 1].replacingOccurrences(of: "Device: ", with: "") }
                }
                let result = Shell.run("/usr/sbin/networksetup", ["-listpreferredwirelessnetworks", interface])
                let networks = result.components(separatedBy: .newlines).dropFirst().map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty && !$0.contains("Error:") }
                return (interface, networks)
            }.value
            wifiInterface = result.0
            wifiNetworks = result.1
            selectedWiFi.formIntersection(result.1)
        }
    }

    func toggleWiFi(_ network: String) {
        if selectedWiFi.contains(network) { selectedWiFi.remove(network) }
        else { selectedWiFi.insert(network) }
    }

    func requestForgetWiFi() {
        let networks = wifiNetworks.filter { selectedWiFi.contains($0) }
        guard !networks.isEmpty else { return }
        confirmation = .init(title: "忘记所选 Wi-Fi？", detail: "将从这台 Mac 移除 \(networks.count) 个已保存网络。再次连接时可能需要重新输入密码。", button: "忘记网络") { [weak self] in
            guard let self else { return }
            let interface = wifiInterface
            Task {
                let results = await Task.detached(priority: .userInitiated) {
                    networks.map { name in
                        (name, Shell.runWithStatus("/usr/sbin/networksetup", ["-removepreferredwirelessnetwork", interface, name]))
                    }
                }.value
                let succeeded = results.filter { $0.1.exitCode == 0 }.map(\.0)
                self.selectedWiFi.subtract(succeeded)
                self.status = succeeded.count == networks.count ? "已忘记 \(succeeded.count) 个 Wi-Fi 网络" :
                    "已忘记 \(succeeded.count) 个；其余操作失败，可能需要在系统设置中管理"
                self.loadWiFi()
            }
        }
    }

    func loadPermissions() {
        permissionError = "正在读取授权概览…"
        Task {
            let result = await Task.detached(priority: .utility) { () -> ([PermissionEntry], String) in
                let path = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/com.apple.TCC/TCC.db").path
                guard FileManager.default.fileExists(atPath: path) else { return ([], "未找到当前用户的授权数据库") }
                let output = Shell.run("/usr/bin/sqlite3", ["-readonly", "-separator", "\t", path,
                    "SELECT service, client, auth_value FROM access ORDER BY client, service;"])
                let entries = output.components(separatedBy: .newlines).compactMap { line -> PermissionEntry? in
                    let parts = line.components(separatedBy: "\t")
                    guard parts.count == 3, let value = Int(parts[2]) else { return nil }
                    return PermissionEntry(client: parts[1], service: parts[0], authorization: value)
                }
                if entries.isEmpty {
                    return ([], output.isEmpty ? "数据库中没有可显示的授权记录" : "无法读取授权数据库：\(output)")
                }
                return (entries, "")
            }.value
            permissionEntries = result.0
            permissionError = result.1
        }
    }

    func loadLoginAgents() {
        let base = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library")
        let enabledDirectory = base.appendingPathComponent("LaunchAgents")
        let disabledDirectory = base.appendingPathComponent("LaunchAgents Disabled")
        let enabled = ((try? FileManager.default.contentsOfDirectory(at: enabledDirectory, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "plist" }.map { LoginAgent(url: $0, enabled: true) }
        let disabled = ((try? FileManager.default.contentsOfDirectory(at: disabledDirectory, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "plist" }.map { LoginAgent(url: $0, enabled: false) }
        loginAgents = (enabled + disabled).sorted { $0.url.lastPathComponent < $1.url.lastPathComponent }
    }

    func requestToggleLoginAgent(_ agent: LoginAgent) {
        confirmation = .init(title: agent.enabled ? "停用这个启动代理？" : "启用这个启动代理？",
                             detail: "\(agent.url.lastPathComponent) 的配置会在当前用户目录内移动。运行状态可能要等下次登录后才完全更新。",
                             button: agent.enabled ? "停用" : "启用") { [weak self] in
            guard let self else { return }
            let base = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library")
            let destinationDirectory = base.appendingPathComponent(agent.enabled ? "LaunchAgents Disabled" : "LaunchAgents")
            let destination = destinationDirectory.appendingPathComponent(agent.url.lastPathComponent)
            do {
                try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
                guard !FileManager.default.fileExists(atPath: destination.path) else { status = "目标目录已有同名配置，未执行"; return }
                let domain = "gui/\(getuid())"
                if agent.enabled { _ = Shell.runWithStatus("/bin/launchctl", ["bootout", domain, agent.url.path]) }
                try FileManager.default.moveItem(at: agent.url, to: destination)
                if !agent.enabled { _ = Shell.runWithStatus("/bin/launchctl", ["bootstrap", domain, destination.path]) }
                status = agent.enabled ? "已停用 \(agent.url.lastPathComponent)" : "已启用 \(agent.url.lastPathComponent)"
                loadLoginAgents()
            } catch { status = error.localizedDescription }
        }
    }

    func loadXProtect() {
        xprotectStatus = "正在检查系统防护状态…"
        Task {
            xprotectStatus = await Task.detached(priority: .utility) {
                let version = Shell.run("/usr/bin/xprotect", ["version"])
                let status = Shell.run("/usr/bin/xprotect", ["status"])
                return [version, status].filter { !$0.isEmpty }.joined(separator: "\n")
            }.value
        }
    }

    var clamAVPath: String? {
        ["/opt/homebrew/bin/clamscan", "/usr/local/bin/clamscan"].first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    func scanMalware() {
        guard let executable = clamAVPath else { malwareScanMessage = "未安装 ClamAV 扫描引擎"; return }
        let id = UUID()
        malwareScanID = id
        let root = fileRoot
        malwareItems = []
        malwareScanRunning = true
        malwareScanMessage = "正在使用 ClamAV 扫描所选目录…"
        Task {
            let output = await Task.detached(priority: .userInitiated) {
                Shell.run(executable, ["--recursive", root.path])
            }.value
            guard malwareScanID == id, fileRoot == root else { return }
            malwareItems = output.components(separatedBy: .newlines).compactMap { line in
                guard line.hasSuffix(" FOUND"), let separator = line.range(of: ": ", options: .backwards) else { return nil }
                let path = String(line[..<separator.lowerBound])
                let signature = String(line[separator.upperBound...].dropLast(" FOUND".count))
                let url = URL(fileURLWithPath: path)
                let normalized = url.standardizedFileURL.path
                let base = root.standardizedFileURL.path
                guard (normalized == base || normalized.hasPrefix(base + "/")), FileManager.default.fileExists(atPath: normalized) else { return nil }
                return ScanItem(url: url, bytes: FileScanner.size(of: url), category: "ClamAV 检测", note: signature, selected: false)
            }
            malwareScanRunning = false
            if output.contains("ERROR") || output.contains("Error") {
                malwareScanMessage = "扫描可能未完成：\(output.components(separatedBy: .newlines).first { $0.contains("ERROR") || $0.contains("Error") } ?? "未知错误")"
            } else {
                malwareScanMessage = malwareItems.isEmpty ? "扫描完成，未检测到已知威胁" : "发现 \(malwareItems.count) 个匹配项，请逐项核对后处理"
            }
        }
    }

    func toggleMalwareItem(_ id: String) {
        guard let index = malwareItems.firstIndex(where: { $0.id == id }) else { return }
        malwareItems[index].selected.toggle()
    }

    func requestMalwareCleanup() {
        let chosen = malwareItems.filter(\.selected)
        guard !chosen.isEmpty else { return }
        confirmation = .init(title: "移走选中的检测项？", detail: "ClamAV 可能出现误报。请核对 \(chosen.count) 个文件与签名；文件将移到废纸篓，可恢复。", button: "移到废纸篓") { [weak self] in
            var failures = 0
            for item in chosen {
                do { try FileManager.default.trashItem(at: item.url, resultingItemURL: nil) }
                catch { failures += 1 }
            }
            self?.malwareItems.removeAll { chosen.contains($0) && !FileManager.default.fileExists(atPath: $0.url.path) }
            self?.malwareScanMessage = failures == 0 ? "已移走 \(chosen.count) 个检测项" : "有 \(failures) 个文件未能移走"
        }
    }

    func scanFiles(mode: SidebarPage) {
        let id = UUID()
        fileScanID = id
        fileMode = mode
        fileScanRunning = true
        let root = fileRoot
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                mode == .duplicates ? FileScanner.duplicates(in: root) : FileScanner.largeOrOld(in: root)
            }.value
            guard fileScanID == id else { return }
            fileItems = result
            fileScanRunning = false
        }
    }

    func clearFileResults(mode: SidebarPage) {
        fileScanID = UUID()
        fileMode = mode
        fileScanRunning = false
        fileItems = []
        if mode == .malware {
            malwareScanID = UUID()
            malwareScanRunning = false
            malwareItems = []
            malwareScanMessage = ""
        }
    }

    func requestFileCleanup(permanent: Bool = false) {
        let chosen = fileItems.filter(\.selected)
        guard !chosen.isEmpty else { status = "请先选择文件"; return }
        let duplicateMode = fileMode == .duplicates
        let keepers = Dictionary(fileItems.filter { $0.note == "保留原件" }.compactMap { item -> (String, URL)? in
            item.contentDigest.map { ($0, item.url) }
        }, uniquingKeysWith: { first, _ in first })
        confirmation = .init(title: permanent ? "永久删除所选文件？" : "处理所选文件？",
                             detail: "共 \(chosen.count) 个文件，\(SpaceFormat.size(chosen.reduce(0) { $0 + $1.bytes }))。\(permanent ? "APFS 快照与 SSD 机制可能保留数据，无法保证安全擦除。" : "文件会移到废纸篓。")",
                             button: permanent ? "永久删除" : "移到废纸篓") { [weak self] in
            guard let self else { return }
            self.fileCleanupRunning = true
            Task {
                let result = await Task.detached(priority: .userInitiated) { () -> ([String], Int) in
                    var succeeded: [String] = []
                    var failed = 0
                    for item in chosen {
                        if duplicateMode {
                            guard let digest = item.contentDigest, let keeper = keepers[digest],
                                  FileScanner.isStillDuplicate(item, keeper: keeper) else { failed += 1; continue }
                        }
                        do {
                            if permanent { try FileManager.default.removeItem(at: item.url) }
                            else { try FileManager.default.trashItem(at: item.url, resultingItemURL: nil) }
                            succeeded.append(item.id)
                        } catch { failed += 1 }
                    }
                    return (succeeded, failed)
                }.value
                let succeededIDs = Set(result.0)
                self.fileItems.removeAll { succeededIDs.contains($0.id) }
                self.fileCleanupRunning = false
                self.status = result.1 == 0 ? "已处理 \(result.0.count) 个文件" : "已处理 \(result.0.count) 个；\(result.1) 个文件已变化或处理失败"
            }
        }
    }

    func runMaintenance(_ action: MaintenanceAction) {
        maintenanceOutput = "正在运行 \(action.title)…"
        Task {
            maintenanceOutput = await Task.detached { Shell.run(action.command, action.arguments) }.value
            if maintenanceOutput.isEmpty { maintenanceOutput = "已完成 \(action.title)" }
        }
    }
}

struct OperationConfirmation: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
    let button: String
    let perform: @MainActor () -> Void
}

struct MaintenanceAction: Identifiable {
    let id: String
    let title: String
    let detail: String
    let command: String
    let arguments: [String]

    static let all: [MaintenanceAction] = [
        .init(id: "quicklook", title: "重置快速查看缓存", detail: "修复预览缩略图异常", command: "/usr/bin/qlmanage", arguments: ["-r", "cache"]),
        .init(id: "dns", title: "刷新 DNS 缓存", detail: "让网络域名解析重新加载", command: "/usr/bin/dscacheutil", arguments: ["-flushcache"]),
        .init(id: "spotlight", title: "查看 Spotlight 状态", detail: "检查当前磁盘索引状态", command: "/usr/bin/mdutil", arguments: ["-s", "/"])
    ]
}

enum Shell {
    static func run(_ executable: String, _ arguments: [String]) -> String {
        runWithStatus(executable, arguments).output
    }

    struct Result: Sendable {
        let output: String
        let exitCode: Int32
    }

    static func runWithStatus(_ executable: String, _ arguments: [String]) -> Result {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return Result(output: output, exitCode: process.terminationStatus)
        } catch { return Result(output: error.localizedDescription, exitCode: -1) }
    }
}
