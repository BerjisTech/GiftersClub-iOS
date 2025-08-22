import Foundation
import SwiftUI
import PhotosUI

enum PostAccessType: String, CaseIterable, Identifiable {
    case free
    case subscription
    case paid
    var id: String { rawValue }
    var title: String {
        switch self {
        case .free: return "Free for all"
        case .subscription: return "Subscribers only"
        case .paid: return "Paid one-time"
        }
    }
}

final class CreatePostViewModel: ObservableObject {
    struct MediaItem: Identifiable, Hashable {
        enum Kind: String { case photo, video }
        let id = UUID()
        let data: Data
        let mime: String
        let kind: Kind
    }

    @Published var caption: String = ""
    @Published var accessType: PostAccessType = .free
    @Published var priceText: String = ""
    @Published var selectedPickerItems: [PhotosPickerItem] = []
    @Published var media: [MediaItem] = []
    @Published var isPosting: Bool = false
    @Published var errorMessage: String? = nil
    // Subscription plan scope for subscription-only posts
    @Published var availablePlans: [SupabaseManager.DBSubscriptionPlan] = []
    @Published var selectedPlanId: String? = nil // nil = All subscribers

    // Text post canvas rendered image placeholder (treated as photo)
    func addRenderedTextImage(_ image: UIImage) {
        if let data = image.jpegData(compressionQuality: 0.9) {
            let item = MediaItem(data: data, mime: "image/jpeg", kind: .photo)
            self.media = [item] // single image for text post
        }
    }

    func loadPickerItems() {
        Task {
            var tmp: [MediaItem] = []
            for item in selectedPickerItems {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    let utType = item.supportedContentTypes.first
                    let mime = utType?.preferredMIMEType ?? "application/octet-stream"
                    let kind: MediaItem.Kind = (mime.hasPrefix("video/")) ? .video : .photo
                    tmp.append(MediaItem(data: data, mime: mime, kind: kind))
                }
            }
            let result = tmp
            await MainActor.run { self.media = result }
        }
    }

    func publish(onSuccess: @escaping (String) -> Void) {
        Task {
            await MainActor.run { isPosting = true; errorMessage = nil }
            defer { Task { await MainActor.run { isPosting = false } } }
            do {
                let postId = try await createPostRow()
                // Upload media in order
                for (idx, m) in media.enumerated() {
                    let filename = "\(postId)-\(Int(Date().timeIntervalSince1970))-\(idx).\(fileExtension(for: m.mime))"
                    let publicUrl = try await SupabaseManager.shared.uploadMedia(bytes: m.data, fileName: filename, mimeType: m.mime, bucket: "post")
                    _ = try await SupabaseManager.shared.insertPostMedia(postId: postId, mediaType: m.kind == .video ? "video" : "photo", url: publicUrl, order: idx)
                }
                await MainActor.run { onSuccess(postId) }
            } catch {
                await MainActor.run { self.errorMessage = "Failed to create post" }
            }
        }
    }

    private func createPostRow() async throws -> String {
        let type = accessType.rawValue
        let price: Int? = accessType == .paid ? Int(priceText) : nil
        let requiredPlanId: String? = (accessType == .subscription) ? selectedPlanId : nil
        guard let post = try await SupabaseManager.shared.createPost(content: caption, accessType: type, price: price, requiredPlanId: requiredPlanId) else {
            throw URLError(.badServerResponse)
        }
        return post.id
    }

    private func fileExtension(for mime: String) -> String {
        if mime.hasPrefix("image/") { return "jpg" }
        if mime.hasPrefix("video/") { return "mp4" }
        return "bin"
    }
}
