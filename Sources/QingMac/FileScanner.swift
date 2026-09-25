import Foundation
import Darwin
import CryptoKit

struct ScanDefinition: Sendable {
    let title: String
    let symbol: String
    let detail: String
    let paths: [String]
    let minimumAge: TimeInterval
    let defaultSelected: Bool
    let validator: ScanValidator

    init(title: String, symbol: String, detail: String, paths: [String], minimumAge: TimeInterval = 0,
         defaultSelected: Bool = true, validator: ScanValidator = .all) {
        self.title = title
        self.symbol = symbol
        self.detail = detail
        self.paths = paths
        self.minimumAge = minimumAge
        self.defaultSelected = defaultSelected
        self.validator = validator
    }
}

enum ScanValidator: Sendable, Equatable {
    case all
    case invalidPropertyList
    case brokenLaunchAgent
}

struct ScanIssue: Identifiable, Sendable {
    var id: String { path }
    let path: String
    let message: String
}

struct ScanReport: Sendable {
    let groups: [ScanGroup]
    let issues: [ScanIssue]
}

enum ScanCatalog {
    static var junkWithTemporaryScreenshots: [ScanDefinition] {
        junk + [
            .init(title: "临时截图", symbol: "photo.on.rectangle", detail: "应用临时保存的截图；最近 15 分钟的文件暂不扫描",
                  paths: [FileManager.default.temporaryDirectory.appendingPathComponent("codex-clipboard-*.png").path],
                  minimumAge: 15 * 60)
        ]
    }

