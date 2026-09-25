import AppKit
import SwiftUI
import SystemConfiguration
import Darwin

struct SpaceEntry: Identifiable, Sendable {
    var id: String { url.path }
    let url: URL
    let bytes: Int64
}

struct SpaceMap: View {
    let root: URL
    let onSelect: (URL) -> Void
    @State private var entries: [SpaceEntry] = []
    @State private var busy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if busy { ProgressView("正在分析空间…").frame(maxWidth: .infinity, maxHeight: .infinity) }
            else if entries.isEmpty { ContentUnavailableView("目录为空或无法读取", systemImage: "folder") }
            else {
                GeometryReader { geometry in
                    Canvas { context, _ in
                        for (index, part) in layout(in: CGRect(origin: .zero, size: geometry.size)).enumerated() {
                            let inset = part.1.insetBy(dx: 2, dy: 2)
                            context.fill(Path(roundedRect: inset, cornerRadius: 8), with: .color(color(index)))
                            if inset.width > 90 && inset.height > 35 {
                                let name = Text(part.0.url.lastPathComponent).font(.caption.bold()).foregroundColor(.white)
                                let size = Text(SpaceFormat.size(part.0.bytes)).font(.caption2).foregroundColor(.white.opacity(0.8))
                                context.draw(name, in: inset.insetBy(dx: 9, dy: 6))
                                if inset.height > 65 { context.draw(size, at: CGPoint(x: inset.minX + 10, y: inset.maxY - 16), anchor: .leading) }
                            }
                        }
                    }
                    .contentShape(Rectangle())
                    .gesture(SpatialTapGesture().onEnded { value in
                        if let entry = layout(in: CGRect(origin: .zero, size: geometry.size))
                            .first(where: { $0.1.contains(value.location) })?.0 {
                            onSelect(entry.url)
                        }
                    })
                }
            }
        }
        .task(id: root) {
            busy = true
            entries = await Task.detached(priority: .userInitiated) { () -> [SpaceEntry] in
                let children = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
                let sorted = children.map { SpaceEntry(url: $0, bytes: FileScanner.size(of: $0)) }
                    .filter { $0.bytes > 0 }
                    .sorted { $0.bytes > $1.bytes }
                guard sorted.count > 40 else { return sorted }
                let visible = Array(sorted.prefix(39))
                let other = sorted.dropFirst(39).reduce(Int64(0)) { $0 + $1.bytes }
                return visible + [SpaceEntry(url: root.appendingPathComponent("其他项目"), bytes: other)]
            }.value
            busy = false
        }
    }

    private func layout(in rect: CGRect) -> [(SpaceEntry, CGRect)] {
        var output: [(SpaceEntry, CGRect)] = []
        func split(_ items: ArraySlice<SpaceEntry>, _ frame: CGRect, _ horizontal: Bool) {
            guard !items.isEmpty else { return }
            if items.count == 1 { output.append((items.first!, frame)); return }
            let total = items.reduce(Int64(0)) { $0 + $1.bytes }
            let half = total / 2
            var partial: Int64 = 0
            var count = 0
            for item in items {
                if partial >= half && count > 0 { break }
                partial += item.bytes
                count += 1
            }
            count = min(count, items.count - 1)
            let first = items.prefix(count)
            let leftTotal = first.reduce(Int64(0)) { $0 + $1.bytes }
            let fraction = CGFloat(leftTotal) / CGFloat(max(total, 1))
            if horizontal {
                let width = frame.width * fraction
                split(first, CGRect(x: frame.minX, y: frame.minY, width: width, height: frame.height), false)
                split(items.dropFirst(count), CGRect(x: frame.minX + width, y: frame.minY, width: frame.width - width, height: frame.height), false)
            } else {
                let height = frame.height * fraction
                split(first, CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: height), true)
                split(items.dropFirst(count), CGRect(x: frame.minX, y: frame.minY + height, width: frame.width, height: frame.height - height), true)
            }
        }
        split(entries[...], rect, rect.width >= rect.height)
        return output
    }

    private func color(_ index: Int) -> Color {
        let palette: [Color] = [.cyan, .blue, .indigo, .teal, .purple, .mint, .orange]
        return palette[index % palette.count].opacity(0.72)
    }
}

struct MenuMetrics: Sendable {
    let cpu: String
    let memory: String
    let disk: String
    let battery: String
    let uptime: String
    let swap: String
    let advice: String

