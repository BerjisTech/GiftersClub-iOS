import SwiftUI

@main
struct GiftersClubApp: App {
    @StateObject private var supabase = SupabaseManager.shared
    @State private var deepLink: DeepLink? = nil

    var body: some Scene {
        WindowGroup {
            Group {
                if supabase.isLoading {
                    ProgressView().progressViewStyle(.circular)
                } else if supabase.user == nil {
                    AuthView()
                } else {
                    MainTabView(deepLink: $deepLink)
                }
            }
            .onOpenURL { url in
                // OAuth callback
                if url.scheme == "gifterclub", url.host == "login-callback" {
                    supabase.handleOpenURL(url)
                    return
                }
                // App deep links
                deepLink = DeepLinkRouter.parse(url: url)
            }
        }
    }
}

