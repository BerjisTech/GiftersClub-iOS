import Foundation
import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
@preconcurrency import AVFoundation

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
    @Published var isLoadingMedia: Bool = false
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
            await MainActor.run { self.isLoadingMedia = true }
            var tmp: [MediaItem] = []
            for item in selectedPickerItems {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    await Task.yield()
                    let utType = item.supportedContentTypes.first
                    let initialMime = utType?.preferredMIMEType ?? "application/octet-stream"
                    let isVideo = initialMime.hasPrefix("video/")
                    if isVideo && initialMime != "video/mp4" {
                        // Transcode locally to MP4 (H.264/AAC) for maximum iOS compatibility
                        if let mp4 = await transcodeToMP4(data: data, suggestedType: utType) {
                            tmp.append(MediaItem(data: mp4, mime: "video/mp4", kind: .video))
                        } else {
                            tmp.append(MediaItem(data: data, mime: initialMime, kind: .video))
                        }
                    } else if initialMime == "image/heic" || initialMime == "image/heif" || initialMime == "image/heif-sequence" {
                        // Convert HEIC/HEIF stills to JPEG for compatibility on older devices / services
                        autoreleasepool {
                            if let img = UIImage(data: data), let jpeg = img.jpegData(compressionQuality: 0.9) {
                                tmp.append(MediaItem(data: jpeg, mime: "image/jpeg", kind: .photo))
                            } else {
                                tmp.append(MediaItem(data: data, mime: initialMime, kind: .photo))
                            }
                        }
                    } else {
                        let kind: MediaItem.Kind = isVideo ? .video : .photo
                        tmp.append(MediaItem(data: data, mime: initialMime, kind: kind))
                    }
                }
            }
            let result = tmp
            await MainActor.run {
                self.media = result
                self.isLoadingMedia = false
            }
        }
    }

    func publish(onSuccess: @escaping (String) -> Void) {
        Task {
            await MainActor.run { isPosting = true; errorMessage = nil }
            do {
                let postId = try await createPostRow()
                // Register background upload tracking for profile shimmer
                await UploadTracker.shared.startPost(id: postId, total: media.count)
                // Kick off uploads in background without blocking UI
                for (idx, m) in media.enumerated() {
                    Task.detached {
                        let filename = "\(postId)-\(Int(Date().timeIntervalSince1970))-\(idx).\(self.fileExtension(for: m.mime))"
                        if let publicUrl = try? await SupabaseManager.shared.uploadMedia(bytes: m.data, fileName: filename, mimeType: m.mime, bucket: "post") {
                            _ = try? await SupabaseManager.shared.insertPostMedia(postId: postId, mediaType: m.kind == .video ? "video" : "photo", url: publicUrl, order: idx)
                            await UploadTracker.shared.incrementPost(id: postId)
                        }
                    }
                }
                await MainActor.run { onSuccess(postId); isPosting = false }
            } catch {
                await MainActor.run { self.errorMessage = "Failed to create post"; isPosting = false }
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
        // Map common MIME types to appropriate extensions
        switch mime.lowercased() {
        case "image/jpeg", "image/jpg": return "jpg"
        case "image/png": return "png"
        case "image/heic": return "heic"
        case "video/mp4", "video/h264": return "mp4"
        case "video/quicktime": return "mov"
        case "video/hevc": return "mov" // HEVC typically in .mov container from Photos
        default:
            if mime.hasPrefix("image/") { return "jpg" }
            if mime.hasPrefix("video/") { return "mp4" }
            return "bin"
        }
    }

    // MARK: - Local transcoding to MP4 for iOS compatibility
    @MainActor
    private func transcodeToMP4(data: Data, suggestedType: UTType?) async -> Data? {
        // Write to a temporary file so AVAsset can read it
        let ext = suggestedType?.preferredFilenameExtension ?? "mov"
        let inputURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("in_\(UUID().uuidString).\(ext)")
        do { try data.write(to: inputURL, options: .atomic) } catch { return nil }
        let asset = AVAsset(url: inputURL)
        // Build a composition to normalize orientation and timescale
        let comp = AVMutableComposition()
        var duration: CMTime = .zero
        var transform: CGAffineTransform = .identity
        var vTrack: AVAssetTrack?
        var aTrack: AVAssetTrack?
        if #available(iOS 16.0, *) {
            do {
                let vts = try await asset.loadTracks(withMediaType: .video)
                vTrack = vts.first
                duration = try await asset.load(.duration)
                if let vt = vTrack { transform = (try? await vt.load(.preferredTransform)) ?? .identity }
                let ats = try await asset.loadTracks(withMediaType: .audio)
                aTrack = ats.first
            } catch {
                // If async loads fail on iOS 16+, gracefully abort transcoding using original data
                return try? Data(contentsOf: inputURL)
            }
        } else {
            vTrack = asset.tracks(withMediaType: .video).first
            aTrack = asset.tracks(withMediaType: .audio).first
            duration = asset.duration
            transform = vTrack?.preferredTransform ?? .identity
        }
        guard let videoTrack = vTrack,
              let compVideo = comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            return try? Data(contentsOf: inputURL)
        }
        compVideo.preferredTransform = transform
        do {
            try compVideo.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: videoTrack, at: .zero)
        } catch {
            return nil
        }
        if let audioTrack = aTrack,
           let compAudio = comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
            _ = try? compAudio.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: audioTrack, at: .zero)
        }
        // Export to MP4 (H.264/AAC) using a safe preset
        let preset = AVAssetExportPreset1280x720
        guard let session = AVAssetExportSession(asset: comp, presetName: preset) else { return nil }
        let outputURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("out_\(UUID().uuidString).mp4")
        session.outputURL = outputURL
        session.outputFileType = .mp4
        session.shouldOptimizeForNetworkUse = true
        final class SendableBox<T>: @unchecked Sendable { var value: T; init(_ v: T) { value = v } }
        let box = SendableBox(session)
        return await withCheckedContinuation { cont in
            box.value.exportAsynchronously { [inputURL, outputURL] in
                defer {
                    try? FileManager.default.removeItem(at: inputURL)
                    try? FileManager.default.removeItem(at: outputURL)
                }
                guard box.value.status == .completed else { cont.resume(returning: nil); return }
                let data = try? Data(contentsOf: outputURL)
                cont.resume(returning: data)
            }
        }
    }
}
