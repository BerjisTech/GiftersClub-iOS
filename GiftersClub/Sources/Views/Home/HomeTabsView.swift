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
    var body: some View {
        GiftsGridView(sort: .newest)
            .padding(.horizontal)
            .padding(.top, 8)
    }
}

private struct GiftsGridView: View {
    enum Sort { case newest, popular, priceAsc, priceDesc }
    let sort: Sort
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
                        if let src = g.image, let url = buildURL(src) {
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
    private func buildURL(_ src: String) -> URL? {
        if src.lowercased().hasPrefix("http") { return URL(string: src) }
        let trimmed = src.hasPrefix("/") ? String(src.dropFirst()) : src
        return SupabaseConfig.url.appendingPathComponent(trimmed)
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
    @State private var items: [SupabaseManager.DBWishlist] = []
    @State private var isLoading = false
    var body: some View {
        List {
            if isLoading { ProgressView().frame(maxWidth: .infinity) }
            else if items.isEmpty { Text("No wishlists yet").foregroundStyle(.secondary) }
            else {
                ForEach(items, id: \.id) { w in
                    HStack {
                        RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)).frame(width: 44, height: 44)
                        Text(w.title ?? "Untitled wishlist").font(.subheadline)
                        Spacer()
                    }
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.04)))
                }
            }
        }
        .task { await load() }
        .refreshable { await load() }
    }
    private func load() async {
        isLoading = true; defer { isLoading = false }
        guard let me = supabase.user?.id.uuidString else { items = []; return }
        items = (try? await supabase.fetchWishlists(userId: me, limit: 50)) ?? []
    }
}
