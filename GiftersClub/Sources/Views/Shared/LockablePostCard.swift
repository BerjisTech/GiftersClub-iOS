import SwiftUI

struct LockablePostCard: View {
    enum MediaKind { case image(URL), video(URL) }
    let postId: String
    let authorUserId: String
    let accessType: String?
    let price: Int?
    let media: MediaKind?
    let isLong: Bool
    var onTapUnlocked: (() -> Void)? = nil

    @ObservedObject private var supabase = SupabaseManager.shared
    @State private var hasAccess: Bool
    @State private var showPaywall: Bool = false

    init(postId: String,
         authorUserId: String,
         accessType: String?,
         price: Int?,
         media: MediaKind?,
         isLong: Bool = false,
         onTapUnlocked: (() -> Void)? = nil) {
        self.postId = postId
        self.authorUserId = authorUserId
        self.accessType = accessType
        self.price = price
        self.media = media
        self.isLong = isLong
        self.onTapUnlocked = onTapUnlocked
        self._hasAccess = State(initialValue: (accessType ?? "free") == "free")
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            content
                .blur(radius: hasAccess ? 0 : 12)
                .overlay { if !hasAccess { RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.35)) } }
                .clipShape(RoundedRectangle(cornerRadius: 12))

            if !hasAccess { Image(systemName: "lock.fill").foregroundStyle(.white).padding(6) }
        }
        .contentShape(Rectangle())
        .onTapGesture { Task { await handleTap() } }
        .task { await initialCheck() }
        .sheet(isPresented: $showPaywall) {
            if accessType == "subscription" {
                PaywallSheet(mode: .subscription(creatorId: authorUserId), onUnlocked: { hasAccess = true; onTapUnlocked?() })
            } else if accessType == "paid" {
                PaywallSheet(mode: .paid(postId: postId, price: price ?? 0), onUnlocked: { hasAccess = true; onTapUnlocked?() })
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch media {
        case .some(.image(let url)):
            GeometryReader { geo in
                AsyncImage(url: url) { img in
                    img.resizable().scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                } placeholder: { Color(.secondarySystemBackground) }
            }
            .frame(height: isLong ? 220 : 200)
        case .some(.video(let url)):
            GeometryReader { geo in
                VideoThumbnail(url: url)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
            }
            .frame(height: isLong ? 220 : 200)
            .overlay(alignment: .center) { Image(systemName: "play.circle.fill").font(.system(size: 36)).foregroundStyle(.white) }
        case .none:
            Color(.secondarySystemBackground)
                .frame(height: isLong ? 220 : 200)
        }
    }

    private func initialCheck() async {
        let type = accessType ?? "free"
        if type == "free" { hasAccess = true; return }
        do {
            if type == "paid" {
                hasAccess = try await supabase.hasPostAccess(postId: postId)
            } else if type == "subscription" {
                hasAccess = try await supabase.hasSubscription(to: authorUserId)
            }
        } catch { hasAccess = false }
    }

    private func handleTap() async {
        if hasAccess { onTapUnlocked?(); return }
        let type = accessType ?? "free"
        guard type != "free" else { onTapUnlocked?(); return }
        do {
            if type == "paid" {
                let has = try await supabase.hasPostAccess(postId: postId)
                if has { hasAccess = true; onTapUnlocked?() } else { showPaywall = true }
            } else if type == "subscription" {
                let has = try await supabase.hasSubscription(to: authorUserId)
                if has { hasAccess = true; onTapUnlocked?() } else { showPaywall = true }
            }
        } catch { showPaywall = true }
    }
}

