// SPM dependency required: https://github.com/livekit/webrtc-xcframework.git
// Add via Xcode → File → Add Package Dependencies → paste the URL above.

import Foundation

#if canImport(LiveKitWebRTC)
import LiveKitWebRTC

/// 管理即時影像串流的完整生命週期：建立 offer → 送出 Edge 指令 → 輪詢 SSE 取得 answer → 建立連線。
@MainActor
final class LiveStreamViewModel: ObservableObject {
    enum State: Equatable {
        case idle
        case connecting
        case connected
        case failed(String)
        case disconnected

        static func == (lhs: State, rhs: State) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle),
                 (.connecting, .connecting),
                 (.connected, .connected),
                 (.disconnected, .disconnected):
                return true
            case (.failed(let a), .failed(let b)):
                return a == b
            default:
                return false
            }
        }
    }

    @Published var state: State = .idle
    @Published var videoTrack: LKRTCVideoTrack?

    private let webRTCClient = WebRTCClient()

    /// 建立即時影像連線。
    /// 流程：createOffer → POST edge command (code "201") → SSE poll → setRemoteAnswer
    func connect(edgeId: String) async {
        state = .connecting

        do {
            // 1. 建立 offer SDP
            let offerSDP = try await webRTCClient.createOffer()

            // 2. 透過 Edge 指令送出 offer
            let payload = WebRTCOfferPayload(sdp: offerSDP)
            let command = try await APIClient.shared.sendEdgeCommand(
                edgeId: edgeId,
                code: "201",
                payload: payload
            )

            // 3. 透過 SSE 輪詢取得 answer
            let result: EdgeCommandResultDTO<WebRTCAnswerResult> = try await APIClient.shared
                .fetchEdgeCommandResult(traceId: command.traceId)

            guard let answerResult = result.result else {
                state = .failed(result.errorMessage ?? "未收到遠端回應")
                return
            }

            // 4. 設定遠端 answer
            try await webRTCClient.setRemoteAnswer(answerResult.sdp)

            // 5. 觀察 videoTrack
            videoTrack = webRTCClient.videoTrack
            state = .connected

            // 持續觀察 videoTrack 變化
            observeVideoTrack()
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// 斷開連線。
    func disconnect() {
        webRTCClient.disconnect()
        videoTrack = nil
        state = .disconnected
    }

    private func observeVideoTrack() {
        // 若建連後 track 尚未就緒，透過 Task 持續觀察
        Task { [weak self] in
            guard let self else { return }
            for _ in 0..<50 { // 最多等 5 秒
                if let track = webRTCClient.videoTrack {
                    self.videoTrack = track
                    return
                }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
    }
}

#else

/// 在無法匯入 WebRTC 的平台上提供無操作的替代實作，避免建置失敗。
@MainActor
final class LiveStreamViewModel: ObservableObject {
    enum State: Equatable {
        case idle
        case connecting
        case connected
        case failed(String)
        case disconnected

        static func == (lhs: State, rhs: State) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle),
                 (.connecting, .connecting),
                 (.connected, .connected),
                 (.disconnected, .disconnected):
                return true
            case (.failed(let a), .failed(let b)):
                return a == b
            default:
                return false
            }
        }
    }

    @Published var state: State = .failed("WebRTC 不支援此平台或未正確連結套件")
    @Published var videoTrack: AnyObject?

    func connect(edgeId: String) async {
        state = .failed("WebRTC 不支援此平台或未正確連結套件")
    }

    func disconnect() {
        videoTrack = nil
        state = .disconnected
    }
}

#endif
