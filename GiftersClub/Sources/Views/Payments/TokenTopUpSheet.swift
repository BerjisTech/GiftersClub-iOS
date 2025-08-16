import SwiftUI
import StoreKit

struct TokenTopUpSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var supabase = SupabaseManager.shared
    @State private var amount: Int = 100
    @StateObject private var sk = StoreKitService.shared
    @State private var isProcessing = false
    @State private var errorText: String? = nil
    var onCompleted: ((Bool) -> Void)? = nil
    // Optional shortfall for contextual messaging and recommendations
    private var neededTokens: Int? = nil

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("Top up tokens").font(.headline)
                if let need = neededTokens {
                    Text("You need \(need) tokens to continue.")
                        .font(.subheadline)
                }
                Text("Prices include platform fees").font(.caption).foregroundStyle(.secondary)
                if sk.isLoading { ProgressView().progressViewStyle(.circular) }
                VStack(spacing: 8) {
                    ForEach(sk.packs) { pack in
                        Button(action: { Task { await buy(pack) } }) {
                            HStack {
                                VStack(alignment: .leading) {
                                    HStack(spacing: 8) {
                                        Text("\(pack.tokens) tokens").font(.subheadline.weight(.semibold))
                                        if isRecommended(pack: pack) {
                                            Text("Recommended")
                                                .font(.caption2.weight(.bold))
                                                .padding(.horizontal, 6).padding(.vertical, 2)
                                                .background(RoundedRectangle(cornerRadius: 6).fill(Color.blue.opacity(0.15)))
                                        }
                                    }
                                    if let name = pack.displayName { Text(name).font(.caption).foregroundStyle(.secondary) }
                                    if let need = neededTokens {
                                        let leftover = max(pack.tokens - need, 0)
                                        Text("Needs \(need), leftover \(leftover)")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Text(pack.displayPrice ?? "")
                                    .font(.subheadline.weight(.semibold))
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemGray6)))
                        }
                        .disabled(isProcessing)
                    }
                }
                .padding(.top, 4)
            }
            .padding()
            .navigationTitle("Buy Tokens")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Close") { onCompleted?(false); dismiss() } } }
        }
        .presentationDetents([.fraction(0.35), .medium])
        .alert("Payment Error", isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorText ?? "") }
        .task { await sk.refreshProducts() }
    }

    private func buy(_ pack: StoreKitService.TokenPack) async {
        guard let me = supabase.user?.id.uuidString else { return }
        await MainActor.run { isProcessing = true; errorText = nil }
        do {
            try await sk.purchase(pack: pack, userId: me)
            _ = try? await supabase.fetchProfile(username: nil, userId: me)
            await MainActor.run { onCompleted?(true); dismiss() }
        } catch {
            await MainActor.run { errorText = (error as NSError).localizedDescription }
        }
        await MainActor.run { isProcessing = false }
    }

    private func isRecommended(pack: StoreKitService.TokenPack) -> Bool {
        guard let need = neededTokens else { return false }
        // Recommend the smallest single pack that covers the need
        let covering = sk.packs.filter { $0.tokens >= need }.sorted { $0.tokens < $1.tokens }
        if let first = covering.first { return first.id == pack.id }
        return false
    }

    init(initialAmount: Int? = nil, onCompleted: ((Bool) -> Void)? = nil) {
        self.neededTokens = initialAmount
        self.onCompleted = onCompleted
    }
}
