import SwiftUI

struct MainTabView: View {
    @Binding var deepLink: DeepLink?
    @State private var selected: Int = 0
    @State private var programmaticSelectProfile = false
    @State private var rootTab: RootTab = .home
    @State private var showComposer = false
    @State private var profileRouteUsername: String? = nil
    @State private var exploreQuery: String? = nil

    var body: some View {
        ZStack(alignment: .bottom) {
            // Fullscreen content behind the bottom bar
            ZStack {
                switch rootTab {
                case .home: HomeTabsView()
                case .explore: ExploreView(externalQuery: $exploreQuery)
                case .chat: ChatListView()
                case .profile: ProfileView(routeUsername: $profileRouteUsername)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaInset(edge: .bottom) { Color.clear.frame(height: CustomBottomBar.barHeight) }

            // Bottom menu overlays content with equal spacing
            CustomBottomBar(selected: $rootTab, onCompose: { showComposer = true })
        }
        .sheet(isPresented: $showComposer) { CreatePostSheet() }
        .onReceive(NotificationCenter.default.publisher(for: .showGifterProfile)) { note in
            programmaticSelectProfile = true
            if let u = note.object as? String { profileRouteUsername = u }
            rootTab = .profile
        }
        .onChange(of: rootTab) { _, newValue in
            if newValue == .profile && programmaticSelectProfile == false {
                NotificationCenter.default.post(name: .showCurrentProfile, object: nil)
            }
            if newValue != .profile { programmaticSelectProfile = false }
        }
        .onChange(of: deepLink) { _, link in
            guard let link else { return }
            route(link)
            // Clear after handling
            self.deepLink = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: .exploreSearch)) { note in
            if let q = note.object as? String {
                exploreQuery = q
                rootTab = .explore
            }
        }
    }

    private func route(_ link: DeepLink) {
        switch link {
        case .wishlist(_):
            rootTab = .home
            NotificationCenter.default.post(name: .showHomeWishlists, object: nil)
        case .gifter(let username):
            rootTab = .profile
            NotificationCenter.default.post(
                name: .showGifterProfile,
                object: username
            )
        }
    }
}

extension Notification.Name {
    static let showWishlistDetail = Notification.Name("showWishlistDetail")
    static let showGifterProfile = Notification.Name("showGifterProfile")
    static let showCurrentProfile = Notification.Name("showCurrentProfile")
    static let showHomeWishlists = Notification.Name("showHomeWishlists")
    static let exploreSearch = Notification.Name("exploreSearch")
}

// MARK: - Placeholder Tab Views

// HomeView implemented in Feed/FeedView.swift
// ExploreView implemented in Explore/ExploreView.swift
// ChatListView implemented in Views/Chat/ChatListView.swift

// Old standalone wishlists tab removed; wishlists now live under Home top tabs

struct ProfileView: View {
    @Binding var routeUsername: String?
    @State private var showGifter = false
    @State private var username: String? = nil
    @StateObject private var banners = BannerQueue()
    @StateObject private var drawer = DrawerManager()
    @State private var btnState: GradientButtonState = .normal
    var body: some View {
        DrawerHost {
            ZStack(alignment: .top) {
                NavigationStack {
                    ProfileDetailView(username: nil, userId: nil)
                        .navigationDestination(isPresented: $showGifter) {
                            if let u = username { GifterProfileView(username: u) }
                        }
                }
                .environmentObject(banners)
                BannerHost().environmentObject(banners)
            }
        }
        .environmentObject(drawer)
        .onChange(of: routeUsername) { _, newValue in
            if let u = newValue { username = u; showGifter = true; routeUsername = nil }
        }
        .onAppear {
            if let u = routeUsername { username = u; showGifter = true; routeUsername = nil }
        }
        .onReceive(NotificationCenter.default.publisher(for: .showGifterProfile)) { note in
            if let u = note.object as? String { username = u; showGifter = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: .showCurrentProfile)) { _ in
            username = nil
            showGifter = false
        }
    }
}

struct WishlistDetailView: View {
    let wishlistId: String
    var body: some View { Text("Wishlist: \(wishlistId)").padding() }
}

struct GifterProfileView: View {
    let username: String
    @StateObject private var banners = BannerQueue()
    @StateObject private var drawer = DrawerManager()
    var body: some View {
        DrawerHost {
            ZStack(alignment: .top) {
                ProfileDetailView(username: username)
                BannerHost()
            }
        }
        .environmentObject(banners)
        .environmentObject(drawer)
    }
}
