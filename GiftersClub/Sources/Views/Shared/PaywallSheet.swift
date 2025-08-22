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
    @State private var plans: [SupabaseManager.DBSubscriptionPlan] = []
    @State private var selectedPlanId: String? = nil
    @State private var creatorUsername: String? = nil

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(systemName: "lock.fill").font(.largeTitle)
                switch mode {
                case .subscription(let creatorId):
                    Text("Subscribe to @\(creatorUsername ?? "creator")").font(.headline)
                    if plans.isEmpty {
                        Text("This creator has no subscription plans available.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(alignment: .leading, spacing: 10) {
                            Picker("Plan", selection: Binding(get: { selectedPlanId ?? plans.first?.id }, set: { selectedPlanId = $0 })) {
                                ForEach(plans, id: \.id) { p in
                                    Text("\(p.name) — \(p.tokens) tokens / \(p.duration_type)").tag(p.id as String?)
                                }
                            }
                            .pickerStyle(.menu)
                            let plan = plans.first { $0.id == (selectedPlanId ?? plans.first?.id) }
                            if let p = plan {
                                GradientButton(title: isLoading ? "Subscribing…" : "Subscribe for \(p.tokens) tokens") { Task { await doSubscribe(plan: p) } }
                                if let desc = p.description, !desc.isEmpty {
                                    let lines = desc.split(separator: "\n").map(String.init)
                                    if !lines.isEmpty {
                                        VStack(alignment: .leading, spacing: 4) {
                                            ForEach(lines, id: \.self) { line in Text("• \(line)").font(.caption) }
                                        }
                                        .padding(.top, 4)
                                    }
                                }
                            }
                        }
                    }
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
        .task {
            if case let .subscription(creatorId) = mode {
                if let list = try? await supabase.fetchSubscriptionPlans(creatorId: creatorId) {
                    let sorted = list.sorted { $0.tokens < $1.tokens }
                    await MainActor.run { plans = sorted; selectedPlanId = sorted.first?.id }
                }
                if let prof = try? await supabase.fetchProfileByUserId(creatorId) {
                    await MainActor.run { creatorUsername = prof.username }
                }
            }
        }
        .sheet(isPresented: $showTopUp, onDismiss: {
            if topUpSucceeded {
                Task {
                    switch mode {
                    case .paid:
                        await doPurchase()
                    case .subscription:
                        if let plan = plans.first(where: { $0.id == (selectedPlanId ?? plans.first?.id) }) {
                            await doSubscribe(plan: plan)
                        }
                    }
                }
                topUpSucceeded = false
            } else {
                isLoading = false
            }
        }) {
            TokenTopUpSheet(onCompleted: { success in topUpSucceeded = success })
        }
        .presentationDetents([.fraction(0.45), .medium])
        .alert("Payment Error", isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorText ?? "") }
    }

    private func doSubscribe(plan: SupabaseManager.DBSubscriptionPlan) async {
        guard case let .subscription(creatorId) = mode else { return }
        await MainActor.run { isLoading = true }
        defer { Task { await MainActor.run { isLoading = false } } }
        do {
            // Enforce local balance
            if let me = supabase.user?.id.uuidString, let prof = try? await supabase.fetchProfile(username: nil, userId: me), (prof.token_balance ?? 0) < plan.tokens {
                await MainActor.run { isLoading = false; topUpSucceeded = false; showTopUp = true }
                return
            }
            // Map duration type to enum; default monthly
            let dur = SupabaseManager.SubscriptionDuration(rawValue: plan.duration_type) ?? .monthly
            try await supabase.subscribeToCreator(creatorId: creatorId, tokens: plan.tokens, duration: dur)
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
