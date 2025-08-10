UI/UX Guide for GiftersClub iOS

Design Principles
- Native first: Lean into SwiftUI, SF Symbols, system typography, dynamic materials, and gestures.
- Fast, optimistic, forgiving: Reflect actions instantly; reconcile in background; provide clear recovery.
- Lightweight motion: Use subtle springs, parallax, and blur; reduce motion when requested.
- Reachability: Primary actions near thumb reach; large tap targets; adequate spacing.
- Consistency: Shared tokens (gradients, radii, spacing) across iOS/Android/Web with iOS-appropriate styling.

Overview
- Purpose: Align iOS UI with existing Angular (web) and Kotlin (Android) implementations while applying iOS-native patterns and your new requirements.
- Sources: Angular repo `gifter-club` and Android repo `GiftersClub` (Kotlin). Concrete references are listed at the end.

Navigation
- App shell: `NavigationStack` wrapping primary views. Use `.toolbar` for actions; respect safe areas.
- Top Bar: Centered title, right: search icon; left: reserved future action (hidden/disabled for now).
- Tabs at Top: A pinned top control under navigation (SegmentedControl-style) that remains sticky during scroll.
  - Home tabs: Following, For You, Live.
  - Search tabs: Top, Users, Videos, Photos, Live (parity with Angular Posts).
  - Use swipeable tabs with a snapping animated indicator; keep scroll position per tab.
  - Prefer `Picker` with `.segmented` style for accessibility; enhance with a custom indicator when needed.

Visual Language
- Materials: Use `.ultraThinMaterial` for overlays (nav bars, toolbars over content) where appropriate.
- SF Symbols: Prefer SF Symbols for icons (search, camera, video, flash, timer, filters, like, share).
- Typography: System fonts with Dynamic Type; use variable weights for emphasis.
- Cards: Subtle corner radius (12–16pt) and soft shadows; content-first design.

Notifications
- No default toasts: Do not use iOS system toasts or snackbars by default.
- Bottom Drawer “toast”: For interactive/important feedback, present a custom bottom drawer that slides up from bottom, dismissible by swipe-down or tapping an X, with rounded top corners 10pt or 20pt (match this app-wide; recommended 20pt). Supports title, message, primary/secondary actions.
- Simple banners: For simple confirmations (e.g., “Your post has been created”), show a non-modal full-width banner at the top with 8pt margins on all sides, auto-dismiss after 3–5s, tappable to navigate if applicable. Use contextual background color and icon.

Buttons and States
- Shape: 10pt corner radius for all buttons.
- Gradients: Replace flat system colors with gradients.
  - Primary (sky-blue): e.g., #00C6FF → #0072FF
  - Danger (orange-red): e.g., #FF7E5F → #FF3D00
  - Success (green): e.g., #00E676 → #00BFA5
  - Warning (amber): e.g., #FFC107 → #FF9800
  - Secondary/Neutral: subtle slate/indigo gradient or filled gray per design needs
- Gradient animation on state change: If feasible, animate gradient background when transitioning states (loading → success → error) by animating the gradient layer’s colors. On iOS, animate `CAGradientLayer.colors` with `CABasicAnimation` or `CAKeyframeAnimation`.
- Loading state: Inline spinner inside the button at the trailing side; button remains readable; optionally dim text to 80%.
- Haptics: Light impact for success, error notification feedback for failures.

Motion & Micro‑interactions
- Use spring animations for tab changes, like pulses on “like” (double-tap) with a heart burst.
- Parallax on post images and video hover; subtle blur on background when presenting drawers.
- Animate list insertions/removals using `.transaction` and matched geometry for media previews.

