import SwiftUI

private enum ExploreTab: String, CaseIterable { case top = "Top", photos = "Photos", videos = "Videos", users = "Users" }

struct ExploreView: View {
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

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchBar
                if showSuggestions {
                    suggestionsView
                } else {
                    tabsBar
                    Divider()
                    resultsView
                }
            }
            .navigationTitle("Explore")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(item: $selectedPost) { post in
                ExplorePostDetailView(post: post)
            }
            .navigationDestination(item: $selectedUser) { user in
                GifterProfileView(username: user.username)
            }
            .task { await loadSuggestions() }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search", text: $query)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .focused($focused)
                .onChange(of: query) { _, new in debounceSearch(new) }
            if !query.isEmpty {
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
            if isSearching {
                ProgressView().padding(.top, 20)
            } else if let r = results {
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
                VStack(spacing: 8) { Text("Search for posts and people").foregroundStyle(.secondary) }.padding(.top, 24)
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
                    AsyncImage(url: url) { img in img.resizable().scaledToFill() } placeholder: { Color(.secondarySystemBackground) }
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                } else if first.media_type == "video", let u = first.url, let url = URL(string: u) {
                    VideoThumbnail(url: url)
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
    private let columns = [GridItem(.flexible()), GridItem(.flexible())]
    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 10) {
                // Users as full-width pills
                ForEach(users, id: \.user_id) { u in
                    ExploreUserPill(user: u)
                        .gridCellColumns(2)
                        .onTapGesture { onSelectUser(u) }
                }
                // Posts as cards
                ForEach(posts, id: \.id) { p in
                    ExplorePostCard(post: p)
                        .frame(height: 200)
                        .contentShape(Rectangle())
                        .onTapGesture { onSelectPost(p) }
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)
        }
    }
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
        ZStack {
            if let img = image { Image(uiImage: img).resizable().scaledToFill() }
            else { Color.black.opacity(0.8) }
        }
        .task { await generate() }
        .clipped()
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
// MARK: - Post detail
private struct ExplorePostDetailView: View {
    let post: SupabaseManager.ExplorePost
    var body: some View {
        ScrollView { VStack(spacing: 12) {
            if let media = post.media, let first = media.first, let u = first.url, let url = URL(string: u) {
                if first.media_type == "photo" {
                    AsyncImage(url: url) { img in img.resizable().scaledToFit() } placeholder: { ProgressView() }
                        .frame(maxWidth: .infinity)
                } else if first.media_type == "video" {
                    VideoThumbnail(url: url).frame(height: 240).overlay(alignment: .center) { Image(systemName: "play.circle.fill").font(.system(size: 48)).foregroundStyle(.white) }
                }
            }
            if let prof = post.profile {
                HStack(spacing: 10) {
                    if let img = prof.image, let url = URL(string: img) {
                        AsyncImage(url: url) { i in i.resizable().scaledToFill() } placeholder: { Color(.systemGray4) }
                            .frame(width: 36, height: 36).clipShape(Circle())
                    } else { Circle().fill(Color(.systemGray4)).frame(width: 36, height: 36) }
                    Text(prof.name ?? prof.username ?? "").font(.headline)
                    Spacer()
                }.padding(.horizontal)
            }
            if let c = post.content, !c.isEmpty { Text(c).font(.body).padding(.horizontal) }
            Spacer(minLength: 0)
        }}
        .navigationTitle("Post")
        .navigationBarTitleDisplayMode(.inline)
    }
}