    static var trash: [ScanDefinition] {
        var definitions = [ScanDefinition(title: "本机废纸篓", symbol: "trash", detail: "删除后无法恢复", paths: ["~/.Trash"])]
        let volumes = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: [.volumeIsRemovableKey, .volumeIsEjectableKey], options: [.skipHiddenVolumes]) ?? []
        for volume in volumes where volume.path.hasPrefix("/Volumes/") {
            let path = volume.appendingPathComponent(".Trashes/\(getuid())").path
            definitions.append(.init(title: "\(volume.lastPathComponent) 废纸篓", symbol: "externaldrive", detail: "外置卷废纸篓；删除后无法恢复", paths: [path]))
        }
        return definitions
    }

    static let junk: [ScanDefinition] = [
        .init(title: "应用缓存", symbol: "shippingbox", detail: "应用生成的临时缓存", paths: ["~/Library/Caches"]),
        .init(title: "应用日志", symbol: "doc.text", detail: "应用运行日志", paths: ["~/Library/Logs"]),
        .init(title: "损坏的偏好设置", symbol: "slider.horizontal.3", detail: "无法解析的用户偏好文件", paths: ["~/Library/Preferences/*.plist", "~/Library/Preferences/ByHost/*.plist"], validator: .invalidPropertyList),
        .init(title: "损坏的登录项目", symbol: "bolt.slash", detail: "无效或指向不存在程序的用户启动代理", paths: ["~/Library/LaunchAgents/*.plist"], validator: .brokenLaunchAgent),
        .init(title: "iOS 设备备份", symbol: "iphone", detail: "可能包含唯一的手机备份；默认不选中", paths: ["~/Library/Application Support/MobileSync/Backup"], defaultSelected: false),
        .init(title: "诊断报告", symbol: "waveform.path.ecg", detail: "崩溃与诊断文件", paths: ["~/Library/Logs/DiagnosticReports"]),
        .init(title: "用户诊断报告", symbol: "stethoscope", detail: "系统生成的用户诊断文件", paths: ["~/Library/Logs/DiagnosticReports/Retired"]),
        .init(title: "快速查看缓存", symbol: "eye", detail: "Quick Look 缩略图缓存", paths: ["~/Library/Caches/com.apple.QuickLook.thumbnailcache"]),
        .init(title: "Safari 缓存", symbol: "safari", detail: "Safari 网页缓存", paths: ["~/Library/Caches/com.apple.Safari"]),
        .init(title: "Chrome 缓存", symbol: "globe", detail: "Chrome 网页缓存", paths: ["~/Library/Application Support/Google/Chrome/*/Cache", "~/Library/Application Support/Google/Chrome/*/Code Cache"]),
        .init(title: "Edge 缓存", symbol: "globe", detail: "Edge 网页缓存", paths: ["~/Library/Application Support/Microsoft Edge/*/Cache", "~/Library/Application Support/Microsoft Edge/*/Code Cache"]),
        .init(title: "Firefox 缓存", symbol: "globe", detail: "Firefox 网页缓存", paths: ["~/Library/Caches/Firefox"]),
        .init(title: "Xcode 派生数据", symbol: "hammer", detail: "可重新构建的编译产物", paths: ["~/Library/Developer/Xcode/DerivedData"]),
        .init(title: "Xcode 归档缓存", symbol: "archivebox", detail: "设备与归档缓存", paths: ["~/Library/Developer/Xcode/iOS DeviceSupport"]),
        .init(title: "VS Code 缓存", symbol: "chevron.left.forwardslash.chevron.right", detail: "编辑器可重建的缓存", paths: ["~/Library/Application Support/Code/Cache", "~/Library/Application Support/Code/CachedData"]),
        .init(title: "JetBrains 缓存", symbol: "chevron.left.forwardslash.chevron.right", detail: "IDE 可重建的缓存", paths: ["~/Library/Caches/JetBrains"]),
        .init(title: "Gradle 缓存", symbol: "hammer", detail: "构建依赖缓存", paths: ["~/.gradle/caches"]),
        .init(title: "Cargo 下载缓存", symbol: "shippingbox", detail: "Rust 包下载缓存", paths: ["~/.cargo/registry/cache"]),
        .init(title: "uv 缓存", symbol: "shippingbox", detail: "Python 包下载缓存", paths: ["~/.cache/uv"]),
        .init(title: "Swift 构建缓存", symbol: "swift", detail: "Swift Package 构建产物", paths: ["~/.swiftpm/cache"]),
        .init(title: "Homebrew 缓存", symbol: "terminal", detail: "下载的软件包缓存", paths: ["~/Library/Caches/Homebrew"]),
        .init(title: "npm 缓存", symbol: "curlybraces", detail: "npm 下载缓存", paths: ["~/.npm/_cacache"]),
        .init(title: "pnpm 缓存", symbol: "curlybraces", detail: "pnpm 存储缓存", paths: ["~/Library/pnpm/store"]),
        .init(title: "pip 缓存", symbol: "chevron.left.forwardslash.chevron.right", detail: "Python 包下载缓存", paths: ["~/Library/Caches/pip"]),
        .init(title: "临时下载", symbol: "arrow.down.circle", detail: "不完整的浏览器下载", paths: ["~/Downloads/*.download", "~/Downloads/*.crdownload"]),
        .init(title: "废旧安装包", symbol: "opticaldisc", detail: "下载目录中的安装镜像与安装包", paths: ["~/Downloads/*.dmg", "~/Downloads/*.pkg"])
    ]

    static let mail: [ScanDefinition] = [
        .init(title: "Apple Mail 附件", symbol: "paperclip", detail: "Mail 下载的附件；删除后可能需要重新下载", paths: ["~/Library/Containers/com.apple.mail/Data/Library/Mail Downloads", "~/Library/Mail Downloads"]),
        .init(title: "Outlook 邮件缓存", symbol: "paperclip", detail: "Outlook 可重新下载的邮件缓存", paths: ["~/Library/Containers/com.microsoft.Outlook/Data/Library/Caches"]),
        .init(title: "Spark 邮件缓存", symbol: "paperclip", detail: "Spark 可重新下载的邮件缓存", paths: ["~/Library/Containers/com.readdle.SparkDesktop/Data/Library/Caches", "~/Library/Containers/com.readdle.smartemail-Mac/Data/Library/Caches"])
    ]

    static let privacy: [ScanDefinition] = [
        .init(title: "Safari 历史记录", symbol: "safari", detail: "清理后无法恢复浏览历史", paths: ["~/Library/Safari/History.db"]),
        .init(title: "Chrome 历史记录", symbol: "globe", detail: "清理后无法恢复浏览历史", paths: ["~/Library/Application Support/Google/Chrome/*/History"]),
        .init(title: "Chrome 网站数据", symbol: "lock", detail: "清理后网站可能需要重新登录", paths: ["~/Library/Application Support/Google/Chrome/*/Network/Cookies"]),
        .init(title: "Edge 历史记录", symbol: "globe", detail: "清理后无法恢复浏览历史", paths: ["~/Library/Application Support/Microsoft Edge/*/History"]),
        .init(title: "Edge 网站数据", symbol: "lock", detail: "清理后网站可能需要重新登录", paths: ["~/Library/Application Support/Microsoft Edge/*/Network/Cookies"]),
        .init(title: "Firefox 历史记录", symbol: "globe", detail: "清理后无法恢复浏览历史", paths: ["~/Library/Application Support/Firefox/Profiles/*/places.sqlite"]),
        .init(title: "Firefox 网站数据", symbol: "lock", detail: "清理后网站可能需要重新登录", paths: ["~/Library/Application Support/Firefox/Profiles/*/cookies.sqlite"])
    ]
}

