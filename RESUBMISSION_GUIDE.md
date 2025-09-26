# App Store Resubmission Guide (iOS)

This note consolidates the actions taken and provides suggested replies for App Review.

## UI fixes implemented

- Buy Tokens sheet no longer shows an overlaid title and now scrolls (and can expand to Large). File: `Sources/Views/Payments/TokenTopUpSheet.swift`.
- Withdrawal UX now refers to “Withdraw Credits” and “creator credits” throughout. Files: `AccountView.swift`, `WithdrawalsView.swift`.
- Added an in‑app info page: `CreatorCreditsInfoView.swift` and entry points:
  - Question‑mark button next to “Withdraw Credits” on Account.
  - “What are creator credits?” link at top of the Withdraw Credits page.
- Account screen now constrains width and adds extra bottom inset so every control is reachable on iPad (file: `Sources/Views/Profile/AccountView.swift`).
- Added a global safe-area inset equal to the bottom bar height so all tabs leave enough space above the floating menu (files: `Sources/Views/MainTabView.swift`, `Sources/Views/UI/CustomBottomBar.swift`).

## Business model clarifications

- Purchased items are “tokens,” a consumable in‑app currency used for digital experiences (e.g., sending gifts). Tokens are not withdrawable and have no cash value.
- “Creator credits” are earned through platform programs (content performance thresholds, ad adjacencies, referrals, and engagement incentives). Only earned creator credits may be withdrawn, subject to verification and policy compliance.

## Suggested replies to App Review

1) Guideline 3.0 – Price confirmation
   - “Yes, the intended prices are $110.99 (token_10000), $279.00 (token_25000), $559.00 (token_50000), and $1000.00 (token_90000).”

2) Guideline 2.1 – Information needed (purpose of tokens)
   - “Tokens are a consumable in‑app currency used to send virtual gifts and access in‑app features. Tokens are not redeemable for money and cannot be withdrawn.”

3) Guideline 3.1.1 – IAP exchange for money
   - “We’ve clarified the product model in‑app. Purchased tokens are consumable and non‑withdrawable. Withdrawals are limited to ‘creator credits,’ which are earned via platform programs and are not in‑app purchases.”

4) Guideline 4.0 / 2.1 – UI and completeness
   - “We resolved the Buy Tokens sheet interaction issues (removed overlaid title, enabled scrolling and large detent). We also updated the Account screen layout so all controls remain reachable on iPad. We verified on iPad Air (5th gen, iPadOS 17/18) that all products are selectable.”

5) Guideline 2.1 – Performance – IAP completeness
   - “After each StoreKit transaction we call the existing `purchase-tokens` Supabase Edge Function (same flow web/Android use). This credits the user’s balance immediately and records the StoreKit transaction ID as the reference.”

6) Guideline 4.1 – Copycat content
   - If applicable: “We have removed any imagery that could be confused with third‑party IP,” or attach rights documentation if you have authorization.

## Reviewer test steps

1. Log in → Profile → Account.
2. Tap “Buy Tokens” → sheet expands and scrolls; tap any product to purchase.
3. Tap “Withdraw Credits” → View balance, request flow, and history.
4. Tap “What are creator credits?” (top link) or the question‑mark icon on Account to review the policy page.

## Developer checklist before resubmission

- App Store Connect: ensure IAPs are Cleared for Sale and linked to the app version.
- Confirm StoreKit products match IDs in `StoreKitService.packs`.
- Verify tokens purpose text in submission notes matches the language above.
- If any potential IP imagery exists, remove or document rights.

## Notes

- If you later separate balances server‑side (purchased tokens vs. earned credits), the UI already uses “credits” for withdrawals; wire the earned balance field to the Withdraw page when available.
