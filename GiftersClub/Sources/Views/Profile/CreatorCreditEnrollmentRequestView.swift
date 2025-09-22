import SwiftUI

struct CreatorCreditEnrollmentRequestView: View {
    @ObservedObject private var supabase = SupabaseManager.shared
    @State private var accepted = false
    @State private var submitting = false
    @State private var error: String? = nil
    @State private var existing: SupabaseManager.DBCreatorCreditEnrollment? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Request Creator Credit Enrollment").font(.title3.weight(.semibold))

                Group {
                    Text("What is creator credit enrollment?").font(.headline)
                    Text("Enrollment lets us verify your account for participation in creator credits. Credits are earned based on program rules and activity; they are not in‑app purchases and cannot be purchased for the purpose of withdrawal.")
                    Text("Program overview").font(.headline)
                    VStack(alignment: .leading, spacing: 8) {
                        bullet("Earned, not purchased", detail: "Only credits earned under program rules are eligible for withdrawal. Tokens you buy are consumable experiences and not withdrawable.")
                        bullet("Eligibility rules", detail: "Activity thresholds, brand‑safety, and regional availability may apply.")
                        bullet("Compliance", detail: "Enrollment requests are reviewed and may be accepted or rejected at our discretion.")
                    }
                    Text("By requesting enrollment, you agree to the program terms, including any updates we publish in‑app or on our website. You must accept these to proceed.")
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)

                Toggle(isOn: $accepted) {
                    Text("I accept the terms and conditions")
                }

                if let existing {
                    statusView(existing)
                }

                if let error { Text(error).foregroundStyle(.red) }

                GradientButton(title: buttonTitle, state: submitting ? .loading : .normal) {
                    Task { await submit() }
                }
                .disabled(!accepted || submitting || (existing?.status == "accepted"))
            }
            .padding()
        }
        .navigationTitle("Creator Credits")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    private var buttonTitle: String { existing == nil ? "Request" : "Re-request" }

    @ViewBuilder private func statusView(_ e: SupabaseManager.DBCreatorCreditEnrollment) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Current status: \(e.status.capitalized)").font(.headline)
            if e.status.lowercased() == "rejected" {
                Text("We reviewed your account and concluded that it does not currently meet one or more criteria for Creator Credits.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("How to improve your chances")
                    .font(.headline)
                VStack(alignment: .leading, spacing: 8) {
                    bullet("Audience size", detail: "At least ~1,000 followers.")
                    bullet("Consistent content", detail: "Regular uploads in a consistent niche/field.")
                    bullet("Cumulative views", detail: "10,000+ total views across posts.")
                    bullet("Trust & safety", detail: "Low reports, never being blocked for violations.")
                    bullet("Family‑friendly", detail: "Content must be safe for a broad audience.")
                    bullet("Engagement quality", detail: "Healthy likes and especially comments; considerate replies to comments.")
                }
                HStack {
                    Spacer()
                    GradientButton(title: "Re‑enroll") {
                        Task { await submit() }
                    }
                    .disabled(submitting || !accepted)
                }
            } else if e.status.lowercased() == "accepted" {
                Text("You’re enrolled and eligible for Creator Credits per program rules.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text("Your request is under review. We’ll notify you once it’s processed.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.05)))
    }

    private func bullet(_ title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail)
            }
        }
    }

    private func load() async {
        error = nil
        existing = try? await supabase.fetchMyCreatorCreditEnrollment()
    }

    private func submit() async {
        error = nil; submitting = true; defer { submitting = false }
        do {
            try await supabase.requestCreatorCreditEnrollment()
            await load()
        } catch {
            self.error = "Failed to submit request. Please try again."
        }
    }
}
