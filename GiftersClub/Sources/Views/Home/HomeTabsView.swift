import SwiftUI

enum HomeTopTab: String, CaseIterable { case posts = "Posts", gifts = "Gifts", gifters = "Gifters", wishlists = "Wishlists" }

struct HomeTabsView: View {
    @State private var tab: HomeTopTab = .posts
    private let tabsHeight: CGFloat = 20

    var body: some View {
        ZStack(alignment: .top) {
            // Content fills entire area; tabs float above
            Group {
                switch tab {
                case .posts:
                    HomeView() // posts fills from top of parent; tabs float above
                case .gifts:
                    GiftsHomeView().padding(.top, tabsHeight)
                case .gifters:
                    GiftersLeaderboardView().padding(.top, tabsHeight)
                case .wishlists:
                    WishlistsHomeView().padding(.top, tabsHeight)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Floating top tabs (no background)
            VStack(spacing: 0) {
                TopTabsBar(tab: $tab, onDark: tab == .posts)
                    .frame(height: tabsHeight)
                    .padding(.horizontal)
            }
            .frame(maxWidth: .infinity)
        }
        .onReceive(NotificationCenter.default.publisher(for: .showHomeWishlists)) { _ in tab = .wishlists }
    }
}

// MARK: - Gifts
struct GiftsHomeView: View {
    struct GiftWrapper: Identifiable { let id: String; let gift: SupabaseManager.DBGift }
    @State private var selectedGift: GiftWrapper? = nil
    var body: some View {
        GiftsGridView(sort: .newest) { gift in
            selectedGift = GiftWrapper(id: gift.id, gift: gift)
        }
            .padding(.horizontal)
            .padding(.top, 8)
            .sheet(item: $selectedGift) { wrap in
                GiftSendSheet(gift: wrap.gift, presetRecipientId: nil)
                    .presentationDetents([.fraction(0.5), .fraction(0.75)])
                    .presentationDragIndicator(.visible)
            }
    }
}

private struct GiftsGridView: View {
    enum Sort { case newest, popular, priceAsc, priceDesc }
    let sort: Sort
    var onSelect: (SupabaseManager.DBGift) -> Void = { _ in }
    private let columns = [GridItem(.flexible()), GridItem(.flexible())]
    @ObservedObject private var supabase = SupabaseManager.shared
    @State private var items: [SupabaseManager.DBGift] = []
    @State private var isLoading = false
    var body: some View {
        ScrollView {
            if isLoading {
                ProgressView().frame(maxWidth: .infinity)
            }
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(items, id: \.id) { g in
                    VStack(spacing: 8) {
                        if let url = giftImageURL(g) {
                            AsyncImage(url: url) { img in
                                img.resizable().scaledToFill()
                            } placeholder: { ShimmerView() }
                            .frame(height: 120)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        } else {
                            RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.06)).frame(height: 120)
                        }
                        Text(g.name ?? "Gift").font(.caption)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { onSelect(g) }
                }
            }
            .padding(.vertical, 8)
        }
        .task { await load() }
        .refreshable { await load() }
    }
    private func load() async {
        isLoading = true; defer { isLoading = false }
        let key: SupabaseManager.GiftsSortKey
        switch sort { case .newest: key = .newest; case .popular: key = .popular; case .priceAsc: key = .priceAsc; case .priceDesc: key = .priceDesc }
        items = (try? await supabase.fetchGifts(sort: key, limit: 60)) ?? []
    }
    private func giftImageURL(_ g: SupabaseManager.DBGift) -> URL? {
        if let src = g.image, !src.isEmpty {
            if src.lowercased().hasPrefix("http") { return URL(string: src) }
            // Treat as web static asset path
            let path = src.hasPrefix("/") ? String(src.dropFirst()) : src
            return SupabaseConfig.webBase.appendingPathComponent(path)
        }
        // Fallback to conventional Angular assets path by name
        if let name = g.name?.lowercased() {
            let filename = (name + ".png").addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? (name + ".png")
            return SupabaseConfig.webBase.appendingPathComponent("assets/images/gifts/\(filename)")
        }
        return nil
    }
}

