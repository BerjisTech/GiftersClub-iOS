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
    private var trackPollTimer: Timer? = nil

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
        // Poll for track in case delegate signature differs; ensures video eventually binds
        trackPollTimer?.invalidate()
        trackPollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            if self.remoteVideoTrack == nil,
               let first = self.room.remoteParticipants.values.first,
               let vt = first.videoTracks.first?.track as? LiveKit.VideoTrack {
                Task { @MainActor in self.remoteVideoTrack = vt }
            }
        }
    }

    func disconnect() async {
        await room.disconnect()
        self.isConnected = false
        self.remoteVideoTrack = nil
        trackPollTimer?.invalidate(); trackPollTimer = nil
    }

    // No delegate implementation; polling handles binding to minimize SDK signature mismatch issues.
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
