import SwiftUI

struct LiveViewerView: View {
    let live: SupabaseManager.DBLiveStreamWithStats
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewer = LiveKitViewer()
    @ObservedObject private var supa = SupabaseManager.shared
    @State private var errorText: String? = nil
    @State private var loading: Bool = true
    @State private var comments: [SupabaseManager.DBLiveStreamComment] = []
    @State private var profilesCache: [String: SupabaseManager.DBProfile] = [:]
    @State private var newComment: String = ""
    @State private var commentsTimer: Timer? = nil
    @State private var statusTimer: Timer? = nil
    @State private var ended: Bool = false
    @State private var suggestions: [SupabaseManager.DBLiveStreamWithStats] = []
    @State private var viewerCount: Int = 0

    var body: some View {
        ZStack {
            if ended {
                endedView
            } else if let track = viewer.remoteVideoTrack {
                LKVideoView(track: track)
                    .scaleEffect(x: -1, y: 1) // mirror horizontally to match Angular (-scale-x-100)
                    .ignoresSafeArea()
            } else {
                // Fallback: thumbnail overlay until video subscribed
                ZStack {
                    if let t = live.thumbnail_url, let url = URL(string: t) {
                        AsyncImage(url: url) { img in img.resizable().scaledToFill() } placeholder: { Color.black }
                    } else { Color.black }
                    LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .top, endPoint: .bottom)
                }
                .scaleEffect(x: -1, y: 1)
                .ignoresSafeArea()
            }

            if !ended {
                VStack {
                    topBar
                    Spacer()
                    bottomBar
                }
                .padding()
            }
        }
        .background(Color.black)
        .toolbar(.hidden, for: .navigationBar)
        .task {
            await join(); await loadComments(); await startStatusPolling()
            if let row = try? await supa.fetchLiveStreamById(live.id) { viewerCount = row.viewer_count ?? 0 }
        }
        .alert("Error", isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorText ?? "") }
        .onAppear { NotificationCenter.default.post(name: .hideBottomBar, object: nil) }
        .onDisappear { NotificationCenter.default.post(name: .showBottomBar, object: nil); commentsTimer?.invalidate(); commentsTimer = nil; statusTimer?.invalidate(); statusTimer = nil }
    }

    private var topBar: some View {
        HStack {
            HStack(spacing: 8) {
                Circle().fill(.red).frame(width: 8, height: 8)
                Text("LIVE")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                Label("\(viewerCount)", systemImage: "eye.fill")
                    .foregroundStyle(.white.opacity(0.9))
                    .font(.footnote)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.35))
            .clipShape(Capsule())

            Spacer()

            Button { Task { await viewer.disconnect(); dismiss() } } label: {
                Text("Close")
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.35))
                    .clipShape(Capsule())
            }
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 8) {
            // Comments list (simple overlay)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(comments) { c in
                        HStack(spacing: 6) {
                            Text(username(for: c.user_id))
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.white)
                            Text(c.content)
                                .font(.footnote)
                                .foregroundStyle(.white)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .frame(height: 180)
            HStack(spacing: 8) {
                TextField("Say something…", text: $newComment)
                    .textFieldStyle(.roundedBorder)
                Button(action: { Task { await sendComment() } }) {
                    Text("Send")
                }
                .disabled(newComment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(8)
        .background(Color.black.opacity(0.25))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func username(for userId: String) -> String {
        if let cached = profilesCache[userId] {
            let uname = cached.username
            return !uname.isEmpty ? uname : (cached.name ?? "")
        }
        Task {
            if let p = try? await supa.fetchProfileByUserId(userId) {
                await MainActor.run { profilesCache[userId] = p }
            }
        }
        return String(userId.prefix(6)) + "…"
    }

    private func join() async {
        loading = true
        defer { Task { await MainActor.run { loading = false } } }
        do {
            let token = try await supa.fetchLiveViewerToken(streamId: live.id)
            try await viewer.connect(url: SupabaseConfig.livekitURL, token: token)
            // In case tracks were already present, try to bind first available video
            if viewer.remoteVideoTrack == nil {
                // No-op here: LiveKitViewer will set via delegate when subscribed
            }
        } catch {
            await MainActor.run { errorText = (error as NSError).localizedDescription }
        }
    }

    private func loadComments() async {
        commentsTimer?.invalidate()
        commentsTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { _ in
            Task {
                if let list = try? await supa.fetchLiveComments(streamId: live.id) {
                    await MainActor.run { comments = list }
                }
            }
        }
    }

    private func sendComment() async {
        let text = newComment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        if let _ = try? await supa.sendLiveComment(streamId: live.id, content: text) { newComment = "" }
    }

    // MARK: - Ended state and suggestions
    private var endedView: some View {
        VStack(spacing: 12) {
            Text("This live has ended").font(.headline).foregroundStyle(.white)
            if suggestions.isEmpty {
                Text("Exploring other lives…").foregroundStyle(.white.opacity(0.8))
            } else {
                let columns = [GridItem(.flexible()), GridItem(.flexible())]
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(suggestions, id: \.id) { s in
                            NavigationLink(destination: LiveViewerView(live: s)) {
                                ZStack(alignment: .bottomLeading) {
                                    if let t = s.thumbnail_url, let url = URL(string: t) {
                                        AsyncImage(url: url) { img in img.resizable().scaledToFill() } placeholder: { Color.black }
                                    } else { Color.black }
                                    LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .top, endPoint: .bottom)
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(s.title).font(.subheadline.weight(.semibold)).foregroundStyle(.white).lineLimit(2)
                                        HStack(spacing: 12) {
                                            Label("\(s.viewer_count ?? 0)", systemImage: "eye.fill").foregroundStyle(.white).font(.caption2)
                                        }
                                    }.padding(8)
                                }
                                .frame(height: 160)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                        }
                    }.padding()
                }
            }
            Button("Back to Feed") { NotificationCenter.default.post(name: .goHome, object: nil) }
                .buttonStyle(.borderedProminent)
        }
    }

    private func startStatusPolling() async {
        statusTimer?.invalidate()
        statusTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { _ in
            Task {
                if let row = try? await supa.fetchLiveStreamById(live.id) {
                    if row.status != "live" {
                    await MainActor.run {
                        ended = true
                        Task { await viewer.disconnect() }
                        NotificationCenter.default.post(name: .showBottomBar, object: nil)
                    }
                    if suggestions.isEmpty {
                        if let lives = try? await supa.fetchFeedLiveStreams(limit: 4, query: nil) {
                            await MainActor.run { suggestions = lives }
                        }
                    }
                    } else {
                        await MainActor.run { viewerCount = row.viewer_count ?? 0 }
                    }
                }
            }
        }
    }
}
