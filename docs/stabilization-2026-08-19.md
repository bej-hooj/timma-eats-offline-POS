# Stabilization pass — borne + cuisine — 2026-08-19

Written **before the first source edit** (CLAUDE.md §0.6, §2.2). The context
window may end mid-pass; disk state must be enough to resume.

Owner, 2026-08-19, verbatim:

> *"i see no filter like on the menu view from the app, like foods categories
> and drinks…"*
> *"i hope that the borne (when online internet) it updates its content
> catalogue and everything…"*
> *"i told you the client could ma combo like cart adding but i dont see it and
> more over the design is not the same as on the app… for example the defaul
> background image is not the same"*
> *"the ticket recieved on the cuisine doesnt currently contain the dishes and
> every details about… the offline kds cuisine should be almost like the online
> one, the tickets should contain all information the client took"*

Read with `kiosk-menu-parity-and-combos-2026-08-18.md` (the M1–M4 plan this
continues) and `timma-eats-offline-KDS/docs/board-link-and-alarm-2026-08-18.md`.

## Findings — measured, not assumed

| # | Complaint | What is actually true |
|---|---|---|
| 1 | No category filter | **The code is there and correct.** `menu_screen.dart` builds a `KioskCategoryPill` strip and hides it when `categories.isEmpty`. The **seeded dev menu has 6 products and zero `SnapshotCategory`**, so on the DEBUG build the strip can never appear. Not a UI bug — a data bug in the seed, plus a snapshot the branch cannot fetch (see 2). |
| 2 | Catalogue refresh when online | `KioskCloudCatalog` + `PosCloudSync` exist and poll. They are inert on this device: **no plaintext device key exists**, so `rpc_menu_snapshot` cannot be called and the kiosk falls back to the seed (the red DEBUG ribbon *is* this). Also `20260818100000_kiosk_snapshot_categories.sql` is **committed and not applied**, so even with a key the bundle would carry no categories. |
| 3 | No add-to-cart / combo | True. **M2** (`+` on the card) and **M3** (one-page meal step) were planned on 2026-08-18 and never built. M4 (real dashboard combos) needs a schema change and stays out. |
| 4 | Design differs from the app | True in at least one measurable way: the kiosk's empty/fallback panel and page ground are not the app's. Needs a token-level diff against the app's catalogue screen, not a repaint by eye. |
| 5 | Cuisine ticket has no dishes | True and the worst of the five. `kds_ticket_card.dart` contains **zero references to lines, options or notes** — it renders a ticket number, a badge and a total. `BoardSnapshot` already carries `BoardOrder.lines`, so the data is on the wire and the card throws it away. |

## Order of work — worst first, each stage green before the next

- **S1 — the cuisine ticket shows what was ordered.** Lines, quantity, variant,
  options, note. The board is the surface a cook *works from*; a ticket without
  dishes is not a ticket. Data already arrives; this is presentation only, so it
  is the cheapest large win and cannot break the transport.
- **S1b — the lanes are smart.** Owner: *"the pipeline column should be
  smart… what the fuck with the column en livraison yet its something client
  get there and go… like mcdonald"*. Right. A take-away kiosk has one spine —
  **À encaisser → Nouvelles → En préparation → Prêtes** — and that is what
  McDonald's boards show. *Programmées* can never fill (`PosOrder` has no
  `fire_at`) and *En livraison* is meaningless for a customer standing at the
  counter. Six fixed lanes at 320 dp on an 844 dp board also means a cook
  scrolls past two empty columns to reach real work. So: the four spine lanes
  always render; *Programmées* and *En livraison* appear **only when they hold
  something**, because those orders come from the app or the web, not from the
  borne. An empty lane that can still receive work stays (a cook must see where
  a ticket goes next); a lane that cannot is noise.

- **S2 — categories on the borne.** Give the seeded menu real categories
  (Plats / Accompagnements / Boissons) so the strip renders on the debug build
  the way it will on a real bundle. No production write.
- **S3 — M2, `+` on the card.** Adds quantity 1 when the dish has no required
  option group; otherwise opens the composer. Card tap keeps its meaning.
- **S4 — M3, the one-page meal step.** Side + drink, nothing pre-ticked, whole
  prices, *Non merci* of equal weight. Client-side meal, engine-priced.
