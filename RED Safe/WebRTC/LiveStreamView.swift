// SPM dependency required: https://github.com/livekit/webrtc-xcframework.git
// Add via Xcode → File → Add Package Dependencies → paste the URL above.

import SwiftUI
import UIKit

/// YouTube Live 風格的即時影像頁:
/// - 全螢幕黑底舞台,影像以 aspectFit 顯示
/// - tap 切換覆蓋層;3 秒無互動自動隱藏(連線中/失敗時保持顯示)
/// - 頂部:返回 / 標題 / LIVE 徽章 + 串流時長
/// - 底部:連線狀態 / 重連 / 旋轉鎖 / 全螢幕切換
/// - 支援橫向(透過 OrientationLock 動態解除 portrait 限制)
struct LiveStreamView: View {
    let edge: EdgeSummary

    @StateObject private var viewModel = LiveStreamViewModel()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var hSize

    @State private var controlsVisible = true
    @State private var hideControlsTask: Task<Void, Never>?
    @State private var startedAt: Date?
    @State private var elapsedSeconds: Int = 0
    @State private var orientationLocked = false
    @State private var isLandscapeForced = false

    /// 錯誤碼 164 的對應訊息,用於判斷是否為無授權失敗。
    private static let noLicenseMessage = ApiErrorCode(rawValue: "164").message
    private static let elapsedTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            stageContent
                .ignoresSafeArea()

            if controlsVisible || !isLive {
                overlay
                    .transition(.opacity)
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .statusBarHidden(!controlsVisible && isLive)
        .preferredColorScheme(.dark)
        .allowedOrientations(.allButUpsideDown)
        .contentShape(Rectangle())
        .onTapGesture { toggleControls() }
        .onReceive(Self.elapsedTimer) { _ in
            guard let started = startedAt else { return }
            elapsedSeconds = Int(Date().timeIntervalSince(started))
        }
        .onChange(of: viewModel.state) { _, newState in
            handleStateChange(newState)
        }
        .task {
            await viewModel.connect(edgeId: edge.edgeId)
        }
        .onDisappear {
            hideControlsTask?.cancel()
            viewModel.disconnect()
        }
    }

    // MARK: - Stage

    @ViewBuilder
    private var stageContent: some View {
        switch viewModel.state {
        case .idle, .connecting:
            statusStage(icon: nil, title: "正在連線...", showSpinner: true)
        case .connected:
            if let track = viewModel.videoTrack {
                WebRTCVideoView(videoTrack: track)
            } else {
                statusStage(icon: nil, title: "等待影像串流...", showSpinner: true)
            }
        case .failed(let message):
            if message == Self.noLicenseMessage {
                noLicenseStage
            } else {
                statusStage(icon: "exclamationmark.triangle.fill", title: "連線失敗", subtitle: message, showRetry: true)
            }
        case .disconnected:
            statusStage(icon: "video.slash.fill", title: "已中斷連線")
        }
    }

