import Foundation
import UIKit
import AuthenticationServices
import SafariServices

final class PaymentCoordinator: NSObject {
    static let shared = PaymentCoordinator()
    private override init() {}
    private var webAuthSession: ASWebAuthenticationSession?
    private var webCompletion: ((Bool) -> Void)?

    /// Present web checkout for token top-up using hosted Flutterwave (via your backend).
    /// Expects the backend to redirect back to the app as: gifterclub://payment-callback?success=1&tx_ref=...
    func presentWebTopUp(userId: String, amount: Int) async -> Bool {
        let txRef = "ios_topup_\(userId)_\(amount)_\(Int(Date().timeIntervalSince1970))"
        // Construct a backend URL that initiates Flutterwave checkout and redirects back on completion
        var url = SupabaseConfig.webBase
            .appendingPathComponent("pay/topup")
            .appending(queryItems: [
                URLQueryItem(name: "user_id", value: userId),
                URLQueryItem(name: "amount", value: String(amount)),
                URLQueryItem(name: "tx_ref", value: txRef),
                URLQueryItem(name: "platform", value: "ios")
            ])

        // Prefer ASWebAuthenticationSession for a clean callback into the app
        if let scheme = URLComponents(url: SupabaseConfig.redirectURL, resolvingAgainstBaseURL: false)?.scheme {
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
        }

        // Fallback: open in SFSafariViewController without callback (returns false on dismissal)
        return await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                guard let root = UIApplication.shared.connectedScenes.compactMap({ ($0 as? UIWindowScene)?.keyWindow }).first?.rootViewController else {
                    continuation.resume(returning: false); return
                }
                let safari = SFSafariViewController(url: url)
                safari.modalPresentationStyle = .formSheet
                root.present(safari, animated: true)
                // No callback in this path; caller should refresh balance manually later
                continuation.resume(returning: false)
            }
        }
    }

    // Allow onOpenURL handler to complete flows started outside ASWebAuthenticationSession if needed
    func handleWebCallback(_ url: URL) {
        let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        if url.host == "payment-callback" {
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
