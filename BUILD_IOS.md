# iOS Build & TestFlight Guide (with IAP)

This guide walks you from a clean project to an uploaded build in App Store Connect (ASC), ready for TestFlight and linking your in‑app purchase `gift_token`.

## Prerequisites

- Apple Developer Program membership and access to the correct Team.
- App created in App Store Connect (name, bundle ID, basic metadata done).
- Xcode 15+ installed and signed in (Xcode → Settings → Accounts → Apple ID → Team).

## 1) Configure the Xcode project

1. Open the project in Xcode.
2. Target → Signing & Capabilities:
   - Set the Team to your Apple Developer Team.
   - Enable “Automatically manage signing”.
   - Add capability: “In‑App Purchase”.
3. Target → General:
   - Bundle Identifier must match the App Store Connect bundle ID exactly.
   - Version (`CFBundleShortVersionString`): semantic version (e.g., 1.0.0).
   - Build (`CFBundleVersion`): integer that must increment for every uploaded build (e.g., 1, 2, 3...).
4. Ensure the app compiles for “Any iOS Device (arm64)”.

Notes:
- Automatic signing is strongly recommended. Xcode will create and manage certificates/profiles for you.
- If you must use manual signing, create an iOS Distribution certificate and an App Store provisioning profile for your bundle ID in Certificates, Identifiers & Profiles, then set them in the target’s Signing.

## Capabilities & Requirements (Checklist)

- In‑App Purchase: enable in Signing & Capabilities; required for StoreKit and TestFlight IAP testing.
- URL Types: custom scheme `gifterclub` configured (handles login and payment callbacks).
- Privacy keys (Info.plist):
  - NSCameraUsageDescription: explain livestream and capture use.
  - NSMicrophoneUsageDescription: explain livestream/video audio recording use.
  - NSPhotoLibraryUsageDescription: explain selecting photos/videos for posts.
  - NSPhotoLibraryAddUsageDescription: explain saving captured media (if/when used).
- LiveKit usage: camera + microphone permissions must be granted to go live; no extra entitlement needed.
- App Transport Security: not required (all endpoints use HTTPS/WSS). If you add non‑TLS endpoints, configure ATS exceptions.
- Background Modes: not required currently. If you want audio to continue while backgrounded or Picture‑in‑Picture, add “Audio, AirPlay, and Picture in Picture”. For true background streaming, plan carefully for UX and battery.
- Notifications: not used yet. If you add push, enable “Push Notifications” capability and add APNs configuration; request authorization at runtime.
- Associated Domains: optional. Add if you plan universal links (`applinks:your.domain`). Not required for `ASWebAuthenticationSession` callback with URL scheme.
- Keychain Sharing/App Groups: not required.

## 2) Add the IAP product in ASC (gift_token)

1. App Store Connect → My Apps → Your App → In‑App Purchases → +.
2. Type: Consumable.
3. Product ID: `gift_token` (must match the app code).
4. Price: $0.99 tier.
5. Localizations: name/description screenshot as required.
6. Cleared for sale: Yes.

Tip: You can leave this IAP in “Ready to Submit” until a production submission. Internal TestFlight testers can still exercise IAP in sandbox.

## 3) Local IAP testing (optional but recommended)

Option A: StoreKit Configuration (no ASC required)
- A ready file is included: `GiftersClub/GiftersClub/StoreKit/GiftersClub.storekit` with `gift_token` at $0.99.
- In Xcode: Scheme → Edit Scheme → Run → Options → StoreKit Configuration → select this file.

Option B: Sandbox Tester (real StoreKit)
- App Store Connect → Users and Access → Sandbox → Testers → +.
- Run on device/simulator, initiate purchase, sign in with sandbox Apple ID.

## 4) Archive the app (Release)

Xcode UI (easiest):
1. Set Scheme to your app, “Any iOS Device (arm64)”.
2. Product → Archive. Wait for build to finish and Organizer to open.

