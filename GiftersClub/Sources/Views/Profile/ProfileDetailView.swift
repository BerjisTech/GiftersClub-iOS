import SwiftUI

struct ProfileModel: Identifiable, Hashable {
    var id: String { userId }
    let userId: String
    let username: String
    let name: String
    let bio: String
    let imageURL: URL?
    let followers: Int
    let following: Int
    let isCurrentUser: Bool
    var isFollowing: Bool
    var isFollowedBy: Bool
}

enum ProfileTab: String, CaseIterable, Hashable { case posts = "Posts", wishlists = "Wishlists", gifts = "Gifts" }
enum GiftsSort: String, CaseIterable { case newest = "Newest", popular = "Popular", priceAsc = "Price ↑", priceDesc = "Price ↓" }

struct ProfileDetailView: View {
    // Input: if nil, load current user
    var username: String?
    var userId: String?

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var banners: BannerQueue
    @EnvironmentObject private var drawer: DrawerManager
    @ObservedObject private var supabase = SupabaseManager.shared

    @State private var profile: ProfileModel?
    @State private var isLoading = true
    @State private var activeTab: ProfileTab = .posts
    @State private var giftsSort: GiftsSort = .newest
    @State private var postThumbs: [URL] = []
    @State private var wishlists: [SupabaseManager.DBWishlist] = []
    @State private var gifts: [SupabaseManager.DBGift] = []
    @State private var showAccount = false
    @State private var showSettings = false
    @State private var isSelfView = false
    @State private var hasLoadedOnce = false
    private var loadKey: String { (username ?? "") + "|" + (userId ?? "") }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                ScrollView {
                    LazyVStack(pinnedViews: [.sectionHeaders]) {
                        // Header
                        if let p = profile { header(p) }
                        // Tabs (sticky)
                        Section {
                            tabContent()
                        } header: {
                            tabsBar()
                        }
                    }
                }
                .toolbar { toolbar }
            }
            .navigationTitle("")
            .toolbarTitleDisplayMode(.inline)
            .loadingOverlay(isLoading)
            .task(id: loadKey) {
                if !hasLoadedOnce {
                    await loadAll()
                    hasLoadedOnce = true
                }
            }
            .navigationDestination(isPresented: $showAccount) { AccountView() }
            .navigationDestination(isPresented: $showSettings) { SettingsView() }
        }
    }

    private var canShowBack: Bool { false }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            if canShowBack {
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.left")
                        .font(.body.weight(.semibold))
                }
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                if let _ = profile, !isSelfView {
                    Button(role: .destructive) { presentBlock() } label: {
                        Label("Block user", systemImage: "hand.raised.fill")
                    }
                    Button { presentReport() } label: {
                        Label("Report user", systemImage: "exclamationmark.bubble.fill")
                    }
                }
                Button { shareProfile() } label: {
                    Label("Share profile", systemImage: "square.and.arrow.up")
                }
            } label: {
                Image(systemName: "ellipsis")
            }
        }
    }

    private func header(_ p: ProfileModel) -> some View {
        VStack(spacing: 12) {
            // Avatar
            ZStack {
                Circle().fill(Color.primary.opacity(0.06))
                if let url = p.imageURL {
                    AsyncImage(url: url) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        ProgressView().progressViewStyle(.circular)
                    }
                } else {
                    Image(systemName: "person.crop.circle.fill")
                        .resizable().scaledToFit().foregroundStyle(.secondary)
                        .padding(12)
                }
            }
            .frame(width: 96, height: 96)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(.thinMaterial, lineWidth: 1))
            .padding(.top, 8)

            // Name & username
            Text(p.name).font(.title3.weight(.semibold))
            Text("@\(p.username)").font(.callout).foregroundStyle(.secondary)

            // Stats
            HStack(spacing: 24) {
                statView(value: p.followers, label: "Followers")
                statView(value: p.following, label: "Following")
            }.padding(.top, 4)

            // Buttons
            buttonsRow(p)

            // Bio
            if !p.bio.isEmpty {
                Text(p.bio)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 8)
    }

    private func statView(value: Int, label: String) -> some View {
        VStack(spacing: 2) {
            Text("\(value)").font(.headline)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func buttonsRow(_ p: ProfileModel) -> some View {
        HStack(spacing: 10) {
            if !isSelfView {
                // Follow/Friends
                let isFriends = p.isFollowing && p.isFollowedBy
                GradientButton(title: isFriends ? "Friends" : (p.isFollowing ? "Following" : "Follow")) {
                    Task { await toggleFollow() }
                }
                // Chat
                GradientButton(title: "Chat") {
                    banners.show(Banner(title: "Open chat (TODO)", style: .info))
                }
            } else {
                GradientButton(title: "Account") { showAccount = true }
                GradientButton(title: "Settings") { showSettings = true }
            }
        }
    }

    private func tabsBar() -> some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                let width = geo.size.width
                let count = CGFloat(ProfileTab.allCases.count)
                let tabWidth = width / max(count, 1)
                ZStack(alignment: .bottomLeading) {
                    HStack(spacing: 0) {
                        ForEach(ProfileTab.allCases, id: \.self) { tab in
                            Button(action: { withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) { activeTab = tab } }) {
                                Text(tab.rawValue)
                                    .font(.subheadline.weight(activeTab == tab ? .semibold : .regular))
                                    .foregroundStyle(activeTab == tab ? Color.primary : .secondary)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 28)
                            }
                        }
                    }
                    // Tiny underline indicator
                    Rectangle()
                        .fill(AppColors.primaryEnd)
                        .frame(width: 24, height: 2)
                        .offset(x: CGFloat(tabIndex(activeTab)) * tabWidth + (tabWidth - 24) / 2)
                        .animation(.spring(response: 0.28, dampingFraction: 0.9), value: activeTab)
                }
            }
            .frame(height: 30)

            if activeTab == .gifts {
                HStack {
                    Menu {
                        ForEach(GiftsSort.allCases, id: \.self) { s in
                            Button(action: { giftsSort = s }) { Text(s.rawValue) }
                        }
                    } label: {
                        Label("Sort: \(giftsSort.rawValue)", systemImage: "arrow.up.arrow.down")
                    }
                    Spacer()
                }
                .padding(.horizontal)
            }

            Divider()
        }
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private func tabIndex(_ tab: ProfileTab) -> Int {
        switch tab {
        case .posts: return 0
        case .wishlists: return 1
        case .gifts: return 2
        }
    }

    @ViewBuilder
    private func tabContent() -> some View {
        switch activeTab {
        case .posts:
            PostsGridView(thumbs: postThumbs)
                .padding(.horizontal)
        case .wishlists:
            WishlistsListView(items: wishlists)
                .padding(.horizontal)
        case .gifts:
            GiftsCatalogView(sort: giftsSort)
                .padding(.horizontal)
        }
    }

    // MARK: - Actions
    private func presentBlock() {
        drawer.present(DrawerModel(
            title: "Block user",
            message: "You will no longer see this user's posts.",
            primaryTitle: "Block",
            primaryAction: { banners.show(Banner(title: "User blocked", style: .success)); drawer.dismiss() },
            secondaryTitle: "Cancel",
            secondaryAction: { drawer.dismiss() }
        ))
    }
    private func presentReport() {
        drawer.present(DrawerModel(
            title: "Report user",
            message: "Tell us what's wrong with this profile.",
            primaryTitle: "Report",
            primaryAction: { banners.show(Banner(title: "Report submitted", style: .success)); drawer.dismiss() },
            secondaryTitle: "Cancel",
            secondaryAction: { drawer.dismiss() }
        ))
    }
    private func shareProfile() {
        banners.show(Banner(title: "Share link copied", style: .info))
    }
    private func toggleFollow() async {
        guard var p = profile, let me = supabase.user?.id.uuidString else { return }
        let newFollow = !p.isFollowing
        // optimistic
        p.isFollowing = newFollow
        profile = p
        do {
            try await supabase.setFollow(currentUserId: me, targetUserId: p.userId, follow: newFollow)
            // optionally refresh follow-back status
        } catch {
            // revert on error
            p.isFollowing.toggle()
            profile = p
            banners.show(Banner(title: "Failed to update follow", style: .error))
        }
    }

    // MARK: - Data
    private func loadAll() async {
        isLoading = true
        defer { isLoading = false }
        do {
            // Determine which profile to load
            let authedId = supabase.user?.id.uuidString
            let targetUserId = userId ?? authedId
            // If neither username nor userId available and not authed, nothing to load
            if username == nil && targetUserId == nil { return }

            // Fetch the target profile (by username or userId)
            guard let db = try await supabase.fetchProfile(username: username, userId: targetUserId) else { return }

            // Self-view if loaded profile's user_id equals authenticated user's id (robust UUID compare)
            let selfView: Bool = {
                if let authedUUID = supabase.user?.id, let targetUUID = UUID(uuidString: db.user_id) {
                    return authedUUID == targetUUID
                }
                if let authedId {
                    let a = authedId.trimmingCharacters(in: .whitespacesAndNewlines)
                    let b = db.user_id.trimmingCharacters(in: .whitespacesAndNewlines)
                    return b.caseInsensitiveCompare(a) == .orderedSame
                }
                return false
            }()
            isSelfView = selfView

            var isFollowing = false
            var isFollowedBy = false
            if let authedId, !selfView {
                isFollowing = (try? await supabase.isFollowing(currentUserId: authedId, targetUserId: db.user_id)) ?? false
                isFollowedBy = (try? await supabase.isFollowing(currentUserId: db.user_id, targetUserId: authedId)) ?? false
            }

            profile = ProfileModel(
                userId: db.user_id,
                username: db.username,
                name: db.name ?? "",
                bio: db.bio ?? "",
                imageURL: db.image.flatMap(URL.init(string:)),
                followers: db.followers_count ?? 0,
                following: db.following_count ?? 0,
                isCurrentUser: selfView,
                isFollowing: isFollowing,
                isFollowedBy: isFollowedBy
            )

            // Load tab data for that profile
            postThumbs = (try? await supabase.fetchUserPostThumbs(userId: db.user_id, limit: 20)) ?? []
            wishlists = (try? await supabase.fetchWishlists(userId: db.user_id, limit: 20)) ?? []
            gifts = (try? await supabase.fetchGifts(sort: mapSort(giftsSort), limit: 40)) ?? []
        } catch {
            // Avoid spamming banners on transient errors; load quietly
            // You can add a single-shot banner here if desired
        }
    }

    private func mapSort(_ s: GiftsSort) -> SupabaseManager.GiftsSortKey {
        switch s {
        case .newest: return .newest
        case .popular: return .popular
        case .priceAsc: return .priceAsc
        case .priceDesc: return .priceDesc
        }
    }
}

