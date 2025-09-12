import SwiftUI
import UIKit
import UserNotifications

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String, completionHandler: @escaping () -> Void) {
        BackgroundUploadManager.shared.setBackgroundCompletionHandler(completionHandler)
    }

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        // Request push authorization and register for remote notifications
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            if granted {
                DispatchQueue.main.async { UIApplication.shared.registerForRemoteNotifications() }
            }
        }
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        // Convert device token to hex string
        let token = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        // Persist token locally so we can upsert after login if not logged in yet
        UserDefaults.standard.set(token, forKey: "apns_device_token_hex")
        Task {
            // Upsert APNs token into user_device_tokens
            let me = SupabaseManager.shared.user?.id.uuidString
            guard me != nil else { return }
            _ = try? await SupabaseManager.shared.client
                .from("user_device_tokens")
                .upsert([[
                    "user_id": me!,
                    "platform": "ios",
                    "provider": "apns",
                    "token": token,
                    "app_version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
                ]])
                .select("user_id")
                .execute()
        }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        #if DEBUG
        print("APNs registration failed: \(error)")
        #endif
    }

    // Present notifications while app is in foreground (banner + sound)
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound, .badge])
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
                } else if supabase.needsUsernameSetup {
                    UsernameOnboardingView()
                } else {
                    MainTabView(deepLink: $deepLink)
                }
            }
            // After login, if we have a cached APNs token, upsert it (iOS 14+ compatible)
            .onChange(of: supabase.user) { newUser in
                if let user = newUser,
                   let token = UserDefaults.standard.string(forKey: "apns_device_token_hex"),
                   !token.isEmpty {
                    Task {
                        _ = try? await SupabaseManager.shared.client
                            .from("user_device_tokens")
                            .upsert([[
                                "user_id": user.id.uuidString,
                                "platform": "ios",
                                "provider": "apns",
                                "token": token,
                                "app_version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
                            ]])
                            .select("user_id")
                            .execute()
                    }
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
