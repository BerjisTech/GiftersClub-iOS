import SwiftUI

struct ProfileModel: Identifiable, Hashable {
    var id: String { userId }
    let userId: String
    let username: String
    let name: String
    let bio: String
    let imageURL: URL?
    let followers: Int
    let following: Int
    let isCurrentUser: Bool
    var isFollowing: Bool
    var isFollowedBy: Bool
}

enum ProfileTab: String, CaseIterable, Hashable { case posts = "Posts", wishlists = "Wishlists", gifts = "Gifts" }
enum GiftsSort: String, CaseIterable { case newest = "Newest", popular = "Popular", priceAsc = "Price ↑", priceDesc = "Price ↓" }

struct ProfileDetailView: View {
    // Input: if nil, load current user
    var username: String?
    var userId: String?

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var banners: BannerQueue
    @EnvironmentObject private var drawer: DrawerManager
    @ObservedObject private var supabase = SupabaseManager.shared

    @State private var profile: ProfileModel?
    @State private var isLoading = true
    @State private var activeTab: ProfileTab = .posts
    @State private var giftsSort: GiftsSort = .newest
    @State private var postsMinimal: [SupabaseManager.UserPostMinimal] = []
    @State private var wishlists: [SupabaseManager.DBWishlistFull] = []
    @State private var gifts: [SupabaseManager.DBGift] = []
    @State private var showAccount = false
    @State private var showSettings = false
    @State private var showChat = false
    @State private var isSelfView = false
    @State private var hasLoadedOnce = false
    private var loadKey: String { (username ?? "") + "|" + (userId ?? "") }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                ScrollView {
                    LazyVStack(pinnedViews: [.sectionHeaders]) {
                        // Header
                        if let p = profile { header(p) }
                        // Tabs (sticky)
                        Section {
                            tabContent()
                        } header: {
                            tabsBar()
                        }
                    }
                }
                .toolbar { toolbar }
            }
            .navigationTitle("")
            .toolbarTitleDisplayMode(.inline)
            .loadingOverlay(isLoading)
            .task(id: loadKey) {
                if !hasLoadedOnce {
                    await loadAll()
                    hasLoadedOnce = true
                }
            }
            .navigationDestination(isPresented: $showAccount) { AccountView() }
            .navigationDestination(isPresented: $showSettings) { SettingsView() }
            .navigationDestination(isPresented: $showChat) {
                if let p = profile {
                    ChatDetailView(partner: ConversationItem.Partner(
                        userId: p.userId,
                        username: p.username,
                        displayName: p.name.isEmpty ? p.username : p.name,
                        imageURL: p.imageURL
                    ))
                }
            }
        }
    }

    private var canShowBack: Bool { false }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            if canShowBack {
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.left")
                        .font(.body.weight(.semibold))
                }
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                if let _ = profile, !isSelfView {
                    Button(role: .destructive) { presentBlock() } label: {
                        Label("Block user", systemImage: "hand.raised.fill")
                    }
                    Button { presentReport() } label: {
                        Label("Report user", systemImage: "exclamationmark.bubble.fill")
                    }
                }
                Button { shareProfile() } label: {
                    Label("Share profile", systemImage: "square.and.arrow.up")
                }
            } label: {
                Image(systemName: "ellipsis")
            }
        }
    }

    private func header(_ p: ProfileModel) -> some View {
        VStack(spacing: 12) {
            // Avatar
            ZStack {
                Circle().fill(Color.primary.opacity(0.06))
                if let url = p.imageURL {
                    AsyncImage(url: url) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        ProgressView().progressViewStyle(.circular)
                    }
                } else {
                    Image(systemName: "person.crop.circle.fill")
                        .resizable().scaledToFit().foregroundStyle(.secondary)
                        .padding(12)
                }
            }
            .frame(width: 96, height: 96)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(.thinMaterial, lineWidth: 1))
            .padding(.top, 8)

            // Name & username
            Text(p.name).font(.title3.weight(.semibold))
            Text("@\(p.username)").font(.callout).foregroundStyle(.secondary)

            // Stats
            HStack(spacing: 24) {
                statView(value: p.followers, label: "Followers")
                statView(value: p.following, label: "Following")
            }.padding(.top, 4)

            // Buttons
            buttonsRow(p)

            // Bio
            if !p.bio.isEmpty {
                Text(p.bio)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 8)
    }

    private func statView(value: Int, label: String) -> some View {
        VStack(spacing: 2) {
            Text("\(value)").font(.headline)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func buttonsRow(_ p: ProfileModel) -> some View {
        HStack(spacing: 10) {
            if !isSelfView {
                // Follow/Friends
                let isFriends = p.isFollowing && p.isFollowedBy
                GradientButton(title: isFriends ? "Friends" : (p.isFollowing ? "Following" : "Follow")) {
                    Task { await toggleFollow() }
                }
                // Chat
                GradientButton(title: "Chat") { showChat = true }
            } else {
                GradientButton(title: "Account") { showAccount = true }
                GradientButton(title: "Settings") { showSettings = true }
            }
        }
    }

    private func tabsBar() -> some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                let width = geo.size.width
                let count = CGFloat(ProfileTab.allCases.count)
                let tabWidth = width / max(count, 1)
                ZStack(alignment: .bottomLeading) {
                    HStack(spacing: 0) {
                        ForEach(ProfileTab.allCases, id: \.self) { tab in
                            Button(action: { withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) { activeTab = tab } }) {
                                Text(tab.rawValue)
                                    .font(.subheadline.weight(activeTab == tab ? .semibold : .regular))
                                    .foregroundStyle(activeTab == tab ? Color.primary : .secondary)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 28)
                            }
                        }
                    }
                    // Tiny underline indicator
                    Rectangle()
                        .fill(AppColors.primaryEnd)
                        .frame(width: 24, height: 2)
                        .offset(x: CGFloat(tabIndex(activeTab)) * tabWidth + (tabWidth - 24) / 2)
                        .animation(.spring(response: 0.28, dampingFraction: 0.9), value: activeTab)
                }
            }
            .frame(height: 30)

            if activeTab == .gifts {
                HStack {
                    Menu {
                        ForEach(GiftsSort.allCases, id: \.self) { s in
                            Button(action: { giftsSort = s }) { Text(s.rawValue) }
                        }
                    } label: {
                        Label("Sort: \(giftsSort.rawValue)", systemImage: "arrow.up.arrow.down")
                    }
                    Spacer()
                }
                .padding(.horizontal)
            }

            Divider()
        }
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private func tabIndex(_ tab: ProfileTab) -> Int {
        switch tab {
        case .posts: return 0
        case .wishlists: return 1
        case .gifts: return 2
        }
    }

    @ViewBuilder
    private func tabContent() -> some View {
        switch activeTab {
        case .posts:
            PostsGrid2View(posts: $postsMinimal,
                           isSelfView: isSelfView,
                           profileUsername: profile?.username ?? "",
                           profileName: profile?.name,
                           profileAvatar: profile?.imageURL)
                .padding(.horizontal)
        case .wishlists:
            WishlistsListView(
                items: wishlists,
                isSelfView: isSelfView,
                username: profile?.username ?? ""
            )
                .padding(.horizontal)
        case .gifts:
            GiftsCatalogView(sort: giftsSort, presetRecipientId: profile?.userId)
                .padding(.horizontal)
        }
    }

    // MARK: - Actions
    private func presentBlock() {
        drawer.present(DrawerModel(
            title: "Block user",
            message: "You will no longer see this user's posts.",
            primaryTitle: "Block",
            primaryAction: { banners.show(Banner(title: "User blocked", style: .success)); drawer.dismiss() },
            secondaryTitle: "Cancel",
            secondaryAction: { drawer.dismiss() }
        ))
    }
    private func presentReport() {
        drawer.present(DrawerModel(
            title: "Report user",
            message: "Tell us what's wrong with this profile.",
            primaryTitle: "Report",
            primaryAction: { banners.show(Banner(title: "Report submitted", style: .success)); drawer.dismiss() },
            secondaryTitle: "Cancel",
            secondaryAction: { drawer.dismiss() }
        ))
    }
    private func shareProfile() {
        banners.show(Banner(title: "Share link copied", style: .info))
    }
    private func toggleFollow() async {
        guard var p = profile, let me = supabase.user?.id.uuidString else { return }
        let newFollow = !p.isFollowing
        // optimistic
        p.isFollowing = newFollow
        profile = p
        do {
            try await supabase.setFollow(currentUserId: me, targetUserId: p.userId, follow: newFollow)
            // optionally refresh follow-back status
        } catch {
            // revert on error
            p.isFollowing.toggle()
            profile = p
            banners.show(Banner(title: "Failed to update follow", style: .error))
        }
    }

    // MARK: - Data
    private func loadAll() async {
        isLoading = true
        defer { isLoading = false }
        do {
            // Determine which profile to load
            let authedId = supabase.user?.id.uuidString
            let targetUserId = userId ?? authedId
            // If neither username nor userId available and not authed, nothing to load
            if username == nil && targetUserId == nil { return }

            // Fetch the target profile (by username or userId)
            guard let db = try await supabase.fetchProfile(username: username, userId: targetUserId) else { return }

            // Self-view if loaded profile's user_id equals authenticated user's id (robust UUID compare)
            let selfView: Bool = {
                if let authedUUID = supabase.user?.id, let targetUUID = UUID(uuidString: db.user_id) {
                    return authedUUID == targetUUID
                }
                if let authedId {
                    let a = authedId.trimmingCharacters(in: .whitespacesAndNewlines)
                    let b = db.user_id.trimmingCharacters(in: .whitespacesAndNewlines)
                    return b.caseInsensitiveCompare(a) == .orderedSame
                }
                return false
            }()
            isSelfView = selfView

            var isFollowing = false
            var isFollowedBy = false
            if let authedId, !selfView {
                isFollowing = (try? await supabase.isFollowing(currentUserId: authedId, targetUserId: db.user_id)) ?? false
                isFollowedBy = (try? await supabase.isFollowing(currentUserId: db.user_id, targetUserId: authedId)) ?? false
            }

            profile = ProfileModel(
                userId: db.user_id,
                username: db.username,
                name: db.name ?? "",
                bio: db.bio ?? "",
                imageURL: db.image.flatMap(URL.init(string:)),
                followers: db.followers_count ?? 0,
                following: db.following_count ?? 0,
                isCurrentUser: selfView,
                isFollowing: isFollowing,
                isFollowedBy: isFollowedBy
            )

            // Load tab data for that profile
            postsMinimal = (try? await supabase.fetchUserPostsMinimal(userId: db.user_id, limit: 20)) ?? []
            wishlists = (try? await supabase.fetchWishlistsDetailed(userId: db.user_id, limit: 30, offset: 0)) ?? []
            gifts = (try? await supabase.fetchGifts(sort: mapSort(giftsSort), limit: 40)) ?? []
        } catch {
            // Avoid spamming banners on transient errors; load quietly
            // You can add a single-shot banner here if desired
        }
    }

    private func mapSort(_ s: GiftsSort) -> SupabaseManager.GiftsSortKey {
        switch s {
        case .newest: return .newest
        case .popular: return .popular
        case .priceAsc: return .priceAsc
        case .priceDesc: return .priceDesc
        }
    }
}

