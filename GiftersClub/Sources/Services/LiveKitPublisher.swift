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
    @Published var isFront: Bool = true

    let room = Room()

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

    func disconnect() async {
        await room.disconnect()
        self.isConnected = false
        self.localVideoTrack = nil
        self.micOn = false
        self.cameraOn = false
    }

    // RoomDelegate methods are optional; we rely on direct state after publish/toggles.
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