Feed and Interactions
- Optimistic UI: Any action (like, comment, share, follow, delete) updates UI immediately while the backend completes in the background.
- Reload posts on actions: After actions complete, refresh the affected post or the visible feed page. Favor surgical refresh (single post) when possible; fall back to re-query current page.
- Action feedback: Use bottom drawer for failures or multi-step confirmations; use top banner for simple success notifications.
- Skeleton loading: Use shimmer placeholders for feed/cards similar to Angular `ShimmerComponent`.
- Autoplay: Videos should autoplay muted when ≥60% visible; pause when off-screen; tap to unmute.
- Visibility: Track cell visibility to manage AVPlayer resources and prevent audio overlap.
- Gestures: Support double-tap like; long-press context menu for share, copy link, report.
- Paging: Vertical paged feed for full-screen media; or continuous scrolling with compositional grid for explore.

Create Post Flow
Step 1 — Camera View (default landing)
- Top-right vertical stack: from top to bottom: switch front/back camera, flash, timer, filters.
- Bottom controls are two rows:
  - Row 1 (presets): Zoom presets 1x, 2x, 4x, 8x; then a 1pt vertical separator; then timer presets 10m, 60s, 15s, 5s in that order. Show selected state clearly.
  - Row 2 (modes/actions): Left: filter presets scroller; Center: large capture button (tap = photo, long-press = video if in photo mode); Right: mode toggle video/camera, create text post, select media from device.
- Zoom: Support both presets and pinch-to-zoom; display current zoom.
- Timer: Support presets plus a custom picker from the vertical timer icon.
- Filters: Show quick presets, with an advanced filters panel accessible from the top-right filters icon.

iOS Camera Implementation Notes
- Use `AVCaptureSession` with separate inputs for front/back; toggle via `AVCaptureDevice.Position`.
- Zoom: pinch-to-zoom via `ramp(toVideoZoomFactor:)` with clamping; presets update the zoom factor.
- Focus/Exposure: tap-to-focus with animated reticle; auto unlock after timer lapse.
- Flash/Torch: handle photo and video separately; surface torch availability.
- Recording: hold-to-record with progress ring around the capture button; timer presets auto-stop recording.
- Filters: Apply Core Image filters (e.g., CIPhotoEffect, CISepia, CIColorControls) in preview and export pipelines.
- Performance: Use `Metal`-backed `MTKView` or `CIContext` for real-time filters when needed.

Step 2 — Editing
- If “Create Text Post” selected: Navigate to a text canvas screen where user enters and formats centered text.
  - Formatting: bold/italic/underline, font family, font size, alignment.
  - Colors: text color picker and background color or image/gradient pickers.
  - Backgrounds: Offer curated gradient backgrounds inspired by Android’s `bg_*_gradient` drawables.
- If photo selected/captured: Navigate to image edit screen with filters, intensity slider, optional crop/rotate.
- If video selected/recorded: Skip editing for now, proceed to Step 3.

Text Post Editor (iOS‑specific polish)
- Canvas: `ZStack` with background gradient/image + centered multiline `TextEditor`.
- Formatting: toolbar above keyboard with bold/italic/underline; alignment toggles; font family/size pickers.
- Colors: popovers for text and background color; swatches + full color picker; contrast previews.
- Backgrounds: curated gradients and images; live preview; optional animated gradients for success states.
- Stickers (optional): allow future sticker overlays; keep model extensible.

Step 3 — Details and Publish
- Fields: Post description/content; access type (Free for all, Subscribers only, Paid one-time); if Paid, show price input.
- Create button: Triggers background post creation. Persist to `public.posts`, `public.post_media` and upload media to S3 (or configured storage) in the background.
- Navigation during upload: Immediately navigate users back to the Home/Posts feed so they stay engaged.
- Completion: Show top banner “Your post has been created”. Tapping banner navigates to the created post.
- Backgrounding: Use `Task` to continue upload when navigating away; show progress in a subtle banner if lengthy.

Search
- Entry: Tap the top-right search icon to open a full search screen.
- Tabs: Top, Users, Videos, Photos, Live (mirrors Angular search tabs).
- Typeahead: Show suggestions under the search field while typing (min 2 chars), with a loading indicator.
- Results: Each tab shows relevant results; tapping an item records the event (analytics) and navigates.
- iOS patterns: Prefer `.searchable(text:prompt:)` with `.searchScopes` for tabs; show suggestions using `SearchCompletion` style; animate empty/result transitions.
- Keyboard: Dismiss on scroll; keep recent searches; provide clear button and cancel button semantics.

