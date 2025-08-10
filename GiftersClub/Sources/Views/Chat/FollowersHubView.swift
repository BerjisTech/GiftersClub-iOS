import SwiftUI

struct FollowersHubView: View {
    enum Tab: String, CaseIterable { case followers = "Followers", gifters = "Gifters", following = "Following" }
    @State private var tab: Tab = .followers

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
                switch tab {
                case .followers:
                    PlaceholderRow(text: "Your followers appear here")
                case .gifters:
                    PlaceholderRow(text: "People who gifted you appear here")
                case .following:
                    PlaceholderRow(text: "Accounts you follow appear here")
                }
            }
            .listStyle(.plain)
        }
        .navigationTitle("Followers")
        .navigationBarTitleDisplayMode(.inline)
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