// MARK: - Custom top tabs bar
private struct TopTabsBar: View {
    @Binding var tab: HomeTopTab
    var onDark: Bool = false
    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let count = CGFloat(HomeTopTab.allCases.count)
            let tabWidth = width / max(count, 1)
            ZStack(alignment: .bottomLeading) {
                HStack(spacing: 0) {
                    ForEach(HomeTopTab.allCases, id: \.self) { t in
                        Button(action: { withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) { tab = t } }) {
                            Text(t.rawValue)
                                .font(.subheadline.weight(tab == t ? .semibold : .regular))
                                .foregroundStyle(onDark ? (tab == t ? Color.white : Color.white.opacity(0.7)) : (tab == t ? Color.primary : .secondary))
                                .frame(maxWidth: .infinity)
                                .frame(height: 30)
                        }
                    }
                }
                Rectangle()
                    .fill(AppColors.primaryEnd)
                    .frame(width: 24, height: 2)
                    .offset(x: CGFloat(index(tab)) * tabWidth + (tabWidth - 24) / 2)
                    .animation(.spring(response: 0.28, dampingFraction: 0.9), value: tab)
            }
        }
        .frame(height: 34)
        Divider()
    }
    private func index(_ t: HomeTopTab) -> Int {
        switch t { case .posts: return 0; case .gifts: return 1; case .gifters: return 2; case .wishlists: return 3 }
    }
}

// MARK: - Wishlists
struct WishlistsHomeView: View {
    @ObservedObject private var supabase = SupabaseManager.shared
    @State private var items: [SupabaseManager.DBWishlistFull] = []
    @State private var isLoading = false
    @State private var showCreate = false
    var body: some View {
        NavigationStack {
            List {
                if isLoading { ProgressView().frame(maxWidth: .infinity) }
                else if items.isEmpty { Text("No wishlists yet").foregroundStyle(.secondary) }
                else {
                    ForEach(items, id: \.id) { w in
                        NavigationLink(value: w.id) {
                            HStack(spacing: 12) {
                                if let url = wishlistImageURL(w.image) {
                                    AsyncImage(url: url) { img in
                                        img.resizable().scaledToFill()
                                    } placeholder: { ShimmerView() }
                                    .frame(width: 48, height: 48)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                } else {
                                    RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)).frame(width: 48, height: 48)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(w.name?.isEmpty == false ? (w.name ?? "Wishlist") : "Wishlist").font(.subheadline).foregroundStyle(.primary)
                                    if let desc = w.description, !desc.isEmpty {
                                        Text(desc).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                    if let max = w.tokens, max > 0 {
                                        let contributed = (w.wishlist_contributions ?? []).reduce(0) { $0 + $1.tokens }
                                        ProgressView(value: Double(contributed), total: Double(max))
                                            .tint(AppColors.primaryEnd)
                                    }
                                }
                                Spacer()
                            }
                            .padding(6)
                        }
                    }
                }
            }
            .navigationDestination(for: String.self) { wid in
                WishlistDetailView(wishlistId: wid)
            }
            .navigationTitle("Wishlists")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { showCreate = true } label: { Image(systemName: "plus") } } }
        }
        .sheet(isPresented: $showCreate) { CreateWishlistView() }
        .task { await load() }
        .refreshable { await load() }
    }
    private func load() async {
        isLoading = true; defer { isLoading = false }
        items = (try? await supabase.fetchAllWishlistsDetailed(limit: 50)) ?? []
    }
    private func wishlistImageURL(_ src: String?) -> URL? {
        guard let src, !src.isEmpty else { return nil }
        if src.lowercased().hasPrefix("http") { return URL(string: src) }
        let path = src.hasPrefix("/") ? String(src.dropFirst()) : src
        return SupabaseConfig.webBase.appendingPathComponent(path)
    }
}

