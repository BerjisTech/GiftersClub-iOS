import SwiftUI
import AVKit
import UIKit
#if canImport(Supabase)
import Supabase
#endif
#if canImport(DotLottie)
import DotLottie
#endif

struct FeedPost: Identifiable, Hashable {
    struct Author: Hashable { let userId: String; let username: String; let name: String?; let avatarURL: URL? }
    enum Media: Hashable { case image(URL); case video(URL); case images([URL]) }
    let id: String
    let author: Author
    let caption: String
    let accessType: String?
    let price: Int?
    let media: Media
    var likes: Int
    var comments: Int
    var shares: Int
    var isLiked: Bool
}

struct HomeView: View {
    @ObservedObject private var supabase = SupabaseManager.shared
    enum FeedItem: Identifiable, Hashable {
        case post(FeedPost)
        case live(SupabaseManager.DBLiveStreamWithStats)
        var id: String {
            switch self {
            case .post(let p): return p.id
            case .live(let l): return "live_\(l.id)"
            }
        }
    }
    @State private var items: [FeedItem] = []
    @State private var posts: [FeedPost] = []
    @State private var selection: Int = 0
    @State private var isLoading = false
    @State private var offset: Int = 0
    @ObservedObject private var commentsPresenter = CommentsPresenter.shared
    @State private var tabBarHeight: CGFloat = 0
    @State private var sharePost: FeedPost? = nil
    @State private var isLoadingMore = false
    @State private var selectedLive: SupabaseManager.DBLiveStreamWithStats? = nil
    // Pull-to-refresh for vertical pager
    @State private var pullDistance: CGFloat = 0
    @State private var isRefreshingFeed: Bool = false

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let fullHeight = size.height
            ZStack(alignment: .top) {
                VerticalPageView(items: items, selection: $selection) { idx, _ in
                    let item = items[idx]
                    switch item {
                    case .post(let p):
                        if let pIndex = posts.firstIndex(where: { $0.id == p.id }) {
                            PostPageView(post: $posts[pIndex], isActive: selection == idx, bottomSafeInset: proxy.safeAreaInsets.bottom, tabBarHeight: tabBarHeight)
                                .frame(width: size.width, height: fullHeight)
                        } else {
                            Color.black.frame(width: size.width, height: fullHeight)
                        }
                    case .live(let live):
                        Button(action: { selectedLive = live }) {
                            LiveCardView(live: live)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .contentShape(Rectangle())
                        .frame(width: size.width, height: fullHeight)
                        .zIndex(10)
                    }
                }
                .frame(width: size.width, height: fullHeight)
                .background(Color.black)
                .ignoresSafeArea(edges: [.bottom])

                // Pull-to-refresh indicator at top
                VStack(spacing: 6) {
                    if isRefreshingFeed {
                        HStack(spacing: 8) { ProgressView(); Text("Refreshing…").foregroundStyle(.white).font(.caption) }
                            .padding(8)
                            .background(.ultraThinMaterial, in: Capsule())
                            .padding(.top, proxy.safeAreaInsets.top + 8)
                    } else if pullDistance > 0.0 {
                        let pct = min(1.0, pullDistance / 90.0)
                        HStack(spacing: 8) {
                            Image(systemName: pct >= 1.0 ? "arrow.clockwise.circle.fill" : "arrow.down.circle")
                                .foregroundStyle(.white)
                            Text(pct >= 1.0 ? "Release to refresh" : "Pull to refresh")
                                .foregroundStyle(.white)
                                .font(.caption)
                        }
                        .padding(8)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.top, proxy.safeAreaInsets.top + 8)
                    }
                    Spacer(minLength: 0)
                }
                .frame(width: size.width, height: fullHeight)
            }
            // Detect a downward pull on the first page to trigger refresh without blocking paging
            .simultaneousGesture(
                DragGesture(minimumDistance: 12, coordinateSpace: .local)
                    .onChanged { value in
                        guard selection == 0 else { pullDistance = 0; return }
                        if value.translation.height > 0 { pullDistance = value.translation.height }
                    }
                    .onEnded { value in
                        defer { pullDistance = 0 }
                        guard selection == 0 else { return }
                        if value.translation.height > 90 {
                            Task {
                                await MainActor.run { isRefreshingFeed = true }
                                await refresh()
                                await MainActor.run { isRefreshingFeed = false }
                            }
                        }
                    }
            )
            // Custom bottom bar is separate now; no need to offset by system tab bar height
        }
        .task { await initialLoad() }
        // Note: SwiftUI .refreshable requires a ScrollView; Home feed uses a pager.
        // We implement a custom pull-to-refresh gesture above.
        .loadingOverlay(isLoading)
        .onReceive(NotificationCenter.default.publisher(for: .refreshHomeFeed)) { _ in
            Task {
                await MainActor.run { selection = 0 }
                await refresh()
            }
        }
        .sheet(isPresented: $commentsPresenter.isPresented) {
            if let id = commentsPresenter.postId {
                CommentsSheet(postId: id)
            }
        }
        .sheet(item: $sharePost) { post in
            ShareOptionsSheet(postId: post.id, url: shareURL(for: post))
        }
        .onReceive(NotificationCenter.default.publisher(for: .init("share_post"))) { note in
            guard let id = note.object as? String, let p = posts.first(where: { $0.id == id }) else { return }
            sharePost = p
        }
        .onChange(of: selection, perform: { newIndex in
            // Load more when near the end
            if newIndex >= posts.count - 3 {
                Task { await loadMoreIfNeeded() }
            }
        })
        .navigationDestinationCompat(item: $selectedLive) { live in
            LiveEntryDestination(live: live)
        }
    }

    private func initialLoad() async { await refresh() }

    private func refresh() async {
        await MainActor.run { isLoading = true }
        defer { Task { await MainActor.run { isLoading = false } } }
        do {
            #if DEBUG
            print("[Feed] fetching posts limit=50 offset=0")
            #endif
            let rows = try await supabase.fetchFeed(limit: 50, offset: 0)
            var mapped = rows.compactMap(mapRow)
            // Always randomize local ordering so refreshes do not repeat
            mapped.shuffle()
            // Initialize liked state for current user
            let ids = mapped.map { $0.id }
            if let liked = try? await supabase.fetchUserLikedPostIDs(postIDs: ids) {
                for i in mapped.indices { mapped[i].isLiked = liked.contains(mapped[i].id) }
            }
            // Fetch ranked live streams and interleave
            #if DEBUG
            print("[Feed] posts=\(mapped.count)")
            #endif
            let lives = try? await supabase.fetchFeedLiveStreams(limit: max(1, mapped.count / 3), query: nil)
            #if DEBUG
            print("[Feed] lives returned=\(lives?.count ?? -1)")
            #endif
            let combined = interleave(posts: mapped, lives: lives ?? [])
            await MainActor.run {
                posts = mapped
                items = combined
                selection = 0
                offset = mapped.count
            }
            // Prefetch access/subscriptions for visible items
            let postIds = mapped.map { $0.id }
            let creators = Array(Set(mapped.map { $0.author.userId }))
            await supabase.prefetchAccess(posts: postIds, creators: creators)
        } catch {
            // Offline or failed fetch: shuffle existing cached posts to avoid repetition
            await MainActor.run {
                if !posts.isEmpty {
                    var shuffled = posts
                    shuffled.shuffle()
                    posts = shuffled
                    items = interleave(posts: shuffled, lives: [])
                    selection = 0
                }
            }
        }
    }

    private func loadMoreIfNeeded() async {
        guard !isLoadingMore else { return }
        await MainActor.run { isLoadingMore = true }
        defer { Task { await MainActor.run { isLoadingMore = false } } }
        do {
            #if DEBUG
            print("[Feed] loadMore offset=\(offset)")
            #endif
            let rows = try await supabase.fetchFeed(limit: 50, offset: offset)
            var mapped = rows.compactMap(mapRow)
            // Randomize the new page before interleaving
            mapped.shuffle()
            if mapped.isEmpty { return }
            // Refresh lives for this page and merge with existing items
            let lives = try? await supabase.fetchFeedLiveStreams(limit: max(1, mapped.count / 3), query: nil)
            let newItems = interleave(posts: mapped, lives: lives ?? [])
            await MainActor.run {
                posts.append(contentsOf: mapped)
                items.append(contentsOf: newItems)
                offset += mapped.count
            }
            // Prefetch for the newly loaded posts
            let postIds = mapped.map { $0.id }
            let creators = Array(Set(mapped.map { $0.author.userId }))
            await supabase.prefetchAccess(posts: postIds, creators: creators)
        } catch {
            // ignore
        }
    }

    private func mapRow(_ r: SupabaseManager.FeedRPCRow) -> FeedPost? {
        // Media mapping priority: video if present, else multiple images, else first image
        let medias = r.media ?? []
        let videos: [URL] = medias.compactMap { m in
            guard m.media_type == "video" else { return nil }
            return m.url.flatMap(URL.init(string:))
        }
        let images: [URL] = medias.compactMap { m in
            guard m.media_type != "video" else { return nil }
            return m.url.flatMap(URL.init(string:))
        }
        let media: FeedPost.Media = {
            if let v = videos.first { return .video(v) }
            if images.count > 1 { return .images(images) }
            if let img = images.first { return .image(img) }
            return .images([])
        }()
        let author = FeedPost.Author(
            userId: r.profile?.user_id ?? r.user_id,
            username: r.profile?.username ?? "unknown",
            name: r.profile?.username,
            avatarURL: r.profile?.image.flatMap(URL.init(string:))
        )
        let caption = r.content ?? ""
        return FeedPost(
            id: r.id,
            author: author,
            caption: caption,
            accessType: r.access_type,
            price: r.price,
            media: media,
            likes: r.like_count ?? 0,
            comments: r.comment_count ?? 0,
            shares: r.share_count ?? 0,
            isLiked: false
        )
    }
}

