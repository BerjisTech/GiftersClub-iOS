import SwiftUI

private enum ExploreTab: String, CaseIterable { case top = "Top", photos = "Photos", videos = "Videos", users = "Users", live = "Live" }

struct ExploreView: View {
    @Binding var externalQuery: String?
    @State private var query: String = ""
    @State private var activeTab: ExploreTab = .top
    @State private var isSearching = false
    @State private var results: SupabaseManager.ExploreResult? = nil
    @State private var recentSuggestions: [String] = []
    @State private var trendingSuggestions: [String] = []
    @State private var selectedPost: SupabaseManager.ExplorePost? = nil
    @State private var selectedUser: SupabaseManager.ExploreUser? = nil
    @FocusState private var focused: Bool
    private let supabase = SupabaseManager.shared

    @State private var searchBarHeight: CGFloat = 56
    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                VStack(spacing: 0) {
                    if showSuggestions {
                        suggestionsView
                    } else {
                        tabsBar
                        Divider()
                        resultsView
                    }
                }
                .padding(.top, searchBarHeight)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                // Pinned search bar overlay measured for exact height (prevents jump and gaps)
                searchBar
                    .background(.ultraThinMaterial)
                    .background(GeometryReader { geo in
                        Color.clear.preference(key: SearchBarHeightKey.self, value: geo.size.height)
                    })
            }
            .onPreferenceChange(SearchBarHeightKey.self) { searchBarHeight = $0 }
            .ignoresSafeArea(.keyboard, edges: .bottom)
            .navigationBarHidden(true)
            .refreshable {
                if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    await search(query)
                } else {
                    await loadSuggestions()
                }
            }
            .navigationDestinationCompat(item: $selectedPost) { post in
                let media: PostViewerModel.Media = {
                    if let first = post.media?.first, let u = first.url, let url = URL(string: u) {
                        if first.media_type == "video" { return .video(url) }
                        return .image(url)
                    }
                    return .images([])
                }()
                PostViewer(model: .init(
                    id: post.id,
                    authorUsername: post.profile?.username ?? "",
                    authorName: post.profile?.name,
                    authorAvatar: post.profile?.image.flatMap(URL.init(string:)),
                    caption: post.content ?? "",
                    media: media
                ))
            }
            .navigationDestinationCompat(item: $selectedUser) { user in
                // Use wrapper that provides required environment objects (banners, drawer)
                GifterProfileView(username: user.username)
            }
            .task { await loadSuggestions() }
            .onAppear { consumeExternalQueryIfNeeded() }
            .onChange(of: externalQuery, perform: { _ in consumeExternalQueryIfNeeded() })
        }
    }

    init(externalQuery: Binding<String?> = .constant(nil)) {
        self._externalQuery = externalQuery
    }

