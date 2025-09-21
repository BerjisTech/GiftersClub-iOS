import Foundation
import UIKit
import Combine
import Supabase
import Realtime
import AuthenticationServices

final class SupabaseManager: ObservableObject {
    static let shared = SupabaseManager()

    let client: SupabaseClient

    @Published var user: Auth.User?
    @Published var isLoading: Bool = true
    @Published var needsUsernameSetup: Bool = false

    private init() {
        client = SupabaseClient(
            supabaseURL: SupabaseConfig.url,
            supabaseKey: SupabaseConfig.anonKey
        )
        Task { await initializeAuth() }
    }

    @MainActor
    private func setUser(_ session: Session?) {
        self.user = session?.user
        self.isLoading = false
    }

    func initializeAuth() async {
        // Load current session (if present)
        let session = try? await client.auth.session
        await MainActor.run { self.setUser(session) }
        // If already signed in on app start, ensure profile and publish E2EE key
        if let u = session?.user {
            await self.ensureProfile(user: u)
            if let pub = try? E2EEKeyManager.shared.publicKeyBase64() {
                await self.upsertMyPublicKey(pub)
            }
        }

        // Listen to auth state changes (Supabase Swift async sequence)
        Task.detached { [weak self] in
            guard let self else { return }
            for await state in self.client.auth.authStateChanges {
                await MainActor.run {
                    self.setUser(state.session)
                }
                if state.event == .signedIn, let user = state.session?.user {
                    await self.ensureProfile(user: user)
                    // Publish my E2EE public key (idempotent upsert)
                    if let pub = try? E2EEKeyManager.shared.publicKeyBase64() {
                        await self.upsertMyPublicKey(pub)
                    }
                    await self.evaluateUsernameRequirement()
                    await MainActor.run {
                        if self.needsUsernameSetup == false {
                            NotificationCenter.default.post(name: Notification.Name("signedIn"), object: nil)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Google OAuth (web flow)
    @MainActor
    func signInWithGoogle() async {
        do {
            _ = try await client.auth.signInWithOAuth(
                provider: .google,
                redirectTo: SupabaseConfig.redirectURL
            )
        } catch {
            #if DEBUG
            print("Google OAuth start failed: \(error)")
            #endif
        }
    }

    func signOut() async {
        do { try await client.auth.signOut() } catch {
            #if DEBUG
            print("Sign out failed: \(error)")
            #endif
        }
    }

    func handleOpenURL(_ url: URL) {
        // Hand off OAuth callback to Supabase
        client.auth.handle(url)
    }

    // MARK: - Sign in with Apple (Native)
    /// Completes Supabase sign-in using a native Apple ID token + nonce
    /// - Parameters:
    ///   - idToken: JWT returned by ASAuthorizationAppleIDCredential.identityToken
    ///   - nonce: The original nonce you hashed and sent in the Apple request
    @MainActor
    func signInWithApple(idToken: String, nonce: String) async throws {
        _ = try await client.auth.signInWithIdToken(
            credentials: .init(
                provider: .apple,
                idToken: idToken,
                nonce: nonce
            )
        )
    }

    // Create a minimal profile row if missing
    func ensureProfile(user: Auth.User) async {
        do {
            let existing: PostgrestResponse<[DBProfile]> = try await client
                .from("profiles")
                .select()
                .eq("user_id", value: user.id.uuidString)
                .limit(1)
                .execute()
            if existing.value.isEmpty {
                let email = user.email ?? ""
                struct NewProfile: Encodable { let user_id: String; let email: String }
                _ = try await client
                    .from("profiles")
                    .insert([NewProfile(user_id: user.id.uuidString, email: email)])
                    .execute()
            }
        } catch {
            #if DEBUG
            print("ensureProfile error: \(error)")
            #endif
        }
    }

    // MARK: - Account Deletion
    /// Create an account deletion request for the current user.
    /// Matches the web app behavior by inserting a row into `deletion_requests`.
    func requestAccountDeletion() async throws {
        guard let me = user?.id.uuidString else { throw NSError(domain: "DeleteAccount", code: -1, userInfo: [NSLocalizedDescriptionKey: "Not signed in"]) }
        struct NewDeletion: Encodable { let user_id: String }
        _ = try await client
            .from("deletion_requests")
            .insert([NewDeletion(user_id: me)])
            .execute()
    }

    // Evaluate if we must force a username prompt (relay emails or missing username)
    @MainActor
    func evaluateUsernameRequirement() async {
        guard let me = user?.id.uuidString else { needsUsernameSetup = false; return }
        do {
            let prof = try await fetchProfile(username: nil, userId: me)
            let email = user?.email ?? prof?.email ?? ""
            let isRelay = email.lowercased().contains("privaterelay.appleid.com")
            let missingUsername = (prof?.username ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            needsUsernameSetup = isRelay || missingUsername
        } catch {
            needsUsernameSetup = true
        }
    }

    // Validate and set username
    func setUsername(_ newUsername: String) async throws {
        guard let me = user?.id.uuidString else { throw URLError(.userAuthenticationRequired) }
        let uname = newUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        guard uname.range(of: "^[A-Za-z0-9_]{3,20}$", options: .regularExpression) != nil else {
            throw NSError(domain: "Username", code: 1, userInfo: [NSLocalizedDescriptionKey: "Username must be 3–20 letters, numbers, or _"])
        }
        // Check availability
        let exists: PostgrestResponse<[DBProfile]> = try await client
            .from("profiles")
            .select("user_id")
            .eq("username", value: uname)
            .limit(1)
            .execute()
        if !exists.value.isEmpty { throw NSError(domain: "Username", code: 2, userInfo: [NSLocalizedDescriptionKey: "Username is taken"]) }
        // Update
        struct Patch: Encodable { let username: String }
        _ = try await client
            .from("profiles")
            .update(Patch(username: uname))
            .eq("user_id", value: me)
            .execute()
        await MainActor.run { self.needsUsernameSetup = false }
    }

    // MARK: - Data Models (Decodable)
    struct DBProfile: Decodable {
        let user_id: String
        let username: String
        let name: String?
        let bio: String?
        let image: String?
        let email: String?
        let followers_count: Int?
        let following_count: Int?
        let token_balance: Int?
        let tokens_sent: Int?
        let tokens_received: Int?
        let gifts_sent: Int?
        let gifts_received: Int?
        // Gifter badge fields
        let gifter_level: Int?
        let gifter_level_name: String?
    }

    struct DBPost: Decodable { let id: String; let user_id: String }
    struct DBPostMedia: Decodable { let post_id: String; let url: String; let order: Int? }
    struct DBWishlist: Decodable { let id: String; let title: String? }
    // Full wishlist row with optional embedded profile and contributions (tokens only)
    struct DBWishlistFull: Decodable, Identifiable {
        let id: String
        let user_id: String
        let link: String?
        let name: String?
        let description: String?
        let image: String?
        let tokens: Int?
        let is_fulfilled: Bool?
        let created_at: String?
        let profile: DBProfile?
        let wishlist_contributions: [DBWishlistContributionToken]?
    }
    struct DBWishlistContributionToken: Decodable { let tokens: Int }
    struct DBWishlistContribution: Decodable {
        let id: String
        let user_id: String
        let contributor_id: String
        let wishlist_id: String
        let tokens: Int
        let created_at: String?
        let updated_at: String?
    }
    struct DBGift: Decodable { let id: String; let name: String?; let tokens: Int?; let image: String? }
    struct DBSticker: Decodable, Identifiable { let id: String; let name: String; let image_url: String; let is_active: Bool?; let sort_index: Int? }
    struct DBTopGifter: Decodable {
        let user_id: String
        let username: String
        let image: String?
        let gifts_sent: Int?
        let tokens_sent: Int?
        let gifter_level: Int?
        let gifter_level_name: String?
        let largest_gift_name: String?
        let largest_gift_id: String?
        let largest_gift_color: String?
        let largest_gift_tokens: Int?
        let badge: String?
    }
    struct DBAttachment: Decodable { let url: String?; let type: String? }
    struct DBMessage: Decodable { let id: String; let sender_id: String; let receiver_id: String; let content: String; let created_at: String; let attachments: [DBAttachment]? }
    struct DBNotification: Decodable { let id: String; let user_id: String; let type: String; let reference_id: String?; let message: String; let is_read: Bool; let created_at: String; let updated_at: String?; let sender_id: String? }
    struct DBConversationDetails: Decodable { let user_a: String; let user_b: String; let last_message_at: String; let partner_id: String; let partner_name: String?; let partner_image: String?; let unread_count: Int; let last_message_id: String?; let last_message_content: String?; let last_message_attachments: [DBAttachment]? }
    struct DBBlocked: Decodable { let blocked_user_id: String }
    struct DBFilteredWord: Decodable { let word: String }
    struct CountRow: Decodable { let id: String }

    // MARK: - Feed RPC DTOs
    struct FeedRPCProfile: Decodable { let id: String?; let user_id: String?; let username: String?; let name: String?; let image: String? }
    struct FeedRPCMedia: Decodable { let id: String?; let media_type: String?; let url: String?; let order: Int?; let created_at: String? }
    struct FeedRPCRow: Decodable {
        let id: String
        let user_id: String
        let content: String?
        let access_type: String?
        let price: Int?
        let required_plan_id: String?
        let created_at: String?
        let like_count: Int?
        let comment_count: Int?
        let share_count: Int?
        let profile: FeedRPCProfile?
        let media: [FeedRPCMedia]?
    }

    func fetchFeed(limit: Int = 10, offset: Int = 0) async throws -> [FeedRPCRow] {
        let me = user?.id.uuidString
        struct Params: Encodable { let _user_id: String?; let _limit: Int; let _offset: Int }
        let params = Params(_user_id: me, _limit: limit, _offset: offset)
        let res: PostgrestResponse<[FeedRPCRow]> = try await client
            .rpc("get_feed_posts", params: params)
            .execute()
        return res.value
    }

    // MARK: - Access gating (subscriptions and pay-per-post)
    // Lightweight in-memory caches for the current session
    private var accessCachePosts = Set<String>()
    private var subscriptionCacheCreators = Set<String>()
    private let accessQueue = DispatchQueue(label: "access-cache-queue")

    /// Prefetch access/ subscription state for visible items to avoid N+1 checks.
    func prefetchAccess(posts: [String], creators: [String]) async {
        let me = user?.id.uuidString
        guard let me, (!posts.isEmpty || !creators.isEmpty) else { return }
        let missingPosts: [String] = accessQueue.sync { posts.filter { !accessCachePosts.contains($0) } }
        let missingCreators: [String] = accessQueue.sync { creators.filter { !subscriptionCacheCreators.contains($0) } }
        do {
            if !missingPosts.isEmpty {
                struct Row: Decodable { let post_id: String }
                let res: PostgrestResponse<[Row]> = try await client
                    .from("post_access").select("post_id")
                    .eq("user_id", value: me)
                    .in("post_id", values: missingPosts)
                    .execute()
                let ids = Set(res.value.map { $0.post_id })
                accessQueue.sync { accessCachePosts.formUnion(ids) }
            }
        } catch { }
        do {
            if !missingCreators.isEmpty {
                let now = ISO8601DateFormatter().string(from: Date())
                struct Row: Decodable { let creator_id: String }
                let res: PostgrestResponse<[Row]> = try await client
                    .from("subscriptions").select("creator_id")
                    .eq("subscriber_id", value: me)
                    .or("end_date.is.null,end_date.gt.\(now)")
                    .in("creator_id", values: missingCreators)
                    .execute()
                let ids = Set(res.value.map { $0.creator_id })
                accessQueue.sync { subscriptionCacheCreators.formUnion(ids) }
            }
        } catch { }
    }
    func hasSubscription(to creatorId: String) async throws -> Bool {
        guard let me = user?.id.uuidString else { return false }
        // Cache check
        if accessQueue.sync(execute: { subscriptionCacheCreators.contains(creatorId) }) { return true }
        // Active subscription: end_date is null or in the future
        let now = ISO8601DateFormatter().string(from: Date())
        struct Row: Decodable { let id: String }
        let res: PostgrestResponse<[Row]> = try await client
            .from("subscriptions")
            .select("id")
            .eq("creator_id", value: creatorId)
            .eq("subscriber_id", value: me)
            .or("end_date.is.null,end_date.gt.\(now)")
            .limit(1)
            .execute()
        let ok = !res.value.isEmpty
        if ok { _ = accessQueue.sync { subscriptionCacheCreators.insert(creatorId); return 0 } }
        return ok
    }

    func hasPostAccess(postId: String) async throws -> Bool {
        guard let me = user?.id.uuidString else { return false }
        if accessQueue.sync(execute: { accessCachePosts.contains(postId) }) { return true }
        struct Row: Decodable { let id: String }
        let res: PostgrestResponse<[Row]> = try await client
            .from("post_access")
            .select("id")
            .eq("post_id", value: postId)
            .eq("user_id", value: me)
            .limit(1)
            .execute()
        let ok = !res.value.isEmpty
        if ok { _ = accessQueue.sync { accessCachePosts.insert(postId); return 0 } }
        return ok
    }

    enum SubscriptionDuration: String { case one_time, monthly, annual }
    func subscribeToCreator(creatorId: String, tokens: Int, duration: SubscriptionDuration) async throws {
        guard let me = user?.id.uuidString else { throw URLError(.userAuthenticationRequired) }
        let functionURL = SupabaseConfig.url.appendingPathComponent("functions/v1/subscribe-creator")
        var req = URLRequest(url: functionURL)
        req.httpMethod = "POST"
        req.addValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        if let token = try? await client.auth.session.accessToken {
            req.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        let txRef = "sub_\(me)_\(creatorId)_\(Int(Date().timeIntervalSince1970))"
        let payload: [String: Any] = [
            "creatorId": creatorId,
            "subscriberId": me,
            "tokens": tokens,
            "durationType": duration.rawValue,
            "txRef": txRef
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let msg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
            throw NSError(domain: "Subscribe", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: msg ?? "Subscription failed"])
        }
        // Optimistically mark creator as subscribed in cache
        _ = accessQueue.sync { subscriptionCacheCreators.insert(creatorId); return 0 }
    }

    func purchasePostAccess(postId: String, tokens: Int) async throws {
        guard let me = user?.id.uuidString else { throw URLError(.userAuthenticationRequired) }
        let functionURL = SupabaseConfig.url.appendingPathComponent("functions/v1/purchase-post-access")
        var req = URLRequest(url: functionURL)
        req.httpMethod = "POST"
        req.addValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        if let token = try? await client.auth.session.accessToken {
            req.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        let txRef = "post_\(me)_\(postId)_\(Int(Date().timeIntervalSince1970))"
        let payload: [String: Any] = [
            "postId": postId,
            "userId": me,
            "tokens": tokens,
            "txRef": txRef
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let msg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
            throw NSError(domain: "Purchase", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: msg ?? "Purchase failed"])
        }
        // Optimistically mark post as accessible
        _ = accessQueue.sync { accessCachePosts.insert(postId); return 0 }
    }

    // MARK: - Subscription Plans (CRUD)
    struct DBSubscriptionPlan: Decodable, Identifiable {
        let id: String
        let creator_id: String
        let name: String
        let description: String?
        let tokens: Int
        let duration_type: String
        let created_at: String?
        let updated_at: String?
    }
    struct UpdateSubscriptionPlanInput: Encodable {
        var name: String?
        var description: String?
        var tokens: Int?
        var duration_type: String?
    }
    func fetchSubscriptionPlans(creatorId: String) async throws -> [DBSubscriptionPlan] {
        let res: PostgrestResponse<[DBSubscriptionPlan]> = try await client
            .from("subscription_plans")
            .select("*")
            .eq("creator_id", value: creatorId)
            .order("created_at", ascending: true)
            .execute()
        return res.value
    }
    func createSubscriptionPlan(name: String, description: String?, tokens: Int, durationType: String) async throws -> DBSubscriptionPlan? {
        guard let me = user?.id.uuidString else { return nil }
        struct Insert: Encodable { let creator_id: String; let name: String; let description: String?; let tokens: Int; let duration_type: String }
        let payload = Insert(creator_id: me, name: name, description: description, tokens: tokens, duration_type: durationType)
        let res: PostgrestResponse<[DBSubscriptionPlan]> = try await client
            .from("subscription_plans")
            .insert(payload)
            .select("*")
            .execute()
        return res.value.first
    }
    func updateSubscriptionPlan(id: String, updates: UpdateSubscriptionPlanInput) async throws -> DBSubscriptionPlan? {
        let res: PostgrestResponse<[DBSubscriptionPlan]> = try await client
            .from("subscription_plans")
            .update(updates)
            .eq("id", value: id)
            .select("*")
            .execute()
        return res.value.first
    }
    func deleteSubscriptionPlan(id: String) async throws {
        _ = try await client
            .from("subscription_plans")
            .delete()
            .eq("id", value: id)
            .execute()
    }

    // MARK: - Explore Search RPC
    struct ExplorePost: Decodable, Identifiable, Hashable {
        let id: String
        let user_id: String
        let content: String?
        let access_type: String?
        let price: Int?
        let required_plan_id: String?
        let is_explicit: Bool?
        let media: [FeedRPCMedia]?
        let profile: FeedRPCProfile?
        let view_count: Int?
        static func == (lhs: ExplorePost, rhs: ExplorePost) -> Bool { lhs.id == rhs.id }
        func hash(into hasher: inout Hasher) { hasher.combine(id) }
    }
    struct ExploreUser: Decodable, Identifiable, Hashable {
        let user_id: String
        let username: String
        let name: String?
        let image: String?
        var id: String { user_id }
    }
    struct ExploreResult: Decodable {
        let top: [ExplorePost]
        let videos: [ExplorePost]
        let photos: [ExplorePost]
        let users: [ExploreUser]
        let live: [JSONValue]?
    }
    /// Minimal JSON value wrapper to decode unknown live object arrays without failing
    struct JSONValue: Decodable {}

    func searchExplore(query: String) async throws -> ExploreResult {
        struct RPCResult: Decodable { let top: [ExplorePost]; let videos: [ExplorePost]; let photos: [ExplorePost]; let users: [ExploreUser]; let live: [JSONValue]? }
        let res: PostgrestResponse<RPCResult> = try await client
            .rpc("search_explore", params: ["q": query])
            .execute()
        // Filter explicit posts client-side as a safety net
        func filter(_ arr: [ExplorePost]) -> [ExplorePost] { arr.filter { ($0.is_explicit ?? false) == false } }
        return ExploreResult(top: filter(res.value.top), videos: filter(res.value.videos), photos: filter(res.value.photos), users: res.value.users, live: res.value.live)
    }

    // MARK: - Search Suggestions
    func fetchRecentSearches(limit: Int = 8) async throws -> [String] {
        guard let me = user?.id.uuidString else { return [] }
        struct Row: Decodable { let query: String }
        let res: PostgrestResponse<[Row]> = try await client
            .from("search_queries")
            .select("query")
            .eq("user_id", value: me)
            .order("created_at", ascending: false)
            .limit(limit)
            .execute()
        // dedupe while preserving order
        var seen = Set<String>(); var out: [String] = []
        for r in res.value { if !seen.contains(r.query) { out.append(r.query); seen.insert(r.query) } }
        return out
    }

    func fetchTrendingSearches(limit: Int = 8, windowDays: Int = 30) async throws -> [String] {
        // Prefer server-side grouping via RPC if available
        struct TrendingRow: Decodable { let query: String; let total_count: Int? }
        struct TrendingParams: Encodable { let timeframe: String; let _limit: Int }
        do {
            let res: PostgrestResponse<[TrendingRow]> = try await client
                .rpc("get_trending_searches", params: TrendingParams(timeframe: "\(windowDays)d", _limit: limit))
                .execute()
            let qs = res.value.map { $0.query }
            if !qs.isEmpty { return qs }
        } catch {
            // Fall back to client-side aggregation below
        }

        // Fallback: Trending = most frequent queries within a recent time window (default 30 days), case-insensitive
        struct Row: Decodable { let query: String }
        let since = Calendar.current.date(byAdding: .day, value: -windowDays, to: Date()) ?? Date(timeIntervalSinceNow: -30*24*3600)
        let iso = ISO8601DateFormatter().string(from: since)
        let res: PostgrestResponse<[Row]> = try await client
            .from("search_queries")
            .select("query,created_at")
            .gte("created_at", value: iso)
            .limit(5000)
            .execute()
        var freq: [String: Int] = [:]
        for r in res.value {
            let key = r.query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !key.isEmpty else { continue }
            freq[key, default: 0] += 1
        }
        let sorted = freq.sorted { lhs, rhs in
            if lhs.value == rhs.value { return lhs.key < rhs.key }
            return lhs.value > rhs.value
        }.map { $0.key }
        return Array(sorted.prefix(limit))
    }

    // MARK: - Stickers (remote gallery)
    func fetchStickers() async throws -> [DBSticker] {
        let res: PostgrestResponse<[DBSticker]> = try await client
            .from("stickers")
            .select("*")
            .eq("is_active", value: true)
            .order("sort_index", ascending: false)
            .order("created_at", ascending: false)
            .execute()
        return res.value
    }

    // MARK: - Profile Posts (minimal for grid + access)
    struct UserPostMinimal: Decodable, Identifiable {
        let id: String
        let user_id: String
        let access_type: String?
        let price: Int?
        let media: [FeedRPCMedia]?
        let view_count: Int?
    }

    func fetchUserPostsMinimal(userId: String, limit: Int = 20) async throws -> [UserPostMinimal] {
        let res: PostgrestResponse<[UserPostMinimal]> = try await client
            .from("posts")
            .select("id,user_id,access_type,price,view_count, media:post_media(url,media_type,order)")
            .eq("user_id", value: userId)
            .order("created_at", ascending: false)
            .limit(limit)
            .execute()
        return res.value
    }

    func recordSearchQuery(_ q: String) async {
        guard let me = user?.id.uuidString else { return }
        struct Row: Encodable { let user_id: String; let query: String }
        _ = try? await client
            .from("search_queries")
            .insert([Row(user_id: me, query: q)])
            .execute()
    }

    // MARK: - Live Streaming
    struct DBLiveStream: Decodable, Identifiable {
        let id: String
        let host_id: String
        let title: String
        let description: String?
        let status: String
        let viewer_count: Int?
        let started_at: String?
        let ended_at: String?
        // Edge function may attach an ephemeral LiveKit token for host/viewer
        let token: String?
    }

    // MARK: - Tags / Hashtags
    struct DBTag: Decodable, Identifiable { let id: String; let name: String }
    /// Suggest hashtags by prefix from `tags` table. No admin RPCs in the user app.
    /// Also enriches with local counts from `post_tags` for the returned tag ids.
    func suggestTags(prefix: String, limit: Int = 8) async -> [(name: String, count: Int)] {
        let q = prefix.lowercased()
        struct TagRow: Decodable { let id: String; let name: String }
        do {
            let tagRes: PostgrestResponse<[TagRow]> = try await client
                .from("tags")
                .select("id,name")
                .ilike("name", pattern: "\(q)%")
                .order("name")
                .limit(limit)
                .execute()
            let tags = tagRes.value
            guard !tags.isEmpty else { return [] }
            // Fetch post_tags rows for returned tag ids and count locally
            struct MapRow: Decodable { let tag_id: String }
            let ids = tags.map { $0.id }
            let mapRes: PostgrestResponse<[MapRow]> = try await client
                .from("post_tags")
                .select("tag_id")
                .in("tag_id", values: ids)
                .limit(5000)
                .execute()
            var freq: [String: Int] = [:]
            for r in mapRes.value { freq[r.tag_id, default: 0] += 1 }
            return tags.map { ($0.name, freq[$0.id] ?? 0) }
        } catch {
            return []
        }
    }
    /// Create a scheduled live stream row directly (status = scheduled)
    func createScheduledLiveStream(
        title: String,
        description: String?,
        categoryId: Int?,
        tags: [String]?,
        scheduledAtISO: String,
        accessType: String?,
        price: Int?,
        requiredPlanId: String?
    ) async throws -> DBLiveStream {
        guard let me = user?.id.uuidString else { throw URLError(.userAuthenticationRequired) }
        struct Insert: Encodable {
            let host_id: String
            let title: String
            let description: String?
            let category_id: Int?
            let tags: [String]?
            let status: String
            let started_at: String
            let access_type: String?
            let price: Int?
            let required_plan_id: String?
        }
        let payload = Insert(
            host_id: me,
            title: title,
            description: description,
            category_id: categoryId,
            tags: tags,
            status: "scheduled",
            started_at: scheduledAtISO,
            access_type: accessType,
            price: price,
            required_plan_id: requiredPlanId
        )
        let res: PostgrestResponse<[DBLiveStream]> = try await client
            .from("live_streams")
            .insert([payload])
            .select("id,host_id,title,description,status,viewer_count,started_at,ended_at")
            .execute()
        guard let row = res.value.first else { throw URLError(.badServerResponse) }
        return row
    }

    // MARK: - System Categories
    struct DBSystemCategory: Decodable, Identifiable { let id: Int; let name: String; let description: String? }
    func fetchSystemCategories() async throws -> [DBSystemCategory] {
        let res: PostgrestResponse<[DBSystemCategory]> = try await client
            .from("system_categories")
            .select("id,name,description")
            .order("name", ascending: true)
            .execute()
        return res.value
    }

    struct DBLiveStreamWithStats: Decodable, Identifiable, Hashable {
        let id: String
        let host_id: String
        let title: String
        let description: String?
        let status: String
        let started_at: String?
        let ended_at: String?
        let viewer_count: Int?
        let comment_count: Int?
        let gift_count: Int?
        let tokens_received: Int?
        let thumbnail_url: String?
        let stream_score: Double?
    }

    func fetchFeedLiveStreams(limit: Int = 10, query: String? = nil) async throws -> [DBLiveStreamWithStats] {
        struct Params: Encodable { let in_viewer_id: String?; let in_limit: Int; let in_query: String? }
        let me = user?.id.uuidString
        let params = Params(in_viewer_id: me, in_limit: limit, in_query: query)
        let res: PostgrestResponse<[DBLiveStreamWithStats]> = try await client
            .rpc("feed_live_streams", params: params)
            .execute()
        #if DEBUG
        print("[RPC] feed_live_streams in_query=\(query ?? "") returned=\(res.value.count)")
        #endif
        return res.value
    }

    struct DBLiveStreamComment: Decodable, Identifiable { let id: String; let live_stream_id: String; let user_id: String; let content: String; let created_at: String? }
    struct DBLiveStreamViewer: Decodable, Identifiable { let id: String; let live_stream_id: String; let viewer_id: String; let joined_at: String? }

    /// Create a live session via Edge Function (returns stream + LiveKit token for host)
    func createLiveSession(title: String, description: String?, categoryId: Int?, tags: [String]?) async throws -> DBLiveStream {
        struct Payload: Encodable { let hostId: String; let title: String; let description: String?; let categoryId: Int?; let tags: [String]? }
        guard let me = user?.id.uuidString else { throw URLError(.userAuthenticationRequired) }
        let functionURL = SupabaseConfig.url.appendingPathComponent("functions/v1/live-session")
        var req = URLRequest(url: functionURL)
        req.httpMethod = "POST"
        req.addValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        if let token = try? await client.auth.session.accessToken { req.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload = Payload(hostId: me, title: title, description: description, categoryId: categoryId, tags: tags)
        req.httpBody = try JSONEncoder().encode(payload)
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let msg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
            throw NSError(domain: "LiveSession", code: (resp as? HTTPURLResponse)?.statusCode ?? -1, userInfo: [NSLocalizedDescriptionKey: msg ?? "Failed to create live session"]) }
        return try JSONDecoder().decode(DBLiveStream.self, from: data)
    }

    // MARK: - Posts View Tracking
    func logPostView(postId: String, viewDuration: Int?) async {
        guard let _ = user?.id.uuidString else { return }
        let functionURL = SupabaseConfig.url.appendingPathComponent("functions/v1/log-post-view")
        var req = URLRequest(url: functionURL)
        req.httpMethod = "POST"
        req.addValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        if let token = try? await client.auth.session.accessToken { req.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        var payload: [String: Any] = ["postId": postId, "platform": "ios"]
        if let d = viewDuration { payload["viewDuration"] = d }
        req.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        _ = try? await URLSession.shared.data(for: req)
    }

    // MARK: - Gift events for live (polling)
    struct DBGiftEvent: Decodable, Identifiable {
        let id: String
        let live_stream_id: String
        let gifter: String
        let recipient: String
        let gift: String
        let tokens_used: Int?
        let created_at: String
        let gift_row: DBGift?
        let gifter_row: DBProfile?
    }
    func fetchGiftEvents(streamId: String, since: String?) async throws -> [DBGiftEvent] {
        var filter = client
            .from("gift_sent")
            .select("id,live_stream_id,gifter,recipient,gift,tokens_used,created_at,gift_row:gifts(*),gifter_row:profiles(*)")
            .eq("live_stream_id", value: streamId)
        if let s = since { filter = filter.gt("created_at", value: s) }
        let res: PostgrestResponse<[DBGiftEvent]> = try await filter
            .order("created_at", ascending: true)
            .execute()
        return res.value
    }

    // Lightweight gift row lookup
    func fetchGiftById(_ id: String) async throws -> DBGift? {
        let res: PostgrestResponse<[DBGift]> = try await client
            .from("gifts")
            .select("id,name,tokens,image")
            .eq("id", value: id)
            .limit(1)
            .execute()
        return res.value.first
    }

    /// Request a viewer token for LiveKit by stream ID via Edge Function.
    func fetchLiveViewerToken(streamId: String) async throws -> String {
        struct Payload: Encodable { let action: String; let streamId: String; let type: String }
        let functionURL = SupabaseConfig.url.appendingPathComponent("functions/v1/live-session")
        var req = URLRequest(url: functionURL)
        req.httpMethod = "POST"
        req.addValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        if let token = try? await client.auth.session.accessToken { req.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload = Payload(action: "token", streamId: streamId, type: "viewer")
        req.httpBody = try JSONEncoder().encode(payload)
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let msg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
            throw NSError(domain: "LiveViewerToken", code: (resp as? HTTPURLResponse)?.statusCode ?? -1, userInfo: [NSLocalizedDescriptionKey: msg ?? "Failed to fetch viewer token"])
        }
        let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        guard let token = json["token"] as? String else {
            throw NSError(domain: "LiveViewerToken", code: -2, userInfo: [NSLocalizedDescriptionKey: "Missing token in response"])
        }
        #if DEBUG
        print("[LiveKit] viewer token fetched length=\(token.count)")
        #endif
        return token
    }

    // MARK: - (Realtime V2 not available in current SDK) — keep polling helpers above

    // MARK: - Multi-host helpers (shared room_id)
    /// Return all cohosted stream ids (same room_id), including the provided id.
    func fetchCohostStreamIds(streamId: String) async throws -> [String] {
        struct Row: Decodable { let id: String; let room_id: String? }
        let s: PostgrestResponse<[Row]> = try await client
            .from("live_streams")
            .select("id,room_id")
            .eq("id", value: streamId)
            .limit(1)
            .execute()
        guard let roomId = s.value.first?.room_id, !roomId.isEmpty else { return [streamId] }
        let sibs: PostgrestResponse<[Row]> = try await client
            .from("live_streams")
            .select("id")
            .eq("room_id", value: roomId)
            .execute()
        var ids = Set([streamId])
        sibs.value.forEach { ids.insert($0.id) }
        return Array(ids)
    }

    /// Fetch comments across multiple stream ids (for cohosted streams sharing room_id)
    func fetchLiveCommentsMulti(streamIds: [String]) async throws -> [DBLiveStreamComment] {
        if streamIds.isEmpty { return [] }
        let res: PostgrestResponse<[DBLiveStreamComment]> = try await client
            .from("live_stream_comments")
            .select("id,live_stream_id,user_id,content,created_at")
            .in("live_stream_id", values: streamIds)
            .order("created_at", ascending: true)
            .execute()
        return res.value
    }

    // MARK: - Matches (battles)
    struct DBBattleSession: Decodable { let id: String; let live_stream_id: String; let started_at: String; let ends_at: String?; let status: String }
    struct DBBattleParticipant: Decodable { let id: String; let battle_id: String; let user_id: String; let team: Int?; let live_stream_id: String }

    /// Active battle for a given stream (if any)
    func fetchActiveBattleForStream(streamId: String) async throws -> DBBattleSession? {
        let res: PostgrestResponse<[DBBattleSession]> = try await client
            .from("battle_sessions")
            .select("id,live_stream_id,started_at,ends_at,status")
            .eq("live_stream_id", value: streamId)
            .eq("status", value: "active")
            .order("started_at", ascending: false)
            .limit(1)
            .execute()
        return res.value.first
    }

    func fetchBattleParticipants(battleId: String) async throws -> [DBBattleParticipant] {
        let res: PostgrestResponse<[DBBattleParticipant]> = try await client
            .from("battle_participants")
            .select("id,battle_id,user_id,team,live_stream_id")
            .eq("battle_id", value: battleId)
            .execute()
        return res.value
    }

    /// Sum tokens_used per recipient since battle start
    func fetchBattleTalliesSince(startedAtIso: String, userIds: [String]) async throws -> [String: Int] {
        if userIds.isEmpty { return [:] }
        struct Row: Decodable { let recipient: String; let tokens_used: Int? }
        let res: PostgrestResponse<[Row]> = try await client
            .from("gift_sent")
            .select("recipient,tokens_used,created_at")
            .in("recipient", values: userIds)
            .gte("created_at", value: startedAtIso)
            .execute()
        var tally: [String: Int] = [:]
        for r in res.value { tally[r.recipient] = (tally[r.recipient] ?? 0) + (r.tokens_used ?? 0) }
        return tally
    }

    // MARK: - Battle mutations (host)
    struct DBBattleSessionRow: Decodable { let id: String }
    func createBattle(streamId: String) async throws -> DBBattleSessionRow? {
        struct Insert: Encodable { let live_stream_id: String; let status: String; let started_at: String }
        let now = ISO8601DateFormatter().string(from: Date())
        let res: PostgrestResponse<[DBBattleSessionRow]> = try await client
            .from("battle_sessions")
            .insert([Insert(live_stream_id: streamId, status: "active", started_at: now)])
            .select("id")
            .execute()
        return res.value.first
    }
    func endBattle(battleId: String) async throws {
        let now = ISO8601DateFormatter().string(from: Date())
        _ = try await client
            .from("battle_sessions")
            .update(["status": "ended", "ends_at": now])
            .eq("id", value: battleId)
            .execute()
    }
    func addBattleParticipant(battleId: String, userId: String, streamId: String?, team: Int?) async throws {
        struct Insert: Encodable { let battle_id: String; let user_id: String; let live_stream_id: String?; let team: Int? }
        _ = try await client
            .from("battle_participants")
            .insert([Insert(battle_id: battleId, user_id: userId, live_stream_id: streamId, team: team)])
            .execute()
    }
    func updateBattleParticipantTeam(participantId: String, team: Int?) async throws {
        struct UpdateTeam: Encodable { let team: Int? }
        _ = try await client
            .from("battle_participants")
            .update(UpdateTeam(team: team))
            .eq("id", value: participantId)
            .execute()
    }
    func deleteBattleParticipant(participantId: String) async throws {
        _ = try await client
            .from("battle_participants")
            .delete()
            .eq("id", value: participantId)
            .execute()
    }

    // MARK: - Guest invites (Edge function 'live-invite')
    func requestGuestInvite(streamId: String) async -> Bool {
        let functionURL = SupabaseConfig.url.appendingPathComponent("functions/v1/live-invite")
        var req = URLRequest(url: functionURL)
        req.httpMethod = "POST"
        req.addValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        if let token = try? await client.auth.session.accessToken { req.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload: [String: Any] = ["action": "request", "streamId": streamId]
        req.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return false }
            return true
        } catch { return false }
    }

    func listPendingGuestInvites(streamId: String) async -> [[String: Any]] {
        let functionURL = SupabaseConfig.url.appendingPathComponent("functions/v1/live-invite")
        var req = URLRequest(url: functionURL)
        req.httpMethod = "POST"
        req.addValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        if let token = try? await client.auth.session.accessToken { req.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload: [String: Any] = ["action": "list", "streamId": streamId]
        req.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return [] }
            let json = (try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]) ?? []
            return json
        } catch { return [] }
    }

    func acceptGuestInvite(inviteId: String) async -> Bool {
        let functionURL = SupabaseConfig.url.appendingPathComponent("functions/v1/live-invite")
        var req = URLRequest(url: functionURL)
        req.httpMethod = "POST"
        req.addValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        if let token = try? await client.auth.session.accessToken { req.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload: [String: Any] = ["action": "accept", "inviteId": inviteId]
        req.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return false }
            return true
        } catch { return false }
    }

    func inviteGuestByUsername(streamId: String, username: String) async -> Bool {
        let functionURL = SupabaseConfig.url.appendingPathComponent("functions/v1/live-invite")
        var req = URLRequest(url: functionURL)
        req.httpMethod = "POST"
        req.addValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        if let token = try? await client.auth.session.accessToken { req.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload: [String: Any] = ["action": "invite", "streamId": streamId, "username": username]
        req.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return false }
            return true
        } catch { return false }
    }

    /// Poll my latest invite status for this stream
    func fetchMyInviteStatus(streamId: String) async -> (id: String, status: String)? {
        guard let me = user?.id.uuidString else { return nil }
        struct Row: Decodable { let id: String; let invitee_id: String; let live_stream_id: String; let status: String; let created_at: String }
        let res: PostgrestResponse<[Row]>? = try? await client
            .from("live_stream_invites")
            .select("id,invitee_id,live_stream_id,status,created_at")
            .eq("live_stream_id", value: streamId)
            .eq("invitee_id", value: me)
            .order("created_at", ascending: false)
            .limit(1)
            .execute()
        if let r = res?.value.first { return (id: r.id, status: r.status) }
        return nil
    }

    /// Guest LiveKit token via function (type: guest)
    func fetchLiveGuestToken(streamId: String) async throws -> String {
        struct Payload: Encodable { let action: String; let streamId: String; let type: String }
        let functionURL = SupabaseConfig.url.appendingPathComponent("functions/v1/live-session")
        var req = URLRequest(url: functionURL)
        req.httpMethod = "POST"
        req.addValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        if let token = try? await client.auth.session.accessToken { req.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload = Payload(action: "token", streamId: streamId, type: "guest")
        req.httpBody = try JSONEncoder().encode(payload)
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let msg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
            throw NSError(domain: "LiveGuestToken", code: (resp as? HTTPURLResponse)?.statusCode ?? -1, userInfo: [NSLocalizedDescriptionKey: msg ?? "Failed to fetch guest token"])
        }
        let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        guard let token = json["token"] as? String else { throw NSError(domain: "LiveGuestToken", code: -2, userInfo: [NSLocalizedDescriptionKey: "Missing token in response"]) }
        return token
    }

    // MARK: - Lightweight DB fetches for live previews
    func fetchLiveStreamById(_ id: String) async throws -> DBLiveStream? {
        struct Row: Decodable { let id: String; let host_id: String; let title: String; let description: String?; let status: String; let viewer_count: Int?; let started_at: String?; let ended_at: String? }
        let res: PostgrestResponse<[Row]> = try await client
            .from("live_streams")
            .select("id,host_id,title,description,status,viewer_count,started_at,ended_at")
            .eq("id", value: id)
            .limit(1)
            .execute()
        if let r = res.value.first {
            return DBLiveStream(id: r.id, host_id: r.host_id, title: r.title, description: r.description, status: r.status, viewer_count: r.viewer_count, started_at: r.started_at, ended_at: r.ended_at, token: nil)
        }
        return nil
    }

    /// Active live stream for the current user as host (if any)
    func fetchActiveLiveForCurrentUser() async throws -> DBLiveStream? {
        guard let me = user?.id.uuidString else { return nil }
        let res: PostgrestResponse<[DBLiveStream]> = try await client
            .from("live_streams")
            .select("id,host_id,title,description,status,viewer_count,started_at,ended_at")
            .eq("host_id", value: me)
            .eq("status", value: "live")
            .order("started_at", ascending: false)
            .limit(1)
            .execute()
        return res.value.first
    }

    /// Active live stream for a specific user as host (if any)
    func fetchActiveLiveForUser(userId: String) async throws -> DBLiveStream? {
        let res: PostgrestResponse<[DBLiveStream]> = try await client
            .from("live_streams")
            .select("id,host_id,title,description,status,viewer_count,started_at,ended_at")
            .eq("host_id", value: userId)
            .eq("status", value: "live")
            .order("started_at", ascending: false)
            .limit(1)
            .execute()
        return res.value.first
    }

    // Join/leave live stream to update viewer_count via trigger
    func recordViewerJoin(streamId: String) async {
        guard let me = user?.id.uuidString else { return }
        _ = try? await client
            .from("live_stream_viewers")
            .insert([["live_stream_id": streamId, "viewer_id": me]])
            .select("id")
            .execute()
    }

    func recordViewerLeave(streamId: String) async {
        guard let me = user?.id.uuidString else { return }
        _ = try? await client
            .from("live_stream_viewers")
            .delete()
            .eq("live_stream_id", value: streamId)
            .eq("viewer_id", value: me)
            .execute()
    }

    // List current viewers for a stream (joined via live_stream_viewers)
    func fetchLiveViewers(streamId: String, limit: Int = 200) async throws -> [DBProfile] {
        struct Row: Decodable { let viewer_id: String }
        let res: PostgrestResponse<[Row]> = try await client
            .from("live_stream_viewers")
            .select("viewer_id")
            .eq("live_stream_id", value: streamId)
            .limit(limit)
            .execute()
        let ids = res.value.map { $0.viewer_id }
        return try await fetchProfilesByUserIds(ids)
    }

    func fetchProfileByUserId(_ userId: String) async throws -> DBProfile? {
        let res: PostgrestResponse<[DBProfile]> = try await client
            .from("profiles")
            .select("*")
            .eq("user_id", value: userId)
            .limit(1)
            .execute()
        return res.value.first
    }

    // MARK: - Live comments (poll + insert)
    func fetchLiveComments(streamId: String) async throws -> [DBLiveStreamComment] {
        let res: PostgrestResponse<[DBLiveStreamComment]> = try await client
            .from("live_stream_comments")
            .select("id,live_stream_id,user_id,content,created_at")
            .eq("live_stream_id", value: streamId)
            .order("created_at", ascending: true)
            .execute()
        return res.value
    }

    func sendLiveComment(streamId: String, content: String) async throws -> DBLiveStreamComment? {
        guard let me = user?.id.uuidString else { return nil }
        let res: PostgrestResponse<[DBLiveStreamComment]> = try await client
            .from("live_stream_comments")
            .insert([[
                "live_stream_id": streamId,
                "user_id": me,
                "content": content
            ]])
            .select("*")
            .execute()
        return res.value.first
    }

    /// Fetch a live session via Edge Function (returns stream + viewer token)
    func fetchLiveSession(_ id: String) async throws -> DBLiveStream {
        var comps = URLComponents(url: SupabaseConfig.url.appendingPathComponent("functions/v1/live-session"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "id", value: id)]
        var req = URLRequest(url: comps.url!)
        req.httpMethod = "GET"
        req.addValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        if let token = try? await client.auth.session.accessToken { req.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let msg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
            throw NSError(domain: "LiveSession", code: (resp as? HTTPURLResponse)?.statusCode ?? -1, userInfo: [NSLocalizedDescriptionKey: msg ?? "Failed to fetch live session"]) }
        return try JSONDecoder().decode(DBLiveStream.self, from: data)
    }

    /// Update live session row (e.g., status: live/ended, started_at/ended_at)
    func updateLiveSession(id: String, updates: [String: Any]) async throws -> DBLiveStream {
        var comps = URLComponents(url: SupabaseConfig.url.appendingPathComponent("functions/v1/live-session"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "id", value: id)]
        var req = URLRequest(url: comps.url!)
        req.httpMethod = "PATCH"
        req.addValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        if let token = try? await client.auth.session.accessToken { req.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: updates)
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let msg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
            throw NSError(domain: "LiveSession", code: (resp as? HTTPURLResponse)?.statusCode ?? -1, userInfo: [NSLocalizedDescriptionKey: msg ?? "Failed to update live session"]) }
        return try JSONDecoder().decode(DBLiveStream.self, from: data)
    }

    /// Join as a viewer in DB (for viewer count)
    func joinLiveStream(streamId: String) async throws {
        guard let me = user?.id.uuidString else { return }
        struct Insert: Encodable { let live_stream_id: String; let viewer_id: String }
        _ = try await client
            .from("live_stream_viewers")
            .insert([Insert(live_stream_id: streamId, viewer_id: me)])
            .execute()
    }

    func addLiveStreamComment(streamId: String, content: String) async throws -> DBLiveStreamComment? {
        guard let me = user?.id.uuidString else { return nil }
        struct Insert: Encodable { let live_stream_id: String; let user_id: String; let content: String }
        let res: PostgrestResponse<[DBLiveStreamComment]> = try await client
            .from("live_stream_comments")
            .insert([Insert(live_stream_id: streamId, user_id: me, content: content)])
            .select("*")
            .execute()
        return res.value.first
    }

    // MARK: - Token Transactions (Top-up)
    struct TokenTransactionInsert: Encodable {
        let user_id: String
        let transaction_type: String // e.g., "purchase"
        let tokens: Int
        let kes_amount: Int
        let flutterwave_transaction_id: String
        let flutterwave_transaction_status: String // e.g., "initiated" | "successful"
        let reference_id: String
    }

    struct TokenTransactionRow: Decodable { let id: String }

    func recordTokenTransaction(_ tx: TokenTransactionInsert) async throws -> String? {
        let res: PostgrestResponse<[TokenTransactionRow]> = try await client
            .from("token_transactions")
            .insert([tx])
            .select("id")
            .execute()
        return res.value.first?.id
    }

    func updateTokenTransaction(id: String, status: String) async throws {
        _ = try await client
            .from("token_transactions")
            .update(["flutterwave_transaction_status": status])
            .eq("id", value: id)
            .execute()
    }

    /// Call Edge Function to credit purchased tokens on successful payment.
    func processPurchaseTokens(userId: String, tokens: Int, txRef: String) async throws {
        let functionURL = SupabaseConfig.url.appendingPathComponent("functions/v1/purchase-tokens")
        var req = URLRequest(url: functionURL)
        req.httpMethod = "POST"
        req.addValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        if let token = try? await client.auth.session.accessToken {
            req.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload = ["userId": userId, "tokens": tokens, "txRef": txRef] as [String : Any]
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (_, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }

    // MARK: - Gifting
    struct GiftFunctionPayload: Encodable { let giftId: String; let gifterId: String; let recipientId: String; let tokens: Int; let txRef: String }
    /// Invoke Edge Function 'send-gift' to process gifting (balance updates, counts, notifications).
    func sendGift(giftId: String, recipientId: String, tokens: Int) async throws {
        guard let me = user?.id.uuidString else { throw URLError(.userAuthenticationRequired) }
        let functionURL = SupabaseConfig.url.appendingPathComponent("functions/v1/send-gift")
        var req = URLRequest(url: functionURL)
        req.httpMethod = "POST"
        req.addValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        if let token = try? await client.auth.session.accessToken {
            req.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        let txRef = "ios_\(me)_\(giftId)_\(Int(Date().timeIntervalSince1970))"
        let payload = GiftFunctionPayload(giftId: giftId, gifterId: me, recipientId: recipientId, tokens: tokens, txRef: txRef)
        req.httpBody = try JSONEncoder().encode(payload)
        let (_, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }

    /// Contribute tokens to a wishlist via Edge Function.
    func contributeToWishlist(wishlistId: String, contributorId: String, tokens: Int) async throws {
        let functionURL = SupabaseConfig.url.appendingPathComponent("functions/v1/contribute-wishlist")
        var req = URLRequest(url: functionURL)
        req.httpMethod = "POST"
        req.addValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        if let token = try? await client.auth.session.accessToken {
            req.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload = [
            "wishlistId": wishlistId,
            "contributorId": contributorId,
            "tokens": tokens
        ] as [String : Any]
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (_, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }

    /// Search users by username, name, or email (case-insensitive), excluding current user.
    func searchProfilesByKeyword(_ keyword: String, limit: Int = 10) async throws -> [DBProfile] {
        let term = "%\(keyword)%"
        var q = client
            .from("profiles")
            .select("user_id,username,name,image,email,token_balance")
            .or("username.ilike.\(term),name.ilike.\(term),email.ilike.\(term)")
        if let me = user?.id.uuidString {
            q = q.neq("user_id", value: me)
        }
        let res: PostgrestResponse<[DBProfile]> = try await q
            .order("username", ascending: true)
            .limit(limit)
            .execute()
        return res.value
    }

    // MARK: - Reported users
    struct DBReportedUserItem: Decodable, Identifiable {
        // Use stable id from row id to avoid duplicate/unstable identifiers
        let rec_id: String
        let reported_user_id: DBReportedUserProfile?
        let reason: String?
        let status: String?
        let created_at: String?
        var id: String { rec_id }
        enum CodingKeys: String, CodingKey { case rec_id = "id", reported_user_id, reason, status, created_at }
    }
    struct DBReportedUserProfile: Decodable { let user_id: String; let username: String }

    func fetchReportedUsers(limit: Int = 100, offset: Int = 0) async throws -> [DBReportedUserItem] {
        guard let me = user?.id.uuidString else { return [] }
        let select = "id,reported_user_id(user_id,username),reason,status,created_at"
        let res: PostgrestResponse<[DBReportedUserItem]> = try await client
            .from("user_reports")
            .select(select)
            .eq("reporter_user_id", value: me)
            .order("created_at", ascending: false)
            .range(from: offset, to: offset + max(0, limit - 1))
            .execute()
        return res.value
    }

    // MARK: - Withdrawals
    struct DBWithdrawalRequest: Decodable, Identifiable {
        let id: String
        let user_id: String
        let tokens: Int
        let kes_amount: Int?
        let target_currency: String
        let exchange_rate: Double
        let converted_amount: Double?
        let status: String
        let rejection_reason: String?
        let payment_method: String
        let payment_details: [String: String]?
        let processed_by: String?
        let processed_at: String?
        let transaction_reference: String?
        let created_at: String
        let updated_at: String
    }

    func fetchWithdrawalsByUser(limit: Int = 100) async throws -> [DBWithdrawalRequest] {
        guard let me = user?.id.uuidString else { return [] }
        let res: PostgrestResponse<[DBWithdrawalRequest]> = try await client
            .from("withdrawals")
            .select("*")
            .eq("user_id", value: me)
            .order("created_at", ascending: false)
            .limit(limit)
            .execute()
        return res.value
    }

    func requestWithdrawal(tokens: Int, targetCurrency: String, exchangeRate: Double, paymentMethod: String, paymentDetails: [String: String]?) async throws -> DBWithdrawalRequest? {
        struct Params: Encodable {
            let p_user_id: String
            let p_tokens: Int
            let p_target_currency: String
            let p_exchange_rate: Double
            let p_payment_method: String
            let p_payment_details: [String: String]?
        }
        guard let me = user?.id.uuidString else { return nil }
        let params = Params(
            p_user_id: me,
            p_tokens: tokens,
            p_target_currency: targetCurrency,
            p_exchange_rate: exchangeRate,
            p_payment_method: paymentMethod,
            p_payment_details: paymentDetails
        )
        let res: PostgrestResponse<DBWithdrawalRequest> = try await client
            .rpc("request_withdrawal", params: params)
            .execute()
        return res.value
    }

    // MARK: - Comments
    struct DBCommentRow: Decodable {
        let id: String
        let post_id: String
        let user_id: String
        let parent_comment_id: String?
        let content: String
        let created_at: String?
        let profile: DBProfile?
    }

    func fetchComments(postId: String, limit: Int = 50, offset: Int = 0) async throws -> [DBCommentRow] {
        // Attempt to embed profile fields from profiles table (PostgREST embedded resource)
        let select = "id,post_id,user_id,parent_comment_id,content,created_at,profile:profiles(user_id,username,image)"
        let res: PostgrestResponse<[DBCommentRow]> = try await client
            .from("comments")
            .select(select)
            .eq("post_id", value: postId)
            .order("created_at", ascending: false)
            .limit(limit)
            .execute()
        return res.value
    }

    func deleteComment(id: String) async throws {
        _ = try await client
            .from("comments")
            .delete()
            .eq("id", value: id)
            .execute()
    }

    func fetchPostOwnerId(postId: String) async throws -> String? {
        struct Row: Decodable { let user_id: String }
        let res: PostgrestResponse<[Row]> = try await client
            .from("posts")
            .select("user_id")
            .eq("id", value: postId)
            .limit(1)
            .execute()
        return res.value.first?.user_id
    }

    // MARK: - AI Meme generation via Supabase Edge Function
    struct MemeRes: Decodable { let top_text: String?; let bottom_text: String?; let stickers: [String]? }
    func generateMeme(image: UIImage) async throws -> MemeRes? {
        guard let data = image.jpegData(compressionQuality: 0.85) else { return nil }
        let b64 = data.base64EncodedString()
        let functionURL = SupabaseConfig.url.appendingPathComponent("functions/v1/ai-meme")
        var req = URLRequest(url: functionURL)
        req.httpMethod = "POST"
        req.addValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        if let token = try? await client.auth.session.accessToken {
            req.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload: [String: Any] = ["image_base64": b64, "sfw": true]
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (respData, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
        return try? JSONDecoder().decode(MemeRes.self, from: respData)
    }

    // MARK: - Auto captions via Edge Function
    struct CaptionSegment: Decodable { let start: Double; let end: Double; let text: String }
    func generateAutoCaptions(videoData: Data) async throws -> [CaptionSegment]? {
        // NOTE: For large files consider presigning+upload then passing URL instead
        let b64 = videoData.base64EncodedString()
        let functionURL = SupabaseConfig.url.appendingPathComponent("functions/v1/auto-captions")
        var req = URLRequest(url: functionURL)
        req.httpMethod = "POST"
        req.addValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        if let token = try? await client.auth.session.accessToken {
            req.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload: [String: Any] = ["video_base64": b64, "format": "segments"]
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (respData, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
        return try? JSONDecoder().decode([CaptionSegment].self, from: respData)
    }

    struct InsertComment: Encodable { let post_id: String; let user_id: String; let content: String; let parent_comment_id: String? }
    func addComment(postId: String, content: String, parentCommentId: String? = nil) async throws -> DBCommentRow? {
        guard let me = user?.id.uuidString else { return nil }
        let payload = InsertComment(post_id: postId, user_id: me, content: content, parent_comment_id: parentCommentId)
        let res: PostgrestResponse<[DBCommentRow]> = try await client
            .from("comments")
            .insert([payload])
            .select("id,post_id,user_id,parent_comment_id,content,created_at,profile:profiles(user_id,username,image)")
            .execute()
        return res.value.first
    }

    // MARK: - Likes
    struct ReactionInsert: Encodable { let post_id: String; let user_id: String; let type: String }
    func setLike(postId: String, like: Bool) async throws {
        guard let me = user?.id.uuidString else { return }
        if like {
            _ = try await client
                .from("post_reactions")
                .insert([ReactionInsert(post_id: postId, user_id: me, type: "like")])
                .execute()
        } else {
            _ = try await client
                .from("post_reactions")
                .delete()
                .eq("post_id", value: postId)
                .eq("user_id", value: me)
                .eq("type", value: "like")
                .execute()
        }
    }

    /// Add a "share" reaction to a post (used for Share to Profile)
    func addShare(postId: String) async throws {
        guard let me = user?.id.uuidString else { return }
        // Only insert if not already shared
        struct Row: Decodable { let id: String }
        let exists: PostgrestResponse<[Row]> = try await client
            .from("post_reactions")
            .select("id")
            .eq("post_id", value: postId)
            .eq("user_id", value: me)
            .eq("type", value: "share")
            .limit(1)
            .execute()
        if exists.value.isEmpty {
            _ = try await client
                .from("post_reactions")
                .insert([ReactionInsert(post_id: postId, user_id: me, type: "share")])
                .execute()
        }
    }

    /// Fetch a set of post IDs that the current user has liked.
    func fetchUserLikedPostIDs(postIDs: [String]) async throws -> Set<String> {
        guard let me = user?.id.uuidString, !postIDs.isEmpty else { return [] }
        struct Row: Decodable { let post_id: String }
        let res: PostgrestResponse<[Row]> = try await client
            .from("post_reactions")
            .select("post_id")
            .eq("user_id", value: me)
            .eq("type", value: "like")
            .in("post_id", values: postIDs)
            .execute()
        return Set(res.value.map { $0.post_id })
    }

    // MARK: - Comment reactions (like)
    struct CommentReactionInsert: Encodable { let comment_id: String; let user_id: String; let type: String }
    func toggleCommentLike(commentId: String) async throws {
        guard let me = user?.id.uuidString else { return }
        // Check if like exists
        struct Row: Decodable { let id: String }
        let existing: PostgrestResponse<[Row]> = try await client
            .from("comment_reactions")
            .select("id")
            .eq("comment_id", value: commentId)
            .eq("user_id", value: me)
            .eq("type", value: "like")
            .limit(1)
            .execute()
        if let row = existing.value.first {
            _ = try await client
                .from("comment_reactions")
                .delete()
                .eq("id", value: row.id)
                .execute()
        } else {
            _ = try await client
                .from("comment_reactions")
                .insert([CommentReactionInsert(comment_id: commentId, user_id: me, type: "like")])
                .execute()
        }
    }

    // MARK: - Profile Fetch
    func fetchProfile(username: String?, userId: String?) async throws -> DBProfile? {
        if let u = username {
            let res: PostgrestResponse<[DBProfile]> = try await client
                .from("profiles")
                .select()
                .eq("username", value: u)
                .execute()
            return res.value.first
        }
        if let id = userId {
            let res: PostgrestResponse<[DBProfile]> = try await client
                .from("profiles")
                .select()
                .eq("user_id", value: id)
                .execute()
            return res.value.first
        }
        // current user
        guard let me = user?.id.uuidString else { return nil }
        let res: PostgrestResponse<[DBProfile]> = try await client
            .from("profiles")
            .select()
            .eq("user_id", value: me)
            .execute()
        return res.value.first
    }

    // MARK: - Follow State
    func isFollowing(currentUserId: String, targetUserId: String) async throws -> Bool {
        let res: PostgrestResponse<[Row]> = try await client
            .from("follows")
            .select("id")
            .eq("follower_id", value: currentUserId)
            .eq("followed_id", value: targetUserId)
            .limit(1)
            .execute()
        struct Row: Decodable { let id: String }
        return !res.value.isEmpty
    }

    func setFollow(currentUserId: String, targetUserId: String, follow: Bool) async throws {
        if follow {
            _ = try await client
                .from("follows")
                .insert([[
                    "follower_id": currentUserId,
                    "followed_id": targetUserId
                ]])
                .execute()
        } else {
            _ = try await client
                .from("follows")
                .delete()
                .eq("follower_id", value: currentUserId)
                .eq("followed_id", value: targetUserId)
                .execute()
        }
    }

    // MARK: - Posts media (first media per post)
    func fetchUserPostThumbs(userId: String, limit: Int = 20) async throws -> [URL] {
        let postRes: PostgrestResponse<[Row]> = try await client
            .from("posts")
            .select("id")
            .eq("user_id", value: userId)
            .order("id", ascending: false)
            .limit(limit)
            .execute()
        struct Row: Decodable { let id: String }
        let posts: [Row] = postRes.value
        let ids = posts.map { $0.id }
        guard !ids.isEmpty else { return [] }
        let mediaRes: PostgrestResponse<[DBPostMedia]> = try await client
            .from("post_media")
            .select("post_id,url,order")
            .in("post_id", values: ids)
            .order("order", ascending: true)
            .execute()
        let media: [DBPostMedia] = mediaRes.value
        // pick first media per post in the same order as posts
        var firstMap: [String: URL] = [:]
        for m in media {
            if firstMap[m.post_id] == nil, let url = URL(string: m.url) { firstMap[m.post_id] = url }
        }
        return ids.compactMap { firstMap[$0] }
    }

    // MARK: - Create Post (parity with Angular/Kotlin)
    struct CreatePostInsert: Encodable {
        let user_id: String
        let content: String
        let access_type: String
        let price: Int?
        let required_plan_id: String?
    }
    struct DBPostRow: Decodable { let id: String; let user_id: String }
    /// Create a new post row. Returns DBPostRow with id.
    func createPost(content: String, accessType: String = "free", price: Int? = nil, requiredPlanId: String? = nil) async throws -> DBPostRow? {
        let me = try await resolvedUserId(explicit: nil)
        let payload = CreatePostInsert(user_id: me, content: content, access_type: accessType, price: price, required_plan_id: requiredPlanId)
        let res: PostgrestResponse<[DBPostRow]> = try await client
            .from("posts")
            .insert([payload])
            .select("id,user_id")
            .execute()
        return res.value.first
    }
    struct PostMediaInsert: Encodable { let post_id: String; let media_type: String; let url: String; let order: Int }
    /// Insert a post_media row after uploading to storage; returns inserted row
    func insertPostMedia(postId: String, mediaType: String, url: String, order: Int) async throws -> DBPostMedia? {
        let payload = PostMediaInsert(post_id: postId, media_type: mediaType, url: url, order: order)
        let res: PostgrestResponse<[DBPostMedia]> = try await client
            .from("post_media")
            .insert([payload])
            .select("post_id,url,order")
            .execute()
        return res.value.first
    }

    // MARK: - Wishlists (basic)
    func fetchWishlists(userId: String, limit: Int = 20) async throws -> [DBWishlist] {
        let res: PostgrestResponse<[DBWishlist]> = try await client
            .from("wishlists")
            .select("id,title")
            .eq("user_id", value: userId)
            .order("id", ascending: false)
            .limit(limit)
            .execute()
        return res.value
    }

    // MARK: - Wishlists (detailed for list/detail)
    func fetchWishlistsDetailed(userId: String, limit: Int = 30, offset: Int = 0) async throws -> [DBWishlistFull] {
        let res: PostgrestResponse<[DBWishlistFull]> = try await client
            .from("wishlists")
            .select("id,user_id,link,name,description,image,tokens,is_fulfilled,created_at,profile:profiles(user_id,username,name,image),wishlist_contributions(tokens)")
            .eq("user_id", value: userId)
            .order("created_at", ascending: false)
            .limit(limit)
            .execute()
        return res.value
    }

    func fetchAllWishlistsDetailed(limit: Int = 30, offset: Int = 0) async throws -> [DBWishlistFull] {
        let res: PostgrestResponse<[DBWishlistFull]> = try await client
            .from("wishlists")
            .select("id,user_id,link,name,description,image,tokens,is_fulfilled,created_at,profile:profiles(user_id,username,name,image),wishlist_contributions(tokens)")
            .order("created_at", ascending: false)
            .limit(limit)
            .execute()
        return res.value
    }

    func fetchWishlistById(_ id: String) async throws -> DBWishlistFull? {
        let res: PostgrestResponse<[DBWishlistFull]> = try await client
            .from("wishlists")
            .select("id,user_id,link,name,description,image,tokens,is_fulfilled,created_at,profile:profiles(user_id,username,name,image),wishlist_contributions(tokens)")
            .eq("id", value: id)
            .limit(1)
            .execute()
        return res.value.first
    }

    func fetchWishlistContributions(wishlistId: String) async throws -> [DBWishlistContribution] {
        let res: PostgrestResponse<[DBWishlistContribution]> = try await client
            .from("wishlist_contributions")
            .select("id,user_id,contributor_id,wishlist_id,tokens,created_at,updated_at")
            .eq("wishlist_id", value: wishlistId)
            .order("created_at", ascending: false)
            .limit(1000)
            .execute()
        return res.value
    }

    func fetchProfilesByUserIds(_ ids: [String]) async throws -> [DBProfile] {
        guard !ids.isEmpty else { return [] }
        let res: PostgrestResponse<[DBProfile]> = try await client
            .from("profiles")
            .select("user_id,username,name,image,email")
            .in("user_id", values: ids)
            .execute()
        return res.value
    }

    struct CreateWishlistInput: Encodable {
        let user_id: String
        let name: String
        let description: String
        let link: String?
        let image: String?
        let tokens: Int
        let is_fulfilled: Bool
    }

    func createWishlist(_ input: CreateWishlistInput) async throws -> String? {
        let res: PostgrestResponse<[[String: String]]> = try await client
            .from("wishlists")
            .insert([input])
            .select("id")
            .execute()
        return res.value.first?["id"]
    }

    struct UpdateWishlistInput: Encodable {
        var name: String?
        var description: String?
        var link: String?
        var image: String?
        var tokens: Int?
        var is_fulfilled: Bool?
    }

    func updateWishlist(id: String, updates: UpdateWishlistInput) async throws {
        _ = try await client
            .from("wishlists")
            .update(updates)
            .eq("id", value: id)
            .execute()
    }

    // MARK: - Gifts (catalog)
    enum GiftsSortKey { case newest, popular, priceAsc, priceDesc }
    func fetchGifts(sort: GiftsSortKey = .newest, limit: Int = 40) async throws -> [DBGift] {
        let base = client.from("gifts").select("id,name,tokens,image")
        let ordered = {
            switch sort {
            case .newest: return base.order("id", ascending: false)
            case .popular: return base.order("is_popular", ascending: false)
            case .priceAsc: return base.order("tokens", ascending: true)
            case .priceDesc: return base.order("tokens", ascending: false)
            }
        }()
        let res: PostgrestResponse<[DBGift]> = try await ordered.limit(limit).execute()
        return res.value
    }

    // MARK: - Update Profile (partial)
    struct PartialProfile: Encodable {
        var username: String?
        var name: String?
        var bio: String?
        var image: String?
    }
    func updateProfile(userId: String, updates: PartialProfile) async throws -> DBProfile? {
        let res: PostgrestResponse<[DBProfile]> = try await client
            .from("profiles")
            .update(updates)
            .eq("user_id", value: userId)
            .select()
            .execute()
        return res.value.first
    }

    // MARK: - Chats & Notifications
    func fetchConversationDetails(limit: Int = 100) async throws -> [DBConversationDetails] {
        let res: PostgrestResponse<[DBConversationDetails]> = try await client
            .from("conversation_details")
            .select("*")
            .order("last_message_at", ascending: false)
            .limit(limit)
            .execute()
        return res.value
    }

    // MARK: - E2EE user keys
    struct DBUserKey: Decodable { let user_id: String; let public_key: String; let created_at: String }
    func upsertMyPublicKey(_ b64: String) async {
        guard let me = user?.id.uuidString else { return }
        _ = try? await client
            .from("user_e2ee_keys")
            .upsert([["user_id": me, "public_key": b64]])
            .execute()
    }
    func fetchPublicKey(for userId: String) async -> String? {
        if let res: PostgrestResponse<[DBUserKey]> = try? await client
            .from("user_e2ee_keys")
            .select("user_id,public_key,created_at")
            .eq("user_id", value: userId)
            .limit(1)
            .execute() {
            return res.value.first?.public_key
        }
        return nil
    }

    // MARK: - User Settings (interaction privacy)
    struct DBUserSettings: Decodable { let user_id: String; let who_can_interact: String? }
    func fetchMyUserSettings() async -> DBUserSettings? {
        guard let me = user?.id.uuidString else { return nil }
        if let res: PostgrestResponse<[DBUserSettings]> = try? await client
            .from("user_settings")
            .select("user_id,who_can_interact")
            .eq("user_id", value: me)
            .limit(1)
            .execute() {
            return res.value.first
        }
        return nil
    }
    func updateInteractionSetting(_ who: String) async throws {
        guard let me = user?.id.uuidString else { throw URLError(.userAuthenticationRequired) }
        struct Row: Encodable { let user_id: String; let who_can_interact: String }
        _ = try await client
            .from("user_settings")
            .upsert([Row(user_id: me, who_can_interact: who)])
            .select("user_id")
            .execute()
    }

    func fetchNotifications(userId: String? = nil, limit: Int = 200) async throws -> [DBNotification] {
        let uid = try await resolvedUserId(explicit: userId)
        let q = client
            .from("notifications")
            .select("*")
            .eq("user_id", value: uid)
            .order("created_at", ascending: false)
            .limit(limit)
        let res: PostgrestResponse<[DBNotification]> = try await q.execute()
        return res.value
    }

    func markNotificationRead(id: String) async throws {
        struct Patch: Encodable { let is_read: Bool }
        _ = try await client
            .from("notifications")
            .update(Patch(is_read: true))
            .eq("id", value: id)
            .select()
            .execute()
    }

    func fetchMessages(partnerId: String, orderAsc: Bool = true, sinceISO: String? = nil) async throws -> [DBMessage] {
        let me = try await resolvedUserId(explicit: nil)
        var q = client
            .from("messages")
            .select("id,sender_id,receiver_id,content,created_at,attachments")
            .or("and(sender_id.eq.\(me),receiver_id.eq.\(partnerId)),and(sender_id.eq.\(partnerId),receiver_id.eq.\(me))")
        if let sinceISO { q = q.gte("created_at", value: sinceISO) }
        let res: PostgrestResponse<[DBMessage]> = try await q
            .order("created_at", ascending: orderAsc)
            .execute()
        return res.value
    }

    // Delete a single message by id (allowed if the current user is sender or receiver per RLS)
    func deleteMessage(id: String) async throws {
        _ = try await client
            .from("messages")
            .delete()
            .eq("id", value: id)
            .select("id")
            .execute()
        // Purge from cache
        cacheQueue.sync {
            for (k, var list) in messagesCache {
                if let idx = list.firstIndex(where: { $0.id == id }) {
                    list.remove(at: idx)
                    messagesCache[k] = list
                }
            }
        }
    }

    // Attempt to delete entire conversation (two-way). If deleting partner's messages is denied by RLS,
    // we still delete my sent messages.
    func deleteConversation(with partnerId: String) async throws {
        let me = try await resolvedUserId(explicit: nil)
        // Try delete both directions
        do {
            _ = try await client
                .from("messages")
                .delete()
                .or("and(sender_id.eq.\(me),receiver_id.eq.\(partnerId)),and(sender_id.eq.\(partnerId),receiver_id.eq.\(me))")
                .select("id")
                .execute()
        } catch {
            // Fallback: delete only my messages (sender_id = me)
            _ = try? await client
                .from("messages")
                .delete()
                .eq("sender_id", value: me)
                .eq("receiver_id", value: partnerId)
                .select("id")
                .execute()
        }
        // Clear cache for that partner
        _ = cacheQueue.sync { messagesCache.removeValue(forKey: partnerId) }
    }

    // MARK: - Lightweight In-Memory Cache (Chat)
    private var messagesCache: [String: [DBMessage]] = [:] // partnerId -> messages ordered asc
    private let cacheQueue = DispatchQueue(label: "chat-cache-queue")

    /// Return cached messages for a partner (if any), ordered ascending by created_at.
    func cachedMessages(partnerId: String) -> [DBMessage] {
        cacheQueue.sync { messagesCache[partnerId] ?? [] }
    }

    /// Fetch only new messages since the last cached item, merge, and return the full ordered list.
    @MainActor
    func syncMessages(partnerId: String) async -> [DBMessage] {
        let since: String? = cacheQueue.sync {
            messagesCache[partnerId]?.last?.created_at
        }
        do {
            var delta = try await fetchMessages(partnerId: partnerId, orderAsc: true, sinceISO: since)
            // Attempt E2EE decrypt
            if let peerPub = await fetchPublicKey(for: partnerId), let key = try? E2EEKeyManager.shared.sharedSecret(with: peerPub) {
                delta = delta.map { m in
                    if let dec = try? E2EEKeyManager.shared.decrypt(m.content, with: key) {
                        return DBMessage(id: m.id, sender_id: m.sender_id, receiver_id: m.receiver_id, content: dec, created_at: m.created_at, attachments: m.attachments)
                    }
                    return m
                }
            }
            if delta.isEmpty { return cachedMessages(partnerId: partnerId) }
            // Merge + de-dupe by id
            var merged = cacheQueue.sync { messagesCache[partnerId] ?? [] }
            var seen = Set(merged.map { $0.id })
            for m in delta where !seen.contains(m.id) { merged.append(m); seen.insert(m.id) }
            // Ensure ascending order
            merged.sort { $0.created_at < $1.created_at }
            cacheQueue.sync { messagesCache[partnerId] = merged }
            return merged
        } catch {
            return cachedMessages(partnerId: partnerId)
        }
    }

    func markMessagesAsRead(partnerId: String, readAtISO: String = ISO8601DateFormatter().string(from: Date())) async throws {
        let me = try await resolvedUserId(explicit: nil)
        struct Patch: Encodable { let read_at: String }
        _ = try await client
            .from("messages")
            .update(Patch(read_at: readAtISO))
            .eq("sender_id", value: partnerId)
            .eq("receiver_id", value: me)
            .is("read_at", value: nil)
            .execute()
    }

    struct InsertMessage: Encodable { let sender_id: String; let receiver_id: String; let content: String }
    func sendMessage(to partnerId: String, content: String) async throws -> DBMessage? {
        let me = try await resolvedUserId(explicit: nil)
        var body = content
        if let peerPub = await fetchPublicKey(for: partnerId), let key = try? E2EEKeyManager.shared.sharedSecret(with: peerPub), let blob = try? E2EEKeyManager.shared.encrypt(content, with: key) {
            body = blob
        }
        let payload = InsertMessage(sender_id: me, receiver_id: partnerId, content: body)
        let res: PostgrestResponse<[DBMessage]> = try await client
            .from("messages")
            .insert([payload])
            .select("id,sender_id,receiver_id,content,created_at,attachments")
            .execute()
        return res.value.first
    }

    private func resolvedUserId(explicit: String?) async throws -> String {
        if let id = explicit { return id }
        guard let me = user?.id.uuidString else { throw URLError(.userAuthenticationRequired) }
        return me
    }

    // MARK: - Functions helpers
    func currentAccessToken() async -> String? {
        return try? await client.auth.session.accessToken
    }

    // MARK: - Realtime (Chat)
    // Store active realtime channels by partnerId
    private var chatChannels: [String: RealtimeChannelV2] = [:]
    private var chatIndexChannel: RealtimeChannelV2?

    /// Subscribe to realtime inserts on messages table between current user and partner.
    /// Calls `onInsert` on main thread with the decoded DBMessage.
    func subscribeToChat(partnerId: String, onInsert: @escaping (DBMessage) -> Void) async {
        guard let me = user?.id.uuidString else { return }
        guard NetworkMonitor.shared.isReachable else { return }
        if chatChannels[partnerId] != nil { return }
        let ch = client.channel("chat-\(me.prefix(6))-\(partnerId.prefix(6))")
        // Listen to my outgoing messages to this partner
        _ = ch.onPostgresChange(InsertAction.self, schema: "public", table: "messages", filter: "sender_id=eq.\(me)") { action in
            let rec = action.record
            if let msg = Self.decodeRecord(rec), msg.receiver_id == partnerId {
                DispatchQueue.main.async { onInsert(msg) }
            }
        }
        // Listen to partner's outgoing messages to me
        _ = ch.onPostgresChange(InsertAction.self, schema: "public", table: "messages", filter: "sender_id=eq.\(partnerId)") { action in
            let rec = action.record
            if let msg = Self.decodeRecord(rec), msg.receiver_id == me {
                DispatchQueue.main.async { onInsert(msg) }
            }
        }
        do { try await ch.subscribeWithError() } catch { return }
        chatChannels[partnerId] = ch
    }

    func unsubscribeChat(partnerId: String) async {
        if let ch = chatChannels.removeValue(forKey: partnerId) {
            await ch.unsubscribe()
            await client.removeChannel(ch)
        }
    }

    /// Subscribe to all messages involving the current user (for chat list updates).
    func subscribeToAllChats(onInsert: @escaping (DBMessage) -> Void) async {
        guard let me = user?.id.uuidString else { return }
        guard NetworkMonitor.shared.isReachable else { return }
        if chatIndexChannel != nil { return }
        let ch = client.channel("chat-index-\(me.prefix(6))")
        // Listen for my outgoing messages (receiver can be anyone)
        _ = ch.onPostgresChange(InsertAction.self, schema: "public", table: "messages", filter: "sender_id=eq.\(me)") { action in
            if let msg = Self.decodeRecord(action.record) {
                DispatchQueue.main.async { onInsert(msg) }
            }
        }
        // Listen for incoming messages to me (from anyone)
        _ = ch.onPostgresChange(InsertAction.self, schema: "public", table: "messages", filter: "receiver_id=eq.\(me)") { action in
            if let msg = Self.decodeRecord(action.record) {
                DispatchQueue.main.async { onInsert(msg) }
            }
        }
        do { try await ch.subscribeWithError() } catch { return }
        chatIndexChannel = ch
    }

    func unsubscribeAllChats() async {
        if let ch = chatIndexChannel {
            await ch.unsubscribe()
            await client.removeChannel(ch)
            chatIndexChannel = nil
        }
    }

    // Helper to decode Postgres change payload across supabase-swift versions
    private static func decodeRecord(_ record: [String: Any]) -> DBMessage? {
        guard let data = try? JSONSerialization.data(withJSONObject: record) else { return nil }
        return try? JSONDecoder().decode(DBMessage.self, from: data)
    }

    // MARK: - Realtime (Live comments & invites)
    private var liveCommentChannels: [String: RealtimeChannelV2] = [:] // key: streamId
    private var inviteChannels: [String: RealtimeChannelV2] = [:] // key: streamId (viewer or host context)
    private var giftChannels: [String: RealtimeChannelV2] = [:]

    /// Subscribe to realtime inserts on live_stream_comments for a specific stream id.
    func subscribeToLiveComments(streamId: String, onInsert: @escaping (DBLiveStreamComment) -> Void) async {
        if liveCommentChannels[streamId] != nil { return }
        let ch = client.channel("live-comments-\(streamId.prefix(6))")
        _ = ch.onPostgresChange(InsertAction.self, schema: "public", table: "live_stream_comments", filter: "live_stream_id=eq.\(streamId)") { action in
            let rec = action.record
            guard let data = try? JSONSerialization.data(withJSONObject: rec), let row = try? JSONDecoder().decode(DBLiveStreamComment.self, from: data) else { return }
            DispatchQueue.main.async { onInsert(row) }
        }
        do { try await ch.subscribeWithError() } catch { return }
        liveCommentChannels[streamId] = ch
    }

    func unsubscribeLiveComments(streamId: String) async {
        if let ch = liveCommentChannels.removeValue(forKey: streamId) {
            await ch.unsubscribe(); await client.removeChannel(ch)
        }
    }

    /// Subscribe to realtime updates on invites for the current viewer for this stream (status changes).
    func subscribeToMyInvite(streamId: String, onStatus: @escaping (String) -> Void) async {
        guard let me = user?.id.uuidString else { return }
        if inviteChannels["viewer_\(streamId)"] != nil { return }
        let ch = client.channel("live-invite-self-\(streamId.prefix(6))")
        _ = ch.onPostgresChange(UpdateAction.self, schema: "public", table: "live_stream_invites", filter: "live_stream_id=eq.\(streamId)") { action in
            let rec = action.record
            // Decode robustly to avoid AnyJSON casts
            if let data = try? JSONSerialization.data(withJSONObject: rec) {
                struct InviteRow: Decodable { let invitee_id: String; let status: String }
                if let row = try? JSONDecoder().decode(InviteRow.self, from: data), row.invitee_id == me {
                    DispatchQueue.main.async { onStatus(row.status) }
                }
            }
        }
        do { try await ch.subscribeWithError() } catch { return }
        inviteChannels["viewer_\(streamId)"] = ch
    }

    func unsubscribeMyInvite(streamId: String) async {
        if let ch = inviteChannels.removeValue(forKey: "viewer_\(streamId)") { await ch.unsubscribe(); await client.removeChannel(ch) }
    }

    /// Host: Subscribe to any changes on invites for a live to refresh list.
    func subscribeToInvitesForLive(streamId: String, onChange: @escaping () -> Void) async {
        if inviteChannels["host_\(streamId)"] != nil { return }
        let ch = client.channel("live-invite-host-\(streamId.prefix(6))")
        _ = ch.onPostgresChange(InsertAction.self, schema: "public", table: "live_stream_invites", filter: "live_stream_id=eq.\(streamId)") { _ in DispatchQueue.main.async { onChange() } }
        _ = ch.onPostgresChange(UpdateAction.self, schema: "public", table: "live_stream_invites", filter: "live_stream_id=eq.\(streamId)") { _ in DispatchQueue.main.async { onChange() } }
        do { try await ch.subscribeWithError() } catch { return }
        inviteChannels["host_\(streamId)"] = ch
    }

    func unsubscribeInvitesForLive(streamId: String) async {
        if let ch = inviteChannels.removeValue(forKey: "host_\(streamId)") { await ch.unsubscribe(); await client.removeChannel(ch) }
    }

    // Gift events Realtime: subscribe to inserts on gift_sent for a live
    struct RTGiftSentRow: Decodable { let live_stream_id: String; let gifter: String; let recipient: String; let gift: String; let tokens_used: Int?; let created_at: String? }
    func subscribeToGiftSent(streamId: String, onInsert: @escaping (RTGiftSentRow) -> Void) async {
        if giftChannels[streamId] != nil { return }
        let ch = client.channel("gift-sent-\(streamId.prefix(6))")
        _ = ch.onPostgresChange(InsertAction.self, schema: "public", table: "gift_sent", filter: "live_stream_id=eq.\(streamId)") { action in
            let rec = action.record
            guard let data = try? JSONSerialization.data(withJSONObject: rec), let row = try? JSONDecoder().decode(RTGiftSentRow.self, from: data) else { return }
            DispatchQueue.main.async { onInsert(row) }
        }
        do { try await ch.subscribeWithError() } catch { return }
        giftChannels[streamId] = ch
    }
    func unsubscribeGiftSent(streamId: String) async {
        if let ch = giftChannels.removeValue(forKey: streamId) { await ch.unsubscribe(); await client.removeChannel(ch) }
    }

    struct PresignRequest: Encodable {
        let fileName: String
        let fileType: String
        let bucket: String
        let overwrite: Bool
    }
    struct PresignResponse: Decodable { let uploadUrl: String; let publicUrl: String }

    /// Generic media upload via Supabase Edge Function; returns a public URL
    func uploadMedia(bytes: Data, fileName: String, mimeType: String, bucket: String) async throws -> String {
        let functionURL = SupabaseConfig.url.appendingPathComponent("functions/v1/upload-media")
        var req = URLRequest(url: functionURL)
        req.httpMethod = "POST"
        req.addValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        if let token = await currentAccessToken() { req.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = PresignRequest(fileName: fileName, fileType: mimeType, bucket: bucket, overwrite: false)
        req.httpBody = try JSONEncoder().encode(body)
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw URLError(.badServerResponse) }
        let presign = try JSONDecoder().decode(PresignResponse.self, from: data)
        guard let uploadURL = URL(string: presign.uploadUrl) else { throw URLError(.badURL) }
        var put = URLRequest(url: uploadURL)
        put.httpMethod = "PUT"
        put.addValue(mimeType, forHTTPHeaderField: "Content-Type")
        // Prefer background session so large uploads continue in background; fall back to foreground if device rejects background mode
        do {
            let _ = try await BackgroundUploadManager.shared.upload(request: put, data: bytes)
        } catch {
            // Fallback: foreground upload with explicit status check
            let (_, resp) = try await URLSession.shared.upload(for: put, from: bytes)
            if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw URLError(.badServerResponse)
            }
        }
        return presign.publicUrl
    }

    /// Upload avatar bytes to S3 via Supabase Edge Function and return the public URL
    func uploadAvatar(imageData: Data, mimeType: String = "image/jpeg") async throws -> String {
        guard let me = user?.id.uuidString else { throw URLError(.userAuthenticationRequired) }
        let filename = "profile-\(me).jpg"
        return try await uploadMedia(bytes: imageData, fileName: filename, mimeType: mimeType, bucket: "profile")
    }

    // MARK: - Chat Send with Attachments
    struct MessageAttachment: Encodable { let url: String; let type: String }
    struct InsertMessageWithAttachments: Encodable { let sender_id: String; let receiver_id: String; let content: String; let attachments: [MessageAttachment] }
    func sendMessage(to partnerId: String, content: String, attachments: [MessageAttachment]) async throws -> DBMessage? {
        let me = try await resolvedUserId(explicit: nil)
        let payload = InsertMessageWithAttachments(sender_id: me, receiver_id: partnerId, content: content, attachments: attachments)
        let res: PostgrestResponse<[DBMessage]> = try await client
            .from("messages")
            .insert([payload])
            .select("id,sender_id,receiver_id,content,created_at,attachments")
            .execute()
        return res.value.first
    }

    // MARK: - Security (Block/Unblock)
    func fetchBlockedUsers() async throws -> [DBProfile] {
        guard let me = user?.id.uuidString else { return [] }
        let blocks: PostgrestResponse<[DBBlocked]> = try await client
            .from("user_blocks")
            .select("blocked_user_id")
            .eq("blocker_user_id", value: me)
            .execute()
        let ids = blocks.value.map { $0.blocked_user_id }
        guard !ids.isEmpty else { return [] }
        let res: PostgrestResponse<[DBProfile]> = try await client
            .from("profiles")
            .select("user_id,username,image")
            .in("user_id", values: ids)
            .execute()
        return res.value
    }

    func blockUser(targetUserId: String) async throws {
        guard let me = user?.id.uuidString else { return }
        _ = try await client
            .from("user_blocks")
            .insert([["blocker_user_id": me, "blocked_user_id": targetUserId]])
            .execute()
    }

    func unblockUser(targetUserId: String) async throws {
        guard let me = user?.id.uuidString else { return }
        _ = try await client
            .from("user_blocks")
            .delete()
            .eq("blocker_user_id", value: me)
            .eq("blocked_user_id", value: targetUserId)
            .execute()
    }

    func findUserId(byUsername username: String) async throws -> String? {
        let res: PostgrestResponse<[DBProfile]> = try await client
            .from("profiles")
            .select("user_id,username")
            .eq("username", value: username)
            .limit(1)
            .execute()
        return res.value.first?.user_id
    }

    // MARK: - Followers/Following/Gifters lists
    func fetchFollowers(of userId: String, limit: Int = 100, offset: Int = 0) async throws -> [DBProfile] {
        struct Row: Decodable { let follower_id: String }
        let res: PostgrestResponse<[Row]> = try await client
            .from("follows")
            .select("follower_id")
            .eq("followed_id", value: userId)
            .order("created_at", ascending: false)
            .range(from: offset, to: offset + max(0, limit) - 1)
            .execute()
        let ids = res.value.map { $0.follower_id }
        if ids.isEmpty { return [] }
        let profs: PostgrestResponse<[DBProfile]> = try await client
            .from("profiles")
            .select()
            .in("user_id", values: ids)
            .execute()
        return profs.value
    }

    func fetchFollowing(of userId: String, limit: Int = 100, offset: Int = 0) async throws -> [DBProfile] {
        struct Row: Decodable { let followed_id: String }
        let res: PostgrestResponse<[Row]> = try await client
            .from("follows")
            .select("followed_id")
            .eq("follower_id", value: userId)
            .order("created_at", ascending: false)
            .range(from: offset, to: offset + max(0, limit) - 1)
            .execute()
        let ids = res.value.map { $0.followed_id }
        if ids.isEmpty { return [] }
        let profs: PostgrestResponse<[DBProfile]> = try await client
            .from("profiles")
            .select()
            .in("user_id", values: ids)
            .execute()
        return profs.value
    }

    func fetchGifters(for userId: String, limit: Int = 100, offset: Int = 0) async throws -> [DBProfile] {
        struct Row: Decodable { let gifter: String }
        // Distinct gifters who sent to this user
        let res: PostgrestResponse<[Row]> = try await client
            .from("gift_sent")
            .select("gifter")
            .eq("recipient", value: userId)
            .order("created_at", ascending: false)
            .range(from: offset, to: offset + max(0, limit) - 1)
            .execute()
        let ids = Array(Set(res.value.map { $0.gifter }))
        if ids.isEmpty { return [] }
        let profs: PostgrestResponse<[DBProfile]> = try await client
            .from("profiles")
            .select()
            .in("user_id", values: ids)
            .execute()
        return profs.value
    }

    // MARK: - Leaderboard
    func fetchTopGifters(limit: Int = 100) async throws -> [DBTopGifter] {
        let res: PostgrestResponse<[DBTopGifter]> = try await client
            .from("top_gifters")
            .select("*")
            .order("tokens_sent", ascending: false)
            .limit(limit)
            .execute()
        return res.value
    }

    // MARK: - Moderation (Filtered words)
    func fetchFilteredWords() async throws -> [String] {
        guard let me = user?.id.uuidString else { return [] }
        let res: PostgrestResponse<[DBFilteredWord]> = try await client
            .from("filtered_words")
            .select("word")
            .eq("user_id", value: me)
            .order("created_at", ascending: false)
            .execute()
        return res.value.map { $0.word }
    }

    // Fetch filtered words for a specific user (e.g., host of a live)
    func fetchFilteredWords(for userId: String) async throws -> [String] {
        let res: PostgrestResponse<[DBFilteredWord]> = try await client
            .from("filtered_words")
            .select("word")
            .eq("user_id", value: userId)
            .order("created_at", ascending: false)
            .execute()
        return res.value.map { $0.word }
    }

    func addFilteredWord(_ word: String) async throws {
        guard let me = user?.id.uuidString else { return }
        _ = try await client
            .from("filtered_words")
            .insert([["user_id": me, "word": word]])
            .execute()
    }

    func removeFilteredWord(_ word: String) async throws {
        guard let me = user?.id.uuidString else { return }
        _ = try await client
            .from("filtered_words")
            .delete()
            .eq("user_id", value: me)
            .eq("word", value: word)
            .execute()
    }

    // Moderation helpers for host (Edge Functions)
    func addHostFilteredWord(hostId: String, word: String) async throws {
        let functionURL = SupabaseConfig.url.appendingPathComponent("functions/v1/add-host-filtered-word")
        var req = URLRequest(url: functionURL)
        req.httpMethod = "POST"
        req.addValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        if let token = try? await client.auth.session.accessToken { req.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["hostId": hostId, "word": word])
        let (_, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw URLError(.badServerResponse) }
    }

    func removeHostFilteredWord(hostId: String, word: String) async throws {
        let functionURL = SupabaseConfig.url.appendingPathComponent("functions/v1/remove-host-filtered-word")
        var req = URLRequest(url: functionURL)
        req.httpMethod = "POST"
        req.addValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        if let token = try? await client.auth.session.accessToken { req.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["hostId": hostId, "word": word])
        let (_, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw URLError(.badServerResponse) }
    }

    func blockUserForHost(hostId: String, targetUserId: String) async throws {
        let functionURL = SupabaseConfig.url.appendingPathComponent("functions/v1/host-block-user")
        var req = URLRequest(url: functionURL)
        req.httpMethod = "POST"
        req.addValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        if let token = try? await client.auth.session.accessToken { req.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["hostId": hostId, "targetUserId": targetUserId])
        let (_, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw URLError(.badServerResponse) }
    }

    func isModeratorOfHost(hostId: String) async -> Bool {
        guard let me = user?.id.uuidString else { return false }
        struct Row: Decodable { let moderator_user_id: String }
        if let res: PostgrestResponse<[Row]> = try? await client
            .from("live_moderators")
            .select("moderator_user_id")
            .eq("host_id", value: hostId)
            .eq("moderator_user_id", value: me)
            .limit(1)
            .execute() {
            return !res.value.isEmpty
        }
        return false
    }

    // MARK: - Moderation: blocks, mutes, moderators
    /// Whether current user is blocked by another user (e.g., host).
    func isUserBlockedBy(userId blockerId: String) async throws -> Bool {
        guard let me = user?.id.uuidString else { return false }
        struct Row: Decodable { let blocked_user_id: String }
        let res: PostgrestResponse<[Row]> = try await client
            .from("user_blocks")
            .select("blocked_user_id")
            .eq("blocker_user_id", value: blockerId)
            .eq("blocked_user_id", value: me)
            .limit(1)
            .execute()
        return !res.value.isEmpty
    }

    /// Live moderators for a host (persistent across streams)
    func fetchLiveModerators(hostId: String) async throws -> [DBProfile] {
        struct Row: Decodable { let moderator_user_id: String }
        let res: PostgrestResponse<[Row]> = try await client
            .from("live_moderators")
            .select("moderator_user_id")
            .eq("host_id", value: hostId)
            .execute()
        let ids = res.value.map { $0.moderator_user_id }
        return try await fetchProfilesByUserIds(ids)
    }

    func addLiveModerator(hostId: String, moderatorUserId: String) async throws {
        _ = try await client
            .from("live_moderators")
            .insert([["host_id": hostId, "moderator_user_id": moderatorUserId]])
            .execute()
    }

    func removeLiveModerator(hostId: String, moderatorUserId: String) async throws {
        _ = try await client
            .from("live_moderators")
            .delete()
            .eq("host_id", value: hostId)
            .eq("moderator_user_id", value: moderatorUserId)
            .execute()
    }

    /// Mutes for a host (viewer comments should be dropped on client if muted)
    func isUserMutedBy(hostId: String) async throws -> Bool {
        guard let me = user?.id.uuidString else { return false }
        struct Row: Decodable { let muted_user_id: String }
        let res: PostgrestResponse<[Row]> = try await client
            .from("live_mutes")
            .select("muted_user_id")
            .eq("host_id", value: hostId)
            .eq("muted_user_id", value: me)
            .limit(1)
            .execute()
        return !res.value.isEmpty
    }

    func muteUser(hostId: String, targetUserId: String) async throws {
        _ = try await client
            .from("live_mutes")
            .insert([["host_id": hostId, "muted_user_id": targetUserId]])
            .execute()
    }

    func unmuteUser(hostId: String, targetUserId: String) async throws {
        _ = try await client
            .from("live_mutes")
            .delete()
            .eq("host_id", value: hostId)
            .eq("muted_user_id", value: targetUserId)
            .execute()
    }

    func fetchMutedUsers(hostId: String, limit: Int = 200) async throws -> [DBProfile] {
        struct Row: Decodable { let muted_user_id: String }
        let res: PostgrestResponse<[Row]> = try await client
            .from("live_mutes")
            .select("muted_user_id")
            .eq("host_id", value: hostId)
            .limit(limit)
            .execute()
        let ids = res.value.map { $0.muted_user_id }
        return try await fetchProfilesByUserIds(ids)
    }

    // MARK: - Account counts
    func giftCounts(userId: String) async throws -> (sent: Int, received: Int) {
        let sentRes: PostgrestResponse<[CountRow]> = try await client
            .from("gift_sent")
            .select("id")
            .eq("gifter", value: userId)
            .execute()
        let recvRes: PostgrestResponse<[CountRow]> = try await client
            .from("gift_sent")
            .select("id")
            .eq("recipient", value: userId)
            .execute()
        return (sentRes.value.count, recvRes.value.count)
    }

    func wishlistCounts(userId: String) async throws -> (open: Int, fulfilled: Int) {
        let openRes: PostgrestResponse<[CountRow]> = try await client
            .from("wishlists")
            .select("id")
            .eq("user_id", value: userId)
            .eq("is_fulfilled", value: false)
            .execute()
        let fullRes: PostgrestResponse<[CountRow]> = try await client
            .from("wishlists")
            .select("id")
            .eq("user_id", value: userId)
            .eq("is_fulfilled", value: true)
            .execute()
        return (openRes.value.count, fullRes.value.count)
    }

    // MARK: - Report user
    func reportUser(reportedUserId: String, reason: String) async throws {
        let functionURL = SupabaseConfig.url.appendingPathComponent("functions/v1/report-user")
        var req = URLRequest(url: functionURL)
        req.httpMethod = "POST"
        req.addValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        if let token = try? await client.auth.session.accessToken {
            req.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload = ["reportedUserId": reportedUserId, "reason": reason]
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (_, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }

    // MARK: - User search (by username prefix)
    func searchUsers(prefix: String, limit: Int = 10) async throws -> [DBProfile] {
        guard !prefix.isEmpty else { return [] }
        var builder = client
            .from("profiles")
            .select("user_id,username,image")
            .ilike("username", pattern: "\(prefix)%")
        if let me = user?.id.uuidString {
            builder = builder.neq("user_id", value: me)
        }
        let res: PostgrestResponse<[DBProfile]> = try await builder.limit(limit).execute()
        return res.value
    }

    // MARK: - Social actions (Repost)
    func repostCount(postId: String) async throws -> Int {
        let res: PostgrestResponse<[CountRow]> = try await client
            .from("post_interaction")
            .select("id")
            .eq("post_id", value: postId)
            .eq("type", value: "repost")
            .execute()
        return res.value.count
    }

    func hasReposted(postId: String) async throws -> Bool {
        guard let me = user?.id.uuidString else { return false }
        let res: PostgrestResponse<[CountRow]> = try await client
            .from("post_interaction")
            .select("id")
            .eq("post_id", value: postId)
            .eq("type", value: "repost")
            .eq("user_id", value: me)
            .limit(1)
            .execute()
        return !res.value.isEmpty
    }

    func addRepost(postId: String) async throws {
        guard let me = user?.id.uuidString else { return }
        struct Row: Encodable { let post_id: String; let user_id: String; let type: String }
        _ = try await client
            .from("post_interaction")
            .insert([Row(post_id: postId, user_id: me, type: "repost")])
            .execute()
    }

    // MARK: - Post details for hydration (profile viewer)
    func fetchPostContent(postId: String) async throws -> String? {
        struct Row: Decodable { let content: String? }
        let res: PostgrestResponse<[Row]> = try await client
            .from("posts")
            .select("content")
            .eq("id", value: postId)
            .limit(1)
            .execute()
        return res.value.first?.content
    }

    func likeCount(postId: String) async throws -> Int {
        let res: PostgrestResponse<[CountRow]> = try await client
            .from("post_reactions")
            .select("id")
            .eq("post_id", value: postId)
            .eq("type", value: "like")
            .execute()
        return res.value.count
    }

    func commentCount(postId: String) async throws -> Int {
        let res: PostgrestResponse<[CountRow]> = try await client
            .from("comments")
            .select("id")
            .eq("post_id", value: postId)
            .execute()
        return res.value.count
    }

    // MARK: - Safe delete (archive) Posts & Wishlists
    func deletePost(id: String) async throws {
        _ = try await client
            .from("posts")
            .delete()
            .eq("id", value: id)
            .execute()
    }
    func deleteWishlist(id: String) async throws {
        _ = try await client
            .from("wishlists")
            .delete()
            .eq("id", value: id)
            .execute()
    }
}
