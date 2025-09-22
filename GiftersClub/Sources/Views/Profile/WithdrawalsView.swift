import SwiftUI

struct WithdrawalsView: View {
    @ObservedObject private var supabase = SupabaseManager.shared
    @State private var profile: SupabaseManager.DBProfile?
    @State private var amountText: String = ""
    @State private var method: String = "Mpesa"
    @State private var paymentDetails: String = ""
    @State private var isSubmitting = false
    @State private var error: String? = nil
    @State private var history: [SupabaseManager.DBWithdrawalRequest] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                NavigationLink(destination: CreatorCreditsInfoView()) {
                    HStack(spacing: 6) {
                        Image(systemName: "questionmark.circle")
                        Text("What are creator credits?")
                            .font(.subheadline.weight(.semibold))
                    }
                }
                .tint(.blue)

                // Available balance
                if let p = profile {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Available Credits").font(.headline)
                        HStack {
                            Text("\(p.token_balance ?? 0) credits").font(.title3.weight(.semibold))
                            Spacer()
                            let usd = Double(p.token_balance ?? 0) * WithdrawalsConfig.exchangeRates["USD"]!
                            Text("$\(String(format: "%.2f", usd))").foregroundStyle(.secondary)
                        }
                        let total = usdValue() * 0.7
                        let fee = usdValue() * 0.3
                        Text("Total received: $\(String(format: "%.2f", total)) • Transaction fee: $\(String(format: "%.2f", fee))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.04)))
                }

                // Request form
                VStack(alignment: .leading, spacing: 12) {
                    Text("Creator Credits").font(.headline)
                    TextField("Amount (credits)", text: $amountText)
                        .keyboardType(.numberPad)
                        .textFieldStyle(.roundedBorder)
                    Picker("Method", selection: $method) {
                        ForEach(WithdrawalsConfig.paymentMethods, id: \.self) { Text($0) }
                    }
                    .pickerStyle(.menu)
                    if WithdrawalsConfig.mobileMoneyMethods.map({ $0.lowercased() }).contains(method.lowercased()) {
                        TextField(paymentPlaceholder, text: $paymentDetails)
                            .textFieldStyle(.roundedBorder)
                    }
                    if let summary = summaryLine() { Text(summary).font(.caption).foregroundStyle(.secondary) }
                    if let validation = validationMessage() { Text(validation).font(.caption).foregroundStyle(.secondary) }
                    if let error { Text(error).foregroundStyle(.red) }
                    GradientButton(title: isSubmitting ? "Submitting…" : "Submit", state: isSubmitting ? .loading : .normal) {
                        Task { await submit() }
                    }
                    .disabled(!isFormValid() || isSubmitting)
                }
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.04)))

                // History
                VStack(alignment: .leading, spacing: 8) {
                    Text("History").font(.headline)
                    if history.isEmpty { Text("No credit withdrawals yet").foregroundStyle(.secondary) }
                    else {
                        ForEach(history) { w in
                            HStack(alignment: .top) {
                                VStack(alignment: .leading) {
                                    Text(historyLine(for: w))
                                        .font(.subheadline.weight(.semibold))
                                    Text(w.payment_method).font(.caption).foregroundStyle(.secondary)
                                    if let reason = w.rejection_reason, !reason.isEmpty { Text("Reason: \(reason)").font(.caption2) }
                                }
                                Spacer()
                                Text(statusText(w.status))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(statusColor(w.status))
                            }
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.04)))
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Creator Credits")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    private func historyLine(for w: SupabaseManager.DBWithdrawalRequest) -> String {
        let currency = w.target_currency
        let gross = w.converted_amount ?? Double(w.tokens) * w.exchange_rate
        let net = gross * 0.7
        let formatted = formatAmount(net, currency: currency)
        return "\(w.tokens) credits → \(currency) \(formatted)"
    }

    private func formatAmount(_ value: Double, currency: String) -> String {
        let noDecimal = ["KES", "NGN", "TZS", "RWF"]
        if noDecimal.contains(currency.uppercased()) {
            return String(Int(value.rounded()))
        } else {
            return String(format: "%.2f", value)
        }
    }

    private func statusText(_ status: String) -> String {
        status.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private func statusColor(_ status: String) -> Color {
        let s = status.lowercased()
        if ["approved", "completed", "paid", "processed", "success", "succeeded"].contains(s) {
            return .green
        }
        if ["pending", "processing", "in_progress", "queued"].contains(s) {
            return .blue
        }
        if ["rejected", "failed", "error", "canceled", "cancelled"].contains(s) {
            return .red
        }
        return .secondary
    }

    private func usdValue() -> Double {
        Double(profile?.token_balance ?? 0) * (WithdrawalsConfig.exchangeRates["USD"] ?? 1.0)
    }

    private func summaryLine() -> String? {
        let tokens = Int(amountText.filter { $0.isNumber }) ?? 0
        guard tokens > 0 else { return nil }
        let currency = WithdrawalsConfig.methodCurrencyMap[method] ?? "USD"
        let rate = WithdrawalsConfig.exchangeRates[currency] ?? 1.0
        let amount = Double(tokens) * rate
        let net = amount * 0.7
        let fee = amount * 0.3
        return String(format: "You will receive: %.2f %@ (• Fee: %.2f %@)", net, currency, fee, currency)
    }

    private func isFormValid() -> Bool {
        let tokens = Int(amountText.filter { $0.isNumber }) ?? 0
        let minTokens = WithdrawalsConfig.minWithdrawalTokens
        let balance = profile?.token_balance ?? 0
        let needsDetails = WithdrawalsConfig.mobileMoneyMethods.map { $0.lowercased() }.contains(method.lowercased())
        let hasDetails = !paymentDetails.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if tokens < minTokens { return false }
        if tokens > max(0, balance) { return false }
        if needsDetails && !hasDetails { return false }
        return true
    }

    private func validationMessage() -> String? {
        let tokens = Int(amountText.filter { $0.isNumber }) ?? 0
        let minTokens = WithdrawalsConfig.minWithdrawalTokens
        let balance = profile?.token_balance ?? 0
        if tokens == 0 { return nil }
        if tokens < minTokens { return "Minimum withdrawal is \(minTokens) credits" }
        if tokens > max(0, balance) { return "Cannot withdraw more than your balance (\(balance) credits)" }
        let needsDetails = WithdrawalsConfig.mobileMoneyMethods.map { $0.lowercased() }.contains(method.lowercased())
        if needsDetails && paymentDetails.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Enter your mobile money details" }
        return nil
    }

    private func submit() async {
        error = nil
        let tokens = Int(amountText.filter { $0.isNumber }) ?? 0
        let minTokens = WithdrawalsConfig.minWithdrawalTokens
        guard tokens >= minTokens else { error = "Minimum withdrawal is \(minTokens) credits"; return }
        let balance = profile?.token_balance ?? 0
        guard tokens <= max(0, balance) else { error = "Cannot withdraw more than your balance"; return }
        let needsDetails = WithdrawalsConfig.mobileMoneyMethods.map { $0.lowercased() }.contains(method.lowercased())
        if needsDetails && paymentDetails.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { error = "Enter your mobile money details"; return }
        isSubmitting = true; defer { isSubmitting = false }
        do {
            let currency = WithdrawalsConfig.methodCurrencyMap[method] ?? "USD"
            let rate = WithdrawalsConfig.exchangeRates[currency] ?? 1.0
            let details = WithdrawalsConfig.mobileMoneyMethods.map({ $0.lowercased() }).contains(method.lowercased()) && !paymentDetails.isEmpty ? ["details": paymentDetails] : nil
            _ = try await supabase.requestWithdrawal(tokens: tokens, targetCurrency: currency, exchangeRate: rate, paymentMethod: method, paymentDetails: details)
            await load()
            amountText = ""; paymentDetails = ""
        } catch {
            self.error = "Withdrawal request failed"
        }
    }

    private func load() async {
        profile = try? await supabase.fetchProfile(username: nil, userId: supabase.user?.id.uuidString)
        history = (try? await supabase.fetchWithdrawalsByUser(limit: 100)) ?? []
    }
}