Profile
- Parity with Android: Mirror Android profile layout—avatar, display name, @username, bio, counts, action buttons, and a grid/list of posts. Use iOS-native controls and `UICollectionViewCompositionalLayout` for grids.
- Editing: Separate Profile Settings screen with avatar picker/crop, username, display name, bio. Use bottom drawer for errors; top banner for simple success messages.
- Highlights: Add profile header collapse-on-scroll with stretchy avatar; context menu for share/report; follow state animated.
- Posts grid: Use `LazyVGrid` in SwiftUI (or Compositional Layout in UIKit) with prefetching and cached thumbnails.

Bottom Drawer (Custom)
- Presentation: Custom container or `UISheetPresentationController` with detents (compact for “toasts”, medium for confirm dialogs). Rounded top corners 20pt recommended, 10pt acceptable if space constrained.
- Content: Title, message, primary/secondary buttons. Support drag-to-dismiss and tap outside to dismiss when appropriate.
- Use cases: Purchase/subscription prompts, multi-step confirmations, errors with recovery actions.
- SwiftUI API: `.sheet` with `.presentationDetents([.height(120), .medium])`, `.presentationCornerRadius(20)`, `.presentationBackground(.ultraThinMaterial)`; wrap UIKit for fully custom grabber/indicator when needed.

Top Banners (Simple Notifications)
- Layout: Full-width banner with 8pt margins all around; drop shadow 8–12%; rounded corners 10pt.
- Semantics: Success (green gradient), Info (sky blue), Warning (amber), Error (orange-red). Include an icon and concise text.
- Behavior: Slide-in from top, auto-dismiss after 3–5s. Tappable to navigate when relevant.
- Queueing: Maintain a queue with dedupe; avoid overlapping; VoiceOver announces role and action.

Loading, Empty, Errors
- Shimmer loading: Apply shimmer to cards/rows during fetch.
- Empty states: Use purposeful illustrations and “Try again”/“Explore” CTA.
- Error states: Use bottom drawer with retry actions for blocking errors; top banner for recovered operations.
- Pull-to-refresh: Use `.refreshable` on scrollable lists; merges with optimistic updates.

