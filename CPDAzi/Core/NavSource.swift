import Foundation

/// 导航引导数据 —— 对应 Android 端从高德 SDK 反射读取的字段集
/// Android: Class.forName("qa.y2").n().j() 取 Guidance 对象，静态字段访问
/// iOS 侧统一定义为值类型，由具体数据源填充
struct NavGuidance {
    var nextIntersectionType: Int = -1
    var nextIntersectionRemainDistance: Int = 0
    var totalRemainDistance: Int = 0
    var remainSeconds: Int = 0
    var nextIntersectionRoadName: String = ""
    var roadName: String = ""
    var nextSpecIntersectionType: Int = 9999
    var closeIntersectionType: Int = -1
    var nextSpecialAccType: Int = -1
    var isValid: Bool = false
}

/// 车道信息 —— Android: Guidance.laneInfo
struct LaneInfo {
    var arrow: String = ""
    var flag: String = ""
    var recommend: String = ""
    var laneNumLeft: Int = -1
    var laneNumRight: Int = -1
    var isValid: Bool = false
}

protocol NavDataSource: AnyObject {
    /// 每 500ms 被 FusionBridge 调用一次；无有效数据时返回 isValid=false
    func currentGuidance() -> NavGuidance
    /// 车道级信息；无则 isValid=false
    func currentLane() -> LaneInfo
}

/// 手动 / 演示数据源：用于没有接入高德 SDK 时验证整条链路
final class ManualNavSource: NavDataSource {
    static let shared = ManualNavSource()

    var guidance = NavGuidance()
    var lane = LaneInfo()

    func currentGuidance() -> NavGuidance { guidance }
    func currentLane() -> LaneInfo { lane }
}