private struct SearchBarHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 56
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search", text: $query)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .focused($focused)
                .onChange(of: query, perform: { new in debounceSearch(new) })
            if isSearching && !query.isEmpty {
                ProgressView().progressViewStyle(.circular)
            } else if !query.isEmpty {
                Button(action: { query = ""; results = nil }) { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemGray6)))
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private var tabsBar: some View {
        HStack(spacing: 6) {
            ForEach(ExploreTab.allCases, id: \.self) { tab in
                Button(action: { withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) { activeTab = tab } }) {
                    Text(tab.rawValue)
                        .font(.subheadline.weight(activeTab == tab ? .semibold : .regular))
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 10).fill(activeTab == tab ? Color(.systemGray5) : .clear))
                }
            }
            Spacer()
        }
        .padding(.horizontal)
        .padding(.top, 6)
        .padding(.bottom, 4)
    }

    private var showSuggestions: Bool { results == nil && query.isEmpty }

    private var suggestionsView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if !recentSuggestions.isEmpty {
                    Text("Recent searches").font(.caption).foregroundStyle(.secondary).padding(.horizontal)
                    ForEach(recentSuggestions, id: \.self) { s in
                        Button(action: { runSearch(s) }) {
                            HStack { Image(systemName: "clock"); Text(s); Spacer() }
                                .padding(.horizontal)
                                .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
                    }
                }
                if !trendingSuggestions.isEmpty {
                    Text("Trending").font(.caption).foregroundStyle(.secondary).padding(.horizontal)
                    ForEach(trendingSuggestions, id: \.self) { s in
                        Button(action: { runSearch(s) }) {
                            HStack { Image(systemName: "sparkles"); Text(s); Spacer() }
                                .padding(.horizontal)
                                .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.top, 8)
        }
    }

    private var resultsView: some View {
        Group {
            if let r = results {
                switch activeTab {
                case .top:
                    // Unified interstitial feed: posts (2-up), users (full-width), and lives mixed in
                    ExploreUnifiedFeed(query: query, posts: r.top, users: r.users,
                                        onSelectPost: { p in selectedPost = p },
                                        onSelectUser: { u in selectedUser = u })
                case .photos:
                    ExplorePostsGrid(posts: r.photos) { p in selectedPost = p }
                case .videos:
                    ExplorePostsGrid(posts: r.videos) { p in selectedPost = p }
                case .users:
                    ExploreUsersList(users: r.users) { u in selectedUser = u }
                case .live:
                    ExploreLiveGrid(query: query)
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Search for posts and people").foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal)
                .padding(.top, 24)
            }
        }
    }

    // MARK: - Search logic
    @State private var debounceTask: Task<Void, Never>? = nil
    private func debounceSearch(_ text: String) {
        debounceTask?.cancel()
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        debounceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            await search(text)
        }
    }

    private func runSearch(_ text: String) {
        query = text
        focused = false
        Task { await search(text) }
    }

    private func search(_ text: String) async {
        await MainActor.run { isSearching = true }
        defer { Task { await MainActor.run { isSearching = false } } }
        do {
            let r = try await supabase.searchExplore(query: text)
            await MainActor.run {
                results = r
                Task { await supabase.recordSearchQuery(text); await loadSuggestions() }
            }
        } catch {
            // Keep existing results on error
        }
    }

    private func loadSuggestions() async {
        async let rec = supabase.fetchRecentSearches(limit: 8)
        async let trend = supabase.fetchTrendingSearches(limit: 8)
        let (a, b) = await ( (try? rec) ?? [], (try? trend) ?? [] )
        // Remove recent items from trending to avoid duplication in UI
        let recSet = Set(a.map { $0.lowercased() })
        let filteredTrend = b.filter { !recSet.contains($0.lowercased()) }
        await MainActor.run { recentSuggestions = a; trendingSuggestions = filteredTrend }
    }

    private func consumeExternalQueryIfNeeded() {
        guard let q = externalQuery, !q.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        externalQuery = nil
        runSearch(q)
    }
}

// MARK: - Live Explore UI Parts
private struct ExploreLiveRow: View {
    @State private var lives: [SupabaseManager.DBLiveStreamWithStats] = []
    @State private var isLoading = false
    private let supabase = SupabaseManager.shared
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                if isLoading {
                    ForEach(0..<3, id: \.self) { _ in
                        ShimmerView().frame(width: 260, height: 150).clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                } else {
                    ForEach(lives, id: \.id) { l in
                        NavigationLink(destination: LiveEntryDestination(live: l)) {
                            LiveCardCell(live: l)
                                .frame(width: 260, height: 150)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .simultaneousGesture(TapGesture().onEnded { NotificationCenter.default.post(name: .hideBottomBar, object: nil) })
                    }
                }
            }.padding(.horizontal)
        }
        .task { await load() }
        .refreshable { await load() }
    }
    private func load() async {
        await MainActor.run { isLoading = true }
        let r = try? await supabase.fetchFeedLiveStreams(limit: 8, query: nil)
        await MainActor.run { lives = r ?? []; isLoading = false }
    }
}

