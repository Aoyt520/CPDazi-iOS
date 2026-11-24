import SwiftUI

/// 对应 Android DeviceActivity（手动控制面板）
struct DeviceView: View {
    @EnvironmentObject var cfg: FusionConfig
    @EnvironmentObject var bridge: FusionBridge
    @State private var status = ""
    @State private var params: [String: String] = [:]
    @State private var edits: [String: String] = [:]
    @State private var goalX = ""
    @State private var goalY = ""
    @State private var goalName = ""
    @State private var authorised = false

    var body: some View {
        NavigationView {
            Form {
                if !authorised {
                    Section {
                        Text("设备功能未授权（需要 MOD 位 4）")
                            .foregroundStyle(.red)
                        NavigationLink("打开授权页") { LicenceView() }
                    }
                }

                Section("① 变道（7706 LANECHANGE）") {
                    HStack {
                        Button("← 左变道") { cmd("LANECHANGE", "LEFT") }
                        Button("右变道 →") { cmd("LANECHANGE", "RIGHT") }
                    }
                }

                Section("② 巡航（7706 CRUISE）") {
                    HStack {
                        Button("巡航开") { cmd("CRUISE", "ON") }
                        Button("巡航关") { cmd("CRUISE", "OFF") }
                        Button("GO") { cmd("CRUISE", "GO") }
                    }
                }

                Section("③ 显示与录屏") {
                    HStack {
                        Button("显示地图") { cmd("DISPLAY", "MAP") }
                        Button("显示道路") { cmd("DISPLAY", "ROAD") }
                    }
                    HStack {
                        Button("录屏开") { cmd("RECORD", "START") }
                        Button("录屏关") { cmd("RECORD", "STOP") }
                        Button("切换") { cmd("RECORD", "TOGGLE") }
                    }
                }

                Section("④ 驾驶模式（7000 param_set）") {
                    HStack {
                        Button("Chill") { setParam("ExperimentalMode", false) }
                        Button("实验") { setParam("ExperimentalMode", true) }
                    }
                    HStack {
                        ForEach(0..<3, id: \.self) { i in
                            Button("ATC \(i)") { setParam("AutoTurnControl", i) }
                        }
                    }
                    HStack {
                        ForEach(0..<3, id: \.self) { i in
                            Button("速度源 \(i)") { setParam("SpeedFromPCM", i) }
                        }
                    }
                }

                Section("⑤ 参数（读取 / 写入）") {
                    Button("读取全部当前值") { loadParams() }
                    ForEach(FusionProtocol.paramKeys, id: \.self) { key in
                        HStack {
                            Text(key).font(.caption2).lineLimit(1)
                            Spacer()
                            TextField("—", text: Binding(
                                get: { edits[key] ?? params[key] ?? "" },
                                set: { edits[key] = $0 }
                            ))
                            .multilineTextAlignment(.trailing)
                            .frame(width: 90)
                            .font(.system(.caption, design: .monospaced))
                            Button("存") { saveParam(key) }
                                .font(.caption)
                        }
                    }
                }

                Section("⑥ 目的地（7706 goalPos）") {
                    TextField("X 经度", text: $goalX).keyboardType(.decimalPad)
                    TextField("Y 纬度", text: $goalY).keyboardType(.decimalPad)
                    TextField("名称", text: $goalName)
                    Button("发送目的地") {
                        guard let x = Double(goalX), let y = Double(goalY) else {
                            status = "坐标格式不对"
                            return
                        }
                        bridge.sendGoal(x: x, y: y, name: goalName.isEmpty ? "目的地" : goalName)
                        status = "已发送（设备侧仅记录，不等于导航执行）"
                    }
                }

                if !status.isEmpty {
                    Section { Text(status).font(.footnote) }
                }
            }
            .navigationTitle("手动控制")
            .onAppear { authorised = LicenceManager.shared.allowed(.device) }
            .onChange(of: bridge.running) { _, _ in
                authorised = LicenceManager.shared.allowed(.device)
            }
        }
    }

    private func cmd(_ c: String, _ a: String) {
        bridge.sendCommand(c, arg: a)
        status = "已发送 \(c) \(a) → \(cfg.resolvedHost):7706"
    }

    private func setParam(_ name: String, _ value: Any) {
        Task {
            do {
                _ = try await DeviceClient.shared.setParam(name: name, value: value)
                await MainActor.run { status = "已写入 \(name) = \(value)" }
                loadParams()
            } catch {
                await MainActor.run { status = "写入失败：\(error.localizedDescription)" }
            }
        }
    }

    private func saveParam(_ key: String) {
        let raw = (edits[key] ?? "").trimmingCharacters(in: .whitespaces)
        let value: Any
        if raw.lowercased() == "true" { value = true }
        else if raw.lowercased() == "false" { value = false }
        else if let n = Int(raw) { value = n }
        else if let d = Double(raw) { value = d }
        else { value = raw }
        setParam(key, value)
    }

    private func loadParams() {
        Task {
            do {
                let r = try await DeviceClient.shared.readParams(FusionProtocol.paramKeys)
                var out: [String: String] = [:]
                if let values = r["values"] as? [String: Any] {
                    for (k, v) in values { out[k] = "\(v)" }
                } else {
                    for (k, v) in r where FusionProtocol.paramKeys.contains(k) { out[k] = "\(v)" }
                }
                await MainActor.run {
                    params = out
                    status = "参数已读回 · \(cfg.resolvedHost):7000"
                }
            } catch {
                await MainActor.run { status = "连不上设备 \(cfg.resolvedHost):7000 —— \(error.localizedDescription)" }
            }
        }
    }
}
