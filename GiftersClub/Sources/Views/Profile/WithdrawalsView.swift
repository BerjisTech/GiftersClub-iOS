import SwiftUI

struct WithdrawalsView: View {
    @ObservedObject private var supabase = SupabaseManager.shared
    @State private var profile: SupabaseManager.DBProfile?
    @State private var amountText: String = ""
    @State private var method: String = WithdrawalsConfig.paymentMethods.first ?? "PayPal"
    @State private var paymentDetails: String = ""
    @State private var isSubmitting = false
    @State private var error: String? = nil
    @State private var history: [SupabaseManager.DBWithdrawalRequest] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Available balance
                if let p = profile {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Available Balance").font(.headline)
                        HStack {
                            Text("\(p.token_balance ?? 0) tokens").font(.title3.weight(.semibold))
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
                    Text("Request Withdrawal").font(.headline)
                    TextField("Amount (tokens)", text: $amountText)
                        .keyboardType(.numberPad)
                        .textFieldStyle(.roundedBorder)
                    Picker("Method", selection: $method) {
                        ForEach(WithdrawalsConfig.paymentMethods, id: \.self) { Text($0) }
                    }
                    .pickerStyle(.menu)
                    if WithdrawalsConfig.mobileMoneyMethods.map({ $0.lowercased() }).contains(method.lowercased()) {
                        TextField("Payment details (e.g., phone)", text: $paymentDetails)
                            .textFieldStyle(.roundedBorder)
                    }
                    if let summary = summaryLine() { Text(summary).font(.caption).foregroundStyle(.secondary) }
                    if let error { Text(error).foregroundStyle(.red) }
                    GradientButton(title: isSubmitting ? "Submitting…" : "Submit", state: isSubmitting ? .loading : .normal) {
                        Task { await submit() }
                    }
                }
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.04)))

                // History
                VStack(alignment: .leading, spacing: 8) {
                    Text("History").font(.headline)
                    if history.isEmpty { Text("No withdrawals yet").foregroundStyle(.secondary) }
                    else {
                        ForEach(history) { w in
                            HStack(alignment: .top) {
                                VStack(alignment: .leading) {
                                    Text("\(w.tokens) tokens → \(w.target_currency)")
                                        .font(.subheadline.weight(.semibold))
                                    Text(w.payment_method).font(.caption).foregroundStyle(.secondary)
                                    if let reason = w.rejection_reason, !reason.isEmpty { Text("Reason: \(reason)").font(.caption2) }
                                }
                                Spacer()
                                Text(w.status.capitalized)
                                    .font(.subheadline.weight(.semibold))
                            }
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.04)))
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Withdrawals")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
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

    private func submit() async {
        error = nil
        let tokens = Int(amountText.filter { $0.isNumber }) ?? 0
        guard tokens >= WithdrawalsConfig.minWithdrawalKES else {
            error = "Minimum withdrawal is \(WithdrawalsConfig.minWithdrawalKES) KES"
            return
        }
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
    static let minWithdrawalKES = 500
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

