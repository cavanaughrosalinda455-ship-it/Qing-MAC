import Foundation

enum SpaceFormat {
    static func size(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

struct ScanItem: Identifiable, Hashable, Sendable {
    let id: String
    let url: URL
    let name: String
    let bytes: Int64
    let category: String
    let note: String
    let lastAccessed: Date?
    let contentDigest: String?
    var selected = true

    init(url: URL, bytes: Int64, category: String, note: String = "", lastAccessed: Date? = nil, contentDigest: String? = nil, selected: Bool = true) {
        self.id = url.path
        self.url = url
        self.name = url.lastPathComponent
        self.bytes = bytes
        self.category = category
        self.note = note
        self.lastAccessed = lastAccessed
        self.contentDigest = contentDigest
        self.selected = selected
    }
}

struct ScanGroup: Identifiable, Sendable {
    var id: String { title }
    let title: String
    let symbol: String
    let detail: String
    var items: [ScanItem]
    var bytes: Int64 { items.reduce(0) { $0 + $1.bytes } }
}

enum SidebarPage: String, CaseIterable, Identifiable {
    case overview = "智能扫描"
    case junk = "系统垃圾"
    case mail = "邮件附件"
    case trash = "废纸篓"
    case malware = "恶意软件清理"
    case privacy = "隐私清理"
    case wifi = "已保存的 Wi-Fi"
    case permissions = "权限总览"
    case optimization = "登录项优化"
    case maintenance = "系统维护"
    case uninstaller = "应用卸载器"
    case extensions = "扩展与插件"
    case updates = "应用更新"
    case space = "空间透视"
    case large = "大文件与旧文件"
    case duplicates = "重复文件"
    case shredder = "文件粉碎"

    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .overview: "sparkles"
        case .junk: "trash.slash"
        case .mail: "envelope"
        case .trash: "trash"
        case .malware: "shield.lefthalf.filled"
        case .privacy: "eye.slash"
        case .wifi: "wifi"
        case .permissions: "hand.raised"
        case .optimization: "bolt"
        case .maintenance: "wrench.adjustable"
        case .uninstaller: "app.badge"
        case .extensions: "puzzlepiece.extension"
        case .updates: "arrow.triangle.2.circlepath"
        case .space: "square.3.layers.3d"
        case .large: "doc.badge.clock"
        case .duplicates: "square.on.square"
        case .shredder: "delete.left"
        }
    }
}

enum SidebarSection: String, CaseIterable {
    case clean = "清理"
    case protect = "防护"
    case performance = "性能"
    case apps = "应用"
    case files = "文件"

    var pages: [SidebarPage] {
        switch self {
        case .clean: [.overview, .junk, .mail, .trash]
        case .protect: [.malware, .privacy, .wifi, .permissions]
        case .performance: [.optimization, .maintenance]
        case .apps: [.uninstaller, .extensions, .updates]
        case .files: [.space, .large, .duplicates, .shredder]
        }
    }
}
