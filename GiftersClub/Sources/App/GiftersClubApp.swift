import SwiftUI
import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String, completionHandler: @escaping () -> Void) {
        BackgroundUploadManager.shared.setBackgroundCompletionHandler(completionHandler)
    }
}

@main
struct GiftersClubApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var supabase = SupabaseManager.shared
    @State private var deepLink: DeepLink? = nil

    var body: some Scene {
        WindowGroup {
            Group {
                if supabase.isLoading {
                    LoadingOverlay(isPresented: true)
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
                // Payment callback (web checkout)
                if url.scheme == "gifterclub", url.host == "payment-callback" {
                    PaymentCoordinator.shared.handleWebCallback(url)
                    return
                }
                // App deep links
                deepLink = DeepLinkRouter.parse(url: url)
            }
        }
    }
}