// MARK: - Tab Content Placeholders
private struct PostsGridView: View {
    let thumbs: [URL]
    private let columns = [GridItem(.flexible()), GridItem(.flexible())]
    var body: some View {
        if thumbs.isEmpty {
            VStack(spacing: 8) { Text("No posts yet").foregroundStyle(.secondary) }
                .padding(.vertical, 16)
        } else {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(thumbs, id: \.self) { url in
                    AsyncImage(url: url) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        ShimmerView()
                    }
                    .frame(width: 180, height: 280)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
            .padding(.vertical, 8)
        }
    }
}

private struct PostsGrid2View: View {
    @Binding var posts: [SupabaseManager.UserPostMinimal]
    let isSelfView: Bool
    let profileUsername: String
    let profileName: String?
    let profileAvatar: URL?
    private let columns = [GridItem(.flexible()), GridItem(.flexible())]
    @ObservedObject private var supabase = SupabaseManager.shared
    @State private var paywallPost: SupabaseManager.UserPostMinimal? = nil
    @State private var unlocked: Set<String> = []
    @State private var showViewer = false
    @State private var startIndex = 0
    @State private var selecting = false
    @State private var selectedIds: Set<String> = []
    var body: some View {
        if posts.isEmpty {
            VStack(spacing: 8) { Text("No posts yet").foregroundStyle(.secondary) }
                .padding(.vertical, 16)
        } else {
            ZStack(alignment: .bottom) {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(Array(posts.enumerated()), id: \.1.id) { idx, p in
                        let media: LockablePostCard.MediaKind? = {
                            if let first = p.media?.first, let u = first.url, let url = URL(string: u) {
                                return (first.media_type == "video") ? .video(url) : .image(url)
                            }
                            return nil
                        }()
                        ZStack(alignment: .topLeading) {
                            LockablePostCard(
                                postId: p.id,
                                authorUserId: p.user_id,
                                accessType: p.access_type,
                                price: p.price,
                                media: media,
                                isLong: true,
                                onTapUnlocked: {
                                    if selecting { toggleSelect(p.id) }
                                    else { startIndex = idx; showViewer = true }
                                }
                            )
                            .highPriorityGesture(LongPressGesture(minimumDuration: 0.25).onEnded { _ in
                                if isSelfView {
                                    selecting = true
                                    selectedIds.insert(p.id)
                                }
                            })

                            if selecting {
                                let checked = selectedIds.contains(p.id)
                                Circle()
                                    .strokeBorder(checked ? Color.green : Color.white, lineWidth: 2)
                                    .background(Circle().fill(checked ? Color.green : Color.black.opacity(0.3)))
                                    .frame(width: 24, height: 24)
                                    .padding(6)
                                    .onTapGesture { toggleSelect(p.id) }
                            }
                        }
                        // No context menu in selection mode; long-press switches to multi-select
                    }
                }
                // Remove extra bottom space; position bottom bar above CustomBottomBar instead
                .padding(.bottom, 0)

                if selecting {
                    HStack {
                        Button("Cancel") { withAnimation { selecting = false; selectedIds.removeAll() } }
                            .buttonStyle(.bordered)
                        Spacer()
                        Button(role: .destructive) {
                            Task { await deleteSelected() }
                        } label: {
                            Text(selectedIds.isEmpty ? "Delete" : "Delete \(selectedIds.count)")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(selectedIds.isEmpty)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 10)
                    .padding(.bottom, CustomBottomBar.barHeight + 12)
                    .background(.ultraThinMaterial)
                }
            }
            .fullScreenCover(isPresented: $showViewer) {
                ProfilePostPagerView(
                    profileUsername: profileUsername,
                    profileName: profileName,
                    profileAvatar: profileAvatar,
                    posts: posts,
                    index: startIndex
                )
            }
            // Owner and non-owner paywall interactions are handled inside LockablePostCard.
            .padding(.vertical, 8)
        }
    }
    private func handleTap(_ p: SupabaseManager.UserPostMinimal) async {}
    private func deletePost(_ id: String) async {
        do {
            try await supabase.deletePost(id: id)
            if let idx = posts.firstIndex(where: { $0.id == id }) {
                _ = await MainActor.run { posts.remove(at: idx) }
            }
        } catch {
            // optionally show banner
        }
    }
    private func toggleSelect(_ id: String) { if selectedIds.contains(id) { selectedIds.remove(id) } else { selectedIds.insert(id) } }
    private func deleteSelected() async {
        let ids = Array(selectedIds)
        for id in ids { _ = try? await supabase.deletePost(id: id) }
        _ = await MainActor.run {
            posts.removeAll { selectedIds.contains($0.id) }
            selectedIds.removeAll()
            selecting = false
        }
    }
}

