import SwiftUI

struct WishlistRowSmall: View {
    let wishlist: SupabaseManager.DBWishlistFull
    var body: some View {
        HStack(spacing: 12) {
            if let url = wishlistImageURL(wishlist.image, fallback: wishlist.profile?.image) {
                AsyncImage(url: url) { img in
                    img.resizable().scaledToFill()
                } placeholder: { ShimmerView() }
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)).frame(width: 48, height: 48)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text((wishlist.name?.isEmpty == false ? (wishlist.name ?? "Wishlist") : "Wishlist"))
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                if let desc = wishlist.description, !desc.isEmpty {
                    Text(desc).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                if let max = wishlist.tokens, max > 0 {
                    let contributed = (wishlist.wishlist_contributions ?? []).reduce(0) { $0 + $1.tokens }
                    ProgressView(value: Double(contributed), total: Double(max))
                        .tint(AppColors.primaryEnd)
                }
            }
            Spacer()
        }
        .padding(6)
    }
    private func wishlistImageURL(_ src: String?, fallback: String? = nil) -> URL? {
        if let s = src, !s.isEmpty {
            if s.lowercased().hasPrefix("http") { return URL(string: s) }
            let path = s.hasPrefix("/") ? String(s.dropFirst()) : s
            return SupabaseConfig.webBase.appendingPathComponent(path)
        }
        if let f = fallback, !f.isEmpty {
            if f.lowercased().hasPrefix("http") { return URL(string: f) }
            let path = f.hasPrefix("/") ? String(f.dropFirst()) : f
            return SupabaseConfig.webBase.appendingPathComponent(path)
        }
        return nil
    }
}

