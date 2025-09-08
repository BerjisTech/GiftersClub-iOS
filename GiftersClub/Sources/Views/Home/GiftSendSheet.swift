import SwiftUI

struct GiftSendSheet: View {
    let gift: SupabaseManager.DBGift
    var presetRecipientId: String?
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var supabase = SupabaseManager.shared
    @State private var query: String = ""
    @State private var results: [SupabaseManager.DBProfile] = []
    @State private var isSearching = false
    @State private var selected: SupabaseManager.DBProfile? = nil
    @State private var errorText: String? = nil
    @State private var isSending = false
    @State private var showTopUp = false
    @State private var missingTokens: Int? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Capsule().fill(Color.secondary.opacity(0.3)).frame(width: 36, height: 5)
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill").font(.title3).foregroundStyle(.secondary)
                }
            }
            .padding(.top, 8)
            HStack(spacing: 10) {
                Text(gift.name ?? "Gift").font(.headline)
                Spacer()
                if let t = gift.tokens {
                    HStack(spacing: 6) {
                        Image("token").resizable().renderingMode(.original).frame(width: 16, height: 16)
                        Text("\(t)").font(.subheadline)
                    }
                }
            }
            if let url = giftImageURL(gift) {
                AsyncImage(url: url) { $0.resizable().scaledToFit() } placeholder: { ShimmerView() }
                    .frame(height: 100)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            if let preset = presetRecipientId { presetSection(preset) }
            else { searchSection }

            if let err = errorText {
                VStack(alignment: .leading, spacing: 8) {
                    Text(err).font(.footnote).foregroundStyle(.red)
                    Button(action: { showTopUp = true }) {
                        HStack(spacing: 8) {
                            Image("token").resizable().renderingMode(.original).frame(width: 16, height: 16)
                            Text("Buy tokens")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal)
        .padding(.bottom, 12)
        .onAppear { Task { await prefillIfNeeded() } }
        .sheet(isPresented: $showTopUp) {
            TokenTopUpSheet(initialAmount: missingTokens, onCompleted: { _ in })
        }
    }

    @ViewBuilder
    private func presetSection(_ recipientId: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let me = supabase.user?.id.uuidString, me.caseInsensitiveCompare(recipientId) == .orderedSame {
                Text("You can’t gift yourself. Search for someone else.")
                    .font(.subheadline).foregroundStyle(.secondary)
                searchSection
            } else {
                HStack {
                    Image(systemName: "person.crop.circle").foregroundStyle(.secondary)
                    Text("Gift to selected user")
                    Spacer()
                }
                Button(action: { Task { await confirmGift(to: recipientId) } }) {
                    Text("Send gift")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSending)
            }
        }
    }

    private var searchSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search users by name, @username, or email", text: $query)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .onChange(of: query, perform: { new in debounceSearch(new) })
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemGray6)))

            if isSearching { ProgressView().progressViewStyle(.circular) }

            if !results.isEmpty {
                List(results, id: \.user_id) { u in
                    HStack(spacing: 12) {
                        if let img = u.image, let url = URL(string: img) {
                            AsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: { Color(.systemGray5) }
                                .frame(width: 36, height: 36)
                                .clipShape(Circle())
                        } else { Circle().fill(Color(.systemGray5)).frame(width: 36, height: 36) }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(u.name ?? u.username).font(.subheadline)
                            Text("@\(u.username)").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { selected = u; Task { await confirmGift(to: u.user_id) } }
                }
                .listStyle(.plain)
                .frame(maxHeight: 260)
            }
        }
    }

    // MARK: - Search
    @State private var debounceTask: Task<Void, Never>? = nil
    private func debounceSearch(_ text: String) {
        debounceTask?.cancel()
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { results = []; return }
        debounceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 250_000_000)
            await search(text)
        }
    }
    private func search(_ text: String) async {
        await MainActor.run { isSearching = true }
        defer { Task { await MainActor.run { isSearching = false } } }
        do { let r = try await supabase.searchProfilesByKeyword(text); await MainActor.run { results = r } }
        catch { await MainActor.run { results = [] } }
    }

    private func prefillIfNeeded() async { }

    // MARK: - Send gift
    private func confirmGift(to recipientId: String) async {
        guard let tokens = gift.tokens else { return }
        do {
            // Check token balance
            guard let me = supabase.user?.id.uuidString, let myProfile = try await supabase.fetchProfile(username: nil, userId: me) else { return }
            let balance = myProfile.token_balance ?? 0
            if balance < tokens {
                await MainActor.run {
                    let missing = max(tokens - balance, 0)
                    errorText = "Insufficient tokens (you have \(balance), you need \(missing) more). Please top up."
                    missingTokens = missing
                }
                return
            }
            await MainActor.run { isSending = true; errorText = nil }
            try await supabase.sendGift(giftId: gift.id, recipientId: recipientId, tokens: tokens)
            await MainActor.run { isSending = false; dismiss() }
        } catch {
            await MainActor.run {
                isSending = false
                errorText = "Failed to send gift. Please try again."
            }
        }
    }

    // No non-IAP top-up paths on iOS
}

// Small helper to append query items
private extension URL {
    func appending(queryItems: [URLQueryItem]) -> URL {
        guard var comp = URLComponents(url: self, resolvingAgainstBaseURL: false) else { return self }
        comp.queryItems = (comp.queryItems ?? []) + queryItems
        return comp.url ?? self
    }
}

// MARK: - Image URL fallback
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
