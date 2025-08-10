import SwiftUI

struct ActivityNotificationsView: View {
    @ObservedObject private var supabase = SupabaseManager.shared
    @State private var items: [SupabaseManager.DBNotification] = []
    @State private var isLoading = false
    var body: some View {
        List {
            if isLoading { ProgressView().frame(maxWidth: .infinity) }
            else if items.isEmpty { Text("No recent activity notifications").foregroundStyle(.secondary) }
            else {
                ForEach(items, id: \.id) { n in
                    NotificationRow(title: n.message, time: relativeTime(n.created_at))
                }
            }
        }
        .navigationTitle("Activity")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }
    private func load() async {
        isLoading = true; defer { isLoading = false }
        do {
            let list = try await supabase.fetchNotifications()
            items = list.filter { !["transaction","withdrawal","follow","friend_request"].contains($0.type) }
            // mark unread as read
            for n in items where n.is_read == false {
                try? await supabase.markNotificationRead(id: n.id)
            }
        } catch { items = [] }
    }
}

struct SystemNotificationsView: View {
    @ObservedObject private var supabase = SupabaseManager.shared
    @State private var items: [SupabaseManager.DBNotification] = []
    @State private var isLoading = false
    var body: some View {
        List {
            if isLoading { ProgressView().frame(maxWidth: .infinity) }
            else if items.isEmpty { Text("No system notifications").foregroundStyle(.secondary) }
            else {
                ForEach(items, id: \.id) { n in
                    NotificationRow(title: n.message, time: relativeTime(n.created_at))
                }
            }
        }
        .navigationTitle("System")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }
    private func load() async {
        isLoading = true; defer { isLoading = false }
        do {
            let list = try await supabase.fetchNotifications()
            items = list.filter { ["transaction","withdrawal"].contains($0.type) }
            for n in items where n.is_read == false { try? await supabase.markNotificationRead(id: n.id) }
        } catch { items = [] }
    }
}

private func relativeTime(_ iso: String) -> String {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let date = f.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) ?? Date()
    let secs = Int(Date().timeIntervalSince(date))
    if secs < 60 { return "now" }
    let m = secs/60; if m < 60 { return "\(m)m" }
    let h = m/60; if h < 24 { return "\(h)h" }
    let d = h/24; return "\(d)d"
}

private struct NotificationRow: View {
    let title: String
    let time: String
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)).frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline)
                Text(time).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }
}
