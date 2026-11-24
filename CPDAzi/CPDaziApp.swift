import SwiftUI

@main
struct CPDaziApp: App {
    @StateObject private var cfg = FusionConfig.shared
    @StateObject private var bridge = FusionBridge.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(cfg)
                .environmentObject(bridge)
                .preferredColorScheme(.dark)
        }
    }
}

struct RootView: View {
    @EnvironmentObject var cfg: FusionConfig
    @EnvironmentObject var bridge: FusionBridge

    var body: some View {
        TabView {
            StatusView()
                .tabItem { Label("状态", systemImage: "gauge") }
            DeviceView()
                .tabItem { Label("控制", systemImage: "car") }
            EPViewScreen()
                .tabItem { Label("EPview", systemImage: "rectangle.on.rectangle") }
            SettingsView()
                .tabItem { Label("设置", systemImage: "gearshape") }
        }
        .onAppear {
            bridge.dataSource = ManualNavSource.shared
        }
    }
}
