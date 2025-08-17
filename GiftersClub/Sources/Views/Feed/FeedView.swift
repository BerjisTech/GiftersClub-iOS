import SwiftUI
import AVKit
import UIKit
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

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let fullHeight = size.height
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
                    LiveCardView(live: live)
                        .frame(width: size.width, height: fullHeight)
                }
            }
            .frame(width: size.width, height: fullHeight)
            .background(Color.black)
            .ignoresSafeArea(edges: [.bottom])
            // Custom bottom bar is separate now; no need to offset by system tab bar height
        }
        .task { await initialLoad() }
        .refreshable { await refresh() }
        .loadingOverlay(isLoading)
        .sheet(isPresented: $commentsPresenter.isPresented) {
            if let id = commentsPresenter.postId {
                CommentsSheet(postId: id)
            }
        }
        .sheet(item: $sharePost) { post in
            ShareOptionsSheet(url: shareURL(for: post))
        }
        .onReceive(NotificationCenter.default.publisher(for: .init("share_post"))) { note in
            guard let id = note.object as? String, let p = posts.first(where: { $0.id == id }) else { return }
            sharePost = p
        }
        .onChange(of: selection) { _, newIndex in
            // Load more when near the end
            if newIndex >= posts.count - 3 {
                Task { await loadMoreIfNeeded() }
            }
        }
    }

    private func initialLoad() async { await refresh() }

    private func refresh() async {
        await MainActor.run { isLoading = true }
        defer { Task { await MainActor.run { isLoading = false } } }
        do {
            #if DEBUG
            print("[Feed] fetching posts limit=10 offset=0")
            #endif
            let rows = try await supabase.fetchFeed(limit: 10, offset: 0)
            var mapped = rows.compactMap(mapRow)
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
        } catch {
            // Keep old posts on failure
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
            let rows = try await supabase.fetchFeed(limit: 10, offset: offset)
            let mapped = rows.compactMap(mapRow)
            if mapped.isEmpty { return }
            // Refresh lives for this page and merge with existing items
            let lives = try? await supabase.fetchFeedLiveStreams(limit: max(1, mapped.count / 3), query: nil)
            let newItems = interleave(posts: mapped, lives: lives ?? [])
            await MainActor.run {
                posts.append(contentsOf: mapped)
                items.append(contentsOf: newItems)
                offset += mapped.count
            }
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
    var body: some View {
        ZStack(alignment: .bottom) {
            ZStack {
                if let t = live.thumbnail_url, let url = URL(string: t) {
                    AsyncImage(url: url) { img in
                        img.resizable().scaledToFill()
                    } placeholder: { Color.black }
                } else {
                    Color.black
                }
                LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .top, endPoint: .bottom)
            }
            .ignoresSafeArea()
            .clipped()
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    NavigationLink(destination: LiveViewerView(live: live)) {
                        Text("LIVE NOW").font(.caption.bold()).foregroundStyle(.white).padding(.horizontal, 8).padding(.vertical, 4).background(Color.red).clipShape(Capsule())
                    }
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
        .task {
            if profile == nil { if let p = try? await supabase.fetchProfileByUserId(live.host_id) { await MainActor.run { profile = p } } }
            timer?.invalidate()
            timer = Timer.scheduledTimer(withTimeInterval: 6.0, repeats: true) { _ in
                Task { if let row = try? await supabase.fetchLiveStreamById(live.id) { await MainActor.run { viewerCount = row.viewer_count } } }
            }
        }
        .onDisappear { timer?.invalidate(); timer = nil }
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
    @State private var activeImageIndex: Int = 0
    @State private var hasAccess: Bool = true
    @State private var unlocking: Bool = false
    @ObservedObject private var supabase = SupabaseManager.shared

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
        .onChange(of: isActive) { _, active in
            if !active { isPaused = false; magnify = 1.0 }
        }
        .background(Color.black)
        .onAppear {
            if let t = post.accessType, t != "free", !isOwnPost { hasAccess = false }
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
                if let id = try? await supabase.findUserId(byUsername: post.author.username) {
                    hasAccess = try await supabase.hasSubscription(to: id)
                } else { hasAccess = false }
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

                VStack(spacing: 18) {
                    VStack(spacing: 4) {
                        Image(systemName: post.isLiked ? "heart.fill" : "heart")
                            .foregroundStyle(post.isLiked ? .red : .white)
                            .font(.title2.weight(.semibold))
                        Text("\(post.likes)").foregroundStyle(.white).font(.caption2)
                    }
                    .onTapGesture { toggleLike(showBurst: true) }

                    VStack(spacing: 4) {
                        Image(systemName: "arrowshape.turn.up.forward.fill")
                            .foregroundStyle(.white)
                            .font(.title2.weight(.semibold))
                        Text("\(post.shares)").foregroundStyle(.white).font(.caption2)
                    }
                    .onTapGesture { share() }

                    VStack(spacing: 4) {
                        Image(systemName: "message.fill")
                            .foregroundStyle(.white)
                            .font(.title2.weight(.semibold))
                        Text("\(post.comments)").foregroundStyle(.white).font(.caption2)
                    }
                    .onTapGesture { CommentsPresenter.shared.present(postId: post.id) }
                }
                .padding(.trailing, 12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .padding(.horizontal, 12)
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
            case .failure(_): Color.gray
            case .empty: Color.black
            @unknown default: Color.black
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

    var body: some View {
        VideoPlayer(player: player)
            .ignoresSafeArea()
            .onAppear {
                if player == nil { player = AVPlayer(url: url) }
                if play { player?.play() }
            }
            .onChange(of: play) { _, playing in
                if playing { player?.play() } else { player?.pause() }
            }
            .onDisappear { player?.pause() }
    }
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
        return URL(string: "https://gifter.club/posts/\(post.id)")!
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