Command line (CI‑friendly):
```bash
xcodebuild \
  -workspace GiftersClub-iOS/GiftersClub.xcworkspace \
  -scheme GiftersClub \
  -configuration Release \
  -archivePath build/GiftersClub.xcarchive \
  archive

# Export an .ipa suitable for App Store upload
cat > ExportOptions.plist <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>app-store</string>
  <key>signingStyle</key><string>automatic</string>
  <key>uploadSymbols</key><true/>
</dict></plist>
PLIST

xcodebuild \
  -exportArchive \
  -archivePath build/GiftersClub.xcarchive \
  -exportOptionsPlist ExportOptions.plist \
  -exportPath build
```

## 5) Upload the build to App Store Connect

Xcode UI:
1. Organizer → Archives → select your archive.
2. Distribute App → App Store Connect → Upload.
3. Keep default options (include symbols), proceed and finish.

Alternative tools:
- Transporter app (Mac App Store): Drag the exported .ipa to upload.
- Fastlane: `fastlane pilot upload` for TestFlight, `fastlane deliver` for App Store metadata.

After upload, ASC will process the build (5–30 minutes). Once processing completes, the build appears under TestFlight.

## 6) TestFlight testing

- Internal testers (up to 100): available immediately, no beta review required. Purchases use the sandbox environment and won’t charge testers.
- External testers: require Beta App Review. Create a group, add your build, fill compliance info, then submit for beta review.

IAP in TestFlight:
- Internal testers can test `gift_token` without IAP approval. External testers require the IAP to be approved or included with an app submission.

## 7) Link IAP to a production submission (when ready)

1. ASC → Your App → App Store → iOS App → + Version (e.g., 1.0.0).
2. Add the processed build to this version.
3. In the “In‑App Purchases” section, add `gift_token` to the version.
4. Complete all submission metadata and submit for review.

## 8) Versioning rules and common pitfalls

- Build number must increment for every upload (even within the same version).
- If you change the Version (e.g., 1.0.0 → 1.0.1), you can reset build numbering or continue incrementing—just ensure each upload has a unique build.
- Automatic signing avoids most provisioning profile errors. If you see “No profiles for bundle ID”, ensure the Team is correct and the bundle ID exists.
- Ensure the In‑App Purchase capability is present in the Xcode target.
- Keep `gift_token` product ID exactly matching the code (`StoreKitService`).

## 9) Fastlane (optional automation)

Install fastlane and use the included lane to automate build + upload:

```ruby
default_platform(:ios)

platform :ios do
  desc "Build and upload to TestFlight"
  lane :beta do
    api_key = app_store_connect_api_key(
      key_id: ENV['ASC_KEY_ID'],
      issuer_id: ENV['ASC_ISSUER_ID'],
      key_content: ENV['ASC_KEY_CONTENT'],
      is_key_content_base64: true
    )
    setup_ci
    match(api_key: api_key, type: "appstore", readonly: false)
    build_app(
      workspace: "GiftersClub-iOS/GiftersClub.xcworkspace",
      scheme: "GiftersClub",
      configuration: "Release",
      export_method: "app-store",
      xcargs: "-allowProvisioningUpdates",
      export_options: { signingStyle: 'automatic', uploadSymbols: true }
    )
    upload_to_testflight(api_key: api_key)
  end
end
```

Run with:
```bash
bundle exec fastlane ios beta
```

### CI with GitHub Actions

This repo includes `.github/workflows/ios-testflight.yml` which:
- Installs Fastlane and runs the `beta` lane.
- Uses App Store Connect API key from GitHub Secrets:
  - `ASC_KEY_ID`: Key ID
  - `ASC_ISSUER_ID`: Issuer ID
  - `ASC_KEY_CONTENT`: Base64 of the `.p8` key contents
  - `APP_BUNDLE_ID`: Your bundle id (e.g., `club.gifters.ios`)
  - `APPLE_ID`: Your Apple ID email (optional, used by Appfile)
  - `MATCH_GIT_URL`: Private repo URL for fastlane match certs/profiles
  - `MATCH_PASSWORD`: Passphrase for the match repo
  - `MATCH_GIT_BRANCH`: Branch name (optional)

