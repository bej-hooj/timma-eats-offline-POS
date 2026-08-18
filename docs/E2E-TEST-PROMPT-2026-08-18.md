# End-to-end test + fix prompt — borne ↔ cuisine — 2026-08-18

Hand this whole file to the next agent. It is self-contained.

---

You are continuing the TIMMA kiosk (borne) / offline KDS (cuisine) build.
**Read before touching code**: every `.md` in the four repos, `CLAUDE.md`, and
the docs listed under "Read first". Write your plan to disk before the first
edit — the context window can die mid-task.

## Repos (four repos, one database)

| Repo | Role | Head (2026-08-18) | Version |
|---|---|---|---|
| `timmaeat-app-flutter` | customer app + **SCHEMA OWNER**: all migrations, edge functions, the four `pos_*` packages | `91adddf` | — |
| `timmaeat-webapp` | dashboard + landing, `ECOSYSTEM.md`, `design-tokens/tokens.json` | `da605f1` | — |
| `timma-eats-offline-POS` | the kiosk — **and the store hub** | `7c47d9d` | 0.3.1+4 |
| `timma-eats-offline-KDS` | the kitchen board | `76d9ef1` | 0.3.1+4 |

⚠ The app repo's shared checkout may sit on another session's branch — use
`git worktree add /tmp/app main`. Check `git branch --show-current` before every
commit. Never `git add -A`. Both tablets pin `pos_*` at `91adddf`; if a shared
package changes, commit it in the app repo first and move BOTH pins together.

## Read first

- `timma-eats-offline-POS/docs/pairing-ui-2026-08-18.md`
- `timma-eats-offline-POS/docs/kiosk-menu-parity-and-combos-2026-08-18.md`
- `timma-eats-offline-POS/docs/cloud-catalog-and-offline-photos-2026-08-17.md`
- `timmaeat-app-flutter/docs/kiosk-stabilization-2026-08-17.md` (result ledger)
- memory: `timma-kiosk-stabilization-2026-08-17.md`

## Hardware

- **Samsung SM-G975F = the borne.** Wireless adb only; it drops often —
  `adb kill-server && adb start-server`, wait ~8 s, `adb devices`. In landscape
  it is **868 × 411 dp** (read from `dumpsys display` `mOverrideDisplayInfo` +
  `wm density` 420 — `wm size` alone has lied). Keep it awake:
  `adb shell svc power stayon true`. ⚠ **NEVER `svc wifi disable`** — adb rides
  that radio and the phone becomes unreachable until someone taps it.
- **Bocav iPhone 14 Pro = the cuisine**, `D04247C3-CB18-57CE-AC14-54814BB5CA51`.
  **Release builds only** (a debug Flutter build cannot launch standalone on
  iOS 14+: FlutterEngine error, then signal 11). First build for a new device
  needs `xcodebuild -destination "id=<udid>" -allowProvisioningUpdates
  -allowProvisioningDeviceRegistration`, or the profile excludes the handset
  (`0xe8008012`). No CLI screenshot path exists — **you cannot inject taps into
  the iPhone**; ask the owner for those, or use the probe below.
- ⚠ **Bump the build number on EVERY device install.** Shipping two different
  binaries as `0.2.0+2` cost an hour of "which one is on the phone?". Verify
  with `xcrun devicectl device info apps --device <udid> | grep -i timma`.

Apps are named **TIMMA Borne** and **TIMMA Cuisine** (both wear the TIMMA logo,
so the name is the only way to tell them apart from Timma Eats).

## Build commands

```
# borne (Samsung)
cd timma-eats-offline-POS
export SUPABASE_URL=$(sed -n '5p' ~/Desktop/Timma-eats/Supabase.txt | tr -d '\r\n')
export SUPABASE_ANON_KEY=$(sed -n '8p' ~/Desktop/Timma-eats/Supabase.txt | tr -d '\r\n')
flutter build apk --debug \
  --dart-define=SUPABASE_URL="$SUPABASE_URL" \
  --dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY" \
  --dart-define=KIOSK_DEV_BRANCH_ID=10000000-0000-4000-8000-000000000001 \
  --dart-define=KIOSK_DEV_DEVICE_ID=dev-kiosk-samsung-01 \
  --dart-define=KIOSK_DEV_SEED_MENU=true \
  --dart-define=KIOSK_MANAGER_PIN=2468
adb -s <serial> install -r build/app/outputs/flutter-apk/app-debug.apk

# cuisine (iPhone)
cd timma-eats-offline-KDS
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
flutter build ios --release
xcrun devicectl device install app --device D04247C3-CB18-57CE-AC14-54814BB5CA51 \
  build/ios/iphoneos/Runner.app
xcrun devicectl device process launch --terminate-existing \
  --device D04247C3-CB18-57CE-AC14-54814BB5CA51 com.timmaeats.timmaKds
```

## THE END-TO-END TEST

### Phase 1 — borne alone (Samsung, French, adb-driven)
1. Launch. Menu shows dishes **with photographs** and prices.
   Log must show `DishPhotoCacheResult(... reused: N ...)` with **0 fetched** on
   a second launch — photos come from disk.
2. Tap a dish → composer shows the **dish photo** + options.
3. Add → cart row shows the **dish photo**, quantity, price.
4. *Commander* → counter screen: big ticket number, total, and either a printed
   slip or the honest "Ticket non imprimé" + *Réimprimer*.
