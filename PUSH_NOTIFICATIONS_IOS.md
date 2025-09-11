# iOS Push Notifications (APNs) — End‑to‑End Setup

This guide sets up Apple Push Notifications (APNs) for the native iOS app and wires it to Supabase so your server can trigger pushes. It’s tailored to this repo and your credentials.

- Bundle ID: `club.gifters.giftersclub.GiftersClub`
- Apple Developer Account: `Fridah Nancy`
- Team ID: `SAZBQ79X56`
- APNs Auth Key: a `.p8` file downloaded already (in `~/Downloads`)
- APNs Key ID: `2RNSXSR6YG` (from Apple Keys)

The app already requests permission, registers with APNs, and upserts tokens to Supabase (see `GiftersClub/Sources/App/GiftersClubApp.swift`). You mainly need to finish Apple-side configuration and add backend credentials + a sending path.

---

## 1) Apple Developer Setup

- Enable Push Notifications on the App ID
  - Apple Developer → Certificates, Identifiers & Profiles → Identifiers.
  - Find `club.gifters.giftersclub.GiftersClub` → ensure the “Push Notifications” capability is ON.

- Create/Confirm APNs Auth Key (`.p8`)
  - Apple Developer → Keys → + → “Apple Push Notifications Authentication Key (APNs)”.
  - If you already created it, you’ll see an entry like `AuthKey_<KEYID>.p8`.
    - For this project, your Key ID is `2RNSXSR6YG`, so the file is typically `AuthKey_2RNSXSR6YG.p8`.
  - Record:
    - Team ID: `SAZBQ79X56` (you provided)
    - Key ID: from the Apple Keys list OR the filename, e.g. `AuthKey_ABC123DEFG.p8` → `ABC123DEFG`.

- Provisioning
  - If you use automatic signing, Xcode will handle provisioning with Push capability. Otherwise, regenerate provisioning profiles for this App ID with Push enabled.

---

## 2) Xcode Project Checks (already mostly done)

- Target → Signing & Capabilities:
  - Add “Push Notifications”.
  - Add “Background Modes” → enable “Remote notifications”.
- Entitlements: already present in repo
  - `GiftersClub/Entitlements/GiftersClub.Debug.entitlements` → `aps-environment = development`.
  - `GiftersClub/Entitlements/GiftersClub.Release.entitlements` → `aps-environment = production`.
  - `Info.plist` → `UIBackgroundModes` includes `remote-notification`.
- Code already in place
  - `AppDelegate` requests permission and registers for remote notifications.
  - On success, the app upserts the APNs token into `user_device_tokens` via Supabase.

No code changes are required for the client to receive pushes.

Optional (foreground banners while app is open):

```swift
// In AppDelegate (it already conforms to UNUserNotificationCenterDelegate)
func userNotificationCenter(_ center: UNUserNotificationCenter,
                            willPresent notification: UNNotification,
                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
    completionHandler([.banner, .sound, .badge])
}

func userNotificationCenter(_ center: UNUserNotificationCenter,
                            didReceive response: UNNotificationResponse,
                            withCompletionHandler completionHandler: @escaping () -> Void) {
    // TODO: route to a screen from response.notification.request.content.userInfo
    completionHandler()
}
```

---

## 3) Supabase: Secrets for APNs

You’ll store Apple credentials in Supabase for your backend to sign APNs JWTs.

Required values:
- `APNS_TEAM_ID`: `SAZBQ79X56`
- `APNS_KEY_ID`: `2RNSXSR6YG`
- `APNS_BUNDLE_ID` (aka APNs topic): `club.gifters.giftersclub.GiftersClub`
- `APNS_P8`: the contents of the `.p8` key (usually begins with `-----BEGIN PRIVATE KEY-----`). You can store raw or base64.

How to prepare and add (two options):

- Option A — Copy raw text
  - Open `~/Downloads/AuthKey_2RNSXSR6YG.p8` in a text editor, copy everything (including the BEGIN/END lines) and save as a secret named `APNS_P8`.

- Option B — Base64 encode via Terminal
  - `base64 -i ~/Downloads/AuthKey_2RNSXSR6YG.p8 | pbcopy` → paste into `APNS_P8_BASE64` (if you prefer a base64 variant). If you do this, also note in your sender code to `atob`/decode before use.

