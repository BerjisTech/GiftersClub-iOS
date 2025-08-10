import Foundation
import Combine
import Supabase

final class SupabaseManager: ObservableObject {
    static let shared = SupabaseManager()

    let client: SupabaseClient

    @Published var user: Auth.User?
    @Published var isLoading: Bool = true

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

        // Listen to auth state changes (Supabase Swift async sequence)
        Task.detached { [weak self] in
            guard let self else { return }
            for await state in self.client.auth.authStateChanges {
                await MainActor.run {
                    self.setUser(state.session)
                }
                if state.event == .signedIn, let user = state.session?.user {
                    await self.ensureProfile(user: user)
                }
            }
        }
    }

    @MainActor
    func signInWithGoogle() async {
        do {
            // ASWebAuthenticationSession variant auto-handles the web flow
            _ = try await client.auth.signInWithOAuth(
                provider: .google,
                redirectTo: SupabaseConfig.redirectURL
            )
        } catch {
            print("Google OAuth start failed: \(error)")
        }
    }

    func signOut() async {
        do { try await client.auth.signOut() } catch { print("Sign out failed: \(error)") }
    }

    func handleOpenURL(_ url: URL) {
        // Hand off OAuth callback to Supabase
        client.auth.handle(url)
    }

    // TODO: mirror Angular's handleProfile (create/update profile row)
    func ensureProfile(user: Auth.User) async {
        // Example (uncomment and adapt to your schema):
        // struct Profile: Codable { let user_id: String; let email: String? }
        // do {
        //     let existing: [Profile] = try await client.database
        //         .from("profiles")
        //         .select()
        //         .eq("user_id", value: user.id)
        //         .execute()
        //         .decoded()
        //     if existing.isEmpty {
        //         try await client.database.from("profiles").insert(values: [
        //             ["user_id": user.id, "email": user.email ?? ""]
        //         ]).execute()
        //     }
        // } catch { print("ensureProfile error: \(error)") }
    }

    // MARK: - Data Models (Decodable)
    struct DBProfile: Decodable {
        let user_id: String
        let username: String
        let name: String?
        let bio: String?
        let image: String?
        let followers_count: Int?
        let following_count: Int?
        let token_balance: Int?
        let tokens_sent: Int?
        let tokens_received: Int?
    }

    struct DBPost: Decodable { let id: String; let user_id: String }
    struct DBPostMedia: Decodable { let post_id: String; let url: String; let order: Int? }
    struct DBWishlist: Decodable { let id: String; let title: String? }
    struct DBGift: Decodable { let id: String; let name: String?; let tokens: Int?; let image: String? }
    struct DBBlocked: Decodable { let blocked_user_id: String }
    struct DBFilteredWord: Decodable { let word: String }
    struct CountRow: Decodable { let id: String }

    // MARK: - Feed RPC DTOs
    struct FeedRPCProfile: Decodable { let id: String?; let user_id: String?; let username: String?; let image: String? }
    struct FeedRPCMedia: Decodable { let id: String?; let media_type: String?; let url: String?; let order: Int?; let created_at: String? }
    struct FeedRPCRow: Decodable {
        let id: String
        let user_id: String
        let content: String?
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

    // MARK: - Comments
    struct DBCommentRow: Decodable {
        let id: String
        let post_id: String
        let user_id: String
        let content: String
        let created_at: String?
        let profile: DBProfile?
    }

    func fetchComments(postId: String, limit: Int = 50, offset: Int = 0) async throws -> [DBCommentRow] {
        // Attempt to embed profile fields from profiles table (PostgREST embedded resource)
        let select = "id,post_id,user_id,content,created_at,profile:profiles(user_id,username,image)"
        let res: PostgrestResponse<[DBCommentRow]> = try await client
            .from("comments")
            .select(select)
            .eq("post_id", value: postId)
            .order("created_at", ascending: false)
            .limit(limit)
            .execute()
        return res.value
    }

    struct InsertComment: Encodable { let post_id: String; let user_id: String; let content: String }
    func addComment(postId: String, content: String) async throws -> DBCommentRow? {
        guard let me = user?.id.uuidString else { return nil }
        let payload = InsertComment(post_id: postId, user_id: me, content: content)
        let res: PostgrestResponse<[DBCommentRow]> = try await client
            .from("comments")
            .insert([payload])
            .select("id,post_id,user_id,content,created_at,profile:profiles(user_id,username,image)")
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

    // MARK: - Functions helpers
    func currentAccessToken() async -> String? {
        return try? await client.auth.session.accessToken
    }

    struct PresignRequest: Encodable {
        let fileName: String
        let fileType: String
        let bucket: String
        let overwrite: Bool
    }
    struct PresignResponse: Decodable { let uploadUrl: String; let publicUrl: String }

    /// Upload avatar bytes to S3 via Supabase Edge Function and return the public URL
    func uploadAvatar(imageData: Data, mimeType: String = "image/jpeg") async throws -> String {
        guard let me = user?.id.uuidString else { throw URLError(.userAuthenticationRequired) }
        let filename = "profile-\(me).jpg"
        // Call Edge Function to get presigned URL
        let functionURL = SupabaseConfig.url.appendingPathComponent("functions/v1/upload-media")
        var req = URLRequest(url: functionURL)
        req.httpMethod = "POST"
        req.addValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        if let token = await currentAccessToken() {
            req.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = PresignRequest(fileName: filename, fileType: mimeType, bucket: "profile", overwrite: true)
        req.httpBody = try JSONEncoder().encode(body)
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let presign = try JSONDecoder().decode(PresignResponse.self, from: data)
        // PUT to S3
        guard let uploadURL = URL(string: presign.uploadUrl) else { throw URLError(.badURL) }
        var put = URLRequest(url: uploadURL)
        put.httpMethod = "PUT"
        put.addValue(mimeType, forHTTPHeaderField: "Content-Type")
        let _ = try await URLSession.shared.upload(for: put, from: imageData)
        return presign.publicUrl
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
}
