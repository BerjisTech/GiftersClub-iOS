import SwiftUI
#if canImport(FlutterwaveSDK)
import FlutterwaveSDK
#endif

struct TokenTopUpSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var supabase = SupabaseManager.shared
    @State private var amount: Int = 100
    @State private var isProcessing = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("Top up tokens").font(.headline)
                Picker("Amount", selection: $amount) {
                    ForEach([50, 100, 250, 500, 1000], id: \.self) { v in
                        Text("\(v) tokens").tag(v)
                    }
                }
                .pickerStyle(.segmented)
                Spacer()
                GradientButton(title: isProcessing ? "Processing…" : "Purchase") {
                    Task { await purchase() }
                }
                .disabled(isProcessing)
            }
            .padding()
            .navigationTitle("Buy Tokens")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Close") { dismiss() } } }
        }
        .presentationDetents([.fraction(0.35), .medium])
    }

    private func purchase() async {
        guard let me = supabase.user?.id.uuidString else { return }
        await MainActor.run { isProcessing = true }

        #if canImport(FlutterwaveSDK)
        // Ensure a public key is configured
        if SupabaseConfig.flutterwavePublicKey.isEmpty {
            // Abort if no key; do NOT credit tokens
            return
        }
        let txRef = "ios_topup_\(me)_\(amount)_\(Int(Date().timeIntervalSince1970))"
        do {
            // Invoke Flutterwave payment UI
            let success = try await PaymentCoordinator.shared.presentFlutterwaveTopUp(publicKey: SupabaseConfig.flutterwavePublicKey, amount: amount, txRef: txRef)
            if success {
                // Only after SDK returns success, credit tokens via Edge Function
                try await supabase.processPurchaseTokens(userId: me, tokens: amount, txRef: txRef)
                await MainActor.run { dismiss() }
            }
        } catch {
            // Payment failed or cancelled — do not credit tokens
        }
        #else
        // Flutterwave SDK not available; do NOT credit tokens.
        // You must add the iOS-v3 Flutterwave SDK to enable top-ups.
        #endif
        await MainActor.run { isProcessing = false }
    }
}