private struct ExploreLiveGrid: View {
    let query: String
    @State private var lives: [SupabaseManager.DBLiveStreamWithStats] = []
    @State private var isLoading = false
    private let supabase = SupabaseManager.shared
    private let columns = [GridItem(.flexible()), GridItem(.flexible())]
    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 10) {
                if isLoading {
                    ForEach(0..<6, id: \.self) { _ in ShimmerView().frame(height: 160).clipShape(RoundedRectangle(cornerRadius: 12)) }
                } else {
                    ForEach(lives, id: \.id) { l in
                        NavigationLink(destination: LiveEntryDestination(live: l)) {
                            LiveCardCell(live: l)
                                .frame(height: 160)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .simultaneousGesture(TapGesture().onEnded { NotificationCenter.default.post(name: .hideBottomBar, object: nil) })
                    }
                }
            }.padding(.horizontal)
        }
        .task { await load(for: query) }
        .refreshable { await load(for: query) }
        .onChange(of: query) { newValue in
            Task { await load(for: newValue) }
        }
    }
    private func load(for query: String) async {
        await MainActor.run { isLoading = true }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let r = try? await supabase.fetchFeedLiveStreams(limit: 20, query: trimmed.isEmpty ? nil : trimmed)
        await MainActor.run { lives = r ?? []; isLoading = false }
    }
}

private struct LiveCardCell: View {
    let live: SupabaseManager.DBLiveStreamWithStats
    @State private var profile: SupabaseManager.DBProfile? = nil
    private let supa = SupabaseManager.shared
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            ZStack {
                if let t = live.thumbnail_url, let url = URL(string: t) {
                    AsyncImage(url: url) { img in img.resizable().scaledToFill() } placeholder: { Color.black }
                } else { Color.black }
                LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .top, endPoint: .bottom)
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text("LIVE").font(.caption.bold()).foregroundStyle(.white).padding(.horizontal, 8).padding(.vertical, 2).background(Color.red).clipShape(Capsule())
                    Spacer()
                    Label("\(live.viewer_count ?? 0)", systemImage: "eye.fill").foregroundStyle(.white).font(.caption2)
                }
                if let p = profile {
                    HStack(spacing: 6) {
                        if let img = p.image, let u = URL(string: img) {
                            AsyncImage(url: u) { i in i.resizable().scaledToFill() } placeholder: { Color.white.opacity(0.2) }
                                .frame(width: 20, height: 20).clipShape(Circle())
                        }
                        Text(p.name ?? p.username).font(.caption.weight(.semibold)).foregroundStyle(.white)
                    }
                }
                Text(live.title).font(.subheadline.weight(.semibold)).foregroundStyle(.white).lineLimit(2)
            }
            .padding(8)
        }
        .background(Color.black)
        .task { if profile == nil { if let p = try? await supa.fetchProfileByUserId(live.host_id) { profile = p } } }
    }
}

// MARK: - Results UI
private struct ExplorePostsGrid: View {
    let posts: [SupabaseManager.ExplorePost]
    var onSelect: (SupabaseManager.ExplorePost) -> Void = { _ in }
    private let columns = [GridItem(.flexible()), GridItem(.flexible())]
    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(posts, id: \.id) { p in
                    let media: LockablePostCard.MediaKind? = {
                        if let first = p.media?.first, let u = first.url, let url = URL(string: u) {
                            return (first.media_type == "video") ? .video(url) : .image(url)
                        }
                        return nil
                    }()
                    LockablePostCard(
                        postId: p.id,
                        authorUserId: p.user_id,
                        accessType: p.access_type,
                        price: p.price,
                        media: media,
                        isLong: false,
                        onTapUnlocked: { onSelect(p) }
                    )
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)
        }
    }
}

