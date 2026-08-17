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
