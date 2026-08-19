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
