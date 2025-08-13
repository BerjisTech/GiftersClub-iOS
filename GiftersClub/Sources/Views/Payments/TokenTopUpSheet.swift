import SwiftUI
#if canImport(FlutterwaveSDK)
import FlutterwaveSDK
#endif

struct TokenTopUpSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var supabase = SupabaseManager.shared
    @State private var amount: Int = 100
    @State private var isProcessing = false
    @State private var errorText: String? = nil
    var onCompleted: ((Bool) -> Void)? = nil

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
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Close") { onCompleted?(false); dismiss() } } }
        }
        .presentationDetents([.fraction(0.35), .medium])
        .alert("Payment Error", isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorText ?? "") }
    }

    private func purchase() async {
        guard let me = supabase.user?.id.uuidString else { return }
        await MainActor.run { isProcessing = true }
        #if canImport(FlutterwaveSDK)
        if SupabaseConfig.flutterwavePublicKey.isEmpty {
            await MainActor.run { errorText = "Payment unavailable. Please try again later."; isProcessing = false }
            return
        }
        let txRef = "ios_topup_\(me)_\(amount)_\(Int(Date().timeIntervalSince1970))"
        do {
            let success = try await PaymentCoordinator.shared.presentFlutterwaveTopUp(publicKey: SupabaseConfig.flutterwavePublicKey, amount: amount, txRef: txRef)
            if success {
                try await supabase.processPurchaseTokens(userId: me, tokens: amount, txRef: txRef)
                await MainActor.run { onCompleted?(true); dismiss() }
            } else {
                await MainActor.run { errorText = "Payment failed or cancelled." }
            }
        } catch {
            await MainActor.run { errorText = "Payment failed or cancelled." }
        }
        #else
        await MainActor.run { errorText = "Payment unavailable. Please install Flutterwave SDK." }
        #endif
        await MainActor.run { isProcessing = false }
    }
}
