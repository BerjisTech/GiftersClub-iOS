import SwiftUI
#if canImport(LiveKit)
import LiveKit
#endif
import Supabase
import UIKit

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
    @State private var hostFollowersOverride: Int? = nil
    @State private var giftsTimer: Timer? = nil
    @State private var lastGiftAt: String? = nil
    @State private var giftCombos: [String: (count: Int, index: Int)] = [:]
    @State private var cohostStreamIds: [String] = []
    @State private var cohostCommentsTimer: Timer? = nil // legacy fallback; kept for safety
    @State private var commentSubscribedIds: Set<String> = []
    // Matches (battles)
    @State private var battleActive: Bool = false
    @State private var battleId: String? = nil
    @State private var battleStartedAt: String? = nil
    @State private var battleTallies: [String: Int] = [:] // recipient user_id -> tokens
    @State private var battleParticipants: [SupabaseManager.DBBattleParticipant] = []
    @State private var battleTimer: Timer? = nil
    @State private var battleEndsAt: String? = nil
    @State private var battleCountdownTimer: Timer? = nil
    @State private var battleCountdownText: String = ""
    // Guest invite
    @State private var canRequestGuest: Bool = false
    @State private var hasRequestedGuest: Bool = false
    @State private var invitePollTimer: Timer? = nil
    @State private var showGiftsSheet: Bool = false
    @State private var showGiftAnimation: Bool = false
    @State private var giftAnimationText: String = ""
    @State private var giftAnimationLottie: String? = nil
    @State private var giftCache: [String: SupabaseManager.DBGift] = [:]
    @State private var hostFiltered: [String] = []
    @State private var mutedByHost: Bool = false
    @State private var stickToBottom: Bool = true
    @State private var amModerator: Bool = false
    @State private var showModeration: Bool = false
    @State private var modNewWord: String = ""
    // Likes (taps)
    @State private var tapHearts: [HeartParticle] = []
    @State private var localTapCount: Int = 0
    @State private var showTapHud: Bool = false
    @State private var likeCommentSent: Bool = false
    @State private var totalTaps: Int = 0
    @State private var lastTapsForRemote: Int = 0
    @State private var chaff: [HeartParticle] = []
    // Access gating for subscriber-only / paid lives
    @State private var hasAccessLive: Bool = false
    @State private var liveAccessType: String? = nil
    @State private var livePrice: Int? = nil

    var body: some View {
        ZStack {
            if ended {
                endedView
            } else if hasAccessLive && !viewer.remoteVideoTracks.isEmpty {
                ZStack {
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
            } else if hasAccessLive, let track = viewer.remoteVideoTrack {
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
            // Paywall overlay for locked lives (subscribe or unlock)
            if !ended && !hasAccessLive {
                Rectangle().fill(Color.black.opacity(0.75)).ignoresSafeArea()
                VStack(spacing: 12) {
                    Image(systemName: "lock.fill").font(.largeTitle).foregroundStyle(.white)
                    Text((liveAccessType == "subscription") ? "Subscribe to watch" : "Unlock to watch").foregroundStyle(.white)
                    if liveAccessType == "paid" {
                        Button(action: { Task { await unlockLive() } }) {
                            Text(livePrice != nil ? "Unlock for \(livePrice!) tokens" : "Unlock")
                                .padding(.horizontal, 16).padding(.vertical, 10)
                        }.buttonStyle(.borderedProminent)
                    } else if liveAccessType == "subscription" {
                        Button(action: { Task { await subscribeToHost() } }) {
                            Text("Subscribe").padding(.horizontal, 16).padding(.vertical, 10)
                        }.buttonStyle(.borderedProminent)
                    }
                }
                .padding()
                .zIndex(5)
            }

            if !ended {
                VStack(spacing: 6) {
                    topBar
                    if battleActive { matchBar }
                    Spacer()
                    bottomBar
                }
                .padding()
                .zIndex(2)
                // Gift animation overlay
                .overlay(alignment: .center) {
                    Group {
                        if showGiftAnimation {
                            if let anim = giftAnimationLottie {
                                LottieView(name: anim, loopMode: .playOnce) { showGiftAnimation = false }
                                    .frame(width: 220, height: 220)
                            } else {
                                Text(giftAnimationText)
                                    .font(.largeTitle.bold())
                                    .foregroundStyle(.white)
                                    .padding(12)
                                    .background(Color.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
                                    .transition(.scale.combined(with: .opacity))
                            }
                        } else { Color.clear }
                    }
                    .allowsHitTesting(false)
                    .accessibilityIdentifier("GiftAnimationOverlay")
                }
            }
            // Floating hearts overlay
            ForEach(tapHearts) { h in
                Image(systemName: "heart.fill")
                    .foregroundStyle(.red)
                    .position(h.position)
                    .opacity(h.opacity)
                    .scaleEffect(h.scale)
                    .allowsHitTesting(false)
            }
            // Chaff/confetti overlay (falls downward then fades)
            ForEach(chaff) { p in
                Text("•")
                    .foregroundStyle(.white)
                    .position(p.position)
                    .opacity(p.opacity)
                    .scaleEffect(p.scale)
                    .allowsHitTesting(false)
            }
        }
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0).onEnded { value in
            spawnTap(at: value.location)
        })
        .background(Color.black)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .task {
            // Moderation: block check
            if (try? await supa.isUserBlockedBy(userId: live.host_id)) == true {
                await MainActor.run { errorText = "You cannot join this live"; ended = true }
                return
            }
            // Check access for subscription/paid
            if let meta = try? await supa.fetchLiveStreamById(live.id) {
                await MainActor.run { liveAccessType = meta.access_type; livePrice = meta.price }
                var allowed = false
                if let t = meta.access_type {
                    if t == "free" { allowed = true }
                    else if (supa.user?.id.uuidString == live.host_id) { allowed = true }
                    else if t == "subscription" { allowed = (try? await supa.hasSubscription(to: live.host_id)) ?? false }
                    else if t == "paid" { allowed = (try? await supa.hasLiveAccess(streamId: live.id)) ?? false }
                } else {
                    // Unknown access type: treat as locked
                    allowed = false
                }
                await MainActor.run { hasAccessLive = allowed }
            } else {
                // Unable to fetch metadata; remain locked by default
                await MainActor.run { hasAccessLive = false }
            }
            // Prefetch moderation settings
            hostFiltered = (try? await supa.fetchFilteredWords(for: live.host_id)) ?? []
            mutedByHost = (try? await supa.isUserMutedBy(hostId: live.host_id)) ?? false
            amModerator = await supa.isModeratorOfHost(hostId: live.host_id)
            if hasAccessLive { await join() }
            await supa.recordViewerJoin(streamId: live.id)
            await loadComments(); await startStatusPolling()
            // Cohost comments: switch to realtime across stream ids (fallback timer disabled by default)
            if let ids = try? await supa.fetchCohostStreamIds(streamId: live.id) {
                _ = await MainActor.run { cohostStreamIds = ids }
                for id in ids where !commentSubscribedIds.contains(id) {
                    await supa.subscribeToLiveComments(streamId: id) { c in
                        if !comments.contains(where: { $0.id == c.id }) {
                            comments.append(c)
                        }
                        // Preload profile
                        Task { if profilesCache[c.user_id] == nil, let p = try? await supa.fetchProfileByUserId(c.user_id) { await MainActor.run { profilesCache[c.user_id] = p } } }
                        // Trigger remote hearts when someone likes the live (content-only, username comes from profile)
                        if c.content.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "liked this live" {
                            spawnRemoteHearts()
                        }
                    }
                    _ = await MainActor.run { commentSubscribedIds.insert(id) }
                }
                // Initial load of existing comments across cohost streams
                if let list = try? await supa.fetchLiveCommentsMulti(streamIds: ids) {
                    await MainActor.run { comments = list; ensureSystemJoinMessages() }
                    for c in list {
                        if profilesCache[c.user_id] == nil, let p = try? await supa.fetchProfileByUserId(c.user_id) {
                            await MainActor.run { profilesCache[c.user_id] = p }
                        }
                    }
                }
            }
            if let row = try? await supa.fetchLiveStreamById(live.id) {
                _ = await MainActor.run { viewerCount = row.viewer_count ?? 0; totalTaps = row.taps ?? 0; lastTapsForRemote = totalTaps }
            }
            if hostProfile == nil, let p = try? await supa.fetchProfileByUserId(live.host_id) {
                await MainActor.run { hostProfile = p }
            }
            // Guest request availability (non-host and not in battle)
            await MainActor.run { canRequestGuest = (supa.user?.id.uuidString != live.host_id) }
            // Load battle state (if any) and start tally polling
            var activeBattle: SupabaseManager.DBBattleSession? = nil
            do { activeBattle = try await supa.fetchActiveBattleForStream(streamId: live.id) } catch { activeBattle = nil }
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
            // Gifts realtime: append combo notifications into comments
            await supa.subscribeToGiftSent(streamId: live.id) { row in
                Task {
                    // Resolve gifter username
                    let uname = await MainActor.run { profilesCache[row.gifter]?.username } ?? String(row.gifter.prefix(6))
                    // Resolve gift name from cache or DB
                    var gname = "gift"
                    if let cached = await MainActor.run(body: { giftCache[row.gift] }) {
                        gname = (cached.name ?? "gift").lowercased()
                    } else if let g = try? await supa.fetchGiftById(row.gift) {
                        await MainActor.run { giftCache[row.gift] = g }
                        gname = (g.name ?? "gift").lowercased()
                    }
                    await MainActor.run {
                        var newItems: [SupabaseManager.DBLiveStreamComment] = []
                        let key = row.gifter + "_" + row.gift
                        if var combo = giftCombos[key] {
                            combo.count += 1
                            giftCombos[key] = combo
                            let idx = combo.index
                            if idx < comments.count {
                                comments[idx] = SupabaseManager.DBLiveStreamComment(id: comments[idx].id, live_stream_id: comments[idx].live_stream_id, user_id: comments[idx].user_id, content: "\(uname) sent a \(combo.count)x \(gname) combo", created_at: comments[idx].created_at)
                            }
                            giftAnimationText = "\(uname) x\(combo.count) \(gname)!"
                            giftAnimationLottie = lottieForGiftName(gname)
                        } else {
                            let c = SupabaseManager.DBLiveStreamComment(id: "gift-\(UUID().uuidString)", live_stream_id: live.id, user_id: row.gifter, content: "\(uname) sent a \(gname)", created_at: row.created_at)
                            newItems.append(c)
                            giftCombos[key] = (count: 1, index: comments.count + newItems.count - 1)
                            giftAnimationText = "\(uname) sent \(gname)!"
                            giftAnimationLottie = lottieForGiftName(gname)
                        }
                        comments.append(contentsOf: newItems)
                        withAnimation(.spring()) { showGiftAnimation = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
                            withAnimation(.easeOut) { showGiftAnimation = false; giftAnimationLottie = nil }
                        }
                    }
                }
            }
            // Invite status via realtime
            await supa.subscribeToMyInvite(streamId: live.id) { status in
                if status == "accepted" {
                    Task {
                        do {
                            let token = try await supa.fetchLiveGuestToken(streamId: live.id)
                            try await viewer.upgradeToGuest(url: SupabaseConfig.livekitURL, token: token)
                            await MainActor.run { hasRequestedGuest = false; canRequestGuest = false }
                        } catch {
                            await MainActor.run { errorText = (error as NSError).localizedDescription }
                        }
                    }
                }
            }
        }
        .alert("Error", isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorText ?? "") }
        .onAppear { NotificationCenter.default.post(name: .hideBottomBar, object: nil) }
        .onDisappear {
            NotificationCenter.default.post(name: .showBottomBar, object: nil)
            commentsTimer?.invalidate(); commentsTimer = nil
            cohostCommentsTimer?.invalidate(); cohostCommentsTimer = nil
            statusTimer?.invalidate(); statusTimer = nil
            giftsTimer?.invalidate(); giftsTimer = nil
            battleTimer?.invalidate(); battleTimer = nil
            battleCountdownTimer?.invalidate(); battleCountdownTimer = nil
            invitePollTimer?.invalidate(); invitePollTimer = nil
            Task {
                for id in commentSubscribedIds { await supa.unsubscribeLiveComments(streamId: id) }
                await supa.unsubscribeMyInvite(streamId: live.id)
                await supa.recordViewerLeave(streamId: live.id)
            }
        }
        .onChange(of: ended, perform: { isEnded in if isEnded { NotificationCenter.default.post(name: .showBottomBar, object: nil) } })
        .sheet(isPresented: $showModeration) { moderationSheet }
    }

    private var matchBar: some View {
        let team1 = battleParticipants.filter { ($0.team ?? 1) == 1 }.map { $0.user_id }
        let team2 = battleParticipants.filter { ($0.team ?? 2) == 2 }.map { $0.user_id }
        let s1 = team1.reduce(0) { $0 + (battleTallies[$1] ?? 0) }
        let s2 = team2.reduce(0) { $0 + (battleTallies[$1] ?? 0) }
        let total = max(s1 + s2, 1)
        let c1 = Color(red: 0.94, green: 0.27, blue: 0.27) // #ef4444
        let c2 = Color(red: 0.23, green: 0.51, blue: 0.96) // #3b82f6
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
            // Avatars/labels per team
            HStack(spacing: 12) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(team1, id: \.self) { uid in
                            Text(shortUsername(for: uid))
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
                            Text(shortUsername(for: uid))
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(c2.opacity(0.5))
                                .clipShape(Capsule())
                        }
                    }
                }
            }
        }
        .onChange(of: comments.last?.id) { _ in
            if let last = comments.last, last.content.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "liked this live" {
                spawnRemoteHearts()
            }
        }
        .task {
            await supa.subscribeToLiveTaps(streamId: live.id) { taps in
                let prev = totalTaps
                totalTaps = taps
                let delta = max(0, taps - prev)
                if delta > 0 { for _ in 0..<min(6, delta) { spawnRemoteHearts() } }
            }
        }
    }

    private func shortUsername(for userId: String) -> String {
        if let p = profilesCache[userId] { return p.username.isEmpty ? (p.name ?? String(userId.prefix(6))) : p.username }
        Task { if let p = try? await supa.fetchProfileByUserId(userId) { await MainActor.run { profilesCache[userId] = p } } }
        return String(userId.prefix(6))
    }

    // HUD under host details showing progress towards 300 taps (legacy; not shown anymore)
    private var tapHud: some View {
        HStack(spacing: 8) {
            Image(systemName: "heart.fill").foregroundStyle(.red)
            ProgressView(value: min(Double(localTapCount)/300.0, 1.0))
                .tint(.red)
                .frame(width: 120)
            Text("\(min(localTapCount, 300))/300").font(.caption2).foregroundStyle(.white)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.black.opacity(0.35))
        .clipShape(Capsule())
    }

    private struct HeartParticle: Identifiable {
        let id = UUID()
        var position: CGPoint
        var opacity: Double
        var scale: CGFloat
    }

    private func spawnTap(at pt: CGPoint) {
        var h = HeartParticle(position: pt, opacity: 1.0, scale: 1.0)
        tapHearts.append(h)
        withAnimation(.easeOut(duration: 1.2)) {
            h.position.y -= 120
            h.opacity = 0.0
            h.scale = 1.4
            if let idx = tapHearts.firstIndex(where: { $0.id == h.id }) { tapHearts[idx] = h }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) {
            tapHearts.removeAll { $0.id == h.id }
        }
        localTapCount += 1
        // Increment DB, then fetch authoritative taps and emit LiveKit "tap" including total
        Task {
            await supa.incrementLiveTaps(streamId: live.id, inc: 1)
            if let row = try? await supa.fetchLiveStreamById(live.id), let taps = row.taps {
                await MainActor.run { totalTaps = taps; viewer.sendTap(total: taps) }
            } else {
                await MainActor.run { totalTaps += 1; viewer.sendTap(total: totalTaps) }
            }
        }
        if !likeCommentSent {
            likeCommentSent = true
            Task { _ = try? await supa.sendLiveComment(streamId: live.id, content: "liked this live") }
        }
        if localTapCount == 300 { spawnChaffAtCounter() }
    }

    private func spawnRemoteHearts() {
        let size = UIScreen.main.bounds.size
        for i in 0..<6 {
            let base = CGPoint(x: size.width - 24, y: size.height - 120)
            var h = HeartParticle(position: base, opacity: 0.9, scale: 1.0)
            let delay = 0.05 * Double(i)
            tapHearts.append(h)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                withAnimation(.easeOut(duration: 1.2)) {
                    h.position.y -= 140
                    h.position.x -= CGFloat(Int.random(in: 0...40))
                    h.opacity = 0.0
                    h.scale = 1.2
                    if let idx = tapHearts.firstIndex(where: { $0.id == h.id }) { tapHearts[idx] = h }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) { tapHearts.removeAll { $0.id == h.id } }
            }
        }
    }

    private func spawnChaffAtCounter() {
        let size = UIScreen.main.bounds.size
        for i in 0..<24 {
            var p = HeartParticle(position: CGPoint(x: size.width - CGFloat(Int.random(in: 80...140)), y: 60), opacity: 1.0, scale: 1.0)
            chaff.append(p)
            let delay = 0.02 * Double(i)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                withAnimation(.easeOut(duration: 1.2)) {
                    p.position.y += CGFloat(Int.random(in: 120...240))
                    p.position.x += CGFloat(Int.random(in: -30...30))
                    p.opacity = 0.0
                    p.scale = 1.0
                    if let idx = chaff.firstIndex(where: { $0.id == p.id }) { chaff[idx] = p }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) { chaff.removeAll { $0.id == p.id } }
            }
        }
    }
    private func requestToJoin() async {
        let ok = await supa.requestGuestInvite(streamId: live.id)
        await MainActor.run { hasRequestedGuest = ok }
    }

    private func lottieForGiftName(_ name: String) -> String? {
        let map: [String: String] = [
            "rose": "rose",
            "heart": "heart",
            "diamond": "diamond",
            "star": "star",
            "rocket": "rocket",
            "cake": "cake",
            "coffee": "coffee",
            "crown": "crown",
            "kiss": "kiss",
            "fire": "fire",
            "balloon": "balloon",
            "flower": "flower",
            "teddy": "teddy",
            "car": "car",
            "yacht": "yacht",
            "castle": "castle"
        ]
        return map[name]
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

    private var videoGrid: some View {
        struct Tile: Identifiable { let id: String; let track: LiveKit.VideoTrack; let userId: String? }
        var tiles: [Tile] = []
        if let local = viewer.localVideoTrack { tiles.append(Tile(id: "local", track: local, userId: supa.user?.id.uuidString)) }
        for rv in viewer.remoteVideos { tiles.append(Tile(id: rv.id, track: rv.track, userId: rv.identity)) }
        return Group {
            if tiles.count == 1 {
                LKVideoView(track: tiles.first!.track)
                    .scaleEffect(x: -1, y: 1)
                    .ignoresSafeArea()
            } else {
                let cols: [GridItem] = Array(repeating: GridItem(.flexible(), spacing: 8), count: tiles.count <= 2 ? 1 : (tiles.count <= 4 ? 2 : 3))
                ScrollView { // allow more than 6 tracks to scroll
                    LazyVGrid(columns: cols, spacing: 8) {
                        ForEach(tiles) { t in
                            ZStack(alignment: .bottomLeading) {
                                LKVideoView(track: t.track)
                                    .scaleEffect(x: -1, y: 1)
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
        VStack(alignment: .leading, spacing: 8) {
            // Streamer details box (avatar + username/followers + follow + viewer count)
            HStack(spacing: 8) {
                if let img = hostProfile?.image, let url = URL(string: img) {
                    AsyncImage(url: url) { i in i.resizable().scaledToFill() } placeholder: { Color.white.opacity(0.2) }
                        .frame(width: 40, height: 40)
                        .clipShape(Circle())
                } else { Circle().fill(Color.white.opacity(0.25)).frame(width: 40, height: 40) }
                VStack(alignment: .leading, spacing: 2) {
                    Text(hostProfile?.username ?? "").font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                    if let f = hostFollowersOverride ?? hostProfile?.followers_count {
                        Text("\(f) followers").font(.caption2).foregroundStyle(.white.opacity(0.9))
                    }
                }
                Spacer(minLength: 8)
                if let me = supa.user?.id.uuidString, me != live.host_id {
                    Button(action: { Task { await toggleFollow() } }) {
                        Image(systemName: (isFollowing ?? false) ? "person.crop.circle.badge.minus" : "person.crop.circle.badge.plus")
                            .foregroundStyle(.white)
                            .frame(width: 28, height: 28)
                    }
                }
                HStack(spacing: 6) {
                    Image(systemName: "eye.fill").foregroundStyle(.white)
                    Text("\(viewerCount)").foregroundStyle(.white).font(.footnote)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(.black.opacity(0.35))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            // Taps details row (heart + progress(>=30) + fraction + total taps)
            HStack(spacing: 8) {
                Image(systemName: "heart.fill").foregroundStyle(.red)
                if localTapCount >= 30 && localTapCount < 300 {
                    ProgressView(value: min(Double(localTapCount)/300.0, 1.0))
                        .tint(.red)
                        .frame(width: 80)
                    Text("\(min(localTapCount, 300))/300").font(.caption2).foregroundStyle(.white)
                }
                Text(shortCount(totalTaps)).foregroundStyle(.white).font(.footnote)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.35))
            .clipShape(Capsule())
        }
    }

    private func shortCount(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fm", Double(n)/1_000_000.0) }
        if n >= 1_000 { return String(format: "%.1fk", Double(n)/1_000.0) }
        return String(n)
    }

    private var bottomBar: some View {
        VStack(spacing: 8) {
            // Comments list (simple overlay: avatar, username + gifter badge, comment)
            ScrollViewReader { proxy in
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
                        .contextMenu {
                            if amModerator {
                                Button("Mute user") { Task { try? await supa.muteUser(hostId: live.host_id, targetUserId: c.user_id) } }
                                Button("Block user", role: .destructive) { Task { try? await supa.blockUserForHost(hostId: live.host_id, targetUserId: c.user_id) } }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .id(c.id)
                    }
                }
                Color.clear.frame(height: 1)
                    .id("bottom")
                    .onAppear { stickToBottom = true }
                    .onDisappear { stickToBottom = false }
            }
            .gesture(DragGesture().onChanged { _ in stickToBottom = false })
            .onChange(of: comments.count) { _ in if stickToBottom { withAnimation { proxy.scrollTo("bottom", anchor: .bottom) } } }
            }
            .frame(height: 180)
            HStack(spacing: 8) {
                TextField(hasAccessLive ? "Say something…" : "Unlock to comment", text: $newComment)
                    .textFieldStyle(.roundedBorder)
                    .disabled(!hasAccessLive)
                Button(action: { Task { await sendComment() } }) {
                    Text("Send")
                }
                .disabled(!hasAccessLive || newComment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || mutedByHost)
                if hasAccessLive {
                    Button(action: { showGiftsSheet = true }) {
                        Image(systemName: "gift.fill")
                            .foregroundStyle(.white)
                            .frame(minWidth: 44, minHeight: 36)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.bordered)
                    if canRequestGuest && !hasRequestedGuest && !battleActive {
                        Button(action: { Task { await requestToJoin() } }) {
                            Image(systemName: "person.2.fill")
                                .foregroundStyle(.white)
                                .frame(minWidth: 44, minHeight: 36)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.bordered)
                        .accessibilityLabel("Request to join")
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .padding(8)
        .background(Color.black.opacity(0.25))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .zIndex(3)
        .sheet(isPresented: $showGiftsSheet) { GiftPickerSheet(recipientId: live.host_id) }
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
            // Receive LiveKit data messages (e.g., tap events from other clients)
            viewer.onData = { typeOrJson in
                if typeOrJson == "tap" {
                    spawnRemoteHearts(); totalTaps += 1
                } else if let data = typeOrJson.data(using: .utf8),
                          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                          (obj["type"] as? String) == "tap" {
                    spawnRemoteHearts()
                    if let t = obj["t"] as? Int { totalTaps = t } else { totalTaps += 1 }
                }
            }
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
                    await MainActor.run { comments = list; ensureSystemJoinMessages() }
                }
            }
        }
    }

    private func ensureSystemJoinMessages() {
        // Insert two local-only banner comments: title and code-of-conduct
        let titleId = "sys-title"
        if !comments.contains(where: { $0.id == titleId }) {
            let c = SupabaseManager.DBLiveStreamComment(id: titleId, live_stream_id: live.id, user_id: live.host_id, content: "🔴 \(live.title)", created_at: nil)
            comments.insert(c, at: 0)
        }
        let rulesId = "sys-rules"
        if !comments.contains(where: { $0.id == rulesId }) {
            let msg = "Be respectful. Avoid sexual content. Follow the rules."
            let c = SupabaseManager.DBLiveStreamComment(id: rulesId, live_stream_id: live.id, user_id: live.host_id, content: msg, created_at: nil)
            comments.insert(c, at: min(1, comments.count))
        }
    }

    private func unlockLive() async {
        guard let price = livePrice else { return }
        do {
            try await supa.purchaseLiveAccess(streamId: live.id, tokens: price)
            await MainActor.run { hasAccessLive = true }
            await join()
        } catch {
            await MainActor.run { errorText = (error as NSError).localizedDescription }
        }
    }

    private func subscribeToHost() async {
        do {
            try await supa.subscribeToCreator(creatorId: live.host_id, tokens: 0, duration: .monthly)
            await MainActor.run { hasAccessLive = true }
            await join()
        } catch {
            await MainActor.run { errorText = (error as NSError).localizedDescription }
        }
    }

    private func userColor(_ id: String) -> Color {
        var hash: UInt64 = 5381
        for u in id.utf8 { hash = ((hash << 5) &+ hash) &+ UInt64(u) }
        let hue = Double(hash % 360) / 360.0
        return Color(hue: hue, saturation: 0.75, brightness: 0.95)
    }

    private func sendComment() async {
        guard hasAccessLive else { return }
        let text = newComment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        // Client-side moderation: drop if muted or contains filtered keywords
        if mutedByHost { return }
        let lower = text.lowercased()
        let blocked = hostFiltered.first { w in !w.isEmpty && lower.contains(w.lowercased()) }
        if blocked != nil { return }
        if let _ = try? await supa.sendLiveComment(streamId: live.id, content: text) {
            await MainActor.run { newComment = "" }
        }
    }

    private var moderationSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("Filtered Words for Host").font(.headline)
                HStack {
                    TextField("Add filtered word", text: $modNewWord)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .textFieldStyle(.roundedBorder)
                    Button("Add") {
                        let w = modNewWord.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !w.isEmpty else { return }
                        Task {
                            do { try await supa.addHostFilteredWord(hostId: live.host_id, word: w); hostFiltered = (try? await supa.fetchFilteredWords(for: live.host_id)) ?? hostFiltered; modNewWord = "" }
                            catch { }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
                if hostFiltered.isEmpty {
                    Text("No filtered words.").foregroundStyle(.secondary)
                } else {
                    List(hostFiltered, id: \.self) { w in
                        HStack {
                            Text(w)
                            Spacer()
                            Button("Remove") { Task { try? await supa.removeHostFilteredWord(hostId: live.host_id, word: w); hostFiltered = (try? await supa.fetchFilteredWords(for: live.host_id)) ?? hostFiltered } }
                                .buttonStyle(.bordered)
                        }
                    }
                    .listStyle(.plain)
                }
                Spacer()
            }
            .padding()
            .navigationTitle("Moderation")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { showModeration = false } } }
        }
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
                let base = hostFollowersOverride ?? hostProfile?.followers_count ?? 0
                let optimistic = max(0, base - 1)
                await MainActor.run {
                    isFollowing = false
                    hostFollowersOverride = optimistic
                }
                // Refresh with guard
                if let fresh = try? await supa.fetchProfileByUserId(live.host_id) {
                    await MainActor.run {
                        // Only apply if not regressing beyond optimistic; then clear override
                        if (fresh.followers_count ?? optimistic) <= optimistic {
                            hostProfile = fresh
                            hostFollowersOverride = nil
                        }
                    }
                }
            } else {
                _ = try await supa.client
                    .from("follows").upsert([["followed_id": live.host_id, "follower_id": me]], onConflict: "followed_id,follower_id")
                    .select("id")
                    .execute()
                let base = hostFollowersOverride ?? hostProfile?.followers_count ?? 0
                let optimistic = base + 1
                await MainActor.run {
                    isFollowing = true
                    hostFollowersOverride = optimistic
                }
                if let fresh = try? await supa.fetchProfileByUserId(live.host_id) {
                    await MainActor.run {
                        if (fresh.followers_count ?? optimistic) >= optimistic {
                            hostProfile = fresh
                            hostFollowersOverride = nil
                        }
                    }
                }
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
                            NavigationLink(destination: LiveEntryDestination(live: s)) {
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
                    await MainActor.run { ended = true }
                        let isEmpty = await MainActor.run { suggestions.isEmpty }
                        if isEmpty {
                        if let lives = try? await supa.fetchFeedLiveStreams(limit: 4, query: nil) {
                            await MainActor.run { suggestions = lives }
                        }
                    }
                    } else {
                        await MainActor.run { viewerCount = row.viewer_count ?? 0 }
                        // Keep bottom chrome hidden via onAppear; avoid spamming notifications here
                    }
                }
            }
        }
    }
}
