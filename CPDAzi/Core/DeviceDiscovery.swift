import Foundation
import Network
import Combine

/// 设备发现 —— 对应 Android com.z6.fusion.DeviceScanner / DeviceFinder
/// iOS 无法读取 /proc/net/arp，改为按本机网段并发探测 :7002/stat
final class DeviceDiscovery: ObservableObject {

    @Published private(set) var found: [String] = []
    @Published private(set) var scanned = 0
    @Published private(set) var total = 0
    @Published private(set) var isScanning = false
    @Published private(set) var localPrefix: String = ""

    private var task: Task<Void, Never>?

    /// 本机 IPv4 前缀，如 "192.168.16."
    func currentSubnetPrefix() -> String {
        guard let ip = Self.wifiAddress() else { return "" }
        let parts = ip.split(separator: ".")
        guard parts.count == 4 else { return "" }
        return "\(parts[0]).\(parts[1]).\(parts[2])."
    }

    static func wifiAddress() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }
        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let ifa = ptr.pointee
            guard let addr = ifa.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) else { continue }
            let name = String(cString: ifa.ifa_name)
            guard name == "en0" else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(addr, socklen_t(addr.pointee.sa_len),
                           &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                address = String(cString: host)
            }
        }
        return address
    }

    func cancel() {
        task?.cancel()
        task = nil
        isScanning = false
    }

    /// 纯 async 并发扫描：不使用阻塞等待，避免线程池饥饿
    func scan(port: UInt16 = UInt16(FusionConfig.statPort), timeout: TimeInterval = 15) {
        guard !isScanning else { return }
        let prefix = currentSubnetPrefix()
        guard !prefix.isEmpty else { return }

        isScanning = true
        localPrefix = prefix
        found = []
        scanned = 0
        total = 254

        task = Task { [weak self] in
            guard let self else { return }
            let deadline = Date().addingTimeInterval(timeout)
            var hits: [String] = []

            // 分批：每批 32 个并发，批与批之间串行，避免 254 个 socket 同时打
            var batchStart = 1
            while batchStart <= 254 {
                if Task.isCancelled { break }
                if Date() >= deadline { break }
                let batchEnd = min(batchStart + 31, 254)
                let batch = Array(batchStart...batchEnd)
                batchStart = batchEnd + 1

                await withTaskGroup(of: (String, Bool).self) { group in
                    for i in batch {
                        group.addTask {
                            (("\(prefix)\(i)"), await Self.probeAsync(ip: "\(prefix)\(i)", port: port))
                        }
                    }
                    for await (ip, ok) in group {
                        if ok { hits.append(ip) }
                        await self.bumpProgress(hits)
                    }
                }
            }

            let sorted = hits.sorted { Self.ipOrder($0) < Self.ipOrder($1) }
            let cancelled = Task.isCancelled
            await MainActor.run {
                self.found = sorted
                self.isScanning = false
                if !cancelled { self.total = self.scanned }
            }
        }
    }

    @MainActor
    private func bumpProgress(_ hits: [String]) {
        scanned += 1
        if !hits.isEmpty {
            found = hits.sorted { Self.ipOrder($0) < Self.ipOrder($1) }
        }
    }

    static func ipOrder(_ ip: String) -> Int {
        Int(ip.split(separator: ".").last ?? "0") ?? 0
    }

    /// 非阻塞探测；与 Android DeviceScanner.probe 判定条件一致
    static func probeAsync(ip: String, port: UInt16) async -> Bool {
        guard let url = URL(string: "http://\(ip):\(port)/stat") else { return false }
        var req = URLRequest(url: url)
        req.timeoutInterval = 0.7
        req.cachePolicy = .reloadIgnoringLocalCacheData
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let h = resp as? HTTPURLResponse, h.statusCode == 200 else { return false }
            let s = String(decoding: data, as: UTF8.self)
            return s.contains("seq=") || s.contains("fps=") || s.contains("out=")
        } catch {
            return false
        }
    }
}