5. Relaunch → ticket numbers continue (they do not restart).
6. `adb logcat` must be clean: no `FATAL EXCEPTION`, `E/flutter`, `OVERFLOW`.

### Phase 2 — pairing
7. On the borne: **long press anywhere on the attract screen** → PIN `2468` →
   *Responsable*. It shows **"Borne visible sur le wifi"**, the real LAN address
   (e.g. `192.168.1.245:8801`) and `0 cuisine(s) connectée(s)`.
8. Tap **Apparier une cuisine** → six digits + countdown.
9. On the cuisine (iPhone): **Chercher la borne** → tap the kiosk, or use the
   address field beside it. Type the six digits → *Apparier*.
10. The cuisine drops into the board; the borne shows **1 cuisine connectée**.
11. **Restart the borne app, then the cuisine app.** They must find each other
    again with NO re-pairing. (This broke once: the hub used an in-memory
    credential store and forgot every board on restart — fixed in `7c47d9d`,
    verify it stays fixed.)

### Phase 3 — order reaches the kitchen
12. Place an order on the borne. It must appear on the cuisine **immediately**.
13. ⚠ **The alarm is NOT built.** The owner has asked repeatedly for a ring on
    every new order, online and offline. See "Work still to do" #1.
14. Advance the ticket on the cuisine; the borne must follow.

### Phase 4 — offline (the whole point)
15. With both on the wifi box, **unplug the box's internet** (leave wifi on).
    ⚠ Never disable wifi on the Samsung — that kills adb.
16. Borne: menu, prices **and photos** still there. Place a full order.
17. Cuisine: receives it with no internet.
18. Restart the borne with no internet: menu and photos return from disk.
19. Restore internet: orders sync to the dashboard by themselves.

### A cuisine you can drive from a terminal
`timma-eats-offline-KDS/tool/board_probe.dart` (⚠ **unfinished — see #4**) is
meant to pair from the command line using the production `LanPairingClient` and
`LanSocketTransport` and print every board it receives, so phases 2–4 can be
proven without tapping an iPhone:
`dart run tool/board_probe.dart <host> <port> <code>`

## Work still to do, in priority order

1. **The alarm — NOT BUILT.** Asked for repeatedly, never delivered. Every new
   order must ring on the cuisine, online and offline, until acknowledged.
   `timma-eats-offline-KDS/lib/kds/domain/kds_alarm.dart` exists; check it is
   wired to arriving snapshots in `board_screen.dart`, that iOS plays audio in
   silent mode, and that the two registers keep **separate seen-sets** (rule
   already paid for: muting one run must never swallow the next order).
2. **Verify the board-publish fix on hardware.** `LanHubServer.publishBoard()`
   was never called after a kiosk sale (its own doc said the kiosk controller
   must); fixed in POS `fd2fd26` and proven by tests, **not yet on devices**.
3. **Board content.** The cuisine still does not render line items, modifiers or
   notes, does not drain its outbox, and does not verify a slip's collection code
   before completing.
4. **`tool/board_probe.dart` does not compile**: `BoardSnapshot` exposes
   `orders` (of `BoardOrder`), not `tickets`. See `pos_link/lib/src/wire.dart`.
5. **Combos / meals.** Planned in `docs/kiosk-menu-parity-and-combos-2026-08-18.md`
   (M3 client-side meal step, one page, nothing pre-ticked; M4 real dashboard
   combos need a snapshot-contract change). Add-to-cart from the card (M2) is
   also still to do.
6. **`PosOrder` has no `fire_at`**, so the scheduled lane can never fill. Never
   point the board at a branch taking scheduled orders.

## Owner decisions blocking real data

- **No plaintext device key exists.** `pos_devices` holds an active kiosk row for
  branch `10000000-0000-4000-8000-000000000001` with only its **hash**, so the
  borne cannot authenticate to `rpc_menu_snapshot` and runs the seeded sample
  menu (the red DEBUG ribbon). Issuing a key is a production write and needs the
  owner's explicit yes.
- **Two migrations committed and NOT applied**:
  `20260816120000_pos_relay_channel_auth.sql`,
  `20260818100000_kiosk_snapshot_categories.sql`. `pos-relay-token` is
  undeployed. Nothing production-mutating without an explicit yes.

## Rules already paid for — do not rediscover

- A lane is presentation; a transition is a state-machine fact.
  `pending_payment` is settled, never advanced.
- The client never computes a price. Money is integer XAF. min/max count
  DISTINCT options. Required choices are never skipped.
- The collection QR is an HMAC over branch + order identity, not a ticket
  number. The six-digit pairing code **never crosses the wire**.
- **`flutter_test` substitutes a fixed-width font**: text widths and wrapping in
  a widget test are NOT the device's ("Ajouter  4 500 FCFA" measures 418 dp in
  the harness, ~230 on the device). Assert geometry in tests; assert legibility
  on hardware. Seven real layout defects were found only on the device.
- `pos_core` and `pos_link` are **pure Dart** — `dart test`, not `flutter test`.
- Test in **French**, at real widths, on the real medium.
- Fix every defect found in the same pass. Commit and push as you go.

## Suites (all green at handoff)

POS 103, KDS 35, pos_core 120, pos_link 69, pos_link_flutter 17, pos_cloud 58,
edge 9 (`npx deno test` — deno is not installed; npx is how it runs).
