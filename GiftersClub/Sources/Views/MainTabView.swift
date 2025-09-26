import SwiftUI

struct MainTabView: View {
    @Binding var deepLink: DeepLink?
    @State private var selected: Int = 0
    @State private var programmaticSelectProfile = false
    @State private var rootTab: RootTab = .home
    @State private var showComposer = false
    @State private var showComposeChoice = false
    @State private var showCreatePost = false
    @State private var showGoLiveSetup = false
    @State private var profileRouteUsername: String? = nil
    @State private var profileRouteUserId: String? = nil
    @State private var exploreQuery: String? = nil
    @State private var hideBottomBar: Bool = false
    @State private var liveCheckTimer: Timer? = nil
    @State private var resumeLive: SupabaseManager.DBLiveStream? = nil
    struct LiveLink: Identifiable { let id: String; let manage: Bool; let setupMatch: Bool }
    @State private var deepLinkLive: LiveLink? = nil
    @ObservedObject private var supabase = SupabaseManager.shared
    @StateObject private var banners = BannerQueue()
    @State private var pendingChatUsername: String? = nil

    @ObservedObject private var network = NetworkMonitor.shared
    var body: some View {
        ZStack(alignment: .bottom) {
            // Fullscreen content behind the bottom bar
            ZStack {
                switch rootTab {
                case .home: HomeTabsView()
                case .explore: ExploreView(externalQuery: $exploreQuery)
                case .chat: ChatListView()
                case .profile: ProfileView(routeUsername: $profileRouteUsername, routeUserId: $profileRouteUserId)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaInset(edge: .bottom) {
                Color.clear
                    .frame(height: hideBottomBar ? 0 : CustomBottomBar.barHeight + CustomBottomBar.additionalSafePadding)
            }

            // Global banner host
            VStack { Spacer(minLength: 0) }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .overlay(alignment: .top) {
                    BannerHost().environmentObject(banners)
                }

            // Bottom menu overlays content with equal spacing
            if !hideBottomBar {
                CustomBottomBar(selected: $rootTab, onCompose: { showComposeChoice = true })
            }
            // No-internet overlay for iOS
            if !network.isReachable {
                VStack(spacing: 8) {
                    Text("No internet connection").font(.subheadline.weight(.semibold))
                    Text("Some features may not work until you're back online.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .frame(maxWidth: .infinity)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal)
                .padding(.bottom, 8)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .sheet(isPresented: $showComposeChoice) {
            ComposeChoiceSheet(
                onCreatePost: { showComposeChoice = false; showCreatePost = true },
                onGoLive: { showComposeChoice = false; showGoLiveSetup = true }
            )
        }
        .fullScreenCover(isPresented: $showCreatePost) { CreatePostCameraView() }
        .fullScreenCover(isPresented: $showGoLiveSetup) { GoLiveSetupView() }
        .fullScreenCover(item: $resumeLive) { stream in
            LiveBroadcastView(stream: stream)
                .environmentObject(banners)
        }
        .fullScreenCover(item: $deepLinkLive) { ctx in
            LiveEntryByIdView(liveId: ctx.id, startManagePanel: ctx.manage, setupMatch: ctx.setupMatch)
        }
        .onReceive(NotificationCenter.default.publisher(for: .showGifterProfile)) { note in
            programmaticSelectProfile = true
            if let u = note.object as? String { profileRouteUsername = u }
            rootTab = .profile
        }
        .onReceive(NotificationCenter.default.publisher(for: .showGifterProfileId)) { note in
            programmaticSelectProfile = true
            if let uid = note.object as? String { profileRouteUserId = uid }
            rootTab = .profile
        }
        .onReceive(NotificationCenter.default.publisher(for: .openChatWithUsername)) { note in
            // Switch to Chat tab; re-post after the tab is active so ChatListView can consume it
            rootTab = .chat
            pendingChatUsername = note.object as? String
        }
        .onChange(of: rootTab, perform: { newTab in
            if newTab == .chat, let username = pendingChatUsername {
                pendingChatUsername = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    NotificationCenter.default.post(name: .openChatWithUsername, object: username)
                }
            }
        })
        .onChange(of: rootTab, perform: { newValue in
            if newValue == .profile && programmaticSelectProfile == false {
                NotificationCenter.default.post(name: .showCurrentProfile, object: nil)
            }
            if newValue != .profile { programmaticSelectProfile = false }
        })
        .onChange(of: deepLink, perform: { link in
            guard let link else { return }
            route(link)
            // Clear after handling
            self.deepLink = nil
        })
        .onReceive(NotificationCenter.default.publisher(for: .exploreSearch)) { note in
            if let q = note.object as? String {
                exploreQuery = q
                rootTab = .explore
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .goHome)) { _ in
            rootTab = .home
            showComposer = false
            showComposeChoice = false
            showCreatePost = false
            showGoLiveSetup = false
        }
        .onReceive(NotificationCenter.default.publisher(for: .gotoProfile)) { _ in
            rootTab = .profile
            // Ensure current profile is shown after switch
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                NotificationCenter.default.post(name: .showCurrentProfile, object: nil)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .signedIn)) { _ in
            banners.show(Banner(title: "Signed in", style: .success, duration: 2))
        }
        .onReceive(NotificationCenter.default.publisher(for: .hideBottomBar)) { _ in hideBottomBar = true }
        .onReceive(NotificationCenter.default.publisher(for: .showBottomBar)) { _ in hideBottomBar = false }
        .task { startLiveResumePolling() }
        .onDisappear { liveCheckTimer?.invalidate(); liveCheckTimer = nil }
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
        case .live(let id, let manage, let setup):
            deepLinkLive = LiveLink(id: id, manage: manage, setupMatch: setup)
        }
    }

    private func startLiveResumePolling() {
        liveCheckTimer?.invalidate()
        liveCheckTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { _ in
            Task { await checkActiveLiveAndMaybeBanner() }
        }
        Task { await checkActiveLiveAndMaybeBanner() }
    }

    private func checkActiveLiveAndMaybeBanner() async {
        guard !hideBottomBar else { return }
        guard supabase.user != nil else { return }
        if let active = try? await supabase.fetchActiveLiveForCurrentUser() {
            await MainActor.run {
                banners.show(Banner(title: "You are live — Resume streaming", style: .info, action: {
                    Task {
                        if let s = try? await supabase.fetchLiveSession(active.id) {
                            await MainActor.run { resumeLive = s }
                        }
                    }
                }, duration: 5))
            }
        }
    }
}

extension Notification.Name {
    static let showWishlistDetail = Notification.Name("showWishlistDetail")
    static let showGifterProfile = Notification.Name("showGifterProfile")
    static let showGifterProfileId = Notification.Name("showGifterProfileId")
    static let showCurrentProfile = Notification.Name("showCurrentProfile")
    static let showHomeWishlists = Notification.Name("showHomeWishlists")
    static let exploreSearch = Notification.Name("exploreSearch")
    static let goHome = Notification.Name("goHome")
    static let hideBottomBar = Notification.Name("hideBottomBar")
    static let showBottomBar = Notification.Name("showBottomBar")
    static let openChatWithUsername = Notification.Name("openChatWithUsername")
    static let gotoProfile = Notification.Name("gotoProfile")
    static let signedIn = Notification.Name("signedIn")
    static let refreshHomeFeed = Notification.Name("refreshHomeFeed")
}

// MARK: - Placeholder Tab Views

// HomeView implemented in Feed/FeedView.swift
// ExploreView implemented in Explore/ExploreView.swift
// ChatListView implemented in Views/Chat/ChatListView.swift

// Old standalone wishlists tab removed; wishlists now live under Home top tabs

struct ProfileView: View {
    @Binding var routeUsername: String?
    @Binding var routeUserId: String?
    @State private var showGifter = false
    @State private var username: String? = nil
    @State private var userId: String? = nil
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
                            else if let uid = userId { GifterProfileViewById(userId: uid) }
                        }
                }
                .environmentObject(banners)
                BannerHost().environmentObject(banners)
            }
        }
        .environmentObject(drawer)
        .onChange(of: routeUsername, perform: { newValue in
            if let u = newValue { username = u; userId = nil; showGifter = true; routeUsername = nil }
        })
        .onChange(of: routeUserId, perform: { newValue in
            if let uid = newValue { userId = uid; username = nil; showGifter = true; routeUserId = nil }
        })
        .onAppear {
            if let u = routeUsername { username = u; userId = nil; showGifter = true; routeUsername = nil }
            if let uid = routeUserId { userId = uid; username = nil; showGifter = true; routeUserId = nil }
        }
        .onReceive(NotificationCenter.default.publisher(for: .showGifterProfile)) { note in
            if let u = note.object as? String { username = u; userId = nil; showGifter = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: .showGifterProfileId)) { note in
            if let uid = note.object as? String { userId = uid; username = nil; showGifter = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: .showCurrentProfile)) { _ in
            username = nil; userId = nil
            showGifter = false
        }
    }
}

struct GifterProfileView: View {
    let username: String
    @StateObject private var banners = BannerQueue()
    @StateObject private var drawer = DrawerManager()
    var body: some View {
        DrawerHost {
            ZStack(alignment: .top) {
                ProfileDetailView(username: username)
                BannerHost().environmentObject(banners)
            }
        }
        .environmentObject(banners)
        .environmentObject(drawer)
    }
}

struct GifterProfileViewById: View {
    let userId: String
    @StateObject private var banners = BannerQueue()
    @StateObject private var drawer = DrawerManager()
    var body: some View {
        DrawerHost {
            ZStack(alignment: .top) {
                ProfileDetailView(username: nil, userId: userId)
                BannerHost().environmentObject(banners)
            }
        }
        .environmentObject(banners)
        .environmentObject(drawer)
    }
}
