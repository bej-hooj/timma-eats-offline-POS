# POS stabilization plan — 2026-08-17

Written before any source edit. The schema-owner plan of record is
`timmaeat-app-flutter/docs/kiosk-stabilization-2026-08-17.md`; this local copy is sufficient to
resume the kiosk portion if the other checkout is unavailable.

## Scope

- Persist one 32-byte branch collection secret in a secure hub-only vault before pairing starts.
  Ordinary restarts and newly paired KDS devices must reuse it; malformed storage must fail closed,
  never rotate silently. No logs or UI may contain it.
- Wire `KioskSessionController.confirm()` in this repository only: durable order first, then
  `CollectionCode.forOrder`, `Slip.build`, and `PrintQueue.enqueue` exactly once.
- Surface queue progress and exhausted failure truthfully, with retry/reprint and double-tap
  protection. A placed order is never rolled back because printing failed, and a failed print is
  never called success.
- Preserve French printer bytes (`À`, NBSP-as-space), integer XAF, server-price authority, distinct
  modifier-option counting, and the existing offline state-machine rules.
- Run format/analyze/all tests/build, then install on the explicitly selected Samsung and inspect
  logcat. Repeat after every fix.
- Replace the fresh-database `readIdentity()!` crash with an explicit unprovisioned/setup state.
  Do not seed a made-up production identity. Add release networking/multicast and iOS local-network
  declarations, then prove both debug and release manifests/builds.
- Compose the hub only from persisted, validated configuration. At plan time no production code
  starts cloud menu sync, pairing, LAN discovery/server, relay, board publication or printer
  transport, so isolated UI/queue tests must not be described as an operational kiosk.

## Coordination and safety

The four `pos_*` packages, migrations and edge functions stay in `timmaeat-app-flutter`; this repo
must not acquire schema files or fork those packages. If a shared package ref changes, POS and KDS
pins move together. Check `git branch --show-current` before every commit, stage explicit paths only,
and never `git add -A`.

Relay migration/function deployment is a separate owner-approved production action. Do not deploy
from this repo. The known `PosOrder.fire_at` omission remains an explicit scheduled-order blocker;
do not claim it fixed as part of printer wiring.

Relay correction before any deploy: hosted custom secret names cannot use the `SUPABASE_` prefix,
the project currently signs Auth sessions with ES256, and this device-key endpoint cannot use the
default user-JWT gateway check. Schema-owner work must use a non-reserved
`POS_RELAY_JWT_SIGNING_SECRET`, confirm the legacy HS256 key remains trusted, set
`verify_jwt = false`, and prove the handler plus Realtime/RLS path. If the legacy key is not trusted,
stop for an owner-approved imported signing-key/rotation design.

## Proof ledger (not yet run this pass)

- [ ] baseline `flutter analyze` and all POS tests
- [ ] collection secret persists across fresh vault/controller instances
- [ ] pre-restart collection code verifies after restart
- [ ] confirm queues one authenticated slip; order failure queues none
- [ ] exhausted printer failure is visible and retryable
- [ ] French real-width/byte regressions stay green
- [ ] Android debug build succeeds
- [ ] Samsung install/launch/confirm/relaunch log smoke is clean
- [ ] physical printer and two-tablet proofs recorded honestly as passed or hardware-blocked
- [ ] fresh store renders setup state rather than crashing
- [ ] debug and release merged manifests contain the required network permissions

## RESULT — 2026-08-17, session 2 (device-proven)

Pins bumped to `ea872ac` in lockstep with the KDS (`6c82491` here, `cb10f4d` there).

- [x] baseline `flutter analyze` and all POS tests — clean, 42/42 at the start, **70/70** at the end
- [x] collection secret persists across fresh vault/controller instances — `CollectionSecretOwner`,
      witness in the store, `test/kiosk_collection_secret_test.dart`
- [x] pre-restart collection code verifies after restart
- [x] confirm queues one authenticated slip; order failure queues none
- [x] exhausted printer failure is visible and retryable — and never reported as printed
- [x] French real-width/byte regressions stay green
- [x] Android debug build succeeds; release APK builds and carries the network permissions
      (verified with `aapt2 dump permissions`, not inferred from the source manifest)
- [x] Samsung install/launch/confirm/relaunch log smoke is clean — no FATAL, no E/flutter, no ANR
- [ ] physical printer proofs — **hardware-blocked**, no printer on this network
- [x] fresh store renders the setup state rather than crashing — proven on the device
- [x] debug and release merged manifests contain the required network permissions

Commits here: `a21a703` (confirm → slip → queue, bootstrap, manifests), `933400d` (the app's card
design + four device-found layout defects), `6c82491` (pin).

### What the device found that the host could not

The Samsung is **868 × 411 dp** in landscape — read from `dumpsys display`'s `mOverrideDisplayInfo`
plus `wm density` (420), never from `wm size` alone. At that height:

1. dish cards computed 370 dp tall in a 259 dp viewport and their **price row was clipped off**;
2. dish names truncated after ~7 characters at 28 pt;
3. the counter screen overflowed by **336 px** — total and *Nouvelle commande* off screen;
4. the attract screen overflowed by **91 px**.

All four are now covered at real device sizes in `test/kiosk_menu_layout_test.dart` and
`test/kiosk_confirm_print_test.dart`.

⚠ `flutter_test` substitutes a fixed-width font (every glyph advances a full em), so text widths and
wrapping in a widget test are **not** the device's. Assert geometry in tests; assert legibility on a
device.

### How to reproduce the device smoke

```
flutter build apk --debug \
  --dart-define=KIOSK_DEV_BRANCH_ID=<branch uuid> \
  --dart-define=KIOSK_DEV_DEVICE_ID=<device id> \
  --dart-define=KIOSK_DEV_SEED_MENU=true
~/Library/Android/sdk/platform-tools/adb -s <serial> install -r build/app/outputs/flutter-apk/app-debug.apk
```

`KioskDevProvisioning` is debug-only and seeds nothing without those defines; a seeded build wears a
permanent red ribbon. Add `--dart-define=KIOSK_PRINTER_HOST=<ip>` to exercise a real printer. Keep the
screen awake (`adb shell svc power stayon true`) — Samsung screen-sleep silently eats `input tap`.
