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
        do {
            // Load current session
            let session = try await client.auth.session
            await MainActor.run { self.setUser(session) }

            // Listen to auth state changes
            client.auth.addStateChangeListener { [weak self] event, session in
                guard let self else { return }
                Task { @MainActor in
                    self.setUser(session)
                }
                if case .signedIn = event, let user = session?.user {
                    Task { await self.ensureProfile(user: user) }
                }
            }
        } catch {
            await MainActor.run { self.isLoading = false }
            print("Failed to get session: \(error)")
        }
    }

    func signInWithGoogle() async {
        do {
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
        _ = client.auth.sessionManager.handle(url: url)
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
}