// MARK: - Live card view
struct LiveCardView: View {
    let live: SupabaseManager.DBLiveStreamWithStats
    @State private var profile: SupabaseManager.DBProfile? = nil
    @State private var viewerCount: Int? = nil
    @State private var timer: Timer? = nil
    private let supabase = SupabaseManager.shared
    @StateObject private var previewViewer = LiveKitViewer()
    var onOpen: () -> Void = {}
    var body: some View {
        ZStack(alignment: .bottom) {
            if previewViewer.remoteVideoTrack != nil {
                LKVideoView(track: previewViewer.remoteVideoTrack)
                    .scaleEffect(x: -1, y: 1)
                    .ignoresSafeArea()
            } else {
                ZStack {
                    if let t = live.thumbnail_url, let url = URL(string: t) {
                        AsyncImage(url: url) { img in img.resizable().scaledToFill() } placeholder: { Color.black }
                    } else { Color.black }
                    LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .top, endPoint: .bottom)
                }
                .ignoresSafeArea()
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text("LIVE NOW").font(.caption.bold()).foregroundStyle(.white).padding(.horizontal, 8).padding(.vertical, 4).background(Color.red).clipShape(Capsule())
                    Spacer()
                    Label("\(viewerCount ?? live.viewer_count ?? 0)", systemImage: "eye.fill").foregroundStyle(.white).font(.caption)
                }
                HStack(spacing: 8) {
                    if let img = profile?.image, let url = URL(string: img) {
                        AsyncImage(url: url) { i in i.resizable().scaledToFill() } placeholder: { Color.white.opacity(0.2) }
                            .frame(width: 28, height: 28)
                            .clipShape(Circle())
                    } else { Circle().fill(Color.white.opacity(0.2)).frame(width: 28, height: 28) }
                    Text(profile?.name ?? profile?.username ?? "").foregroundStyle(.white).font(.subheadline.weight(.semibold))
                    Spacer()
                }
                Text(live.title).font(.headline).foregroundStyle(.white).lineLimit(2)
            }
            .padding()
        }
        .background(Color.black)
        .contentShape(Rectangle())
        .task {
            if profile == nil { if let p = try? await supabase.fetchProfileByUserId(live.host_id) { await MainActor.run { profile = p } } }
            timer?.invalidate()
            timer = Timer.scheduledTimer(withTimeInterval: 6.0, repeats: true) { _ in
                Task { if let row = try? await supabase.fetchLiveStreamById(live.id) { await MainActor.run { viewerCount = row.viewer_count } } }
            }
            // Inline live preview
            do {
                var token: String? = nil
                if let session = try? await supabase.fetchLiveSession(live.id), let t = session.token, !t.isEmpty { token = t }
                else { token = try? await supabase.fetchLiveViewerToken(streamId: live.id) }
                if let tok = token, !tok.isEmpty { try? await previewViewer.connect(url: SupabaseConfig.livekitURL, token: tok) }
            }
        }
        .onDisappear { timer?.invalidate(); timer = nil; Task { await previewViewer.disconnect() } }
    }
}

