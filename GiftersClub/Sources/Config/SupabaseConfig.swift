import Foundation

enum SupabaseConfig {
    static let url = URL(string: "https://app.gifters.club")!
    // Public anon key from Angular environment; consider secure storage for production
    static let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InhmZmh0ZXJ0b296dHl5b3R3aHJ2Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NDc5MDI0ODAsImV4cCI6MjA2MzQ3ODQ4MH0.uaLukRBX5IVWbFM8aD6-025am4WpsT94crliJPHl1pk"
    static let redirectURL = URL(string: "gifterclub://login-callback")!
    // Base URL for web app where static assets (like gifts images) are hosted
    static let webBase = URL(string: "https://gifters.club")!
    // Hosted payment path for web-based Flutterwave checkout (backend-defined)
    static let paymentTopUpPath = "pay/topup"
    // URL scheme/host used by the app to receive web checkout callbacks
    // e.g., gifterclub://payment-callback?success=1&tx_ref=...
    static let paymentCallbackHost = "payment-callback"
    // Supabase Edge Function to initialize a token top-up session (returns checkout URL)
    // Update to match your functions repo (Angular/Kotlin parity)
    static let paymentTopUpFunctionName = "purchase-tokens-init"
    // Supabase Edge Function to validate IAP and credit tokens
    static let iapPurchaseFunctionName = "purchase-tokens-iap"
    // Flutterwave public key from Angular/Kotlin
    #if DEBUG
    static let flutterwavePublicKey = "FLWPUBK_TEST-d9ddd8396154af47423b8e55dc5c1f69-X"
    #else
    static let flutterwavePublicKey = "FLWPUBK-23f4ab7e7dfd648de9c957acd063b30d-X"
    #endif

    // LiveKit server URL used by the iOS client to connect to the room created by the Edge Function token
    // Example (LiveKit Cloud): wss://yourdomain.livekit.cloud
    // Example (self-hosted):  wss://your.domain:7880
    static let livekitURL = URL(string: "wss://giftersclub-1ej914uy.livekit.cloud")!
}
