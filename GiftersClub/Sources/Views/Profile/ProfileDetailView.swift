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
            .task { await loadProfile() }
        }
    }

    private var canShowBack: Bool { true }

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
                Button(role: .destructive) { presentBlock() } label: {
                    Label("Block user", systemImage: "hand.raised.fill")
                }
                Button { presentReport() } label: {
                    Label("Report user", systemImage: "exclamationmark.bubble.fill")
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
            if !p.isCurrentUser {
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
                GradientButton(title: "Account") { banners.show(Banner(title: "Account (TODO)", style: .info)) }
                GradientButton(title: "Settings") { banners.show(Banner(title: "Settings (TODO)", style: .info)) }
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
            PostsGridView(userId: profile?.userId)
                .padding(.horizontal)
        case .wishlists:
            WishlistsListView(userId: profile?.userId)
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
        guard var p = profile else { return }
        p.isFollowing.toggle()
        profile = p
        // TODO: Call Supabase RPC to follow/unfollow
    }

    // MARK: - Data
    private func loadProfile() async {
        isLoading = true
        defer { isLoading = false }
        // TODO: fetch from Supabase; stubbed for now
        let isSelf = (username == nil && userId == nil)
        let currentUsername = supabase.user?.email?.split(separator: "@").first.map(String.init) ?? "me"
        profile = ProfileModel(
            userId: userId ?? (supabase.user.map { $0.id.uuidString }) ?? UUID().uuidString,
            username: username ?? currentUsername,
            name: "User Name",
            bio: "This is a short bio about the user.",
            imageURL: nil,
            followers: 123,
            following: 45,
            isCurrentUser: isSelf,
            isFollowing: false,
            isFollowedBy: false
        )
    }
}

// MARK: - Tab Content Placeholders
private struct PostsGridView: View {
    let userId: String?
    private let columns = [GridItem(.flexible()), GridItem(.flexible())]
    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(0..<8, id: \.self) { _ in
                ShimmerView().frame(height: 140)
            }
        }
        .padding(.vertical, 8)
    }
}

private struct WishlistsListView: View {
    let userId: String?
    var body: some View {
        VStack(spacing: 8) {
            ForEach(0..<5, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.06)).frame(height: 56)
            }
        }
        .padding(.vertical, 8)
    }
}

    private struct GiftsCatalogView: View {
        let sort: GiftsSort
        private let columns = [GridItem(.flexible()), GridItem(.flexible())]
        var body: some View {
            LazyVGrid(columns: columns, spacing: 10) {
            ForEach(0..<10, id: \.self) { _ in
                VStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.06)).frame(height: 100)
                    Text("Gift name").font(.caption)
                }
            }
        }
        .padding(.vertical, 8)
    }
}
