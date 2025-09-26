import Foundation

enum SupabaseConfig {
    // Use the custom domain configured for the Supabase project
    static let url = URL(string: "https://app.gifters.club")!
    // Public anon key from Angular environment; consider secure storage for production
    static let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InhmZmh0ZXJ0b296dHl5b3R3aHJ2Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NDc5MDI0ODAsImV4cCI6MjA2MzQ3ODQ4MH0.uaLukRBX5IVWbFM8aD6-025am4WpsT94crliJPHl1pk"
    static let redirectURL = URL(string: "gifterclub://login-callback")!
    // Base URL for web app where static assets (like gifts images) are hosted
    static let webBase = URL(string: "https://gifters.club")!
    // LiveKit server URL used by the iOS client to connect to the room created by the Edge Function token
    // Example (LiveKit Cloud): wss://yourdomain.livekit.cloud
    // Example (self-hosted):  wss://your.domain:7880
    static let livekitURL = URL(string: "wss://giftersclub-1ej914uy.livekit.cloud")!
}
