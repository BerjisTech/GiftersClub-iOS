import Foundation
import Combine
import SwiftUI

#if canImport(LiveKit)
import LiveKit

@MainActor
final class LiveKitPublisher: NSObject, ObservableObject, RoomDelegate {
    @Published var isConnected: Bool = false
    @Published var cameraOn: Bool = false
    @Published var micOn: Bool = false
    @Published var localVideoTrack: VideoTrack?
    @Published var remoteVideoTracks: [LiveKit.VideoTrack] = []
    @Published var remoteVideos: [LKRemoteVideo] = []
    @Published var isFront: Bool = true
    @Published var beautyOn: Bool = false

    let room = Room()
    private var trackPollTimer: Timer? = nil
    var onData: ((String) -> Void)? = nil

    override init() {
        super.init()
        room.add(delegate: self)
    }

    func connectAndPublish(url: URL, token: String) async throws {
        try await room.connect(url: url.absoluteString, token: token)
        try await room.localParticipant.setMicrophone(enabled: true)
        try await room.localParticipant.setCamera(enabled: true)
        self.isConnected = true
        self.micOn = true
        self.cameraOn = true
        self.localVideoTrack = self.room.localParticipant.videoTracks.first?.track as? LiveKit.VideoTrack
        startTrackPolling()
    }

    func toggleMic() async {
        do {
            let newValue = !micOn
            try await room.localParticipant.setMicrophone(enabled: newValue)
            self.micOn = newValue
        } catch { }
    }
    func toggleCamera() async {
        do {
            let newValue = !cameraOn
            try await room.localParticipant.setCamera(enabled: newValue)
            self.cameraOn = newValue
            self.localVideoTrack = self.room.localParticipant.videoTracks.first?.track as? LiveKit.VideoTrack
        } catch { }
    }

    func switchCamera() async {
        do {
            // Fallback approach: disable and re-enable camera; many SDKs will flip default device
            try await room.localParticipant.setCamera(enabled: false)
            try await room.localParticipant.setCamera(enabled: true)
            self.isFront.toggle()
            self.localVideoTrack = self.room.localParticipant.videoTracks.first?.track as? LiveKit.VideoTrack
        } catch { }
    }

    func setBeautyFilter(enabled: Bool) {
        // Placeholder: wire up custom video source with filter pipeline if available
        self.beautyOn = enabled
        // In a future iteration, attach a CIFilter-based pipeline or ARKit face beautification
    }

    func disconnect() async {
        await room.disconnect()
        self.isConnected = false
        self.localVideoTrack = nil
        self.micOn = false
        self.cameraOn = false
        self.remoteVideoTracks = []
        self.remoteVideos = []
        trackPollTimer?.invalidate(); trackPollTimer = nil
    }

    // RoomDelegate methods are optional; we rely on direct state after publish/toggles.
    func room(_ room: Room, didReceive data: Data, participant: RemoteParticipant?) {
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let type = obj["type"] as? String {
            onData?(type)
        }
    }

    private func startTrackPolling() {
        trackPollTimer?.invalidate()
        trackPollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                var tracks: [LiveKit.VideoTrack] = []
                var videos: [LKRemoteVideo] = []
                for p in self.room.remoteParticipants.values {
                    for pub in p.videoTracks {
                        if let t = pub.track as? LiveKit.VideoTrack {
                            tracks.append(t)
                            // Build a stable id by coercing types to String
                            let sidStr = pub.track?.sid.map { String(describing: $0) } ?? UUID().uuidString
                            let identityForId = p.identity.map { String(describing: $0) } ?? ""
                            let rid = sidStr + identityForId
                            let identityValue: String? = p.identity.map { String(describing: $0) }
                            videos.append(LKRemoteVideo(id: rid, track: t, identity: identityValue))
                        }
                    }
                }
                if tracks.map({ ObjectIdentifier($0) }) != self.remoteVideoTracks.map({ ObjectIdentifier($0) }) {
                    self.remoteVideoTracks = tracks
                }
                self.remoteVideos = videos
            }
        }
    }
}

struct LKVideoView: UIViewRepresentable {
    let track: LiveKit.VideoTrack?
    func makeUIView(context: Context) -> LiveKit.VideoView {
        let v = LiveKit.VideoView()
        v.contentMode = .scaleAspectFit
        return v
    }
    func updateUIView(_ uiView: LiveKit.VideoView, context: Context) {
        uiView.contentMode = .scaleAspectFit
        uiView.track = track
    }
}

#else

final class LiveKitPublisher: NSObject, ObservableObject {
    @Published var isConnected: Bool = false
    @Published var cameraOn: Bool = false
    @Published var micOn: Bool = false
    @Published var localVideoTrack: Any?

    func connectAndPublish(url: URL, token: String) async throws {
        throw NSError(domain: "LiveKit", code: -1, userInfo: [NSLocalizedDescriptionKey: "LiveKit package not linked to target"])
    }
    func toggleMic() async {}
    func toggleCamera() async {}
    func disconnect() async {}
}

struct LKVideoView: View {
    let track: Any?
    var body: some View { Color.black }
}

#endif
