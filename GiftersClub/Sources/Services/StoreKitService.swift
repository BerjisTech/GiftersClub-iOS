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

    func refreshProducts() async {
        isLoading = true
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
        } catch {
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
            // Send signed payload to backend to validate and credit tokens
            try await notifyBackendForTokens(userId: userId, tokens: pack.tokens, productId: product.id, transaction: transaction)
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

    private func notifyBackendForTokens(userId: String, tokens: Int, productId: String, transaction: Transaction) async throws {
        // Build request to Supabase Edge Function for IAP validation + credit
        let functionURL = SupabaseConfig.url
            .appendingPathComponent("functions/v1/")
            .appendingPathComponent(SupabaseConfig.iapPurchaseFunctionName)
        var req = URLRequest(url: functionURL)
        req.httpMethod = "POST"
        req.addValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        if let token = try? await SupabaseManager.shared.client.auth.session.accessToken {
            req.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        // Include app receipt for server-side verification
        let receipt = try await fetchAppReceiptBase64()
        let payload: [String: Any] = [
            "userId": userId,
            "productId": productId,
            "tokens": tokens,
            "transactionId": String(transaction.id),
            "originalTransactionId": String(transaction.originalID),
            "appReceipt": receipt
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let msg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
            throw NSError(domain: "IAPCredit", code: (resp as? HTTPURLResponse)?.statusCode ?? -1, userInfo: [NSLocalizedDescriptionKey: msg ?? "Failed to credit tokens"])
        }
    }

    private func fetchAppReceiptBase64() async throws -> String {
        if #available(iOS 18.0, *) {
            // Prefer AppTransaction JSON for iOS 18+
            let result = try await AppTransaction.shared
            let appTx: AppTransaction = try checkVerified(result)
            return appTx.jsonRepresentation.base64EncodedString()
        } else {
            if let url = Bundle.main.appStoreReceiptURL, let data = try? Data(contentsOf: url) , !data.isEmpty {
                return data.base64EncodedString()
            }
            // Request a receipt refresh
            try await AppStore.sync()
            guard let url2 = Bundle.main.appStoreReceiptURL, let data2 = try? Data(contentsOf: url2), !data2.isEmpty else {
                throw NSError(domain: "StoreKit", code: -5, userInfo: [NSLocalizedDescriptionKey: "Missing App Store receipt"])
            }
            return data2.base64EncodedString()
        }
    }
}
