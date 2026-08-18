# Pairing UI — kiosk hub ↔ KDS board — 2026-08-18

Written before the first source edit (§0.6). Owner, 2026-08-18:

> *"on the same phone (samsung) the kds only show not pared device screen"*
> *"so i can test with kioske from samsung and kds on iphone"*

## Why the board can only say "not paired"

This is not a bug in the board — it is the honest end of a road that stops. The
whole transport exists and is tested in `pos_link`:

| Piece | Where | State |
|---|---|---|
| `PairingRegistry` — mints the 6-digit code, derives the credential, wraps the branch secret | `pos_link/src/pairing.dart` | built, tested |
| `LanHubServer` — the hub's websocket, challenge/proof, snapshot push | `pos_link/src/lan_hub_server.dart` | built, tested |
| `LanPairingClient` — the board's side of the handshake | `pos_link/src/lan_socket_transport.dart` | built, tested |
| `NsdHubDiscovery` — mDNS advertise/browse for `_timma-pos._tcp` | `pos_link_flutter` | built, tested |
| `KdsCredentialVault`, `BranchCollectionSecretVault` — keystore persistence | `pos_link_flutter` | built, tested |

**Nothing constructs any of it.** No screen starts the hub, no screen shows a
code, no screen browses for a hub. So the board boots, finds no credential, and
correctly reports that it is not paired. Every green test in those packages is
about the wire, not about a product anyone can use.

## What this pass builds

### P1 — the kiosk becomes a hub a board can find

- A **manager screen** reachable from the kiosk without giving a customer a way
  out of the app: a long-press on the attract screen's mark, then a PIN. The
  kiosk is unattended in a public room; a visible "Manager" button is a door.
- It starts `LanHubServer` on the branch's engine, advertises `_timma-pos._tcp`
  over mDNS, and shows: the hub's LAN address, the running state, and the list
  of paired boards.
- **Pair a kitchen** calls `PairingRegistry.begin()`, shows the six digits and a
  countdown, and waits. On a claim it shows the device's name and asks a human
  to confirm before the credential is issued.

### P2 — the board finds the hub and joins

- The unpaired screen gains **Chercher la borne**: browse mDNS, list what is
  found (label + address), or accept an address typed by hand for a network
  where multicast is blocked.
- Entering the six digits runs `LanPairingClient`, and on success persists the
  credential **and** the branch collection secret atomically, then drops into
  the board.
- Failures are named in French and are recoverable: wrong code, expired code,
  hub on another branch, hub unreachable.

### P3 — the board actually shows the service

Once paired, the board connects with `LanSocketTransport`, applies the hub's
snapshot, and renders the lanes it already has. Reconnect is automatic and the
link badge tells the truth (`§1.7` — a badge that lies is worse than none).

## Security rules this pass keeps

1. **The six-digit code never crosses the wire.** It is the input to the HKDF
   that derives the credential; the hub proves knowledge of it. (This was a real
   hole once — a sniffer minted a credential with a guessed code.)
2. **A human confirms the device** before a credential exists. Anyone on the
   wifi can reach the socket; only someone standing at the kiosk can approve.
3. **The branch is bound** into the challenge, the accept and every reconnect;
   a board refuses a hub that names another branch.
4. **The collection secret is AES-256-GCM wrapped** under a third HKDF label and
   opened only after the hub's proof verifies.
5. **Codes expire and are single-use.** An expired code is a normal event with a
   plain French message, never a retry loop.
6. **Nothing secret is logged** — not the code, not the credential, not the
   secret. Diagnostics carry device labels and error codes only.

## Verification

- Host tests for the two controllers (hub pairing state machine, board join
  state machine) against the real `pos_link` pieces over a loopback socket.
- Device: kiosk on the Samsung, board on the Bocav iPhone, both on one wifi box.
  Pair them, place an order on the kiosk, watch it land on the iPhone, advance
  it there, and see the kiosk follow — with the box's internet unplugged.
