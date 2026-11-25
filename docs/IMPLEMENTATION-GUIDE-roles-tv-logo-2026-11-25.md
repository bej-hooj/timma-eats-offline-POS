# Implementation guide — remaining stages (S5, S7, S8, S9, S6-after-discussion)

**Audience: any coding agent, including one less capable than the one that
wrote this.** Follow the steps in order. Every decision is already taken; do
not redesign. When a step says "mirror X", open X and copy its structure.

Companion docs (read first, in this order):
1. `docs/roles-tv-logo-sync-2026-11-25.md` — plan, decisions, results log,
   stage table (the only status source).
2. `timmaeat-webapp/ECOSYSTEM.md` §25 — the cross-repo contract.
3. `CLAUDE.md` of the repo you are in — §0 prime directives, §11.11 security.
4. `~/Downloads/vibecoding coding code Prompt instructions rules Suffix (1).md`
   — owner's global rules. **Never deploy, never apply a migration, never
   upload a build without the owner's explicit "yes" in the chat.**

---

## 0 · Where everything is (state at the end of 2026-11-25)

| Repo | Branch | Head | What is in it |
|---|---|---|---|
| `timmaeat-app-flutter` | `feat/roles-tv-logo-2026-11-25` | `974001c` (pushed) | 3 migrations (not applied) + pos_core/pos_cloud/pos_link changes |
| `timma-eats-offline-POS` (borne) | `feat/roles-tv-logo-2026-11-25` | `6561dfb` (not pushed) | S4 done |
| `timma-eats-offline-KDS` (the "cuisine" app — **name it KDS**) | `feat/roles-tv-logo-2026-11-25` | `e219ff5` (not pushed) + pubspec pin bumped to `974001c…` uncommitted | S1 done; S5 to do |
| `timmaeat-webapp` | `main` | ECOSYSTEM §25 appended, uncommitted | S8 to do |

Full pin SHA for both tablets: `974001cae4996a37a846d767ff294b8f7ced7049`.
If you change anything under `timmaeat-app-flutter/packages/`, commit + push
it, then bump **both** tablet pubspecs to the new **full 40-char** SHA.

Test commands (all must be green before any commit):
- packages: `cd packages/<pkg> && dart test && dart analyze`
  (`pos_link_flutter` and `pos_cloud` use `flutter test`)
- tablets: `flutter analyze && flutter test`
- web: `php artisan test && ./vendor/bin/pint --test`

---

## S5 · KDS access roles (repo `timma-eats-offline-KDS`)

> ⚠⚠ **SUPERSEDED (owner, 2026-11-25): NO login/password.** The KDS opens on a
> role picker — « Cuisine » or « Caisse paiement » — remembered on the device,
> with a « Changer de vue » button. Keep only steps 3 (`kds_access_roles.dart`),
> 5–7 (gate/restrict/l10n, with the picker instead of the login screen) and the
> lane tests. Skip bcrypt, roster store, verifier, lockout. Then remove the dead
> roster code — see the decision note at the end of the plan doc. S8a is cancelled.

### What the owner asked
"The KDS should have access id+pass that opens different views. Kitchen
access = pipeline from *Nouvelles* to *Prêt*. Encaisser access = only the
*À encaisser* column. All KDS on the same wifi show the same information; the
only difference is the access."

### What already exists (do not rebuild)
- The hub (borne) already sends the roster: `LanHubServer(rosterSource:)` +
  `publishRoster()`; frame type `roster`, sealed per board.
- `LanSocketTransport(onRoster: (KitchenRoster r) {...})` delivers it
  **already decrypted**. `KitchenRoster`, `KitchenAccount`, `KitchenRole` are
  in `package:pos_core/pos_core.dart`.
- Lanes: `lib/kds/domain/kds_lanes.dart` (`KdsLane.all`, `KdsLane.visible`).

### Steps
1. `flutter pub get` (pin already bumped). Run `flutter test` — must be green.
2. **Dependency:** add `bcrypt: ^1.1.3` to `pubspec.yaml` dependencies with a
   comment: "Verifies the dashboard's bcrypt hashes offline (CLAUDE.md
   §11.11 — bcrypt or Argon2id only)". Check pub.dev for the latest 1.x first.
   ⚠ Laravel writes `$2y$`; if the package rejects `$2y$`, replace the prefix
   with `$2b$` before verifying (they are the same algorithm).
