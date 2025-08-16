import Foundation
import UIKit
import AuthenticationServices
import SafariServices

final class PaymentCoordinator: NSObject {
    static let shared = PaymentCoordinator()
    private override init() {}
    private var webAuthSession: ASWebAuthenticationSession?
    private var webCompletion: ((Bool) -> Void)?

    /// Present web checkout for token top-up by invoking a Supabase Edge Function
    /// that initializes a Flutterwave (or other PSP) session and returns a hosted payment URL.
    /// Expects the backend to redirect back to the app as: gifterclub://payment-callback?success=1&tx_ref=...
    func presentWebTopUp(userId: String, amount: Int) async -> Bool {
        let scheme = URLComponents(url: SupabaseConfig.redirectURL, resolvingAgainstBaseURL: false)?.scheme
        let callback = "\(scheme ?? "gifterclub")://\(SupabaseConfig.paymentCallbackHost)"

        // Build request to Edge Function (purchase-tokens-init)
        let functionURL = SupabaseConfig.url
            .appendingPathComponent("functions/v1/")
            .appendingPathComponent(SupabaseConfig.paymentTopUpFunctionName)
        var req = URLRequest(url: functionURL)
        req.httpMethod = "POST"
        req.addValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        if let token = try? await SupabaseManager.shared.client.auth.session.accessToken {
            req.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "userId": userId,
            "amount": amount,
            "platform": "ios",
            "callback_url": callback
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return false
            }
            // Parse response for a hosted payment URL and tx_ref
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let urlString = (json?["payment_url"] as? String)
                ?? (json?["checkout_url"] as? String)
                ?? (json?["redirect_url"] as? String)
            guard let urlString, let url = URL(string: urlString), let scheme else { return false }

            return await withCheckedContinuation { continuation in
                self.webCompletion = { success in continuation.resume(returning: success) }
                self.webAuthSession = ASWebAuthenticationSession(url: url, callbackURLScheme: scheme) { callbackURL, error in
                    defer { self.webAuthSession = nil }
                    guard error == nil, let callbackURL else {
                        self.webCompletion?(false); self.webCompletion = nil; return
                    }
                    let comps = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)
                    let success = comps?.queryItems?.first(where: { $0.name == "success" })?.value == "1"
                    self.webCompletion?(success)
                    self.webCompletion = nil
                }
                self.webAuthSession?.presentationContextProvider = self
                self.webAuthSession?.start()
            }
        } catch {
            return false
        }
    }

    // Allow onOpenURL handler to complete flows started outside ASWebAuthenticationSession if needed
    func handleWebCallback(_ url: URL) {
        let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        if url.scheme == URLComponents(url: SupabaseConfig.redirectURL, resolvingAgainstBaseURL: false)?.scheme,
           url.host == SupabaseConfig.paymentCallbackHost {
            let success = comps?.queryItems?.first(where: { $0.name == "success" })?.value == "1"
            webCompletion?(success)
            webCompletion = nil
        }
    }
}

extension PaymentCoordinator: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first ?? ASPresentationAnchor()
    }
}
