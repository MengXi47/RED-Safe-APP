// SPM dependency required: https://github.com/livekit/webrtc-xcframework.git
// Add via Xcode → File → Add Package Dependencies → paste the URL above.

import SwiftUI

#if canImport(LiveKitWebRTC) && canImport(UIKit)
import LiveKitWebRTC

/// 將 LKRTCMTLVideoView 包裝為 SwiftUI View，用於顯示 WebRTC 視訊串流。
struct WebRTCVideoView: UIViewRepresentable {
    let videoTrack: LKRTCVideoTrack

    func makeUIView(context: Context) -> LKRTCMTLVideoView {
        let view = LKRTCMTLVideoView()
        view.videoContentMode = .scaleAspectFit
        view.clipsToBounds = true
        videoTrack.add(view)
        return view
    }

    func updateUIView(_ uiView: LKRTCMTLVideoView, context: Context) {
        // 當 videoTrack 變更時重新綁定
    }

    static func dismantleUIView(_ uiView: LKRTCMTLVideoView, coordinator: ()) {
        // LKRTCMTLVideoView 會在 dealloc 時自行清理
    }
}

#else

/// 在無法匯入 WebRTC 的平台上提供簡單的占位 View，避免建置失敗。
struct WebRTCVideoView: View {
    var body: some View {
        ZStack {
            Color.black
            Text("WebRTC 視訊不支援此平台")
                .foregroundColor(.white)
                .font(.body)
        }
    }
}

#endif
