# Roles, TV display, merchant code, day menu, live sync, new logo — 2026-11-25

> **Next agent: follow `IMPLEMENTATION-GUIDE-roles-tv-logo-2026-11-25.md`** (step-by-step for S5, S7, S8, S9, S6).

Owner request of 2026-11-25 (whole ecosystem: app, web, cuisine, borne).
**This file is the plan AND the results log.** A fresh session resumes from
here alone. Canon summary: `timmaeat-webapp/ECOSYSTEM.md` §25.
Rules followed: `~/Downloads/vibecoding coding code Prompt instructions rules Suffix (1).md`
(clean/feature architecture, no secrets in code, tests, **never deploy / apply a
migration / upload without explicit owner approval**).

Status legend: ⬜ planned · 🟨 in progress · ✅ done (built + tested) · 🚫 blocked on owner

---

## 0 · What already exists (read before planning — do not rebuild it)

| Need | Already there | Gap |
|---|---|---|
| Web/app orders reach the cuisine | Borne = hub. `PosCloudSync` pulls `rpc_order_feed` every **5 s**, merges as `origin: remote`; the cuisine is a LAN peer of the hub and gets every board snapshot. Paid CamPay orders arrive as `placed` → lane **Nouvelles**. | ⛔ the feed returns **every** branch order, so an online order still **waiting for CamPay** (`pending_payment`, source app/web) lands in **À encaisser** as if a customer owed cash at the counter. |
| Dashboard ↔ cuisine connected | Cuisine taps → hub outbox → `rpc_device_transition_order` (2 s drain). Dashboard moves come back through the feed (`advanced`). | Not re-proven on hardware since November. Historical cloud tickets sit in *Prêtes* for ever ("141061 min"). |
| All cuisines on one wifi show the same thing | Any number of boards pair to one hub (`peer_count`), each receives the same snapshot. | Nothing — keep. |
| Borne updated from the dashboard | Menu pinned at boot; feed/drain/heartbeat loops. | No periodic **re-pin** of the menu, no settings/roster/day-menu pull. |
| Dish not cooked today | `menu_days` + server rule `fn_assert_on_menu` (fails OPEN on a day with no published menu). Kiosk RPC deliberately unpatched (offline sales must never be refused later). | Borne shows every dish every day. |
| Merchant code | — | Nothing anywhere. |
| Roles on the cuisine | — | One view for everyone. |
| TV | — | Nothing. |

Branch facts (2026-11-25):
- App repo: `claude/app-updates-stabilization-7vpamf` (app 1.5.1, Sept) and
  `fix/kiosk-snapshot-categories-2026-11-22` (`6b1de23`, all pos_* work, Nov)
  **diverge** from `5a43079`. Neither is in `main`. Work branch for this task:
  **`feat/roles-tv-logo-2026-11-25`** = stabilization branch + merge of the fix
  branch (the fix branch only touches `packages/` + one migration).
- Tablet repos pin pos_* by **full 40-char SHA**; bump POS and KDS together.

---

## 1 · Decisions (taken on the owner's standing rule "go with my recommendation")

1. **One hub, unchanged.** The borne stays the only writer to Supabase (§23.2).
   The cuisine never talks to Supabase; everything — roster, photos, settings —
   reaches it over the paired, encrypted LAN session. No split brain.
2. **Online orders: only PAID ones reach the board.** `pending_payment` from
   source `app`/`web` is not the kitchen's yet → no lane. A kiosk
   `pending_payment` (cash owed at the counter) still goes to *À encaisser*.
   `pay_at_counter` / `cash_on_delivery` web orders are `placed` and go to
   *Nouvelles* as today (they are accepted orders, paid later).
