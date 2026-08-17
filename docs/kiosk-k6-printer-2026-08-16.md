# K6 — the receipt printer

Plan of record: `docs/pos-kiosk-kds-offline-2026-08-15.md` §K6. Started 2026-08-16, after K5.2–K5.5.

## The constraint that decides the design

> *"The QR must encode a code the KDS can verify **from its local store**, with no lookup —
> otherwise collection breaks in exactly the outage the slip exists to survive."*

That single sentence rules out every simpler option. A server-issued code needs a network. A code the
hub mints needs a hub round trip at collection. A sequence number needs a shared counter. So the
payload is **self-describing and self-authenticating**: ticket identifiers plus an HMAC over them,
keyed by a per-shift secret both devices already hold from pairing. The KDS recomputes and compares —
no lookup, no clock dependency, no shared state.

It is deliberately **not** just the ticket number. A kitchen that accepts "42" scanned off any slip
accepts yesterday's 42, the 42 from the branch across town, and a 42 written on a napkin — and this
code is used at the one moment food is handed over.

The branch id is inside the MAC because two TIMMA branches share a menu **and** a ticket-number
sequence; without it a slip from one collects food at the other.

## Why ESC/POS is written out rather than imported

The slip needs about a dozen commands. A thermal printer's failure mode is a customer standing at a
counter with no proof of an order, and a dependency that quietly changes its idea of "cut" between
versions is not worth the saved afternoon. Every constant is from the Epson reference that generic
58/80 mm network printers implement.

Paper is 58 mm / 32 columns: it is what the local supplier stocks, and a layout assuming 48 silently
wraps every line on the printer that actually arrives.

> **RESULT — K6 core DONE 2026-08-16.** `lib/kiosk/printing/{escpos,collection_code,slip,print_queue}
> .dart` + `test/kiosk_slip_test.dart`, **18 tests**, app suite **406/406**, analyze clean.
>
> **Two defects the tests caught, both of which only show on paper:**
>
> - **Uppercase accents fell off the code page.** The slip's own take-away line starts with `À`,
>   which was not in the CP858 map and printed as `?`. Only the lowercase set had been mapped.
> - **`MoneyFormatter` joins its groups with a NON-BREAKING space** so `12 500 FCFA` cannot wrap on
>   screen. Unmapped, that printed as `3?500?FCFA` — every price on every slip. A thermal slip is
>   fixed-width and never wraps, so it now maps to a plain space.
>
> Neither would have been visible in any on-screen test, and both would have reached a customer's
> hand. This is the third stage running in which the *French* string was the one that broke.
>
> The print queue proves its retry rules against an injected `PrinterTransport` (the same seam shape
> as `pos_link`'s `CloudRelayBackend`): transient failure retries, an exhausted job stays **visible**
> as failed rather than being silently dropped, paper-out is caught **before** a job rather than
> halfway through one, and reprint-last does not drift one job backwards on repeated use.
>
> **Socket transport DONE** (`socket_printer.dart`): port 9100, a **fresh connection per job**
> because a long-lived socket to a thermal printer reads healthy long after the printer is switched
> off — TCP reports a vanished peer as connected until a write fills the window, the same lie about
> liveness the link badge already refuses to tell (§1.7). `flush()` is awaited because it is the only
> part that reports a write failure: without it the job sits in the OS buffer and `close` returns
> happily on a printer that is off, so **every slip would "succeed"**.
>
> **Not done:** the physical proofs the plan names (a real print, paper pulled mid-job then
> reinserted, printer powered off and back on) — hardware-blocked. And the decision below.

## ⚠ OPEN DECISION — where the collection secret comes from

`CollectionCode` is keyed by "a per-shift secret both devices already hold from pairing". **That
secret does not exist yet**, and the gap is deliberate rather than hidden: choosing it wrong is
worse than choosing it late.

The problem is that one printed QR must be verifiable by **every** paired KDS, while pairing gives
each device its **own** `DeviceCredential`. So the code cannot be signed with a per-device key. The
options, with what each costs:

1. **A branch collection secret handed out at pairing.** The hub mints one per shift (or per branch)
   and includes it in the `pair_accepted` frame. Clean, but it **changes the pairing protocol**,
   which is K3-SEC territory — the last two defects in that handshake were a cleartext secret and a
   code on the wire, and it is not a place to make a casual addition.
2. **Derive it from something both sides already have.** No protocol change, but there is currently
   no shared secret to derive from — the whole point of §23.9 is that each pairing produces a
   *different* key.
3. **Drop the MAC and verify against the local store instead.** The KDS already holds the ticket:
   `clientId` + `ticketNumber` + status could be checked directly with no key at all. Simpler, and
   still needs no lookup beyond the store — but it means anyone who learns a `clientId` can collect,
   and `clientId` travels on the LAN and the relay.

**Recommendation: option 1**, taken deliberately as part of K5.6 when the relay work reopens the
pairing/credential surface anyway, so the protocol is changed once rather than twice. Until it is
decided, `CollectionCode` takes its secret as a parameter and nothing constructs one in production —
the kiosk's confirm step is therefore **not yet wired to the printer**, which is the honest state
rather than a slip signed with a placeholder.
