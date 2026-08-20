# Pairing proven on hardware, and the stale address behind it — 2026-08-20

Session goal, from the continuation prompt: item 0 (prove `adopt()`), item 1
(pair the two real devices), item 2 (the real catalogue), item 3 (the offline
drill on shop wifi).

## The headline

**The borne and the cuisine pair, and an order crosses.** Confirmed on the
hardware at 17:51: `/health` → `"peer_count":1,"link":"lan"`, two orders rung on
the borne arrived on the board, and the alarm rang. The cuisine found the borne
**in the discovery list** — no address typed — so pairing is one tap plus six
digits, which was the owner's requirement.

Bocav was carrying the **old** branch secret from the failed attempts, and the
pairing still completed. That is `adopt()` doing the job it was written for, on
real devices. `dc0a257` is the pinned commit that was proven; nothing in this
session moves it.

## Why it had been failing — the part nobody had measured

The borne's manager screen said:

> Borne visible sur le wifi
> **192.168.1.132:8801**
> 0 cuisine(s) connectée(s)

The tablet's only IPv4 address was **192.168.1.245** (`ip -4 addr` → one
`wlan0`, one address). The hub was listening (`0.0.0.0:8801 LISTEN`), healthy
over curl from the Mac, and had **zero inbound connections** — no pairing
attempt in the log at all. The cuisine was dialling an address that had been
dead for hours, because the borne itself was still printing and advertising it.

`HubController.start()` resolved the LAN address **once** and never again. A
DHCP lease change therefore made the borne unreachable to any new board until
somebody restarted the app by hand. Restarting it, on camera, changed the screen
to `192.168.1.245:8801` — and the very next code paired first time.

This is very likely the original *"something wrong with the key"* report as
well: two failure modes stacked, and only one of them had been found.

### Fixed

`timma-eats-offline-POS` `7943a19`. The address is re-resolved every 15 s for as
long as the hub runs; a change updates the screen **and** re-raises the mDNS
registration, because the address lives inside the record. Three seams added so
the path is testable at all — the address list, the credential store, the watch
interval — and the test waits on the controller's own timer rather than calling
the resolver, since the resolver was never the bug: nothing asking it again was.

`test/kiosk_hub_address_test.dart`, POS **115/115**.

## Item 0 — `adopt()` is now proven end to end

`timma-eats-offline-KDS` `08914a1`, `test/kds_kiosk_reinstall_test.dart`.
Pair against a kiosk with secret A, uninstall it, install a kiosk with secret B,
pair again: the board adopts B, a slip signed by B verifies on it, and a slip
signed by A no longer does. A **wrong** code still cannot rotate the secret —
that is the half that keeps `adopt()` from being a hole where `writeOnce` was.

The previous attempt failed and was deleted. The cause: `pos_link` leaks a
failed connect to the zone as an unobserved async error, which fails a Dart test
outright. It was reported as *"the first pairing failed"* when the pairing had
succeeded and the test had died on a socket retrying a kiosk the test itself had
removed. Guarded here, and the guard asserts that nothing but socket noise was
swallowed. The leak remains a `pos_link` defect; fixing it means moving the pin.

### Two more defects those tests found

* **Re-pairing left the board on the old socket.** `KdsLinkController.start()`
  returns early while a transport exists, so pairing on top of a live link
  paired perfectly, wrote the new address, reported no error — and went on
  talking to the kiosk that had gone. `join()` now stops the link first.
* **A refused pairing still reported `paired: true`**, carried over from an
  earlier session. Nothing reads it today; the next thing that did would have
  inherited it silently.

KDS **55/55**.

## Item 2 — the real catalogue, instrumented

Still `snapshot_checksum_mismatch`; the borne still sells the seeded menu behind
the red *PRIX NON RÉELS* ribbon. Written this session, built, **not yet run on
the device**: `lib/kiosk/catalog/snapshot_checksum_diagnostic.dart`, a subclass
of `SupabaseMenuSnapshotSource` that on a mismatch — once per launch — re-fetches
and reports:

* which shape the server's checksum actually describes (as parsed · without
  categories · with an empty `categories` key);
* the **key names** the server sent that the client's model does not carry, and
  the reverse, at top level and inside `products` and `categories`. A field the
  server hashes and the client drops is exactly how this fails, and it has
  happened before — the first categories migration hashed `photo_url` into every
  category against a Dart model with four fields and no `photo_url`.

Names and sizes only, never values. It extends rather than wraps because
`CatalogSync` takes the concrete source type, and widening that parameter would
mean moving the pin for a diagnostic.

**Next run of the borne prints the answer.** One log line names the field.

## Item 3 — the offline drill

Not run. It needs the router's WAN unplugged (never the wifi), and the Samsung
kept awake.

## Traps hit again today

* **adb drops constantly**, and the phone falls off the wifi entirely when the
  screen sleeps — `svc power stayon true` after every reconnect, and the app has
  to be in the foreground or the hub stops answering.
* `monkey` **resumes** an existing process rather than restarting it, so a hub
  started under an old lease keeps its old address and the manager screen keeps
  showing a stale pairing code. Use `am force-stop` first when the point is a
  fresh start.
* The phone is the owner's personal handset. It had a private conversation open
  mid-session; screenshotting stopped until the borne was back in front.