// MARK: - Interleave helper
extension HomeView {
    private func interleave(posts: [FeedPost], lives: [SupabaseManager.DBLiveStreamWithStats]) -> [FeedItem] {
        var out: [FeedItem] = []
        var si = 0
        var sinceLast = 0
        var lastHost: String? = nil
        var insertedLives = 0
        let maxLives = 3
        var rng = SeededRng(seed: hashSeed("\(supabase.user?.id.uuidString ?? "anon"):0:\(posts.count)"))
        var gap = randomGap(3, 5, &rng)
        for p in posts {
            out.append(.post(p))
            sinceLast += 1
            if sinceLast >= gap && si < lives.count && insertedLives < maxLives {
                let live = lives[si]
                if live.host_id != lastHost {
                    out.append(.live(live))
                    lastHost = live.host_id
                    si += 1
                    sinceLast = 0
                    insertedLives += 1
                    gap = randomGap(3, 5, &rng)
                }
            }
        }
        return out
    }
    private func randomGap(_ min: Int, _ max: Int, _ rng: inout SeededRng) -> Int { Int(rng.next() * Double(max - min + 1)) + min }
    private func hashSeed(_ s: String) -> UInt32 {
        var h: UInt32 = 0x811c9dc5
        for c in s.utf8 { h ^= UInt32(c); h = h &+ (h << 1) &+ (h << 4) &+ (h << 7) &+ (h << 8) &+ (h << 24) }
        return h
    }
    struct SeededRng { var x: UInt32; init(seed: UInt32) { self.x = seed == 0 ? 123456789 : seed }
        mutating func next() -> Double { x ^= x << 13; x ^= x >> 17; x ^= x << 5; return Double(x) / Double(UInt32.max) } }
}