    private func statusStage(
        icon: String? = nil,
        title: String,
        subtitle: String? = nil,
        showSpinner: Bool = false,
        showRetry: Bool = false
    ) -> some View {
        VStack(spacing: 18) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 44))
                    .foregroundStyle(Color.warningOrange)
            }
            if showSpinner {
                ProgressView()
                    .tint(.white)
                    .scaleEffect(1.2)
            }
            Text(title)
                .font(.bodyLarge.weight(.semibold))
                .foregroundStyle(.white)
            if let subtitle {
                Text(subtitle)
                    .font(.bodyMedium)
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            if showRetry {
                Button {
                    Task { await viewModel.connect(edgeId: edge.edgeId) }
                } label: {
                    Text("重試")
                        .font(.bodyMedium.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 12)
                        .background(Capsule().fill(Color.primaryBrand))
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noLicenseStage: some View {
        VStack(spacing: 18) {
            Image(systemName: "exclamationmark.shield.fill")
                .font(.system(size: 44))
                .foregroundStyle(Color.warningOrange)
            Text("尚無有效授權")
                .font(.displaySmall)
                .foregroundStyle(.white)
            Text("此裝置尚無有效授權,無法執行指令。\n請至 introducing.redsafe-tw.com 購買授權。")
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
                .background(Capsule().fill(Color.primaryBrand))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Overlay (YouTube-Live style)

    private var overlay: some View {
        VStack(spacing: 0) {
            topBar
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .background(
                    LinearGradient(
                        colors: [.black.opacity(0.65), .black.opacity(0)],
                        startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea(edges: .top)
                )
            Spacer(minLength: 0)
            bottomBar
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
                .background(
                    LinearGradient(
                        colors: [.black.opacity(0), .black.opacity(0.65)],
                        startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea(edges: .bottom)
                )
        }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            iconButton(systemName: "chevron.left") { dismiss() }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    if isLive { liveBadge }
                    Text(edge.displayName?.isEmpty == false ? edge.displayName! : edge.edgeId)
                        .font(.bodyMedium.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                if isLive {
                    Text(elapsedString)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
            Spacer(minLength: 0)

            iconButton(systemName: orientationLocked ? "lock.rotation" : "rotate.right") {
                orientationLocked.toggle()
                let mask: UIInterfaceOrientationMask = orientationLocked
                    ? currentOrientationMask()
                    : .allButUpsideDown
                OrientationLock.shared.setMask(mask)
            }
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            statusPill

            Spacer(minLength: 0)

            if case .failed = viewModel.state {
                iconButton(systemName: "arrow.clockwise") {
                    Task { await viewModel.connect(edgeId: edge.edgeId) }
                }
            }

            iconButton(systemName: isLandscapeForced
                ? "arrow.down.right.and.arrow.up.left"
                : "arrow.up.left.and.arrow.down.right") {
                toggleFullscreenOrientation()
            }
        }
    }

    private var liveBadge: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(Color.red)
                .frame(width: 6, height: 6)
            Text("LIVE")
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(.white)
                .tracking(0.5)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(Color.red.opacity(0.85)))
    }

    private var statusPill: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(statusLabel)
                .font(.captionText.weight(.medium))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Capsule().fill(.black.opacity(0.45)))
        .overlay(Capsule().stroke(.white.opacity(0.15), lineWidth: 1))
    }

    private func iconButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(Circle().fill(.black.opacity(0.45)))
                .overlay(Circle().stroke(.white.opacity(0.15), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Derived

    private var isLive: Bool {
        if case .connected = viewModel.state, viewModel.videoTrack != nil { return true }
        return false
    }

    private var statusColor: Color {
        switch viewModel.state {
        case .connected: return Color.successGreen
        case .connecting, .idle: return Color.warningOrange
        case .failed: return Color.errorRed
        case .disconnected: return Color.textTertiary
        }
    }

    private var statusLabel: String {
        switch viewModel.state {
        case .connected: return viewModel.videoTrack == nil ? "等待影像" : "直播中"
        case .connecting, .idle: return "連線中"
        case .failed: return "連線失敗"
        case .disconnected: return "已中斷"
        }
    }

    private var elapsedString: String {
        let h = elapsedSeconds / 3600
        let m = (elapsedSeconds % 3600) / 60
        let s = elapsedSeconds % 60
        return h > 0
            ? String(format: "%02d:%02d:%02d", h, m, s)
            : String(format: "%02d:%02d", m, s)
    }

    // MARK: - Behavior

    private func handleStateChange(_ newState: LiveStreamViewModel.State) {
        if case .connected = newState, viewModel.videoTrack != nil {
            if startedAt == nil { startedAt = Date(); elapsedSeconds = 0 }
            scheduleControlsHide()
        } else {
            startedAt = nil
            elapsedSeconds = 0
            controlsVisible = true
            hideControlsTask?.cancel()
        }
    }

    private func toggleControls() {
        guard isLive else { return }
        withAnimation(.easeInOut(duration: 0.2)) { controlsVisible.toggle() }
        if controlsVisible { scheduleControlsHide() }
    }

    private func scheduleControlsHide() {
        hideControlsTask?.cancel()
        hideControlsTask = Task { [isLiveSnapshot = isLive] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled, isLiveSnapshot else { return }
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.2)) { controlsVisible = false }
            }
        }
    }

    private func toggleFullscreenOrientation() {
        isLandscapeForced.toggle()
        let mask: UIInterfaceOrientationMask = isLandscapeForced ? .landscape : .allButUpsideDown
        let target: UIInterfaceOrientation = isLandscapeForced ? .landscapeRight : .portrait
        OrientationLock.shared.setMask(mask, rotateTo: target)
    }

    private func currentOrientationMask() -> UIInterfaceOrientationMask {
        guard let scene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
        else { return .portrait }
        switch scene.interfaceOrientation {
        case .landscapeLeft: return .landscapeLeft
        case .landscapeRight: return .landscapeRight
        case .portraitUpsideDown: return .portraitUpsideDown
        default: return .portrait
        }
    }
}

