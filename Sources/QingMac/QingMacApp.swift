import AppKit
import SwiftUI

@main
struct QingMacApp: App {
    var body: some Scene {
        WindowGroup("清清 Mac") {
            MainView()
                .frame(minWidth: 1020, minHeight: 690)
        }
        .windowStyle(.titleBar)

        MenuBarExtra("清清 Mac", systemImage: "sparkles.rectangle.stack") {
            MenuMetricsView()
        }
        .menuBarExtraStyle(.window)
    }
}

struct MainView: View {
    @State private var model = AppModel()
    @State private var permissionSearch = ""

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "sparkles.rectangle.stack")
                        .font(.title2.bold())
                        .foregroundStyle(.cyan)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("清清 Mac").font(.headline)
                        Text("你的 Mac，清爽有序").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(18)

                List {
                    ForEach(SidebarSection.allCases, id: \.self) { section in
                        Section(section.rawValue) {
                            ForEach(section.pages) { page in
                                Button {
                                    model.page = page
                                    loadIfNeeded(page)
                                } label: {
                                    Label(page.rawValue, systemImage: page.symbol)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .listRowBackground(model.page == page ? Color.accentColor.opacity(0.15) : Color.clear)
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
                HStack {
                    Image(systemName: "checkmark.shield.fill").foregroundStyle(.green)
                    Text("所有操作都由你确认").font(.caption)
                }
                .foregroundStyle(.secondary)
                .padding(14)
            }
            .frame(minWidth: 215)
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    pageContent
                    if !model.status.isEmpty {
                        Text(model.status)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(30)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .alert(item: $model.confirmation) { request in
            Alert(title: Text(request.title), message: Text(request.detail),
                  primaryButton: .destructive(Text(request.button), action: request.perform),
                  secondaryButton: .cancel(Text("取消")))
        }
        .onAppear { model.scan(.overview) }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text(model.page.rawValue).font(.largeTitle.bold())
                Text(subtitle(for: model.page)).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: model.page.symbol)
                .font(.system(size: 29, weight: .medium))
                .foregroundStyle(.cyan)
                .frame(width: 58, height: 58)
                .background(.cyan.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
        }
    }

    @ViewBuilder private var pageContent: some View {
        switch model.page {
        case .overview, .junk, .mail, .trash, .privacy: scanPage
        case .malware: malwarePage
        case .wifi: wifiPage
        case .permissions: permissionsPage
        case .optimization: optimizationPage
        case .maintenance: maintenancePage
        case .uninstaller: uninstallerPage
        case .extensions: extensionsPage
        case .updates: updatesPage
        case .space: spacePage
        case .large, .duplicates, .shredder: filesPage
        }
    }

    private var scanPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                MetricCard(title: "发现空间", value: SpaceFormat.size(model.totalBytes), icon: "externaldrive")
                MetricCard(title: "已选择", value: SpaceFormat.size(model.selectedBytes), icon: "checkmark.circle")
                MetricCard(title: "扫描项目", value: "\(model.groups.flatMap(\.items).count)", icon: "doc.on.doc")
            }
            HStack {
                Button { model.scan(model.page) } label: {
                    Label(model.scanIsRunning ? "扫描中…" : "开始扫描", systemImage: "magnifyingglass")
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.scanIsRunning)
                if model.scanIsRunning {
                    ProgressView(value: model.scanProgress)
                        .frame(width: 100)
                    Button("取消") { model.cancelScan() }
                }
                Spacer()
                Button("全选") { model.setAllScanSelection(true) }
                    .disabled(model.groups.allSatisfy(\.items.isEmpty))
                Button("清空选择") { model.setAllScanSelection(false) }
                    .disabled(!model.groups.flatMap(\.items).contains(where: \.selected))
                Button(model.page == .trash ? "清空所选" : "清理所选") { model.requestCleanup(permanent: model.page == .trash) }
                    .buttonStyle(.bordered)
                    .disabled(!model.groups.flatMap(\.items).contains(where: \.selected) || model.scanIsRunning || model.cleanupInProgress)
            }
            if model.scanIsRunning { Text(model.scanProgressLabel).font(.caption).foregroundStyle(.secondary) }
            if !model.lastCleanupItems.isEmpty {
                DisclosureGroup("上次操作 · \(model.lastCleanupItems.count) 项") {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(model.lastCleanupItems) { item in
                            HStack { Text(item.category).foregroundStyle(.secondary); Text(item.name).lineLimit(1); Spacer(); Text(SpaceFormat.size(item.bytes)).monospacedDigit() }
                                .font(.caption)
                        }
                    }
                    .padding(.top, 8)
                }
                .card()
            }
            if model.page == .privacy { NoticeCard(text: "浏览器历史记录与 Cookie 被移走后可能无法恢复，网站可能要求重新登录。请先退出浏览器。", symbol: "exclamationmark.shield") }
            if model.page == .trash { NoticeCard(text: "废纸篓中的所选项目将永久删除。", symbol: "exclamationmark.triangle") }
            if !model.scanIssues.isEmpty {
                DisclosureGroup("未能扫描的目录 · \(model.scanIssues.count)") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(model.scanIssues) { issue in
                            Text("\(issue.path)：\(issue.message)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                    .padding(.top, 8)
                }
                .card()
            }
            if model.page == .overview && !model.smartChecks.isEmpty {
                Text("防护与性能检查").font(.headline)
                ForEach(model.smartChecks) { check in
                    HStack(spacing: 12) {
                        Image(systemName: check.symbol).foregroundStyle(.cyan).frame(width: 25)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(check.title).fontWeight(.medium)
                            Text(check.detail).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("查看") {
                            model.page = check.destination
                            loadIfNeeded(check.destination)
                        }
                    }
                    .card()
                }
            }
            ForEach(model.groups) { group in
                if !group.items.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: group.symbol).foregroundStyle(.cyan).frame(width: 25)
                            Text(group.title).font(.headline)
                            Spacer()
                            Text(SpaceFormat.size(group.bytes)).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                        }
                        Text(group.detail).font(.caption).foregroundStyle(.secondary)
                        ForEach(group.items) { item in
                            HStack(spacing: 10) {
                                Button { model.toggleItem(groupID: group.id, itemID: item.id) } label: {
                                    Image(systemName: item.selected ? "checkmark.square.fill" : "square")
                                        .foregroundStyle(item.selected ? .cyan : .secondary)
                                }.buttonStyle(.plain)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.name).lineLimit(1)
                                    Text(item.url.path).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                                }
                                Spacer()
                                Text(SpaceFormat.size(item.bytes)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 3)
                        }
                    }
                    .card()
                }
            }
            if !model.scanIsRunning && model.groups.allSatisfy(\.items.isEmpty) {
                EmptyState(text: "没有发现项目", symbol: "checkmark.circle")
            }
        }
    }

    private var malwarePage: some View {
        VStack(alignment: .leading, spacing: 16) {
            NoticeCard(text: "恶意软件检测需要可信的签名引擎。当前版本不会把可疑文件误报为已检测或已清理。", symbol: "shield.lefthalf.filled")
            let engine = model.clamAVPath != nil
            HStack {
                Image(systemName: engine ? "checkmark.shield" : "shield.slash")
                    .foregroundStyle(engine ? .green : .orange)
                VStack(alignment: .leading) {
                    Text(engine ? "检测到 ClamAV" : "未检测到病毒扫描引擎").font(.headline)
                    Text(engine ? "选择目录运行签名扫描，逐项核对结果。" : "安装 ClamAV 后即可在此扫描；当前可查看 XProtect 状态。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }.card()
            if engine {
                folderPicker
                HStack {
                    Button(model.malwareScanRunning ? "扫描中…" : "开始 ClamAV 扫描") { model.scanMalware() }
                        .buttonStyle(.borderedProminent).disabled(model.malwareScanRunning)
                    if model.malwareScanRunning { ProgressView().controlSize(.small) }
                    Spacer()
                    Button("移走所选") { model.requestMalwareCleanup() }
                        .disabled(!model.malwareItems.contains(where: \.selected))
                }
                if !model.malwareScanMessage.isEmpty { Text(model.malwareScanMessage).font(.caption).foregroundStyle(.secondary) }
                ForEach(model.malwareItems) { item in
                    HStack(spacing: 10) {
                        Button { model.toggleMalwareItem(item.id) } label: {
                            Image(systemName: item.selected ? "checkmark.square.fill" : "square")
                                .foregroundStyle(item.selected ? .cyan : .secondary)
                        }.buttonStyle(.plain)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.name).fontWeight(.medium)
                            Text(item.url.path).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        Text(item.note).font(.caption2).foregroundStyle(.orange)
                    }.card()
                }
            }
            if !model.xprotectStatus.isEmpty {
                Text("macOS XProtect").font(.headline)
                Text(model.xprotectStatus).font(.system(.caption, design: .monospaced)).textSelection(.enabled).card()
            }
            Button("刷新 XProtect 状态") { model.loadXProtect() }
            Button("打开 macOS 安全性设置") { openSettings("com.apple.preference.security") }
        }
    }

    private var wifiPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("此 Mac 保存的 Wi-Fi 网络").font(.headline)
                Spacer()
                Button("刷新") { model.loadWiFi() }
                Button("忘记所选") { model.requestForgetWiFi() }
                    .disabled(model.selectedWiFi.isEmpty)
            }
            if model.wifiNetworks.isEmpty { EmptyState(text: "未读取到已保存网络", symbol: "wifi.slash") }
            ForEach(model.wifiNetworks, id: \.self) { name in
                HStack {
                    Button { model.toggleWiFi(name) } label: {
                        Image(systemName: model.selectedWiFi.contains(name) ? "checkmark.square.fill" : "square")
                            .foregroundStyle(model.selectedWiFi.contains(name) ? .cyan : .secondary)
                    }.buttonStyle(.plain)
                    Image(systemName: "wifi").foregroundStyle(.cyan)
                    Text(name)
                    Spacer()
                }.card()
            }
            Button("管理已知网络") { openSettings("com.apple.wifi-settings-extension") }
        }
    }

    private var permissionsPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            NoticeCard(text: "下面只读显示当前用户的应用授权记录。授权开关由 macOS 系统设置管理。", symbol: "hand.raised")
            HStack {
                TextField("搜索应用或权限", text: $permissionSearch)
                    .textFieldStyle(.roundedBorder)
                Button("刷新") { model.loadPermissions() }
                Button("打开隐私设置") { openSettings("com.apple.preference.security?Privacy") }
            }
            if !model.permissionError.isEmpty { Text(model.permissionError).font(.caption).foregroundStyle(.secondary) }
            let filtered = model.permissionEntries.filter {
                permissionSearch.isEmpty || $0.client.localizedCaseInsensitiveContains(permissionSearch) || $0.serviceName.localizedCaseInsensitiveContains(permissionSearch)
            }
            ForEach(Array(Dictionary(grouping: filtered, by: \.client).keys).sorted(), id: \.self) { client in
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(client).font(.headline).lineLimit(1)
                        Spacer()
                        Button("在系统设置查看") { openSettings("com.apple.preference.security?Privacy") }
                    }
                    ForEach(filtered.filter { $0.client == client }) { entry in
                        HStack {
                            Text(entry.serviceName)
                            Spacer()
                            Text(entry.statusName)
                                .foregroundStyle(entry.authorization == 2 ? .green : .secondary)
                        }
                        .font(.caption)
                    }
                }
                .card()
            }
        }
    }

    private var optimizationPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            NoticeCard(text: "这里可以启用或停用当前用户的传统启动代理。现代登录项仍由系统设置管理。", symbol: "bolt")
            Button("打开登录项设置") { openSettings("com.apple.LoginItems-Settings.extension") }
                .buttonStyle(.borderedProminent)
            HStack { Text("当前用户的启动代理 · \(model.loginAgents.count)").font(.headline); Spacer(); Button("刷新") { model.loadLoginAgents() } }
            ForEach(model.loginAgents) { agent in
                HStack {
                    Image(systemName: "gearshape.2").foregroundStyle(.cyan)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(agent.url.lastPathComponent)
                        Text(agent.enabled ? "已启用" : "已停用").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("在 Finder 中显示") { NSWorkspace.shared.activateFileViewerSelecting([agent.url]) }
                    Button(agent.enabled ? "停用" : "启用") { model.requestToggleLoginAgent(agent) }
                }.card()
            }
        }
    }

    private var maintenancePage: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(MaintenanceAction.all) { action in
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(action.title).font(.headline)
                        Text(action.detail).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("运行") { model.runMaintenance(action) }
                }.card()
            }
            if !model.maintenanceOutput.isEmpty { Text(model.maintenanceOutput).font(.system(.caption, design: .monospaced)).textSelection(.enabled).card() }
        }
    }

    private var uninstallerPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text("已安装应用 · \(model.apps.count)").font(.headline); Spacer(); Button("刷新") { model.loadApps() } }
            ForEach(model.apps) { app in
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 14) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path)).resizable().frame(width: 34, height: 34)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(app.name).fontWeight(.medium)
                            Text(app.bundleID.isEmpty ? app.url.path : app.bundleID).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        Text(SpaceFormat.size(app.bytes)).font(.caption).foregroundStyle(.secondary)
                        Button("管理") { model.inspectApp(app) }
                    }
                    if model.selectedApp?.id == app.id {
                        if model.residualScanRunning { ProgressView("查找关联文件…") }
                        else {
                            HStack {
                                Text("关联文件 · \(model.appResiduals.count)").font(.subheadline.bold())
                                Spacer()
                                Button("选择缓存与偏好") { model.selectSafeAppResiduals() }
                                Button("重置所选") { model.requestResetSelectedResiduals(app) }
                                    .disabled(!model.appResiduals.contains(where: \.selected))
                                Button("卸载应用与所选") { model.requestFullUninstall(app) }
                            }
                            ForEach(model.appResiduals) { item in
                                HStack(spacing: 10) {
                                    Button { model.toggleAppResidual(item.id) } label: {
                                        Image(systemName: item.selected ? "checkmark.square.fill" : "square")
                                            .foregroundStyle(item.selected ? .cyan : .secondary)
                                    }.buttonStyle(.plain)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.url.lastPathComponent)
                                        Text(item.url.path).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                    Spacer()
                                    Text(SpaceFormat.size(item.bytes)).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }.card()
            }
        }
    }

    private var extensionsPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text("已发现的面板与插件 · \(model.extensions.count)").font(.headline); Spacer(); Button("刷新") { model.loadExtensions() } }
            ForEach(model.extensions) { item in
                HStack {
                    Image(systemName: "puzzlepiece.extension").foregroundStyle(.cyan)
                    VStack(alignment: .leading) { Text(item.url.lastPathComponent); Text(item.kind).font(.caption).foregroundStyle(.secondary) }
                    Spacer()
                    Button("显示") { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }
                    if item.url.path.hasPrefix(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library").path + "/") {
                        Button("移到废纸篓") { model.requestRemoveExtension(item) }
                    }
                }.card()
            }
            if model.extensions.isEmpty { EmptyState(text: "未发现传统面板或插件", symbol: "puzzlepiece.extension") }
            if !model.safariExtensions.isEmpty {
                Text("Safari 扩展").font(.headline)
                Text(model.safariExtensions).font(.system(.caption, design: .monospaced)).textSelection(.enabled).card()
            }
        }
    }

    private var updatesPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            NoticeCard(text: "App Store 更新由 macOS 管理。第三方应用需要各自的更新源，当前版本不会猜测可用更新。", symbol: "arrow.triangle.2.circlepath")
            Button("打开 App Store 更新") { NSWorkspace.shared.open(URL(string: "macappstore://showUpdatesPage")!) }.buttonStyle(.borderedProminent)
            Button("打开软件更新设置") { openSettings("com.apple.Software-Update-Settings.extension") }
        }
    }

    private var spacePage: some View {
        VStack(alignment: .leading, spacing: 16) {
            folderPicker
            Button("返回上一级") { model.fileRoot = model.fileRoot.deletingLastPathComponent() }
                .disabled(model.fileRoot.path == "/")
            Text("所选文件夹的空间分布").font(.headline)
            SpaceMap(root: model.fileRoot) { url in
                var isDirectory: ObjCBool = false
                if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
                    model.fileRoot = url
                } else if FileManager.default.fileExists(atPath: url.path) {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            }
                .frame(height: 320)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            Text("图块面积代表文件或文件夹的大小。点击文件夹可继续深入查看。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var filesPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            if model.page == .shredder {
                NoticeCard(text: "永久删除不会经过废纸篓。由于 APFS 快照和 SSD 的存储方式，无法保证数据被安全擦除。", symbol: "exclamationmark.triangle")
                Button("选择要永久删除的文件…") { pickFilesToShred() }.buttonStyle(.borderedProminent)
            } else {
                folderPicker
                HStack {
                    Button(model.fileScanRunning ? "分析中…" : "开始分析") { model.scanFiles(mode: model.page) }
                        .buttonStyle(.borderedProminent).disabled(model.fileScanRunning)
                    if model.fileScanRunning { ProgressView().controlSize(.small) }
                    if model.page == .large {
                        Picker("排序", selection: $model.fileSort) {
                            ForEach(FileSortMode.allCases, id: \.self) { mode in Text(mode.rawValue).tag(mode) }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 140)
                    }
                    Spacer()
                    Button(model.page == .duplicates ? "移走所选副本" : "移到废纸篓") { model.requestFileCleanup() }
                        .disabled(!model.fileItems.contains(where: \.selected) || model.fileCleanupRunning)
                }
                if model.page == .duplicates { NoticeCard(text: "按大小、首尾内容和完整 SHA-256 校验；同一 inode 的硬链接不会算作可回收副本。每组保留一个原件，所选副本会移到废纸篓。", symbol: "square.on.square") }
            }
            if model.page == .shredder && !model.fileItems.isEmpty {
                Button("永久删除所选") { model.requestFileCleanup(permanent: true) }.foregroundStyle(.red)
            }
            ForEach(model.displayedFileItems) { item in
                HStack(spacing: 10) {
                    Button { model.toggleFileItem(item.id) } label: {
                        Image(systemName: item.selected ? "checkmark.square.fill" : "square")
                            .foregroundStyle(item.selected ? .cyan : .secondary)
                    }.buttonStyle(.plain)
                        .disabled(model.page == .duplicates && item.note == "保留原件")
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.name).fontWeight(.medium)
                        Text(item.url.path).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    Text(item.note).font(.caption2).foregroundStyle(.secondary)
                    Text(SpaceFormat.size(item.bytes)).font(.caption.monospacedDigit())
                }.card()
            }
            if model.fileItems.isEmpty && !model.fileScanRunning { EmptyState(text: "请选择目录并开始分析", symbol: "folder") }
        }
    }

    private var folderPicker: some View {
        HStack {
            Image(systemName: "folder").foregroundStyle(.cyan)
            Text(model.fileRoot.path).lineLimit(1).font(.subheadline)
            Spacer()
            Button("更换目录…") {
                let panel = NSOpenPanel()
                panel.canChooseFiles = false
                panel.canChooseDirectories = true
                panel.allowsMultipleSelection = false
                if panel.runModal() == .OK, let url = panel.url {
                    model.fileRoot = url
                    model.clearFileResults(mode: model.page)
                }
            }
        }.card()
    }

    private func pickFilesToShred() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK {
            model.fileItems = panel.urls.map { ScanItem(url: $0, bytes: FileScanner.size(of: $0), category: "永久删除", selected: true) }
        }
    }

    private func loadIfNeeded(_ page: SidebarPage) {
        switch page {
        case .overview, .junk, .mail, .trash, .privacy: model.scan(page)
        case .wifi: model.loadWiFi()
        case .permissions: model.loadPermissions()
        case .optimization: model.loadLoginAgents()
        case .malware: model.loadXProtect()
        case .uninstaller: model.loadApps()
        case .extensions: model.loadExtensions()
        case .large, .duplicates, .shredder: model.clearFileResults(mode: page)
        default: break
        }
    }

    private func openSettings(_ pane: String) {
        guard let url = URL(string: "x-apple.systempreferences:\(pane)") else { return }
        NSWorkspace.shared.open(url)
    }

    private func subtitle(for page: SidebarPage) -> String {
        switch page {
        case .overview: "一眼了解可释放空间，逐项决定清理内容"
        case .junk: "查找 \(ScanCatalog.junkWithTemporaryScreenshots.count) 类缓存、日志和构建产物"
        case .mail: "查看 Mail 附件及 Outlook、Spark 邮件缓存"
        case .trash: "选择废纸篓中要永久删除的项目"
        case .malware: "检查安全引擎的可用状态"
        case .privacy: "管理浏览器历史记录与网站数据"
        case .wifi: "查看此 Mac 记住的无线网络"
        case .permissions: "查看当前用户的隐私授权记录"
        case .optimization: "查看开机启动项目与用户代理"
        case .maintenance: "运行常见的系统维护任务"
        case .uninstaller: "卸载应用，或将其重置为初始状态"
        case .extensions: "查看传统设置面板与插件"
        case .updates: "快速进入应用更新入口"
        case .space: "看清文件夹里的空间占用"
        case .large: "寻找体积大或长期未修改的文件"
        case .duplicates: "精确匹配内容相同的文件"
        case .shredder: "选择文件并永久删除"
        }
    }
}

private struct MetricCard: View {
    let title: String
    let value: String
    let icon: String
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Image(systemName: icon).foregroundStyle(.cyan); Text(title).font(.caption).foregroundStyle(.secondary); Spacer() }
            Text(value).font(.title2.bold()).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

private struct NoticeCard: View {
    let text: String
    let symbol: String
    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: symbol).foregroundStyle(.orange)
            Text(text).font(.subheadline).foregroundStyle(.secondary)
            Spacer()
        }
        .card()
    }
}

private struct EmptyState: View {
    let text: String
    let symbol: String
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 34)).foregroundStyle(.tertiary)
            Text(text).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(38)
    }
}

private extension View {
    func card() -> some View {
        self.padding(15)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
    }
}