private struct WishlistsListView: View {
    @State var items: [SupabaseManager.DBWishlistFull]
    let isSelfView: Bool
    let username: String
    @State private var selecting = false
    @State private var selectedIds: Set<String> = []
    @State private var editing: SupabaseManager.DBWishlistFull? = nil
    @State private var editName: String = ""
    @State private var editDescription: String = ""
    @State private var editLink: String = ""
    @State private var editTokens: String = ""
    var body: some View {
        VStack(spacing: 8) {
            if items.isEmpty {
                VStack(spacing: 8) {
                    if isSelfView { Text("You have not created a wishlist yet").foregroundStyle(.secondary) }
                    else { Text("@\(username) has not created any wishlists").foregroundStyle(.secondary) }
                }
                .padding(.vertical, 16)
            } else {
                ZStack(alignment: .bottom) {
                    VStack(spacing: 8) {
                        ForEach(items, id: \.id) { w in
                            ZStack(alignment: .topLeading) {
                                NavigationLink(destination: WishlistDetailView(wishlistId: w.id)) {
                                    HStack {
                                        RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)).frame(width: 44, height: 44)
                                        Text(w.name ?? "Untitled wishlist").font(.subheadline)
                                        Spacer()
                                        if isSelfView && !selecting {
                                            Menu {
                                                Button { startEdit(w) } label: { Label("Edit", systemImage: "pencil") }
                                                Button(role: .destructive) { Task { await deleteWishlist(w.id) } } label: { Label("Delete", systemImage: "trash") }
                                            } label: {
                                                Image(systemName: "ellipsis").foregroundStyle(.secondary)
                                            }
                                        }
                                    }
                                    .padding(8)
                                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.04)))
                                }
                                .disabled(selecting)
                                .highPriorityGesture(LongPressGesture(minimumDuration: 0.25).onEnded { _ in
                                    if isSelfView { selecting = true; selectedIds.insert(w.id) }
                                })

                                if selecting {
                                    let checked = selectedIds.contains(w.id)
                                    Circle()
                                        .strokeBorder(checked ? Color.green : Color.white, lineWidth: 2)
                                        .background(Circle().fill(checked ? Color.green : Color.black.opacity(0.3)))
                                        .frame(width: 24, height: 24)
                                        .padding(6)
                                        .onTapGesture { toggleSelect(w.id) }
                                }
                            }
                        }
                    }
                    // Do not add extra bottom padding here; bottom bar is offset instead
                    .padding(.bottom, 0)
                    if selecting {
                        HStack {
                            Button("Cancel") { withAnimation { selecting = false; selectedIds.removeAll() } }
                                .buttonStyle(.bordered)
                            Spacer()
                            Button(role: .destructive) { Task { await deleteSelected() } } label: { Text(selectedIds.isEmpty ? "Delete" : "Delete \(selectedIds.count)") }
                                .buttonStyle(.borderedProminent)
                                .disabled(selectedIds.isEmpty)
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 10)
                        .padding(.bottom, CustomBottomBar.barHeight + 12)
                        .background(.ultraThinMaterial)
                    }
                }
                .padding(.vertical, 8)
            }
        }
        .sheet(item: $editing, onDismiss: { resetEditFields() }) { w in
            NavigationStack {
                Form {
                    Section("Details") {
                        TextField("Name", text: $editName)
                        TextField("Description", text: $editDescription, axis: .vertical)
                        TextField("Link", text: $editLink)
                        TextField("Tokens", text: $editTokens).keyboardType(.numberPad)
                    }
                }
                .navigationTitle("Edit Wishlist")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { Button("Cancel") { editing = nil } }
                    ToolbarItem(placement: .topBarTrailing) { Button("Save") { Task { await saveEdit(w) } } }
                }
            }
        }
    }
    private func startEdit(_ w: SupabaseManager.DBWishlistFull) {
        editing = w
        editName = w.name ?? ""
        editDescription = w.description ?? ""
        editLink = w.link ?? ""
        editTokens = String(w.tokens ?? 0)
    }
    private func resetEditFields() { editName = ""; editDescription = ""; editLink = ""; editTokens = "" }
    private func saveEdit(_ w: SupabaseManager.DBWishlistFull) async {
        let tokens = Int(editTokens) ?? (w.tokens ?? 0)
        let updates = SupabaseManager.UpdateWishlistInput(name: editName.isEmpty ? nil : editName,
                                                         description: editDescription.isEmpty ? nil : editDescription,
                                                         link: editLink.isEmpty ? nil : editLink,
                                                         image: nil,
                                                         tokens: tokens,
                                                         is_fulfilled: nil)
        do {
            try await SupabaseManager.shared.updateWishlist(id: w.id, updates: updates)
            if let idx = items.firstIndex(where: { $0.id == w.id }) {
                _ = await MainActor.run {
                    items[idx] = SupabaseManager.DBWishlistFull(
                        id: w.id,
                        user_id: w.user_id,
                        link: editLink.isEmpty ? w.link : editLink,
                        name: editName.isEmpty ? w.name : editName,
                        description: editDescription.isEmpty ? w.description : editDescription,
                        image: w.image,
                        tokens: tokens,
                        is_fulfilled: w.is_fulfilled,
                        created_at: w.created_at,
                        profile: w.profile,
                        wishlist_contributions: w.wishlist_contributions
                    )
                }
            }
        } catch { }
        _ = await MainActor.run { editing = nil; resetEditFields() }
    }
    private func toggleSelect(_ id: String) { if selectedIds.contains(id) { selectedIds.remove(id) } else { selectedIds.insert(id) } }
    private func deleteSelected() async {
        let ids = Array(selectedIds)
        for id in ids { _ = try? await SupabaseManager.shared.deleteWishlist(id: id) }
        _ = await MainActor.run {
            items.removeAll { selectedIds.contains($0.id) }
            selectedIds.removeAll(); selecting = false
        }
    }
    private func deleteWishlist(_ id: String) async {
        do {
            try await SupabaseManager.shared.deleteWishlist(id: id)
            if let idx = items.firstIndex(where: { $0.id == id }) {
                _ = await MainActor.run { items.remove(at: idx) }
            }
        } catch { }
    }
}

