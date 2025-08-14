import SwiftUI

struct PaywallSheet: View {
    enum Mode { case subscription(creatorId: String), paid(postId: String, price: Int) }
    let mode: Mode
    @ObservedObject private var supabase = SupabaseManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showTopUp = false
    @State private var duration: SupabaseManager.SubscriptionDuration = .monthly
    @State private var isLoading = false
    @State private var topUpSucceeded = false
    var onUnlocked: (() -> Void)? = nil
    @State private var errorText: String? = nil

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
                    GradientButton(title: isLoading ? "Unlocking…" : "Unlock for \(price) tokens", state: isLoading ? .loading : .normal) { Task { await doPurchase() } }
                }
                Button("Top up tokens") { showTopUp = true }
                    .font(.caption)
            }
            .padding()
            .navigationTitle("Locked Content")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Close") { dismiss() } } }
        }
        .sheet(isPresented: $showTopUp, onDismiss: {
            if topUpSucceeded { Task { await doPurchase() }; topUpSucceeded = false } else { isLoading = false }
        }) {
            TokenTopUpSheet(onCompleted: { success in topUpSucceeded = success })
        }
        .presentationDetents([.fraction(0.45), .medium])
        .alert("Payment Error", isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorText ?? "") }
    }

    private func doSubscribe() async {
        guard case let .subscription(creatorId) = mode else { return }
        await MainActor.run { isLoading = true }
        defer { Task { await MainActor.run { isLoading = false } } }
        do {
            try await supabase.subscribeToCreator(creatorId: creatorId, tokens: 0, duration: duration)
            await MainActor.run { onUnlocked?(); dismiss() }
        } catch {
            await MainActor.run { errorText = "Subscription failed. Please try again." }
        }
    }
    private func doPurchase() async {
        guard case let .paid(postId, price) = mode else { return }
        await MainActor.run { isLoading = true }
        defer { Task { await MainActor.run { isLoading = false } } }
        do {
            // Check local balance first
            if let me = supabase.user?.id.uuidString, let prof = try? await supabase.fetchProfile(username: nil, userId: me), (prof.token_balance ?? 0) < price {
                await MainActor.run { isLoading = false; topUpSucceeded = false; showTopUp = true }
                return
            }
            try await supabase.purchasePostAccess(postId: postId, tokens: price)
            await MainActor.run { onUnlocked?(); dismiss() }
        } catch {
            let msg = (error as NSError).userInfo[NSLocalizedDescriptionKey] as? String ?? error.localizedDescription
            if msg.lowercased().contains("insufficient") && msg.lowercased().contains("token") {
                await MainActor.run { isLoading = false; topUpSucceeded = false; showTopUp = true }
            } else {
                await MainActor.run { errorText = msg.isEmpty ? "Purchase failed. Please try again." : msg }
            }
        }
    }
    // retry handled in onDismiss
}