private struct ExplorePostCard: View {
    let post: SupabaseManager.ExplorePost
    @ObservedObject private var supabase = SupabaseManager.shared
    @State private var showPaywall = false
    @State private var hasAccess: Bool
    init(post: SupabaseManager.ExplorePost) {
        self.post = post
        self._hasAccess = State(initialValue: (post.access_type ?? "free") == "free")
    }
    var body: some View {
        let isOwner = (supabase.user?.id.uuidString ?? "") == post.user_id
        ZStack(alignment: .bottomLeading) {
            if let media = post.media, let first = media.first {
                if first.media_type == "photo", let u = first.url, let url = URL(string: u) {
                    GeometryReader { geo in
                        AsyncImage(url: url) { img in
                            img.resizable().scaledToFill()
                                .frame(width: geo.size.width, height: geo.size.height)
                                .clipped()
                                .blur(radius: (hasAccess || isOwner) ? 0 : 12)
                        } placeholder: { Color(.secondarySystemBackground) }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                } else if first.media_type == "video", let u = first.url, let url = URL(string: u) {
                    GeometryReader { geo in
                        VideoThumbnail(url: url)
                            .frame(width: geo.size.width, height: geo.size.height)
                            .clipped()
                            .blur(radius: (hasAccess || isOwner) ? 0 : 12)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(alignment: .center) { Image(systemName: "play.circle.fill").font(.system(size: 36)).foregroundStyle(.white) }
                } else { Color(.secondarySystemBackground).clipShape(RoundedRectangle(cornerRadius: 12)) }
            } else { Color(.secondarySystemBackground).clipShape(RoundedRectangle(cornerRadius: 12)) }
            if let prof = post.profile { Text(prof.username ?? "").font(.caption).foregroundStyle(.white).padding(6) }
            if let type = post.access_type, type != "free" {
                if !hasAccess && !isOwner {
                    RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.35))
                }
                VStack { HStack { Spacer(); Image(systemName: "lock.fill").foregroundStyle(.white).padding(6) } ; Spacer() }
            }
        }
        .sheet(isPresented: $showPaywall) {
            if post.access_type == "subscription" {
                PaywallSheet(mode: .subscription(creatorId: post.user_id), onUnlocked: { hasAccess = true })
            } else if post.access_type == "paid" {
                PaywallSheet(mode: .paid(postId: post.id, price: post.price ?? 0), onUnlocked: { hasAccess = true })
            }
        }
        .onTapGesture { Task { await handleTap(isOwner: isOwner) } }
        .task { await initialCheck(isOwner: isOwner) }
    }
    private func handleTap(isOwner: Bool) async {
        if isOwner { return }
        let type = post.access_type ?? "free"
        guard type != "free" else { return }
        do {
            if type == "paid" {
                let has = try await supabase.hasPostAccess(postId: post.id)
                if !has { showPaywall = true }
            } else if type == "subscription" {
                let has = try await supabase.hasSubscription(to: post.user_id)
                if !has { showPaywall = true }
            }
        } catch { showPaywall = true }
    }
    private func initialCheck(isOwner: Bool) async {
        let type = post.access_type ?? "free"
        if isOwner { hasAccess = true; return }
        if type == "free" { hasAccess = true; return }
        do {
            if type == "paid" {
                hasAccess = try await supabase.hasPostAccess(postId: post.id)
            } else if type == "subscription" {
                hasAccess = try await supabase.hasSubscription(to: post.user_id)
            }
        } catch { hasAccess = false }
    }
}

private struct ExploreUsersList: View {
    let users: [SupabaseManager.ExploreUser]
    var onSelect: (SupabaseManager.ExploreUser) -> Void = { _ in }
    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                ForEach(users, id: \.user_id) { u in
                    HStack(spacing: 10) {
                        if let img = u.image, let url = URL(string: img) {
                            AsyncImage(url: url) { img in img.resizable().scaledToFill() } placeholder: { Color(.systemGray4) }
                                .frame(width: 36, height: 36).clipShape(Circle())
                        } else { Circle().fill(Color(.systemGray4)).frame(width: 36, height: 36) }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(u.name ?? u.username).font(.subheadline)
                            Text("@\(u.username)").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemGray6)))
                    .padding(.horizontal)
                    .contentShape(Rectangle())
                    .onTapGesture { onSelect(u) }
                }
            }
            .padding(.top, 8)
        }
    }
}

