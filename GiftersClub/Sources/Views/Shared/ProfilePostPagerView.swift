import SwiftUI

struct ProfilePostPagerView: View {
    let profileUsername: String
    let profileName: String?
    let profileAvatar: URL?
    let posts: [SupabaseManager.UserPostMinimal]
    @State var index: Int

    private func model(for post: SupabaseManager.UserPostMinimal) -> PostViewerModel? {
        // Build media
        let mediaURLs: [URL] = (post.media ?? []).compactMap { m in
            m.url.flatMap(URL.init(string:))
        }
        guard !mediaURLs.isEmpty else { return nil }
        let media: PostViewerModel.Media = {
            if let firstType = post.media?.first?.media_type, firstType == "video", let u = mediaURLs.first {
                return .video(u)
            }
            if mediaURLs.count == 1, let u = mediaURLs.first { return .image(u) }
            return .images(mediaURLs)
        }()
        return PostViewerModel(
            id: post.id,
            authorUsername: profileUsername,
            authorName: profileName,
            authorAvatar: profileAvatar,
            caption: "",
            media: media
        )
    }

    var body: some View {
        let models: [PostViewerModel] = posts.compactMap(model(for:))
        VerticalPageView(items: models, selection: $index) { i, m in
            PostViewer(model: m)
        }
        .background(Color.black.ignoresSafeArea())
    }
}