3. **Create folder `lib/kds/access/`** with these files:
   - `kds_access_roles.dart` — pure mapping, no Flutter:
     ```dart
     abstract final class KdsAccess {
       /// Lanes each role may see. manager/null(=no roster) → all.
       static List<String> lanesFor(String? role) => switch (role) {
         KitchenRole.kitchen => <String>[KdsLane.scheduled, KdsLane.newTickets,
             KdsLane.preparing, KdsLane.ready, KdsLane.outForDelivery],
         KitchenRole.cashier => <String>[KdsLane.counter],
         _ => KdsLane.all,
       };
     }
     ```
     `display` is NOT handled here (S6, on hold) — until S6 exists, a
     `display` login must be **refused** with the message
     *"Cet accès est réservé à l'écran salle (bientôt disponible)."*
   - `kds_roster_store.dart` — keeps the last roster in the KDS's own
     `PosStore` meta under key `KitchenRosterKeys`-style constant
     `'kds_roster'` (JSON via `roster.toJson()`), so login works offline after
     a restart. API: `KitchenRoster read()`, `void write(KitchenRoster)`.
   - `kds_password_verifier.dart` — `abstract interface class
     KdsPasswordVerifier { Future<bool> verify(String password, String hash); }`
     + `BcryptPasswordVerifier` (runs `BCrypt.checkpw` inside `Isolate.run`
     so the UI never freezes) + nothing else.
   - `kds_session_controller.dart` — Riverpod `Notifier<KdsSession>`:
     - `KdsSession { String? login; String? role; int failures; DateTime? lockedUntil; }`
     - `Future<KdsLoginResult> login(String login, String password)`:
       1. if `lockedUntil` in the future → `locked`;
       2. `account = roster.find(login)`; if null → count failure, `wrong`;
       3. if `account.role == display` → `displayNotAvailable` (see above);
       4. `await verifier.verify(password, account.passwordHash)`; false →
          failure; after **5** failures set `lockedUntil = now + 30 s` and
          reset the counter;
       5. success → store `login` + `role` in meta key `'kds_session'` and
          state.
     - `void logout()` clears both.
     - `void onRoster(KitchenRoster r)`: write it to the store; if the
       logged-in login is no longer in `r`, or its role changed → `logout()`.
     - Constants (`maxFailures = 5`, `lockout = Duration(seconds: 30)`) live
       in this file as `static const`, not in widgets.
   - `kds_login_screen.dart` — two `TextField`s (login, password with
     `obscureText: true`, `autocorrect: false`, `enableSuggestions: false`),
     one `FilledButton` *Ouvrir*, error line, lockout countdown. 48 dp+
     targets, works at 868×411 dp (the Samsung) — test it at that size.
     **Never log the password or the hash.**
4. **Wire it** in `lib/kds/link/kds_link.dart`: where `LanSocketTransport(` is
   constructed, add `onRoster: (KitchenRoster r) => ref.read(kdsSessionProvider.notifier).onRoster(r)`.
5. **Gate the board** in `lib/kds/kds_root.dart` (after pairing, before the
   board):
   - roster `isConfigured == false` → show the board exactly as today plus a
     thin banner *"Aucun accès configuré — tableau complet"* (key
     `kds-no-roster-banner`). ⚠ Never lock a working kitchen out.
   - configured and not logged in → `KdsLoginScreen`.
   - logged in → the board, restricted.
6. **Restrict the board** in `lib/kds/presentation/board_screen.dart`: where it
   calls `KdsLane.visible(lanes)`, intersect with
   `KdsAccess.lanesFor(session.role)` (keep the order of `KdsLane.all`).
   Add a header chip with the login and a *Changer d'accès* button →
   `logout()`.
   ⚠ The alarm must follow the role too: in `kds_board.dart`, the cashier
   must not hear the *Nouvelles* register and the kitchen must not hear the
   *counter* register. Filter the `lanes` map passed to `_alarm.evaluate`
   with the same `lanesFor`.
7. **l10n**: add every new string to `lib/l10n/app_fr.arb` (template) and
   `app_en.arb`, then `flutter gen-l10n`. No literal UI text in Dart.
8. **Tests** (new file `test/kds_access_test.dart`), each must fail if you
   remove the code it protects:
   - `lanesFor(kitchen)` has no `counter`; `lanesFor(cashier) == [counter]`.
   - Fake verifier: wrong password ×5 → locked; correct password while locked
     → still locked; after 30 s (inject a clock) → works.
   - `onRoster` without the current login → logged out.
   - Widget: roster empty → banner + all lanes; cashier logged in → only
     *À encaisser* heading visible (scope finders to the lane heading widget,
     not `find.text` globally — memory: a global finder matched the header).
   - A real bcrypt hash made with PHP: run
     `php -r 'echo password_hash("test-1234", PASSWORD_BCRYPT, ["cost"=>10]);'`
     and assert `BcryptPasswordVerifier` accepts it (and rejects
     `test-12345`). This proves PHP ↔ Dart compatibility.
