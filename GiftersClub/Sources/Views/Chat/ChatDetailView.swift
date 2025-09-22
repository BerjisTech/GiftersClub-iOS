import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import AVFoundation

struct ChatDetailView: View {
    let partner: ConversationItem.Partner
    @ObservedObject private var supabase = SupabaseManager.shared
    @StateObject private var banners = BannerQueue()
    @State private var input: String = ""
    @State private var messages: [MessageItem] = []
    @State private var isLoading = false
    @State private var pollTask: Task<Void, Never>? = nil
    @State private var selectedItem: PhotosPickerItem? = nil
    @State private var selectedData: Data? = nil
    @State private var selectedMime: String? = nil
    @State private var selectedPreview: Data? = nil
    @State private var selectedDocURL: URL? = nil
    @State private var showDocImporter: Bool = false
    @State private var showPhotoPicker: Bool = false
    @State private var isSending: Bool = false

    @State private var showDeleteConversationConfirm = false
    @State private var pendingDeleteMessageId: String? = nil

    var body: some View {
        ZStack(alignment: .top) {
            BannerHost().environmentObject(banners)
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
                            // Context menu for deleting a specific message
                            .contextMenu {
                                Button(role: .destructive) {
                                    pendingDeleteMessageId = msg.id
                                    Task { await deleteMessage(id: msg.id) }
                                } label: {
                                    Label("Delete Message", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
                .onChange(of: messages.last?.id, perform: { last in
                    if let last { withAnimation { proxy.scrollTo(last, anchor: .bottom) } }
                })
            }
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                if let data = selectedPreview ?? selectedData {
                    HStack(spacing: 10) {
                        AttachmentPreview(data: data, mime: selectedMime)
                            .frame(width: 64, height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        Spacer()
                        Button {
                            selectedData = nil; selectedPreview = nil; selectedMime = nil; selectedItem = nil; selectedDocURL = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill").font(.title2).foregroundStyle(.secondary)
                        }
                    }
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.06)))
                }
                HStack(spacing: 8) {
                Menu {
                    Button {
                        showPhotoPicker = true
                    } label: {
                        Label("Photo or Video", systemImage: "photo.on.rectangle")
                    }
                    Button { showDocImporter = true } label: {
                        Label("Document", systemImage: "doc")
                    }
                } label: {
                    Image(systemName: (selectedData != nil || selectedDocURL != nil || selectedItem != nil) ? "checkmark.circle.fill" : "paperclip")
                        .font(.title3)
                }
                // Present Photos picker outside of Menu to avoid presentation issues
                .photosPicker(isPresented: $showPhotoPicker, selection: $selectedItem, matching: .any(of: [.images, .videos]))
                .onChange(of: selectedItem, perform: { item in
                    guard let item else { return }
                    // Do not eagerly load large files; just record that a selection exists and enable Send
                    selectedData = nil; selectedPreview = nil
                    let mime = item.supportedContentTypes.first?.preferredMIMEType
                    selectedMime = mime
                    Task {
                        // Best-effort lightweight preview: load Data and downscale if it's an image
                        if let data = try? await item.loadTransferable(type: Data.self) {
                            if (mime ?? "").hasPrefix("image/"), let ui = UIImage(data: data), let jpeg = ui.jpegData(compressionQuality: 0.6) {
                                await MainActor.run { selectedPreview = jpeg }
                            } else {
                                await MainActor.run { selectedPreview = Data() }
                            }
                        } else {
                            await MainActor.run { selectedPreview = Data() }
                        }
                    }
                })
                .fileImporter(isPresented: $showDocImporter, allowedContentTypes: [UTType.data], allowsMultipleSelection: false) { res in
                    switch res {
                    case .success(let urls):
                        selectedDocURL = urls.first
                        selectedData = nil; selectedPreview = Data()
                        selectedMime = urls.first.flatMap { mimeType(for: $0) } ?? "application/octet-stream"
                    case .failure:
                        selectedDocURL = nil; selectedPreview = nil
                    }
                }
                TextField("Message", text: $input)
                    .textFieldStyle(.roundedBorder)
                Button { Task { await send() } } label: {
                    Image(systemName: "paperplane.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSending || (input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && selectedData == nil && selectedDocURL == nil && selectedItem == nil))
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(.thinMaterial)
            }
            .padding(.bottom, CustomBottomBar.barHeight)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Button(action: {
                    // Route by userId to avoid ambiguity with display names
                    NotificationCenter.default.post(name: .showGifterProfileId, object: partner.userId)
                    NotificationCenter.default.post(name: .gotoProfile, object: nil)
                }) {
                    Text(partner.displayName)
                        .font(.headline)
                }
                .buttonStyle(.plain)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(role: .destructive) {
                        showDeleteConversationConfirm = true
                    } label: {
                        Label("Delete Conversation", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .alert("Delete Conversation?", isPresented: $showDeleteConversationConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { Task { await deleteConversation() } }
        } message: {
            Text("This will remove messages in this conversation. Some messages may persist for the other participant depending on server policies.")
        }
        .task { await initialLoad() }
        .onDisappear {
            pollTask?.cancel(); pollTask = nil
            Task { await supabase.unsubscribeChat(partnerId: partner.userId) }
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func deleteMessage(id: String) async {
        do {
            try await supabase.deleteMessage(id: id)
            await loadMessages()
        } catch {
            // silently ignore; optionally show banner via NotificationCenter
        }
    }

    private func deleteConversation() async {
        do {
            try await supabase.deleteConversation(with: partner.userId)
            await MainActor.run { messages.removeAll() }
        } catch {
            // ignore errors
        }
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
        if text.isEmpty && selectedData == nil && selectedDocURL == nil && selectedItem == nil { return }
        input = ""; isSending = true
        do {
            var attachments: [SupabaseManager.MessageAttachment] = []
            // If a document was picked, upload it as a file type
            if let doc = selectedDocURL {
                var didAccess = false
                if doc.startAccessingSecurityScopedResource() { didAccess = true }
                defer { if didAccess { doc.stopAccessingSecurityScopedResource() } }
                let data = try Data(contentsOf: doc)
                let mime = mimeType(for: doc) ?? "application/octet-stream"
                let ext = doc.pathExtension.isEmpty ? (mime.split(separator: "/").last.map(String.init) ?? "bin") : doc.pathExtension
                let name = "chat-\(Int(Date().timeIntervalSince1970)).\(ext)"
                // Shimmer placeholder for attachment
                let phId = "local-\(name)"
                let ph = ChatAttachment(url: nil, type: "file")
                messages.append(MessageItem(id: phId, fromMe: true, text: "", time: "now", attachments: [ph]))
                selectedDocURL = nil
                let publicUrl = try await supabase.uploadMedia(bytes: data, fileName: name, mimeType: mime, bucket: "post")
                attachments.append(.init(url: publicUrl, type: "file"))
            } else if let item = selectedItem, selectedData == nil {
                // Lazy-load selected photo/video data now
                if let data = try? await item.loadTransferable(type: Data.self) {
                    let mime = item.supportedContentTypes.first?.preferredMIMEType ?? "application/octet-stream"
                    await MainActor.run { selectedData = data; selectedMime = mime }
                }
            }
            if var data = selectedData, var mime = selectedMime {
                await Task.yield()
                // Transcode for compatibility: HEIC -> JPEG, non-MP4 video -> MP4
                if mime == "image/heic" || mime == "image/heif" || mime == "image/heif-sequence" {
                    autoreleasepool {
                        if let img = UIImage(data: data), let jpeg = img.jpegData(compressionQuality: 0.9) {
                            data = jpeg; mime = "image/jpeg"
                        }
                    }
                } else if mime.hasPrefix("video/") && mime != "video/mp4" {
                    if let mp4 = await transcodeToMP4(data: data) { data = mp4; mime = "video/mp4" }
                }
                let ext = mime.split(separator: "/").last.map(String.init) ?? "bin"
                let name = "chat-\(Int(Date().timeIntervalSince1970)).\(ext)"
                // Insert shimmer placeholder message on my side while uploading and hide preview immediately
                let phId = "local-\(name)"
                let ph = ChatAttachment(url: nil, type: mime.hasPrefix("image/") ? "image" : (mime.hasPrefix("video/") ? "video" : "file"))
                messages.append(MessageItem(id: phId, fromMe: true, text: "", time: "now", attachments: [ph]))
                selectedData = nil; selectedPreview = nil; selectedMime = nil; selectedItem = nil
                let publicUrl = try await supabase.uploadMedia(bytes: data, fileName: name, mimeType: mime, bucket: "post")
                let kind = mime.hasPrefix("image/") ? "image" : (mime.hasPrefix("video/") ? "video" : "file")
                attachments.append(.init(url: publicUrl, type: kind))
            }
            if attachments.isEmpty {
                _ = try await supabase.sendMessage(to: partner.userId, content: text)
            } else {
                _ = try await supabase.sendMessage(to: partner.userId, content: text, attachments: attachments)
            }
            selectedData = nil; selectedPreview = nil; selectedMime = nil; selectedItem = nil; selectedDocURL = nil
            await markRead()
            await loadMessages()
            isSending = false
        } catch {
            // Show failure banner and restore input
            banners.show(Banner(title: "Failed to send attachment", style: .error))
            input = text; isSending = false
        }
    }

    private func mimeType(for url: URL) -> String? {
        if #available(iOS 14.0, *) {
            if let type = UTType(filenameExtension: url.pathExtension) {
                return type.preferredMIMEType
            }
        }
        return nil
    }

    // Minimal local video transcode to MP4 for compatibility across devices/buckets
    private func transcodeToMP4(data: Data) async -> Data? {
        let inputURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("chat_in_\(UUID().uuidString).mov")
        do { try data.write(to: inputURL, options: .atomic) } catch { return nil }
        let asset = AVAsset(url: inputURL)
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else { return nil }
        let outURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("chat_out_\(UUID().uuidString).mp4")
        session.outputURL = outURL
        session.outputFileType = .mp4
        session.shouldOptimizeForNetworkUse = true
        return await withUnsafeContinuation { cont in
            session.exportAsynchronously {
                defer { try? FileManager.default.removeItem(at: inputURL); try? FileManager.default.removeItem(at: outURL) }
                let data = try? Data(contentsOf: outURL)
                cont.resume(returning: data)
            }
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
            .frame(maxWidth: .infinity, alignment: fromMe ? .trailing : .leading)
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