enum FileScanner {
    static let fm = FileManager.default

    static func expanded(_ path: String) -> URL {
        URL(fileURLWithPath: NSString(string: path).expandingTildeInPath)
    }

    static func scan(_ definitions: [ScanDefinition]) -> [ScanGroup] {
        scanDetailed(definitions).groups
    }

    static func scanDetailed(_ definitions: [ScanDefinition], onProgress: (@Sendable (Int, Int, String) -> Void)? = nil) -> ScanReport {
        var seen = Set<String>()
        var issues: [ScanIssue] = []
        let namedRoots = Set(definitions.flatMap(\.paths).filter { !$0.contains("*") }.map { expanded($0).path })
        var groups: [ScanGroup] = []
        for (index, definition) in definitions.enumerated() {
            if Task<Never, Never>.isCancelled { break }
            var items: [ScanItem] = []
            for pattern in definition.paths {
                if Task<Never, Never>.isCancelled { break }
                let root = expanded(pattern).deletingLastPathComponent()
                if pattern.contains("*"), fm.fileExists(atPath: root.path), !fm.isReadableFile(atPath: root.path) {
                    issues.append(ScanIssue(path: root.path, message: "没有读取权限"))
                    continue
                }
                let paths = expandGlob(pattern)
                for url in paths {
                    if Task<Never, Never>.isCancelled { break }
                    guard !seen.contains(url.path) else { continue }
                    guard fm.fileExists(atPath: url.path) else {
                        do { _ = try fm.attributesOfItem(atPath: url.path) }
                        catch let error as NSError where error.code != NSFileNoSuchFileError {
                            issues.append(ScanIssue(path: url.path, message: error.localizedDescription))
                        } catch { }
                        continue
                    }
                    guard fm.isReadableFile(atPath: url.path) else {
                        issues.append(ScanIssue(path: url.path, message: "没有读取权限"))
                        continue
                    }
                    if definition.minimumAge > 0 {
                        guard let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                              Date().timeIntervalSince(modified) >= definition.minimumAge else { continue }
                    }
                    if !pattern.contains("*") && !isSingleFile(url) {
                        let contents: [URL]
                        do { contents = try fm.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsPackageDescendants]) }
                        catch {
                            issues.append(ScanIssue(path: url.path, message: error.localizedDescription))
                            continue
                        }
                        for child in contents where !seen.contains(child.path) && !namedRoots.contains(child.path) {
                            if Task<Never, Never>.isCancelled { break }
                            seen.insert(child.path)
                            if !fm.isReadableFile(atPath: child.path) {
                                issues.append(ScanIssue(path: child.path, message: "没有读取权限"))
                                continue
                            }
                            guard matchesValidator(child, definition.validator) else { continue }
                            let bytes = size(of: child)
                            items.append(ScanItem(url: child, bytes: bytes, category: definition.title, note: definition.detail, selected: definition.defaultSelected))
                        }
                    } else {
                        seen.insert(url.path)
                        guard matchesValidator(url, definition.validator) else { continue }
                        let bytes = size(of: url)
                        items.append(ScanItem(url: url, bytes: bytes, category: definition.title, note: definition.detail, selected: definition.defaultSelected))
                    }
                }
            }
            groups.append(ScanGroup(title: definition.title, symbol: definition.symbol, detail: definition.detail, items: items))
            onProgress?(index + 1, definitions.count, definition.title)
        }
        return ScanReport(groups: groups, issues: Array(Dictionary(issues.map { ($0.path, $0) }, uniquingKeysWith: { old, _ in old }).values).sorted { $0.path < $1.path })
    }

    static func isSingleFile(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
    }

    private static func matchesValidator(_ url: URL, _ validator: ScanValidator) -> Bool {
        guard validator != .all else { return true }
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 10_000_000,
              let data = try? Data(contentsOf: url) else { return false }
        let plist: Any
        do { plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) }
        catch { return true }
        guard validator == .brokenLaunchAgent else { return false }
        guard let dictionary = plist as? [String: Any] else { return true }
        let program = (dictionary["Program"] as? String) ?? (dictionary["ProgramArguments"] as? [String])?.first
        guard let program, !program.isEmpty else { return true }
        return program.hasPrefix("/") && !fm.fileExists(atPath: program)
    }

    static func expandGlob(_ pattern: String) -> [URL] {
        guard pattern.contains("*") else { return [expanded(pattern)] }
        let components = expanded(pattern).path.split(separator: "/").map(String.init)
        var candidates = [URL(fileURLWithPath: "/", isDirectory: true)]
        for component in components {
            if component.contains("*") {
                let parts = component.split(separator: "*", omittingEmptySubsequences: false)
                let expression = "^" + parts.map { NSRegularExpression.escapedPattern(for: String($0)) }.joined(separator: ".*") + "$"
                guard let regex = try? NSRegularExpression(pattern: expression) else { return [] }
                candidates = candidates.flatMap { parent in
                    let children = (try? fm.contentsOfDirectory(at: parent, includingPropertiesForKeys: nil)) ?? []
                    return children.filter { child in
                        let name = child.lastPathComponent
                        return regex.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)) != nil
                    }
                }
            } else {
                candidates = candidates.map { $0.appendingPathComponent(component) }
            }
            if candidates.isEmpty { break }
        }
        return candidates.sorted { $0.path < $1.path }
    }

    static func size(of url: URL) -> Int64 {
        guard let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey, .fileSizeKey]), values.isSymbolicLink != true else { return 0 }
        if values.isRegularFile == true { return Int64(values.fileSize ?? 0) }
        guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey], options: [.skipsPackageDescendants]) else { return 0 }
        var total: Int64 = 0
        for case let child as URL in enumerator {
            if Task<Never, Never>.isCancelled { break }
            if let data = try? child.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]), data.isSymbolicLink != true, data.isRegularFile == true {
                total += Int64(data.fileSize ?? 0)
            }
        }
        return total
    }

    static func files(in root: URL) -> [URL] {
        guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey], options: [.skipsPackageDescendants, .skipsHiddenFiles]) else { return [] }
        return enumerator.compactMap { item in
            guard let url = item as? URL, let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]), values.isRegularFile == true, values.isSymbolicLink != true else { return nil }
            return url
        }
    }

    static func largeOrOld(in root: URL) -> [ScanItem] {
        let cutoff = Date().addingTimeInterval(-365 * 24 * 3600)
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        return files(in: root).compactMap { url in
            guard let data = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .contentAccessDateKey]) else { return nil }
            let bytes = Int64(data.fileSize ?? 0)
            let old = (data.contentModificationDate ?? Date()) < cutoff
            guard bytes >= 50_000_000 || (old && bytes >= 10_000_000) else { return nil }
            let access = data.contentAccessDate
            let accessText = access.map { "最近访问 \(dateFormatter.string(from: $0))" } ?? "最近访问未知"
            let label = old ? "超过一年未修改" : "大于 50 MB"
            return ScanItem(url: url, bytes: bytes, category: old ? "旧文件" : "大文件", note: "\(label) · \(accessText)", lastAccessed: access, selected: false)
        }.sorted { $0.bytes > $1.bytes }
    }

    static func duplicates(in root: URL) -> [ScanItem] {
        let candidates = files(in: root).compactMap { url -> (URL, Int64, FileIdentity)? in
            guard let value = try? url.resourceValues(forKeys: [.fileSizeKey]), let size = value.fileSize, size > 0 else { return nil }
            guard let identity = identity(of: url) else { return nil }
            return (url, Int64(size), identity)
        }
        let bySize = Dictionary(grouping: candidates, by: { $0.1 })
        var items: [ScanItem] = []
        for (bytes, sameSize) in bySize where sameSize.count > 1 {
            var byPartialHash: [String: [(URL, FileIdentity)]] = [:]
            for (url, _, identity) in sameSize {
                if let digest = partialSHA256(url, bytes: bytes) { byPartialHash[digest, default: []].append((url, identity)) }
            }
            for (_, possibleCopies) in byPartialHash where possibleCopies.count > 1 {
                var byFullHash: [String: [(URL, FileIdentity)]] = [:]
                for (url, identity) in possibleCopies {
                    if let digest = sha256(url) { byFullHash[digest, default: []].append((url, identity)) }
                }
                for (digest, exactCopies) in byFullHash where exactCopies.count > 1 {
                    var seenIdentities = Set<FileIdentity>()
                    let sorted = exactCopies.sorted { $0.0.path < $1.0.path }
                        .filter { seenIdentities.insert($0.1).inserted }
                    guard sorted.count > 1 else { continue }
                    for (index, pair) in sorted.enumerated() {
                        items.append(ScanItem(url: pair.0, bytes: bytes, category: "重复文件", note: index == 0 ? "保留原件" : "内容完全相同", contentDigest: digest, selected: index != 0))
                    }
                }
            }
        }
        return items.sorted { $0.name < $1.name }
    }

    private struct FileIdentity: Hashable {
        let device: dev_t
        let inode: ino_t
    }

    private static func identity(of url: URL) -> FileIdentity? {
        var data = stat()
        let result = url.withUnsafeFileSystemRepresentation { path in
            path.map { lstat($0, &data) } ?? -1
        }
        guard result == 0 else { return nil }
        return FileIdentity(device: data.st_dev, inode: data.st_ino)
    }

    private static func partialSHA256(_ url: URL, bytes: Int64) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        do {
            let first = try handle.read(upToCount: 65_536) ?? Data()
            hasher.update(data: first)
            if bytes > 65_536 {
                try handle.seek(toOffset: UInt64(max(0, bytes - 65_536)))
                hasher.update(data: try handle.read(upToCount: 65_536) ?? Data())
            }
            return hasher.finalize().map { String(format: "%02x", $0) }.joined()
        } catch { return nil }
    }

    static func isStillDuplicate(_ item: ScanItem, keeper: URL) -> Bool {
        guard let expected = item.contentDigest,
              item.url != keeper,
              sha256(item.url) == expected,
              sha256(keeper) == expected else { return false }
        return true
    }

    static func sha256(_ url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        do {
            while true {
                let data = try handle.read(upToCount: 1024 * 1024) ?? Data()
                if data.isEmpty { break }
                hasher.update(data: data)
            }
            return hasher.finalize().map { String(format: "%02x", $0) }.joined()
        } catch { return nil }
    }
}
