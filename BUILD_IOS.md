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
- Xcode → File → New → StoreKit Configuration File (.storekit).
- Add product `gift_token` at $0.99 and assign the file to your scheme (Scheme → Run → Options → StoreKit Configuration).

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

Install fastlane and add the following minimal `Fastfile` to automate build + upload:

```ruby
default_platform(:ios)

platform :ios do
  desc "Build and upload to TestFlight"
  lane :beta do
    build_app(
      workspace: "GiftersClub-iOS/GiftersClub.xcworkspace",
      scheme: "GiftersClub",
      configuration: "Release",
      export_method: "app-store"
    )
    upload_to_testflight
  end
end
```

Run with:
```bash
bundle exec fastlane ios beta
```

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