9. `flutter analyze && flutter test`, commit
   `feat(kds): access roles — kitchen, cashier, manager (ECOSYSTEM §25.2)`.
10. Update the stage table + results log in the plan doc.

---

## S7 · New logo everywhere

### Sources (owner)
- `~/Downloads/maat/1.png` — **gold** horizontal wordmark (1772×592, alpha)
- `~/Downloads/maat/2.png` — **green** horizontal wordmark
- `~/Downloads/tamm/1.png` — **green** arch mark (416×602, alpha)
- `~/Downloads/tamm/2.png` — **gold** arch mark
Rule: replace each old asset by the new one of the **same colour role and
shape** (owner: "just replace with correspondence in color and shape").
Brand colours: green `#205A39`, gold `#EFCF9D` (`AppColors.brandGreen/Gold`).

### Mapping (exact files)
| Old file | Old look | New source | How |
|---|---|---|---|
| `timmaeat-app-flutter/assets/branding/logo_inline.png` (848×199) | gold wordmark | `maat/1.png` | scale to height 199 keeping ratio (≈596×199) — or keep full res; check every `Image.asset` caller's `height:` so it still fits |
| same in `timma-eats-offline-POS/assets/branding/` and `timma-eats-offline-KDS/assets/branding/` | gold wordmark | `maat/1.png` | same |
| `*/assets/branding/app_icon.png` (1024×1024, **no alpha**) — app, POS, KDS | gold mark centred on green `#205A39` | `tamm/2.png` | composite gold mark, height ≈ 44 % of 1024, centred, on opaque `#205A39`; **output must have no alpha** (App Store rejects alpha icons) |
| `timmaeat-app-flutter/store-assets/google-play/timma-app-icon-512x512.png` | same | same composite at 512 | |
| `timmaeat-webapp/public/images/timma-logo-inline.png/.webp` | check by opening it | maat 1 or 2 matching its colour | |
| `timmaeat-webapp/public/images/timma-logo.png`, `timma-logo-strip.webp` | open and match | maat/tamm matching | |
| `timmaeat-webapp/public/icons/*.png`, `public/favicon.ico` | icon | tamm composite (gold on green) at 16/32/180/192/512 | `favicon.ico`: 32×32 |

No ImageMagick/PIL on this Mac. Use the Swift script below (CoreGraphics is
built in). Save it in the **scratchpad**, never inside a repo.

```swift
// usage: swift compose.swift <mark.png> <out.png> <size> <hexBg> <markHeightFraction>
import AppKit
let a = CommandLine.arguments
let mark = NSImage(contentsOfFile: a[1])!
let size = CGFloat(Double(a[3])!)
let hex = Int(a[4], radix: 16)!
let frac = CGFloat(Double(a[5])!)
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
  bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false, isPlanar: false,
  colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSColor(red: CGFloat((hex>>16)&255)/255, green: CGFloat((hex>>8)&255)/255,
        blue: CGFloat(hex&255)/255, alpha: 1).setFill()
NSRect(x: 0, y: 0, width: size, height: size).fill()
let h = size * frac, w = h * mark.size.width / mark.size.height
mark.draw(in: NSRect(x: (size-w)/2, y: (size-h)/2, width: w, height: h))
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: a[2]))
```
Wordmarks need no compositing: `sips --resampleHeight 199 maat/1.png --out …`.

Then in **each Flutter repo**: `dart run flutter_launcher_icons` (config is
already in `pubspec.yaml`: `image_path` + `adaptive_icon_background: "#205A39"`).
⚠ Android adaptive icons crop to the centre 66 %: the adaptive *foreground*
should be the mark on a **transparent** 1024 canvas at ≈ 40 % height — make a
separate `assets/branding/app_icon_foreground.png` with the Swift script
modified to `hasAlpha: true` and no fill, and point
`adaptive_icon_foreground` at it.
Check: `sips -g hasAlpha ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png` → `no`.

Verify visually: open every generated PNG with the Read tool; build each app
and screenshot the header (app home, borne attract + menu, KDS header, web
header at 375 px and 1440 px). Memory warns: Cloudflare caches images 7 days —
**rename** web files (e.g. `timma-logo-inline-2026.webp`) and update the
Blade references, instead of overwriting the same URL. Deploying the web is an
owner-approval step.

Commit per repo: `feat(brand): the new TIMMA eats logo (ECOSYSTEM §25.7)`.

---

