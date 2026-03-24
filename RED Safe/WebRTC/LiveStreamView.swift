// SPM dependency required: https://github.com/livekit/webrtc-xcframework.git
// Add via Xcode → File → Add Package Dependencies → paste the URL above.

import SwiftUI

/// 全螢幕即時影像預覽頁面，依據連線狀態切換顯示內容。
struct LiveStreamView: View {
    let edge: EdgeSummary

    @StateObject private var viewModel = LiveStreamViewModel()

    /// 錯誤碼 164 的對應訊息，用於判斷是否為無授權失敗。
    private static let noLicenseMessage = ApiErrorCode(rawValue: "164").message

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch viewModel.state {
            case .idle, .connecting:
                VStack(spacing: 16) {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(1.2)
                    Text("正在連線...")
                        .font(.bodyMedium)
                        .foregroundStyle(.white.opacity(0.8))
                }

            case .connected:
                if let track = viewModel.videoTrack {
                    WebRTCVideoView(videoTrack: track)
                        .ignoresSafeArea()
                } else {
                    VStack(spacing: 16) {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(1.2)
                        Text("等待影像串流...")
                            .font(.bodyMedium)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }

            case .failed(let message):
                if message == Self.noLicenseMessage {
                    noLicenseView
                } else {
                    VStack(spacing: 20) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(Color.warningOrange)
                        Text("連線失敗")
                            .font(.displaySmall)
                            .foregroundStyle(.white)
                        Text(message)
                            .font(.bodyMedium)
                            .foregroundStyle(.white.opacity(0.7))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                        Button {
                            Task { await viewModel.connect(edgeId: edge.edgeId) }
                        } label: {
                            Text("重試")
                                .font(.bodyMedium.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 32)
                                .padding(.vertical, 12)
                                .background(
                                    Capsule()
                                        .fill(Color.primaryBrand)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }

            case .disconnected:
                VStack(spacing: 16) {
                    Image(systemName: "video.slash.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.white.opacity(0.5))
                    Text("已中斷連線")
                        .font(.bodyMedium)
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
        }
        .navigationTitle("即時影像")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task {
            await viewModel.connect(edgeId: edge.edgeId)
        }
        .onDisappear {
            viewModel.disconnect()
        }
    }

    private var noLicenseView: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.shield.fill")
                .font(.system(size: 40))
                .foregroundStyle(Color.warningOrange)
            Text("尚無有效授權")
                .font(.displaySmall)
                .foregroundStyle(.white)
            Text("此裝置尚無有效授權，無法執行指令。\n請至 introducing.redsafe-tw.com 購買授權。")
                .font(.bodyMedium)
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button {
                if let url = URL(string: "https://introducing.redsafe-tw.com/pricing") {
                    UIApplication.shared.open(url)
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "cart.fill")
                    Text("購買授權")
                }
                .font(.bodyMedium.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 32)
                .padding(.vertical, 12)
                .background(
                    Capsule()
                        .fill(Color.primaryBrand)
                )
            }
            .buttonStyle(.plain)
        }
    }
}
