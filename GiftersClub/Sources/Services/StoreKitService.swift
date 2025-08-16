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

    @Published var packs: [TokenPack] = [
        .init(id: "tokens_70", tokens: 70),
        .init(id: "tokens_150", tokens: 150),
        .init(id: "tokens_375", tokens: 375),
        .init(id: "tokens_800", tokens: 800)
    ]
    @Published var isLoading = false

    func refreshProducts() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let ids = Set(packs.map { $0.id })
            let products = try await Product.products(for: ids)
            var map: [String: Product] = [:]
            products.forEach { map[$0.id] = $0 }
            packs = packs.map { p in
                if let prod = map[p.id] {
                    var np = p
                    np.product = prod
                    np.displayName = prod.displayName
                    np.displayPrice = prod.displayPrice
                    return np
                }
                return p
            }
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
