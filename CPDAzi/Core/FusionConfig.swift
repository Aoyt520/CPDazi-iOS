import Foundation
import Combine

/// 与 Android 端 FusionPrefs 一一对应，键名保持完全一致以便双端共用配置语义
final class FusionConfig: ObservableObject {
    static let shared = FusionConfig()

    private let d = UserDefaults.standard

    static let defaultHost = "192.168.16.31"
    static let defaultPort = 7002
    static let statPort = 7002
    static let devicePort = 7000
    static let udpPort = 7706
    static let diagPort = 7707
    static let hbPort = 7795

    @Published var host: String {
        didSet { d.set(host, forKey: "ip") }
    }
    @Published var fps: Int {
        didSet { d.set(max(1, min(30, fps)), forKey: "fps") }
    }
    @Published var laneEnabled: Bool {
        didSet { d.set(laneEnabled, forKey: "lane_enabled") }
    }
    @Published var epAutoStart: Bool {
        didSet { d.set(epAutoStart, forKey: "ep_autostart") }
    }
    @Published var greetingEnabled: Bool {
        didSet { d.set(greetingEnabled, forKey: "greeting_on") }
    }
    @Published var licenceCode: String {
        didSet { d.set(licenceCode, forKey: "code") }
    }
    @Published var activatedAt: String {
        didSet { d.set(activatedAt, forKey: "activated_at") }
    }

    init() {
        host = d.string(forKey: "ip") ?? Self.defaultHost
        fps = d.object(forKey: "fps") as? Int ?? 15
        laneEnabled = d.object(forKey: "lane_enabled") as? Bool ?? true
        epAutoStart = d.object(forKey: "ep_autostart") as? Bool ?? true
        greetingEnabled = d.object(forKey: "greeting_on") as? Bool ?? true
        licenceCode = d.string(forKey: "code") ?? ""
        activatedAt = d.string(forKey: "activated_at") ?? ""
    }

    /// 与 Android FusionPrefs.ip(context) 等价；resolveIp 的 ARP 探测在 iOS 上不可用，改由用户/发现页写入
    var resolvedHost: String {
        host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Self.defaultHost : host
    }
}