3. **Roles = accounts made in the dashboard**, verified **offline** on the
   tablet. Table `kitchen_accounts` (login, role, password hash, active), hash
   = **bcrypt, cost 10** (CLAUDE.md §11.11 forbids anything but Argon2id/bcrypt;
   Laravel `Hash::make` writes it, the tablet verifies with the pure-Dart
   `bcrypt` package — the one new dependency, justified by §11.11). Plaintext never stored, never sent.
   Roles: `kitchen` → lanes *Nouvelles → En préparation → Prêtes*
   (+ *En livraison*/*Programmées* when they hold tickets); `cashier` → *À
   encaisser* only; `display` → the TV screen (§G); `manager` → everything.
   ⚠ **Backward compatible:** while the branch has **no** active account, the
   board stays the full board it is today with a banner *Aucun accès
   configuré* — a working kitchen is never locked out by an empty table.
   5 wrong passwords → 30 s lockout. Session survives app restart; *Changer
   d'accès* logs out.
   ⚠ The role is an **operational** gate on a trusted, paired device, not a
   cryptographic one: the trust boundary stays the pairing approval (manager
   PIN on the borne). Documented, not hidden.
4. **Roster transport:** hub pulls `rpc_kiosk_staff_roster(device_key)` (only
   hashes leave the DB, only to a device key), stores it, and sends a new
   `roster` frame to every authenticated board on connect and on change.
5. **Merchant codes** per branch in a new table `branch_payment_codes`
   (provider `mtn_momo` | `orange_money`, code, holder name, active, sort),
   dashboard-edited, pulled by the hub through `rpc_kiosk_settings`, cached,
   shown on the borne's ticket screen ("Pas d'espèces ? Payez par Mobile
   Money") and printed on the slip. The cashier then settles with tender
   *Mobile Money* (the tender enum already has `mobile_money`).
6. **Day menu on the borne:** `rpc_kiosk_day_menu(device_key)` returns the
   published `menu_days` for today → +13 days and the `menu_day_enforced`
   switch; cached (two weeks offline). **Same fail-open rule as the server**:
   a day with no published menu restricts nothing. Hidden dishes are not drawn
   and not counted in category counts. A *Menu de la semaine* button opens a
   view of every dish with the days it is cooked. Kept **out of the menu
   snapshot** on purpose: adding it would change the checksum contract and
   re-pin every borne for a non-price fact.
7. **Live sync loop:** `PosCloudSync` gains a `catalogInterval` (60 s) tick:
   re-pin the menu (already waits for an idle borne), pull settings, roster
   and day menu. A failed tick = offline; the first successful tick after a
   failure triggers an immediate full refresh ("as soon as the internet is
   there"). The cuisine follows automatically through the hub.
8. **TV (customer order display):** see §G — a fourth role of the **cuisine
   app**, so it pairs, survives offline and updates exactly like a board.
   Shows **only borne orders** (`source = kiosk`): *En préparation* and
   *Prêt*, by ticket code, with a chime + French voice
   (`flutter_tts`, Android TextToSpeech / Windows SAPI; chime-only fallback).
9. **Logo:** `~/Downloads/maat/` = horizontal wordmark (1 = gold on dark,
   2 = green on light) → every header bar. `~/Downloads/tamm/` = arch mark
   (1 = green, 2 = gold) → every app icon / favicon. Each old asset is
   replaced by the new one of the **same colour role and shape**.

---

## 2 · Stages (each one builds, tests green, is committed; nothing is deployed)

| # | Stage | Repos | Status |
|---|---|---|---|
| S0 | Work branch `feat/roles-tv-logo-2026-11-25` (stab + fix merge) | app | ✅ `bbd0018` |
| S1 | Lane fix: unpaid online orders hidden (stale-ticket bound REVERTED, see log) | KDS | ✅ KDS `e219ff5` |
| S2 | Migrations **written, not applied**: `kitchen_accounts` + roster RPC, `branch_payment_codes` + settings RPC, day-menu RPC | app | ✅ written (not validated — no local Postgres) |
| S3 | `pos_cloud`: gateway calls + BranchConfigSync + `unchanged` fix; `pos_link`: sealed `roster` frame | app packages | ✅ `974001c` pushed |
| S4 | Borne: merchant code on ticket screen; day filter + *Menu de la semaine*; 60 s re-pin fix; hub roster | POS | ✅ `6561dfb` (slip printing of the code NOT done) |
| S5 | KDS view picker « Cuisine » / « Caisse paiement » (NO login, owner) + dead roster code deleted | KDS, packages, POS | ✅ KDS `82bfb6a`, pkgs `072083e` |
| S6 | KDS: TV role (display screen, voice, Android TV launcher) | KDS | ⏸ **ON HOLD — owner wants to discuss the TV first (2026-11-25)** |
| S7 | New logo: icons+wordmark (earlier), `TimmaMark` = new mark asset (app splash + borne), web favicon/touch icon/landing mark | all | ✅ app `541e88e`, POS `7a45823`, web `9aad51b` (web NOT deployed) |
| S8 | S8a *Accès KDS* CANCELLED (no login); S8b *Codes marchands* on Settings | web | ✅ S8b `1f35a8b` (NOT deployed; needs migration 120100) |
| S9 | Pin bump both tablets, builds, device tests, docs/memory/ECOSYSTEM | all | ⬜ |
| S10 | À encaisser tickets never auto-expire + cashier delete icon with confirmation → server cancel | KDS, pos_core, server | ✅ KDS `bcc5361`+`b1f445c`, pkgs `8bb93d8`, cron migration APPLIED |
| S11 | KDS ↔ cloud ↔ customer verification | server | 🟨 notification regression FIXED + APPLIED `20261125190000`; hardware drill not run |
| — | **Owner approval needed**: apply the 3 migrations, deploy web, publish APKs | — | 🚫 |

---

## G · The TV — how McDonald's does it, and what we build

**What McDonald's uses:** a *Customer Order Display* (COD) — ordinary
commercial screens (43–55") hung in the dining room, each driven by a small
media player / mini-PC wired to the restaurant network. The player subscribes
to the same order bus as the kitchen screens and draws two columns,
*Preparing* and *Ready*, by order number, with a chime when a number moves to
Ready. It is not a special TV; it is a screen + a small computer + software.

**Our equivalent (no new server, works offline):**
- Software: the cuisine app in role **`display`** — paired to the borne like
  any board, so it keeps working with the internet down.
- Hardware, either:
  1. **Recommended:** any HDMI TV (32–55") + an **Android TV box** (Android 9+,
     e.g. Xiaomi TV Box S, Google TV Streamer, or similar) on the restaurant
     wifi (ethernet better). The cuisine APK installs on it (leanback launcher
     entry added). Sound through the TV speakers.
  2. A **Windows mini-PC** on HDMI running the existing Windows cuisine
     installer, logged in as `display`.
  3. A cheap Android tablet with HDMI-out (fallback).
- Screen: two big columns, *En préparation* (amber) / *Prêt — à récupérer*
  (green), 4-character ticket codes in very large type, newest *Prêt* code
  highlighted for 10 s. A *Prêt* code leaves the screen when the order is
  completed at the counter (or after 15 min).
- Voice (French): « Commande A D 4 5 — en préparation. » / « Commande A D 4 5
  est prête. » Characters spelled one by one, chime first, utterances queued
  so two moves never talk over each other. Mute toggle behind the role login.
- **Only kiosk orders** (`source = kiosk`). App/web customers follow their own
  journey in the app.

---

## 3 · Test plan

- Unit: lane rule (online unpaid hidden, kiosk unpaid in counter, stale bound),
  bcrypt verify against a hash produced by Laravel `Hash::make`, role → lanes
  map, lockout clock, day-menu filter incl. fail-open + Douala midnight, TV
  transitions → utterances (no repeat on a re-sent snapshot), roster frame
  encode/decode, merchant-code rendering when none defined (section absent).
- Package suites: `dart test` in pos_core / pos_link / pos_cloud.
- Tablet suites: `flutter test` + `flutter analyze` in POS and KDS.
- Web: `php artisan test` + pint for the two CRUD modules.
- Hardware (after owner applies migrations): borne Samsung + cuisine GM92,
  then a TV box if available.

---

## 4 · Results log

**Naming (owner, 2026-11-25): the cuisine app is called "KDS".** Use that name
in UI strings and docs from now on.

- **S1** — `KdsLane.laneFor`: `pending_payment` goes to *À encaisser* only when
  `payment_method = pay_at_counter` (mirrors `PosStore.counterLane()`); a
  CamPay order awaiting payment has no lane. 3 tests, the first proven to fail
  without the fix. KDS 111/111, analyze clean.
  ⚠ The "18 h service window" to hide 97-day-old tickets was written and
  **reverted**: the KDS compares the borne's `placedAtDevice` to its OWN clock,
  so a KDS with a wrong clock would hide every live ticket. Root fix belongs on
  the server (close the stale historical orders) — open item.
- **S2** — 3 migrations `20261125120000/120100/120200`. Names checked free in
  production (read-only query). **Not applied, not dry-run** (no local
  Postgres on this Mac). Needs owner approval.
- **S3** — found while reading: **a running borne never re-pinned the menu**.
  `KioskCloudCatalog.refresh()` calls `PosCloudSync.start()`, idempotent after
  boot; and even a real re-pin of an unedited menu got `{unchanged:true}` from
  the server, which the source refused as "no checksum". Both fixed in the
  package (`MenuSnapshotUnchanged`, `isStarted`); the POS call site is S4.
  Roster frame is **sealed per board** (AES-256-GCM, HKDF of the board's
  pairing secret) because LAN frames are signed but readable.
  Tests: pos_core 155 · pos_cloud 72 · pos_link 93 · pos_link_flutter 21, all green.
- **S4** — borne: `KioskCloudCatalog` re-pins with `refreshMenu()` once
  started, every 60 s, and pulls `BranchConfigSync`; `kioskBranchConfigProvider`
  + `kioskConfigRevisionProvider` (lib/kiosk/branch_config/); menu screen
  `isOnToday` filter (Douala date computed only when a schedule exists — the
  widget tests have no tz database) + calendar button → `KioskWeekMenuSheet`;
  `KioskMobileMoneyPanel` on the ticket screen while unpaid; hub
  `rosterSource` + `publishRoster()`. Borne 195/195 green, analyze clean.
  Not on hardware yet (migrations not applied → the three RPCs fail and the
  borne simply shows no codes/no restriction, by design).

## ⚠ DECISION CHANGE (owner, 2026-11-25) — NO login/password on the KDS
Owner: "no need for id and password. We open the KDS and just choose
« Cuisine » or « Caisse paiement »."
So S5 becomes: a role picker on the KDS (two big buttons, choice remembered on
the device in its store meta, a « Changer de vue » button to switch back).
Cuisine = Nouvelles → En préparation → Prêtes (+ Programmées/En livraison when
non-empty); Caisse paiement = À encaisser only. Use `KdsAccess.lanesFor` from
the guide; ignore every bcrypt/login/lockout step.
Consequences:
- Do NOT apply `20261125120000_kitchen_accounts_roster.sql` (it was declined
  anyway) — delete that migration file, and remove the now-dead roster code
  (pos_core `kitchen_roster.dart`, pos_link `roster_seal.dart` + `roster`
  frame + `rosterSource`/`publishRoster`, pos_cloud roster pull, borne hub
  wiring) in one commit, tests green, re-pin both tablets (CLAUDE.md §0.10:
  delete dead code). S8a (dashboard Accès KDS) is CANCELLED; S8b (merchant
  codes) stays.
- ECOSYSTEM §25.2 must be rewritten to "role chosen on the device, no
  credentials".

## S11 · Precisions (owner, 2026-11-25, later) — KDS ↔ cloud ↔ customer apps
**A. Online orders (app/web, already paid via CamPay)** land in the dashboard
web KDS AND in the « Cuisine » view of the KDS app (*Nouvelles*). When the KDS
app moves one to *En préparation* and later *Prêt*, the database must be updated
so the customer app/web *Suivi de commande* updates and the customer gets the
push (to the right account, right device, right order).
**B. Borne orders**: when « Caisse paiement » marks a ticket encaissé, the
server must receive the paid ticket with ALL details (ticket code, every dish
and drink, options, removals, totals, tender) — for accounting.
**Both:** offline → kept locally, sent as soon as internet returns.

### Design decision (secure, reuse what exists)
- The KDS must NOT store customer FCM tokens, account or device data: that is
  PII on a shared kitchen tablet (CLAUDE.md §11.6). It sends only
  `order_id + new status`; the SERVER already knows order → user → devices →
  tokens and targets the right app/account. Same result the owner wants, no
  leak.
- Path that already exists (§23): KDS tap → envelope to the hub (borne) →
  hub outbox (SQLite, survives reboot) → `rpc_device_transition_order` /
  `rpc_device_mark_counter_paid` every 2 s when online. Borne sales go up as
  `place_order` envelopes with every line snapshotted.

### Verify first (next session — read before coding)
1. Does `rpc_device_transition_order` → `fn_transition_order` create the
   customer notification (in-app `notifications` row + push via
   `20260810180000_notifications_push_trigger`) exactly as the dashboard web
   KDS does? Test read-only on a real order id. If not → migration (owner yes).
2. Does a kiosk sale reach `orders`/`order_items` with ticket number, station,
   lines, modifiers, removals, tender + `payment_status=paid` after
   « encaissé »? Check `rpc_place_kiosk_order` + `rpc_device_mark_counter_paid`
   payloads; the tender (cash / mobile_money) must be sent — today
   `settleCounter` may not carry it.
3. ⚠ Weak point: KDS envelopes go to the HUB first. If the borne is off, KDS
   actions queue on the KDS until the borne is back. Document; consider later
   letting the KDS drain directly to the cloud (needs a KDS device key).
4. Prove on hardware: CamPay order → KDS Nouvelles in ≤ 5 s → En préparation
   → customer app shows it + push; offline drill (WAN unplugged) then replay.

## Results — session 2 (2026-11-25, evening)

- **S10 delete icon** — `PosEngine.cancelUnpaid(clientId)`: only an order
  awaiting counter payment; queued as `transition → cancelled` with reason
  `unpaid_at_counter` (the server's `fn_transition_order` already allows
  `pending_payment → cancelled` for a device but REQUIRES a reason — no
  migration needed). Hub applier routes a KDS cancel through the strict path
  (a KDS cannot cancel a paid order); cloud sink passes `p_reason`. KDS: trash
  icon beside *Encaisser* on unpaid counter tickets only, dialog « Supprimer le
  ticket X ? La commande sera annulée. » Dead expiry summary line removed.
  Tests: pos_core +3, pos_link +1, pos_cloud +1, KDS +5 (widget: Garder keeps
  it, Supprimer cancels; paid ticket has no icon).
- **S11 verification** —
  1. ⛔ **No order-status notification has been written since 2026-08-14.**
     `20260815170000_kiosk_cloud_feed` moved `rpc_transition_order` into
     `fn_transition_order` and dropped the `notifications` insert of
     `20260810120000`. Live check: last `order_*` row 2026-08-14 19:49 UTC; no
     trigger on `orders` creates one. Dashboard AND KDS paths are both silent.
     Fix written from the LIVE definition: `20261125190000_restore_order_status_notifications.sql`
     — **NOT applied, needs the owner's yes.** It fixes both paths at once;
     the KDS still sends only `order_id + status` (no PII on the tablet).
  2. Borne sale → `orders`/`order_items`: ticket number, station, every line
     with modifiers/removals snapshotted ✅. Settle → `paid`, `status placed`,
     `tender = cash` ✅ (`rpc_device_mark_counter_paid` hardcodes cash).
     ⚠ Open owner decision: Mobile Money at the till (merchant code). The KDS
     records cash only by design (§7.4) and the server requires a `tender_ref`
     for `mobile_money`; recording MoMo payments needs a « Payé Mobile Money »
     button + typed transaction ref + migration. Today a MoMo payment would be
     booked as cash.
  3. Weak point documented: KDS envelopes go via the borne; borne off = KDS
     actions queue on the KDS until it returns.
  4. NOT done: hardware drill (CamPay order → KDS → customer push; WAN unplugged).
- **S5** — `lib/kds/access/` (`kds_view.dart` lanes per view,
  `kds_view_controller.dart` meta key `kds.view`, `kds_view_picker.dart`).
  `KdsRoot`: paired + no view → picker. Board lanes and ALARM filtered by view.
  « Changer de vue » is icon-only (with the label it overflowed the 844 dp
  header by 142 px — caught by the header-fit test). Roster/bcrypt code deleted
  everywhere + `20261125120000` migration file deleted. KDS 126/126.
- **S7** — `assets/branding/timma_mark.png` (tamm/1 trimmed, white on alpha)
  in app + POS; `TimmaMark` = tinted `Image.asset`; splash delivery box paints
  the decoded asset (`TimmaMarkAsset.load/paintInto`). Native splashes carry no
  logo (checked). Web: `icons/timma-icon-2026-{16,32,180,512}.png`,
  `images/timma-mark-2026.png`, new `favicon.ico` requested as `?v=2026`;
  public `_head` gained a 32 px PNG + apple-touch icon. Inline wordmark was
  already new. Web NOT deployed.
- **S8b** — Settings › « Codes marchands Mobile Money » (see
  `timmaeat-webapp/storage/Project_Documentation/Settings/PaymentCodes.md`).
- Pins: both tablets on `072083e2f1df09f7e5b59cc9c0c7a43b0ea7ae4d`.
- Suites: pos_core 154, pos_link 89, pos_cloud 73, pos_link_flutter 21, app
  876, borne 195, KDS 126, web 1182 (all green after fixes).
- **Owner approval needed:** apply `20261125120100` (merchant codes) and
  `20261125190000` (notifications); deploy web; build/publish APKs (S9).

- **Migrations APPLIED 2026-11-25 (owner yes):** `20261125120100` (merchant
  codes; trigger now `create or replace` — the Supabase connector silently
  auto-declines any migration containing DROP, which is why it was "declined"
  three times with no prompt) and `20261125190000` (notifications). Verified:
  table RLS on, anon/authenticated no table access, `rpc_kiosk_settings`
  executable by anon; rolled-back probe on a real order wrote exactly one
  `order_cancelled` row « Votre commande TM-100136 a été annulée. », order
  untouched after. Remaining owner steps: web deploy, APKs + hardware drill.

## Session 3 (2026-11-25, night) — hardware test + owner decisions

### Owner decisions
- **Mobile Money at the till stays CASH** — the payment happens outside the
  system with no backend confirmation; the cashier settles as cash. Final.
- **Merchant code printed on the slip** — DONE `75f280b`.
- **TV (S6) — behaviour decided, hardware still to choose:**
  1. Voice announces BOTH « en préparation » and « prête ».
  2. A « Prêt » number stays **3 minutes**. While several are ready, the TV
     **rotates** the announcements: « Commande XXXX est prête » + the ticket
     code spelled + **the dishes and drinks on it**.
  3. Voice always on (no chime-only mode).
  4. **Several TVs** (each one a paired display, same as several KDS).

### Test rig
- Borne: new AVD `Timma_Borne_Tablet` (2560x1600 @280, landscape, Android 37),
  borne 1.0.1+2012, device id `borne-emulator-tablet`. 16 iOS simulators deleted.
- KDS + customer app on the Samsung S10 (adb wifi 192.168.1.245).
- The emulator is NAT'd: test-only bridge = `adb forward tcp:8801` + a Python
  relay on the Mac's LAN IP 192.168.1.90:8801 (scratchpad, not in any repo).
  On a real LAN the borne is reached directly — no bridge.

### Verified on hardware
- Picker « Cuisine » / « Caisse paiement » ✅; pairing by one tap with matching
  numbers ✅; new logos (app splash/home, borne, KDS) ✅.
- Borne sale → server `rpc_place_kiosk_order` 200 in < 1 s → KDS *À encaisser*
  in < 6 s with trash icon ✅; delete dialog ✅; ticket leaves the KDS ✅.

### ⛔ Found on hardware (fixed in code, one needs the owner)
1. **No KDS action on a borne ticket has ever reached the server.** The KDS
   delete was retried every 2 s with HTTP 400: `rpc_device_transition_order`
   and `rpc_device_mark_counter_paid` demand a `kds` key, the hub relays with
   its `kiosk` key, and production has no `kds` device. Encaissé / accepter /
   prêt on borne orders have been stuck in borne outboxes since 2026-08-15.
   Fix `20261125200000_hub_may_relay_kds_actions.sql` — **WRITTEN, NOT
   APPLIED (owner yes)**. Queued envelopes drain by themselves once applied.
2. KDS showed « Ticket 01 » while the borne told the customer « HQJ7 »: the
   LAN wire dropped `station_code`. Fixed `151adba` (+2 tests).
3. KDS header said « Cuisine » in the cashier view; gold wordmark invisible on
   cream; title truncated beside the alarm — all fixed.
- Pins now `151adba60931769291f04ed7bfd24c6a57862f4e` (both tablets).

### Session 3 — later
- ✅ `20261125200000_hub_may_relay_kds_actions` APPLIED (owner yes). Proven on
  hardware: ticket HQVU sold on the borne, deleted on the KDS → server
  `cancelled / unpaid_at_counter` within ~2 s. KDS card now reads « Ticket
  HQVU » = the customer's code.
- ⚠ Envelopes refused 5× BEFORE the fix were QUARANTINED on the borne (no
  retry, no replay UI). TM-100152 (test) was closed server-side by hand.
  Open item: a manager "rejouer" action for quarantined envelopes, or
  automatic re-try of quarantined envelopes after a server change.
- Day menu: the borne pulls it fine; the dashboard schedule simply ended
  2026-09-23, so nothing was restricted and the week button (hidden when no
  schedule) never showed. Button now ALWAYS shown, labelled on wide screens
  (`POS` commit « Menu de la semaine is always offered »).
- Owner asked: 4 dishes for today → `menu_days` 2026-11-25 = Ndolé, Poulet DG,
  Koki, Eru (published). ⚠ `menu_day_enforced` is on, so the app and the web
  also offer only these 4 today.

### ✅ End-to-end online order, real devices (2026-11-25 20:11–20:13)
TM-100154, Koki at 10 FCFA (test price, restored to 2 000 right after), pickup,
CamPay / Orange on the owner's number, approved by the owner on his phone.
| Step | Proof |
|---|---|
| Payment confirmed | app « Payment confirmed », push « Paiement reçu », DB `placed/paid` 19:11:55 UTC |
| KDS *Nouvelles* | « Ticket A03 · 1× Koki » + alarm, Cuisine view |
| Accepter | DB `accepted` 19:12:31 + `order_accepted` row + push « Commande acceptée » |
| Commencer | DB `preparing` 19:12:43 (silent by design) |
| Prêt | DB `ready` 19:12:49 + `order_ready` + push « Commande prête » |
| App tracking | Order ticket: Placed → Accepted → Preparing → Ready ticked |
Order left at `ready` (owner can complete it).

### Fixed after the run
- KDS: view switch floated mid-row; « Couper l'alarme » showed in Cuisine for a
  till ticket it never rings for. Both fixed, test fails on either old code.

### Open items (owner to schedule)
1. Borne: no way to replay envelopes quarantined before a server fix.
2. App Menu tab lists dishes that are not on today's menu (borne hides them);
   check whether the app should hide or only refuse at checkout (§24.1).
3. App payment screen keeps the title « Payment pending » after confirmation.
4. App splash still reads « TIMMA Restaurant » under the new mark.
5. TV (S6): behaviour decided; hardware to choose (recommendation: Android TV box).

### Night continuation

Plan: finish and install the customer Menu filter first. Then update the borne
heading, weekly photos and cart, with FR/EN coverage and emulator screenshots.
Use the manager screen to confirm and requeue quarantined envelopes for normal
ordered delivery. Match the app cart, label its filtered Menu tab, and fix the
confirmed-payment heading and splash. Owner confirmed « TIMMA eats » for the
splash and asked to keep S6 on hold.

The borne shows the dated « Menu du jour » heading for a restricted day,
« Boissons dispo » for the drinks category, and « Notre carte » for the
unrestricted catalog. The weekly dialog uses the same disk-first thumbnail
and brand fallback as the dish cards. `kiosk_cart.dart` combines matching
configurations and retains ingredient removals from the composer. The full
suite passed (201 tests). The 1.0.1+2012 emulator build showed today's four
dishes, weekly photos and a single Koki row at quantity four.
