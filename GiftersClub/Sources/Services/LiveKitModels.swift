import Foundation

#if canImport(LiveKit)
import LiveKit

struct LKRemoteVideo: Identifiable, Equatable {
    let id: String
    let track: LiveKit.VideoTrack
    let identity: String?
    static func == (lhs: LKRemoteVideo, rhs: LKRemoteVideo) -> Bool { lhs.id == rhs.id }
}
#endif

