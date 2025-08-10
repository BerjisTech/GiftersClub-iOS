import SwiftUI

struct GiftersLeaderboardView: View {
    @ObservedObject private var supabase = SupabaseManager.shared
    @State private var items: [SupabaseManager.DBTopGifter] = []
    @State private var isLoading = false

    var body: some View {
        List {
            if isLoading { ProgressView().frame(maxWidth: .infinity) }
            else if items.isEmpty { Text("No top gifters yet").foregroundStyle(.secondary) }
            else {
                ForEach(items.indices, id: \.self) { i in
                    let g = items[i]
                    HStack(spacing: 12) {
                        ZStack {
                            Circle().fill(Color.primary.opacity(0.06))
                            if let img = g.image, let url = URL(string: img) {
                                AsyncImage(url: url) { img in
                                    img.resizable().scaledToFill()
                                } placeholder: { ProgressView() }
                            } else {
                                Image(systemName: "person.crop.circle").foregroundStyle(.secondary)
                            }
                        }.frame(width: 44, height: 44).clipShape(Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text(g.username).font(.subheadline.weight(.semibold))
                            Text("Tokens sent: \(g.tokens_sent ?? 0)").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("#\(i+1)").font(.subheadline).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                }
            }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        isLoading = true; defer { isLoading = false }
        items = (try? await supabase.fetchTopGifters(limit: 100)) ?? []
    }
}

