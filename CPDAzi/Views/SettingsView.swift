import SwiftUI

/// 对应 Android SettingsActivity（设置页）
struct SettingsView: View {
    @EnvironmentObject var cfg: FusionConfig
    @StateObject private var discovery = DeviceDiscovery()
    @State private var manualHost = ""

    var body: some View {
        NavigationView {
            Form {
                Section("目标设备") {
                    TextField("IP", text: Binding(
                        get: { cfg.host },
                        set: { cfg.host = $0 }
                    ))
                    .keyboardType(.decimalPad)
                    .font(.system(.body, design: .monospaced))
                    HStack {
                        Text("本机网段").font(.caption)
                        Spacer()
                        Text(discovery.localPrefix.isEmpty ? "—" : "\(discovery.localPrefix)x")
                            .font(.system(.caption, design: .monospaced))
                    }
                }

                Section("设备发现") {
                    Button(discovery.isScanning
                           ? "扫描中 \(discovery.scanned)/\(discovery.total)"
                           : "扫描本网段") {
                        discovery.scan()
                    }
                    .disabled(discovery.isScanning)

                    ForEach(discovery.found, id: \.self) { ip in
                        Button {
                            cfg.host = ip
                            manualHost = ip
                        } label: {
                            HStack {
                                Text(ip).font(.system(.caption, design: .monospaced))
                                Spacer()
                                if cfg.host == ip {
                                    Image(systemName: "checkmark").foregroundStyle(.green)
                                }
                            }
                        }
                    }
                }

                Section("EPview") {
                    Toggle("自动启动画面", isOn: Binding(
                        get: { cfg.epAutoStart },
                        set: { cfg.epAutoStart = $0 }
                    ))
                    Stepper("帧率 \(cfg.fps)", value: Binding(
                        get: { cfg.fps },
                        set: { cfg.fps = $0 }
                    ), in: 1...30)
                }

                Section("融合桥") {
                    Toggle("车道变道辅助", isOn: Binding(
                        get: { cfg.laneEnabled },
                        set: { cfg.laneEnabled = $0 }
                    ))
                    Toggle("开机问候", isOn: Binding(
                        get: { cfg.greetingEnabled },
                        set: { cfg.greetingEnabled = $0 }
                    ))
                    HStack {
                        Text("状态")
                        Spacer()
                        Text(FusionBridge.shared.status).foregroundStyle(.secondary)
                    }
                }

                Section("授权") {
                    Text(LicenceManager.shared.summary).font(.caption)
                    NavigationLink(destination: LicenceView()) { Text("打开授权页") }
                }

                Section("协议端口（只读）") {
                    port("UDP 导航下发", FusionConfig.udpPort)
                    port("UDP 诊断镜像", FusionConfig.diagPort)
                    port("UDP 心跳", FusionConfig.hbPort)
                    port("HTTP 参数", FusionConfig.devicePort)
                    port("HTTP 视频流", FusionConfig.defaultPort)
                }

                Section {
                    Text("协议逆向自 com.tencent.wecarnavi 9.11.0.159 (classes9.dex / com.z6.fusion)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("设置")
        }
    }

    private func port(_ name: String, _ p: Int) -> some View {
        HStack {
            Text(name).font(.caption)
            Spacer()
            Text("\(p)").font(.system(.caption, design: .monospaced))
        }
    }
}