// MARK: - Post Page
struct PostPageView: View {
    @Binding var post: FeedPost
    let isActive: Bool
    let bottomSafeInset: CGFloat
    let tabBarHeight: CGFloat

    @State private var magnify: CGFloat = 1.0
    @State private var isPaused: Bool = false
    @State private var showHeart: Bool = false
    @State private var showBreak: Bool = false
    @State private var repostCount: Int = 0
    @State private var didRepost: Bool = false
    @State private var activeImageIndex: Int = 0
    @State private var hasAccess: Bool = true
    @State private var unlocking: Bool = false
    @ObservedObject private var supabase = SupabaseManager.shared
    @State private var authorUserId: String? = nil
    @State private var isFollowing: Bool = false

    var overlaysHidden: Bool { magnify > 1.01 || isPaused }
    private var isOwnPost: Bool { (supabase.user?.id.uuidString ?? "") == post.author.userId }

    var body: some View {
        ZStack {
            content
                .blur(radius: hasAccess ? 0 : 24)
                .allowsHitTesting(hasAccess)
                .scaleEffect(isPaused ? 1.03 : 1.0)
                .animation(.easeInOut(duration: 0.2), value: isPaused)
                .scaleEffect(magnify)
                .gesture(singleTap)
                .simultaneousGesture(magnifyGesture)

            if showHeart {
                #if canImport(DotLottie)
                DotLottieAnimation(
                    webURL: "https://lottie.host/fe660a41-2c70-4105-afb4-bab713f7e77b/AcLybokfnG.lottie",
                    config: AnimationConfig(autoplay: true, loop: false)
                ).view()
                    .frame(width: 220, height: 220)
                    .transition(.scale)
                    .allowsHitTesting(false)
                    .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { showHeart = false } }
                #else
                Image(systemName: "heart.fill")
                    .font(.system(size: 120))
                    .foregroundStyle(.red)
                    .opacity(0.95)
                    .transition(.scale)
                    .allowsHitTesting(false)
                    .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { showHeart = false } }
                #endif
            }
            if showBreak {
                #if canImport(DotLottie)
                DotLottieAnimation(
                    webURL: "https://lottie.host/810116a8-7247-45df-a8b2-f2d777b491f0/JDVtLuvkEG.lottie",
                    config: AnimationConfig(autoplay: true, loop: false)
                ).view()
                    .frame(width: 180, height: 180)
                    .transition(.scale)
                    .allowsHitTesting(false)
                    .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { showBreak = false } }
                #endif
            }

            // Overlays
            if !overlaysHidden { overlays }
            if !hasAccess { paywall }
        }
        .simultaneousGesture(doubleTap)
        .onChange(of: isActive, perform: { active in
            if !active { isPaused = false; magnify = 1.0 }
        })
        .background(Color.black)
        .onAppear {
            if let t = post.accessType, t != "free", !isOwnPost { hasAccess = false }
            Task { await preloadFollowState() }
            // Initialize repost count from backend and whether I already reposted
            Task {
                if let c = try? await supabase.repostCount(postId: post.id) { await MainActor.run { repostCount = c } }
                if let mine = try? await supabase.hasReposted(postId: post.id) { await MainActor.run { didRepost = mine } }
            }
        }
        .task { await checkAccess() }
    }

    @ViewBuilder
    private var content: some View {
        switch post.media {
        case .image(let url):
            ZoomableAsyncImage(url: url)
        case .images(let urls):
            CarouselView(urls: urls, index: $activeImageIndex)
        case .video(let url):
            VideoBackgroundView(url: url, play: isActive && !isPaused && hasAccess)
        }
    }

    private var paywall: some View {
        ZStack {
            Rectangle().fill(Color.black.opacity(0.65)).ignoresSafeArea()
            VStack(spacing: 12) {
                Image(systemName: "lock.fill").font(.largeTitle).foregroundStyle(.white)
                Text(post.accessType == "subscription" ? "Subscribe to view" : "Purchase to view")
                    .foregroundStyle(.white)
                if post.accessType == "paid" {
                    Button(action: { Task { await purchase() } }) {
                        Text(unlocking ? "Unlocking..." : "Unlock for \(post.price ?? 0) tokens").padding(.horizontal, 16).padding(.vertical, 10)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(unlocking)
                    .opacity(unlocking ? 0.6 : 1.0)
                } else if post.accessType == "subscription" {
                    Button(action: { Task { await subscribe() } }) {
                        Text("Subscribe").padding(.horizontal, 16).padding(.vertical, 10)
                    }.buttonStyle(.borderedProminent)
                }
            }
            .padding()
        }
    }

    private func checkAccess() async {
        if isOwnPost { hasAccess = true; return }
        guard let type = post.accessType, type != "free" else { hasAccess = true; return }
        do {
            if type == "paid" {
                hasAccess = try await supabase.hasPostAccess(postId: post.id)
            } else if type == "subscription" {
                hasAccess = try await supabase.hasSubscription(to: post.author.userId)
            }
        } catch { hasAccess = false }
    }

    private func purchase() async {
        await MainActor.run { unlocking = true }
        defer { Task { await MainActor.run { unlocking = false } } }
        do {
            try await supabase.purchasePostAccess(postId: post.id, tokens: post.price ?? 0)
            await MainActor.run { hasAccess = true }
        } catch {
            // leave hasAccess as false; button text will revert via defer
        }
    }
    private func subscribe() async {
        do { if let id = try? await supabase.findUserId(byUsername: post.author.username) { try await supabase.subscribeToCreator(creatorId: id, tokens: 0, duration: .monthly); hasAccess = true } } catch {}
    }

    private var overlays: some View {
        ZStack {
            // Bottom gradient for legibility
            LinearGradient(colors: [.black.opacity(0.0), .black.opacity(0.5)], startPoint: .center, endPoint: .bottom)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        if let url = post.author.avatarURL { AsyncAvatar(url: url) }
                        Text(post.author.name ?? "@\(post.author.username)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                    }
                    .onTapGesture { openPoster() }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(post.caption)
                            .font(.footnote)
                            .foregroundStyle(.white)
                            .lineLimit(3)
                        let tags = extractHashtags(post.caption).prefix(3)
                        if !tags.isEmpty {
                            HStack(spacing: 6) {
                                ForEach(Array(tags), id: \.self) { t in
                                    Text("#\(t)")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.white.opacity(0.22))
                                        .clipShape(Capsule())
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            NotificationCenter.default.post(name: .exploreSearch, object: "#\(t)")
                                        }
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.bottom, 28)

                VStack(spacing: 16) {
                    // Avatar with a single overlay button: Follow when not following, Message when following
                    ZStack(alignment: .bottom) {
                        if let url = post.author.avatarURL {
                            AsyncImage(url: url) { img in
                                img.resizable().scaledToFill()
                            } placeholder: { Circle().fill(Color.white.opacity(0.2)) }
                            .frame(width: 44, height: 44)
                            .clipShape(Circle())
                            .overlay(Circle().strokeBorder(.white.opacity(0.5), lineWidth: 1))
                            .onTapGesture { openPoster() }
                        } else {
                            Circle().fill(Color.white.opacity(0.2)).frame(width: 44, height: 44)
                        }
                        if isFollowing {
                            Button(action: { NotificationCenter.default.post(name: .openChatWithUsername, object: post.author.username) }) {
                                Image(systemName: "paperplane.fill")
                                    .font(.caption.weight(.bold))
                                    .padding(6)
                                    .background(.ultraThinMaterial, in: Circle())
                            }
                            .buttonStyle(.plain)
                            .offset(y: 12)
                        } else {
                            Button(action: { Task { await followAuthor() } }) {
                                Image(systemName: "person.badge.plus")
                                    .font(.caption.weight(.bold))
                                    .padding(6)
                                    .background(.ultraThinMaterial, in: Circle())
                            }
                            .buttonStyle(.plain)
                            .offset(y: 12)
                        }
                    }
                    VStack(spacing: 10) {
                        VStack(spacing: 4) {
                            Image(systemName: post.isLiked ? "heart.fill" : "heart")
                                .foregroundStyle(post.isLiked ? .red : .white)
                                .font(.title2.weight(.semibold))
                            Text("\(post.likes)").foregroundStyle(.white).font(.caption2)
                        }
                        .onTapGesture { toggleLike(showBurst: true) }

                        VStack(spacing: 4) {
                            Image(systemName: "message.fill")
                                .foregroundStyle(.white)
                                .font(.title2.weight(.semibold))
                            Text("\(post.comments)").foregroundStyle(.white).font(.caption2)
                        }
                        .onTapGesture { CommentsPresenter.shared.present(postId: post.id) }

                        VStack(spacing: 4) {
                            Image(systemName: "arrowshape.turn.up.forward.fill")
                                .foregroundStyle(.white)
                                .font(.title2.weight(.semibold))
                            Text("\(post.shares)").foregroundStyle(.white).font(.caption2)
                        }
                        .onTapGesture { share() }

                        VStack(spacing: 4) {
                            Image(systemName: "arrow.2.squarepath")
                                .foregroundStyle(.white)
                                .font(.title2.weight(.semibold))
                            Text("\(repostCount)").foregroundStyle(.white).font(.caption2)
                        }
                        .onTapGesture { repost() }
                    }
                }
.padding(.trailing, 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .padding(.leading, 12)
            .padding(.bottom, 0)
        }
        .allowsHitTesting(true)
    }

    private var doubleTap: some Gesture {
        TapGesture(count: 2).onEnded {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                toggleLike(showBurst: true)
            }
        }
    }

    private var singleTap: some Gesture {
        TapGesture(count: 1).onEnded {
            // Pause/play videos, simply toggle overlay mode for images
            isPaused.toggle()
        }
    }

    private var magnifyGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                magnify = min(max(value, 1.0), 3.0)
            }
            .onEnded { _ in
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    if magnify < 1.05 { magnify = 1.0 }
                }
            }
    }

    private func toggleLike(showBurst: Bool = false) {
        var updated = post
        let willLike = !updated.isLiked
        updated.isLiked = willLike
        updated.likes += willLike ? 1 : -1
        post = updated
        if willLike {
            if showBurst { showHeart = true }
        } else {
            showBreak = true
        }
        Task {
            do {
                try await SupabaseManager.shared.setLike(postId: post.id, like: willLike)
            } catch {
                // Revert UI on failure
                await MainActor.run {
                    var reverted = post
                    reverted.isLiked.toggle()
                    reverted.likes += reverted.isLiked ? 1 : -1
                    post = reverted
                }
            }
        }
    }

    private func share() {
        NotificationCenter.default.post(name: .init("share_post"), object: post.id)
    }

    private func openPoster() {
        NotificationCenter.default.post(name: .showGifterProfile, object: post.author.username)
    }

    private func followAuthor() async {
        // Ensure we know author id
        authorUserId = post.author.userId
        guard let id = authorUserId, let me = supabase.user?.id.uuidString, !isOwnPost else { return }
        do {
            struct F: Encodable { let followed_id: String; let follower_id: String }
            _ = try await supabase.client
                .from("follows").insert(F(followed_id: id, follower_id: me))
                .execute()
            await MainActor.run { isFollowing = true }
        } catch {
            // ignore
        }
    }

    private func repost() {
        Task {
            do {
                guard !didRepost else { return }
                try await SupabaseManager.shared.addRepost(postId: post.id)
                await MainActor.run { didRepost = true; repostCount += 1 }
            } catch {
                // swallow for now
            }
        }
    }

    private func preloadFollowState() async {
        guard !isOwnPost else { return }
        guard let me = supabase.user?.id.uuidString else { return }
        do {
            authorUserId = post.author.userId
            let id = post.author.userId
            do {
                let res: PostgrestResponse<[SupabaseManager.CountRow]> = try await supabase.client
                    .from("follows").select("id")
                    .eq("followed_id", value: id)
                    .eq("follower_id", value: me)
                    .limit(1)
                    .execute()
                await MainActor.run { isFollowing = !res.value.isEmpty }
            } catch { }
        }
    }

    private func toggleFollow() async {
        guard let id = authorUserId, let me = supabase.user?.id.uuidString, !isOwnPost else { return }
        do {
            if isFollowing {
                _ = try await supabase.client
                    .from("follows").delete()
                    .eq("followed_id", value: id)
                    .eq("follower_id", value: me)
                    .execute()
                await MainActor.run { isFollowing = false }
            } else {
                struct F: Encodable { let followed_id: String; let follower_id: String }
                _ = try await supabase.client
                    .from("follows").insert(F(followed_id: id, follower_id: me))
                    .execute()
                await MainActor.run { isFollowing = true }
            }
        } catch { }
    }
}