To create the base64:
```bash
base64 -i AuthKey_ABC123XYZ.p8 | tr -d '\n' | pbcopy
```

Important: For GitHub-hosted runners, Xcode cannot create signing assets unless it can access your developer account. Options:
- Use a self-hosted macOS runner signed into Xcode (Automatic Signing works).
- Or set up `fastlane match` (configured here) to install certificates/profiles in CI.
- Or build locally in Xcode (Organizer) and let CI only handle metadata or uploads.

### Automated Signing with fastlane match

1. Create a private git repo for signing assets (e.g., `ios-certificates`).
2. Initialize match locally:
   ```bash
   bundle exec fastlane match init
   ```
3. Bootstrap App Store certs/profiles:
   ```bash
   export MATCH_GIT_URL=git@github.com:your-org/ios-certificates.git
   export MATCH_PASSWORD=some-strong-passphrase
   export APP_BUNDLE_ID=club.gifters.ios
   export APPLE_ID=your-appleid@example.com
   bundle exec fastlane match appstore
   ```
4. Push the encrypted profiles/certs to the repo.
5. Add `MATCH_GIT_URL`, `MATCH_PASSWORD` (and optionally `MATCH_GIT_BRANCH`) as GitHub Secrets.
6. Trigger the `iOS TestFlight` workflow.

## 10) Verifying IAP end‑to‑end

1. Install the TestFlight build.
2. Sign in to your app.
3. Open the token top‑up sheet and purchase `gift_token`.
4. Expect: TestFlight sandbox flow, receipt sent to the backend, token balance updates.

If the purchase fails:
- Check ASC sandbox tester setup.
- Confirm `gift_token` exists in ASC and is Cleared for Sale.
- Check Xcode console logs and server logs for the Edge Function call.

—

Questions or roadblocks? Capture the exact step and error message and we’ll adjust signing or transport accordingly.

## 11) Accounts, Roles, and Keys (What to Create and Why)

- Apple Developer Program (developer.apple.com):
  - You or your company must enroll. Required to sign and distribute apps.
  - Roles: Account Holder/Admin can manage certificates/profiles; Developer can view/build.

- App Store Connect (appstoreconnect.apple.com):
  - Create the App record (you did), add users (internal testers), create IAPs.
  - Create Sandbox Testers for IAP testing (Users and Access → Sandbox → Testers).
  - Create an App Store Connect API Key (Users and Access → Keys → App Store Connect API):
    - Needed by Fastlane/CI to upload builds to TestFlight without 2FA prompts.
    - Save Key ID, Issuer ID, and download the .p8 key file.

- GitHub (or your CI):
  - Add Secrets for CI (Repository → Settings → Secrets → Actions):
    - ASC_KEY_ID: App Store Connect API Key ID (string like ABCDE12345).
    - ASC_ISSUER_ID: Issuer ID (UUID).
    - ASC_KEY_CONTENT: Base64 of the .p8 file contents (do not commit the .p8).
    - APP_BUNDLE_ID: e.g., club.gifters.ios (must match Xcode/ASC).
    - APPLE_ID: Your Apple ID email (used by Appfile; optional).
    - MATCH_GIT_URL: Private repo URL for fastlane match signing assets (e.g., git@github.com:your-org/ios-certificates.git).
    - MATCH_PASSWORD: Passphrase for match repo encryption.
    - MATCH_GIT_BRANCH: Branch name (optional, default main).

- Fastlane Match repository (private):
  - Holds encrypted signing certificates and provisioning profiles.
  - Create a new private repo just for this (not the app repo).
  - Keep MATCH_PASSWORD safe; rotate if leaked.

Security notes:
- Never commit .p8 keys or raw provisioning profiles to the app repo.
- The ASC API key can be revoked and rotated if needed; keep the .p8 in a password manager.
- iOS does NOT have an Android-style keystore that bricks updates if lost. Distribution certificates can be revoked and reissued.

## 12) App Store Metadata Guidelines (What to Fill In)

