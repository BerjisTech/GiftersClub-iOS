# In‑App Purchase (IAP) Setup for Token Packs

This doc captures the minimal, repeatable process to ship consumable token packs via StoreKit 2, and how it integrates with our Supabase Edge Functions for validation + crediting.

## Prerequisites

- App record exists in App Store Connect (ASC).
- Agreements, Tax, and Banking are completed in ASC.
- Xcode target has the capability: In‑App Purchase (Signing & Capabilities).

## Product Model (Consumables)

We sell tokens (coins) as consumable products; users spend tokens on gifts and wishlists. Gifts are NOT IAP items.

- Current product ID: `token_100` (consumable).
- Grant: 100 tokens per purchase.
- If pricing or fee assumptions change, you can adjust the token grant here (client) and/or on the server mapping.

## Create IAP Products in App Store Connect

1. ASC → My Apps → Your App → In‑App Purchases → + → New In‑App Purchase.
2. Type: Consumable.
3. Reference Name: Human label (e.g., "Tokens 100").
4. Product ID: Must match the app (e.g., `token_100`).
5. Pricing: Choose a Price Tier. You can customize per region later.
6. Localizations: Add Display Name and Description for at least your primary locale.
7. Cleared for Sale: Yes.
8. Review Information:
   - Screenshot of the in‑app purchase UI.
   - Reviewer notes and test credentials if login is required.
9. Save. Repeat for all packs.

## Link IAPs to a Release

- New IAPs start as "Ready to Submit". Include them with a new app version submission for production.
- For development, see "Testing" below; production linking happens during review.

## Testing

### Local (StoreKit Configuration)

- Xcode → File → New → StoreKit Configuration File (.storekit).
- Add products matching your IDs and desired prices.
- Scheme → Run → Options → StoreKit Configuration → select the .storekit file.
- Run on simulator or device; purchases use local data (no ASC required).

### Sandbox (Real StoreKit)

- ASC → Users and Access → Sandbox → Testers → + Create tester (email not tied to an Apple ID).
- Run on device/simulator, initiate a purchase, sign in with the sandbox tester when prompted.

### IAP Statuses in App Store Connect

- Missing Metadata: One or more required fields are missing. Fix by adding Display Name, Description, Localization, Screenshot, and a Price Tier; set Cleared for Sale = Yes.
- Ready to Submit: Metadata complete; the IAP will be reviewed with your next app version submission (link it in the App Version’s “In‑App Purchases” section).
- Waiting for Review / In Review: Apple is reviewing the IAP.
- Approved: IAP can go live with your app release.

Review Information (what to include):
- Test account credentials if your app requires login prior to purchase.
- Step-by-step path to the purchase UI (e.g., Profile → Buy Tokens → select pack).
- Clarify expected result (e.g., 70 tokens credited per `gift_token`).

## App Integration (Already Implemented)

- `StoreKitService` loads products, performs purchases, and POSTs to a Supabase Edge Function for validation and crediting.
- `TokenTopUpSheet` lists packs (with prices) and highlights a recommended pack when there's a shortfall; on success it refreshes the user balance and closes with a success callback.

Update these when you finalize product IDs or token counts:

- File: `GiftersClub-iOS/GiftersClub/Sources/Services/StoreKitService.swift` (set `token_100` and token grant)
- (Optional) Move productId→tokens mapping to a Supabase config table for remote control.

## Server Validation Flow (Supabase Edge Function)

Endpoint name (configurable): `purchase-tokens-iap`.

The app POSTs JSON:

- `userId`: string
- `productId`: string
- `tokens`: number (server may re‑map based on productId)
- `transactionId`: string
- `originalTransactionId`: string
- Either (iOS 18+): `appTransaction` = base64 of `AppTransaction.jsonRepresentation`
- Or (iOS < 18): `appReceipt` = base64 of the App Store receipt

Server responsibilities:

1. Verify the receipt/transaction with Apple (classic receipt validation or App Store Server API).
2. Ensure the transaction is for `productId`, not refunded, and not already consumed.
3. Map `productId` → tokens (e.g., `gift_token` → 70), credit the user, record the transaction, and return 2xx.

Troubleshooting tips:
- If the app reports purchase success but no tokens: check server logs for the `purchase-tokens-iap` function; verify Apple receipt validation and productId mapping.
- If purchase sheet won’t appear in TestFlight: ensure you’re signed in with a sandbox tester when prompted; confirm IAP is “Cleared for Sale”.

## Economics (Pack Sizing)

If Apple fee = `c` (0.30 or 0.15), withdrawal fee = `F`, and creator payout rate = `r` (e.g., 0.70), you can size iOS token packs to avoid negative margin.

- Given price `P`, grant tokens:
  - `tokens = floor((P * (1 − c) − F) / r)`
- Or, given desired tokens `T`, required price tier is approximately:
  - `P ≈ (F + T * r) / (1 − c)`

Most apps either:
- Reduce tokens per iOS pack at the same price tier, or
- Use higher price tiers while keeping token counts.

## Common Gotchas

- Product IDs must exactly match between ASC and the app.
- Banking/Tax agreements must be complete before go‑live.
- If purchase UI is behind auth, provide reviewer credentials and a clear note in the submission.
- Do not steer users to external purchase flows for digital goods in the iOS app (App Store Review Guideline 3.1.1).

## Checklist

- [ ] IAP capability enabled in Xcode target.
- [ ] Consumable IAPs created in ASC with final product IDs (e.g., `gift_token`).
- [ ] StoreKit products load in the app (StoreKit config or sandbox tester).
- [ ] Supabase function `purchase-tokens-iap` validates and credits tokens.
- [ ] App refreshes balance and shows success toast after purchase.
- [ ] Optional: productId→tokens mapping is remote‑configurable.

---

If you change product IDs, update `StoreKitService.packs` and/or the server mapping. For economics help (token counts per tier), jot down fee %, withdrawal fee, and payout rate and we’ll compute a matching set of pack sizes.
