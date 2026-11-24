import Foundation
import Combine

/// 融合桥主循环 —— 对应 Android com.z6.fusion.TcBridge + FusionBridge
/// 每 500ms 从 NavDataSource 拉一次引导数据，映射后经 UDP 7706 下发，同时发 7795 心跳
final class FusionBridge: ObservableObject {

    static let shared = FusionBridge()

    @Published private(set) var running = false
    @Published private(set) var status = "待机"
    @Published private(set) var lastSendAt = Date.distantPast
    @Published private(set) var frameCount = 0
    @Published private(set) var lastGuidance = NavGuidance()
    @Published private(set) var lastLane = LaneInfo()

    weak var dataSource: NavDataSource? = ManualNavSource.shared

    private let udp = UDPSender()
    private var timer: DispatchSourceTimer?
    private var seq = Int(Date().timeIntervalSince1970)
    private var lastLaneAt = Date.distantPast
    private let laneInterval: TimeInterval = 15
    private let tickInterval: TimeInterval = 0.5

    private var host: String { FusionConfig.shared.resolvedHost }

    var linkHealthy: Bool {
        Date().timeIntervalSince(lastSendAt) < 10
    }

    // MARK: - 生命周期

    func start() {
        guard !running else { return }
        running = true
        status = "运行中"
        seq = Int(Date().timeIntervalSince1970)

        let t = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "z6.bridge"))
        t.schedule(deadline: .now(), repeating: tickInterval, leeway: .milliseconds(50))
        t.setEventHandler { [weak self] in self?.tick() }
        t.resume()
        timer = t
    }

    func stop() {
        running = false
        status = "已停止"
        timer?.cancel()
        timer = nil
        udp.close()
    }

    private func nextIndex() -> Int {
        seq += 1
        return seq
    }

    // MARK: - 主循环，原实现 TcBridge.tick()

    private func tick() {
        guard running, let src = dataSource else { return }
        let g = src.currentGuidance()
        lastGuidance = g
        guard g.isValid else { return }

        sendNav(g)
        sendHeartbeat()
        frameCount += 1
        lastSendAt = Date()

        // 车道级诊断镜像（7706 同包 + 7707 语义一致，原实现只发 7706）
        udp.send(json: FusionProtocol.laneDiagFrame(arrow: "", recommend: "", curIdx: -3, recIdx: g.nextIntersectionType),
                 host: host, port: UInt16(FusionConfig.udpPort))
        udp.send(json: FusionProtocol.rawDiagFrame(g.nextIntersectionType,
                                                   g.nextSpecIntersectionType,
                                                   g.closeIntersectionType,
                                                   g.nextSpecialAccType),
                 host: host, port: UInt16(FusionConfig.udpPort))

        // 变道辅助，原实现 TcBridge.tick() 后半段
        let dir = FusionProtocol.dirOf(g.nextIntersectionType)
        guard dir != -1, g.nextSpecIntersectionType <= 1200 else { return }
        guard FusionConfig.shared.laneEnabled else { return }

        let lane = src.currentLane()
        lastLane = lane
        if lane.isValid {
            udp.send(json: FusionProtocol.flagDiagFrame(lane.flag), host: host, port: UInt16(FusionConfig.udpPort))
        }
        let assistDir = laneAssistDirection(base: dir, lane: lane)
        guard Date().timeIntervalSince(lastLaneAt) >= laneInterval else { return }
        let arg = assistDir == 0 ? "LEFT" : "RIGHT"
        udp.send(json: FusionProtocol.commandFrame(index: nextIndex(), cmd: "LANECHANGE", arg: arg),
                 host: host, port: UInt16(FusionConfig.udpPort))
        lastLaneAt = Date()
    }

    private func sendNav(_ g: NavGuidance) {
        let frame = FusionProtocol.navFrame(index: nextIndex(),
                                            turnType: FusionProtocol.mapTurn(g.nextIntersectionType),
                                            tbtDist: g.nextIntersectionRemainDistance,
                                            goPosDist: g.totalRemainDistance,
                                            goPosTime: g.remainSeconds,
                                            mainText: g.nextIntersectionRoadName,
                                            roadName: g.roadName)
        udp.send(json: frame, host: host, port: UInt16(FusionConfig.udpPort))
    }

    private func sendHeartbeat() {
        udp.send(json: FusionProtocol.heartbeat, host: host, port: UInt16(FusionConfig.hbPort))
    }

    /// 原实现 TcBridge.tryLaneAssist(int)
    private func laneAssistDirection(base: Int, lane: LaneInfo) -> Int {
        guard lane.isValid else { return base }
        guard let curIdx = lane.flag.firstIndex(of: "1"), let recIdx = lane.recommend.firstIndex(of: "1") else {
            return base
        }
        let cur = lane.flag.distance(from: lane.flag.startIndex, to: curIdx)
        let rec = lane.recommend.distance(from: lane.recommend.startIndex, to: recIdx)
        if cur != rec {
            let d = rec >= cur ? 1 : 0
            if d == base { return d }
        }
        return base
    }

    // MARK: - 手动指令，原实现 FusionBridge.sendCommand / sendExtras

    func sendCommand(_ cmd: String, arg: String) {
        udp.send(json: FusionProtocol.commandFrame(index: nextIndex(), cmd: cmd, arg: arg),
                 host: host, port: UInt16(FusionConfig.udpPort))
        DispatchQueue.main.async { self.lastSendAt = Date() }
    }

    func sendGoal(x: Double, y: Double, name: String) {
        udp.send(json: FusionProtocol.goalFrame(x: x, y: y, name: name),
                 host: host, port: UInt16(FusionConfig.udpPort))
        DispatchQueue.main.async { self.lastSendAt = Date() }
    }
}
