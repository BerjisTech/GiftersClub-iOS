import SwiftUI

struct PaywallSheet: View {
    enum Mode { case subscription(creatorId: String), paid(postId: String, price: Int) }
    let mode: Mode
    @ObservedObject private var supabase = SupabaseManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showTopUp = false
    @State private var duration: SupabaseManager.SubscriptionDuration = .monthly
    @State private var isLoading = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(systemName: "lock.fill").font(.largeTitle)
                switch mode {
                case .subscription:
                    Text("Subscribe to view").font(.headline)
                    Picker("Billing", selection: $duration) {
                        Text("Monthly").tag(SupabaseManager.SubscriptionDuration.monthly)
                    }
                    .pickerStyle(.segmented)
                    GradientButton(title: isLoading ? "Subscribing…" : "Subscribe") { Task { await doSubscribe() } }
                case .paid(_, let price):
                    Text("Purchase to view").font(.headline)
                    GradientButton(title: isLoading ? "Purchasing…" : "Unlock for \(price) tokens") { Task { await doPurchase() } }
                }
                Button("Top up tokens") { showTopUp = true }
                    .font(.caption)
            }
            .padding()
            .navigationTitle("Locked Content")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Close") { dismiss() } } }
        }
        .sheet(isPresented: $showTopUp) { TokenTopUpSheet() }
        .presentationDetents([.fraction(0.45), .medium])
    }

    private func doSubscribe() async {
        guard case let .subscription(creatorId) = mode else { return }
        await MainActor.run { isLoading = true }
        defer { Task { await MainActor.run { isLoading = false } } }
        do { try await supabase.subscribeToCreator(creatorId: creatorId, tokens: 0, duration: duration); await MainActor.run { dismiss() } } catch {}
    }
    private func doPurchase() async {
        guard case let .paid(postId, price) = mode else { return }
        await MainActor.run { isLoading = true }
        defer { Task { await MainActor.run { isLoading = false } } }
        do { try await supabase.purchasePostAccess(postId: postId, tokens: price); await MainActor.run { dismiss() } } catch {}
    }
}