// MARK: - Media Views
private struct ZoomableAsyncImage: View {
    let url: URL
    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let img):
                img.resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .background(Color.black)
            case .failure(_):
                Color.gray
            case .empty:
                ZStack(alignment: .bottom) {
                    Color.black
                    BlinkingLoadingBar()
                }
            @unknown default:
                Color.black
            }
        }
        .ignoresSafeArea()
    }
}

private struct CarouselView: View {
    let urls: [URL]
    @Binding var index: Int
    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $index) {
                ForEach(urls.indices, id: \.self) { i in
                    ZoomableAsyncImage(url: urls[i])
                        .tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            // Custom indicators
            HStack(spacing: 6) {
                ForEach(urls.indices, id: \.self) { i in
                    Circle()
                        .fill(i == index ? Color.white : Color.white.opacity(0.4))
                        .frame(width: 6, height: 6)
                        .onTapGesture { withAnimation { index = i } }
                }
            }
            .padding(.bottom, 24)
        }
        .ignoresSafeArea()
    }
}

private struct VideoBackgroundView: View {
    let url: URL
    var play: Bool
    @State private var player: AVPlayer? = nil
    @State private var endObserver: NSObjectProtocol? = nil
    @State private var timeObserver: Any? = nil
    @State private var showLoadingBar: Bool = true
    @State private var statusObserver: NSKeyValueObservation? = nil
    @State private var showErrorOverlay = false

