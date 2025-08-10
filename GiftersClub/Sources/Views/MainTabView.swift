import SwiftUI

struct MainTabView: View {
    @Binding var deepLink: DeepLink?
    @State private var selected: Int = 0
    @State private var programmaticSelectProfile = false

    var body: some View {
        TabView(selection: $selected) {
            HomeView()
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag(0)
            ExploreView()
                .tabItem { Label("Explore", systemImage: "safari.fill") }
                .tag(1)
            ChatListView()
                .tabItem { Label("Chat", systemImage: "bubble.left.and.bubble.right.fill") }
                .tag(2)
            WishlistsView()
                .tabItem { Label("Wishlists", systemImage: "gift.fill") }
                .tag(3)
            ProfileView()
                .tabItem { Label("Profile", systemImage: "person.crop.circle.fill") }
                .tag(4)
        }
        .onReceive(NotificationCenter.default.publisher(for: .showGifterProfile)) { _ in
            programmaticSelectProfile = true
            selected = 4
        }
        .onChange(of: selected) { _, newValue in
            if newValue == 4 && programmaticSelectProfile == false {
                NotificationCenter.default.post(name: .showCurrentProfile, object: nil)
            }
            if newValue != 4 { programmaticSelectProfile = false }
        }
        .onChange(of: deepLink) { _, link in
            guard let link else { return }
            route(link)
            // Clear after handling
            self.deepLink = nil
        }
    }

    private func route(_ link: DeepLink) {
        switch link {
        case .wishlist(let id):
            selected = 3
            // Present wishlist detail over Wishlists tab
            NotificationCenter.default.post(
                name: .showWishlistDetail,
                object: id
            )
        case .gifter(let username):
            selected = 4
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
}

// MARK: - Placeholder Tab Views

// HomeView implemented in Feed/FeedView.swift
// ExploreView implemented in Explore/ExploreView.swift
// ChatListView implemented in Views/Chat/ChatListView.swift

struct WishlistsView: View {
    @State private var showDetail = false
    @State private var wishlistId: String? = nil
    var body: some View {
        NavigationStack {
            List {
                Text("Your wishlists will appear here")
            }
            .navigationTitle("Wishlists")
            .navigationDestination(isPresented: $showDetail) {
                WishlistDetailView(wishlistId: wishlistId ?? "")
            }
            .onReceive(NotificationCenter.default.publisher(for: .showWishlistDetail)) { note in
                if let id = note.object as? String {
                    wishlistId = id
                    showDetail = true
                }
            }
        }
    }
}

struct ProfileView: View {
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