enum WithdrawalsConfig {
    static let minWithdrawalTokens = 500
    static let exchangeRates: [String: Double] = [
        "USD": 0.0078,
        "NGN": 6.96,
        "GHS": 0.09,
        "TZS": 18.2,
        "RWF": 7.8
    ]
    static let paymentMethods: [String] = [
        "PayPal",
        "Bank Transfer",
        "Mpesa",
        "Paga (Nigeria)",
        "MTN MoMo (Nigeria)",
        "MTN MoMo (Ghana)",
        "Airtel Money (Ghana)",
        "Vodacom M-Pesa (Tanzania)",
        "Tigo Pesa (Tanzania)",
        "MTN Momo (Rwanda)"
    ]
    static let mobileMoneyMethods: [String] = [
        "Mpesa",
        "Paga (Nigeria)",
        "MTN MoMo (Nigeria)",
        "MTN MoMo (Ghana)",
        "Airtel Money (Ghana)",
        "Vodacom M-Pesa (Tanzania)",
        "Tigo Pesa (Tanzania)",
        "MTN Momo (Rwanda)"
    ]
    static let methodCurrencyMap: [String: String] = [
        "PayPal": "USD",
        "Bank Transfer": "KES",
        "Mpesa": "KES",
        "Paga (Nigeria)": "NGN",
        "MTN MoMo (Nigeria)": "NGN",
        "MTN MoMo (Ghana)": "GHS",
        "Airtel Money (Ghana)": "GHS",
        "Vodacom M-Pesa (Tanzania)": "TZS",
        "Tigo Pesa (Tanzania)": "TZS",
        "MTN Momo (Rwanda)": "RWF"
    ]
}

private extension WithdrawalsView {
    var paymentPlaceholder: String {
        // For Kenya Mpesa, expect MSISDN format starting with country code
        if method.caseInsensitiveCompare("Mpesa") == .orderedSame { return "2547......." }
        return "Payment details (e.g., phone)"
    }
}
