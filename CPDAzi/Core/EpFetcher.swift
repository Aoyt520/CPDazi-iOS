import Foundation
import UIKit
import Combine

/// MJPEG 拉流 —— 对应 Android com.z6.fusion.EpFetcher（GET /f 返回单帧 JPEG）
final class EpFetcher: ObservableObject {

    @Published private(set) var running = false
    @Published private(set) var lastFrame: UIImage?
    @Published private(set) var lastError: String = ""
    @Published private(set) var fps: Double = 0
    @Published private(set) var bytesPerFrame: Int = 0

    private var worker: DispatchSourceTimer?
    private var frameNo: Int64 = 0
    private var successCount = 0
    private var failStreak = 0
    private var tickCount = 0
    private var lastFpsAt = Date()
    private let session: URLSession

    init() {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 1.8
        cfg.timeoutIntervalForResource = 1.8
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        cfg.httpMaximumConnectionsPerHost = 4
        session = URLSession(configuration: cfg)
    }

    var endpoint: String {
        "http://\(FusionConfig.shared.resolvedHost):\(FusionConfig.defaultPort)/f"
    }

    func start() {
        guard !running else { return }
        running = true
        failStreak = 0
        successCount = 0
        tickCount = 0
        lastFpsAt = Date()

        let interval = 1.0 / Double(max(1, min(30, FusionConfig.shared.fps)))
        let t = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "z6.epview"))
        t.schedule(deadline: .now(), repeating: interval, leeway: .milliseconds(20))
        t.setEventHandler { [weak self] in self?.pull() }
        t.resume()
        worker = t
    }

    func stop() {
        running = false
        worker?.cancel()
        worker = nil
    }

    private func pull() {
        guard running else { return }
        frameNo += 1
        guard let url = URL(string: "\(endpoint)?t=\(frameNo)") else { return }
        var req = URLRequest(url: url)
        req.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        req.setValue("no-cache", forHTTPHeaderField: "Pragma")

        session.dataTask(with: req) { [weak self] data, resp, err in
            guard let self, self.running else { return }
            self.tickCount += 1

            if let err {
                self.onFailure("\(err.localizedDescription)")
                return
            }
            guard let h = resp as? HTTPURLResponse, h.statusCode == 200 else {
                let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
                self.onFailure("HTTP \(code) @ \(FusionConfig.shared.resolvedHost):\(FusionConfig.defaultPort)")
                return
            }
            guard let data, data.count >= 128 else {
                self.onFailure("空帧 / 设备未推流")
                return
            }
            guard let img = UIImage(data: data) else {
                self.onFailure("JPEG 解码失败")
                return
            }
            self.failStreak = 0
            self.successCount += 1
            DispatchQueue.main.async {
                self.lastFrame = img
                self.bytesPerFrame = data.count
                self.lastError = ""
                self.refreshFps()
            }
        }.resume()
    }

    private func onFailure(_ msg: String) {
        failStreak += 1
        // 与原实现一致：首次失败立即报，之后每 20 次报一次
        if failStreak == 1 || failStreak % 20 == 0 {
            DispatchQueue.main.async {
                self.lastError = msg
                self.refreshFps()
            }
        }
    }

    private func refreshFps() {
        let dt = Date().timeIntervalSince(lastFpsAt)
        guard dt >= 2 else { return }
        fps = Double(successCount) / dt
        successCount = 0
        lastFpsAt = Date()
    }
}
