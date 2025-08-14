import SwiftUI

struct ProfilePostPagerView: View {
    let profileUsername: String
    let profileName: String?
    let profileAvatar: URL?
    let posts: [SupabaseManager.UserPostMinimal]
    @State var index: Int

    @State private var feedPosts: [FeedPost] = []

    private func mapToFeedPost(_ p: SupabaseManager.UserPostMinimal) -> FeedPost? {
        let mediaURLs: [URL] = (p.media ?? []).compactMap { m in m.url.flatMap(URL.init(string:)) }
        guard !mediaURLs.isEmpty else { return nil }
        let media: FeedPost.Media = {
            if let firstType = p.media?.first?.media_type, firstType == "video", let u = mediaURLs.first { return .video(u) }
            if mediaURLs.count > 1 { return .images(mediaURLs) }
            if let u = mediaURLs.first { return .image(u) }
            return .images([])
        }()
        let author = FeedPost.Author(userId: p.user_id, username: profileUsername, name: profileName, avatarURL: profileAvatar)
        return FeedPost(
            id: p.id,
            author: author,
            caption: "",
            accessType: p.access_type,
            price: p.price,
            media: media,
            likes: 0,
            comments: 0,
            shares: 0,
            isLiked: false
        )
    }

    var body: some View {
        GeometryReader { proxy in
            let fullHeight = proxy.size.height
            VerticalPageView(items: feedPosts, selection: $index) { i, _ in
                PostPageView(post: $feedPosts[i], isActive: index == i, bottomSafeInset: 0, tabBarHeight: 0)
                    .frame(width: proxy.size.width, height: fullHeight)
                    .task { await hydrateIfNeeded(index: i) }
            }
            .frame(width: proxy.size.width, height: fullHeight)
            .background(Color.black.ignoresSafeArea())
            .onAppear { if feedPosts.isEmpty { feedPosts = posts.compactMap(mapToFeedPost) } }
        }
    }

    private func hydrateIfNeeded(index i: Int) async {
        guard i >= 0 && i < feedPosts.count else { return }
        let postId = feedPosts[i].id
        // Avoid re-fetch if caption already loaded (simple check)
        if !feedPosts[i].caption.isEmpty { return }
        do {
            let content = try await SupabaseManager.shared.fetchPostContent(postId: postId) ?? ""
            let likes = (try? await SupabaseManager.shared.likeCount(postId: postId)) ?? 0
            let comments = (try? await SupabaseManager.shared.commentCount(postId: postId)) ?? 0
            await MainActor.run {
                let old = feedPosts[i]
                feedPosts[i] = FeedPost(
                    id: old.id,
                    author: old.author,
                    caption: content,
                    accessType: old.accessType,
                    price: old.price,
                    media: old.media,
                    likes: likes,
                    comments: comments,
                    shares: old.shares,
                    isLiked: old.isLiked
                )
            }
        } catch {
            // ignore; show defaults
        }
    }
}
