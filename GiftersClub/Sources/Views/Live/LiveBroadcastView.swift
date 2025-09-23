import SwiftUI
#if canImport(LiveKit)
import LiveKit
#endif
import AVFoundation
import UIKit

struct LiveBroadcastView: View {
    let stream: SupabaseManager.DBLiveStream
    var startManagePanel: Bool = false
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var banners: BannerQueue
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
    @State private var cohostStreamIds: [String] = []
    @State private var commentSubscribedIds: Set<String> = []
    @State private var giftSubscribedIds: Set<String> = []
    // Matches (battles)
    @State private var battleActive: Bool = false
    @State private var battleId: String? = nil
    @State private var battleStartedAt: String? = nil
    @State private var battleParticipants: [SupabaseManager.DBBattleParticipant] = []
    @State private var battleTallies: [String: Int] = [:]
    @State private var battleTimer: Timer? = nil
    @State private var battleEndsAt: String? = nil
    @State private var battleCountdownTimer: Timer? = nil
    @State private var battleCountdownText: String = ""
    // Invite management (host)
    @State private var showManagePanel: Bool = false
    @State private var pendingInvites: [[String: Any]] = []
    @State private var inviteUsername: String = ""
    @State private var invitesTimer: Timer? = nil
    @State private var inviteQuery: String = ""
    @State private var inviteSuggestions: [SupabaseManager.DBProfile] = []
    @State private var modQuery: String = ""
    @State private var modSuggestions: [SupabaseManager.DBProfile] = []
    @State private var addQuery: String = ""
    @State private var addSuggestions: [SupabaseManager.DBProfile] = []
    @State private var addTeam: Int = 1
    @State private var showViewerList: Bool = false
    @State private var viewerProfiles: [SupabaseManager.DBProfile] = []
    @State private var viewerListTimer: Timer? = nil
    @State private var moderatorIds: Set<String> = []
    @State private var moderatorProfiles: [SupabaseManager.DBProfile] = []
    @State private var stickToBottom: Bool = true
    @State private var beautyPipeline: BeautyFilterPipeline? = nil
    // Poster details & taps/hearts (host sees remote hearts and total taps)
    @State private var hostProfile: SupabaseManager.DBProfile? = nil
    @State private var totalTaps: Int = 0
    private struct HeartParticle: Identifiable { let id = UUID(); var position: CGPoint; var opacity: Double; var scale: CGFloat }
    @State private var tapHearts: [HeartParticle] = []
    @State private var tapBatch: Int = 0
    @State private var tapFlushTimer: Timer? = nil