// MARK: - Unified interleaved feed (Top tab)
private struct ExploreUnifiedFeed: View {
    let query: String
    let posts: [SupabaseManager.ExplorePost]
    let users: [SupabaseManager.ExploreUser]
    var onSelectPost: (SupabaseManager.ExplorePost) -> Void = { _ in }
    var onSelectUser: (SupabaseManager.ExploreUser) -> Void = { _ in }
    @State private var lives: [SupabaseManager.DBLiveStreamWithStats] = []
    private let supabase = SupabaseManager.shared

    enum Item: Identifiable {
        case posts([SupabaseManager.ExplorePost])
        case user(SupabaseManager.ExploreUser)
        case live(SupabaseManager.DBLiveStreamWithStats)
        var id: String {
            switch self {
            case .posts(let ps): return "posts:" + ps.map { $0.id }.joined(separator: ",")
            case .user(let u): return "user:" + u.user_id
            case .live(let l): return "live:" + l.id
            }
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(buildItems()) { item in
                    switch item {
                    case .posts(let pair):
                        HStack(spacing: 10) {
                            if let first = pair.first {
                                let media: LockablePostCard.MediaKind? = first.media?.first.flatMap { m in
                                    guard let u = m.url, let url = URL(string: u) else { return nil }
                                    return (m.media_type == "video") ? .video(url) : .image(url)
                                }
                                LockablePostCard(
                                    postId: first.id,
                                    authorUserId: first.user_id,
                                    accessType: first.access_type,
                                    price: first.price,
                                    media: media,
                                    isLong: false,
                                    onTapUnlocked: { onSelectPost(first) }
                                )
                            }
                            if pair.count > 1, let second = pair.dropFirst().first {
                                let media2: LockablePostCard.MediaKind? = second.media?.first.flatMap { m in
                                    guard let u = m.url, let url = URL(string: u) else { return nil }
                                    return (m.media_type == "video") ? .video(url) : .image(url)
                                }
                                LockablePostCard(
                                    postId: second.id,
                                    authorUserId: second.user_id,
                                    accessType: second.access_type,
                                    price: second.price,
                                    media: media2,
                                    isLong: false,
                                    onTapUnlocked: { onSelectPost(second) }
                                )
                            } else {
                                Color.clear.frame(height: 200)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal)
                    case .user(let u):
                        ExploreUserPill(user: u)
                            .padding(.horizontal)
                            .contentShape(Rectangle())
                            .onTapGesture { onSelectUser(u) }
                        Divider().padding(.horizontal)
                    case .live(let l):
                        // Use the same live card as Home feed for visual parity
                        NavigationLink(destination: LiveEntryDestination(live: l)) {
                            LiveCardView(live: l)
                                .frame(maxWidth: .infinity)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .simultaneousGesture(TapGesture().onEnded { NotificationCenter.default.post(name: .hideBottomBar, object: nil) })
                        .padding(.horizontal)
                    }
                }
            }
            .padding(.top, 8)
        }
        .task { await loadLives(for: query) }
        .task {
            // Prefetch access and subscriptions for visible items to avoid N+1 checks
            let postIds = posts.map { $0.id }
            var creatorIds = Set(posts.map { $0.user_id })
            for u in users { creatorIds.insert(u.user_id) }
            await supabase.prefetchAccess(posts: postIds, creators: Array(creatorIds))
        }
        .onChange(of: query) { _ in
            Task { await loadLives(for: query) }
        }
    }

    private func buildItems() -> [Item] {
        // Pair posts two per row
        let pairs: [[SupabaseManager.ExplorePost]] = stride(from: 0, to: posts.count, by: 2).map { i in
            var arr: [SupabaseManager.ExplorePost] = []
            arr.append(posts[i])
            if i + 1 < posts.count { arr.append(posts[i+1]) }
            return arr
        }
        var out: [Item] = []
        var uIndex = 0
        var lIndex = 0
        var sinceUser = 0
        var sinceLive = 0
        for pair in pairs {
            out.append(.posts(pair))
            sinceUser += 1
            sinceLive += 1
            // Inject a user pill every 2 post rows
            if sinceUser >= 2, uIndex < users.count {
                out.append(.user(users[uIndex])); uIndex += 1; sinceUser = 0
            }
            // Inject a live card every 3 post rows
            if sinceLive >= 3, lIndex < lives.count {
                out.append(.live(lives[lIndex])); lIndex += 1; sinceLive = 0
            }
        }
        // If no post rows but have users, still show the first user as a hint
        if pairs.isEmpty, let firstUser = users.first { out.append(.user(firstUser)) }
        return out
    }

