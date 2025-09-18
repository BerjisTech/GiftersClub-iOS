import SwiftUI

struct CreatorCreditsInfoView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("About Creator Credits")
                    .font(.title2.weight(.semibold))

                Text("Creator credits are non-cash, earned credits that recognize creator activity and performance on Gifters Club. Creator credits are not in‑app purchases and cannot be bought for the purpose of withdrawal. Purchased tokens are for use within the app only (for example, sending gifts) and are not redeemable for money.")
                    .font(.body)

                Group {
                    Text("How credits are earned")
                        .font(.headline)
                    VStack(alignment: .leading, spacing: 10) {
                        bullet("Content performance thresholds", detail: "Credits may be awarded when creator content meets view or watch‑time thresholds in supported surfaces and regions.")
                        bullet("Advertising adjacencies", detail: "Credits may be awarded when eligible ads are served in connection with a creator’s content, subject to availability and brand‑safety policies.")
                        bullet("Referrals", detail: "Credits may be awarded when a creator refers new users who meet onboarding and activity criteria.")
                        bullet("Engagement programs", detail: "Credits may be awarded from platform incentive programs related to wishlists, gifts, livestreams, or similar engagements where the platform shares a percentage pursuant to program terms.")
                    }
                }

                Group {
                    Text("Key points")
                        .font(.headline)
                    VStack(alignment: .leading, spacing: 8) {
                        item("Earned, not purchased", detail: "Only creator credits earned under program rules are eligible for withdrawal. Purchased tokens are consumable for in‑app experiences and are not withdrawable.")
                        item("Program availability", detail: "Earning programs may vary by country, content category, quality, and policy compliance. Credits are subject to review and may be adjusted for fraud‑prevention and policy enforcement.")
                        item("Compliance", detail: "Participation requires compliance with our Terms, Community Guidelines, and local laws. We may request verification information prior to processing withdrawals.")
                        item("No guarantees", detail: "Credits are awarded at our discretion based on stated criteria and availability. Program details may change and will be communicated in updated documentation.")
                    }
                }

                Group {
                    Text("Withdrawing creator credits")
                        .font(.headline)
                    Text("Eligible creators can request withdrawal of earned credits to supported payout methods and currencies shown in the app. Payout timing, minimum thresholds, exchange rates, and fees are displayed during the withdrawal flow and may vary by method.")
                        .font(.body)
                }

                Text("This information is intended to provide clarity about how creator credits work within Gifters Club. For complete details, please review the Terms and any program‑specific policies disclosed in the app or on our website.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
        .navigationTitle("Creator Credits")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func bullet(_ title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.seal.fill").foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.subheadline)
            }
        }
    }

    private func item(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.subheadline.weight(.semibold))
            Text(detail).font(.subheadline)
        }
    }
}

