# TODO

- Add AppIcon from logo and configure Icons in Xcode
- Wire Tailwind color assets into UI components (tabs, buttons, backgrounds)
- Add dark-mode gradient variants matching Angular’s dark styles
- Design and produce branded icon set (app icon, tab icons, toolbar, placeholders) to replace Google/Material placeholders across iOS/Android/Angular; export platform-specific sizes
- Replace current tab/system icons with branded icons once assets are ready (update Assets.xcassets and usages)
- Complete Supabase profile creation/update in `SupabaseService.ensureProfile` to mirror Angular/Android logic

## Accessibility Support (iPhone)
- Overall criteria: Users must complete common tasks (onboarding, changing settings, posting, viewing, gifting, messaging) using each supported feature.

- Dark Interface — Supported
  - Keep as fully supported; verify all views render correctly in dark mode and avoid contrast regressions when assets change.

- Larger Text — Supported (verify, improve)
  - Audit text to ensure Dynamic Type is used everywhere; replace fixed font sizes with semantic styles where feasible.
  - Ensure layouts adapt for XL–XXXL sizes (no clipped or overlapping text).

- VoiceOver — Not yet supported
  - Replace tap gestures on non-accessible views with `Button` where appropriate or add `.accessibilityLabel`, `.accessibilityHint`, and custom `accessibilityActions` for like, comment, share, follow, open profile, etc.
  - Define logical accessibility order and grouping for Feed cells, Live cards, Paywall, and Create Post flows.
  - Provide labels for dynamic controls (token amounts, gift names, viewer counts) and images (creator avatars, thumbnails) with useful alt text.

- Voice Control — Not yet supported
  - Ensure actionable elements are real controls (`Button`, `Toggle`, `TextField`) with visible labels matching their accessibility labels to support voice commands.
  - Avoid gesture-only interactions where possible or provide explicit controls.

- Differentiate Without Color Alone — Not yet supported
  - Add non-color cues (icons, text, patterns, underline) wherever color indicates state (liked vs not, selected tabs, badges).
  - Ensure form validation and status messages include icons/text, not just color.

- Sufficient Contrast — Needs audit
  - Run contrast checks on secondary text over imagery/gradients; raise opacity or adjust colors to meet WCAG 4.5:1 for normal text.
  - Verify overlays (e.g., hashtags, counters) against background video/images.

- Reduced Motion — Not yet supported
  - Respect `@Environment(\.accessibilityReduceMotion)` and replace scale/blur/zoom and Lottie animations with fades or static states.
  - Gate video autoplay/motion-heavy effects when Reduce Motion is on.

- Captions — Not yet supported
  - Add caption support for user videos (e.g., WebVTT/SRT attachment, toggle in player UI).
  - Provide creator tooling to upload captions in Create Post; store and deliver with media.

- Audio Descriptions — Not yet supported
  - Allow attaching and selecting an audio description track in the player.
  - Document guidance for creators to add descriptions; add UI affordance to toggle descriptions.

Acceptance checklist before marking “Yes” in App Store Connect:
- [ ] VO/VC users can complete onboarding, browse feed, like/comment/share, open profiles, start chats, purchase tokens, and subscribe.
- [ ] All text scales with Larger Text without truncation.
- [ ] Non-color indicators exist for all color-coded states; contrast meets WCAG.
- [ ] Animations respond to Reduce Motion; autoplay behavior adjusted.
- [ ] Video player supports captions; audio descriptions available where provided.


> Roger that. Once Apple approves the address/bank/tax updates, here’s the quick path to green:

  Next Steps

  - Verify “Paid Apps Agreement” = Active (Agreements, Tax, and Banking).
  - Confirm each token_… IAP is Cleared for Sale, priced, localized, and linked to your submitted version.
  - Install latest TestFlight build on device → Profile → Buy Tokens → tap Reload. Expect prices + Buy button.
  - If still empty: capture device logs (Console → filter “StoreKit”) to confirm 0 products vs. other errors.
  - Optional now: use local StoreKit config for instant testing in Xcode (GiftersClub.storekit already added; select in Scheme → Run → Options).

  Review Notes (suggested)

  - Provide test login credentials (if required before purchase).
  - Steps: Profile → Buy Tokens → choose token_100 → confirm.
  - Expected: tokens credited, balance updates, success toast.
  - Clarify IAP runs via Apple sandbox in TestFlight.

  Ping me when the 24h passes—happy to sanity-check the ASC state and help you verify on-device before re-submitting.


  # User reports
  - add preloader animation in swiperefresh, and other areas that require loading
  - Clicking on user name in chat it should go to the user profile
  - in create post, selecting from media sometimes doesn't send user to edit step bu directly recording or taking a photo does
  - still in create post, uploading a post sometimes takes time like a heavy video, so add a ui indicator like the one in android that tells user "post uploading in background" so they stop complaining about seeing a post they uploaded if the post is still actually uploading in background
  - do better caching
  -------------------------------------------------------------------------------------
  - delete message options. whole conversation and spercific messages in conversation