    private func loadLives(for query: String) async {
        let limit = max(1, posts.count / 3)
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let r = try? await supabase.fetchFeedLiveStreams(limit: limit, query: trimmed.isEmpty ? nil : trimmed)
        await MainActor.run { lives = r ?? [] }
    }
}

private struct ExploreTopGrid: View {
    let posts: [SupabaseManager.ExplorePost]
    let users: [SupabaseManager.ExploreUser]
    var onSelectPost: (SupabaseManager.ExplorePost) -> Void = { _ in }
    var onSelectUser: (SupabaseManager.ExploreUser) -> Void = { _ in }
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(buildTopEntries(posts: posts, users: users)) { entry in
                    if let pair = entry.posts {
                        HStack(spacing: 10) {
                            ExplorePostCard(post: pair[0])
                                .frame(height: 200)
                                .contentShape(Rectangle())
                                .onTapGesture { onSelectPost(pair[0]) }
                            if pair.count > 1 {
                                ExplorePostCard(post: pair[1])
                                    .frame(height: 200)
                                    .contentShape(Rectangle())
                                    .onTapGesture { onSelectPost(pair[1]) }
                            } else {
                                Color.clear.frame(height: 200)
                            }
                        }
                        .padding(.horizontal)
                    }
                    if let u = entry.user {
                        ExploreUserPill(user: u)
                            .padding(.horizontal)
                            .onTapGesture { onSelectUser(u) }
                        Divider().padding(.horizontal)
                    }
                }
            }
            .padding(.top, 8)
        }
    }
}

private struct TopEntry: Identifiable {
    let id: String
    let posts: [SupabaseManager.ExplorePost]?
    let user: SupabaseManager.ExploreUser?
}

private func buildTopEntries(posts: [SupabaseManager.ExplorePost], users: [SupabaseManager.ExploreUser]) -> [TopEntry] {
    let pairs: [[SupabaseManager.ExplorePost]] = stride(from: 0, to: posts.count, by: 2).map { i in
        var arr: [SupabaseManager.ExplorePost] = []
        arr.append(posts[i])
        if i + 1 < posts.count { arr.append(posts[i+1]) }
        return arr
    }
    var entries: [TopEntry] = []
    var uIndex = 0
    for (idx, pair) in pairs.enumerated() {
        let rowId = pair.map { $0.id }.joined(separator: ",")
        entries.append(TopEntry(id: "row:\(rowId)", posts: pair, user: nil))
        if (idx + 1) % 2 == 0, uIndex < users.count {
            let u = users[uIndex]
            entries.append(TopEntry(id: "user:\(u.user_id)", posts: nil, user: u))
            uIndex += 1
        }
    }
    if users.count > 0 && pairs.isEmpty {
        let u = users[0]
        entries.append(TopEntry(id: "user:\(u.user_id)", posts: nil, user: u))
    }
    return entries
}

private struct ExploreUserPill: View {
    let user: SupabaseManager.ExploreUser
    var body: some View {
        HStack(spacing: 10) {
            if let img = user.image, let url = URL(string: img) {
                AsyncImage(url: url) { img in img.resizable().scaledToFill() } placeholder: { Color(.systemGray4) }
                    .frame(width: 36, height: 36).clipShape(Circle())
            } else { Circle().fill(Color(.systemGray4)).frame(width: 36, height: 36) }
            VStack(alignment: .leading, spacing: 2) {
                Text(user.name ?? user.username).font(.subheadline)
                Text("@\(user.username)").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemGray6)))
    }
}

// MARK: - Video thumbnail generator
// Using shared VideoThumbnail component

// Removed local storage; using DB-backed suggestions
// Reused Home-like viewer is now used for post detail
