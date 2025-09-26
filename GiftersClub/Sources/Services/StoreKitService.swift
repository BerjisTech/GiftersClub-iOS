import Foundation
import StoreKit

@MainActor
final class StoreKitService: ObservableObject {
    static let shared = StoreKitService()
    private init() {}

    // Define your iOS product IDs (create these in App Store Connect)
    // Adjust token counts to cover Apple commission and withdrawal fees
    struct TokenPack: Identifiable, Hashable {
        let id: String              // StoreKit product ID
        let tokens: Int             // Tokens to grant after successful purchase
        var displayName: String?    // From StoreKit
        var displayPrice: String?   // From StoreKit
        var product: Product?
        var packName: String { displayName ?? id }
    }

    // Consumable token packs (product IDs must exist in App Store Connect)
    // Exclude items with Missing Metadata to avoid confusing the UI until ready.
    @Published var packs: [TokenPack] = [
        .init(id: "token_100", tokens: 100),
        .init(id: "token_500", tokens: 500),
        .init(id: "token_2000", tokens: 2_000),
        .init(id: "token_5000", tokens: 5_000),
        .init(id: "token_10000", tokens: 10_000),
        .init(id: "token_25000", tokens: 25_000),
        .init(id: "token_50000", tokens: 50_000),
        .init(id: "token_90000", tokens: 90_000)
    ]
    @Published var isLoading = false
    @Published var bestValuePackId: String? = nil
    @Published var lastLoadError: String? = nil

    func refreshProducts() async {
        isLoading = true
        lastLoadError = nil
        defer { isLoading = false }
        do {
            let ids = Set(packs.map { $0.id })
            let products = try await Product.products(for: ids)
            var map: [String: Product] = [:]
            products.forEach { map[$0.id] = $0 }
            var newPacks = packs.map { p in
                if let prod = map[p.id] {
                    var np = p
                    np.product = prod
                    np.displayName = prod.displayName
                    np.displayPrice = prod.displayPrice
                    return np
                }
                return p
            }
            // Keep ascending by token amount for nicer UI ordering
            newPacks.sort { $0.tokens < $1.tokens }
            packs = newPacks
            // Choose best value as the largest token pack (common pricing practice)
            bestValuePackId = newPacks.max(by: { $0.tokens < $1.tokens })?.id
            if products.isEmpty {
                lastLoadError = "In‑app purchases are currently unavailable. Ensure IAPs are linked to this app version and Cleared for Sale in App Store Connect."
            }
        } catch {
            lastLoadError = (error as NSError).localizedDescription
            // Keep existing packs; UI can still show token counts
        }
    }

    /// Purchase a pack via StoreKit and notify backend to credit tokens
    func purchase(pack: TokenPack, userId: String) async throws {
        var resolved: Product? = pack.product
        if resolved == nil {
            let ids: Set<String> = [pack.id]
            let list = try await Product.products(for: ids)
            resolved = list.first
        }
        guard let product = resolved else {
            throw NSError(domain: "StoreKit", code: -1, userInfo: [NSLocalizedDescriptionKey: "Product not available"]) }

        let result = try await product.purchase()
        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            // Credit tokens via Supabase Edge Function shared across clients
            try await SupabaseManager.shared.processPurchaseTokens(
                userId: userId,
                tokens: pack.tokens,
                txRef: String(transaction.id)
            )
            await transaction.finish()
        case .userCancelled:
            throw NSError(domain: "StoreKit", code: -2, userInfo: [NSLocalizedDescriptionKey: "Purchase cancelled"]) 
        case .pending:
            throw NSError(domain: "StoreKit", code: -3, userInfo: [NSLocalizedDescriptionKey: "Purchase pending"]) 
        @unknown default:
            throw NSError(domain: "StoreKit", code: -4, userInfo: [NSLocalizedDescriptionKey: "Unknown purchase result"]) 
        }
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, let error):
            throw error
        case .verified(let safe):
            return safe
        }
    }

}
