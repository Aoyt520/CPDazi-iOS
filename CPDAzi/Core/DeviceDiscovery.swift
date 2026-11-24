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

    private let queue = DispatchQueue(label: "z6.scan", qos: .userInitiated)

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
            guard ifa.ifa_addr?.pointee.sa_family == UInt8(AF_INET) else { continue }
            let name = String(cString: ifa.ifa_name)
            guard name == "en0" else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(ifa.ifa_addr, socklen_t(ifa.ifa_addr.pointee.sa_len),
                           &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                address = String(cString: host)
            }
        }
        return address
    }

    func scan(port: UInt16 = UInt16(FusionConfig.statPort), timeout: TimeInterval = 12) {
        guard !isScanning else { return }
        let prefix = currentSubnetPrefix()
        guard !prefix.isEmpty else { return }
        isScanning = true
        localPrefix = prefix
        found = []
        scanned = 0
        total = 254

        queue.async { [weak self] in
            guard let self else { return }
            let group = DispatchGroup()
            let sem = DispatchSemaphore(value: 48)
            var hits: [String] = []
            let lock = NSLock()
            let deadline = Date().addingTimeInterval(timeout)

            for i in 1...254 {
                guard Date() < deadline else { break }
                let ip = "\(prefix)\(i)"
                group.enter()
                sem.wait()
                DispatchQueue.global(qos: .userInitiated).async {
                    defer {
                        sem.signal()
                        group.leave()
                    }
                    if Self.probeSync(ip: ip, port: port) {
                        lock.lock(); hits.append(ip); lock.unlock()
                        DispatchQueue.main.async {
                            self.found = hits.sorted()
                        }
                    }
                    DispatchQueue.main.async { self.scanned += 1 }
                }
            }
            group.wait()
            let sorted = hits.sorted()
            DispatchQueue.main.async {
                self.found = sorted
                self.isScanning = false
            }
        }
    }

    /// 同步探测，供并发扫描使用；与 Android DeviceScanner.probe 判定条件一致
    static func probeSync(ip: String, port: UInt16) -> Bool {
        guard let url = URL(string: "http://\(ip):\(port)/stat") else { return false }
        var req = URLRequest(url: url)
        req.timeoutInterval = 0.5
        req.cachePolicy = .reloadIgnoringLocalCacheData
        let sem = DispatchSemaphore(value: 0)
        var ok = false
        let task = URLSession.shared.dataTask(with: req) { data, resp, _ in
            defer { sem.signal() }
            guard let h = resp as? HTTPURLResponse, h.statusCode == 200, let data else { return }
            let s = String(decoding: data, as: UTF8.self)
            ok = s.contains("seq=") || s.contains("fps=") || s.contains("out=")
        }
        task.resume()
        _ = sem.wait(timeout: .now() + 1.0)
        task.cancel()
        return ok
    }
}