    var body: some View {
        ZStack(alignment: .bottom) {
            VideoPlayer(player: player)
                .ignoresSafeArea()
            if showLoadingBar { BlinkingLoadingBar() }
            if showErrorOverlay {
                VStack(spacing: 8) {
                    Image(systemName: "play.slash.fill").font(.title).foregroundStyle(.white)
                    Text("Can’t play this video").foregroundStyle(.white)
                }
                .padding(10)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .onAppear {
                if player == nil { player = AVPlayer(url: url) }
                if let p = player, endObserver == nil {
                    endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: p.currentItem, queue: .main) { _ in
                        p.seek(to: .zero)
                        if play { p.play() }
                    }
                    // Hide loading bar once playback advances
                    timeObserver = p.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.2, preferredTimescale: 600), queue: .main) { t in
                        if t.seconds > 0.05 { showLoadingBar = false }
                    }
                    // Also hide when item becomes ready (even if not playing)
                    if let item = p.currentItem {
                        statusObserver = item.observe(\.status, options: [.new]) { it, _ in
                            if it.status == .readyToPlay { showLoadingBar = false; showErrorOverlay = false }
                            if it.status == .failed { showLoadingBar = false; showErrorOverlay = true }
                        }
                    }
                }
                if play { player?.play() }
            }
            .onChange(of: play, perform: { playing in
                if playing { player?.play() } else { player?.pause() }
            })
            .onDisappear {
                player?.pause()
                if let obs = endObserver { NotificationCenter.default.removeObserver(obs) }
                endObserver = nil
                if let to = timeObserver { player?.removeTimeObserver(to); timeObserver = nil }
                statusObserver?.invalidate(); statusObserver = nil
            }
    }

    // No HEAD probing; rely on AVFoundation
}

