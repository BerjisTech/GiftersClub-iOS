import SwiftUI
import PhotosUI

struct ChatDetailView: View {
    let partner: ConversationItem.Partner
    @ObservedObject private var supabase = SupabaseManager.shared
    @State private var input: String = ""
    @State private var messages: [MessageItem] = []
    @State private var isLoading = false
    @State private var pollTask: Task<Void, Never>? = nil
    @State private var selectedItem: PhotosPickerItem? = nil
    @State private var selectedData: Data? = nil
    @State private var selectedMime: String? = nil
    @State private var isSending: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(messages) { msg in
                            // Build the full message content stack: bubble, media, time
                            VStack(alignment: .leading, spacing: 6) {
                                if !msg.text.isEmpty { Bubble(text: msg.text, fromMe: msg.fromMe) }
                                if let atts = msg.attachments, !atts.isEmpty { AttachmentsGrid(attachments: atts) }
                                HStack {
                                    if msg.fromMe { Spacer(minLength: 0) }
                                    Text(msg.time)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    if !msg.fromMe { Spacer(minLength: 0) }
                                }
                            }
                            // Align entire message row (text + media + time) to side using frame alignment
                            .frame(maxWidth: .infinity, alignment: msg.fromMe ? .trailing : .leading)
                            .id(msg.id)
                            .padding(.horizontal, 12)
                        }
                    }
                }
                .onChange(of: messages.last?.id, perform: { last in
                    if let last { withAnimation { proxy.scrollTo(last, anchor: .bottom) } }
                })
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                if let data = selectedData {
                    HStack(spacing: 10) {
                        AttachmentPreview(data: data, mime: selectedMime)
                            .frame(width: 64, height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        Spacer()
                        Button {
                            selectedData = nil; selectedMime = nil; selectedItem = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill").font(.title2).foregroundStyle(.secondary)
                        }
                    }
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.06)))
                }
                HStack(spacing: 8) {
                PhotosPicker(selection: $selectedItem, matching: .any(of: [.images, .videos])) {
                    Image(systemName: selectedData == nil ? "paperclip" : "checkmark.circle.fill")
                        .font(.title3)
                }
                .onChange(of: selectedItem, perform: { item in
                    guard let item else { return }
                    Task {
                        // Try images first
                        if let data = try? await item.loadTransferable(type: Data.self) {
                            await MainActor.run { selectedData = data; selectedMime = item.supportedContentTypes.first?.preferredMIMEType ?? "application/octet-stream" }
                        } else {
                            selectedData = nil; selectedMime = nil
                        }
                    }
                })
                TextField("Message", text: $input)
                    .textFieldStyle(.roundedBorder)
                Button { Task { await send() } } label: {
                    Image(systemName: "paperplane.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSending || (input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && selectedData == nil))
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(.thinMaterial)
            }
            .padding(.bottom, CustomBottomBar.barHeight)
        }
        .navigationTitle(partner.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .task { await initialLoad() }
        .onDisappear {
            pollTask?.cancel(); pollTask = nil
            Task { await supabase.unsubscribeChat(partnerId: partner.userId) }
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }

    private func initialLoad() async {
        isLoading = true; defer { isLoading = false }
        // Prime from cache immediately
        let cached = supabase.cachedMessages(partnerId: partner.userId)
        if !cached.isEmpty {
            messages = cached.map { r in
                MessageItem(
                    id: r.id,
                    fromMe: r.sender_id != partner.userId,
                    text: r.content,
                    time: Self.relativeTime(r.created_at),
                    attachments: r.attachments?.compactMap { a in
                        guard let u = a.url, let url = URL(string: u) else { return nil }
                        return ChatAttachment(url: url, type: a.type ?? "image")
                    }
                )
            }
        }
        await markRead()
        await loadMessages()
        // Subscribe to realtime inserts for this chat (stubbed), and keep polling fallback
        await supabase.subscribeToChat(partnerId: partner.userId) { msg in
            Task { @MainActor in
                if !messages.contains(where: { $0.id == msg.id }) {
                    let mapped = MessageItem(
                        id: msg.id,
                        fromMe: msg.sender_id != partner.userId,
                        text: msg.content,
                        time: Self.relativeTime(msg.created_at),
                        attachments: msg.attachments?.compactMap { a in
                            guard let u = a.url, let url = URL(string: u) else { return nil }
                            return ChatAttachment(url: url, type: a.type ?? "image")
                        }
                    )
                    messages.append(mapped)
                }
            }
        }
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
        let rows = await supabase.syncMessages(partnerId: partner.userId)
        messages = rows.map { r in
            MessageItem(
                id: r.id,
                // Determine direction by comparing to partner id to avoid relying on auth state timing
                fromMe: r.sender_id != partner.userId,
                text: r.content,
                time: Self.relativeTime(r.created_at),
                attachments: r.attachments?.compactMap { a in
                    guard let u = a.url, let url = URL(string: u) else { return nil }
                    return ChatAttachment(url: url, type: a.type ?? "image")
                }
            )
        }
    }

    private func markRead() async {
        do { try await supabase.markMessagesAsRead(partnerId: partner.userId) } catch {}
    }

    private func send() async {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty && selectedData == nil { return }
        input = ""; isSending = true
        do {
            var attachments: [SupabaseManager.MessageAttachment] = []
            if let data = selectedData, let mime = selectedMime {
                let ext = mime.split(separator: "/").last.map(String.init) ?? "bin"
                let name = "chat-\(Int(Date().timeIntervalSince1970)).\(ext)"
                // Insert shimmer placeholder message on my side while uploading and hide preview immediately
                let phId = "local-\(name)"
                let ph = ChatAttachment(url: nil, type: mime.hasPrefix("image/") ? "image" : (mime.hasPrefix("video/") ? "video" : "file"))
                messages.append(MessageItem(id: phId, fromMe: true, text: "", time: "now", attachments: [ph]))
                selectedData = nil; selectedMime = nil; selectedItem = nil
                let publicUrl = try await supabase.uploadMedia(bytes: data, fileName: name, mimeType: mime, bucket: "post")
                let kind = mime.hasPrefix("image/") ? "image" : (mime.hasPrefix("video/") ? "video" : "file")
                attachments.append(.init(url: publicUrl, type: kind))
            }
            if attachments.isEmpty {
                _ = try await supabase.sendMessage(to: partner.userId, content: text)
            } else {
                _ = try await supabase.sendMessage(to: partner.userId, content: text, attachments: attachments)
            }
            selectedData = nil; selectedMime = nil; selectedItem = nil
            await markRead()
            await loadMessages()
            isSending = false
        } catch {
            // Ideally show a banner. For now, restore input on failure
            input = text; isSending = false
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

struct MessageItem: Identifiable { let id: String; let fromMe: Bool; let text: String; let time: String; let attachments: [ChatAttachment]? }

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

private struct AttachmentPreview: View {
    let data: Data
    let mime: String?
    var body: some View {
        if (mime ?? "").hasPrefix("image/"), let ui = UIImage(data: data) {
            Image(uiImage: ui).resizable().scaledToFill()
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.06))
                Image(systemName: (mime ?? "").hasPrefix("video/") ? "play.circle.fill" : "paperclip").font(.title2).foregroundStyle(.secondary)
            }
        }
    }
}

struct ChatAttachment: Identifiable { let id: String; let url: URL?; let type: String; init(url: URL?, type: String) { self.url = url; self.type = type; self.id = url?.absoluteString ?? UUID().uuidString } }

private struct AttachmentsGrid: View {
    let attachments: [ChatAttachment]
    @State private var viewer: PostViewerModel? = nil
    private let columns = [GridItem(.fixed(120))]
    var body: some View {
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(attachments, id: \.id) { att in
                ZStack {
                    if att.url == nil {
                        ShimmerView()
                    } else if att.type == "image" {
                        AsyncImage(url: att.url) { img in img.resizable().scaledToFill().clipped() } placeholder: { ShimmerView() }
                    } else if att.type == "video" {
                        ZStack {
                            Rectangle().fill(Color.primary.opacity(0.06))
                            Image(systemName: "play.circle.fill").font(.system(size: 28)).foregroundStyle(.white)
                        }
                    } else {
                        RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.06))
                        Image(systemName: "paperclip").foregroundStyle(.secondary)
                    }
                }
                .frame(width: 120, height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .contentShape(Rectangle())
                .onTapGesture { if let _ = att.url { open(att) } }
            }
        }
        .sheet(item: $viewer) { model in
            PostViewer(model: model)
        }
    }
    private func open(_ att: ChatAttachment) {
        if att.type == "image", let url = att.url {
            viewer = PostViewerModel(id: url.absoluteString, authorUsername: "", authorName: nil, authorAvatar: nil, caption: "", media: .image(url))
        } else if att.type == "video", let url = att.url {
            viewer = PostViewerModel(id: url.absoluteString, authorUsername: "", authorName: nil, authorAvatar: nil, caption: "", media: .video(url))
        }
    }
}
