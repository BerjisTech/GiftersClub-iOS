import SwiftUI
import AVKit
import UIKit
#if canImport(DotLottie)
import DotLottie
#endif

struct FeedPost: Identifiable, Hashable {
    struct Author: Hashable { let username: String; let name: String?; let avatarURL: URL? }
    enum Media: Hashable { case image(URL); case video(URL); case images([URL]) }
    let id: String
    let author: Author
    let caption: String
    let media: Media
    var likes: Int
    var comments: Int
    var shares: Int
    var isLiked: Bool
}

struct HomeView: View {
    @ObservedObject private var supabase = SupabaseManager.shared
    @State private var posts: [FeedPost] = []
    @State private var selection: Int = 0
    @State private var isLoading = false
    @State private var offset: Int = 0
    @ObservedObject private var commentsPresenter = CommentsPresenter.shared
    @State private var tabBarHeight: CGFloat = 0
    @State private var sharePost: FeedPost? = nil

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let fullHeight = size.height + proxy.safeAreaInsets.bottom
            VerticalPageView(items: posts, selection: $selection) { idx, _ in
                PostPageView(post: $posts[idx], isActive: selection == idx, bottomSafeInset: proxy.safeAreaInsets.bottom, tabBarHeight: tabBarHeight)
                    .frame(width: size.width, height: fullHeight)
            }
            .frame(width: size.width, height: fullHeight)
            .background(Color.black.ignoresSafeArea())
            .ignoresSafeArea(edges: [.top, .bottom])
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
    }

    private func initialLoad() async { await refresh() }

    private func refresh() async {
        await MainActor.run { isLoading = true }
        defer { Task { await MainActor.run { isLoading = false } } }
        do {
            let rows = try await supabase.fetchFeed(limit: 10, offset: 0)
            let mapped = rows.compactMap(mapRow)
            await MainActor.run {
                posts = mapped
                selection = 0
                offset = mapped.count
            }
        } catch {
            // Keep old posts on failure
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
            username: r.profile?.username ?? "unknown",
            name: r.profile?.username,
            avatarURL: r.profile?.image.flatMap(URL.init(string:))
        )
        let caption = r.content ?? ""
        return FeedPost(
            id: r.id,
            author: author,
            caption: caption,
            media: media,
            likes: r.like_count ?? 0,
            comments: r.comment_count ?? 0,
            shares: r.share_count ?? 0,
            isLiked: false
        )
    }
}

// MARK: - Post Page
private struct PostPageView: View {
    @Binding var post: FeedPost
    let isActive: Bool
    let bottomSafeInset: CGFloat
    let tabBarHeight: CGFloat

    @State private var magnify: CGFloat = 1.0
    @State private var isPaused: Bool = false
    @State private var showHeart: Bool = false
    @State private var showBreak: Bool = false
    @State private var activeImageIndex: Int = 0

    var overlaysHidden: Bool { magnify > 1.01 || isPaused }

    var body: some View {
        ZStack {
            content
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
        }
        .simultaneousGesture(doubleTap)
        .onChange(of: isActive) { _, active in
            if !active { isPaused = false; magnify = 1.0 }
        }
        .background(Color.black)
    }

    @ViewBuilder
    private var content: some View {
        switch post.media {
        case .image(let url):
            ZoomableAsyncImage(url: url)
        case .images(let urls):
            CarouselView(urls: urls, index: $activeImageIndex)
        case .video(let url):
            VideoBackgroundView(url: url, play: isActive && !isPaused)
        }
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
                                        .foregroundStyle(.white.opacity(0.9))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.white.opacity(0.2))
                                        .clipShape(Capsule())
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
        Task { try? await SupabaseManager.shared.setLike(postId: post.id, like: willLike) }
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

// MARK: - Vertical Pager (TabView rotated hack)
// MARK: - Vertical UIPageViewController wrapper for perfect paging
private struct VerticalPageView<Data: RandomAccessCollection, Content: View>: UIViewControllerRepresentable where Data.Element: Identifiable, Data.Element.ID: Hashable {
    typealias UIViewControllerType = UIPageViewController
    var items: Data
    @Binding var selection: Int
    var content: (Int, Data.Element) -> Content

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIPageViewController {
        let vc = UIPageViewController(transitionStyle: .scroll, navigationOrientation: .vertical)
        vc.dataSource = context.coordinator
        vc.delegate = context.coordinator
        context.coordinator.reloadPages(controller: vc)
        return vc
    }

    func updateUIViewController(_ uiViewController: UIPageViewController, context: Context) {
        context.coordinator.parent = self
        // Rebuild pages if the data set size or identity changed
        if context.coordinator.needsReload(for: items) {
            context.coordinator.reloadPages(controller: uiViewController)
        } else {
            // Otherwise, update existing controllers' root views to reflect state changes
            context.coordinator.updatePages()
        }
        // Only jump if selection differs from current visible index
        if let current = uiViewController.viewControllers?.first,
           let currentIndex = context.coordinator.index(of: current),
           currentIndex != selection {
            context.coordinator.goTo(targetIndex: selection, controller: uiViewController, animated: false)
        }
    }

    final class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
        var parent: VerticalPageView
        var controllers: [UIHostingController<AnyView>] = []
        private var lastIDs: [Data.Element.ID] = []

        init(_ parent: VerticalPageView) { self.parent = parent }

        func viewController(at index: Int) -> UIViewController? {
            guard index >= 0 && index < controllers.count else { return nil }
            return controllers[index]
        }

        func index(of viewController: UIViewController) -> Int? {
            controllers.firstIndex(where: { $0 === viewController })
        }

        func reloadPages(controller: UIPageViewController) {
            lastIDs = parent.items.map { $0.id }
            controllers = parent.items.enumerated().map { idx, item in
                let host = UIHostingController(rootView: AnyView(parent.content(idx, item)))
                host.view.backgroundColor = .clear
                return host
            }
            let initial = viewController(at: min(max(parent.selection, 0), max(controllers.count - 1, 0)))
            if let initial { controller.setViewControllers([initial], direction: .forward, animated: false) }
        }

        func needsReload(for items: Data) -> Bool {
            let ids = items.map { $0.id }
            return ids != lastIDs || items.count != lastIDs.count
        }

        func updatePages() {
            for (idx, item) in parent.items.enumerated() {
                if idx < controllers.count {
                    controllers[idx].rootView = AnyView(parent.content(idx, item))
                }
            }
        }

        func goTo(targetIndex: Int, controller: UIPageViewController, animated: Bool) {
            guard let current = controller.viewControllers?.first,
                  let currentIndex = self.index(of: current),
                  targetIndex != currentIndex,
                  let dest = viewController(at: targetIndex) else { return }
            let direction: UIPageViewController.NavigationDirection = targetIndex > currentIndex ? .forward : .reverse
            controller.setViewControllers([dest], direction: direction, animated: animated)
        }

        // MARK: DataSource
        func pageViewController(_ pageViewController: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {
            guard let idx = index(of: viewController) else { return nil }
            return self.viewController(at: idx - 1)
        }
        func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
            guard let idx = index(of: viewController) else { return nil }
            return self.viewController(at: idx + 1)
        }

        // MARK: Delegate
        func pageViewController(_ pageViewController: UIPageViewController, didFinishAnimating finished: Bool, previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
            guard completed, let current = pageViewController.viewControllers?.first, let idx = index(of: current) else { return }
            parent.selection = idx
        }
    }
}

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
