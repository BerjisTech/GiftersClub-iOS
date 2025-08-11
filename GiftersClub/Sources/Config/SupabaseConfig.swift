import Foundation

enum SupabaseConfig {
    static let url = URL(string: "https://xffhtertooztyyotwhrv.supabase.co")!
    // Public anon key from Angular environment; consider secure storage for production
    static let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InhmZmh0ZXJ0b296dHl5b3R3aHJ2Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NDc5MDI0ODAsImV4cCI6MjA2MzQ3ODQ4MH0.uaLukRBX5IVWbFM8aD6-025am4WpsT94crliJPHl1pk"
    static let redirectURL = URL(string: "gifterclub://login-callback")!
    // Base URL for web app where static assets (like gifts images) are hosted
    static let webBase = URL(string: "https://gifter.club")!
    // Flutterwave public key (set to your live or test key)
    static let flutterwavePublicKey = "" // TODO: fill with your public key
}