## S8 · Dashboard (repo `timmaeat-webapp`, Laravel 13)

Two small CRUD screens. **Mirror the Tables module exactly**:
`app/Http/Controllers/Admin/TablesController.php`,
`app/Services/Tables/Admin/{TableRepository.php,SupabaseTables.php}`,
`resources/views/admin/tables/index.blade.php`,
routes in `routes/web.php` (~line 467, `staff.can:` group),
`app/Support/RouteNames/RouteNames.php`, test `tests/Feature/TablesAndPromosTest.php`.

### S8a · *Accès KDS* (table `kitchen_accounts`)
- Route group permission: the same one Staff management uses (open
  `StaffController` routes and reuse its permission constant).
- Screen: list (login, role, active), create form (login, role select,
  password + confirmation), toggle active, reset password, delete.
- Validation in a `FormRequest`: login `regex:/^[a-z0-9._-]{3,32}$/`
  (lower-case it first), role `in:kitchen,cashier,display,manager`,
  password `min:8|confirmed`.
- Hash with `Hash::make($password)` (bcrypt, cost ≥ 10 — check
  `config/hashing.php`). **Never** store, log, flash or re-display the
  plaintext. The list never shows the hash.
- Writes with the service-role Supabase client (the table has RLS and no
  policies). `$fillable` allow-list if you add a model.
- After a change the borne picks it up within 60 s and sends it to every KDS.
- Tests: create → row has a `$2y$` hash; plaintext absent from the response
  body and the logs; bad login rejected; non-permitted staff gets 403.

### S8b · *Codes marchands Mobile Money* (table `branch_payment_codes`)
- Put it on the existing Settings page (`SettingsController`) as a section,
  or a small page next to Tables — choose Settings.
- Fields: provider select (`mtn_momo` → "MTN Mobile Money", `orange_money` →
  "Orange Money"), code `regex:/^[A-Za-z0-9]{3,32}$/`, holder name ≤ 80,
  active, sort. One row per provider per branch (unique constraint).
- Help text: "Affiché sur la borne sous le numéro de ticket, et seulement si
  actif."
- Tests: save, toggle off, the regex refuses `12 34` and `<b>1</b>`.

All UI strings through `__()` in `lang/fr` + `lang/en`. Update
`storage/Project_Documentation/<Module>/` and `PROJECT.md` access matrix.

---

## S9 · Release checklist (needs the owner at several steps)

1. **Owner approval** → apply the 3 migrations in this order:
   `20261125120000_kitchen_accounts_roster.sql`,
   `20261125120100_branch_payment_codes_kiosk_settings.sql`,
   `20261125120200_kiosk_day_menu.sql`. Then verify from a fresh read:
   `select public.rpc_kiosk_day_menu('<device key>')` etc. — the device key is
   in `timma-eats-offline-POS/docs/setup-config.md` (gitignored, never print
   it in chat or commit it). ⚠ `psql --single-transaction` COMMITS.
2. Push the POS and KDS branches; build APKs with the commands in
   `docs/CONTINUE-2026-11-24.md` §3 (borne needs its dart-defines); version
   must stay **> 2011**, bump to `1.0.1+2012` on both.
3. Install on the Samsung (borne) and GM92 (KDS); check: menu re-pins after a
   dashboard price edit **without a restart** (≤ 60 s); a CamPay order still
   waiting for payment does NOT show in *À encaisser*; after payment it shows
   in *Nouvelles*; merchant code appears on the ticket; a dish removed from
   today's menu disappears; the week view lists it; KDS logins.
4. Owner uploads release artefacts (`gh release upload … --clobber`, never a
   new tag — see `CONTINUE-2026-11-24.md` §2) and deploys the web.

---

## S6 · The dining-room TV — ON HOLD until the owner discusses it

Proposal to discuss (do **not** build before the owner agrees):
- Software: role `display` of the KDS app (same pairing, works offline).
  Shows only `source = kiosk` orders: *En préparation* (`accepted`,
  `preparing`) and *Prêt* (`ready`) by ticket code; a *Prêt* code leaves when
  the order is `completed` or after 15 min. French voice via `flutter_tts`:
  « Commande A-D-4-5, en préparation » / « … est prête ».
- Hardware options: (1) any HDMI TV + Android TV box (Android 9+); (2) a
  Windows mini-PC with the existing Windows KDS installer; (3) an Android
  tablet with HDMI out. Ethernet preferred over wifi.
- Open questions for the owner: which hardware; voice for *en préparation*
  too or only *prête*; how long a *Prêt* code stays; does the TV also need a
  "Commande prête" chime only (no voice) mode.
