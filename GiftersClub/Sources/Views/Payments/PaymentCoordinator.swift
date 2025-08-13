import Foundation
import UIKit
#if canImport(FlutterwaveSDK)
import FlutterwaveSDK
#endif

final class PaymentCoordinator {
    static let shared = PaymentCoordinator()
    private init() {}

    #if canImport(FlutterwaveSDK)
    /// Present Flutterwave checkout to top-up tokens. Returns true if payment succeeds.
    func presentFlutterwaveTopUp(publicKey: String, amount: Int, txRef: String) async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.main.async {
                guard let root = UIApplication.shared.connectedScenes.compactMap({ ($0 as? UIWindowScene)?.keyWindow }).first?.rootViewController else {
                    continuation.resume(returning: false); return
                }

                // Configure Flutterwave payment
                let config = FlutterwaveConfig.shared()
                config?.currencyCode = "KES"
                config?.publicKey = publicKey
                config?.txRef = txRef
                config?.amount = Float(amount)
                config?.paymentOptionsToExclude = []

                // Present payment options
                let controller = FlutterwavePayViewController()
                controller.delegate = self
                controller.modalPresentationStyle = .overFullScreen
                self.completion = { success in continuation.resume(returning: success) }
                root.present(controller, animated: true)
            }
        }
    }

    private var completion: ((Bool) -> Void)?
    #endif
}

#if canImport(FlutterwaveSDK)
extension PaymentCoordinator: FlutterwavePayProtocol {
    func tranasctionSuccessful(flwRef: String?, responseData: [AnyHashable : Any]?) {
        completion?(true); completion = nil
        dismissPresented()
    }
    func tranasctionFailed(flwRef: String?, responseData: [AnyHashable : Any]?) {
        completion?(false); completion = nil
        dismissPresented()
    }
    func tranasctionCanceled() {
        completion?(false); completion = nil
        dismissPresented()
    }
    private func dismissPresented() {
        DispatchQueue.main.async {
            UIApplication.shared.connectedScenes
                .compactMap { ($0 as? UIWindowScene)?.keyWindow?.rootViewController }
                .first?.presentedViewController?.dismiss(animated: true)
        }
    }
}
#endif