Theming
- Light/Dark support: Ensure gradients and text contrast meet accessibility in dark mode.
- Tokens: Centralize gradients and radii in a theme module so Android, iOS, and Web can stay visually consistent.
  - Example tokens (iOS):
    - ButtonPrimaryGradient: sky-blue (#00C6FF → #0072FF)
    - ButtonDangerGradient: orange-red (#FF7E5F → #FF3D00)
    - ButtonSuccessGradient: emerald (#00E676 → #00BFA5)
    - CornerRadiusButton: 10pt
    - DrawerCornerRadiusTop: 20pt
- Materials: Add background materials for sheets and navbars; use vibrancy for icons over materials.
- Color assets: Centralize semantic colors in the asset catalog with light/dark variants.

Accessibility and Motion
- Dynamic Type: Respect text size changes; ensure banners/drawers scale appropriately.
- VoiceOver: Announce success/error banners and drawer presentations.
- Reduce Motion: Replace slide/gradient animations with cross-fades when Reduce Motion is enabled.
- Hit targets: ≥44×44pt; ensure controls near edges have extra insets for gesture conflicts.
- Contrast: Meet WCAG AA for text over gradients/materials.

Data/Background Work
- Background actions: Network tasks (create post, like, comment) run off the main thread; UI reflects action immediately and shows completion/failure via banners/drawers.
- Feed refresh triggers: On returning from Create Post, trigger a lightweight refresh of the top of feed. For actions like like/comment/delete, update the single item; if stale or failed, reconcile with a background fetch.
- Concurrency: Use async/await + `Task` and `@MainActor`; cancel in-flight tasks on view disappear to conserve battery.
- Background tasks: Consider `BGAppRefreshTask` for periodic sync; show unobtrusive progress when resuming.

Design Specs and Sizing
- Corner radii: Buttons 10pt; Drawer top corners 20pt (or 10pt if specified). Note: iOS points ≈ Android dp for practical sizing; follow 1:1 mapping unless device testing suggests adjustments.
- Spacing: 8/12/16/24pt system; banner margins 8pt; tab indicators 2pt thickness.
- Separator: 1pt vertical rule between zoom and timer presets in the camera step.
- Layout margins: Respect safe area; use `containerRelativeFrame` and `safeAreaInset` for immersive layouts.

Suggested iOS Components
- Top tabs: `UISegmentedControl` or custom `UICollectionView` with pinned section header for more flexible styling.
- Banners: Custom view manager attached to the window’s safe area top; queue multiple banners.
- Bottom drawer: Custom container or `UISheetPresentationController` with custom background and corner radii.
- Buttons: `UIButton` subclass backed by `CAGradientLayer` with animated `colors` transitions.
- Shimmer: SwiftUI overlay using gradient mask animation; reusable `ShimmerView`.
- Media: `AVPlayer` wrapper with visibility-driven playback and muted/unmuted states; `VideoPlayer` where acceptable.
- Image loading: `AsyncImage` with cache; low-memory handling; placeholder shimmer.

Composable Views to Implement
- `GradientButton`: State-driven gradient, 10pt radius, loading spinner, haptic feedback.
- `BannerHost`: Queued top banners with tap handling; safe-area-aware; announced via VoiceOver.
- `DrawerHost`: Reusable bottom sheet wrapper (custom or UISheetPresentationController bridge).
- `PostCardView`: Media carousel/grid, like/comment/share, avatar/username, timestamp; optimized for reuse.
- `FeedView`: Vertical paged feed (full screen) or list/grid; visibility tracking; prefetching.
- `CreatePostCameraView`: Capture, zoom, focus, flash/torch, timer; filter preview pipeline.
- `TextPostEditorView`: Canvas with formatting controls and background selector.
- `SearchView`: `.searchable` + `.searchScopes` with tabs and suggestions; results list/grid per scope.
- `ProfileView`: Collapsing header, action buttons, posts grid with pagination.

References (existing implementations)
- Angular (web):
  - Toasts: `src/app/components/ui/toast.component.ts`, `toast-container.component.ts`; Service: `src/app/services/ui/toast.service.ts`
  - Shimmer/Skeleton: `src/app/components/ui/shimmer/`
  - Posts feed/search tabs and background actions: `src/app/pages/posts/posts-page.component.ts`
- Android (Kotlin):
  - Create Post camera UI, filters, timers, text editor, and publish flow: `app/src/main/java/club/gifters/giftersclub/gifts/CreatePostFragment.kt`
  - Profile settings/editing: `app/src/main/java/club/gifters/giftersclub/settings/ProfileSettingsFragment.kt`

Open Questions / To Confirm
- Home tabs: Confirm desired top-level tabs and their ordering for iOS (e.g., Following | For You | Live vs. other).
- Gradient palette: Approve exact gradient color stops and naming for shared tokens.
- Drawer sizes: Confirm default detents for bottom drawer “toast” (compact height) and modal confirmations (medium).

Notable Differences from Android (by design)
- Swipeable tabs with animated indicator and segmented accessibility, not constrained by XML TabLayout.
- AVFoundation camera with Core Image filters rather than GPUImage; better integration and performance.
- System materials (blur) for overlays instead of opaque panels; more depth and legibility.
- SwiftUI `.searchable` and `.searchScopes` with native results suggestions.
- Visibility-driven video autoplay with energy awareness; strict resource cleanup for backgrounding.

QA Checklist (iOS)
- Dynamic Type across feed, banners, drawers, editors.
- VoiceOver navigation for posts, media, controls, and camera.
- Light/Dark mode visual checks for gradients/materials.
- Reduce Motion: verify cross-fades replacing transitions and gradient animations.
- Backgrounding uploads and action reconciliations while user navigates elsewhere.
- Video autoplay policy: respects Low Power Mode and Reduce Motion.



Screen arangement

In main/home
 
