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
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                // Simplify sheet: remove large titles/headers to avoid overlay
                if let need = neededTokens {
                    Text("You need \(need) tokens to continue.")
                        .font(.subheadline)
                }
                Text("Prices include platform fees").font(.caption).foregroundStyle(.secondary)
                if sk.isLoading { ProgressView().progressViewStyle(.circular) }
                if let err = sk.lastLoadError, !sk.isLoading {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.red)
                    Button("Reload") { Task { await sk.refreshProducts() } }
                        .buttonStyle(.bordered)
                }
                    VStack(spacing: 8) {
                        ForEach(sk.packs) { pack in
                            Button(action: { Task { await buy(pack) } }) {
                                HStack {
                                    VStack(alignment: .leading) {
                                        HStack(spacing: 8) {
                                            Text("\(pack.tokens) tokens").font(.subheadline.weight(.semibold))
                                            if isRecommended(pack: pack) { badge("Recommended") }
                                            else if isBestValue(pack: pack) { badge("Best value") }
                                        }
                                        if let name = pack.displayName { Text(name).font(.caption).foregroundStyle(.secondary) }
                                        else { Text("Price pending").font(.caption).foregroundStyle(.secondary) }
                                        if let need = neededTokens {
                                            let leftover = max(pack.tokens - need, 0)
                                            Text("Needs \(need), leftover \(leftover)")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                    Text(pack.displayPrice ?? "Unavailable")
                                        .font(.subheadline.weight(.semibold))
                                }
                                .padding(12)
                                .frame(maxWidth: .infinity)
                                .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemGray6)))
                            }
                            .disabled(isProcessing || pack.product == nil)
                        }
                    }
                    .padding(.top, 4)
                }
                .padding()
            }
            // Remove navigation title to prevent large overlaying title on iPad sheet
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Close") { onCompleted?(false); dismiss() } } }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
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
            #if DEBUG
            print("Token purchase failed: \(error)")
            #endif
            await MainActor.run { errorText = friendlyErrorMessage(for: error) }
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

    private func isBestValue(pack: StoreKitService.TokenPack) -> Bool {
        return sk.bestValuePackId == pack.id
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.blue.opacity(0.15)))
    }

    private func friendlyErrorMessage(for error: Error) -> String {
        let ns = error as NSError
        if ns.domain == "StoreKit" {
            return ns.localizedDescription
        }
        if ns.domain == NSURLErrorDomain {
            return "We couldn't reach the server. Please check your connection and try again."
        }
        return "We couldn't complete the purchase right now. If the charge went through, contact support and we'll help."
    }

    init(initialAmount: Int? = nil, onCompleted: ((Bool) -> Void)? = nil) {
        self.neededTokens = initialAmount
        self.onCompleted = onCompleted
    }
}
