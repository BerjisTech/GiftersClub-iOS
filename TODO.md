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

  - a user noticerd that the send button only becomes blue when there's text in chat input so they have no way of posting media without text. Allow users to send photo or video or document as they choose without the need to write text
  - selecting media when creating post takes time for practically all users on iphones especially older ones like 11 to 13. When they select from device and click add or done, it takes a while before they're sent to the edit section
  - add option to delete edits like when a caption is added or a meme or a sticker.
  - users especially on smaller devices are saying the items on screen in edit section are squeezed, you can make them scroll and use the whole screen top to bottom side to side

  - some users report reset button for filter in post creation doesn't reset the filters.
  - users are requesting option to set duration that a sticker/meme/sticker stays when the media being edited is video
  - Some users are requesting autocaptions
  - Users are also requesting hashtag suggestion, ie in the details section when they type #followed by something a typeahead and a scrollable list of hashtags options based on what they've alread typed including number of times the hastag has beed used is displayed and they can tap on an option and it can be used in the description. For hashtag details check the angular project for interface.ts/interfaces.ts and migration files to see how hashtags were set up on the app





  iOS Submission
Unresolved Issues

Your app version was rejected and no other items submitted can be accepted or approved. You can make edits to your app version below.

Items Submitted (1)
You can review and make edits to your items below, or communicate with Apple. Accepted items won't be available for release until all items with issues are resubmitted and accepted. You can also remove those items and resubmit them later.
Item
Type
Review Status
Action
iOS App 1.0

1.0.9 (9)

App Version
Rejected
2.1.0 Performance: App Completeness

3.0.0 Business: Preamble

3.1.1 Business: Payments - In-App Purchase

4.0.0 Design: Preamble

4.1.0 Design: Copycats

0a4134e31478f0d260ac459a060c29876ee3afde.pngDownload
Screenshot-0918-181252.pngDownload
Screenshot-0918-181304.pngDownload
Screenshot-0918-181322.pngDownload
Edit

Messages (1)

App ReviewToday 1:21 PM
Hello,

Thank you for your efforts to follow our guidelines. There are still some issues that need your attention.

If you have any questions, we are here to help. Reply to this message in App Store Connect and let us know.

Review Environment

Submission ID: 8a130c58-056d-498c-9cb9-cbf550078713
Review date: September 18, 2025
Version reviewed: 1.0


Guideline 4.1 - Design - Copycats

The app or its metadata appears to contain potentially misleading references to third-party content.

Specifically, the app includes content that resembles Deathstroke without the necessary authorization.

Next Steps

If you have the necessary rights to distribute an app with this third-party content, attach documentary evidence in the App Review Information section in App Store Connect and reply to this message. 

If you do not have the necessary rights to the third-party content, It would be appropriate to revise the app and metadata to remove the third-party content before resubmitting for review. 

Resources

Learn more about requirements to prevent apps from impersonating other apps or services in guideline 4.1.


Guideline 4.0 - Design

Parts of the app's user interface were crowded, laid out, or displayed in a way that made it difficult to use the app when reviewed on iPad Air (5th generation) running iPadOS 26.0.

Next Steps

To resolve this issue, revise the app to ensure that the content and controls on the screen are easy to read and interact with.

Note that users expect apps they download to function on all the devices where they are available. Since your app may be downloaded onto iPad devices, it is important that it also function as expected for iPad users. 

Resources

- Learn foundational design principles from Apple designers and the developer community.
- Learn more about designing for iOS in the Human Interface Guidelines.
- See documentation for the UIKit framework.
- Learn more about design requirements in guideline 4.


Guideline 2.1 - Performance - App Completeness
Issue Description

The app exhibited one or more bugs that would negatively impact users.

Bug description: we were unable to top up tokens because all the option were not responsive when tapped on it.

Review device details:

- Device type: iPad Air (5th generation) 
- OS version: iPadOS 26.0

Next Steps

Test the app on supported devices to identify and resolve bugs and stability issues before submitting for review.

If the bug cannot be reproduced, try the following:

- For new apps, uninstall all previous versions of the app from a device, then install and follow the steps to reproduce.
- For app updates, install the new version as an update to the previous version, then follow the steps to reproduce.

Resources

- For information about testing apps and preparing them for review, see Testing a Release Build.
- To learn about troubleshooting networking issues, see Networking Overview.


Guideline 3.1.1 - Business - Payments - In-App Purchase

We noticed your app includes a mechanism that allows users to exchange in-app purchases for money. 

This is not an appropriate use of in-app purchase, since in-app purchase is designed to provide a consistent and safe experience for purchasing digital content within apps.

Next Steps

To resolve this issue, please remove any features or services that allow users to exchange in-app purchases for money.

Resources 

Learn more about appropriate uses for in-app purchase in App Review Guideline 3.1.1.


Guideline 3.0 - Business

We began our review, but we are unable to continue because we need additional information about your app.

Specifically, can you confirm that $110.99 USD, $279.00 USD, $559.00 USD, $1000.00 USD is the intended price of your in-app purchase product, token_10000, token_25000, token_50000, and token_90000? 

Once we receive your confirmation, we will continue our review. If there's additional information you'd like to provide, please include it in your response to this message in App Store Connect.


Guideline 2.1 - Information Needed

We need more information to continue the review.

Next Steps

Provide detailed answers to the following questions:

1. What is the purpose of tokens in the app?

Support
- Reply to this message in your preferred language if you need assistance. If you need additional support, use the Contact Us module.
- Consult with fellow developers and Apple engineers on the Apple Developer Forums.
- Request an App Review Appointment at Meet with Apple to discuss your app's review. Appointments subject to availability during your local business hours on Tuesdays and Thursdays.
- Provide feedback on this message and your review experience by completing a short survey.
Reply to App Review

Date Submitted
Sep 16, 2025 at 6:39 PM
Submission ID
8a130c58-056d-498c-9cb9-cbf550078713
Submitted By
Fridah Nancy
Last Updated By
Apple
Cancel Submission