Add these in Supabase:
- Dashboard → Project → Settings → Secrets → Add secret
  - `APNS_TEAM_ID = SAZBQ79X56`
  - `APNS_KEY_ID = 2RNSXSR6YG`
  - `APNS_BUNDLE_ID = club.gifters.giftersclub.GiftersClub`
  - `APNS_P8 = <entire .p8 content>` (or `APNS_P8_BASE64` if using base64)

---

## 4) Supabase: Device Tokens Table (confirm schema + RLS)

The app writes to `user_device_tokens`. Make sure it exists and RLS permits inserts/updates for the logged-in user.

Suggested schema:

```sql
create table if not exists public.user_device_tokens (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  platform text not null check (platform in ('ios','android','web')),
  provider text not null check (provider in ('apns','fcm','webpush')),
  token text not null,
  app_version text default null,
  created_at timestamptz not null default now(),
  unique (user_id, token)
);

alter table public.user_device_tokens enable row level security;

-- Allow users to upsert their own tokens
create policy "Users can manage their own device tokens" on public.user_device_tokens
  for insert with check (auth.uid() = user_id);
create policy "Users can manage their own device tokens update" on public.user_device_tokens
  for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "Users can view their own tokens" on public.user_device_tokens
  for select using (auth.uid() = user_id);
```

If you prefer to manage tokens server-side only, you can restrict `insert`/`update` to the service role and call a secure endpoint instead.

---

## 5) Backend: How to Send APNs

You have two practical paths. Pick one and wire it to your events (new DM, someone goes live, purchase updates, etc.).

### Path A — Supabase Edge Function (Node runtime) or small Node service

APNs requires HTTP/2. If you deploy on a Node 18+ environment (Render, Fly.io, Cloud Run, or Supabase Functions with Node runtime), you can use an APNs library.

Example (TypeScript, Node, using `@parse/node-apn`):

```ts
// send-apns.ts
import apn from '@parse/node-apn';
import { createClient } from '@supabase/supabase-js';

const supabase = createClient(process.env.SUPABASE_URL!, process.env.SUPABASE_SERVICE_ROLE_KEY!);

const APNS_TOPIC = process.env.APNS_BUNDLE_ID!; // club.gifters.giftersclub.GiftersClub
const APNS_KEY_ID = process.env.APNS_KEY_ID!;   // e.g. 2RNSXSR6YG
const APNS_TEAM_ID = process.env.APNS_TEAM_ID!; // SAZBQ79X56
const APNS_P8 = process.env.APNS_P8!;           // raw .p8 text

const provider = new apn.Provider({
  token: {
    key: APNS_P8,
    keyId: APNS_KEY_ID,
    teamId: APNS_TEAM_ID,
  },
  production: true, // set false for sandbox
});

export async function sendPushToUser(userId: string, alert: { title?: string; body: string }, extra?: Record<string, unknown>) {
  // Fetch APNs tokens for this user
  const { data: tokens, error } = await supabase
    .from('user_device_tokens')
    .select('token')
    .eq('user_id', userId)
    .eq('platform', 'ios')
    .eq('provider', 'apns');
  if (error) throw error;

  if (!tokens || tokens.length === 0) return { sent: 0 };

  const notification = new apn.Notification({
    alert,
    topic: APNS_TOPIC,
    sound: 'default',
    payload: extra ?? {},
    // For background content-available: 1, include `contentAvailable: 1`
  });

  const deviceTokens = tokens.map(t => t.token);
  const response = await provider.send(notification, deviceTokens);

  return { sent: response.sent.length, failed: response.failed };
}
```

- Deploy this as:
  - A small service (Render/Fly/Cloud Run) with env vars set as in section 3, plus `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY`.
  - Or a Supabase Function using the Node runtime (if enabled in your project). Ensure the runtime supports HTTP/2 and NPM modules.
- Expose a simple HTTP endpoint (auth’d by a secret header) that triggers `sendPushToUser`.

Test with a real device build (Ad Hoc/TestFlight) for production pushes, or a debug build for sandbox.

