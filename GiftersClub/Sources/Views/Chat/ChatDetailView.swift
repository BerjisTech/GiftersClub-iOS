import SwiftUI

struct ChatDetailView: View {
    let partner: ConversationItem.Partner
    @ObservedObject private var supabase = SupabaseManager.shared
    @State private var input: String = ""
    @State private var messages: [MessageItem] = []
    @State private var isLoading = false
    @State private var pollTask: Task<Void, Never>? = nil

    var body: some View {
        VStack(spacing: 0) {
            List(messages) { msg in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        if msg.fromMe { Spacer(minLength: 0) }
                        Bubble(text: msg.text, fromMe: msg.fromMe)
                        if !msg.fromMe { Spacer(minLength: 0) }
                    }
                    HStack {
                        if msg.fromMe { Spacer(minLength: 0) }
                        Text(msg.time)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        if !msg.fromMe { Spacer(minLength: 0) }
                    }
                }
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
            }
            .listStyle(.plain)

            HStack(spacing: 8) {
                TextField("Message", text: $input)
                    .textFieldStyle(.roundedBorder)
                Button { Task { await send() } } label: {
                    Image(systemName: "paperplane.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.thinMaterial)
        }
        .navigationTitle(partner.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .task { await initialLoad() }
        .onDisappear { pollTask?.cancel(); pollTask = nil }
    }

    private func initialLoad() async {
        isLoading = true; defer { isLoading = false }
        await markRead()
        await loadMessages()
        startPolling()
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                await loadMessages()
            }
        }
    }

    @MainActor private func loadMessages() async {
        do {
            let rows = try await supabase.fetchMessages(partnerId: partner.userId, orderAsc: true)
            messages = rows.map { r in
                MessageItem(
                    id: r.id,
                    // Determine direction by comparing to partner id to avoid relying on auth state timing
                    fromMe: r.sender_id != partner.userId,
                    text: r.content,
                    time: Self.relativeTime(r.created_at)
                )
            }
        } catch {
            // keep previous messages on error
        }
    }

    private func markRead() async {
        do { try await supabase.markMessagesAsRead(partnerId: partner.userId) } catch {}
    }

    private func send() async {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        input = ""
        do {
            _ = try await supabase.sendMessage(to: partner.userId, content: text)
            await markRead()
            await loadMessages()
        } catch {
            // Ideally show a banner. For now, restore input on failure
            input = text
        }
    }

    private static func relativeTime(_ iso: String) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = f.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) ?? Date()
        let secs = Int(Date().timeIntervalSince(date))
        if secs < 60 { return "now" }
        let m = secs/60; if m < 60 { return "\(m)m" }
        let h = m/60; if h < 24 { return "\(h)h" }
        let d = h/24; return "\(d)d"
    }
}

struct MessageItem: Identifiable { let id: String; let fromMe: Bool; let text: String; let time: String }

private struct Bubble: View {
    let text: String
    let fromMe: Bool
    private let maxWidth: CGFloat = 280
    var body: some View {
        Text(text)
            .foregroundColor(fromMe ? Color.white : Color.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(fromMe ? AppColors.primaryEnd : Color.primary.opacity(0.06))
            )
            .frame(maxWidth: maxWidth, alignment: fromMe ? .trailing : .leading)
    }
}
