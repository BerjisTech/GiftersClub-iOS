import SwiftUI

struct FollowersHubView: View {
    enum Tab: String, CaseIterable { case followers = "Followers", gifters = "Gifters", following = "Following" }
    @State private var tab: Tab = .followers
    @ObservedObject private var supabase = SupabaseManager.shared
    @State private var followers: [SupabaseManager.DBProfile] = []
    @State private var following: [SupabaseManager.DBProfile] = []
    @State private var gifters: [SupabaseManager.DBProfile] = []
    @State private var isLoading = false

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                ForEach(Tab.allCases, id: \.self) { t in
                    Text(t.rawValue).tag(t)
                }
            }
            .pickerStyle(.segmented)
            .padding()

            List {
                if isLoading { ProgressView().frame(maxWidth: .infinity) }
                else {
                    switch tab {
                    case .followers:
                        if followers.isEmpty { PlaceholderRow(text: "No followers yet") }
                        ForEach(followers, id: \.user_id) { p in ProfileRow(p: p) }
                    case .gifters:
                        if gifters.isEmpty { PlaceholderRow(text: "No gifters yet") }
                        ForEach(gifters, id: \.user_id) { p in ProfileRow(p: p) }
                    case .following:
                        if following.isEmpty { PlaceholderRow(text: "Not following anyone yet") }
                        ForEach(following, id: \.user_id) { p in ProfileRow(p: p) }
                    }
                }
            }
            .listStyle(.plain)
        }
        .navigationTitle("Followers")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .onChange(of: tab, perform: { _ in Task { await load() } })
    }

    private func load() async {
        guard let me = supabase.user?.id.uuidString else { return }
        await MainActor.run { isLoading = true }
        defer { Task { await MainActor.run { isLoading = false } } }
        do {
            switch tab {
            case .followers:
                let list = try await supabase.fetchFollowers(of: me)
                await MainActor.run { followers = list }
            case .gifters:
                let list = try await supabase.fetchGifters(for: me)
                await MainActor.run { gifters = list }
            case .following:
                let list = try await supabase.fetchFollowing(of: me)
                await MainActor.run { following = list }
            }
        } catch {
            // leave lists unchanged on error
        }
    }
}

private struct PlaceholderRow: View {
    let text: String
    var body: some View {
        HStack(spacing: 12) {
            Circle().fill(Color.primary.opacity(0.06)).frame(width: 36, height: 36)
            Text(text).foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
    }
}

private struct ProfileRow: View {
    let p: SupabaseManager.DBProfile
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Color.primary.opacity(0.06))
                if let img = p.image, let url = URL(string: img) {
                    AsyncImage(url: url) { img in img.resizable().scaledToFill() } placeholder: { Color.primary.opacity(0.06) }
                } else {
                    Image(systemName: "person.crop.circle.fill").resizable().scaledToFit().foregroundStyle(.secondary).padding(4)
                }
            }
            .frame(width: 36, height: 36)
            .clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(p.name?.isEmpty == false ? (p.name ?? "") : (p.username))
                    .font(.subheadline.weight(.semibold))
                Text("@\(p.username)").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.footnote).foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .onTapGesture { NotificationCenter.default.post(name: .showGifterProfile, object: p.username) }
        .padding(.vertical, 6)
    }
}
