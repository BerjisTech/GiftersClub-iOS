import Foundation
import Combine
import SwiftUI

#if canImport(LiveKit)
import LiveKit

@MainActor
final class LiveKitViewer: NSObject, ObservableObject, RoomDelegate {
    @Published var isConnected: Bool = false
    @Published var remoteVideoTrack: LiveKit.VideoTrack?
    @Published var remoteVideoTracks: [LiveKit.VideoTrack] = []
    @Published var remoteVideos: [LKRemoteVideo] = []
    @Published var localVideoTrack: LiveKit.VideoTrack?
    @Published var remoteAudioEnabled: Bool = true

    private let room = Room()
    private var trackPollTimer: Timer? = nil
    // Callback for lightweight data messages like {"type":"tap"}
    var onData: ((String) -> Void)? = nil

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
            Task { @MainActor in
                guard let self else { return }
                // primary for backward UI
                if self.remoteVideoTrack == nil,
                   let first = self.room.remoteParticipants.values.first,
                   let vt = first.videoTracks.first?.track as? LiveKit.VideoTrack {
                    self.remoteVideoTrack = vt
                }
                // collect all remote tracks for multi-host grid + identities
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

    // LiveKit RoomDelegate: receive data messages from participants
    func room(_ room: Room, didReceive data: Data, participant: RemoteParticipant?) {
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let type = obj["type"] as? String {
            onData?(type)
        }
    }

    func disconnect() async {
        await room.disconnect()
        self.isConnected = false
        self.remoteVideoTrack = nil
        self.remoteVideoTracks = []
        self.remoteVideos = []
        self.localVideoTrack = nil
        trackPollTimer?.invalidate(); trackPollTimer = nil
    }

    /// Send a lightweight tap signal over LiveKit data channel so all participants can animate hearts.
    func sendTap() {
        let obj: [String: Any] = ["type": "tap", "ts": Int(Date().timeIntervalSince1970)]
        if let data = try? JSONSerialization.data(withJSONObject: obj) {
            Task { try? await room.localParticipant.publish(data: data) }
        }
    }

    /// Upgrade from viewer to guest publisher (disconnect and reconnect with guest token)
    func upgradeToGuest(url: URL, token: String) async throws {
        await room.disconnect()
        try await room.connect(url: url.absoluteString, token: token)
        self.isConnected = true
        try await room.localParticipant.setMicrophone(enabled: true)
        try await room.localParticipant.setCamera(enabled: true)
        self.localVideoTrack = self.room.localParticipant.videoTracks.first?.track as? LiveKit.VideoTrack
        // start polling again
        trackPollTimer?.invalidate()
        trackPollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if self.remoteVideoTrack == nil,
                   let first = self.room.remoteParticipants.values.first,
                   let vt = first.videoTracks.first?.track as? LiveKit.VideoTrack {
                    self.remoteVideoTrack = vt
                }
                var tracks: [LiveKit.VideoTrack] = []
                for p in self.room.remoteParticipants.values {
                    for pub in p.videoTracks { if let t = pub.track as? LiveKit.VideoTrack { tracks.append(t) } }
                }
                if tracks.map({ ObjectIdentifier($0) }) != self.remoteVideoTracks.map({ ObjectIdentifier($0) }) {
                    self.remoteVideoTracks = tracks
                }
            }
        }
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
