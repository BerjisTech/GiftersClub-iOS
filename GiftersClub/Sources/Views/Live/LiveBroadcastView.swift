import SwiftUI
import AVFoundation

struct LiveBroadcastView: View {
    let stream: SupabaseManager.DBLiveStream
    @Environment(\.dismiss) private var dismiss
    @State private var isLive: Bool = false
    @State private var viewers: Int = 0
    @State private var ending: Bool = false
    @State private var errorText: String? = nil
    @StateObject private var supa = SupabaseManager.shared
    @StateObject private var publisher = LiveKitPublisher()
    @State private var comments: [SupabaseManager.DBLiveStreamComment] = []
    @State private var newComment: String = ""
    @State private var commentsTimer: Timer? = nil
    @State private var profilesCache: [String: SupabaseManager.DBProfile] = [:]

    var body: some View {
        ZStack {
            ZStack {
                // LiveKit local camera preview
                Color.black.ignoresSafeArea()
                if let track = publisher.localVideoTrack {
                    LKVideoView(track: track)
                        .scaleEffect(x: publisher.isFront ? -1 : 1, y: 1)
                        .ignoresSafeArea()
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "video.fill").font(.system(size: 50)).foregroundStyle(.white.opacity(0.8))
                        Text("Initializing camera…").foregroundStyle(.white.opacity(0.9))
                    }
                }
            }

            VStack {
                topBar
                Spacer()
                commentsBar
                bottomBar
            }
            .padding()
        }
        .onAppear { NotificationCenter.default.post(name: .hideBottomBar, object: nil); Task { await goLiveIfNeeded(); await startHostPolling() } }
        .onDisappear { NotificationCenter.default.post(name: .showBottomBar, object: nil) }
        .alert("End Live Stream?", isPresented: $ending) {
            Button("End Live", role: .destructive) { Task { await endLive() } }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Are you sure you want to end the live stream?") }
        .alert("Error", isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorText ?? "") }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var topBar: some View {
        HStack {
            HStack(spacing: 8) {
                Circle().fill(isLive ? .red : .gray).frame(width: 8, height: 8)
                Text("\(viewers) viewers")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.9))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.35))
            .clipShape(Capsule())

            Spacer()

            Button { ending = true } label: {
                Text("End")
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
        HStack(spacing: 8) {
            Button { Task { await publisher.toggleMic() } } label: {
                Image(systemName: publisher.micOn ? "mic.fill" : "mic.slash.fill")
                    .foregroundStyle(.white)
            }
            .frame(width: 44, height: 44)
            .background(Color.black.opacity(0.35))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            Button { Task { await publisher.toggleCamera() } } label: {
                Image(systemName: publisher.cameraOn ? "camera.fill" : "camera")
                    .foregroundStyle(.white)
            }
            .frame(width: 44, height: 44)
            .background(Color.black.opacity(0.35))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            // Comment composer (host) between camera and gift
            HStack(spacing: 6) {
                TextField("Say something…", text: $newComment)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 120)
                Button("Send") { Task { await sendComment() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(newComment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 6)
            .background(Color.black.opacity(0.35))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            Button { /* gifts sheet */ } label: {
                Image(systemName: "gift.fill").foregroundStyle(.white)
            }
            .frame(width: 44, height: 44)
            .background(Color.black.opacity(0.35))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .padding(.bottom, 24)
    }

    private var commentsBar: some View {
        VStack(spacing: 8) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(comments, id: \.id) { c in
                        HStack(alignment: .top, spacing: 8) {
                            if let p = profilesCache[c.user_id], let img = p.image, let url = URL(string: img) {
                                AsyncImage(url: url) { img in img.resizable().scaledToFill() } placeholder: { Color.white.opacity(0.2) }
                                    .frame(width: 20, height: 20)
                                    .clipShape(Circle())
                            } else {
                                Circle().fill(Color.white.opacity(0.2)).frame(width: 20, height: 20)
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
                    }
                }
            }
            .frame(height: 140)
        }
        .padding(8)
        .background(Color.black.opacity(0.25))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func goLiveIfNeeded() async {
        guard !isLive else { return }
        guard let token = stream.token else { await MainActor.run { errorText = "Missing LiveKit token" }; return }
        // Ensure LiveKit URL is configured
        if SupabaseConfig.livekitURL.host?.contains("your-livekit-host.example") == true {
            await MainActor.run { errorText = "Set SupabaseConfig.livekitURL to your LiveKit server (e.g., wss://yourdomain.livekit.cloud)" }
            return
        }
        let iso = ISO8601DateFormatter().string(from: Date())
        do {
            // Mark live in DB
            _ = try await supa.updateLiveSession(id: stream.id, updates: ["status": "live", "started_at": iso])
            // Connect to LiveKit and publish camera+mic
            try await publisher.connectAndPublish(url: SupabaseConfig.livekitURL, token: token)
            await MainActor.run { isLive = true }
        } catch {
            await MainActor.run { errorText = (error as NSError).localizedDescription }
        }
    }

    private func startHostPolling() async {
        commentsTimer?.invalidate()
        commentsTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { _ in
            Task {
                if let row = try? await supa.fetchLiveStreamById(stream.id) {
                    await MainActor.run { viewers = row.viewer_count ?? 0 }
                }
                if let list = try? await supa.fetchLiveComments(streamId: stream.id) {
                    await MainActor.run { comments = list }
                    // Preload profiles
                    for c in list {
                        if await profilesCache[c.user_id] == nil {
                            if let p = try? await supa.fetchProfileByUserId(c.user_id) {
                                await MainActor.run { profilesCache[c.user_id] = p }
                            }
                        }
                    }
                }
            }
        }
    }

    private func sendComment() async {
        let text = newComment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        if let _ = try? await supa.sendLiveComment(streamId: stream.id, content: text) { newComment = "" }
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

    private func userColor(_ id: String) -> Color {
        var hash: UInt64 = 5381
        for u in id.utf8 { hash = ((hash << 5) &+ hash) &+ UInt64(u) }
        let hue = Double(hash % 360) / 360.0
        return Color(hue: hue, saturation: 0.75, brightness: 0.95)
    }

    private func endLive() async {
        let iso = ISO8601DateFormatter().string(from: Date())
        do {
            // Disconnect from LiveKit and mark ended
            await publisher.disconnect()
            _ = try await supa.updateLiveSession(id: stream.id, updates: ["status": "ended", "ended_at": iso])
            await MainActor.run { dismiss() }
        } catch {
            await MainActor.run { errorText = (error as NSError).localizedDescription }
        }
    }
}

#Preview {
    LiveBroadcastView(stream: .init(id: UUID().uuidString, host_id: UUID().uuidString, title: "My Stream", description: "", status: "scheduled", viewer_count: 0, started_at: nil, ended_at: nil, token: "tok"))
}