Implemented in this repo (Deno Edge Function):
- Location: `gifter-club/supabase/functions/send-apns`
- Exposes POST `/send-apns` (guarded by `X-Admin-Secret`).
- Reads: `user_device_tokens` to resolve APNs tokens.
- Secrets needed: `FUNCTION_SECRET`, `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, `APNS_TEAM_ID`, `APNS_KEY_ID=2RNSXSR6YG`, `APNS_BUNDLE_ID`, `APNS_P8`, `APNS_ENV`.
- Note: APNs requires HTTP/2. Supabase Edge Functions must support outbound HTTP/2 to APNs hosts for delivery. If not, deploy the included logic on a Node service or use Path B.

### Path B — Supabase Push (Dashboard integration)

Supabase offers a Push service that can hold your APNs/FCM credentials and deliver pushes for you (no custom Node service). If you choose this:
- Supabase Dashboard → Push → Apple → configure the same values as in section 3 (upload `.p8`, set Key ID, Team ID, and Bundle ID). Choose Sandbox or Production as needed.
- Follow Supabase Push docs for how to:
  - Register device tokens (it can also use your existing `user_device_tokens` table as the source if you keep it in sync),
  - Send notifications via the Push API/SDK or from the Dashboard.

Note: Exact API calls depend on the current Supabase Push SDK/REST documentation. Use the dashboard’s examples for your project.

---

## 6) Trigger Points (when to send)

Common places to send a push (server-side):
- New direct message: notify the recipient.
- Creator goes live: notify followers (consider rate limiting and user opt‑outs).
- Comment reply / mention: notify the target user.
- Purchase / gift events: receipt/thank‑you notification.

Pattern:
1) Identify target users → look up APNs tokens (`user_device_tokens`).
2) Send push via Path A or Path B.
3) Optionally store a record in a `notifications` table for in‑app display.

---

## 7) Local Verification Checklist

- On a physical device, install a Debug build and launch the app.
  - Allow notifications when prompted.
  - Check Supabase `user_device_tokens` has a row for your `auth.uid()` with `platform=ios`, `provider=apns` and a long hex `token`.
- Send a test push via your chosen backend path.
  - Debug build → use APNs sandbox; Release/TestFlight → use production.
  - If sandbox vs production mismatch, pushes won’t arrive.
- Foreground vs background behavior
  - Foreground: banners won’t show by default unless you implement `userNotificationCenter(_:willPresent:)` to display.
  - Background/terminated: banners arrive if app permissions and Focus modes allow.

---

## 8) Troubleshooting

- 400/403 from APNs
  - Check Key ID, Team ID, and that the APNs JWT is signed with the correct `.p8` content.
  - Ensure `topic` equals your Bundle ID: `club.gifters.giftersclub.GiftersClub`.
- No devices receive
  - Confirm tokens exist in `user_device_tokens` and are recent.
  - Sandbox vs Production mismatch is the #1 cause.
  - Device Focus/Do Not Disturb or notification settings can suppress alerts.
- “BadDeviceToken”
  - Token was minted for sandbox but you’re sending to production (or vice versa).
  - Reinstall the app and try again.
- Auth errors reading tokens
  - If using anon key from the server, RLS will block. Use the service role key on the server side to read `user_device_tokens` or create a dedicated RPC secured by policies.

---

## 9) What you need to do now

1) In Apple Developer:
   - Verify Push is enabled for the App ID.
   - Get your APNs Key ID from the existing `.p8` (filename) or Apple → Keys.
2) In Supabase → Settings → Secrets: add
   - `APNS_TEAM_ID = SAZBQ79X56`
   - `APNS_KEY_ID = 2RNSXSR6YG`

Security note: Never commit the `.p8` file to the repo. Store it only in secure secrets (Supabase, your hosting provider, 1Password, etc.).
   - `APNS_BUNDLE_ID = club.gifters.giftersclub.GiftersClub`
   - `APNS_P8 = <entire .p8 contents>`
3) Confirm `user_device_tokens` table + RLS (or share your current schema and I’ll adjust policies).
4) Choose a sending path:
   - Path A: Deploy the Node sender shown here and call it from your events.
   - Path B: Configure Supabase Push in the Dashboard and follow its send API.
5) Build to a device and send a test.

If you want, I can wire Path A as a Supabase Function or a small Node service and add the exact code + deployment files in the repo. Just confirm which path you prefer.
