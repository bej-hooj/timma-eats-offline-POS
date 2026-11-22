# The borne reads the dashboard live, and the offline drill — 2026-11-22

Owner, today: *"today everything should be finest fine and working 100% with
wireless rooter with no internet and when internet is back it should loads
content from the dashboard and send content to the database"* and *"Every price,
every menu everything on borne is made from the dashboard and loaded when the
borne connects internet."*

Hardware **changed** from every previous session:

| Role | Device | adb |
|---|---|---|
| **borne** (hub) | **GM92 "iMac Kimya"**, Android 12, arm64-v8a | `192.168.1.233:43721` |
| **cuisine** (board) | **Samsung SM-G975F** | `adb-R58N113RK6J-pXlm4k._adb-tls-connect._tcp` |

⚠ The cuisine is **Android now**, not the Bocav iPhone. The KDS has never been
run on Android hardware — its manifest carries INTERNET / multicast, and its
suite is green (60/60), but nothing has been seen on a screen.

⚠ The GM92 is **1097 × 569 dp** landscape (1920×1080 px @ 280 dpi). Every
previous layout proof was at the Samsung's 868 × 411 dp or at 1200 × 800. This
is a **third geometry** and the repo's own history says layout breaks at every
new real width (four French overflow defects across three stages). Expect them.

## What was actually wrong — measured today, not assumed

### 1. ⛔ There was no device key. `f852570f-…` is a ROW ID, not a key.

`docs/stabilization-2026-08-19.md:189` recorded `f852570f-6d02-4835-8faf-…` as
"the key that was issued". It is the **`pos_devices.id`** of that row. Proof:

```sql
select key_hash = encode(sha256(convert_to('f852570f-…','UTF8')),'hex') ...
-- false, for all four rows
```

Calling `rpc_menu_snapshot` with it returns **`device_unknown`**, which is why
the borne fell back to the seeded menu. Every "the key works" claim from
2026-08-19 onward was about a key whose plaintext is nowhere on disk.

**Fixed:** a new key issued 2026-11-22 (owner-approved, additive — the four
existing rows untouched), row `808b32da-755b-4c61-9de4-ae5fe1faab6a`,
label *Borne GM92 "iMac Kimya"*. The plaintext is in `docs/setup-config.md`,
which is now **gitignored** (it was not before — the `.gitignore` entry is part
of this change). Only the sha256 ever went to the database.

### 2. ✅ `snapshot_checksum_mismatch` is GONE — measured, not hoped

With the new key, the live bundle through the **pinned** `pos_core`:

```
server : cf0f778e1bac6bc2df4749a78a135913deeba7c775ecd7cc17a5f34673b73563
kiosk  : cf0f778e1bac6bc2df4749a78a135913deeba7c775ecd7cc17a5f34673b73563
MATCH    9 products, 1 categories, v1789043850
```

Production's `rpc_menu_snapshot` carries `prep_min`/`prep_max`/`spice_level`/
`origin_*` (Stage 3d) and categories **without** `photo_url`, and the tablets
are pinned at `5a43079`, which has the matching Dart model. The August
mismatch was a real skew that later migrations + the re-pin closed.

⚠⚠ **But the repo migration is still poisoned.** `20260818100000_kiosk_snapshot_categories.sql:160`
still emits `'photo_url', c.image_url` inside every category. Production does
NOT run that file — it runs `20260819134257_kiosk_snapshot_categories_checksum_safe`,
applied by hand. **A replay from zero (the CI migration-safety job, or a new
environment) recreates the function that makes every borne refuse its menu and
stop selling.** Fixing that file is schema-owner work, listed below.

### 3. ⛔ The ribbon lies in the dangerous direction

`kiosk_app.dart:55` keys *DEBUG — MENU D'EXEMPLE · PRIX NON RÉELS* on
`KioskDevProvisioning.seedMenu` — a **build flag**. The seed is version `1` and
any real bundle supersedes it, so the moment the real menu lands the borne sells
**real prices under a red band saying the prices are fake**. The ribbon exists
to stop fake data being mistaken for real; keyed this way it does the opposite.

**Fix:** key it on the **active snapshot's version** — the band shows when, and
only when, the menu being sold is the seed.

### 4. ⛔⛔ A new menu never reaches the screen — the owner's requirement, broken

`kiosk_app.dart:308` does `ref.read(kioskEngineProvider).pinnedMenu` — a
**read**, not a watch — and `KioskCloudCatalog` notifies nobody. The 15-minute
refresh pins the dashboard's new prices into SQLite and **the screen keeps
showing the old ones until someone restarts the app**. That is exactly
*"loaded when the borne connects internet"* not working.

Same bug, worse shape: `KioskSessionController.build()` decides
`outOfService` once, from `engine.pinnedMenu == null`. A **fresh tablet** — the
GM92, today — has nothing pinned at first launch, so it shows *Borne
indisponible* and **stays there forever** even after the catalogue arrives.