struct WishlistDetailView: View {
    let wishlistId: String
    @ObservedObject private var supabase = SupabaseManager.shared
    @State private var wishlist: SupabaseManager.DBWishlistFull?
    @State private var contributions: [SupabaseManager.DBWishlistContribution] = []
    @State private var contributorProfiles: [SupabaseManager.DBProfile] = []
    @State private var isLoading = false
    var body: some View {
        ScrollView {
            if isLoading { ProgressView().frame(maxWidth: .infinity) }
            if let w = wishlist {
                VStack(alignment: .leading, spacing: 12) {
                    if let url = wishlistImageURL(w.image) {
                        AsyncImage(url: url) { img in img.resizable().scaledToFill() } placeholder: { ShimmerView() }
                            .frame(height: 180)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    Text(w.name ?? "Wishlist").font(.title2).bold()
                    if let owner = w.profile { HStack(spacing: 8) { Circle().fill(Color.primary.opacity(0.06)).frame(width: 24, height: 24); Text(owner.name ?? owner.username).font(.subheadline).foregroundStyle(.secondary) } }
                    if let desc = w.description, !desc.isEmpty { Text(desc).font(.body) }
                    if let max = w.tokens {
                        let contributed = contributions.reduce(0) { $0 + $1.tokens }
                        VStack(alignment: .leading, spacing: 6) {
                            ProgressView(value: Double(contributed), total: Double(max)).tint(AppColors.primaryEnd)
                            Text("\(contributed) / \(max) tokens").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Divider()
                    Text("Contributors").font(.headline)
                    if contributorProfiles.isEmpty { Text("No contributions yet").foregroundStyle(.secondary) }
                    else {
                        ForEach(contributorProfiles, id: \.user_id) { p in
                            HStack { RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)).frame(width: 32, height: 32); Text(p.name ?? p.username).font(.subheadline); Spacer() }
                        }
                    }
                }
                .padding()
            }
        }
        .navigationTitle("Wishlist")
        .task { await load() }
        .refreshable { await load() }
    }
    private func load() async {
        isLoading = true; defer { isLoading = false }
        wishlist = try? await supabase.fetchWishlistById(wishlistId)
        contributions = (try? await supabase.fetchWishlistContributions(wishlistId: wishlistId)) ?? []
        let ids = Array(Set(contributions.map { $0.contributor_id }))
        contributorProfiles = (try? await supabase.fetchProfilesByUserIds(ids)) ?? []
    }
    private func wishlistImageURL(_ src: String?) -> URL? {
        guard let src, !src.isEmpty else { return nil }
        if src.lowercased().hasPrefix("http") { return URL(string: src) }
        let path = src.hasPrefix("/") ? String(src.dropFirst()) : src
        return SupabaseConfig.webBase.appendingPathComponent(path)
    }
}

struct CreateWishlistView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var supabase = SupabaseManager.shared
    @State private var name: String = ""
    @State private var description: String = ""
    @State private var link: String = ""
    @State private var image: String = ""
    @State private var tokensText: String = ""
    @State private var isSaving = false
    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Name", text: $name)
                    TextField("Description", text: $description, axis: .vertical)
                    TextField("Target tokens", text: $tokensText).keyboardType(.numberPad)
                }
                Section("Links (optional)") {
                    TextField("Image URL or path", text: $image)
                    TextField("External link", text: $link)
                }
            }
            .navigationTitle("New Wishlist")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(action: { Task { await save() } }) { if isSaving { ProgressView() } else { Text("Save") } }.disabled(isSaving) } }
        }
    }
    private func save() async {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let me = supabase.user?.id.uuidString else { return }
        isSaving = true; defer { isSaving = false }
        let tokens = Int(tokensText.filter { $0.isNumber }) ?? 0
        let input = SupabaseManager.CreateWishlistInput(
            user_id: me,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            description: description.trimmingCharacters(in: .whitespacesAndNewlines),
            link: link.isEmpty ? nil : link,
            image: image.isEmpty ? nil : image,
            tokens: tokens,
            is_fulfilled: false
        )
        _ = try? await supabase.createWishlist(input)
        dismiss()
    }
}
