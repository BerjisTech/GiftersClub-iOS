# In‑App Purchase (IAP) Setup for Token Packs

This doc captures the minimal, repeatable process to ship consumable token packs via StoreKit 2, and how it integrates with our Supabase Edge Functions for validation + crediting.

## Prerequisites

- App record exists in App Store Connect (ASC).
- Agreements, Tax, and Banking are completed in ASC.
- Xcode target has the capability: In‑App Purchase (Signing & Capabilities).

## Product Model (Consumables)

We sell tokens (coins) as consumable products; users spend tokens on gifts and wishlists. Gifts are NOT IAP items.

- Suggested product IDs (can change later, but IDs are immutable once created):
  - `tokens_70`
  - `tokens_150`
  - `tokens_375`
  - `tokens_800`
- Token counts are iOS‑specific and sized to cover Apple’s commission and withdrawal fees. Adjust server mapping as needed.

## Create IAP Products in App Store Connect

1. ASC → My Apps → Your App → In‑App Purchases → + → New In‑App Purchase.
2. Type: Consumable.
3. Reference Name: Human label (e.g., "Tokens 70").
4. Product ID: Must match the app (e.g., `tokens_70`).
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

## App Integration (Already Implemented)

- `StoreKitService` loads products, performs purchases, and POSTs to a Supabase Edge Function for validation and crediting.
- `TokenTopUpSheet` lists packs (with prices) and highlights a recommended pack when there's a shortfall; on success it refreshes the user balance and closes with a success callback.

Update these when you finalize product IDs or token counts:

- File: `GiftersClub-iOS/GiftersClub/Sources/Services/StoreKitService.swift` (packs and IDs)
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
3. Map `productId` → tokens, credit the user, record the transaction, and return 2xx.

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
- [ ] Consumable IAPs created in ASC with final product IDs.
- [ ] StoreKit products load in the app (StoreKit config or sandbox tester).
- [ ] Supabase function `purchase-tokens-iap` validates and credits tokens.
- [ ] App refreshes balance and shows success toast after purchase.
- [ ] Optional: productId→tokens mapping is remote‑configurable.

---

If you change product IDs, update `StoreKitService.packs` and/or the server mapping. For economics help (token counts per tier), jot down fee %, withdrawal fee, and payout rate and we’ll compute a matching set of pack sizes.

