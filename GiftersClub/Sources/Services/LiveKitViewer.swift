import Foundation
import Combine
import SwiftUI

#if canImport(LiveKit)
import LiveKit

@MainActor
final class LiveKitViewer: NSObject, ObservableObject, RoomDelegate {
    @Published var isConnected: Bool = false
    @Published var remoteVideoTrack: LiveKit.VideoTrack?
    @Published var remoteAudioEnabled: Bool = true

    private let room = Room()

    override init() {
        super.init()
        room.add(delegate: self)
    }

    func connect(url: URL, token: String) async throws {
        try await room.connect(url: url.absoluteString, token: token)
        self.isConnected = true
        // Bind first available remote video track if present
        if let firstParticipant = room.remoteParticipants.values.first,
           let vt = firstParticipant.videoTracks.first?.track as? LiveKit.VideoTrack {
            self.remoteVideoTrack = vt
        }
    }

    func disconnect() async {
        await room.disconnect()
        self.isConnected = false
        self.remoteVideoTrack = nil
    }

    // MARK: - RoomDelegate
    // Delegate: publication subscribed -> bind video track
    func room(_ room: Room, participant: RemoteParticipant, didSubscribeTrack publication: TrackPublication) {
        if let vt = publication.track as? LiveKit.VideoTrack {
            Task { @MainActor in self.remoteVideoTrack = vt }
        }
    }
}

#else

@MainActor
final class LiveKitViewer: NSObject, ObservableObject {
    @Published var isConnected: Bool = false
    @Published var remoteVideoTrack: Any?
    func connect(url: URL, token: String) async throws {
        throw NSError(domain: "LiveKit", code: -1, userInfo: [NSLocalizedDescriptionKey: "LiveKit package not linked to target"])
    }
    func disconnect() async { }
}

#endif
