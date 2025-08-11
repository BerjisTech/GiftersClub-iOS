import SwiftUI

private enum ExploreTab: String, CaseIterable { case top = "Top", photos = "Photos", videos = "Videos", users = "Users" }

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
            .navigationDestination(item: $selectedPost) { post in
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
            .navigationDestination(item: $selectedUser) { user in
                // Avoid nested stacks: push the profile detail directly
                ProfileDetailView(username: user.username)
            }
            .task { await loadSuggestions() }
            .onAppear { consumeExternalQueryIfNeeded() }
            .onChange(of: externalQuery) { _, _ in consumeExternalQueryIfNeeded() }
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
                .onChange(of: query) { _, new in debounceSearch(new) }
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
                    ExploreTopGrid(posts: r.top, users: r.users) { p in selectedPost = p } onSelectUser: { u in selectedUser = u }
                case .photos:
                    ExplorePostsGrid(posts: r.photos) { p in selectedPost = p }
                case .videos:
                    ExplorePostsGrid(posts: r.videos) { p in selectedPost = p }
                case .users:
                    ExploreUsersList(users: r.users) { u in selectedUser = u }
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

// MARK: - Results UI
private struct ExplorePostsGrid: View {
    let posts: [SupabaseManager.ExplorePost]
    var onSelect: (SupabaseManager.ExplorePost) -> Void = { _ in }
    private let columns = [GridItem(.flexible()), GridItem(.flexible())]
    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(posts, id: \.id) { p in
                    ExplorePostCard(post: p)
                        .frame(height: 200)
                        .contentShape(Rectangle())
                        .onTapGesture { onSelect(p) }
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)
        }
    }
}

private struct ExplorePostCard: View {
    let post: SupabaseManager.ExplorePost
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let media = post.media, let first = media.first {
                if first.media_type == "photo", let u = first.url, let url = URL(string: u) {
                    GeometryReader { geo in
                        AsyncImage(url: url) { img in
                            img.resizable().scaledToFill()
                                .frame(width: geo.size.width, height: geo.size.height)
                                .clipped()
                        } placeholder: { Color(.secondarySystemBackground) }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                } else if first.media_type == "video", let u = first.url, let url = URL(string: u) {
                    GeometryReader { geo in
                        VideoThumbnail(url: url)
                            .frame(width: geo.size.width, height: geo.size.height)
                            .clipped()
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(alignment: .center) { Image(systemName: "play.circle.fill").font(.system(size: 36)).foregroundStyle(.white) }
                } else { Color(.secondarySystemBackground).clipShape(RoundedRectangle(cornerRadius: 12)) }
            } else { Color(.secondarySystemBackground).clipShape(RoundedRectangle(cornerRadius: 12)) }
            if let prof = post.profile { Text(prof.username ?? "").font(.caption).foregroundStyle(.white).padding(6) }
        }
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
import AVFoundation
private struct VideoThumbnail: View {
    let url: URL
    @State private var image: UIImage? = nil
    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let img = image {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                } else {
                    Color.black.opacity(0.8)
                }
            }
        }
        .task { await generate() }
    }
    private func generate() async {
        let asset = AVURLAsset(url: url)
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        let time = CMTime(seconds: 0.5, preferredTimescale: 600)
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            gen.generateCGImagesAsynchronously(forTimes: [NSValue(time: time)]) { _, cg, _, _, _ in
                if let cg { Task { await MainActor.run { image = UIImage(cgImage: cg) } } }
                continuation.resume()
            }
        }
    }
}

// Removed local storage; using DB-backed suggestions
// Reused Home-like viewer is now used for post detail
