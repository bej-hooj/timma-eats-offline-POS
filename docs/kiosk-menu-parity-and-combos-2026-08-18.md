# Kiosk: app-menu parity, add-to-cart, and meals — 2026-08-18

Written before the first source edit (§0.6). Owner, 2026-08-18:

> *"the design of the borne/kioske and everything about design on it should be
> the same as on menu. the user can make combos... cause its too much basic...
> get infos on how the Greatest like burger king and kfc and mcdonald do theirs"*

## What the biggest chains actually do, and what we take from it

Researched 2026-08-18; sources at the bottom.

| Pattern | Source | Taken? |
|---|---|---|
| **Tap the dish image to add it** — no detour through a detail screen for a simple item | KFC kiosks | **Yes.** A `+` on the card adds a dish that has no required choices. |
| **A combo on ONE page.** BK's old constructor needed up to 15 interactions and customers abandoned it; putting every part on a single page was the fix that raised conversion | Burger King redesign | **Yes.** The meal step is one screen — side and drink together, never a wizard. |
| **Offer the meal at the moment the main is chosen**, gently, skippable | McDonald's | **Yes**, with a *Non merci* of equal weight. |
| **Popular first**, so the common order is the shortest path | McDonald's | Partly — `sortIndex` already orders the grid; the dashboard decides. |
| Aggressive pop-ups, partitioned pricing, bad defaults, pressured selling — documented **dark patterns** in an audit of McDonald's own flow | McDonald's (as a warning) | **Refused.** See below. |

### Rules this pass will not break

1. **No pre-ticked upsell.** Nothing enters a cart the customer did not tap. A
   default that costs money is theft with a UI.
2. **One prompt, once.** The meal step appears when a main is added and never
   again for that item. No second-chance screens, no "are you sure" on exit.
3. **Whole prices, always.** The step shows what the side and drink cost and what
   the total becomes — never "+ only 500 FCFA" against a partitioned base.
   `MoneyFormatter`, integer XAF, server-priced.
4. **Skip is as easy as accept.** Same size, same prominence, no colour trick.
5. **Required choices are never skipped** (already paid for): a dish with a
   `minSelect > 0` group always opens the composer, so `+` is only ever a
   shortcut for a dish with no decisions to make.

## What is missing today

- **No dish image anywhere but the menu grid** — measured: zero `Image`/`photoUrl`
  references in `cart_screen.dart` or `composer_sheet.dart`. A customer who chose
  a photograph should see it in their basket.
- **No add-to-cart from the grid.** Every dish, however simple, forces the
  composer open.
- **No meal/combo at all.**

## Plan

### M1 — one thumbnail widget, everywhere a dish appears
`KioskDishThumb`: disk-first via `DishPhotoCache`, network second, brand panel
last — the card's existing three-step fallback, extracted so there is one
implementation instead of three. Used by the card, the cart row, the composer.

### M2 — `+` on the card
Adds quantity 1 straight to the cart when the dish has no required option group;
otherwise opens the composer. Card tap keeps its meaning (open the composer).

### M3 — the meal step, one page
After a main is added, one screen offers a side and a drink from the pinned
snapshot. Tap to include, tap again to drop; running total always visible;
*Ajouter le menu* and *Non merci* side by side. Nothing selected by default.

⚠ **This is a client-side meal, not a dashboard combo.** `rpc_menu_snapshot`
carries no combo steps today, so a real combo product — own price, own steps,
defined by ops — needs a schema-owner change. That is M4 and is NOT in this pass.
Prices here remain the server's: every line is a snapshot product priced by the
engine, and the meal is the sum of its parts with no invented discount.

### M4 — real combos from the dashboard (next pass, schema owner)
`SnapshotProduct.type == 'combo'` plus steps, priced as a product in its own
right. Needs an `ECOSYSTEM` §23.8 contract note, a migration, and both tablet
pins moved together.

## Verification
Widget tests at the Samsung's real 868 × 411 dp: `+` adds without opening the
composer; a dish with a required group still opens it; the meal step shows whole
prices; *Non merci* adds nothing; cart row and composer both render a photograph
from the cache with no network. Then the device, in French.

## Sources
- BK combo constructor redesign (15 interactions → one page):
  https://orderingstack.com/case-study/automation-of-burger-king-restaurants-implementation-of-self-service-kiosks
- KFC kiosk flow, tap the image to add:
  https://touchwo.com/how-to-use-self-ordering-machines-at-kfc/
- McDonald's combo prompt timing/placement:
  https://www.lizard.global/en/blog/how-mcdonalds-kiosks-use-ui-ux-data-analysis-to-boost-revenue
- Dark-pattern audit of McDonald's kiosk flow (what to refuse):
  https://www.researchgate.net/publication/401523803_Deception_by_Design_A_Temporal_Dark_Patterns_Audit_of_McDonald's_Self-Ordering_Kiosk_Flow
