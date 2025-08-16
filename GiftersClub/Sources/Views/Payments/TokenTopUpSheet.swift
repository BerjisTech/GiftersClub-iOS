import SwiftUI

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
        // Web checkout via hosted Flutterwave (backend handles token crediting)
        let success = await PaymentCoordinator.shared.presentWebTopUp(userId: me, amount: amount)
        if success {
            // Backend should credit tokens; optionally refresh balance here
            await MainActor.run { onCompleted?(true); dismiss() }
        }
        await MainActor.run { isProcessing = false }
    }
}
