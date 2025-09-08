# GiftersClub (iOS)

SwiftUI iOS app that mirrors the Android `GiftersClub` and the Angular `gifter-club` auth and main navigation.

## Overview

- Native Sign in with Apple for sign-in (via Supabase Auth).
- Root router that shows `AuthView` when signed out, `MainTabView` when signed in.
- Deep links:
  - `gifterclub://login-callback` (OAuth return)
  - `gifterclub://wishlist/<id>` (open wishlist detail)
  - `gifterclub://u/<username>` and `gifterclub://g/<username>` (open gifter profile)

## Setup

1) Open the Xcode project `GiftersClub.xcodeproj`.

2) Add Supabase Swift SDK via Swift Package Manager:

   - File > Add Packages…
   - Enter: `https://github.com/supabase-community/supabase-swift`
   - Add `Supabase` package to the `GiftersClub` target.

3) Configure URL Schemes (Info tab > URL Types):

   - URL Schemes: `gifterclub`
   - Role: Viewer

   Also add Associated Domains if you plan to support universal links later.

4) Capabilities

   - Add “Sign in with Apple” capability to the app target.
   - Add “Push Notifications” if you plan to use APNs.
   - In‑App Purchase capability should be enabled on the App ID (no entitlement file needed).

5) Supabase Config

   Supabase values are centralized in `SupabaseConfig.swift` and match the Angular app (custom domain `https://app.gifters.club`). For production, consider secure storage or remote config for the anon key.

6) Redirect URLs in Supabase Console (optional)

   If you use any web-based auth or fallbacks, add `gifterclub://login-callback` to Redirect URLs. Native Sign in with Apple does not require this.

7) Build and Run

   - Launch the app. Tap “Sign in with Apple” and complete sign-in.
   - On success, the app shows `MainTabView` with tabs (Home, Explore, Chat, Wishlists, Profile).

## Notes

- Profile creation/update logic mirrors Android/Angular but is simplified here. Fill in `ensureProfile` in `SupabaseService.swift` to match your exact schema and behavior.
- Add push notifications, update prompts, and network checks later to mirror the Android parity if needed.