// MARK: - Tab Content Placeholders
private struct PostsGridView: View {
    let thumbs: [URL]
    private let columns = [GridItem(.flexible()), GridItem(.flexible())]
    var body: some View {
        if thumbs.isEmpty {
            VStack(spacing: 8) { Text("No posts yet").foregroundStyle(.secondary) }
                .padding(.vertical, 16)
        } else {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(thumbs, id: \.self) { url in
                    AsyncImage(url: url) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        ShimmerView()
                    }
                    .frame(width: 180, height: 280)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
            .padding(.vertical, 8)
        }
    }
}

private struct WishlistsListView: View {
    let items: [SupabaseManager.DBWishlist]
    var body: some View {
        if items.isEmpty {
            VStack(spacing: 8) { Text("No wishlists yet").foregroundStyle(.secondary) }
                .padding(.vertical, 16)
        } else {
            VStack(spacing: 8) {
                ForEach(items, id: \.id) { w in
                    HStack {
                        RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)).frame(width: 44, height: 44)
                        Text(w.title ?? "Untitled wishlist").font(.subheadline)
                        Spacer()
                    }
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.04)))
                }
            }
            .padding(.vertical, 8)
        }
    }
}

private struct GiftsCatalogView: View {
    let sort: GiftsSort
    private let columns = [GridItem(.flexible()), GridItem(.flexible())]
    private let supabase = SupabaseManager.shared
    @State private var items: [SupabaseManager.DBGift] = []
    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(items, id: \.id) { g in
                VStack(spacing: 8) {
                    if let src = g.image, let url = URL(string: src) {
                        AsyncImage(url: url) { img in
                            img.resizable().scaledToFill()
                        } placeholder: { ShimmerView() }
                        .frame(height: 100)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    } else {
                        RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.06)).frame(height: 100)
                    }
                    Text(g.name ?? "Gift").font(.caption)
                }
            }
        }
        .padding(.vertical, 8)
        .task { await load() }
    }
    private func load() async {
        let key: SupabaseManager.GiftsSortKey
        switch sort { case .newest: key = .newest; case .popular: key = .popular; case .priceAsc: key = .priceAsc; case .priceDesc: key = .priceDesc }
        items = (try? await supabase.fetchGifts(sort: key, limit: 40)) ?? []
    }
}