private struct GiftsCatalogView: View {
    let sort: GiftsSort
    var presetRecipientId: String?
    private let columns = [GridItem(.flexible()), GridItem(.flexible())]
    private let supabase = SupabaseManager.shared
    @State private var items: [SupabaseManager.DBGift] = []
    struct GiftWrapper: Identifiable { let id: String; let gift: SupabaseManager.DBGift }
    @State private var selectedGift: GiftWrapper? = nil
    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(items, id: \.id) { g in
                VStack(spacing: 8) {
                    if let url = giftImageURL(g) {
                        AsyncImage(url: url) { img in
                            img.resizable().scaledToFill()
                        } placeholder: { ShimmerView() }
                        .frame(height: 100)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    } else {
                        RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.06)).frame(height: 100)
                    }
                    Text(g.name ?? "Gift").font(.caption)
                }
                .contentShape(Rectangle())
                .onTapGesture { selectedGift = GiftWrapper(id: g.id, gift: g) }
            }
        }
        .padding(.vertical, 8)
        .task { await load() }
        .sheet(item: $selectedGift) { wrap in
            GiftSendSheet(gift: wrap.gift, presetRecipientId: presetRecipientId)
                .presentationDetents([.fraction(0.5), .fraction(0.75)])
                .presentationDragIndicator(.visible)
        }
    }
    private func load() async {
        let key: SupabaseManager.GiftsSortKey
        switch sort { case .newest: key = .newest; case .popular: key = .popular; case .priceAsc: key = .priceAsc; case .priceDesc: key = .priceDesc }
        items = (try? await supabase.fetchGifts(sort: key, limit: 40)) ?? []
    }
    private func giftImageURL(_ g: SupabaseManager.DBGift) -> URL? {
        if let src = g.image, !src.isEmpty {
            if src.lowercased().hasPrefix("http") { return URL(string: src) }
            let path = src.hasPrefix("/") ? String(src.dropFirst()) : src
            return SupabaseConfig.webBase.appendingPathComponent(path)
        }
        if let name = g.name?.lowercased() {
            let filename = (name + ".png").addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? (name + ".png")
            return SupabaseConfig.webBase.appendingPathComponent("assets/images/gifts/\(filename)")
        }
        return nil
    }
}