private struct AsyncAvatar: View {
    let url: URL
    var body: some View {
        AsyncImage(url: url) { img in
            img.resizable().scaledToFill()
        } placeholder: {
            Circle().fill(Color.white.opacity(0.2))
        }
        .frame(width: 28, height: 28)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(.white.opacity(0.3), lineWidth: 1))
    }
}

// (Removed old embedded VerticalPageView; use the shared UI/VerticalPageView.swift)

private func extractHashtags(_ text: String) -> [String] {
    let pattern = "#([A-Za-z0-9_]+)"
    guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return [] }
    let ns = text as NSString
    let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: ns.length))
    return matches.compactMap { m in
        guard m.numberOfRanges > 1 else { return nil }
        return ns.substring(with: m.range(at: 1))
    }
}
    private func shareURL(for post: FeedPost) -> URL {
        // TODO: Build actual deep link for a post
        return URL(string: "https://gifters.club/posts/\(post.id)")!
    }

// MARK: - Tab bar height introspection
private struct TabBarHeightReader: UIViewRepresentable {
    var onUpdate: (CGFloat) -> Void
    func makeUIView(context: Context) -> UIView { Probe(onUpdate: onUpdate) }
    func updateUIView(_ uiView: UIView, context: Context) {}

    private final class Probe: UIView {
        var onUpdate: (CGFloat) -> Void
        init(onUpdate: @escaping (CGFloat) -> Void) { self.onUpdate = onUpdate; super.init(frame: .zero); backgroundColor = .clear }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func didMoveToWindow() { super.didMoveToWindow(); report() }
        override func layoutSubviews() { super.layoutSubviews(); report() }
        private func report() {
            // Ascend responder chain to find a hosting VC, then its tabBarController
            var responder: UIResponder? = self
            while let r = responder { if let vc = r as? UIViewController { if let tb = vc.tabBarController?.tabBar { onUpdate(tb.frame.height); return } }; responder = r.next }
            onUpdate(0)
        }
    }
}