    static func snapshot() -> MenuMetrics {
        let cpuOutput = Shell.run("/usr/bin/top", ["-l", "1", "-n", "0"])
        let cpuLine = cpuOutput.components(separatedBy: .newlines).first { $0.contains("CPU usage:") } ?? ""
        let cpuPercent = MetricsFormatter.cpuUsagePercent(from: cpuLine)
        let cpu = cpuPercent.map { "\(Int($0.rounded()))%" } ?? "不可用"
        let vm = Shell.run("/usr/bin/vm_stat", [])
        func pages(_ key: String) -> Double {
            guard let line = vm.components(separatedBy: .newlines).first(where: { $0.hasPrefix(key) }) else { return 0 }
            return Double(line.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()) ?? 0
        }
        let usedMemory = (pages("Pages active:") + pages("Pages wired down:") + pages("Pages occupied by compressor:")) * 16384
        let totalMemory = Double(ProcessInfo.processInfo.physicalMemory)
        let memoryPercent = totalMemory > 0 ? min(100, max(0, Int(usedMemory / totalMemory * 100))) : 0
        let diskValues = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey])
        let free = Int64(diskValues?.volumeAvailableCapacityForImportantUsage ?? 0)
        let disk = "\(SpaceFormat.size(free)) 可用"
        let batteryLine = Shell.run("/usr/bin/pmset", ["-g", "batt"]).components(separatedBy: .newlines).first { $0.contains("%") } ?? ""
        let battery = MetricsFormatter.battery(from: batteryLine)
        let uptimeHours = Int(ProcessInfo.processInfo.systemUptime / 3600)
        let swapOutput = Shell.run("/usr/sbin/sysctl", ["-n", "vm.swapusage"])
        let swap = MetricsFormatter.swapUsed(from: swapOutput)
        let advice: String
        if free < 20_000_000_000 { advice = "磁盘可用空间偏低，建议扫描大文件。" }
        else if memoryPercent >= 85 { advice = "内存使用较高，建议关闭暂时不用的应用。" }
        else { advice = "系统状态正常。可定期检查缓存和废纸篓。" }
        return MenuMetrics(cpu: cpu, memory: "\(memoryPercent)% · 已用 \(SpaceFormat.size(Int64(usedMemory)))",
                           disk: disk, battery: battery,
                           uptime: "\(uptimeHours / 24) 天 \(uptimeHours % 24) 小时", swap: swap, advice: advice)
    }
}

struct NetworkSample: Sendable {
    let interface: String
    let received: UInt64
    let sent: UInt64
    let time: TimeInterval
}

struct NetworkCounters: Sendable {
    let interface: String
    let received: UInt64
    let sent: UInt64
    let isUp: Bool
}

enum NetworkTraffic {
    static func readSample() -> NetworkSample? {
        guard let counters = readCounters() else { return nil }
        return select(counters, preferredInterface: primaryInterface(), time: ProcessInfo.processInfo.systemUptime)
    }

    private static func readCounters() -> [NetworkCounters]? {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        for _ in 0..<3 {
            var required = 0
            guard sysctl(&mib, u_int(mib.count), nil, &required, nil, 0) == 0,
                  required > 0, required < 4_000_000 else { return nil }
            var data = Data(count: required)
            var actual = required
            let result = data.withUnsafeMutableBytes { bytes in
                sysctl(&mib, u_int(mib.count), bytes.baseAddress, &actual, nil, 0)
            }
            if result == 0 {
                data.count = actual
                return decode(data) { index in
                    var name = [CChar](repeating: 0, count: Int(IF_NAMESIZE))
                    let found = name.withUnsafeMutableBufferPointer { buffer in
                        if_indextoname(index, buffer.baseAddress) != nil
                    }
                    return found ? String(cString: name) : nil
                }
            }
            if errno != ENOMEM { return nil }
        }
        return nil
    }

    static func decode(_ data: Data, nameForIndex: (UInt32) -> String?) -> [NetworkCounters] {
        data.withUnsafeBytes { bytes in
            var counters: [NetworkCounters] = []
            var offset = 0
            while offset + MemoryLayout<UInt16>.size <= bytes.count {
                let messageLength = Int(bytes.loadUnaligned(fromByteOffset: offset, as: UInt16.self))
                guard messageLength >= 4, messageLength <= bytes.count - offset else { break }
                if bytes[offset + 3] == UInt8(RTM_IFINFO2),
                   messageLength >= MemoryLayout<if_msghdr2>.size {
                    let message = bytes.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                    if let name = nameForIndex(UInt32(message.ifm_index)) {
                        counters.append(NetworkCounters(interface: name,
                                                        received: message.ifm_data.ifi_ibytes,
                                                        sent: message.ifm_data.ifi_obytes,
                                                        isUp: message.ifm_flags & IFF_UP != 0))
                    }
                }
                offset += messageLength
            }
            return counters
        }
    }

    static func select(_ counters: [NetworkCounters], preferredInterface: String?, time: TimeInterval) -> NetworkSample? {
        let available = counters.filter { $0.isUp && $0.interface != "lo0" }
        let primary = preferredInterface.flatMap { name in available.first { $0.interface == name } }
        let fallback = available.first { $0.interface == "en0" }
            ?? available.first { $0.interface.hasPrefix("en") }
            ?? available.first
        guard let chosen = primary ?? fallback else { return nil }
        return NetworkSample(interface: chosen.interface, received: chosen.received, sent: chosen.sent, time: time)
    }

    static func rates(current: NetworkSample, previous: NetworkSample) -> (received: Double, sent: Double)? {
        let interval = current.time - previous.time
        guard current.interface == previous.interface, interval > 0,
              current.received >= previous.received, current.sent >= previous.sent else { return nil }
        return (Double(current.received - previous.received) / interval,
                Double(current.sent - previous.sent) / interval)
    }

