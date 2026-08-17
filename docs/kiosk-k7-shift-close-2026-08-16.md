# K7 — sync, replay and reconciliation

Plan of record: `docs/pos-kiosk-kds-offline-2026-08-15.md` §K7. Started 2026-08-16, after K6.

## The two numbers this stage exists to produce

**Cash and mobile-money-at-till, reported apart and never summed.** The cash figure is the one a
manager counts against the drawer; a combined "till total" is a number nobody can check. Neither was
computable before K1 made the tender a **column** instead of a sentence — a free-text note cannot be
summed, which is why the till has never been reportable.

A **third** line names money that was paid with **no tender recorded**. `tender is null` never means
cash (§7.4): those are rows from before the column existed, or a settlement that landed without one.
Folding them into the cash figure would hand a manager a drawer total that does not match what is in
the drawer, which is worse than admitting the gap.

## Nameable, not countable

Every owed or stuck ticket is listed **by ticket number and reason**. "3 failed" is not something a
manager can chase. The whole reason an envelope is quarantined rather than retried forever is that a
human now has to do something, and they cannot do it without knowing which order. Quarantined tickets
sort above merely pending ones: a stuck ticket needs a person now, a pending one only needs the
network back.

`acknowledged` counts orders with a `serverOrderId`, not drained envelopes — a drained envelope says
*we sent it*, not *they have it*.

## The whole screen reads from the local store

No network. A shift is closed at the end of a day that may have been entirely offline, and a
reconciliation screen that needs the WAN to say what was taken is a screen that fails on the day it
matters most.

> **RESULT — K7 DONE 2026-08-16.** `lib/kiosk/shift/{shift_close,shift_close_screen}.dart` +
> `test/kiosk_shift_close_test.dart`, **10 tests**, app suite **416/416**, analyze clean.
>
> **The stage's own proof runs as a test:** 20 orders rung over an hour with the sink offline, spread
> across settled/unsettled and accepted/placed; the shift close reports 20 local, 0 acknowledged, 20
> unsent and a **countable cash total while still offline**; the WAN returns, a forced drain runs to
> completion, and cloud state matches local exactly (20 acknowledged, 0 unsent, outbox settled,
> nothing stranded). Then the deliberate duplicate — a manager taps *force sync* again — and
> **nothing changes**: no envelope is re-sent, no total moves.
>
> Two things the test caught about its own fidelity, both worth keeping:
> the fake sink originally returned `server_order_id`, but `PosEngine.acknowledge` reads **`order_id`**
> — the same key the real `PosCloudSink` returns, so a fake with its own vocabulary would have proved
> the drain works against a contract nothing speaks. And derived server ids **collided**: client ids
> are UUIDv7, so orders rung in the same window share a long prefix, and `server_order_id` is uniquely
> indexed in the store. The store was right to refuse.
>
> **Not done:** wiring the screen behind a manager gesture on the kiosk, the sync badge on the kiosk
> surface itself, and the physical offline drill — hardware-blocked.
