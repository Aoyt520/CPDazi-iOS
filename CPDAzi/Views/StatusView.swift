import SwiftUI

/// 对应 Android SettingsActivity 的状态页
struct StatusView: View {
    @EnvironmentObject var cfg: FusionConfig
    @EnvironmentObject var bridge: FusionBridge
    @State private var reachable: Bool?
    @State private var checking = false

    var body: some View {
        NavigationView {
            Form {
                Section("授权") {
                    let s = LicenceManager.shared.summary
                    Text(s)
                        .font(.footnote)
                    HStack {
                        Text("本机设备码").font(.caption)
                        Spacer()
                        Text(LicenceManager.deviceCode()).font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    }
                    NavigationLink("打开授权页") { LicenceView() }
                }

                Section("链路") {
                    row("目标设备", cfg.resolvedHost)
                    row("视频源", "http://\(cfg.resolvedHost):\(FusionConfig.defaultPort)/f")
                    row("融合桥", bridge.status)
                    row("帧计数", "\(bridge.frameCount)")
                    row("7706 出包", bridge.linkHealthy ? "健康" : "超时")
                    if let r = reachable {
                        row("目标可达性", r ? "可达 ✔" : "不可达 ✘")
                    }
                }

                Section {
                    Button(checking ? "检测中…" : "重测可达性") {
                        checking = true
                        reachable = nil
                        Task {
                            let ok = await DeviceClient.shared.probeStat(cfg.resolvedHost)
                            await MainActor.run {
                                reachable = ok
                                checking = false
                            }
                        }
                    }
                    Button(bridge.running ? "停止融合桥" : "启动融合桥") {
                        if bridge.running { bridge.stop() } else { bridge.start() }
                    }
                }

                Section("导航卡片条件") {
                    let g = bridge.lastGuidance
                    row("导航有效", g.isValid ? "✔" : "—")
                    row("nGoPosDist", "\(g.totalRemainDistance)")
                    row("nGoPosTime", "\(g.remainSeconds)")
                    row("转向类型", "\(g.nextIntersectionType) → \(FusionProtocol.mapTurn(g.nextIntersectionType))")
                }
            }
            .navigationTitle("融合状态")
        }
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text(v).font(.system(.caption, design: .monospaced)).multilineTextAlignment(.trailing)
        }
    }
}
