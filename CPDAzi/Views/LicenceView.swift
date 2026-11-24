import SwiftUI

/// 对应 Android LicenseActivity
struct LicenceView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @State private var message = ""
    @State private var ok = false

    var body: some View {
        NavigationView {
            Form {
                Section("设备码") {
                    Text(LicenceManager.deviceCode())
                        .font(.system(.title3, design: .monospaced))
                        .textSelection(.enabled)
                    Text("把这个码发给签发方，换回授权码")
                        .font(.caption2).foregroundStyle(.secondary)
                }

                Section("授权码") {
                    TextField("EPL1A.xxx.yyy 或 6 位数字", text: $code)
                        .font(.system(.body, design: .monospaced))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section {
                    Button("激活") {
                        let r = LicenceManager.shared.activate(code)
                        ok = r.ok
                        message = r.ok
                            ? "已激活 · \(r.expText) · \(r.modText)"
                            : r.reason
                    }
                }

                if !message.isEmpty {
                    Section {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(ok ? .green : .red)
                    }
                }

                Section {
                    Button("清除授权", role: .destructive) {
                        LicenceManager.shared.clear()
                        message = "已清除"
                        ok = false
                    }
                }
            }
            .navigationTitle("授权")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }
}