    var body: some View {
        ZStack {
            ZStack {
                // LiveKit local + remote camera previews (multi-host)
                Color.black.ignoresSafeArea()
                videoGrid
                if battleActive {
                    HStack(spacing: 0) {
                        Color.yellow.opacity(0.08)
                        Color.blue.opacity(0.08)
                    }
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                }
            }

            VStack(spacing: 6) {
                topBar
                    .frame(maxWidth: .infinity)
                if battleActive { matchBar }
                Spacer(minLength: 0)
                commentsBar
                bottomBar
                    .frame(maxWidth: .infinity, alignment: .bottom)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            // Floating hearts overlay (remote hearts spawn at bottom-right)
            ForEach(tapHearts) { h in
                Image(systemName: "heart.fill")
                    .foregroundStyle(.red)
                    .position(h.position)
                    .opacity(h.opacity)
                    .scaleEffect(h.scale)
                    .allowsHitTesting(false)
            }
        }
        .onAppear {
            // Keep screen awake during hosting to avoid display sleep
            UIApplication.shared.isIdleTimerDisabled = true
            NotificationCenter.default.post(name: .hideBottomBar, object: nil)
            Task { await goLiveIfNeeded(); await startHostPolling(); await startRealtimeComments(); await startRealtimeGifts(); await preloadHostProfile(); await subscribeToTaps() }
            if startManagePanel { showManagePanel = true }
        }
        .onDisappear {
            NotificationCenter.default.post(name: .showBottomBar, object: nil)
            // Restore idle timer behavior when leaving live
            UIApplication.shared.isIdleTimerDisabled = false
            battleTimer?.invalidate(); battleTimer = nil
            battleCountdownTimer?.invalidate(); battleCountdownTimer = nil
            invitesTimer?.invalidate(); invitesTimer = nil
            tapFlushTimer?.invalidate(); tapFlushTimer = nil
            Task {
                for id in commentSubscribedIds { await supa.unsubscribeLiveComments(streamId: id) }
                for id in giftSubscribedIds { await supa.unsubscribeGiftSent(streamId: id) }
            }
        }
        .alert("End Live Stream?", isPresented: $ending) {
            Button("End Live", role: .destructive) { Task { await endLive() } }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Are you sure you want to end the live stream?") }
        .alert("Error", isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorText ?? "") }
        .toolbar(.hidden, for: .navigationBar)
    }

    private func startRealtimeComments() async {
        if let ids = try? await supa.fetchCohostStreamIds(streamId: stream.id) {
            _ = await MainActor.run { cohostStreamIds = ids }
            for id in ids where !commentSubscribedIds.contains(id) {
                await supa.subscribeToLiveComments(streamId: id) { c in
                    if !comments.contains(where: { $0.id == c.id }) { comments.append(c) }
                    Task { if profilesCache[c.user_id] == nil, let p = try? await supa.fetchProfileByUserId(c.user_id) { await MainActor.run { profilesCache[c.user_id] = p } } }
                }
                _ = await MainActor.run { commentSubscribedIds.insert(id) }
            }
            // Initial load existing comments across cohost streams
            if let list = try? await supa.fetchLiveCommentsMulti(streamIds: ids) {
                await MainActor.run { comments = list }
                for c in list {
                    if profilesCache[c.user_id] == nil, let p = try? await supa.fetchProfileByUserId(c.user_id) {
                        await MainActor.run { profilesCache[c.user_id] = p }
                    }
                }
            }
        }
    }

    private func startRealtimeGifts() async {
        // Subscribe to gift_sent across this stream and cohost streams to mirror gift comments for host
        let ids = cohostStreamIds.isEmpty ? [stream.id] : cohostStreamIds
        for id in ids where !giftSubscribedIds.contains(id) {
            await supa.subscribeToGiftSent(streamId: id) { gift in
                Task { @MainActor in
                    // Resolve gifter username
                    var uname = "Someone"
                    if let p = profilesCache[gift.gifter] { uname = p.username }
                    else if let p = try? await supa.fetchProfileByUserId(gift.gifter) { profilesCache[gift.gifter] = p; uname = p.username }
                    // Resolve gift name
                    var gname = "a gift"
                    if let g = try? await supa.fetchGiftById(gift.gift), let n = g.name, !n.isEmpty { gname = n }
                    let msg = "\(uname) sent a \(gname)"
                    let synthetic = SupabaseManager.DBLiveStreamComment(
                        id: UUID().uuidString,
                        live_stream_id: gift.live_stream_id,
                        user_id: gift.gifter,
                        content: msg,
                        created_at: gift.created_at
                    )
                    comments.append(synthetic)
                }
            }
            _ = await MainActor.run { giftSubscribedIds.insert(id) }
        }
    }

    private var videoGrid: some View {
        struct Tile: Identifiable { let id: String; let track: LiveKit.VideoTrack; let userId: String? }
        var tiles: [Tile] = []
        if let local = publisher.localVideoTrack { tiles.append(Tile(id: "local", track: local, userId: stream.host_id)) }
        for rv in publisher.remoteVideos { tiles.append(Tile(id: rv.id, track: rv.track, userId: rv.identity)) }
        return Group {
            if tiles.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "video.fill").font(.system(size: 50)).foregroundStyle(.white.opacity(0.8))
                    Text("Initializing camera…").foregroundStyle(.white.opacity(0.9))
                }
            } else if tiles.count == 1 {
                LKVideoView(track: tiles.first!.track)
                    // Show host preview as viewers see it (no mirror)
                    .scaleEffect(x: 1, y: 1)
                    .ignoresSafeArea()
                    .overlay(alignment: .topTrailing) {
                        Group {
                            if publisher.beautyOn, let pipe = beautyPipeline {
                                BeautyPreviewView(pipeline: pipe)
                                    .frame(width: 120, height: 180)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.4), lineWidth: 1))
                            } else {
                                Color.clear
                            }
                        }
                        .padding(8)
                    }
            } else {
                let cols: [GridItem] = Array(repeating: GridItem(.flexible(), spacing: 8), count: tiles.count <= 2 ? 1 : (tiles.count <= 4 ? 2 : 3))
                ScrollView { // allow more than 6 tracks to scroll
                    LazyVGrid(columns: cols, spacing: 8) {
                        ForEach(tiles) { t in
                            ZStack(alignment: .bottomLeading) {
                                LKVideoView(track: t.track)
                                    .aspectRatio(3/4, contentMode: .fit)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.6), lineWidth: 1))
                                    .overlay(teamOverlay(for: t.userId))
                                Text(usernamePill(for: t.userId))
                                    .font(.caption2.bold())
                                    .padding(.horizontal, 8).padding(.vertical, 4)
                                    .background(Color.black.opacity(0.4))
                                    .clipShape(Capsule())
                                    .padding(6)
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                }
                .ignoresSafeArea()
            }
        }
    }

    private func teamOverlay(for userId: String?) -> AnyView {
        guard battleActive, let uid = userId else { return AnyView(EmptyView()) }
        let team = battleParticipants.first(where: { $0.user_id == uid })?.team
        let c: Color? = team == 1 ? .yellow.opacity(0.12) : (team == 2 ? .blue.opacity(0.12) : nil)
        if let cc = c { return AnyView(RoundedRectangle(cornerRadius: 8).fill(cc)) }
        return AnyView(EmptyView())
    }
    private func usernamePill(for userId: String?) -> String {
        guard let uid = userId else { return "" }
        if let cached = profilesCache[uid] { return cached.username.isEmpty ? (cached.name ?? String(uid.prefix(6))) : cached.username }
        Task { if let p = try? await supa.fetchProfileByUserId(uid) { await MainActor.run { profilesCache[uid] = p } } }
        return String(uid.prefix(6))
    }

    private var topBar: some View {
        HStack(alignment: .top, spacing: 8) {
            // Streamer details box (avatar + username/followers)
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    if let img = hostProfile?.image, let url = URL(string: img) {
                        AsyncImage(url: url) { i in i.resizable().scaledToFill() } placeholder: { Color.white.opacity(0.2) }
                            .frame(width: 40, height: 40)
                            .clipShape(Circle())
                    } else { Circle().fill(Color.white.opacity(0.25)).frame(width: 40, height: 40) }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(hostProfile?.username ?? "").font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                        if let f = hostProfile?.followers_count { Text("\(f) followers").font(.caption2).foregroundStyle(.white.opacity(0.9)) }
                HStack(spacing: 6) {
                    Image(systemName: "eye.fill").foregroundStyle(.white)
                    Text("\(viewers)").foregroundStyle(.white).font(.footnote)
                }
                .onTapGesture {
                    Task {
                        if let list = try? await supa.fetchLiveViewers(streamId: stream.id) {
                            await MainActor.run { viewerProfiles = list; showViewerList = true }
                        } else {
                            await MainActor.run { showViewerList = true }
                        }
                    }
                }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color.black.opacity(0.35))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                // Taps row under details (host sees total taps always)
                HStack(spacing: 8) {
                    Image(systemName: "heart.fill").foregroundStyle(.red)
                    Text(shortCount(totalTaps)).foregroundStyle(.white).font(.footnote)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.black.opacity(0.35))
                .clipShape(Capsule())
            }

            Spacer(minLength: 8)

            // Vertical host tools
            VStack(spacing: 8) {
                Button { ending = true } label: {
                    Text("End")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.red.opacity(0.6))
                        .clipShape(Capsule())
                }
                Button { Task { await publisher.switchCamera() } } label: {
                    Image(systemName: "arrow.triangle.2.circlepath.camera").foregroundStyle(.white)
                }.frame(width: 32, height: 32)
                Button { Task { await publisher.toggleCamera() } } label: {
                    Image(systemName: publisher.cameraOn ? "video.fill" : "video.slash.fill").foregroundStyle(.white)
                }.frame(width: 32, height: 32)
                Button { Task { await publisher.toggleMic() } } label: {
                    Image(systemName: publisher.micOn ? "mic.fill" : "mic.slash.fill").foregroundStyle(.white)
                }.frame(width: 32, height: 32)
                if let url = URL(string: "https://gifters.club/live/\(stream.id)") {
                    ShareLink(item: url) { Image(systemName: "square.and.arrow.up").foregroundStyle(.white) }.frame(width: 32, height: 32)
                }
            }
            .padding(6)
            .background(Color.black.opacity(0.35))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private func shortCount(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fm", Double(n)/1_000_000.0) }
        if n >= 1_000 { return String(format: "%.1fk", Double(n)/1_000.0) }
        return String(n)
    }

    private var bottomBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 8) {
            // Effects (beauty/AR) placed before composer so it stays visible
            Menu {
                Toggle(isOn: Binding(get: { publisher.beautyOn }, set: { v in
                    publisher.setBeautyFilter(enabled: v)
                    if v {
                        if beautyPipeline == nil { beautyPipeline = BeautyFilterPipeline() }
                        beautyPipeline?.start()
                    } else {
                        beautyPipeline?.stop(); beautyPipeline = nil
                    }
                })) {
                    Label("Beauty", systemImage: "wand.and.stars")
                }
                Button("AR Face Effects (coming soon)") {}
            } label: {
                Image(systemName: "wand.and.stars").foregroundStyle(.white)
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

            Button { showManagePanel = true } label: {
                Image(systemName: "person.3.fill").foregroundStyle(.white)
            }
            .frame(width: 44, height: 44)
            .background(Color.black.opacity(0.35))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .frame(maxHeight: 44)
        }
        .padding(.bottom, 24)
        .sheet(isPresented: $showManagePanel) { managePanel }
        .sheet(isPresented: $showViewerList) { viewerListSheet }
        .sheetStyleCompat()
    }

    private var commentsBar: some View {
        VStack(spacing: 8) {
            ScrollViewReader { proxy in
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
                        .contextMenu {
                            Button("Mute user") { Task { try? await supa.muteUser(hostId: stream.host_id, targetUserId: c.user_id); banners.show(Banner(title: "User muted", style: .success)) } }
                            if moderatorIds.contains(c.user_id) {
                                Button("Remove moderator") { Task { try? await supa.removeLiveModerator(hostId: stream.host_id, moderatorUserId: c.user_id); await refreshModerators(); banners.show(Banner(title: "Moderator removed", style: .success)) } }
                            } else {
                                Button("Make moderator") { Task { try? await supa.addLiveModerator(hostId: stream.host_id, moderatorUserId: c.user_id); await refreshModerators(); banners.show(Banner(title: "Added moderator", style: .success)) } }
                            }
                            Button("Block user", role: .destructive) { Task { try? await supa.blockUser(targetUserId: c.user_id); banners.show(Banner(title: "User blocked", style: .success)) } }
                        }
                        .id(c.id)
                    }
                    Color.clear.frame(height: 1)
                        .id("bottom")
                        .onAppear { stickToBottom = true }
                        .onDisappear { /* user likely scrolled up */ stickToBottom = false }
                }
            }
            .gesture(DragGesture().onChanged { _ in stickToBottom = false })
            .onChange(of: comments.count) { _ in
                if stickToBottom { withAnimation { proxy.scrollTo("bottom", anchor: .bottom) } }
            }
            }
            .frame(height: 140)
            if !stickToBottom {
                Button(action: { withAnimation { stickToBottom = true } }) {
                    Label("Jump to latest", systemImage: "arrow.down.circle.fill")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(8)
        .background(Color.black.opacity(0.25))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var viewerListSheet: some View {
        NavigationStack {
            List(viewerProfiles, id: \.user_id) { p in
                HStack(spacing: 12) {
                    if let img = p.image, let url = URL(string: img) {
                        AsyncImage(url: url) { i in i.resizable().scaledToFill() } placeholder: { Color.white.opacity(0.2) }
                            .frame(width: 36, height: 36)
                            .clipShape(Circle())
                    } else { Circle().fill(Color.white.opacity(0.2)).frame(width: 36, height: 36) }
                    VStack(alignment: .leading) {
                        Text("@\(p.username)").font(.subheadline.weight(.semibold))
                        if let name = p.name, !name.isEmpty { Text(name).font(.caption).foregroundStyle(.secondary) }
                        if moderatorIds.contains(p.user_id) { Text("Moderator").font(.caption2.weight(.bold)).foregroundStyle(.green) }
                    }
                    Spacer()
                    Menu {
                        if moderatorIds.contains(p.user_id) {
                            Button("Remove moderator") { Task { try? await supa.removeLiveModerator(hostId: stream.host_id, moderatorUserId: p.user_id); await refreshModerators(); banners.show(Banner(title: "Moderator removed", style: .success)) } }
                        } else {
                            Button("Make moderator") { Task { try? await supa.addLiveModerator(hostId: stream.host_id, moderatorUserId: p.user_id); await refreshModerators(); banners.show(Banner(title: "Added moderator", style: .success)) } }
                        }
                        Button("Mute user") { Task { try? await supa.muteUser(hostId: stream.host_id, targetUserId: p.user_id); banners.show(Banner(title: "User muted", style: .success)) } }
                        Button("Block user", role: .destructive) { Task { try? await supa.blockUser(targetUserId: p.user_id) ; banners.show(Banner(title: "User blocked", style: .success)) } }
                    } label: {
                        Image(systemName: "ellipsis.circle").font(.title3)
                    }
                }
            }
            .navigationTitle("Viewers")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { showViewerList = false } } }
            .task {
                await loadViewerProfiles()
                viewerListTimer?.invalidate()
                viewerListTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true, block: { _ in
                    Task { await loadViewerProfiles() }
                })
            }
            .onDisappear { viewerListTimer?.invalidate(); viewerListTimer = nil }
        }
    }

    private func loadViewerProfiles() async {
        // Aggregate viewers across cohost streams when in multi-host/shared room
        var ids: [String] = [stream.id]
        if !cohostStreamIds.isEmpty { ids.append(contentsOf: cohostStreamIds) }
        var all: [SupabaseManager.DBProfile] = []
        for sid in ids {
            // Prefer joined fetch (may bypass stricter RLS on direct profiles reads)
            if let list = try? await supa.fetchLiveViewerProfiles(streamId: sid) {
                all.append(contentsOf: list)
            } else if let list = try? await supa.fetchLiveViewers(streamId: sid) {
                all.append(contentsOf: list)
            }
        }
        // De-dup by user_id and sort by username
        var seen: Set<String> = []
        var unique: [SupabaseManager.DBProfile] = []
        for p in all {
            if !seen.contains(p.user_id) { seen.insert(p.user_id); unique.append(p) }
        }
        unique.sort { ($0.username) < ($1.username) }
        await MainActor.run { viewerProfiles = unique }
    }

    private func refreshModerators() async {
        if let mods = try? await supa.fetchLiveModerators(hostId: stream.host_id) {
            await MainActor.run {
                moderatorProfiles = mods
                moderatorIds = Set(mods.map { $0.user_id })
            }
        }
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
            // Configure audio session for low-latency voice/video to avoid AVAudioEngine errors (-3010)
            let session = AVAudioSession.sharedInstance()
            try? session.setCategory(.playAndRecord, mode: .videoChat, options: [.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP, .mixWithOthers])
            try? session.setPreferredSampleRate(48000)
            try? session.setPreferredIOBufferDuration(0.005)
            try? session.setActive(true, options: .notifyOthersOnDeactivation)
            // Mark live in DB
            _ = try await supa.updateLiveSession(id: stream.id, updates: ["status": "live", "started_at": iso])
            // Connect to LiveKit and publish camera+mic
            try await publisher.connectAndPublish(url: SupabaseConfig.livekitURL, token: token)
            // Listen for data messages like {"type":"tap"} from viewers
            publisher.onData = { typeOrJson in
                if typeOrJson == "tap" {
                    spawnRemoteHearts(); tapBatch += 1
                } else if let data = typeOrJson.data(using: .utf8),
                          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                          (obj["type"] as? String) == "tap" {
                    spawnRemoteHearts(); tapBatch += 1
                    if let t = obj["t"] as? Int { totalTaps = t }
                }
            }
            // Start periodic flush: host updates taps total in DB
            tapFlushTimer?.invalidate()
            tapFlushTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true, block: { _ in
                let count = tapBatch
                if count <= 0 { return }
                tapBatch = 0
                Task { await supa.incrementLiveTaps(streamId: stream.id, inc: count) }
            })
            await MainActor.run { isLive = true }
            // Load battle state (if any) and start tally polling
            var activeBattle: SupabaseManager.DBBattleSession? = nil
            do { activeBattle = try await supa.fetchActiveBattleForStream(streamId: stream.id) } catch { activeBattle = nil }
            if let battle = activeBattle {
                await MainActor.run {
                    battleActive = true
                    battleId = battle.id
                    battleStartedAt = battle.started_at
                    battleEndsAt = battle.ends_at
                    battleCountdownText = computeCountdown()
                }
                if let parts = try? await supa.fetchBattleParticipants(battleId: battle.id) {
                    await MainActor.run { battleParticipants = parts }
                }
                battleTimer?.invalidate()
                battleTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true, block: { _ in
                    Task {
                        let startedAt = await MainActor.run { battleStartedAt }
                        let ids = await MainActor.run { battleParticipants.map { $0.user_id } }
                        guard let s = startedAt, !ids.isEmpty else { return }
                        if let t = try? await supa.fetchBattleTalliesSince(startedAtIso: s, userIds: ids) {
                            await MainActor.run { battleTallies = t }
                        }
                    }
                })
                battleCountdownTimer?.invalidate()
                battleCountdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true, block: { _ in
                    Task { await MainActor.run { battleCountdownText = computeCountdown() } }
                })
            }
        } catch {
            await MainActor.run { errorText = (error as NSError).localizedDescription }
        }
    }

    private func startHostPolling() async {
        commentsTimer?.invalidate()
        // Preload cohost ids once
        Task { if let ids = try? await supa.fetchCohostStreamIds(streamId: stream.id) { _ = await MainActor.run { cohostStreamIds = ids } } }
        commentsTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { _ in
            Task {
                if let row = try? await supa.fetchLiveStreamById(stream.id) {
                    let prev = await MainActor.run { totalTaps }
                    await MainActor.run { viewers = row.viewer_count ?? 0; totalTaps = row.taps ?? totalTaps }
                    let now = await MainActor.run { totalTaps }
                    let delta = max(0, now - prev)
                    if delta > 0 { await MainActor.run { for _ in 0..<min(6, delta) { spawnRemoteHearts() } } }
                }
                // Refresh comments alongside Realtime to ensure host sees existing thread
                let ids = await MainActor.run { cohostStreamIds.isEmpty ? [stream.id] : cohostStreamIds }
                if let list = try? await supa.fetchLiveCommentsMulti(streamIds: ids) {
                    await MainActor.run { comments = list }
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

    private func preloadHostProfile() async {
        if hostProfile == nil, let p = try? await supa.fetchProfileByUserId(stream.host_id) {
            await MainActor.run { hostProfile = p }
        }
    }

    private func subscribeToTaps() async {
        await supa.subscribeToLiveTaps(streamId: stream.id) { taps in
            let prev = totalTaps
            totalTaps = taps
            let delta = max(0, taps - prev)
            if delta > 0 { for _ in 0..<min(6, delta) { spawnRemoteHearts() } }
        }
    }

    private func spawnRemoteHearts() {
        let size = UIScreen.main.bounds.size
        var h = HeartParticle(position: CGPoint(x: size.width - 24, y: size.height - 120), opacity: 0.9, scale: 1.0)
        tapHearts.append(h)
        withAnimation(.easeOut(duration: 1.2)) {
            h.position.y -= 140
            h.position.x -= CGFloat(Int.random(in: 0...40))
            h.opacity = 0.0
            h.scale = 1.2
            if let idx = tapHearts.firstIndex(where: { $0.id == h.id }) { tapHearts[idx] = h }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) { tapHearts.removeAll { $0.id == h.id } }
    }

    private var matchBar: some View {
        let team1 = battleParticipants.filter { ($0.team ?? 1) == 1 }.map { $0.user_id }
        let team2 = battleParticipants.filter { ($0.team ?? 2) == 2 }.map { $0.user_id }
        let s1 = team1.reduce(0) { $0 + (battleTallies[$1] ?? 0) }
        let s2 = team2.reduce(0) { $0 + (battleTallies[$1] ?? 0) }
        let total = max(s1 + s2, 1)
        let c1 = Color(red: 0.94, green: 0.27, blue: 0.27)
        let c2 = Color(red: 0.23, green: 0.51, blue: 0.96)
        return VStack(spacing: 6) {
            ZStack {
                GeometryReader { geo in
                    HStack(spacing: 0) {
                        c1.frame(width: geo.size.width * CGFloat(Double(s1) / Double(total)))
                        c2.frame(width: geo.size.width * CGFloat(Double(s2) / Double(total)))
                    }
                }
                .frame(height: 12)
                .clipShape(Capsule())
                HStack {
                    Text("\(s1)").font(.caption.bold()).foregroundStyle(.white)
                    Spacer()
                    Text("\(s2)").font(.caption.bold()).foregroundStyle(.white)
                }
                .padding(.horizontal, 8)
            }
            .background(Color.black.opacity(0.25))
            .clipShape(Capsule())
            // Time progress (below scores)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.25)).frame(height: 6)
                Capsule().fill(Color.white).frame(height: 6)
                    .scaleEffect(x: CGFloat(timeProgress()), y: 1.0, anchor: .leading)
            }
            .overlay(alignment: .trailing) { Text(battleCountdownText).font(.caption2.bold()).foregroundStyle(.white.opacity(0.9)) }
            HStack(spacing: 12) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(team1, id: \.self) { uid in
                            Text(username(for: uid))
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(c1.opacity(0.5))
                                .clipShape(Capsule())
                        }
                    }
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(team2, id: \.self) { uid in
                            Text(username(for: uid))
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(c2.opacity(0.5))
                                .clipShape(Capsule())
                        }
                    }
                }
            }
        }
    }

    private func isoToDate(_ s: String?) -> Date? {
        guard let s else { return nil }
        return ISO8601DateFormatter().date(from: s)
    }
    private func computeCountdown() -> String {
        guard let end = isoToDate(battleEndsAt) else { return "" }
        let now = Date()
        let remain = max(0, end.timeIntervalSince1970 - now.timeIntervalSince1970)
        let m = Int(remain) / 60
        let sec = Int(remain) % 60
        return String(format: "%d:%02d", m, sec)
    }
    private func timeProgress() -> Double {
        guard let start = isoToDate(battleStartedAt), let end = isoToDate(battleEndsAt) else { return 0 }
        let now = Date()
        let total = max(end.timeIntervalSince1970 - start.timeIntervalSince1970, 1)
        let elapsed = min(max(0, now.timeIntervalSince1970 - start.timeIntervalSince1970), total)
        return Double(elapsed) / Double(total)
    }

    private var managePanel: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                // Pending guest requests
                Text("Guest Requests").font(.headline)
                if pendingInvites.isEmpty {
                    Text("No pending requests").font(.subheadline).foregroundStyle(.secondary)
                } else {
                    ForEach(Array(pendingInvites.enumerated()), id: \.offset) { idx, inv in
                        HStack {
                            Text(inv["username"] as? String ?? String((inv["invitee_id"] as? String ?? "").prefix(6)))
                            Spacer()
                            Button("Accept") {
                                if let id = inv["id"] as? String { Task { _ = await supa.acceptGuestInvite(inviteId: id); await loadInvites() } }
                            }
                        }
                    }
                }
                Divider()
                // Invite by username
                Text("Invite Guest").font(.headline)
                VStack(alignment: .leading) {
                    TextField("Search @username, name, or email", text: $inviteQuery)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: inviteQuery, perform: { new in Task { await searchInvite(new) } })
                    if !inviteSuggestions.isEmpty {
                        List(inviteSuggestions, id: \.user_id) { u in
                            HStack {
                                Text(u.username).font(.subheadline)
                                Spacer()
                                Button("Invite") {
                                    Task {
                                        let ok = await supa.inviteGuestByUsername(streamId: stream.id, username: u.username)
                                        if ok {
                                            await loadInvites()
                                            await MainActor.run { inviteQuery = ""; inviteSuggestions = [] }
                                        }
                                    }
                                }
                            }
                        }.listStyle(.plain).frame(maxHeight: 200)
                    }
                }
                Divider()
                // Moderators management
                Text("Moderators").font(.headline)
                if moderatorProfiles.isEmpty {
                    Text("No moderators yet").font(.subheadline).foregroundStyle(.secondary)
                } else {
                    ForEach(moderatorProfiles, id: \.user_id) { p in
                        HStack {
                            Text("@\(p.username)")
                            Spacer()
                            Button("Remove") {
                                Task { try? await supa.removeLiveModerator(hostId: stream.host_id, moderatorUserId: p.user_id); await refreshModerators(); banners.show(Banner(title: "Moderator removed", style: .success)) }
                            }
                        }
                    }
                }
                VStack(alignment: .leading) {
                    TextField("Add moderator by @username", text: $modQuery)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: modQuery, perform: { new in Task { await searchMod(new) } })
                    if !modSuggestions.isEmpty {
                        List(modSuggestions, id: \.user_id) { u in
                            HStack {
                                Text(u.username).font(.subheadline)
                                Spacer()
                                Button("Add") {
                                    Task { try? await supa.addLiveModerator(hostId: stream.host_id, moderatorUserId: u.user_id); await refreshModerators(); await MainActor.run { modQuery = ""; modSuggestions = [] }; banners.show(Banner(title: "Added moderator", style: .success)) }
                                }
                            }
                        }.listStyle(.plain).frame(maxHeight: 200)
                    }
                }
                Divider()
                // Battle controls
                Text("Match (Battle)").font(.headline)
                if !battleActive {
                    Button("Start Match") { Task { await startBattle() } }
                        .buttonStyle(.borderedProminent)
                } else {
                    // Add participant to team
                    VStack(alignment: .leading, spacing: 8) {
                        Picker("Team", selection: $addTeam) {
                            Text("Team 1").tag(1)
                            Text("Team 2").tag(2)
                        }
                        .pickerStyle(.segmented)
                        TextField("Search user to add", text: $addQuery)
                            .textInputAutocapitalization(.never)
                            .disableAutocorrection(true)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: addQuery, perform: { new in Task { await searchAdd(new) } })
                        if !addSuggestions.isEmpty {
                            List(addSuggestions, id: \.user_id) { u in
                                HStack {
                                    Text(u.username)
                                    Spacer()
                                    Button("Add") { Task { await addUserToBattle(u) } }
                                }
                            }.listStyle(.plain).frame(maxHeight: 200)
                        }
                    }
                    // Simple participant list with tallies
                    ForEach(Array(battleParticipants.enumerated()), id: \.offset) { idx, p in
                        HStack {
                            Text(username(for: p.user_id))
                            Spacer()
                            Picker("", selection: Binding(get: { p.team ?? 1 }, set: { new in
                                Task { try? await supa.updateBattleParticipantTeam(participantId: p.id, team: new); await refreshBattleParticipants() }
                            })) {
                                Text("1").tag(1)
                                Text("2").tag(2)
                            }
                            .pickerStyle(.segmented)
                            Button("Remove") { Task { try? await supa.deleteBattleParticipant(participantId: p.id); await refreshBattleParticipants() } }
                                .buttonStyle(.bordered)
                        }
                    }
                    Button("End Match", role: .destructive) { Task { await endBattle() } }
                        .buttonStyle(.bordered)
                }
                Spacer()
            }
            .padding()
            .navigationTitle("Manage Live")
            .task { await loadInvites(); await refreshModerators() }
            .onAppear {
                invitesTimer?.invalidate() // prefer realtime; keep as optional fallback disabled
                invitesTimer = nil
                Task { await supa.subscribeToInvitesForLive(streamId: stream.id) { Task { await loadInvites() } } }
            }
            .onDisappear {
                invitesTimer?.invalidate(); invitesTimer = nil
                Task { await supa.unsubscribeInvitesForLive(streamId: stream.id) }
            }
        }
    }

    private func loadInvites() async {
        let base = await supa.listPendingGuestInvites(streamId: stream.id)
        var enriched: [[String: Any]] = []
        for var inv in base {
            if inv["username"] == nil, let uid = inv["invitee_id"] as? String {
                let prof: SupabaseManager.DBProfile? = (try? await supa.fetchProfileByUserId(uid)) ?? nil
                inv["username"] = prof?.username ?? String(uid.prefix(6))
            }
            enriched.append(inv)
        }
        await MainActor.run { pendingInvites = enriched }
    }
    private func startBattle() async {
        do {
            if let row = try await supa.createBattle(streamId: stream.id) {
                await MainActor.run {
                    battleActive = true
                    battleId = row.id
                    battleStartedAt = ISO8601DateFormatter().string(from: Date())
                }
            }
        } catch {}
    }
    private func endBattle() async { if let bid = battleId { try? await supa.endBattle(battleId: bid); await MainActor.run { battleActive = false } } }
    private func refreshBattleParticipants() async { if let bid = battleId, let parts = try? await supa.fetchBattleParticipants(battleId: bid) { await MainActor.run { battleParticipants = parts } } }
    private func searchInvite(_ text: String) async {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { await MainActor.run { inviteSuggestions = [] }; return }
        if let r = try? await supa.searchProfilesByKeyword(t) { await MainActor.run { inviteSuggestions = r } }
    }
    private func searchAdd(_ text: String) async {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { await MainActor.run { addSuggestions = [] }; return }
        if let r = try? await supa.searchProfilesByKeyword(t) { await MainActor.run { addSuggestions = r } }
    }
    private func searchMod(_ text: String) async {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { await MainActor.run { modSuggestions = [] }; return }
        if let r = try? await supa.searchProfilesByKeyword(t) { await MainActor.run { modSuggestions = r } }
    }
    private func addUserToBattle(_ user: SupabaseManager.DBProfile) async {
        guard let bid = battleId else { return }
        let active = try? await supa.fetchActiveLiveForUser(userId: user.user_id)
        let sid = active?.id
        try? await supa.addBattleParticipant(battleId: bid, userId: user.user_id, streamId: sid, team: addTeam)
        await refreshBattleParticipants()
        await MainActor.run { addQuery = ""; addSuggestions = [] }
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
    LiveBroadcastView(stream: .init(id: UUID().uuidString, host_id: UUID().uuidString, title: "My Stream", description: "", status: "scheduled", viewer_count: 0, taps: 0, started_at: nil, ended_at: nil, token: "tok"))
}
