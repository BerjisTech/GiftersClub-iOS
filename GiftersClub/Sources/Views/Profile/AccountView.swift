import SwiftUI

struct AccountView: View {
    @ObservedObject private var supabase = SupabaseManager.shared
    @State private var profile: SupabaseManager.DBProfile?
    @State private var activityText: String = "You have no activity today."
    @State private var giftsSent = 0
    @State private var giftsReceived = 0
    @State private var openWishlists = 0
    @State private var fulfilledWishlists = 0
    @State private var showTopUp = false
    @State private var showWithdrawals = false
    @StateObject private var banners = BannerQueue()

    var body: some View {
        ZStack(alignment: .top) {
        ScrollView {
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Welcome back").font(.headline)
                    Text(activityText).font(.subheadline).foregroundStyle(.secondary)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 16).fill(Color.primary.opacity(0.04)))

                // Token details card
                if let p = profile {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Tokens").font(.headline)
                        HStack {
                            VStack(alignment: .leading) {
                                Text("Balance").font(.caption).foregroundStyle(.secondary)
                                Text("\(p.token_balance ?? 0)")
                            }
                            Spacer()
                            VStack(alignment: .leading) {
                                Text("Sent").font(.caption).foregroundStyle(.secondary)
                                Text("\(p.tokens_sent ?? 0)")
                            }
                            Spacer()
                            VStack(alignment: .leading) {
                                Text("Received").font(.caption).foregroundStyle(.secondary)
                                Text("\(p.tokens_received ?? 0)")
                            }
                        }
                        HStack(spacing: 10) {
                            GradientButton(title: "Buy Tokens") { showTopUp = true }
                            GradientButton(title: "Withdraw") { showWithdrawals = true }
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 16).fill(Color.primary.opacity(0.04)))
                }

                // Gifts details card
                VStack(alignment: .leading, spacing: 8) {
                    Text("Gifts").font(.headline)
                    HStack {
                        VStack(alignment: .leading) {
                            Text("Sent").font(.caption).foregroundStyle(.secondary)
                            Text("\(giftsSent)")
                        }
                        Spacer()
                        VStack(alignment: .leading) {
                            Text("Received").font(.caption).foregroundStyle(.secondary)
                            Text("\(giftsReceived)")
                        }
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 16).fill(Color.primary.opacity(0.04)))

                // Wishlists details card
                VStack(alignment: .leading, spacing: 8) {
                    Text("Wishlists").font(.headline)
                    HStack {
                        VStack(alignment: .leading) {
                            Text("Open wishlists").font(.caption).foregroundStyle(.secondary)
                            Text("\(openWishlists)")
                        }
                        Spacer()
                        VStack(alignment: .leading) {
                            Text("Fulfilled").font(.caption).foregroundStyle(.secondary)
                            Text("\(fulfilledWishlists)")
                        }
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 16).fill(Color.primary.opacity(0.04)))

                // Logout button full width
                GradientButton(title: "Log out") {
                    Task { await supabase.signOut() }
                }

                // Legal links
                VStack(spacing: 8) {
                    Link("Privacy Policy", destination: SupabaseConfig.webBase.appendingPathComponent("privacy"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Link("Terms of Service", destination: SupabaseConfig.webBase.appendingPathComponent("terms"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                NavigationLink(destination: DeleteAccountView()) {
                    Text("Delete Account")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 8)
                }
            }
            .padding()
        }
        .navigationTitle("Account")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .navigationDestination(isPresented: $showWithdrawals) { WithdrawalsView() }
        .sheet(isPresented: $showTopUp, onDismiss: { Task { await load() } }) {
            TokenTopUpSheet(onCompleted: { success in
                if success {
                    Task { await load() }
                    banners.show(Banner(title: "Balance refreshed", style: .success))
                }
            })
        }
        BannerHost().environmentObject(banners)
        }
    }

    private func load() async {
        guard let me = supabase.user?.id.uuidString else { return }
        do {
            profile = try await supabase.fetchProfile(username: nil, userId: me)
            // TODO compute real activity summary via gifts/wishlists today
            activityText = "You have no activity today."
            giftsSent = profile?.gifts_sent ?? 0
            giftsReceived = profile?.gifts_received ?? 0
            let wl = try? await supabase.wishlistCounts(userId: me)
            openWishlists = wl?.open ?? 0
            fulfilledWishlists = wl?.fulfilled ?? 0
        } catch {
            activityText = "Unable to load activity."
        }
    }
}
