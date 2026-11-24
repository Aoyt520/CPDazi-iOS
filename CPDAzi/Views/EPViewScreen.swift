import SwiftUI

/// 对应 Android EpWindow / OverlayController
/// iOS 无系统级悬浮窗权限，改为应用内全屏画面 + 可缩放拖动
struct EPViewScreen: View {
    @EnvironmentObject var cfg: FusionConfig
    @StateObject private var fetcher = EpFetcher()

    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var immersive = false
    @State private var authorised = false

    var body: some View {
        NavigationView {
            GeometryReader { geo in
                ZStack {
                    Color.black.ignoresSafeArea()

                    if !authorised {
                        VStack(spacing: 12) {
                            Text("EPview 未授权").foregroundStyle(.red)
                            NavigationLink(destination: LicenceView()) { Text("打开授权页") }
                        }
                    } else if let img = fetcher.lastFrame {
                        Image(uiImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .scaleEffect(scale)
                            .offset(offset)
                            .gesture(
                                SimultaneousGesture(
                                    MagnificationGesture()
                                        .onChanged { v in scale = max(0.5, min(6, lastScale * v)) }
                                        .onEnded { _ in lastScale = scale },
                                    DragGesture()
                                        .onChanged { v in
                                            offset = CGSize(width: lastOffset.width + v.translation.width,
                                                            height: lastOffset.height + v.translation.height)
                                        }
                                        .onEnded { _ in lastOffset = offset }
                                )
                            )
                            .onTapGesture(count: 2) {
                                withAnimation { immersive.toggle() }
                            }
                    } else {
                        VStack(spacing: 8) {
                            ProgressView()
                            Text(fetcher.lastError.isEmpty ? "等待画面…" : fetcher.lastError)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                    }

                    if !immersive {
                        VStack {
                            HStack {
                                Text(String(format: "%.1f fps", fetcher.fps))
                                    .font(.system(.caption2, design: .monospaced))
                                    .padding(6)
                                    .background(.ultraThinMaterial, in: Capsule())
                                Spacer()
                                Button {
                                    if fetcher.running { fetcher.stop() } else { fetcher.start() }
                                } label: {
                                    Image(systemName: fetcher.running ? "stop.fill" : "play.fill")
                                }
                                .padding(6)
                                .background(.ultraThinMaterial, in: Circle())
                                Button {
                                    withAnimation { scale = 1; offset = .zero; lastScale = 1; lastOffset = .zero }
                                } label: {
                                    Image(systemName: "arrow.counterclockwise")
                                }
                                .padding(6)
                                .background(.ultraThinMaterial, in: Circle())
                            }
                            .padding(.horizontal, 12)
                            .padding(.top, 8)
                            Spacer()
                            Text("\(fetcher.bytesPerFrame) B/帧 · \(cfg.resolvedHost):\(FusionConfig.defaultPort)")
                                .font(.system(.caption2, design: .monospaced))
                                .padding(6)
                                .background(.ultraThinMaterial, in: Capsule())
                                .padding(.bottom, 8)
                        }
                    }
                }
            }
            .navigationTitle("EPview")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                authorised = LicenceManager.shared.allowed(.epview)
                if authorised && cfg.epAutoStart && !fetcher.running { fetcher.start() }
            }
            .onDisappear { fetcher.stop() }
        }
    }
}
