# GiftersClub (iOS)

SwiftUI iOS app that mirrors the Android `GiftersClub` and the Angular `gifter-club` auth and main navigation.

## Overview

- Supabase Google OAuth for sign-in (same project/keys as Angular).
- Root router that shows `AuthView` when signed out, `MainTabView` when signed in.
- Deep links:
  - `gifterclub://login-callback` (OAuth return)
  - `gifterclub://wishlist/<id>` (open wishlist detail)
  - `gifterclub://u/<username>` and `gifterclub://g/<username>` (open gifter profile)

## Setup

1) Open an Xcode iOS App project named `GiftersClub` (SwiftUI, Swift). Then add the files in `GiftersClub-iOS/Sources/*` to your project.

2) Add Supabase Swift SDK via Swift Package Manager:

   - File > Add Packages…
   - Enter: `https://github.com/supabase-community/supabase-swift`
   - Add `Supabase` package to the `GiftersClub` target.

3) Configure URL Schemes (Info tab > URL Types):

   - URL Schemes: `gifterclub`
   - Role: Viewer

   Also add Associated Domains if you plan to support universal links later.

4) Supabase Keys

   The app uses the same Supabase credentials as `gifter-club` Angular:

   - URL: `https://xffhtertooztyyotwhrv.supabase.co`
   - anon key: the same public key in Angular `environment.ts`

   They are centralized in `SupabaseConfig.swift`. For production, consider moving them into a plist or remote config.

5) Redirect URLs in Supabase Console

   In Supabase Auth settings, add `gifterclub://login-callback` to Redirect URLs.

6) Build and Run

   - Launch the app. Tap “Continue with Google” and complete sign-in.
   - On success, the app shows `MainTabView` with tabs (Home, Explore, Chat, Wishlists, Profile).

## Notes

- Profile creation/update logic mirrors Android/Angular but is simplified here. Fill in `ensureProfile` in `SupabaseService.swift` to match your exact schema and behavior.
- Add push notifications, update prompts, and network checks later to mirror the Android parity if needed.

