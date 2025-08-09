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
    }

    struct DBPost: Decodable { let id: String; let user_id: String }
    struct DBPostMedia: Decodable { let post_id: String; let url: String; let order: Int? }
    struct DBWishlist: Decodable { let id: String; let title: String? }
    struct DBGift: Decodable { let id: String; let name: String?; let tokens: Int?; let image: String? }

    // MARK: - Profile Fetch
    func fetchProfile(username: String?, userId: String?) async throws -> DBProfile? {
        if let u = username {
            let res: PostgrestResponse<[DBProfile]> = try await client
                .from("profiles")
                .select()
                .eq("username", value: u)
                .limit(1)
                .execute()
            return res.value.first
        }
        if let id = userId {
            let res: PostgrestResponse<[DBProfile]> = try await client
                .from("profiles")
                .select()
                .eq("user_id", value: id)
                .limit(1)
                .execute()
            return res.value.first
        }
        // current user
        guard let me = user?.id.uuidString else { return nil }
        let res: PostgrestResponse<[DBProfile]> = try await client
            .from("profiles")
            .select()
            .eq("user_id", value: me)
            .limit(1)
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
}