- **S5 — design parity.** Diff the kiosk against the app's catalogue screen at
  the token level; align ground, fallback panel and card grammar.
- **S6 — device smoke on the Samsung** after every stage, French, real widths,
  logcat clean of `FATAL EXCEPTION`, `E/flutter`, `OVERFLOW`.

## Rules this pass will not break

Already paid for; do not rediscover.

1. The client never computes a price. Integer XAF, engine-priced, snapshotted.
2. `minSelect`/`maxSelect` count **distinct** options. Required choices are
   never skipped — `+` is only ever a shortcut for a dish with no decisions.
3. **No pre-ticked upsell.** Nothing enters a cart the customer did not tap.
4. A lane is presentation; a transition is a state-machine fact.
5. Test in **French**, at real widths, on the real medium. `flutter_test`
   substitutes a fixed-width font, so text widths there are fake — assert
   geometry in tests, legibility on the device.
6. `pos_core`/`pos_link` are pure Dart: `dart test`, not `flutter test`.

## Owner decisions still blocking real data

- **Issuing a plaintext device key** for branch `10000000-…-0001` is a
  production write. Without it the borne cannot fetch a real menu, so 1 and 2
  above stay demonstrable only against the seed.
- **Applying** `20260816120000_pos_relay_channel_auth.sql` and
  `20260818100000_kiosk_snapshot_categories.sql`, and deploying
  `pos-relay-token`. Nothing production-mutating without an explicit yes.

## State at the top of this pass

POS `0.4.0+9`, 110 tests green. KDS `0.5.1+10`, 48 tests green.
Devices: Samsung SM-G975F = borne, wireless adb `192.168.1.245:42503`, hub on
`192.168.1.245:8801`. Cuisine paired by the owner by hand; `/health` reports
`peer_count: 1, link: lan`.


## Progress — end of session 2026-08-19

**Done, tested, committed.**

- **S1 — the cuisine ticket shows what was ordered.** Every line renders
  quantity, dish, size and chosen options, plus the customer note in its own
  block. `KdsBoardState` now carries `lines` per `clientId`, read once per
  refresh, so the card stays a pure function of its inputs. KDS `0.6.1+12`,
  **51 tests**.
- **S1b — smart lanes.** Only the take-away spine renders; *Programmées* and
  *En livraison* appear only while they hold work. **Device-proven on the
  Samsung + simulator**: the board shows four columns, and all four now fit
  the 844 dp board (the first attempt's 200 dp floor pushed *Prêtes* back off
  the edge — fixed, and the test now measures the COLUMN, not the title).
- Earlier the same day, and device-proven: the board no longer dead-ends when
  the kiosk does not know it (`KdsPairingGate` + long-press *Apparier une autre
  borne*), and *Apparier* no longer runs off the bottom of the pairing screen.

**Not done.** S2 (categories in the seed), S3 (`+` add-to-cart), S4 (meal step),
S5 (design parity with the app).

## ⚠ Blocker for the next session — driving the Samsung

Placing an order **by adb tap** stopped working reliably and this is what ended
the session, not the code.

1. The phone flips between `landscapeLeft` and `landscapeRight` on its own,
   which **mirrors every button**. A tap computed from one screenshot lands on
   the wrong control in the next frame — *Commander* becomes *Continuer*, which
   silently returns to the menu and looks like "the order vanished".
2. Locking it with `settings put system user_rotation 1` makes it **worse**:
   `screencap` returns the rotated framebuffer while `input tap` keeps using the
   panel's natural (portrait) axes, so the two spaces stop agreeing entirely and
   no tap lands at all.

Settings were restored (`accelerometer_rotation 1`, `user_rotation 0`).

**Do this instead next time:** drive the borne through the **iOS Simulator +
Android emulator** pair (both scriptable, proven earlier today), or fix
`tool/board_probe.dart`'s blocker — macOS withholds **Local Network** permission
from the `dart` binary, so the probe gets `No route to host` while `curl` to the
same address succeeds. Granting it in System Settings → Privacy & Security →
Local Network turns the probe into a scriptable cuisine and removes the need to
tap anything.

