import Foundation
import UIKit

/// 对应 Android com.z6.fusion.DeviceHttp（端口 7000）
final class DeviceClient {

    static let shared = DeviceClient()

    enum ClientError: LocalizedError {
        case notAuthorised
        case badURL
        case http(Int)
        var errorDescription: String? {
            switch self {
            case .notAuthorised: return "设备功能未授权"
            case .badURL: return "地址无效"
            case .http(let c): return "HTTP \(c)"
            }
        }
    }

    private let session: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 2.5
        cfg.timeoutIntervalForResource = 2.5
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: cfg)
    }()

    /// 原实现：DeviceHttp.base(Context)
    private func base() -> String {
        "http://\(FusionConfig.shared.resolvedHost):\(FusionConfig.devicePort)"
    }

    /// 原实现：DeviceHttp.guard(Context)
    private func guardLicence() throws {
        guard LicenceManager.shared.check().allows(.device) else {
            throw ClientError.notAuthorised
        }
    }

    private func get(_ urlString: String) async throws -> [String: Any] {
        guard let url = URL(string: urlString) else { throw ClientError.badURL }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("close", forHTTPHeaderField: "Connection")
        let (data, resp) = try await session.data(for: req)
        if let h = resp as? HTTPURLResponse, h.statusCode >= 400 {
            // 与原实现一致：错误流也尝试解析 JSON
            return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        }
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    private func post(_ urlString: String, body: [String: Any]) async throws -> [String: Any] {
        guard let url = URL(string: urlString) else { throw ClientError.badURL }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("close", forHTTPHeaderField: "Connection")
        req.httpBody = FusionProtocol.jsonData(body)
        let (data, resp) = try await session.data(for: req)
        if let h = resp as? HTTPURLResponse, h.statusCode >= 400 {
            return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        }
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    /// GET /api/params_bulk?names=...
    func readParams(_ names: [String]) async throws -> [String: Any] {
        try guardLicence()
        let joined = names.joined(separator: ",")
        let encoded = joined.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? joined
        return try await get("\(base())/api/params_bulk?names=\(encoded)")
    }

    /// POST /api/param_set
    @discardableResult
    func setParam(name: String, value: Any) async throws -> [String: Any] {
        try guardLicence()
        let body: [String: Any] = [
            "name": name,
            "value": value,
            "source": "z6_fusion_device_page"
        ]
        return try await post("\(base())/api/param_set", body: body)
    }

    /// GET /api/heartbeat_status
    func heartbeat() async throws -> [String: Any] {
        try await get("\(base())/api/heartbeat_status")
    }

    /// GET /api/live_runtime?force=1
    func liveRuntime() async throws -> [String: Any] {
        try await get("\(base())/api/live_runtime?force=1")
    }

    /// GET :7002/stat —— 原实现 TcBridge.probeIp / DeviceScanner.probe
    func probeStat(_ ip: String) async -> Bool {
        guard let url = URL(string: "http://\(ip):\(FusionConfig.statPort)/stat") else { return false }
        var req = URLRequest(url: url)
        req.timeoutInterval = 0.6
        req.cachePolicy = .reloadIgnoringLocalCacheData
        do {
            let (data, resp) = try await session.data(for: req)
            guard let h = resp as? HTTPURLResponse, h.statusCode == 200 else { return false }
            let s = String(decoding: data, as: UTF8.self)
            return s.contains("seq=") || s.contains("fps=") || s.contains("out=")
        } catch {
            return false
        }
    }
}
