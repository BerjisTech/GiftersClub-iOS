import SwiftUI

struct GiftPickerSheet: View {
    let recipientId: String
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var supa = SupabaseManager.shared
    @State private var gifts: [SupabaseManager.DBGift] = []
    @State private var sort: SupabaseManager.GiftsSortKey = .popular
    @State private var error: String? = nil
    @State private var isSending: Bool = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Picker("Sort", selection: $sort) {
                    Text("Popular").tag(SupabaseManager.GiftsSortKey.popular)
                    Text("Newest").tag(SupabaseManager.GiftsSortKey.newest)
                    Text("Price ↑").tag(SupabaseManager.GiftsSortKey.priceAsc)
                    Text("Price ↓").tag(SupabaseManager.GiftsSortKey.priceDesc)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 12)], spacing: 12) {
                        ForEach(gifts, id: \.id) { g in
                            Button(action: { Task { await send(g) } }) {
                                VStack(spacing: 8) {
                                    if let url = giftImageURL(g) {
                                        AsyncImage(url: url) { image in image.resizable().scaledToFit() } placeholder: { ShimmerView() }
                                            .frame(height: 64)
                                    } else { Image(systemName: "gift.fill").font(.title) }
                                    Text(g.name ?? "Gift").font(.caption).lineLimit(1)
                                    if let t = g.tokens {
                                        HStack(spacing: 4) {
                                            Image("token").resizable().renderingMode(.original).frame(width: 14, height: 14)
                                            Text("\(t)").font(.caption2)
                                        }
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .padding(8)
                                .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemGray6)))
                            }
                            .disabled(isSending)
                        }
                    }
                    .padding(.horizontal)
                }
                if let e = error { Text(e).font(.footnote).foregroundStyle(.red) }
            }
            .navigationTitle("Send a Gift")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .task { await load() }
            .onChange(of: sort, perform: { _ in Task { await load() } })
        }
    }

    private func load() async {
        do { let list = try await supa.fetchGifts(sort: sort, limit: 60); _ = await MainActor.run { gifts = list } }
        catch { _ = await MainActor.run { gifts = [] } }
    }

    private func send(_ gift: SupabaseManager.DBGift) async {
        guard let tokens = gift.tokens else { return }
        do {
            _ = await MainActor.run { isSending = true; self.error = nil }
            try await supa.sendGift(giftId: gift.id, recipientId: recipientId, tokens: tokens)
            _ = await MainActor.run { isSending = false; dismiss() }
        } catch {
            _ = await MainActor.run { isSending = false; self.error = "Failed to send gift. Please try again." }
        }
    }
}

// Local helper copied from GiftSendSheet
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