    private static func primaryInterface() -> String? {
        let key = "State:/Network/Global/IPv4" as CFString
        let state = SCDynamicStoreCopyValue(nil, key) as? [String: Any]
        return state?["PrimaryInterface"] as? String
    }
}

enum MetricsFormatter {
    static func cpuUsagePercent(from line: String) -> Double? {
        guard let idle = firstMatch(#"([0-9]+(?:\.[0-9]+)?)%\s*idle"#, in: line).flatMap(Double.init) else { return nil }
        return min(100, max(0, 100 - idle))
    }

    static func battery(from line: String) -> String {
        guard let percent = firstMatch(#"([0-9]{1,3})%"#, in: line).flatMap(Int.init) else { return "不可用" }
        if line.contains("AC attached") {
            return "\(percent)% · \(line.contains("not charging") ? "已接电源" : "充电中")"
        }
        return "\(percent)%"
    }

    static func megabytes(_ bytes: Int64) -> String {
        let value = Int64((Double(bytes) / 1_000_000).rounded())
        return NumberFormatter.localizedString(from: NSNumber(value: value), number: .decimal) + " MB"
    }

    static func megabytesPerSecond(_ bytesPerSecond: Double) -> String {
        let amount = bytesPerSecond / 1_000_000
        if amount == 0 { return "0 MB/s" }
        return String(format: amount < 0.01 ? "%.3f MB/s" : "%.2f MB/s", amount)
    }

    static func swapUsed(from output: String) -> String {
        guard let number = firstMatch(#"used\s*=\s*([0-9.]+)"#, in: output).flatMap(Double.init),
              let unit = firstMatch(#"used\s*=\s*[0-9.]+([KMGT])"#, in: output) else { return "不可用" }
        if number == 0 { return "未使用" }
        let multiplier: Double
        switch unit {
        case "K": multiplier = 1_024
        case "M": multiplier = 1_048_576
        case "G": multiplier = 1_073_741_824
        default: multiplier = 1_099_511_627_776
        }
        let bytes = number * multiplier
        if bytes >= 1_000_000_000 { return String(format: "已用 %.1f GB", bytes / 1_000_000_000) }
        return String(format: "已用 %.0f MB", bytes / 1_000_000)
    }

    private static func firstMatch(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }
}

struct MenuMetricsView: View {
    @State private var metrics: MenuMetrics?
    @State private var lastNetworkSample: NetworkSample?
    @State private var networkReceived = "测量中…"
    @State private var networkSent = "测量中…"

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Image(systemName: "sparkles.rectangle.stack").foregroundStyle(.cyan)
                Text("清清 Mac").font(.headline)
                Spacer()
                Button { Task { await refresh() } } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.plain)
                    .help("网络每秒更新，其余状态每 15 秒更新；点击立即刷新")
            }
            Divider()
            if let metrics {
                metric("CPU 使用率", metrics.cpu, "cpu")
                    .help("当前处理器的总使用率。数值越低，通常表示越空闲。")
                metric("内存", metrics.memory, "memorychip")
                metric("磁盘", metrics.disk, "internaldrive")
                metric("电池", metrics.battery, "battery.100percent")
                Divider()
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "network").frame(width: 20).foregroundStyle(.cyan)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("网络流量")
                        Text("实时速度").font(.caption2).foregroundStyle(.tertiary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 3) {
                        Text("接收 \(networkReceived)")
                        Text("发送 \(networkSent)")
                    }
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
                metric("运行时间", metrics.uptime, "clock")
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "externaldrive").frame(width: 20).foregroundStyle(.cyan)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("临时内存")
                        Text("内存不足时借用磁盘").font(.caption2).foregroundStyle(.tertiary)
                    }
                    Spacer()
                    Text(metrics.swap).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                Divider()
                Label(metrics.advice, systemImage: "lightbulb").font(.caption).fixedSize(horizontal: false, vertical: true)
            } else { ProgressView("读取系统状态…") }
        }
        .padding(16)
        .frame(width: 300)
        .task {
            await refresh()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                if Task.isCancelled { break }
                await refresh()
            }
        }
        .task {
            while !Task.isCancelled {
                let current = await Task.detached(priority: .utility) { NetworkTraffic.readSample() }.value
                if let current {
                    if let previous = lastNetworkSample,
                       let speed = NetworkTraffic.rates(current: current, previous: previous) {
                        networkReceived = MetricsFormatter.megabytesPerSecond(speed.received)
                        networkSent = MetricsFormatter.megabytesPerSecond(speed.sent)
                    } else {
                        networkReceived = "测量中…"
                        networkSent = "测量中…"
                    }
                    lastNetworkSample = current
                } else {
                    networkReceived = "不可用"
                    networkSent = "不可用"
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func metric(_ name: String, _ value: String, _ symbol: String) -> some View {
        HStack { Image(systemName: symbol).frame(width: 20).foregroundStyle(.cyan); Text(name); Spacer(); Text(value).font(.caption.monospacedDigit()).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.85) }
    }

    private func refresh() async {
        metrics = await Task.detached(priority: .utility) { MenuMetrics.snapshot() }.value
    }
}
