import Foundation

enum SupabaseConfig {
    // Use the canonical Supabase project URL to ensure Auth, REST, Realtime, and Functions endpoints resolve correctly.
    // Custom domains can cause Functions/Realtime to fail if not fully configured.
    static let url = URL(string: "https://xffhtertooztyyotwhrv.supabase.co")!
    // Public anon key from Angular environment; consider secure storage for production
    static let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InhmZmh0ZXJ0b296dHl5b3R3aHJ2Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NDc5MDI0ODAsImV4cCI6MjA2MzQ3ODQ4MH0.uaLukRBX5IVWbFM8aD6-025am4WpsT94crliJPHl1pk"
    static let redirectURL = URL(string: "gifterclub://login-callback")!
    // Base URL for web app where static assets (like gifts images) are hosted
    static let webBase = URL(string: "https://gifters.club")!
    // Supabase Edge Function to validate IAP and credit tokens
    static let iapPurchaseFunctionName = "purchase-tokens-iap"

    // LiveKit server URL used by the iOS client to connect to the room created by the Edge Function token
    // Example (LiveKit Cloud): wss://yourdomain.livekit.cloud
    // Example (self-hosted):  wss://your.domain:7880
    static let livekitURL = URL(string: "wss://giftersclub-1ej914uy.livekit.cloud")!
}
