import SwiftUI
import AVKit
#if canImport(DotLottie)
import DotLottie
#endif

struct PostViewerModel: Identifiable, Hashable {
    enum Media: Hashable { case image(URL), images([URL]), video(URL) }
    let id: String
    let authorUsername: String
    let authorName: String?
    let authorAvatar: URL?
    let caption: String
    let media: Media
}

struct PostViewer: View {
    let model: PostViewerModel
    @State private var isPaused = false
    @State private var magnify: CGFloat = 1.0
    @State private var showLike = false
    @State private var showDislike = false
    @State private var liked = false

    var overlaysHidden: Bool { magnify > 1.01 || isPaused }

    var body: some View {
        ZStack {
            content
                .scaleEffect(isPaused ? 1.03 : 1.0)
                .animation(.easeInOut(duration: 0.2), value: isPaused)
                .scaleEffect(magnify)
                .gesture(singleTap)
                .simultaneousGesture(magnifyGesture)

            if showLike {
                #if canImport(DotLottie)
                DotLottieAnimation(webURL: "https://lottie.host/fe660a41-2c70-4105-afb4-bab713f7e77b/AcLybokfnG.lottie", config: AnimationConfig(autoplay: true, loop: false)).view()
                    .frame(width: 220, height: 220)
                    .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { showLike = false } }
                #else
                Image(systemName: "heart.fill").font(.system(size: 120)).foregroundStyle(.red)
                    .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { showLike = false } }
                #endif
            }
            if showDislike {
                #if canImport(DotLottie)
                DotLottieAnimation(webURL: "https://lottie.host/810116a8-7247-45df-a8b2-f2d777b491f0/JDVtLuvkEG.lottie", config: AnimationConfig(autoplay: true, loop: false)).view()
                    .frame(width: 200, height: 200)
                    .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { showDislike = false } }
                #endif
            }

            if !overlaysHidden { overlays }
        }
        .simultaneousGesture(doubleTap)
        .background(Color.black.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var content: some View {
        switch model.media {
        case .image(let url): ZoomableAsyncImage(url: url)
        case .images(let urls): Carousel(urls: urls)
        case .video(let url): AutoPlayVideo(url: url, play: !isPaused)
        }
    }

    private var overlays: some View {
        VStack { Spacer()
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        if let a = model.authorAvatar {
                            AsyncImage(url: a) { $0.resizable().scaledToFill() } placeholder: { Color.white.opacity(0.2) }
                                .frame(width: 28, height: 28)
                                .clipShape(Circle())
                        }
                        Text(model.authorName ?? "@\(model.authorUsername)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        NotificationCenter.default.post(name: .showGifterProfile, object: model.authorUsername)
                    }
                    if !model.caption.isEmpty {
                        Text(model.caption)
                            .font(.footnote)
                            .foregroundStyle(.white)
                            .lineLimit(3)
                        let tags = extractHashtags(model.caption)
                        if !tags.isEmpty {
                            WrapTagsView(tags: tags)
                        }
                    }
                }
                Spacer()
                VStack(spacing: 18) {
                    Image(systemName: liked ? "heart.fill" : "heart")
                        .foregroundStyle(liked ? .red : .white)
                        .font(.title2.weight(.semibold))
                        .onTapGesture { like() }
                    Image(systemName: "arrowshape.turn.up.forward.fill")
                        .foregroundStyle(.white)
                        .font(.title2.weight(.semibold))
                    Image(systemName: "message.fill")
                        .foregroundStyle(.white)
                        .font(.title2.weight(.semibold))
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 24 + CustomBottomBar.barHeight)
        }
    }

    private var doubleTap: some Gesture { TapGesture(count: 2).onEnded { like() } }
    private var singleTap: some Gesture { TapGesture(count: 1).onEnded { isPaused.toggle() } }
    private var magnifyGesture: some Gesture {
        MagnificationGesture().onChanged { v in magnify = min(max(v, 1.0), 3.0) }.onEnded { _ in withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { if magnify < 1.05 { magnify = 1.0 } } }
    }
    private func like() {
        let willLike = !liked
        liked = willLike
        if willLike {
            if showDislike { showDislike = false }
            showLike = true
        } else {
            showDislike = true
        }
        Task {
            do { try await SupabaseManager.shared.setLike(postId: model.id, like: willLike) }
            catch {
                await MainActor.run { liked.toggle() }
            }
        }
    }
}

private struct AutoPlayVideo: View {
    let url: URL
    var play: Bool
    @State private var player: AVPlayer? = nil
    var body: some View {
        VideoPlayer(player: player)
            .onAppear { if player == nil { player = AVPlayer(url: url) }; if play { player?.play() } }
            .onChange(of: play) { _, p in if p { player?.play() } else { player?.pause() } }
            .onDisappear { player?.pause() }
            .ignoresSafeArea()
    }
}

private struct ZoomableAsyncImage: View {
    let url: URL
    var body: some View {
        GeometryReader { geo in
            AsyncImage(url: url) { img in
                img.resizable().scaledToFit().frame(maxWidth: geo.size.width, maxHeight: geo.size.height)
            } placeholder: { Color.black }
        }.ignoresSafeArea()
    }
}

// MARK: - Hashtag Pills
private struct WrapTagsView: View {
    let tags: [String]
    var body: some View {
        // Simple horizontal flow; wraps naturally across lines in SwiftUI when embedded in VStack
        // because we’ll chunk into rows by width if needed. For simplicity, just a horizontal scroll for now.
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(tags.prefix(6), id: \.self) { t in
                    Text("#\(t)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.white.opacity(0.22))
                        .clipShape(Capsule())
                        .contentShape(Rectangle())
                        .onTapGesture { NotificationCenter.default.post(name: .exploreSearch, object: "#\(t)") }
                }
            }
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

private struct Carousel: View { let urls: [URL]; @State private var idx = 0
    var body: some View {
        TabView(selection: $idx) { ForEach(urls.indices, id: \.self) { i in ZoomableAsyncImage(url: urls[i]).tag(i) } }
            .tabViewStyle(.page(indexDisplayMode: .automatic))
            .ignoresSafeArea()
    }
}
