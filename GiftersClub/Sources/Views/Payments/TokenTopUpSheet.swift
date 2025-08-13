import SwiftUI

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
        defer { Task { await MainActor.run { isProcessing = false } } }
        do {
            // TODO: Present Flutterwave payment UI and confirm success before crediting tokens.
            // For now, call Edge Function directly to credit (dev/test flow).
            try await supabase.processPurchaseTokens(userId: me, tokens: amount, txRef: "ios_topup_\(Int(Date().timeIntervalSince1970))")
            await MainActor.run { dismiss() }
        } catch {
            // handle error
        }
    }
}

