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
