# TIMMA — self-order kiosk

The customer-facing tablet at the door. It is **also the store hub**: it holds the shift's truth in
SQLite, serves the kitchen tablet over the restaurant's own LAN, and is the **only** device that
talks to Supabase. One writer, no split-brain (ECOSYSTEM §23.2).

**Offline is not a fallback mode. It is the normal mode** (§23.1). Nothing a customer does waits on
a network: the menu is a pinned bundle, prices come from that bundle, the ticket number is minted
locally and instantly, and the slip prints without asking anyone's permission.

```bash
flutter run          # the kiosk
flutter test         # 42 tests
```

## Where everything lives — four repos, one database

| Repo | Owns |
|---|---|
| `timmaeat-app-flutter` | The customer phone app. **SCHEMA OWNER**: every migration, every edge function, and the four `pos_*` packages this repo depends on. |
| `timmaeat-webapp` | Dashboard + landing. Home of **`ECOSYSTEM.md`** (canon for anything spanning repos) and **`design-tokens/tokens.json`** (the one colour/spacing source). |
| `timma-eats-offline-POS` | The self-order kiosk — a customer tablet at the door that is **also the store hub**. |
| `timma-eats-offline-KDS` | The kitchen board — a tablet that keeps working with the WAN unplugged. |

### Why the engine is not in here

`pos_core` (money, outbox, status guard), `pos_link` (LAN + relay transport), `pos_link_flutter`
and `pos_cloud` stay in `timmaeat-app-flutter` and are consumed here as **pinned git
dependencies**.

Both tablet apps need the same engine. Two copies of `pos_core` would mean a ticket behaving
differently depending on which tablet touched it — and `pos_cloud` calls the kiosk RPCs directly,
so an engine one git hop from the migrations it is written against is exactly how those two drift.
One engine, two apps, no fork.

**Bumping the pin is a deliberate edit to `pubspec.yaml`, and the POS and KDS repos should be
bumped together** — they speak the same wire, and a version skew between them is a tablet that
cannot pair.

### Why the design layer is copied, and why that is not a fork

`lib/design/` mirrors `timmaeat-webapp/design-tokens/tokens.json`, which is the single source
ECOSYSTEM §15.5 names. The phone app's `AppColors` is *already* a derived mirror of that file — so
this is a third consumer of one source, not a second source. **Sync from `tokens.json`, never
edit a hex here.**

## What this app will not do

- **It never carries a customer session.** No Supabase auth, no Hive, no account. The screen faces a
  public room.
- **It never computes a price.** The cart sends ids and quantities; `PosEngine` prices from the
  pinned snapshot and the database prices it again on replay (§23.3).
- **It takes cash only, and only at the counter.** A tender that appears when the WAN is up makes
  the UI change shape with the network — out of scope by design, not deferred.
- **It collects no PII.** There is no text field anywhere on the path, and a test asserts it.

## Plan and stage results

`docs/pos-kiosk-kds-offline-2026-08-15.md` is the plan of record (K0–K10). Per-stage results are in
the `docs/kiosk-k*.md` files.
