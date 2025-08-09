import SwiftUI

struct MainTabView: View {
    @Binding var deepLink: DeepLink?
    @State private var selected: Int = 0

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
}

// MARK: - Placeholder Tab Views

struct HomeView: View { var body: some View { Text("Feed").frame(maxWidth: .infinity, maxHeight: .infinity) } }
struct ExploreView: View { var body: some View { Text("Explore").frame(maxWidth: .infinity, maxHeight: .infinity) } }
struct ChatListView: View { var body: some View { Text("Chats").frame(maxWidth: .infinity, maxHeight: .infinity) } }

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
                    VStack(spacing: 16) {
                        Text("Profile")
                        GradientButton(title: "Show Success Banner", state: btnState) {
                            banners.show(Banner(title: "Your post has been created", style: .success))
                            btnState = .success
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { btnState = .normal }
                        }
                        GradientButton(title: "Open Drawer", state: .normal) {
                            drawer.present(DrawerModel(
                                title: "Subscribe",
                                message: "Subscribe to @creator to unlock posts",
                                primaryTitle: "Subscribe",
                                primaryAction: { drawer.dismiss() },
                                secondaryTitle: "Not now",
                                secondaryAction: { drawer.dismiss() }
                            ))
                        }
                        Button("Sign out") { Task { await SupabaseManager.shared.signOut() } }
                    }
                    .navigationDestination(isPresented: $showGifter) {
                        GifterProfileView(username: username ?? "")
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .showGifterProfile)) { note in
                        if let u = note.object as? String {
                            username = u
                            showGifter = true
                        }
                    }
                }
                .environmentObject(banners)
                BannerHost().environmentObject(banners)
            }
        }
        .environmentObject(drawer)
    }
}

struct WishlistDetailView: View {
    let wishlistId: String
    var body: some View { Text("Wishlist: \(wishlistId)").padding() }
}

struct GifterProfileView: View {
    let username: String
    var body: some View { Text("@\(username)").padding() }
}
