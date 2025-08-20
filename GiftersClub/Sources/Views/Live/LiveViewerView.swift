import SwiftUI
import Supabase

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
    @State private var hostProfile: SupabaseManager.DBProfile? = nil
    @State private var isFollowing: Bool? = nil

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
            await join()
            await supa.recordViewerJoin(streamId: live.id)
            await loadComments(); await startStatusPolling()
            if let row = try? await supa.fetchLiveStreamById(live.id) { viewerCount = row.viewer_count ?? 0 }
            if hostProfile == nil, let p = try? await supa.fetchProfileByUserId(live.host_id) {
                await MainActor.run { hostProfile = p }
            }
            // Preload follow state for viewer
            if let me = supa.user?.id.uuidString, me != live.host_id {
                struct Row: Decodable { let id: String }
                if let res: PostgrestResponse<[Row]> = try? await supa.client
                    .from("follows").select("id")
                    .eq("followed_id", value: live.host_id)
                    .eq("follower_id", value: me)
                    .limit(1)
                    .execute() {
                    await MainActor.run { isFollowing = !(res.value.isEmpty) }
                }
            }
        }
        .alert("Error", isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorText ?? "") }
        .onAppear { NotificationCenter.default.post(name: .hideBottomBar, object: nil) }
        .onDisappear { NotificationCenter.default.post(name: .showBottomBar, object: nil); commentsTimer?.invalidate(); commentsTimer = nil; statusTimer?.invalidate(); statusTimer = nil; Task { await supa.recordViewerLeave(streamId: live.id) } }
        .onChange(of: ended) { _, isEnded in if isEnded { NotificationCenter.default.post(name: .showBottomBar, object: nil) } }
    }

    private var topBar: some View {
        HStack(alignment: .center, spacing: 8) {
            HStack(spacing: 8) {
                if let img = hostProfile?.image, let url = URL(string: img) {
                    AsyncImage(url: url) { i in i.resizable().scaledToFill() } placeholder: { Color.white.opacity(0.2) }
                        .frame(width: 28, height: 28)
                        .clipShape(Circle())
                } else {
                    Circle().fill(Color.white.opacity(0.25)).frame(width: 28, height: 28)
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text(hostProfile?.username ?? "")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    if let f = hostProfile?.followers_count {
                        Text("\(f) followers")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.9))
                    }
                }
                if let me = supa.user?.id.uuidString, me != live.host_id {
                    Button(action: { Task { await toggleFollow() } }) {
                        Image(systemName: (isFollowing ?? false) ? "person.crop.circle.badge.minus" : "person.crop.circle.badge.plus")
                            .foregroundStyle(.white)
                    }
                    .padding(.leading, 6)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.35))
            .clipShape(Capsule())

            Spacer()

            HStack(spacing: 8) {
                Circle().fill(.red).frame(width: 8, height: 8)
                Label("\(viewerCount)", systemImage: "eye.fill")
                    .foregroundStyle(.white.opacity(0.9))
                    .font(.footnote)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.35))
            .clipShape(Capsule())

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
            // Comments list (simple overlay: avatar, username + gifter badge, comment)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(comments) { c in
                        HStack(alignment: .top, spacing: 8) {
                            if let p = profilesCache[c.user_id], let urlStr = p.image, let url = URL(string: urlStr) {
                                AsyncImage(url: url) { img in
                                    img.resizable().scaledToFill()
                                } placeholder: { Color.white.opacity(0.2) }
                                .frame(width: 20, height: 20)
                                .clipShape(Circle())
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(username(for: c.user_id))
                                        .font(.footnote.weight(.semibold))
                                        .foregroundStyle(userColor(c.user_id))
                                    if let p = profilesCache[c.user_id], let lvl = p.gifter_level, lvl > 0 {
                                        Text("Lv \(lvl)")
                                            .font(.caption2.weight(.bold))
                                            .foregroundStyle(.white)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.white.opacity(0.25))
                                            .clipShape(Capsule())
                                    }
                                }
                                Text(c.content)
                                    .font(.footnote)
                                    .foregroundStyle(.white)
                            }
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
                if let uname = hostProfile?.username {
                    Button(action: { NotificationCenter.default.post(name: .showGifterProfile, object: uname) }) {
                        Image(systemName: "gift.fill")
                    }
                    .buttonStyle(.bordered)
                }
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
            // Try session first, then viewer token
            var token: String? = nil
            if let session = try? await supa.fetchLiveSession(live.id), let t = session.token, !t.isEmpty {
                token = t
            } else {
                token = try? await supa.fetchLiveViewerToken(streamId: live.id)
            }
            guard let tok = token, !tok.isEmpty else {
                throw NSError(domain: "LiveKit", code: -1, userInfo: [NSLocalizedDescriptionKey: "Missing LiveKit token"]) }
            try await viewer.connect(url: SupabaseConfig.livekitURL, token: tok)
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

    private func userColor(_ id: String) -> Color {
        var hash: UInt64 = 5381
        for u in id.utf8 { hash = ((hash << 5) &+ hash) &+ UInt64(u) }
        let hue = Double(hash % 360) / 360.0
        return Color(hue: hue, saturation: 0.75, brightness: 0.95)
    }

    private func sendComment() async {
        let text = newComment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        if let _ = try? await supa.sendLiveComment(streamId: live.id, content: text) { newComment = "" }
    }

    private func toggleFollow() async {
        guard let me = supa.user?.id.uuidString else { return }
        do {
            if isFollowing == true {
                _ = try await supa.client
                    .from("follows").delete()
                    .eq("followed_id", value: live.host_id)
                    .eq("follower_id", value: me)
                    .execute()
                await MainActor.run { isFollowing = false }
            } else {
                struct F: Encodable { let followed_id: String; let follower_id: String }
                _ = try await supa.client
                    .from("follows").insert(F(followed_id: live.host_id, follower_id: me))
                    .select("id")
                    .execute()
                await MainActor.run { isFollowing = true }
            }
        } catch { }
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
                    // Disconnect first, then update UI
                    await viewer.disconnect()
                    await MainActor.run {
                        ended = true
                        NotificationCenter.default.post(name: .showBottomBar, object: nil)
                    }
                        if await suggestions.isEmpty {
                        if let lives = try? await supa.fetchFeedLiveStreams(limit: 4, query: nil) {
                            await MainActor.run { suggestions = lives }
                        }
                    }
                    } else {
                        await MainActor.run { viewerCount = row.viewer_count ?? 0 }
                        // Reinforce hiding bottom chrome while viewing
                        NotificationCenter.default.post(name: .hideBottomBar, object: nil)
                    }
                }
            }
        }
    }
}