- App Name: up to 30 chars, brandable, no trademark issues.
- Subtitle: short tagline; avoid keyword stuffing.
- Description: clear, honest description of features; avoid promises you don’t ship.
- Keywords: comma-separated, relevant, no competitor names or trademarks.
- Promotional Text: optional, shows at top of description for timely messages.
- Privacy Policy URL: required; must be reachable and describe data handling.
- Support URL: required; a working support/contact page.
- Screenshots: required per device family used; use real in-app screens (no device frames required by Apple, but fine to include). Localize later.
- Age Rating questionnaire: answer accurately. If user-generated content, enable reporting/moderation references.
- App Privacy (Data Types): complete the privacy nutrition label in ASC per Apple guidance.
- Encryption (Export Compliance): most apps answer “uses standard encryption” → yes, not using end-to-end user-managed keys.

Tips:
- Keep Info.plist permission strings specific: e.g., “Camera is used for livestreams and to capture photos/videos for your posts.”
- Ensure the app shows the IAP UI and a flow to purchase for the reviewer with clear steps.

## 13) IAP Review Info and Common Statuses

Where to add: ASC → Your App → In‑App Purchases → select `gift_token` → Review Information.

Include in Review Information:
- Test account credentials (if the purchase UI requires login in your app).
- Exact steps to reach the purchase UI (e.g., Profile → Top Up Tokens → Buy).
- Note that purchases run in sandbox; provide a sandbox tester or say “use any Apple sandbox tester”.
- Explain expected grant: “Purchasing `gift_token` credits 70 tokens to the user account.”

Common IAP statuses (and fixes):
- Missing Metadata: add Display Name, Description, Screenshot, Pricing, Localization; ensure Cleared for Sale = Yes.
- Ready to Submit: metadata complete; will be reviewed when you submit an App Version that includes this IAP.
- Waiting for Review / In Review: Apple is reviewing (can take hours to days).
- Approved: available for production when your app version goes live.

TestFlight specifics:
- Internal testers can purchase IAP in sandbox even if `gift_token` is not yet approved for production.
- External testers usually require the IAP to be approved or included with an app submission.

## 14) Permissions to Request In‑App (and Wording)

- Camera (NSCameraUsageDescription): “Camera is used for livestreams and to capture photos/videos for your posts.”
- Microphone (NSMicrophoneUsageDescription): “Microphone is used for livestream audio and video recordings.”
- Photo Library Read (NSPhotoLibraryUsageDescription): “Allow access to select photos and videos for your posts.”
- Photo Library Add (NSPhotoLibraryAddUsageDescription): “Allow saving captured photos or videos to your library.”

Request timing:
- Camera/Mic: request before going live or recording; fail gracefully if denied.
- Photo Library: request when user picks media; avoid requesting on app launch.

## 15) Troubleshooting & Common Rejections

- Build not processing: ensure the app is built with Release, correct bundle ID, and valid signing; try re-uploading.
- ITMS-90161/90164 (Invalid Provisioning Profile/Code Signing): verify signing assets or use fastlane match; ensure Team matches the bundle ID.
- IAP Missing Metadata: add screenshot and localized strings; ensure pricing and Cleared for Sale.
- Reviewer cannot reach IAP: provide clear steps and test account; ensure UI is visible without special toggles.
- Login required but no creds provided: include a test account under Review Information.
- Crashes at launch: test on a clean device (no Xcode debugger), review required capabilities.

## 16) Zero-to-TestFlight Checklist (Quick Reference)

- Accounts: Apple Developer + App Store Connect set; roles OK.
- App Record: created with name, bundle ID, basic metadata.
- Xcode: Team set, Automatic Signing ON, IAP capability added.
- IAP: `gift_token` created, Cleared for Sale, metadata and screenshot added.
- StoreKit local config: `GiftersClub.storekit` selected in scheme (optional).
- Fastlane/CI: secrets added; match repo created and bootstrapped.
- Build & Upload: run `bundle exec fastlane ios beta` or upload from Organizer.
- Test: add yourself as internal tester; install via TestFlight; complete IAP purchase in sandbox.
- Production: create app version, attach build, link the IAP, fill review info, submit.
