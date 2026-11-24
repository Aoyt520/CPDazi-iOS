import Foundation

/// 从 APK classes9.dex (com.z6.fusion.TcBridge / DeviceActivity) 逆向出的协议构造器
/// 所有字段名与 Android 端逐字节一致，勿改
enum FusionProtocol {

    // MARK: - 转向类型映射

    /// 高德 nextIntersectionType → 车机 nTBTTurnType
    /// 原实现：TcBridge.mapTurn(int)
    static func mapTurn(_ t: Int) -> Int {
        switch t {
        case 2, 4: return 12
        case 3, 5: return 13
        case 6:    return 16
        case 7:    return 19
        case 8:    return 14
        default:   return -1
        }
    }

    /// 变道方向：0=左 1=右 -1=不变道
    /// 原实现：TcBridge.dirOf(int)
    static func dirOf(_ t: Int) -> Int {
        switch t {
        case 2, 4, 6: return 0
        case 3, 5, 7: return 1
        default:      return -1
        }
    }

    // MARK: - 7706 导航帧

    /// 原实现：TcBridge.sendNav(...)
    static func navFrame(index: Int,
                         turnType: Int,
                         tbtDist: Int,
                         goPosDist: Int,
                         goPosTime: Int,
                         mainText: String,
                         roadName: String,
                         nextTurnType: Int = -1,
                         nextDist: Int = 0) -> [String: Any] {
        [
            "carrotIndex": index,
            "nTBTTurnType": turnType,
            "nTBTDist": tbtDist,
            "nGoPosDist": goPosDist,
            "nGoPosTime": goPosTime,
            "nRoadLimitSpeed": 30,
            "szTBTMainText": mainText,
            "szPosRoadName": roadName,
            "nTBTTurnTypeNext": nextTurnType,
            "nTBTDistNext": nextDist,
            "nTBTNextRoadWidth": 0,
            "szNearDirName": "",
            "szFarDirName": "",
            "nSdiType": -1,
            "roadcate": 0
        ]
    }

    // MARK: - 7706 指令帧

    /// 原实现：TcBridge.sendLaneChange / FusionBridge.sendCommand
    static func commandFrame(index: Int, cmd: String, arg: String) -> [String: Any] {
        ["carrotIndex": index, "carrotCmd": cmd, "carrotArg": arg]
    }

    /// 原实现：DeviceActivity.sendGoal(int)
    static func goalFrame(x: Double, y: Double, name: String) -> [String: Any] {
        ["goalPosX": x, "goalPosY": y, "szGoalName": name]
    }

    // MARK: - 7795 心跳

    static let heartbeat: [String: Any] = ["z6Hb": 1]

    // MARK: - 7707 诊断镜像

    static func laneDiagFrame(arrow: String, recommend: String, curIdx: Int, recIdx: Int) -> [String: Any] {
        ["z6Lane": 1, "arrow": arrow, "recommend": recommend, "curIdx": curIdx, "recIdx": recIdx]
    }

    static func flagDiagFrame(_ flag: String) -> [String: Any] {
        ["z6Flag": 1, "v": flag]
    }

    static func rawDiagFrame(_ a: Int, _ b: Int, _ c: Int, _ d: Int) -> [String: Any] {
        ["z6Raw": 1, "a": a, "b": b, "c": c, "d": d]
    }

    // MARK: - 7000 参数

    /// 原实现：DeviceActivity.PARAM_KEYS
    static let paramKeys = [
        "AutoTurnControl",
        "AutoTurnControlSpeedTurn",
        "AutoCurveSpeedFactor",
        "AutoCurveSpeedLowerLimit",
        "MapTurnSpeedFactor",
        "AutoNaviSpeedDecelRate",
        "AutoRoadSpeedLimitOffset",
        "TurnSpeedControlMode",
        "ClusterHudCameraViewMode",
        "ExperimentalMode",
        "SpeedFromPCM"
    ]

    static func jsonData(_ obj: [String: Any]) -> Data {
        (try? JSONSerialization.data(withJSONObject: obj, options: [])) ?? Data()
    }
}
