// SPM dependency required: https://github.com/livekit/webrtc-xcframework.git
// Add via Xcode → File → Add Package Dependencies → paste the URL above.

import Foundation

#if canImport(LiveKitWebRTC)
import LiveKitWebRTC

/// 封裝 WebRTC peer connection 的建立與管理，提供 async/await 介面給 ViewModel 使用。
@MainActor
final class WebRTCClient: NSObject, ObservableObject {
    @Published var videoTrack: LKRTCVideoTrack?

    private var peerConnectionFactory: LKRTCPeerConnectionFactory?
    private var peerConnection: LKRTCPeerConnection?
    private var gatheringContinuation: CheckedContinuation<Void, Never>?

    override init() {
        super.init()
        LKRTCInitializeSSL()
        let decoderFactory = LKRTCDefaultVideoDecoderFactory()
        let encoderFactory = LKRTCDefaultVideoEncoderFactory()
        peerConnectionFactory = LKRTCPeerConnectionFactory(
            encoderFactory: encoderFactory,
            decoderFactory: decoderFactory
        )
    }

    /// 建立 PeerConnection、新增 recvOnly video transceiver (偏好 H264)、
    /// 產生 offer 並等待 ICE gathering 完成，回傳完整 SDP。
    func createOffer() async throws -> String {
        guard let factory = peerConnectionFactory else {
            throw WebRTCError.factoryNotInitialized
        }

        let config = LKRTCConfiguration()
        config.iceServers = [
            LKRTCIceServer(urlStrings: ["stun:stun.l.google.com:19302"])
        ]
        config.sdpSemantics = .unifiedPlan

        let constraints = LKRTCMediaConstraints(
            mandatoryConstraints: nil,
            optionalConstraints: nil
        )

        guard let pc = factory.peerConnection(
            with: config,
            constraints: constraints,
            delegate: self
        ) else {
            throw WebRTCError.peerConnectionCreationFailed
        }

        peerConnection = pc

        // recvOnly video transceiver
        let transceiverInit = LKRTCRtpTransceiverInit()
        transceiverInit.direction = .recvOnly

        pc.addTransceiver(of: .video, init: transceiverInit)

        // Create offer
        let offerConstraints = LKRTCMediaConstraints(
            mandatoryConstraints: [
                "OfferToReceiveVideo": "true",
                "OfferToReceiveAudio": "false"
            ],
            optionalConstraints: nil
        )

        let offer = try await pc.offer(for: offerConstraints)
        try await pc.setLocalDescription(offer)

        // 等待 ICE gathering 完成
        if pc.iceGatheringState != .complete {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                gatheringContinuation = continuation
            }
        }

        guard let localDescription = pc.localDescription else {
            throw WebRTCError.noLocalDescription
        }

        return localDescription.sdp
    }

    /// 設定遠端 answer SDP。
    func setRemoteAnswer(_ sdp: String) async throws {
        guard let pc = peerConnection else {
            throw WebRTCError.peerConnectionNotEstablished
        }

        let answer = LKRTCSessionDescription(type: .answer, sdp: sdp)
        try await pc.setRemoteDescription(answer)
    }

    /// 斷開連線並釋放資源。
    func disconnect() {
        peerConnection?.close()
        peerConnection = nil
        videoTrack = nil
    }

    deinit {
        peerConnection?.close()
        LKRTCCleanupSSL()
    }
}

// MARK: - LKRTCPeerConnectionDelegate

extension WebRTCClient: LKRTCPeerConnectionDelegate {
    nonisolated func peerConnection(_ peerConnection: LKRTCPeerConnection, didChange stateChanged: LKRTCSignalingState) {}

    nonisolated func peerConnection(_ peerConnection: LKRTCPeerConnection, didAdd stream: LKRTCMediaStream) {
        guard let track = stream.videoTracks.first else { return }
        Task { @MainActor in
            self.videoTrack = track
        }
    }

    nonisolated func peerConnection(_ peerConnection: LKRTCPeerConnection, didRemove stream: LKRTCMediaStream) {}

    nonisolated func peerConnectionShouldNegotiate(_ peerConnection: LKRTCPeerConnection) {}

    nonisolated func peerConnection(_ peerConnection: LKRTCPeerConnection, didChange newState: LKRTCIceConnectionState) {}

    nonisolated func peerConnection(_ peerConnection: LKRTCPeerConnection, didChange newState: LKRTCIceGatheringState) {
        if newState == .complete {
            Task { @MainActor in
                self.gatheringContinuation?.resume()
                self.gatheringContinuation = nil
            }
        }
    }

    nonisolated func peerConnection(_ peerConnection: LKRTCPeerConnection, didGenerate candidate: LKRTCIceCandidate) {}

    nonisolated func peerConnection(_ peerConnection: LKRTCPeerConnection, didRemove candidates: [LKRTCIceCandidate]) {}

    nonisolated func peerConnection(_ peerConnection: LKRTCPeerConnection, didOpen dataChannel: LKRTCDataChannel) {}

    nonisolated func peerConnection(_ peerConnection: LKRTCPeerConnection, didAdd rtpReceiver: LKRTCRtpReceiver, streams mediaStreams: [LKRTCMediaStream]) {
        guard let track = rtpReceiver.track as? LKRTCVideoTrack else { return }
        Task { @MainActor in
            self.videoTrack = track
        }
    }
}

// MARK: - Error

enum WebRTCError: Error, LocalizedError {
    case factoryNotInitialized
    case peerConnectionCreationFailed
    case peerConnectionNotEstablished
    case noLocalDescription

    var errorDescription: String? {
        switch self {
        case .factoryNotInitialized:
            return "WebRTC 工廠尚未初始化"
        case .peerConnectionCreationFailed:
            return "無法建立 PeerConnection"
        case .peerConnectionNotEstablished:
            return "PeerConnection 尚未建立"
        case .noLocalDescription:
            return "無法取得本地 SDP"
        }
    }
}

#else

@MainActor
final class WebRTCClient: NSObject, ObservableObject {
    @Published var videoTrack: AnyObject?

    func createOffer() async throws -> String {
        throw WebRTCUnavailableError()
    }

    func setRemoteAnswer(_ sdp: String) async throws {
        throw WebRTCUnavailableError()
    }

    func disconnect() {}
}

struct WebRTCUnavailableError: LocalizedError {
    var errorDescription: String? {
        "WebRTC 不支援此平台或未正確連結套件"
    }
}

#endif
