import SwiftUI

struct ChatListView: View {
    @ObservedObject private var supabase = SupabaseManager.shared
    @State private var conversations: [ConversationItem] = []
    @State private var isLoading = false
    @State private var showGroups = true
    @State private var followersCount: Int = 0
    @State private var activityCount: Int = 0
    @State private var systemCount: Int = 0
    @State private var navPath = NavigationPath()

    var body: some View {
        NavigationStack(path: $navPath) {
            List {
                Section {
                    DisclosureGroup(isExpanded: $showGroups) {
                        NavigationLink { FollowersHubView() } label: {
                            GroupRow(icon: "person.2.fill", title: "Followers", subtitle: followersSubtitle)
                        }
                        NavigationLink { ActivityNotificationsView() } label: {
                        GroupRow(icon: "sparkles", title: "Activity", subtitle: activitySubtitle)
                        }
                        NavigationLink { SystemNotificationsView() } label: {
                            GroupRow(icon: "exclamationmark.bubble.fill", title: "System", subtitle: systemSubtitle)
                        }
                    } label: {
                        HStack {
                            Text("Notifications & Activity").font(.subheadline.weight(.semibold))
                            Spacer()
                            if totalNewCount > 0 {
                                Text("\(totalNewCount) new")
                                    .font(.caption2.weight(.semibold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section("Chats") {
                    if isLoading {
                        ProgressView().frame(maxWidth: .infinity)
                    } else if conversations.isEmpty {
                        Text("No conversations yet").foregroundStyle(.secondary)
                    } else {
                        ForEach(conversations) { conv in
                            NavigationLink {
                                ChatDetailView(partner: conv.partner)
                            } label: {
                                ConversationRow(item: conv)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    Task {
                                        try? await supabase.deleteConversation(with: conv.partner.userId)
                                        await loadConversations()
                                    }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Chats")
            .navigationDestination(for: ConversationItem.Partner.self) { p in
                ChatDetailView(partner: p)
            }
            .task {
                await load()
                await supabase.subscribeToAllChats { msg in
                    Task { @MainActor in
                        guard let me = supabase.user?.id.uuidString else { return }
                        let partnerId = (msg.sender_id == me) ? msg.receiver_id : msg.sender_id
                        if let idx = conversations.firstIndex(where: { $0.partner.userId == partnerId }) {
                            let existing = conversations[idx]
                            let preview = Self.previewText(content: msg.content, attachments: msg.attachments)
                            let time = Self.relativeTime(fromISO: msg.created_at)
                            let unread = (msg.sender_id == me) ? existing.unreadCount : (existing.unreadCount + 1)
                            let updated = ConversationItem(
                                id: existing.id,
                                partner: existing.partner,
                                lastMessagePreview: preview,
                                lastMessageTime: time,
                                unreadCount: unread
                            )
                            conversations.remove(at: idx)
                            conversations.insert(updated, at: 0)
                        } else {
                            await loadConversations()
                        }
                    }
                }
            }
            .onDisappear { Task { await supabase.unsubscribeAllChats() } }
            .refreshable { await load() }
            .onReceive(NotificationCenter.default.publisher(for: .openChatWithUsername)) { note in
                guard let username = note.object as? String else { return }
                Task {
                    if let id = try? await supabase.findUserId(byUsername: username) {
                        await MainActor.run {
                            navPath.append(ConversationItem.Partner(userId: id, username: username, displayName: username, imageURL: nil))
                        }
                    }
                }
            }
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        async let a: Void = loadConversations()
        async let b: Void = loadNotifications()
        _ = await (a, b)
    }

    private func loadConversations() async {
        do {
            let details = try await supabase.fetchConversationDetails()
            var items: [ConversationItem] = []
            for d in details {
                var content = d.last_message_content
                let looksEncrypted = { (s: String?) -> Bool in
                    guard let s = s?.trimmingCharacters(in: .whitespacesAndNewlines) else { return false }
                    return s.hasPrefix("{") && s.contains("\"ct\"")
                }
                if looksEncrypted(content) {
                    if let raw = content, let peerPub = await supabase.fetchPublicKey(for: d.partner_id), let key = try? E2EEKeyManager.shared.sharedSecret(with: peerPub), let dec = try? E2EEKeyManager.shared.decrypt(raw, with: key) {
                        content = dec
                    } else {
                        content = "encryption key missing for this chat"
                    }
                }
                let item = ConversationItem(
                    id: d.partner_id,
                    partner: .init(
                        userId: d.partner_id,
                        username: d.partner_name ?? "",
                        displayName: d.partner_name ?? "",
                        imageURL: d.partner_image.flatMap(URL.init(string:))
                    ),
                    lastMessagePreview: Self.previewText(content: content, attachments: d.last_message_attachments),
                    lastMessageTime: Self.relativeTime(fromISO: d.last_message_at),
                    unreadCount: d.unread_count
                )
                items.append(item)
            }
            conversations = items
        } catch {
            // leave as-is on error
        }
    }

    private func loadNotifications() async {
        do {
            let list = try await supabase.fetchNotifications()
            let cutoff = Date().addingTimeInterval(-24*3600)
            func isRecent(_ iso: String) -> Bool { (Self.parseISO(iso) ?? .distantPast) > cutoff }
            let follows = list.filter { $0.type == "follow" || $0.type == "friend_request" }
            let activity = list.filter { !["transaction","withdrawal","follow","friend_request"].contains($0.type) }
            let system = list.filter { $0.type == "transaction" || $0.type == "withdrawal" }
            followersCount = follows.filter { isRecent($0.created_at) }.count
            activityCount = activity.filter { isRecent($0.created_at) }.count
            systemCount = system.filter { isRecent($0.created_at) }.count
        } catch {
            followersCount = 0; activityCount = 0; systemCount = 0
        }
    }

    private var totalNewCount: Int { followersCount + activityCount + systemCount }
    private var followersSubtitle: String { followersCount > 0 ? "\(followersCount) new last 24h" : "No new followers" }
    private var activitySubtitle: String { activityCount > 0 ? "\(activityCount) new last 24h" : "No new activity" }
    private var systemSubtitle: String { systemCount > 0 ? "\(systemCount) new last 24h" : "No new system notifications" }

    private static func parseISO(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: s) ?? ISO8601DateFormatter().date(from: s)
    }
    private static func relativeTime(fromISO iso: String) -> String {
        guard let date = parseISO(iso) else { return "" }
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 60 { return "now" }
        let m = seconds/60; if m < 60 { return "\(m)m" }
        let h = m/60; if h < 24 { return "\(h)h" }
        let d = h/24; return "\(d)d"
    }

    private static func previewText(content: String?, attachments: [SupabaseManager.DBAttachment]?) -> String {
        if let c = content, !c.isEmpty { return c }
        if let a = attachments?.first {
            let t = (a.type ?? "image").lowercased()
            if t == "image" { return "[PHOTO]" }
            if t == "video" { return "[VIDEO]" }
        }
        return ""
    }
}

// MARK: - Rows
private struct GroupRow: View {
    let icon: String
    let title: String
    let subtitle: String
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
                Image(systemName: icon)
                    .foregroundStyle(.primary)
            }
            .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .contentShape(Rectangle())
        .padding(.vertical, 4)
    }
}

private struct ConversationRow: View {
    let item: ConversationItem
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Avatar(url: item.partner.imageURL)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(item.partner.displayName).font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(item.lastMessageTime).font(.caption2).foregroundStyle(.secondary)
                }
                HStack(alignment: .firstTextBaseline) {
                    Text(item.lastMessagePreview)
                        .lineLimit(1)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if item.unreadCount > 0 {
                        Text("\(item.unreadCount)")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                    }
                }
            }
        }
        .padding(.vertical, 6)
    }
}

private struct Avatar: View {
    let url: URL?
    var body: some View {
        ZStack {
            Circle().fill(Color.primary.opacity(0.06))
            if let url {
                AsyncImage(url: url) { img in
                    img.resizable().scaledToFill()
                } placeholder: { ProgressView().progressViewStyle(.circular) }
            } else {
                Image(systemName: "person.crop.circle.fill").resizable().scaledToFit().foregroundStyle(.secondary).padding(6)
            }
        }
        .frame(width: 44, height: 44)
        .clipShape(Circle())
    }
}

// MARK: - Models
struct ConversationItem: Identifiable {
    struct Partner: Hashable {
        let userId: String
        let username: String
        let displayName: String
        let imageURL: URL?
    }
    let id: String
    let partner: Partner
    let lastMessagePreview: String
    let lastMessageTime: String
    let unreadCount: Int

    static func samples() -> [ConversationItem] {
        [
            ConversationItem(
                id: "c1",
                partner: .init(userId: "u2", username: "sarah", displayName: "Sarah", imageURL: nil),
                lastMessagePreview: "Hey! Did you see my wishlist?",
                lastMessageTime: "2m",
                unreadCount: 2
            ),
            ConversationItem(
                id: "c2",
                partner: .init(userId: "u3", username: "chris", displayName: "Chris", imageURL: nil),
                lastMessagePreview: "Thanks for the gift!",
                lastMessageTime: "1h",
                unreadCount: 0
            )
        ]
    }
}
