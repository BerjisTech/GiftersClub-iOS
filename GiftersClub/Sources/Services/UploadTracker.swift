import Foundation
import Combine

@MainActor
final class UploadTracker: ObservableObject {
    static let shared = UploadTracker()
    private init() {}

    // postId -> (uploaded count, total count)
    @Published private(set) var postProgress: [String: (uploaded: Int, total: Int)] = [:]

    var postIds: [String] { Array(postProgress.keys) }

    func startPost(id: String, total: Int) {
        guard total > 0 else { return }
        postProgress[id] = (uploaded: 0, total: total)
    }

    func incrementPost(id: String) {
        guard var p = postProgress[id] else { return }
        p.uploaded += 1
        if p.uploaded >= p.total {
            postProgress.removeValue(forKey: id)
        } else {
            postProgress[id] = p
        }
    }

    func finishPost(id: String) {
        postProgress.removeValue(forKey: id)
    }

    func isUploading(postId: String) -> Bool { postProgress[postId] != nil }
}