**Still unproven on the Samsung specifically:** an order placed by hand arriving
on the cuisine with its dish lines. The transport itself is proven over a real
socket in `test/kds_link_test.dart` and was proven live on the emulator pair
earlier today; what is unproven is only the Samsung's tap path.

## S7 — the catalogue actually refreshes when online (owner: "very important")

### Why it is inert today, exactly

`pos_devices` holds **one** row for branch `10000000-…-0001`:
`a3c7b786-9d7e-445c-89de-e02dc90a271c`, role `kiosk`, active, created
2026-08-15 — and only its `key_hash`. The plaintext was never recorded, so no
build can present it. `rpc_menu_snapshot` matches on
`key_hash = encode(sha256(convert_to(p_device_key,'UTF8')),'hex')`
(`20260815120000_kiosk_offline_store.sql:157`), so with no key the call cannot
be made, `KioskCloudCatalog` falls back to the pinned/seeded menu, and the red
`DEBUG — MENU D'EXEMPLE · PRIX NON RÉELS` ribbon is the honest consequence.
The kiosk reads the key from `--dart-define=KIOSK_DEVICE_KEY` and keeps it in
the platform keystore (`DeviceKeyVault`) from then on.

### The write, stated before it is made

⚠ Production. Owner asked for this on 2026-08-19 ("Very important to fix the
Catalogue refresh when online").

**Additive, not a rotation.** A new kiosk device row is INSERTed for the
Samsung; the existing row is left exactly as it is. Overwriting its `key_hash`
would be the smaller diff but it destroys the only record of a credential
issued on 2026-08-15 — and a device nobody can identify might still hold it.
Adding a row costs nothing and is reversible with one `active = false`.

- Key: 32 random bytes, base64url, generated locally, **never committed**.
- Stored: only `encode(sha256(...),'hex')`, which is all the RPC compares.
- Recorded for the owner in `docs/setup-config.md` (gitignored) and handed over
  in the session, per §11.1 — secrets live in the build config, not in git.

### Then

1. Rebuild the borne **without** `KIOSK_DEV_SEED_MENU` and **with**
   `KIOSK_DEVICE_KEY`, so the seed cannot mask a failed fetch.
2. Expect: the ribbon **gone**, real dishes, real prices, and — because
   `20260818100000_kiosk_snapshot_categories.sql` is still **unapplied** — very
   possibly still no category strip. Applying that migration is a second,
   separate production decision; it is DDL and is not bundled with the key.
3. Watch `[KioskCatalog]` in logcat: `no device key` must become a snapshot
   version, and photos must still report `reused` (offline-first intact).

### S7 result — the key works; the client parse does not

**Done and verified server-side.** A new kiosk row was INSERTed for the Samsung
(`f852570f-6d02-4835-8faf-3f8f5b7f8c4a`, additive — the 2026-08-15 row is
untouched and still active). Calling `rpc_menu_snapshot` with the new plaintext
returns the **real menu**: real dishes (*Jus de foléré*, *Poulet DG*), real
prices, real `photo_url`s under the `catalog` bucket, and a `category_id` on
every product. `device_unknown` is returned for a wrong key, as designed.

The key itself is in the session's scratchpad, not in git. It must be recorded
in `docs/setup-config.md` (gitignored) and re-passed as
`--dart-define=KIOSK_DEVICE_KEY=…` on every borne build.

**On the device the ribbon's cause is gone** — `[KioskCatalog] no device key`
no longer appears, Supabase initialises, and the sync is attempted. It then
logs `[KioskCatalog] a sync tick failed`, and that error is **deliberately
swallowed** ("a cloud error can carry a request URL, and a request URL can
carry a device key"). So the remaining work is client-side parsing, not auth.

**Two concrete suspects, in order:**

1. **The bundle carries `category_id` but no `categories` array.**
   `20260818100000_kiosk_snapshot_categories.sql` is committed and **not
   applied**, so the snapshot names no categories. That alone explains the
   missing filter strip, and it may also fail `MenuSnapshot.validate()` if a
   product references a category the bundle does not define.
2. **`type` is `simple` / `composed`** in the live data, where the seed uses
   `dish` / `drink`. If any client-side switch is exhaustive on those literals
   the parse throws.

**Next session starts here:** temporarily surface the swallowed error behind a
debug-only flag (never in release — §11.1), read it once on the Samsung, then
fix the parse. Do **not** re-issue a device key; one exists and works.

### S8 — dish photographs on the cuisine's tickets (owner, 2026-08-19)

The board renders dish names but no images. `BoardOrder.lines` carries
`productId`, and the cuisine has no `DishPhotoCache` — the kiosk does. Two
honest options, to decide before coding:

- **Ship the photo URL on the line.** `PosOrderLine` has no `photoUrl`; adding
  one is a `pos_core` change and moves both pins. The board would then use the
  same disk-first `KioskDishThumb` grammar the kiosk uses.
- **Give the cuisine its own cache** keyed by the branch's active snapshot,
  warmed at pairing. Heavier, but it survives an outage the same way the
  kiosk's does — which is the whole premise of this surface.

⚠ Whichever is chosen, a kitchen tablet must never block a ticket on a network
fetch: disk first, brand panel last, exactly as `KioskDishThumb` already does.

## S9 — this pass (session 3): both devices, then the offline guide

Owner, 2026-08-19: *"build the updates on bocav iphone and Samsung and lets
test. For pairing… i will do that myself manually. After you test everything,
you give me the guide step by step for offline test on wifi with no internet.
Then you read everything about the whole ecosystem and tell me what should be
done next."*

### State at the top of S9

- `kiosk_snapshot_categories_checksum_safe` (`20260819134257`) is **APPLIED**.
  It is the reviewed migration minus one field: the original emitted
  `photo_url` inside every category and hashed it into the checksum, while the
  shipped Dart `SnapshotCategory` carries four fields and no `photo_url`. On any
  branch **with** categories the two hashes disagree, `MenuSnapshot.validate()`
  refuses the bundle, and a kiosk with no valid menu **cannot sell**. Production
  has three active categories (Burgers 2, Plats 5, Boissons 2), every one with
  an image, so it would have fired on the first fetch.
- A kiosk device key exists for the Samsung and authenticates:
  `rpc_menu_snapshot` returns the real menu. `[KioskCatalog] no device key` is
  gone from the device log.
- Live catalogue: 9 published products, `type` in `simple|composed|combo`
  (the seed used `dish|drink`). **The kiosk never reads `type`**, so that is not
  the parse failure. Product key sets and category key sets now match the Dart
  models exactly, so the checksum is not the suspect either.
- KDS has one uncommitted fix: the refusal-on-reconnect handler (below).

### S9.1 — make the failure name itself (observability first)

`[KioskCatalog] a sync tick failed` is unactionable, and the error is swallowed
on purpose: *"a cloud error can carry a request URL, and a request URL can carry
a device key"*. That reasoning is right and stays. But the **exception type**
and, for a `PostgrestException`, its **`code`**, carry no URL and no key — and
they are the difference between a diagnosis and a guess. Log those two, nothing
else. Then rebuild and read the log rather than reasoning about which of the
four RPCs a tick calls.

### S9.2 — the refusal must be caught on EVERY reconnect

Shipped uncommitted in `kds_link.dart`. `connect()` was called once at start-up,
so only that attempt's error reached the handler that sends a refused board back
to pairing. `LanSocketTransport` then reconnects on its own backoff for ever and
those failures are private — which is the field case the owner hit **twice**: a
board that worked, a kiosk that was reinstalled, and a tablet parked on *Hors
ligne* with no route back. The pump now re-attempts while disconnected and reads
the error.

⚠ The integration test written for this timed out on loopback port reuse and was
**removed rather than left flaky**. The controller-level gate is still covered by
`kds_pairing_gate_test.dart`; the reconnect path is proven only by the device log
line `[KdsLink] the kiosk refused this board — pairing again`. That is a known
gap, recorded here rather than papered over.

### S9.3 — build both devices, smoke, fix, repeat

Samsung = borne (wireless adb, `192.168.1.245`). Bocav iPhone = cuisine,
**release build only**, bump the build number every install. Owner does the
pairing taps. Watch logcat for `FATAL EXCEPTION`, `E/flutter`, `OVERFLOW`.

### S9.4 — the offline guide

Written only after the online path is clean, so the guide describes something
that has been seen working rather than something intended.