### 5. ⚠ The fix in 4 creates a hazard that must be fixed with it

`PosEngine.placeKioskOrder` re-reads `_store.activeSnapshot()` **at placement
time**. So a pin that lands while a customer is mid-order means they are charged
the **new** price for the screen they read at the **old** one — silently — and a
withdrawn dish throws. This is true *today*, before any of my changes; making
the UI follow the menu would only make it frequent.

**Fix:** never pin while a customer is mid-order. The pin is skipped (not
dropped — the next tick takes it) unless the kiosk is idle: attract or
out-of-service, with an empty cart.

## The changes, in order

1. `.gitignore` + `docs/setup-config.md` — the key, never committed. **done**
2. `pos_devices` row for the GM92. **done, owner-approved**
3. `kioskMenuRevisionProvider` — bumped when a pin changes the active version.
4. `KioskCloudCatalog`: `canPin` gate + `onPinned` callback; `refresh()` skips
   the cloud pin while a customer is mid-order, and always warms photos.
5. `_MenuWithCartBar` watches the revision; the ribbon reads the active version.
6. `KioskSessionController` leaves `outOfService` when a menu finally arrives.
7. Tests for each, French, at **1097 × 569 dp**.

## Then, on the hardware

- Borne on the GM92 with the real key, seed OFF: it must show the **dashboard's**
  dishes and prices, with photos, and **no** red ribbon.
- Change a price in the dashboard → it reaches the borne without a restart.
- Cuisine on the Samsung; pair; order crosses; alarm rings.
- **The drill:** router WAN unplugged (never the wifi — adb rides it). Menu and
  photos still render, an order still reaches the cuisine, both apps restart and
  reconnect, then the WAN returns and the orders reach the database.

## Owed, not in this pass

- ⚠ Correct `20260818100000_kiosk_snapshot_categories.sql` in the app repo so a
  replay cannot recreate the kiosk-breaking function (schema owner).
- ⚠ The cloud relay is still not deployed: `20260816120000_pos_relay_channel_auth.sql`
  unapplied, `pos-relay-token` undeployed. WAN-separated tablets cannot talk.
  LAN pairing — today's drill — does not need it.
- ⚠ `PosOrder` has no `fire_at`; the cuisine's *Programmées* lane cannot fill.
  Do not point this board at a branch taking scheduled orders.
- Q70's remaining menu parity: `+` add-to-cart, the meal step, tag badges.

---

## Result — the borne, on the GM92

**The real catalogue is live.** `[KioskCatalog] menu v1 → v1789043850`, nine
dishes with the dashboard's prices and photographs, and the sample-menu ribbon
gone of its own accord because the menu being sold is no longer the seed.

The menu was then rebuilt towards the phone app and the owner's reference
tills, each step seen on the device:

- Grid sized from the **width**: five compact columns alone, three beside the
  basket, instead of three billboards.
- Card: title 22 → 17 (at the role), the text block hugs its lines so the band
  of cream between the name and the cooking time is gone, and the sold-out
  badge no longer covers a third of the picture.
- A **"+" on every card** that drops the dish straight in the basket with the
  phone's fly-to-cart bubble — offered only where there is nothing to decide,
  so Poulet DG's required *Accompagnement* still opens the composer.
- A **basket panel** standing beside the menu on a wide screen: lines with
  **dish thumbnails**, quantity steppers, a running total and *Commander*.
  Proven on the device: two taps → 8 000 FCFA.
- **Category tiles with icons and dish counts**, the icons chosen for this menu
  (grill, rice bowl, soup, fish, plate) rather than the references' burger and
  pizza. ⚠ Icon comes from the category NAME: the bundle has no icon field and
  adding one re-pins every borne, so that is a scheduled change, not a design
  one.
- The strip falls back to icon-beside-label under 560 dp of height — the
  Samsung is 411 dp tall in landscape and the stacked tile ate the grid.

## ⚠ Two things only the owner can fix, both in the dashboard

1. **Five of nine dishes have no photograph on the borne.**
   `DishPhotoCacheResult(fetched: 2, reused: 2, refused: 5)` — the kiosk accepts
   images from the Supabase host only, and those five are hotlinked elsewhere
   (one is a signed URL that expires). They must be **re-uploaded through the
   dashboard** into the catalog bucket. This is deliberate: a kiosk that
   followed any URL would lose its menu pictures the day someone else's CDN
   expired, which is exactly the outage it exists to survive.
2. **Only one category is published** — "Plats", holding all nine dishes. The
   drinks filter the owner asked for cannot appear until Boissons (and anything
   else) has published products behind it. The strip and the icons are ready
   for them.

## Still open after this pass

- The cuisine is **not yet installed on the Samsung**, so nothing has been
  paired and no order has crossed.
- The **offline drill has not been run**.
- The composer is still the August design — a full-bleed photo and a stepper.
  Matching the app's dish page is the next design step.
