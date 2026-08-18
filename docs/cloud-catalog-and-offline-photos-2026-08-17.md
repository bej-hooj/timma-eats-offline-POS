# Kiosk cloud catalog + offline dish photos — 2026-08-17 (session 3)

Written before the first source edit (`CLAUDE.md` §0.6). Owner report, 2026-08-17:

> *"i saw the images from the dashboard are not displayed on the kiosk menu. i told you when online
> the kiosk should load content catalog from the dashboard then works offline."*

## The two root causes, named before any fix

The data path already exists end to end and is NOT the problem:

- `rpc_menu_snapshot` (migration `20260815170000_kiosk_cloud_feed.sql`) already returns
  `photo_url` from `p.images[1]`;
- `SnapshotProduct.photoUrl` already parses it;
- `SupabaseMenuSnapshotSource` + `PosCloudSync.start()` already pin a validated bundle.

What is missing is at both ends of that path:

1. **Nothing composes the cloud sync.** The kiosk's `main.dart` builds an engine over the local
   store and stops. `PosCloudSync` is never constructed, so `rpc_menu_snapshot` is never called and
   the only menu on the device is whatever the debug seed wrote — and that seed has no photos. This
   is why the dashboard's images are absent: the dashboard's catalogue never arrived.
2. **Photos are `Image.network` with no disk cache.** Even once the URLs arrive, a kiosk that has
   lost internet renders nothing, because every image would be a fresh HTTP GET. A menu whose
   pictures vanish with the internet is not an offline kiosk.

## Plan

### C1 — compose the cloud catalog (online), keep selling (offline)

- Build `SupabasePosCloudGateway` + `SupabaseMenuSnapshotSource` + `PosCloudSync` in the kiosk's
  composition root when Supabase URL/anon key and a device key are configured.
- **Offline-first, always.** The pinned snapshot on disk is the source of truth for selling. A
  failed pin is a logged, visible-in-diagnostics event, never a blocked screen and never an empty
  menu. The kiosk boots from disk and refreshes behind the customer.
- Never block `runApp` on the network: the first pin runs after the UI is up, bounded by a timeout.

### C2 — dish photos that survive the outage

- A content-addressed disk cache in app-private storage. When a snapshot is pinned, every
  `photoUrl` is fetched once and written atomically (temp file + rename), then read from disk
  forever after.
- The dish card reads **disk first, network second, brand panel third** — the existing photoless
  fallback stays as the last step.
- Bounded: a maximum byte budget and a maximum per-file size, oldest-evicted-first, so a large
  catalogue cannot fill a tablet.

### C3 — security rules this cache obeys

1. **https only.** A `photo_url` that is not `https` is refused outright — no `http`, no `file`,
   no `data`. The kiosk stands in a public room on a shop wifi; a plaintext image URL is a
   tamperable one.
2. **The URL's host must be the configured Supabase host.** The snapshot is authenticated data, but
   defence in depth: a compromised row must not be able to point a kiosk at an arbitrary host.
3. **Bounded downloads.** Per-file cap and a total budget, enforced while streaming, so a hostile or
   broken response cannot exhaust storage.
4. **Content-addressed filenames** (SHA-256 of the URL, hex). No path element ever comes from the
   remote string, so a crafted URL cannot traverse out of the cache directory.
5. **It is a cache, never truth.** Prices, availability and names come from the pinned snapshot the
   engine validated. An image is decoration; a missing or corrupt one degrades to the brand panel.
6. **No secrets in it.** Device key and anon key never appear in a filename, a log line or an
   exception message.

### C4 — verification

- Host tests: pin-from-cloud path, offline fallback to the pinned snapshot, cache hit/miss, https
  refusal, foreign-host refusal, oversize refusal, traversal-proof naming, eviction.
- Device: Samsung, French. Online run pins the real dashboard catalogue and shows real photos; then
  **internet off, wifi on**, relaunch, and the same menu with the same photos must render from disk.
- Both tablet suites and all four shared suites stay green; pins move together if a shared package
  changes.

## Boundaries

Unchanged and still true: no production mutation without owner approval; the relay migration and
`pos-relay-token` stay committed-and-unapplied; `PosOrder` still has no `fire_at`; physical printer,
two-network and device-owner proofs stay hardware-blocked unless the hardware is present.

---

## RESULT — 2026-08-18

### Built and committed

| Piece | Where |
|---|---|
| Cloud catalogue composed in the kiosk (gateway → snapshot source → `PosCloudSync`), started **after** `runApp` | `lib/main.dart`, `lib/kiosk/catalog/cloud_catalog.dart` |
| Offline dish-photo cache — https-only, host-locked, bounded, content-addressed, atomic | `lib/kiosk/catalog/dish_photo_cache.dart` |
| Card reads disk → network → brand panel | `lib/kiosk/presentation/widgets/kiosk_dish_card.dart` |
| Device key in the keystore, write-once, never in the APK | `lib/kiosk/hub/device_key_vault.dart` |
| Search + category filter, app-style | `lib/kiosk/presentation/menu_screen.dart`, `widgets/kiosk_category_pill.dart` |
| Categories in the snapshot contract + migration | schema owner `d5cf80f`, `20260818100000_kiosk_snapshot_categories.sql` |
| TIMMA logo: launcher icons + attract screen | `assets/branding/`, `pubspec.yaml` |

POS 95/95, KDS 28/28, pos_core 120/120, analyze clean, debug + release APKs build.

### Device proof (Samsung SM-G975F, wireless adb, French)

**Online, fresh install** — logcat:

```
[KioskCatalog] photos DishPhotoCacheResult(fetched: 3, reused: 0, refused: 0, failed: 0, skipped: 0)
```

Three real dashboard photographs (`poulet-dg.webp`, `poisson-braise.webp`,
`ndole-miondo.webp`) downloaded into `app_flutter/dish_photos/` under their
SHA-256 names, and the menu rendered them. Screenshot: `menu-online-photos.png`.

**Offline** — NOT yet taken on the device. `adb shell svc wifi disable` cut the
adb link itself, because this device is connected *over* Wi-Fi; the phone had to
be re-enabled by hand and dropped again during the second attempt. The offline
path is covered by `test/kiosk_offline_catalog_test.dart`, which renders a
cached photo with no HTTP override installed at all (any network access throws)
and asserts the widget is a `MemoryImage` — i.e. bytes off the disk. The device
half of that proof is **owed** and is the first item in the operator guide below.

### What the dashboard's own data says (read-only check, production)

Of nine published products, **four** carry an image:

| Dish | Image |
|---|---|
| Poulet DG, Poisson braisé, Ndolé | `catalog` bucket — fine, cached, offline-safe |
| TIMMA Burger | `img.magnific.com`, a **signed URL with an `exp` parameter** |
| The other five | none at all |

Two consequences the owner needs, neither of them a code fix:

1. The kiosk **refuses the burger's image by design** — foreign host, and the
   URL expires on its own anyway. Re-upload that photo to the `catalog` bucket
   through the dashboard and it appears.
2. Five dishes will show the brand panel until somebody gives them a picture.

### Owed before the kiosk can pin the LIVE catalogue

1. **A device key.** `pos_devices` already holds an active kiosk row for branch
   `10000000-…0001` ("Borne entrée (prod live proof)"), but only its hash — the
   plaintext was never recorded, which is correct hygiene and means a key must
   be issued to provision a tablet. Owner action.
2. **Deploy `20260818100000_kiosk_snapshot_categories.sql`** for the category
   pills to have anything to show. Until then the strip is simply absent.
   Owner approval required; nothing is deployed.
