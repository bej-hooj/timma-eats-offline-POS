# Self-order kiosk + offline KDS — build plan, 2026-08-15

Owner ask, verbatim: *"Lets discuss about the creation of the POS to put on the tab in front of the
restaurant. it should work offline · connected to the KDS already done · Being updated when internet
gets back · its data come from the dashboard · so the KDS should also be able to work offline · It
should be very beautifull · i dont know yet on which Tablet/tab it would be put on …so lets do it in
flutter for both apple and Android · It should take care of synchronous when internet is gone it
store data … you just tell me the most Professionnal Mcdonald/burger king does it."*

Plan written **before any code** (`CLAUDE.md` §0.6). Cross-repo canon goes to
`timmaeat-webapp/ECOSYSTEM.md` first (stage K0). This file is the resume point: a fresh session
should be able to continue from it alone.

Owner decisions taken 2026-08-15, before this plan existed:

| Question | Decision |
|---|---|
| Who touches the front tablet | **Customer self-order kiosk** |
| Offline POS→KDS link | **POS is the store hub over LAN** |
| Offline payment | **Cash / pay-at-counter only** |
| Tender on the **tablet** KDS | **Cash only** (owner, 2026-08-15) |
| Tender on the **web** KDS | **Cash or momo-at-till** — unchanged (owner, 2026-08-15) |
| Peripherals | **Screen + receipt printer** (no cash drawer) |
| Kiosk order mode | **Take-away only** — `mode = 'pickup'`, always. No dine-in, no table |
| Branch offline, customer side | **Warn but allow** — app/web say the restaurant is offline, order proceeds |

---

## 0. Baseline, verified at the start of this pass

| Thing | State, checked in the code |
|---|---|
| KDS today | `timmaeat-webapp/app/Http/Controllers/Admin/KdsController.php` — a **Blade page rendered on the VPS**, polled. Nothing of it runs on the tablet |
| KDS counter lane | Already exists: `OrderAdminRepository::awaitingCounterPayment()`, `KdsController::counterPaid()` |
| State machine | Already **in the database**: `rpc_transition_order` owns the legal moves and the row lock |
| Customer order path | `rpc_place_order` (`20260712230000_ordering_rpcs.sql:290`) — requires `auth.uid()` **and** `phone_verified`, and **mints the id + `daily_code` server-side** |
| `orders.user_id` | `not null references public.profiles(id)` — no anonymous order is representable today |
| Money | `subtotal`/`discount`/totals are `integer`. XAF is zero-decimal. **No float ever touches money** |
| Pay-at-counter | ECOSYSTEM §7.4, and it is **dine-in only**; §5 matrix row 5 says pickup is OFF behind "a single setting" |
| Unpaid expiry | 15-minute cron (§6.3) — a **server** cron, unreachable offline |
| Migrations | 41 applied, immutable. New ones are dated `YYYYMMDDHHMMSS_*.sql` |
| Flutter app | Has `cached_catalog_repository` / `cached_order_repository` — read-through caching, **not** an offline write path. Nothing here is an outbox |

### The two facts that set the scope

1. **The existing KDS cannot be given an offline mode.** It is a remote web page; with the WAN down
   the tablet shows a browser error, not a stale board. Offline KDS = **a second Flutter app**. The
   web KDS survives unchanged as the manager's remote view.
2. **The existing order path cannot be reused by the kiosk.** Server-minted identity plus a
   mandatory logged-in, phone-verified customer are each independently fatal offline.

---

## 1. The architecture, and why it is this one

### 1.1 What McDonald's / Burger King actually do

In a real QSR, **offline is not a fallback mode — it is the normal mode.** The store is the unit of
availability, not the cloud. Terminals and kitchen screens talk to the store's own LAN and never
reach across the internet to ring up a sale. The WAN carries exactly two things: menus and prices
*down*, sales *up*. Losing it is a non-event because nothing in the sale path depended on it.

The principles that follow, and how each lands here:

| QSR principle | TIMMA application |
|---|---|
| One local source of truth per store | The **kiosk tablet's SQLite is the shift's truth**. The KDS is a client of it, not a peer |
| Menu is a versioned bundle, pulled and pinned | Dashboard publishes `menu_version` *n*; the kiosk downloads it **whole**, validates, then activates. A bad push cannot break service — the kiosk keeps serving *n−1* |
| The terminal mints identity, never the server | Kiosk mints `order.id` (UUID v7) + `device_seq`. The server dedupes on the id it was handed |
| Sync is a durable outbox | Every state change appends to a local queue with a sequence number; a worker drains with backoff. **No UI action ever awaits the network** |
| Conflicts settled by a rule, not timestamps | The status machine is **monotonic**. A replayed `preparing` arriving after the server holds `ready` is *dropped*, not applied |
| Payment is the hard wall | Cash always works. Mobile money cannot be store-and-forwarded — there is no auth to defer. The kiosk therefore takes **cash at the counter, always** |
| Every shift ends in reconciliation | Shift close shows local ticket count vs cloud-acknowledged count vs unsent. Nobody assumes "it probably synced" |

### 1.2 The hub, concretely

No store-server appliance — one restaurant, nobody to maintain a box. The kiosk tablet **is** the
store hub:

```
   ┌─────────────────────────────────────────── restaurant LAN ────────┐
   │                                                                   │
   │   KIOSK TABLET (hub)                    KDS TABLET (client)       │
   │   ├ Flutter UI (customer-facing)        ├ Flutter UI (staff)      │
   │   ├ SQLite = shift truth                ├ SQLite = local mirror   │
   │   ├ outbox → cloud                      ├ ws client + reconnect   │
   │   ├ shelf HTTP + WebSocket server ◄─────┤                         │
   │   ├ mDNS advertise (+ manual IP)        │                         │
   │   └ ESC/POS printer client ──► thermal printer (network)          │
   │                                                                   │
   └───────────────────────────┬───────────────────────────────────────┘
                               │  (only this one line needs the internet)
                     Supabase  ▼  Postgres + RPCs + RLS
                               ▲
                       Laravel dashboard on the VPS
                       (menu authoring, web KDS, reports)
```

- Kiosk → KDS is **instant, over WiFi, with the internet unplugged**.
- The KDS never talks to Supabase directly. Its "mark paid" and "advance ticket" actions go to the
  hub, which owns replay to the cloud. One writer to the cloud = no split-brain.
- Online, orders from the **phone app** arrive at the hub (Realtime or poll) and reach the KDS by
  the same internal path. One board, one truth, whether the ticket came from a phone or the kiosk.

### 1.3 Why not the alternatives

- **Both apps independent, syncing only through Supabase** — simplest to build, and it fails the one
  scenario the owner asked for: offline, a kiosk order never reaches the kitchen screen.
- **Peer-to-peer between tablets** — split-brain. Two devices with different ideas about ticket 47.
- **A physical store server** — correct at 40 stores, absurd at one.

The hub is built behind an `OrderFeed` interface with a LAN implementation, so a cloud-fallback
implementation is a later addition and not a rewrite.

### 1.4 Two hardware constraints, before the tablet is bought

- **iOS can only run the embedded server while the app is foregrounded.** Both apps build for both
  platforms, but the **hub role should sit on the Android tablet** — it can be locked to the app as
  device owner and held awake reliably. If the kiosk must be an iPad, it works, but it must never be
  backgrounded, and that is a weaker guarantee.
- **mDNS is blocked by plenty of cheap routers.** Discovery is best-effort; a **manual "enter hub
  address" screen and a DHCP reservation for the kiosk are mandatory**, not a nicety.

### 1.5 Why the kiosk never offers CamPay — online or offline

Owner, 2026-08-15: *"cause mixing campay in offline and online seems complicated"*. Correct, and the
reason is worth recording because it removes a whole category of defect:

A payment method that is available only when the WAN is up makes the **UI change shape based on
network state**. The customer sees tiles appear and disappear; staff get asked why; the kiosk needs
an offline banner, a greyed-tile state, a "connection came back mid-order" transition, and a test
matrix that multiplies by connectivity. Every one of those is a bug surface.

Cash-only collapses it. **The kiosk renders identically with the cable pulled.** There is no offline
mode to design, because there is no online mode to differ from — the only thing connectivity changes
is how quickly the outbox drains, which is invisible to the customer.

The rule that falls out, and it is one rule rather than a list of exceptions:

> **A surface that already requires connectivity may accept a connectivity-dependent tender.
> A surface built to survive without connectivity may not.**

| Surface | Reachable offline? | Tender | Why |
|---|---|---|---|
| Phone app | no | CamPay | Customer has their own phone and their own confirmation |
| Web app | no | CamPay | Same |
| **Web KDS** (dashboard) | **no** | **Cash *or* momo-at-till** | A manager on the dashboard is by definition online, so a momo payment is verifiable at the moment it is recorded. Unchanged from today |
| **Kiosk** | **yes** | **Cash, always** | Identical screens with the cable pulled |
| **Tablet KDS** | **yes** | **Cash, always** | It is the offline surface; it must never record a payment it cannot verify |

So the tablet KDS is not a stripped-down web KDS — the two have different capabilities *because they
have different guarantees*. Enforced in K1 at the RPC, by device role, not by hiding a button.

### 1.6 The inbound direction — already-paid online orders reach the tablet

Owner, 2026-08-15: *"i want the offline POS to be sync with data from the web POS (when internet is
up), so that it received already paid (campay) orders and signal them and display them in the
pipeline."*

The hub is bidirectional. Outbound is the outbox (§1.1). Inbound is a **cursor pull**: the hub asks
Supabase for every order at this branch changed since its last cursor, merges them into the local
store, and pushes them to the KDS over the LAN — the same path a kiosk ticket takes. One board.

Three things make this correct rather than merely working:

**A CamPay order arrives already `paid`, so it skips the counter lane entirely.** It lands directly
in the cook pipeline. That is §6.1 working as designed — the counter lane exists only for tickets
that owe money. Nobody should ever be asked to pay for an order twice.

**Staff must see the difference at a glance.** Every card carries its `source` (📱 app · 🌐 web ·
🖥 kiosk) and its money state. A kiosk ticket in the counter lane means *take cash*; an app ticket
in the cook lane means *already settled, just cook it*. Confusing those two costs the restaurant
money in one direction and a customer's trust in the other.

**Reconnect is a catch-up, not a flood.** When the WAN returns after an outage, the cursor pull may
bring back a dozen orders at once, some placed twenty minutes ago. They must land with their **true
elapsed time** — an order paid at 12:04 shows as 20 minutes old and immediately red, not as new. And
the alert is **one summary** ("4 commandes reçues pendant la coupure"), not four alarms racing each
other. A board that lies about age is worse than a board that was briefly empty.

**The uncomfortable corollary, stated plainly:** while the WAN is down, customers can still pay by
CamPay on their phones, and **nobody in the kitchen knows**. The money is taken and no food is
started until reconnect. Mitigation is a **presence heartbeat** — the hub touches
`pos_devices.last_seen_at` every 30s, and the app/website **warn but still allow** ordering when the
branch has not been seen for a few minutes (owner, 2026-08-15 — §6.3). Without the heartbeat, an
outage is silently a queue of paid-and-unstarted orders.

### 1.7 The link must be VISIBLE — on the LAN and across the WAN

Owner, 2026-08-15: *"I hope you are creating offline POS kiosk to KDS in mobile app (flutter). they
both connected to the same LAN something shows up like they are linked. even when they are both on
WAN something shows up that they can communicate."*

Two requirements, and the second is a **scope addition** to this plan — it is recorded as one rather
than absorbed silently.

**1. The link has a state, and both screens show it.** Not a hidden implementation detail: a
persistent indicator on the kiosk and on the KDS naming *which* peer, *over what*, and *how long
ago* it was last heard from. A kitchen must never have to guess whether the door tablet can still
reach it — silence and disconnection look identical on a board with no indicator, and that is the
single most expensive ambiguity in this whole architecture.

**2. The two tablets must be able to talk when they are NOT on the same LAN.** The original plan put
a cloud-fallback `OrderFeed` in K10 ("deliberately not in v1"). The owner has now asked for it, so it
moves into the build as **K3c**. It is additive on the architecture exactly as K10 predicted — the
hub stays the single writer of order state to the cloud; the cloud becomes a second *delivery route*
for the same envelopes, not a second author.

The state model, defined in K2 so K3/K3c only render it:

| state | shown as | meaning |
|---|---|---|
| `lan` | **Lié — réseau local** (green) | Direct socket to the peer on the restaurant LAN. Sub-second, survives the internet being unplugged. The normal state |
| `cloud` | **Lié — via Internet** (blue) | No LAN route, but both devices reach Supabase and envelopes are relaying through it. Slower, and it **stops working the moment the WAN does** — so the badge says so |
| `stale` | **Dernier contact il y a N min** (amber) | A route existed and has gone quiet past the threshold. Not yet declared dead |
| `none` | **Hors ligne — aucun lien** (red) | Neither route. The kiosk keeps taking orders (that is the point) and the KDS keeps working its mirror; new tickets simply do not cross until a route returns |

Three rules that fall out, and each exists because its absence is a defect:

- **LAN wins whenever it is available.** Never relay through Kinshasa what can cross the room. The
  monitor prefers `lan` and demotes to `cloud` only after the LAN peer is genuinely unreachable, so a
  single dropped packet does not move the store's traffic onto the internet.
- **A green badge must mean a *proven* round trip**, not "we opened a socket once". Presence is an
  application-level ping with a reply, not TCP's opinion. A socket that is open to a crashed app
  reports connected forever.
- **The badge never blocks anything.** It is information. Every action on both tablets stays local
  and instant in every one of the four states — that is §23.1, and a link indicator that gates a
  button would quietly undo it.

**What this does NOT change:** the KDS still never writes order state to Supabase. Over the cloud
route it sends *the same envelope it would have sent over the LAN*, addressed to the hub, and the hub
applies it and remains the only writer. Single-writer is what makes replay safe (§23.2); a cloud
transport that let both tablets write would reintroduce exactly the split-brain the hub exists to
prevent.

---

## 2. The flow, end to end

**Offline** (the case that must be perfect — and, cash-only, identical to the online case):

1. Customer taps the kiosk out of its attract loop. Menu comes from the **pinned local snapshot**.
2. Composes, adds to cart. Prices computed locally from the snapshot — with the same
   per-ingredient quantity rules as §8.2, from the same data.
3. Confirms. **No mode picker** — the kiosk sells take-away only, so that screen does not exist.
4. Kiosk mints `id` + a **local ticket number**, writes the order `pending_payment` / `unpaid` /
   `payment_method = pay_at_counter`, appends to the outbox, pushes it to the KDS over the LAN.
5. **Printer slips the ticket**: big number, items, total, **"Payez en espèces à la caisse"**, and
   the **order code + QR** — because `ready → completed` is a *verified* collection (§6 state table,
   "pickup collected … verify ticket QR/code"), and offline that verification has nothing to scan
   unless the slip carries it.
6. Kiosk resets to attract in ~4s. Total network calls made: zero.
7. The ticket appears **in the KDS counter lane, not the cook lanes** (§6.1 invariant holds offline).
8. Customer pays cash at the counter. Staff taps **Encaisser (espèces)** on the KDS tablet — one
   action, no tender picker, no typed note → hub records the cash payment → status `placed` → the
   ticket moves into the cook lane and the kitchen starts.
9. Kitchen advances Accept → Preparing → Ready on the KDS. Every tap writes to the hub, appends to
   the outbox.
10. Unpaid tickets **expire locally after 15 minutes**, mirroring the §6.3 cron the hub cannot reach.

**When the internet returns:** the outbox drains in sequence. The server dedupes on the client id,
applies status changes through `rpc_transition_order`, and **drops any transition that would move a
ticket backwards**. The kiosk shows a sync badge; the manager's shift-close screen shows counts.

**Online**, exactly one thing differs, and no customer can see it: the hub also receives phone-app
orders and forwards them to the KDS. The kiosk's own screens are byte-identical either way.

---

## 3. Stages

Each stage names its **proof**. A stage is not done because it compiles.

### K0 — Canon first *(no code)*

**DONE 2026-08-15.** `ECOSYSTEM.md` → **v1.16**, new **§23** "The store keeps trading when the
internet does not" — hub shape, device-minted identity, the outbox and its monotonic rule, both sync
directions and the returning-flood trap, presence, and the rules that hold whatever else changes.

> Corrected during the work: the plan said *v1.15 / §22*. ECOSYSTEM was **already** at v1.15 and
> **§22 is operator alerting**, written earlier the same day. Hence v1.16 / §23 — and §22.1's
> *waiting* vs *notice* alarm registers are **already canon**, so K5 inherits them (§23.6) instead of
> inventing a second alarm vocabulary.

**Flip §5 matrix row 5 — `pay_at_counter` for `pickup` — and treat it as load-bearing.** Take-away
only means every kiosk order is `pickup` + `pay_at_counter`, and that exact pair is **OFF today**
("single setting can enable later"). It is now the single gate on the kiosk existing at all. Name
the setting, flip it, and prove the guard that currently rejects the pair is gone before K1 writes a
line of SQL. **Amend §7.4** — the till tender
becomes a structured field rather than a free-text note, **cash or momo on the web KDS, cash only on
the tablet KDS**. Record §1.5's single rule (*a surface that requires connectivity may accept a
connectivity-dependent tender; one built to survive without it may not*) as the reasoning, so a
future session cannot reintroduce momo-at-kiosk as an "improvement".
`BUILD_PLAN.md` in both repos gets the K-stage table.

**Proof:** canon merged before the first migration is written.

### K1 — Server truth: schema, RPCs, device identity

One dated migration:

- `orders.user_id` → **nullable**; new `orders.source text not null default 'app'` checked against
  `('app','web','kiosk')`; constraint: `user_id is null` ⟹ `source = 'kiosk'`.
- `orders.client_id uuid unique` — the device-minted identity replay dedupes on.
- `orders.menu_version integer` — which priced snapshot this sale was rung against.
- `orders.placed_at_device timestamptz` alongside the server clock (offline devices drift; store
  both, order by `device_seq`, never by wall clock).
- `pos_devices` table: id, branch, label, role (`kiosk` | `kds`), **api key hash**, `last_seen_at`.
- `rpc_place_kiosk_order(p_client_id, p_items, p_mode, p_menu_version, p_device_seq, …)` —
  no `auth.uid()`, authenticated by device key, **idempotent on `client_id`**, prices server-side
  from the named snapshot and **rejects on a price mismatch** rather than silently trusting the
  tablet.
- **Structured till tender.** New `orders.tender text check (tender in ('cash','mobile_money'))` —
  a column, not the free-text `till_note` the web KDS requires today (`KdsController.php:136`),
  which cannot be summed and so has never been reportable. `rpc_mark_counter_paid` gains
  `p_tender default 'cash'`; `till_note` stays **required for `mobile_money`** (it carries the
  transaction reference) and becomes **optional for `cash`**. Existing rows backfill to `'cash'`
  with their note preserved verbatim — nothing already recorded is rewritten or lost.
- **The offline surface cannot record momo, and that is enforced server-side.** A `kds`-role
  **device key** may only pass `p_tender => 'cash'`; a staff web session may pass either. The RPC
  raises on violation. Hiding a button is not enforcement — a replayed outbox entry does not go
  through the UI.
- `rpc_mark_counter_paid` reachable by a `kds`-role device key.
- `rpc_menu_snapshot(p_version)` → the whole pinned bundle in one call.
- **Kiosk orders are always `mode = 'pickup'` with `table_id null`** — `rpc_place_kiosk_order` does
  not take a mode at all, so a kiosk cannot emit a dine-in order even by accident.

> **Corrected while writing the migration.** An earlier draft of this line said the §5 flip lets the
> pair past `rpc_place_order`'s guard. It does not, and must not: `rpc_place_order` **stays
> untouched** and keeps raising `counter_dine_in_only`. The matrix opens that pair for the *kiosk*,
> which reaches the database through its own RPC. Letting the customer-facing path accept a counter
> tender would be a way to eat without paying. Verified: the matrix is enforced only inside
> `rpc_place_order` — there is no table trigger — and `orders_guard_payment_provider` returns early
> on a null provider, so a kiosk order passes it untouched.
- RLS: kiosk orders visible to staff, **never** to any customer account.

**Proof:** pgTAP/SQL tests — replaying the same `client_id` five times creates one order; a stale
`preparing` after `ready` is refused; a customer JWT cannot read a kiosk order.

> ## K1 RESULT — **APPLIED to production 2026-08-15, verified.** Recorded as migration
> `20260815120000`. Three defects were found reviewing the written migration and fixed **before** it
> was applied; the first is the important one.
>
> ### ⚠ The constraint would not have applied, and forcing it would have broken account deletion
>
> The draft asserted `check ((user_id is null) = (source = 'kiosk'))`, on the stated reasoning that
> "anonymous" and "kiosk" are the same fact. **They are not.** `orders.user_id` has been nullable
> since `20260731120000_account_deletion.sql`, whose own comment reads: *"NULL then means exactly one
> thing: this customer deleted their account"* (§14.7 — Apple 5.1.1(v) and Play both require in-app
> deletion, so it is store-blocking).
>
> **Ten production orders are already anonymous for that reason** (`TM-100071`…`TM-100102`, checked
> 2026-08-15), so the equivalence would simply have failed to apply. Worse, had it been forced
> through with a backfill, the FK's `on delete set null` would violate the check on every future
> deletion — **a customer could no longer erase themselves.**
>
> Now one-directional: `check (source <> 'kiosk' or user_id is null)`. That `user_id is null` no
> longer identifies a kiosk sale is exactly why `source` has to be its own column.
>
> ### The other two
>
> * **`p_tender` defaults to NULL, not `'cash'`.** A `cash` default contradicted this migration's own
>   refusal to backfill: the dashboard's live 2-argument call would have stamped every till payment,
>   **including mobile money**, as cash from the moment it landed — and K7's shift-close totals would
>   have been confidently wrong. Null means "the caller did not say"; the dashboard was updated in
>   the same pass (K1b) so it always says.
> * **The `unique_violation` handler re-raises** unless the collision really was `client_id`. It
>   previously swallowed *any* unique violation and returned `{order_id: null, replayed: true}` — an
>   order the kiosk believes is placed, has printed a slip for, and which does not exist.
> * **A device may only settle its own branch's till.** `rpc_device_mark_counter_paid` resolved the
>   device and then never compared branches. A device key is a bearer credential on a tablet in a
>   public room; without the check, a lifted key marks orders paid in another restaurant.
>
> ### Proof taken against production
>
> | check | result |
> |---|---|
> | dashboard's 2-arg `rpc_mark_counter_paid` still resolves | **yes** — called it: raises `not_counter_payable`, not `undefined_function` |
> | `rpc_mark_counter_paid` overloads | exactly **1** (the ambiguity trap avoided) |
> | 10 deletion-anonymised orders | intact |
> | `tender` on all 19 existing rows | **null** — nothing invented |
> | `pos_devices`, `branch_online`, kiosk/device/heartbeat RPCs | present |
>
> ### K1b — the dashboard states the tender *(done in the same pass)*
>
> Without it, K1 would silently degrade the data it exists to structure. `OrderTender` enum,
> `markCounterPaid($id, $tender, $note = null)`, `required_if` on the reference, and the counter lane
> now settles **cash in one tap with nothing to type** — the note was only ever required because free
> text was the sole record. Mobile money still demands its reference, enforced in the controller
> **and** in the RPC. Webapp suite **676 / 673 passed / 3 skipped**.

### K2 — `pos_core`: the offline engine *(the heart — no UI)*

A shared Dart package used by both apps. Pure Dart, host-testable, zero platform channels.

- SQLite store: orders, lines, snapshot, outbox, device state.
- **Outbox**: append-only, `(device_id, seq)` ordered, at-least-once drain with exponential backoff
  and jitter, poison-message quarantine after N failures with a visible manager alert.
- **Snapshot pinning**: download → validate whole → activate atomically. Never activate a partial.
- **Monotonic guard**: a status transition table that refuses backwards moves *locally too*, so the
  device never even queues an invalid move.
- **Clock discipline**: `device_seq` monotonic counter persisted across restarts; both timestamps
  stored; ordering never depends on a wall clock.
- **Money**: integer minor units end to end. A lint/test asserts no `double` in the pricing path.
- **Link state** (§1.7): the four-state model, transport preference and staleness thresholds, as
  pure logic. K3/K3c feed it events; K4/K5 render it.

**Proof:** ≥60 host tests. Kill-the-process-mid-write test; drain-out-of-order test; duplicate-drain
test; snapshot-activation-interrupted test.

---

#### K2 detailed plan *(written 2026-08-15, before the first line of code)*

**Location** `timmaeat-app-flutter/packages/pos_core/` — a pure-Dart package inside the schema-owner
repo, consumed later by the kiosk app (K4) and the KDS app (K5) as a path dependency. It is *not* a
dependency of the customer app and must never become one.

##### Deviation from the stage brief: `package:sqlite3` directly, not drift

The brief above said drift. Building it, three reasons said otherwise, and the decision is recorded
so a later session does not read this as an oversight:

1. **The deliverable of K2 is a durability guarantee, and the guarantee is spelled in raw SQLite
   nouns** — `journal_mode=WAL`, `synchronous=FULL`, explicit transaction boundaries. The
   kill-mid-write proof is a statement about those three. An ORM is a layer between the test and the
   thing under test.
2. **The query surface is tiny** — seven tables and about thirty statements, nearly all keyed
   lookups. drift's type-safe DSL earns its keep on large read-heavy surfaces; here it buys little.
3. **No codegen.** This repo runs no `build_runner` today. Adding one to the critical path of the
   offline engine means every session that touches a table must regenerate before tests mean
   anything, and a stale generated file is a silent wrong answer.

**The risk is neutralised rather than accepted**: every statement lives behind `PosStore`, an
interface the engine talks to. Swapping in drift later is one implementation, not a rewrite.

For the Flutter apps the native library comes from `sqlite3_flutter_libs` in *their* pubspecs; on the
host, `package:sqlite3` opens the system `libsqlite3.dylib`. `pos_core` itself stays platform-free.

##### Module map

| path | holds |
|---|---|
| `lib/src/money.dart` | integer minor units, line/total arithmetic. No `double`, ever |
| `lib/src/ids.dart` | UUID v7 `client_id` minting (time-ordered so an id sorts like its creation) |
| `lib/src/clock.dart` | injectable clock — tests must not depend on the machine's |
| `lib/src/device.dart` | `device_id`, role, branch, and the **persisted monotonic `device_seq`** |
| `lib/src/store/schema.dart` | table DDL + the local schema version ladder |
| `lib/src/store/pos_store.dart` | the interface the engine uses |
| `lib/src/store/sqlite_pos_store.dart` | the only place SQL is written |
| `lib/src/snapshot/` | stage → validate → activate, and the pinned-menu reader |
| `lib/src/outbox/` | envelope, append, claim, ack, backoff, quarantine |
| `lib/src/guard/status_guard.dart` | the transition table + the monotonic merge rule |
| `lib/src/link/` | the §1.7 four-state model and its monitor |
| `lib/src/engine/pos_engine.dart` | the façade both apps call |

##### Tables (local SQLite — unrelated to the Postgres schema, and deliberately not a mirror of it)

`pos_meta` · `menu_snapshots` · `snapshot_products` · `orders` · `order_lines` · `outbox` ·
`applied_envelopes`.

`applied_envelopes` is the inbound twin of the outbox: the KDS receiving the same hub message twice
(a reconnect replays it) must apply it once. At-least-once delivery in both directions means
idempotency in both directions.

##### The four design decisions worth arguing about

**1. Ordering is per *subject*, not global.** The outbox drains in `seq` order, but an envelope is
only blocked by an earlier unfinished envelope **for the same order**. A poisoned ticket must not
stop the rest of the day's sync — a kitchen whose entire outbox is jammed behind one bad row has lost
the whole shift's reconciliation, not one ticket. Quarantine therefore halts *that order's* lane and
raises a named manager alert; every other order keeps flowing.

**2. The engine never awaits the network — the *store write* is what "done" means.** `placeOrder`
writes the order, its lines and the outbox envelope in **one transaction** and returns. There is no
code path in which a slip prints for an order that is not durably on disk, and none in which an
envelope exists for an order that does not.

**3. `device_seq` is allocated inside that same transaction.** Allocating it before, and crashing,
would burn a number — survivable. Allocating it after, and crashing, would reuse one — a duplicate
`(device_id, seq)` is a corrupt ordering key, and the whole replay contract is built on it.

**4. The local guard is a strict subset of `rpc_transition_order`.** Mirrored from
`20260810120000_order_notifications.sql:96-105`, verbatim. The device refusing something the server
would accept is a bug the staff can see and report; the device *queuing* something the server will
reject is an envelope that can never drain and a lane that quarantines itself.

##### Test inventory — target ≥ 60

money 6 · ids + `device_seq` 7 · store/schema 4 · snapshot 10 · outbox 15 · guard 12 · engine 8 ·
link 7 · durability 3. The four named proofs:

- **kill-mid-write** — a real child process is `SIGKILL`ed mid-transaction; the parent reopens the
  database and asserts no order without its lines, no envelope without its order, and no burned or
  duplicated `seq`.
- **out-of-order drain** — envelopes acked by the sink in the wrong order; the store's view of what
  is sent must not depend on the sink's manners.
- **duplicate drain** — the same envelope delivered twice changes nothing, on both sides.
- **interrupted activation** — a snapshot killed between stage and activate, and again mid-activate;
  the previous version is still serving in both cases, and it is still *whole*.

##### Two gaps in K1 that K2 must not paper over

Checked against the applied migration, not assumed:

- **`rpc_menu_snapshot` does not exist.** The K1 brief listed it; the migration that shipped does
  not contain it. K2 defines the snapshot *format and pinning* and takes its bundle from an injected
  `SnapshotSource`; the RPC is a one-function migration owed at **K3b**, when there is finally
  something to call it from.
- **There is no device-role transition RPC.** `rpc_transition_order` is `service_role` only
  (`…:175`), so a `kds` device key cannot advance a ticket. `rpc_device_mark_counter_paid` exists;
  its advance-the-ticket sibling does not. Also owed at K3b, in the same migration.

Neither blocks K2 — it is offline-first by construction, and its cloud edge is an interface with a
fake behind it in tests. Both are recorded here so K3b does not discover them as surprises.

---

> ## K2 RESULT — **DONE on the host, 2026-08-15. 116 tests, all green.** Not on a device: K2 has no
> UI, and its device proof is K3's.
>
> `packages/pos_core/`, pure Dart, `dart test` in about two seconds. `dart analyze` clean;
> `flutter analyze` at the repo root unaffected (the nested package carries its own options) and the
> app suite still **350 / 350**.
>
> Test count by file: `outbox` 23 · `engine` 20 · `status_guard` 18 · `snapshot` 12 · `link_state` 10
> · `ids_and_seq` 9 · `money` 7 · `enum_parity` 5 · `store_schema` 5 · `durability` 4 ·
> `money_is_integer` 3. Target was ≥ 60.
>
> ### Every test was proven to bite
>
> A green suite that stays green with the behaviour deleted proves nothing, so each load-bearing
> guarantee was reverted and the suite re-run:
>
> | behaviour removed | result |
> |---|---|
> | snapshot re-validation at activation | snapshot suite **fails** |
> | per-subject ordering → global FIFO | outbox suite **fails** ("a stuck order does NOT block a different order") |
> | monotonic merge → last-write-wins | guard **and** engine suites fail (2 tests) |
> | the sale's transaction wrapper | engine atomicity test fails **3 runs out of 3** |
>
> ### What the kill-mid-write proof actually proves — and what it does not
>
> The fuzz (`loop` mode: sell in a tight loop, `SIGKILL` at an arbitrary instant) caught a
> deliberately non-atomic sale in only **one run out of three**. The kill has to land in the narrow
> gap between two commits, and most of the loop is spent elsewhere. A test that catches a real bug a
> third of the time is not a proof, so two more were added rather than leaving it at that:
>
> * **`hang` mode** — deterministic, about the *store*: the victim dies inside a transaction it will
>   never commit. Nothing survives: no order, no envelope, **no burned `device_seq`, no burned ticket
>   number**. Fails every time if rollback is broken.
> * **`engine_test.dart` → "a failure at the LAST write undoes the whole sale"** — deterministic,
>   about the *engine*: a store that throws exactly at `appendEnvelope`, after the order and lines
>   are written. This is the one that catches an engine that forgot to wrap, 3 runs out of 3.
>
> And the honest limit: killing a **process** does not discard the OS page cache, so none of these
> proves fsync durability. That is what `synchronous = FULL` buys, and only a pulled plug
> demonstrates it — a K9 device drill.
>
> ### Two corrections made while building
>
> * ⚠ **UUID v7 is time-ordered only to the millisecond.** The first draft asserted that ids sort in
>   creation order and the test failed on a burst of twenty: `package:uuid` adds no
>   within-millisecond counter, so ids minted in the same millisecond sort arbitrarily. The claim in
>   `ids.dart` was corrected rather than the test weakened. It changes nothing structurally —
>   `device_seq` was always the ordering key (§23.4), precisely because a device's clock is not
>   trustworthy — but "the id sorts like its creation" would have been a false premise for someone
>   later reading an outbox by hand.
> * **Ordering is per subject, not global** (argued in the module plan above, and now enforced and
>   tested). A poisoned envelope halts *its own order's* lane and raises a named manager alert; every
>   other order keeps flowing. Global FIFO would cost a restaurant its whole afternoon of cloud state
>   over one bad ticket.
>
> ### Also deliberate
>
> * **A network failure is retried forever; only a server *rejection* can quarantine.** "The internet
>   has been down since Tuesday" must not lose a sale, so there is no attempt cap on the retryable
>   branch. A transport that throws counts as retryable — the one thing known is that the server did
>   not get to have an opinion.
> * **There is no `inflight` envelope state.** A claim is a read; a crash between claiming and
>   sending leaves the row exactly as pending as it was. An `inflight` column would need a recovery
>   sweep on every launch to un-stick rows a crash abandoned — a whole failure mode bought for
>   nothing.
> * **`snapshot_products.ord`** stores the position in the bundle as it arrived, separately from
>   `sort_index`. The checksum is taken over the array the server sent, so reconstructing in display
>   order would fail validation on a perfectly good menu.
>
> ### Left for the stage that can actually prove them
>
> `BUILD_PLAN.md` in this repo is **not updated** — it is uncommitted in the parallel session and
> owned by it (CONTINUE trap 6). The K ledger there still reads K1b.

### K3 — LAN hub transport

`shelf` + `shelf_web_socket` server in the kiosk app; mDNS advertise (`nsd`) with a **manual IP
fallback screen**; pairing by a 6-digit code shown on the kiosk and typed on the KDS, exchanging a
device key; heartbeat + reconnect with backoff on the KDS side; a visible connection state on both.

**Proof:** on the owner's **no-internet WiFi box** — order rung on the kiosk appears on the KDS in
under one second; KDS killed and relaunched rebuilds its board from the hub; kiosk rebooted, KDS
reconnects without a human touching it.

### K3b — Inbound cloud feed + presence heartbeat

The other half of the hub (§1.6). Cursor-based pull of every order at this branch changed since
`last_synced_at`, merged into the local store under the **same monotonic guard** as outbound replay —
a cloud row may not move a ticket backwards either. Realtime subscription when it is up, poll as the
floor, because Realtime silently dies on flaky links and a kitchen must not depend on it.

Also: the heartbeat. Hub touches `pos_devices.last_seen_at` every 30s; a `branch_online` view the
customer app and website can read.

**And the customer-side half of the "warn but allow" decision** — this reaches into the other two
repos: a calm banner on the phone app's and the website's checkout when the branch has not been seen
for a few minutes ("Le restaurant est momentanément hors ligne — votre commande peut prendre plus de
temps"). Ordering is never blocked. The banner must **fail open**: if the heartbeat view itself
cannot be read, show nothing rather than warning about an outage that may not exist.

**Proof:** an order paid by CamPay on the phone appears on the KDS in under 5s with the WAN up. Then
the hard case — WAN pulled, three orders placed and paid from a phone, WAN restored: all three land
with **correct elapsed times**, correct SLA colours, and **one** summary alert. Replaying the same
cursor window twice changes nothing.

### K3c — Cloud relay: the two tablets talk when they are not on one LAN

**Promoted out of K10 by the owner, 2026-08-15 (§1.7).** A second transport for the *same* envelopes
K3 carries over the LAN, so a KDS in the back office on mobile data, or a kiosk on a separate
guest VLAN, still reaches its hub.

- `EnvelopeTransport` gains a `CloudRelayTransport` beside `LanSocketTransport`. `pos_core` already
  addresses envelopes to *the hub*, not to an IP, so neither the engine nor the outbox changes.
- **The hub stays the only writer of order state to the cloud** (§23.2). The KDS's relayed envelope
  is an *intent addressed to the hub*, which the hub applies and then replays outbound as it always
  did. A relay is a postal service, not a second author.
- Route selection is the §1.7 preference: LAN whenever a proven round trip exists, cloud only after
  the LAN peer is genuinely unreachable, and the badge tells the room which one is carrying traffic.
- The relay is **not** a substitute for the LAN and the UI must not let anyone believe it is: over
  the cloud the store's internal traffic depends on the internet, which is the dependency this whole
  architecture exists to remove. It is a fallback, labelled as one.

**Proof:** kiosk and KDS on two different networks (phone hotspot vs house WiFi) — a ticket rung on
the kiosk reaches the board, and the badge reads *via Internet*. Then the LAN is restored and the
badge returns to *réseau local* **without either app being restarted**. Then the WAN is pulled with
both on the same LAN: the badge goes green and everything keeps working, which is the case that
proves the fallback did not quietly become the primary.

**K3c implementation — milestone 1: pure-Dart transport + route selector + fake-relay tests
(plan, 2026-08-15).** Per the plan's own ordering, the deterministic logic lands and is proven
against an injected relay before any real Realtime channel exists:

1. `CloudRelayBackend` — a two-line seam (`Stream<String> inbound`, `Future<void> publish(String)`,
   `Future<void> close()`). The real implementation (Supabase Realtime channel, one per branch) is a
   K5/K9 concern; K3c proves everything above the wire.
2. `CloudRelayTransport implements EnvelopeTransport` beside `LanSocketTransport`. It reuses the
   existing `LinkFrame` wire and `DeviceCredential` MAC — **the relay carries the same signed
   envelopes, so there is no second authentication invented**. Delivery publishes a signed
   `envelope` frame, awaits the matching `deliveryAck` by frame id with the same timeout, and
   records `LinkPong(LinkTransport.cloud)` on relay pongs. Unverifiable frames are ignored — they
   carry no authority and must not be able to kill the fallback.
3. `RouteSelector` — pure logic over `LinkMonitor.allRoutes()`: LAN is used while its route is not
   dead (i.e. within `deadAfter`), cloud only after LAN genuinely goes silent. A LAN pong returning
   promotes traffic back **without a restart**. The badge already states the same preference in
   `LinkState` (§1.7); the selector routes traffic exactly the way the badge reads.
4. Hub side: `CloudRelayHubListener` verifies each relayed frame against `PairingRegistry
   .credentialFor(frame.deviceId)` and applies intents through the **same** `HubEnvelopeApplier`
   that `LanHubServer` uses (extracted verbatim from `_applyEnvelope` so the two routes cannot
   drift). The hub stays the sole Supabase writer; a relayed `envelope` is applied locally and the
   board is published back over the relay.
5. Deterministic tests (no sockets, no Supabase): fallback to cloud after LAN silence past
   `deadAfter`, promotion back to LAN on a returning pong, no-double-apply of a replayed envelope
   (`markApplied` wins), relay deliver/ack/timeout, hub verification rejection of an unsigned or
   foreign frame, and the badge route preference across the whole fallback→recovery cycle.

> **RESULT — DONE 2026-08-15, after a review pass that found three defects.** All five
> K3c-milestone-1 files landed (`pos_link` **47/47**, +23 new tests; `pos_core` 116/116;
> `pos_link_flutter` 9/9; app 353/353; analyze clean). The route selector is pure logic over
> `LinkMonitor.allRoutes()` — LAN while not dead, cloud after silence past `deadAfter`, promotion on
> a returning pong with no restart; the KDS transport and hub listener share the existing
> `LinkFrame`/`DeviceCredential` wire, so the relay proves the same device identity as the LAN and
> invents no second authentication; `LanHubServer` now applies intents through the same extracted
> `HubEnvelopeApplier` the relay uses. Relay envelopes are applied locally by the hub, which stays
> the sole Supabase writer.
>
> **What the review caught — each one was proven with a probe before it was fixed, and each fix now
> has a test that fails without it:**
>
> - **The relay had no heartbeat.** `pingNow()` was called once, from `connect()`, and its own doc
>   referred to a "periodic caller" that did not exist. `staleAfter` is 20 s and `deadAfter` 90 s, so
>   over a relay answering *every* ping the badge went amber at 21 s and red at ~100 s and stayed
>   there. The operator's only signal during a WAN fallback read **offline while orders were
>   flowing**. Fixed: `pingInterval` (5 s, sized like the LAN's) drives a `Timer.periodic`, cancelled
>   on `close()`.
> - **An undecodable frame killed the route.** The `catch` wrapped `LinkFrame.decode`, so a parse
>   failure — *before* any MAC check — called `recordDown(cloud)`. On the branch-wide bus this file
>   is written for, one malformed byte from any publisher took the fallback down, which is exactly
>   the denial of service the class doc claimed immunity from. Fixed: decode and verify failures are
>   dropped silently; only a *backend* error is evidence the route died.
> - **The board reached only the tablet that acted.** `LanHubServer.publishBoard()` fans out to every
>   authenticated peer; the relay signed one snapshot for the requester. On a kitchen+bar branch the
>   other board stayed stale until it happened to act. Fixed: `CloudRelayHubListener.publishBoard()`
>   mirrors the LAN, one board per verified peer signed with that peer's own credential.
>
> The regression test for the second defect was **vacuous** — it asserted an already-offline badge
> stayed offline, which is why the bug survived it. It now records a live pong first, so "cannot kill
> the fallback" has something to kill.
>
> **Known and deliberate at this milestone:** the fake relay is a two-ended pipe, while the real
> backend is a branch-keyed *broadcast* channel — self-echo and cross-device traffic are untested,
> and the MAC gives integrity but **not confidentiality**, so every paired device on a branch can
> read its peers' frames in plaintext. Decide the channel-authorization and encryption posture when
> the real `CloudRelayBackend` lands (K5/K9); it drops straight onto this seam. The ack-outcome
> vocabulary (`delivered`/`rejected`/`retryable`) is still duplicated between
> `LanSocketTransport._completeDelivery` and the relay's — the same drift risk `HubEnvelopeApplier`
> removed, worth extracting next.

### K4 — Kiosk UI *("very beautiful")*

Attract loop (dish photography, gentle motion — the F-pass motion rules apply: **1–2 animated
elements per view**, per `design-fable-pass-2026-08-05`). Menu browse, composer at parity with the
phone app, cart, confirm, and a **large calm "pay at the counter" number screen**. Idle timeout that
clears an abandoned cart and returns to attract. Touch targets sized for a standing customer at
arm's length, not a phone in the hand. FR/EN from the existing l10n.

Take-away only removes the mode screen entirely — **four taps from attract to printed slip** is the
target, and every screen that is not on that path has to justify itself.

**Proof:** golden tests for the main states; a walkthrough on both tablets; no PII rendered anywhere.

### K5 — KDS Flutter app

Counter lane first — **it is the lane that releases tickets to the kitchen** — then the cook lanes
mirroring `KdsLanes`/`KdsColumn` semantics exactly, SLA amber/red from the same thresholds, card
detail, and local 15-minute expiry of unpaid tickets. Every action writes through `pos_core`.

The counter action is **one button, cash, no picker and no typed note** — a kitchen tablet during a
rush is the worst place in the building to ask someone to type into a text field. The ticket total
is shown large so staff can take the note and count change against it.

**Card identity (§1.6).** Every card shows its `source` badge and its money state, so *take cash* and
*already paid* are never confusable. Paid-online tickets enter the cook lane directly.

**Alarm inherits ECOSYSTEM §22.1's two registers** — *waiting* (repeats until the lane empties) and
*notice* (sounds once, never repeats, for scheduled tickets). That vocabulary is already canon as of
v1.15; do not invent a second one. Thresholds come from the same settings as the web board
(`config/kds.php`), so the two cannot drift.

The native app **deletes** the browser-autoplay workaround the web board is built around
(`index.blade.php:57-104`) — no audio-permission gesture, no reload killing the alarm. It can also
vibrate and flash, which a browser tab cannot. Batched catch-up alert on reconnect, per §1.6.

**Proof:** lane logic tests ported from `KdsLanesTest`/`KdsAdvanceTest` so the two KDS
implementations cannot drift; offline advance proven on the WiFi box.

### K6 — Receipt printer

Network ESC/POS thermal printer on the same LAN (no Bluetooth pairing pain). Print queue with retry,
paper-out detection, reprint-last, and a **clear failure state** — a lost slip is a lost order.
Slip layout: ticket number dominant, items, total, timestamp, "Payez en espèces à la caisse", and
the **order code + QR** for the verified collection at `ready → completed`. The QR must encode a
code the KDS can verify **from its local store**, with no lookup — otherwise collection breaks in
exactly the outage the slip exists to survive.

**Proof:** physical print, paper pulled mid-job then reinserted, printer powered off and back on.

### K7 — Sync, replay and reconciliation

Drain on WAN return; sync badge; **shift close** screen: local tickets vs cloud-acknowledged vs
unsent, with the unsent list nameable. Manager can force a drain.

Shift close reports **cash and momo-at-till as two separate totals**, the cash one countable against
the drawer. Both numbers are only computable because K1 made the tender a column instead of a
sentence — today neither exists. Tickets taken on the tablet can only ever land in the cash column.

**Proof:** an hour offline with ≥20 orders across all statuses, then reconnect — cloud state matches
local exactly, and a deliberate duplicate drain changes nothing.

### K8 — Kiosk hardening

Android device owner + screen pinning; `wakelock_plus`; notification shade suppressed; crash
auto-restart into the kiosk; no route to any admin surface; no back-door out of the app. iOS:
Guided Access documented, Autonomous Single App Mode noted as needing supervision/MDM.

**Proof:** ten minutes of adversarial poking on the device — swipes, long-presses, volume+power,
force-crash — never escapes the app.

### K9 — Device proof on both *(owner rule)*

Full loop on the **Samsung S10 and the iPhone "bocav"**, on the no-internet WiFi box and again on a
live connection. Screenshots into `docs/`.

### K10 — Deliberately *not* in v1

Cash drawer and change calculation; loyalty at the kiosk; a second kiosk tablet. Each is additive on
this architecture, none requires revisiting it.

> **Moved out, 2026-08-15.** The cloud-fallback transport was listed here. The owner asked for it
> (§1.7), so it is now **K3c** — and it went in exactly as this section predicted: additively, with
> no change to the engine, the outbox or the single-writer rule.

**Mobile money at the kiosk is not "later" — it is out of scope by design** (§1.5). Adding it would
reintroduce the connectivity-dependent UI this decision exists to delete. Customers who want to pay
by CamPay use the phone app or the website; that is what those surfaces are for.

---

## 4. Risks, named

| Risk | Handling |
|---|---|
| Kiosk tablet dies mid-shift | KDS keeps its local mirror and can still advance tickets; new orders stop until the hub returns. Documented as the accepted single point of failure at one restaurant |
| Router blocks mDNS | Manual IP entry + DHCP reservation, mandatory from K3 |
| iPad as hub, backgrounded | Hub role recommended on Android; if iPad, kiosk lock makes backgrounding near-impossible, and the KDS shows a loud "hub unreachable" state |
| Price drift between snapshot and server | `rpc_place_kiosk_order` reprices server-side and rejects mismatches; the order records its `menu_version` |
| Someone taps Payé on a ticket never paid | Same trust model as the existing counter role today. Audit trail records the device and time |
| Two KDS devices advancing the same ticket | The hub serialises; the database settles the same race it already settles today |
| **CamPay orders paid during an outage, kitchen blind to them** | Presence heartbeat (K3b) + loud batched catch-up with true elapsed times, plus a customer-facing warning banner (§6.3, settled). **The residual risk is real and cannot be fully removed** — a warned customer can still pay into a dark kitchen |
| Realtime silently dies on a flaky link | Poll is the floor, Realtime is the accelerator. The board never depends on a socket staying alive |

---

## 5. Rough effort

K0 small · K1 medium · **K2 large (the heart)** · K3 medium · K3b medium · K3c small-medium ·
**K4 large (the beauty)** · K5 medium · K6 small-medium · K7 medium · K8 small · K9 small.

K2, K3 and K3b must land before any UI is worth building. K4 and K5 can then proceed in parallel.
K3c is small **because** K2 makes it so: it is one more `EnvelopeTransport`, and if it ever looks
larger than that, the engine has grown a dependency on the LAN that it was designed not to have.

---

## 6. Owner decisions — settled, and the one still open

**6.1 Kiosk mode — SETTLED 2026-08-15: take-away only.** Every kiosk order is `pickup` +
`pay_at_counter`, no dine-in, no table. Consequences already folded in: no mode screen in K4, no
`table_id` in K1, the §5 matrix row 5 flip promoted to the load-bearing gate in K0, and the slip
carries the collection code + QR (K6) because pickup collection is a *verified* step.

**6.2 Which tablet is the hub — STILL OPEN.** Android strongly preferred (§1.4). **Needed before
hardware is bought**, not before code starts. This is the only unanswered question in the plan.

**6.3 Branch-offline behaviour — SETTLED 2026-08-15: warn but allow.** Banner on the phone app and
website checkout when the branch has not heartbeated; ordering never blocked; **fails open** if the
heartbeat itself cannot be read. Built in K3b.

> **Scope note.** 6.3 is the only decision here that reaches outside the two new apps — it puts a
> small change into `timmaeat-app-flutter`'s customer app **and** `timmaeat-webapp`. Both are
> additive, neither touches the order path.

---

## 7. K3–K9 execution plan — continuation pass, 2026-08-15b

Written before the first K3 source edit, per `CLAUDE.md` §0.6. This is an implementation record,
not a change to the cross-repo canon: `ECOSYSTEM.md` §23 already contains the governing contract.
Its uncommitted v1.17 delta belongs to the parallel app-background pass and is deliberately not
touched here.

### Boundaries and evidence rules

- Do not modify the parallel pass's files listed in
  `CONTINUE-kiosk-pos-2026-08-15b.md` §2, especially the customer app's `lib/l10n/`, theme,
  home/catalog paths, `BUILD_PLAN.md`, or the web app's uncommitted `ECOSYSTEM.md`.
- Do not deploy, push, alter production, or stage unrelated work. Explicit paths only if a commit
  is later requested.
- Every new load-bearing behaviour receives a host test first; the test is then made to fail by
  temporarily removing its protected behaviour. A stage result records only commands actually run
  in this continuation pass.
- The Samsung `R58N113RK6J` is the first K3 proof target and iPhone `bocav` remains mandatory
  before K9 can be claimed. Re-run `adb reverse tcp:8801 tcp:8801` after an install.

### K3 — LAN hub transport

1. Add `packages/pos_link/`, a pure-Dart package that depends on `pos_core` only for shared types.
   It owns versioned JSON envelope framing, protocol validation, bounded frame sizes, correlation
   identifiers, pair/session credentials, peer metadata, replay idempotency hand-off, and an
   `EnvelopeTransport` abstraction. No Flutter or platform channels enter this package.
2. Implement `LanHubServer` with `shelf` + `shelf_web_socket`: a health endpoint for device proof,
   a WebSocket endpoint, a snapshot-on-connect flow, and broadcast of hub-applied envelopes. A
   client reconnect always asks the hub for a fresh board, so a killed KDS does not rely on missed
   deltas.
3. Implement `LanSocketTransport` with application-level ping/pong, exponential reconnect backoff,
   request timeouts, duplicate-safe delivery, and `LinkMonitor` event feeding. A socket opening is
   never treated as a healthy link: only a received reply is.
4. Pairing is deliberately narrow: a cryptographically generated six-digit, short-lived code;
   attempt and expiry limits; a distinct KDS device key returned only after successful pairing; and
   authenticated subsequent requests. The code and the key are redacted from diagnostics. Tests
   cover expiry, wrong-code rejection, replay rejection, and key requirement.
5. Discovery is an interface in `pos_link`. A Flutter-side `nsd` adapter may advertise/discover
   where supported, but `ManualHubEndpoint` is always present and tests the same connector path;
   it is not a secondary or degraded implementation.
6. Add a small, non-production KDS harness target that renders the real link state and received
   board count. It will be used to prove loopback processes first and then Samsung-to-Mac traffic
   with the WAN unavailable. The shipping K4/K5 surfaces consume the same controller rather than
   a harness-only protocol.

**K3 host proof:** two independent Dart processes exchange a ticket over loopback in under a
second; a restarted client rebuilds from the hub; a restarted hub reconnects the client without a
manual action. **Device proof:** the Samsung harness reaches the Mac hub on the measured LAN, then
still receives a ticket with WAN unavailable. Logs are captured and inspected.

#### K3 progress — host transport and process proof, 2026-08-15

- Implemented the isolated pure-Dart `packages/pos_link/` package: bounded versioned frames,
  HMAC device credentials, single-use six-digit pairing, manual endpoint validation, discovery
  abstraction, `LanHubServer`, `LanSocketTransport`, snapshot replay, authenticated ping/pong, and
  hub-side idempotent application of KDS cash/transition intents. A KDS cannot emit a sale and no
  KDS message is forwarded directly to Supabase.
- Actual host command: `cd packages/pos_link && dart format lib test tool && dart analyze && dart
  test`; analyzer was clean and all **11** tests passed. The suite covers pairing expiry/limits,
  signed-frame tampering, manual fallback validation, snapshot delivery, duplicate intent safety,
  KDS restart/rebuild, and automatic hub-restart reconnect/rebuild.
- Actual two-process command: `dart run tool/loopback_process_proof.dart`; its independent hub and
  KDS processes exchanged and mirrored a ticket over loopback in **93 ms**. The printed result
  contains ticket receipt/timing only; it never prints the pairing code or device secret.
- Bite proof performed and restored: temporarily changing `LinkFrame.verifies` to always return
  true made `dart test test/pairing_protocol_test.dart --name 'changing a signed payload fails
  verification' --reporter expanded` fail with `Expected: false / Actual: <true>`. The restored
  full package suite passed afterward.
- This is **not a K3 RESULT block**: Flutter mDNS and secure-keystore adapters, the separate
  Android KDS harness, Samsung-to-Mac and no-WAN proof, captured device logs, and final device
  evidence remain required.

#### K3 next subpass plan — Flutter adapters and isolated KDS harness

1. Create `packages/pos_link_flutter/`, distinct from the pure-Dart transport. It will contain an
   asynchronous KDS credential vault over `flutter_secure_storage` and an `nsd` implementation of
   the existing `HubDiscovery` seam. The credential remains outside `pos_core`; only a validated
   `DeviceCredential` is returned to the transport at connection time.
2. Advertise/discover only the dedicated `_timma-pos._tcp` service with non-secret hub/branch
   metadata. Discovery remains best effort: every discovered result is converted into the same
   `HubEndpoint` used by the required manual address field, and pairing is still supervised.
3. Create `packages/kds_harness/` as a separately identified non-production Flutter app so an
   Android install cannot overwrite the customer TIMMA app. It will persist its test identity/local
   SQLite store and paired credential, render actual `LinkState`, board count and manual pairing,
   and contain complete FR/EN strings inside its own package.
4. Give the Android manifest only network/multicast permissions required by the discovery plugin.
   Run host tests/analyze/build before installing; then use the Samsung's measured `192.168.1.90`
   manual endpoint to prove real LAN operation. The plugin choice is deliberately pinned after
   checking its current Android/iOS API and permission requirements, not guessed.

### K3b — cloud feed, device presence, and fail-open checkout warning

1. Add one forward-only migration in the schema-owner repo for the missing `rpc_menu_snapshot` and
   device-role transition RPC. It will use the same device authentication, branch checks,
   `SECURITY DEFINER` hardening, and monotonic status contract as K1; it will not add an overload
   to `rpc_mark_counter_paid`.
2. Add a hub-only Supabase adapter: cursor pull is authoritative, Realtime accelerates it, polling
   remains the floor, and imported rows use the existing monotonic merge guard. The KDS continues
   to communicate only with its hub.
3. Add a 30-second hub heartbeat to `pos_devices.last_seen_at` and consume the existing
   `branch_online` read shape on both customer checkouts. The warning is display-only and fails
   open on an unreadable/malformed presence response.
4. Test cursor duplicates, regressions, returning-flood aggregation, heartbeat cadence, branch
   isolation, and every warning state. Verify the server migration locally before any production
   action.

### K3c — cloud relay

1. Implement `CloudRelayTransport` beside `LanSocketTransport`, behind the same
   `EnvelopeTransport` interface. A route selector retains LAN after a proven round trip and falls
   back only after its stale threshold; it promotes LAN without restart when it returns.
2. Relay envelopes are addressed to the hub. The KDS never receives cloud credentials able to
   write order state; the hub applies the intent locally and remains the sole Supabase writer.
3. Add deterministic fake-relay tests for fallback, recovery, no-double-apply, and badge route
   preference before connecting any real Realtime channel.

### K4 — kiosk surface

1. Create an isolated tablet surface/entrypoint using the shared local engine and link controller;
   it will not alter the customer app's navigation or l10n files. Its UI text is localized within
   the new surface package, with FR and EN complete together.
2. Build attract, browse, composer, cart, cash-at-counter confirmation, printed-slip state, and
   idle-cart reset. Every customer-visible amount uses integer XAF formatting; kiosk orders have no
   account, table, personal data, tender choice, or online-only path.
3. Add golden/widget tests for loading, empty, error, offline, and main sale states; then run the
   four-tap and no-PII walkthrough on both devices.

### K5 — KDS surface

1. Build a second tablet entrypoint over the hub mirror: counter lane first, then the canon's cook
   lanes. Cash payment and every advance create intents for the hub; no KDS code writes Supabase.
2. Port lane/advance fixtures from the web KDS, preserve true elapsed times and source/money
   identity, mirror local 15-minute expiry, and implement the two alarm registers without browser
   autoplay workarounds.
3. Test lanes, SLA clock, duplicate delivery, counter-only cash, offline advance, and reconnect
   summary alerts. Prove an offline Wi-Fi-box advance on a tablet.

### K6 — printer

1. Isolate ESC/POS formatting and queue/retry policy behind a printer interface. The slip carries
   ticket number, items, integer total, cash instruction, order code, and locally-verifiable QR.
2. Test byte layout, retry/backoff, paper/printer error states, and reprint-last before a physical
   printer drill. Record the specific printer capability rather than pretending generic network
   ESC/POS can detect unsupported paper sensors.

### K7 — reconciliation

1. Add a hub-owned drain/reconciliation controller that reports local, acknowledged, unsent and
   quarantined work by named order, with a manager-initiated drain that never reorders lanes.
2. Report cash and mobile-money-at-till separately, preserving `null` tender as pre-v1.16 unknown
   rather than guessing. Test duplicate drain, network retry-forever, server-only quarantine, and
   totals.

### K8 — kiosk hardening

1. Add app-level wake/foreground and launch-recovery handling, then document Android device-owner
   provisioning/screen pinning and iOS Guided Access/ASAM operational steps. Platform security
   features are enabled only where their OS guarantees can be truthfully verified.
2. Test no navigation escape route in the kiosk surface and execute the ten-minute device drill;
   record any OS-level escape that requires MDM rather than claiming an app can suppress it.

### K9 — acceptance evidence

1. Run the full sale, counter, cook, reconnect, and physical-durability loops on Samsung and
   `bocav`, once on no-WAN LAN and once with live WAN.
2. Capture screenshots/logs under `docs/`, pull power only after safely identifying the test device,
   reopen the local store, and compare durable orders/outbox with cloud acknowledgement after
   recovery.
3. Add per-stage RESULT blocks and update memory with actual evidence, unresolved hardware choices,
   and exact resume commands. Do not mark a stage complete on compile-only evidence.

---

## 8. K3 review pass — independent verification, 2026-08-15c

Every claim below was produced by running the command in this session, not by reading the code.
Nothing was committed, pushed, or deployed.

### Re-verified green
| Command | Result |
|---|---|
| `cd packages/pos_core && dart test` | **116 passed** |
| `cd packages/pos_link && dart analyze && dart test` | clean · **16 passed** (11 existing + 5 added below) |
| `cd packages/pos_link_flutter && flutter analyze && flutter test` | clean · **7 passed** |
| `flutter test` (app repo) | **350 passed** — the parallel UI pass is unharmed |
| `dart run tool/loopback_process_proof.dart` | ticket crossed two OS processes in **87 ms**, output redacted |

### ⚠ K3-SEC — the pairing handshake sends the device secret in cleartext
`LanHubServer._handleHandshake` writes `credential.toWire()` — the raw 256-bit secret — into the
`pair_accepted` frame, over `ws://`. **Proven, not theorised:** a probe acting as a passive LAN
listener captured the secret from the wire, connected with it, and delivered a `settle_counter`
envelope the hub accepted, moving a live order to `paymentStatus = paid`. A tablet marking money
received is the one thing §23.2 exists to protect.

Single-use codes, the 5-minute expiry and supervised pairing do not address a listener who is
merely present for those seconds, and the measured AP has **no client isolation**.

**Required order of work:** record the decision in `ECOSYSTEM.md` §23 first (§0.8), then implement.
Recommended shape: X25519 ECDH establishes the channel key and the six-digit code authenticates the
transcript, so a passive attacker learns nothing even though six digits is low entropy. A
`ws://`-only mitigation (wrapping the secret under a key derived from the code) still falls to a
10⁶ offline search of a captured transcript and must not be treated as sufficient.

### Boundaries confirmed intact, and now defended by tests
Probed live against a running hub with a *validly paired* credential — so these are the hub
refusing an authenticated peer, not authentication doing the work:

- a KDS ringing a sale → `forbidden_envelope`
- a KDS borrowing another `device_id` → `forbidden_envelope`
- a counter settlement tendered as `mobile_money` → `forbidden_envelope`
- an envelope whose payload `client_id` disowns its subject → `forbidden_envelope`
- a KDS expiry request against a fresh ticket → applied, ticket untouched
- a second tablet replaying the pairing code → `pairing_unavailable`

None of the first five had a test. Added `packages/pos_link/test/hub_authority_test.dart` (5 tests)
and **proved every one bites**: reverting the `place_order` throw, the `deviceId` comparison, the
`tender != cash` check and the payload/subject check each produced the matching failure. The server
file was restored byte-identical (`git diff --quiet` clean) and the package re-run at 16 green.

### Defects to fix before K3 gets its RESULT block
1. **K3-SEC** — **FIXED 2026-08-15** (plan §9 + RESULT below). Blocks the RESULT block.
2. **`packages/kds_harness/`** — untouched `flutter create` counter template; **deleted 2026-08-15**
   (owner-approved; no pubspec/CI references existed). A real KDS device-harness is deferred to the
   K5/K9 device-proof stage.
3. **`BUILD_PLAN.md`** — had been edited against the do-not-touch list, its new K section marking
   **K1 and K2 unchecked when both are DONE** and calling `pos_core` a *"drift SQLite store"* when it
   is raw `package:sqlite3`; **restored from HEAD 2026-08-15** (owner-approved), the K ledger remains
   in this doc and `docs/CONTINUE-kiosk-pos-2026-08-15b.md`.
4. **Multi-KDS badge:** `LanHubServer._removePeer` called `recordDown()` on any authenticated peer's
   departure. **FIXED 2026-08-15** (§9): now only when `connectedPeerCount == 0` after removal; biting
   badge test recorded in §9.
5. **Injectable `Random`:** **FIXED 2026-08-15** (§9): `requireSecureOrTestRandom` guard on
   `LanHubServer` and `PairingRegistry`; throwing `Random`-guard test recorded in §9.

## 9. K3-SEC — closing the cleartext-secret hole (plan, 2026-08-15, before any code)

**Decision first:** recorded in `timmaeat-webapp/ECOSYSTEM.md` §23.9, version header bumped to 1.18.
§0.8 order satisfied — canon precedes implementation. This section is the app-repo plan.

**Goal.** Pairing no longer puts key material on the wire. A passive capture of the handshake yields
nothing (public keys, a MAC, a proof), and the six-digit code cannot be brute-forced offline because
nothing on the wire is checkable under a guessed code alone. The device secret is *derived*,
never transmitted. Also closes review items 4 and 5 (multi-KDS badge, injectable `Random`).

**Files to touch (all in `packages/pos_link/`).**
- `pubspec.yaml` — add `cryptography` (pinned; justification below).
- `lib/src/pairing_protocol.dart` *(new)* — X25519/HKDF/HMAC. Public surface:
  - `PairingSecret derivePairingSecret(...)` + a `PairProof` (keyId, value) pair of helpers, with
    the transcript canonicalised as `(protocolVersion, challenge, pair, pairAccepted)` JSON bytes.
  - Info strings and salt roles as named constants (`PairingContext`), no magic strings.
- `lib/src/pairing.dart` — `PairingRegistry` reworks: `begin()` keeps an ephemeral X25519 secret,
  `claim()` returns a derived credential instead of a minted one; code stays 6 digits/5 min/5 attempts.
  Constructor gains the `Random` guard (review item 5): production default `Random.secure()`, and an
  injectable non-`TestRandom` `Random` is rejected (throw).
- `lib/src/lan_hub_server.dart` — `challenge` frame carries hub ephemeral public key; `pair_accepted`
  no longer contains `credential.toWire()` — only `device_id`, `issued_at`, hub metadata and a MAC
  under `authKey`. `_removePeer` badge fix (review item 4): `recordDown()` only when
  `connectedPeerCount == 0` after removal.
- `lib/src/lan_socket_transport.dart` — `LanPairingClient.pair` performs its own ephemeral X25519,
  verifies the hub MAC, derives the same `credentialSecret`.
- `lib/src/protocol.dart` — `LinkProtocol.version` 1 → 2; frame fields above. Version mismatch is an
  explicit handshake rejection (v1 device cannot pair v2 hub and vice-versa).
- `tool/loopback_hub.dart` + `tool/loopback_client.dart` — compile against the new surface (no wire
  change in behaviour otherwise).

**Dependency justification (required by rule before adding).** The handshake needs X25519 + HKDF +
HMAC. `package:crypto` (already present, `^3.0.7`) has HMAC/HKDF but **no X25519**. `cryptography`
is the smallest well-audited pure-Dart option with a Dart-only X25519 implementation (`X25519.new`)
that runs identically in the Dart VM, on Android and on iOS without a native dependency; its package
count is 1. No platform channel, no build-time native code, constant-time implementations. Pin
exactly (no caret) to the resolved version after `dart pub add` and record the pinned version in the
RESULT block.

**Test plan (new `test/k3_sec_pairing_test.dart`), each must be shown to bite before restore:**
1. **Wire-capture oracle test.** Wrap the socket layer so every byte frame leaves the hub is
   recorded (a `HubFrameSink`/capture harness). Pair end-to-end with `TestRandom` on both sides, then
   assert the raw 32-byte secret **appears nowhere** in the captured transcript — not as bytes, not
   base64, not hex. *Bite:* restore the old `credential.toWire()` write in `pair_accepted` → the
   assertion must fail with the captured occurrence printed.
2. **Transcript-only attacker test.** A client that captures the hub's `challenge` (public key only)
   and tries to authenticate as a KDS without ever doing the DH, or that guesses codes against the
   captured transcript, must be rejected with `incorrect_code`/`pairing_unavailable` — and its MAC
   must not match under any guessed code. *Bite:* make the attacker accept a random code's MAC →
   the test must fail.
3. **Badge test (review item 4).** Two KDS peers authenticated; one disconnects → `linkState`
   health stays `linked`; second disconnects → `offline`. *Bite:* revert the `_removePeer` guard →
   first disconnect must redden the badge and the test must fail.
4. **Random guard test (review item 5).** Injecting `Random(42)` (non-`TestRandom`) into
   `PairingRegistry`/`LanHubServer` throws.

**Proof-of-bite protocol:** write the test → watch it fail for the *right* reason → fix → restore the
buggy line with the test still failing → capture the failure text → revert → `git diff --quiet`
clean on the touched file → full `pos_link` suite green + `dart analyze` clean.

**How to resume:** all five review items (ECOSYSTEM §23.9 decision + this plan) are on disk. The
build is green at 16 `pos_link` tests today; after this stage it must be green at 21+ with the two
biting proofs recorded. Do not touch `BUILD_PLAN.md`, `lib/core/theme/*`, `lib/l10n/*`, the app's
own test files, or the webapp's uncommitted ECOSYSTEM v1.17 delta.

> ## K3-SEC RESULT — **DONE on the host, 2026-08-15. `dart analyze` clean; `pos_link` green at 21 tests.**
>
> **Dependency pinned:** `cryptography: 2.9.0` (exact, no caret) added to `packages/pos_link/pubspec.yaml`.
> It is the only new package. `package:crypto` provides HMAC/SHA-256 for the transcript MACs; `cryptography`
> provides X25519 + HKDF, pure Dart, VM/Android/iOS identical.
>
> **Implemented:** `lib/src/pairing_protocol.dart` (new — X25519 keypairs, `deriveDh`, `derivePairingSecrets`
> with HKDF `pair-auth`/`device-credential` info strings and the code as HKDF salt, `pairingProof`,
> `pairingCoreWire`, `pairingTranscript`), `lib/src/test_random.dart` (new — `TestRandom` +
> `requireSecureOrTestRandom`), `pairing.dart` (`begin()` mints an ephemeral X25519 keypair, `claim()`
> derives the credential and verifies the KDS proof; `ephemeralPublicKey` getter), `lan_hub_server.dart`
> (challenge carries hub `eph_pub` while a pairing is pending; `pair_accepted` carries only `device_id`,
> `issued_at`, hub metadata and the hub's proof — **no secret**; `_removePeer` badge guard), `lan_socket_transport.dart`
> (`LanPairingClient.pair` does its own X25519, verifies the hub proof, derives `DeviceCredential.fromSecret`),
> `protocol.dart` (`LinkProtocol.version` 1 → 2), `credentials.dart` (`DeviceCredential.fromSecret`; `toWire`/
> `fromWire` deleted as dead), `tool/loopback_hub.dart` (awaits `beginPairing`). `pos_link` was fully
> untracked in git throughout, so the proof-of-bite restores were verified by source reads + the running suite,
> and the `_removePeer` guard / hub-proof byte-diffs were confirmed restored.
>
> **Test plan (all 4 in `test/k3_sec_pairing_test.dart`, plus the migrated unit + integration suites):**
> 1. **Wire-capture oracle** — `_RawKds` records every verbatim frame of a real end-to-end pairing; asserts the
>    32-byte derived secret appears nowhere (raw base64url, standard base64, hex). **Bite (restoring
>    `credential.toWire()`-style write into `pair_accepted` data):**
>    ```
>    Expected: false
>      Actual: <true>
>    the shared secret must never be serialized onto the wire
>    ```
> 2. **Transcript-only attacker** — an attacker with only the captured transcript cannot reopen a captured
>    pairing; the transcript must contain no replayable `secret`, and a fresh `authenticate` gets
>    `unauthenticated`. **Bite (same secret-on-wire restore):**
>    ```
>    Expected: null
>      Actual: 'Jvv-PQ_CVQqPCdAeguaqE7V97fMDDqDHQSQunn2qhCA'
>    the transcript must not contain anything to replay
>    ```
> 3. **Badge** — two raw KDS peers authenticated; one disconnects → `linked`, last disconnects → `offline`
>    (deterministic: pings are driven manually, no auto-pong). **Bite (reverting the `_removePeer` guard to
>    unconditional `recordDown`):**
>    ```
>    Expected: LinkHealth:<LinkHealth.linked>
>      Actual: LinkHealth:<LinkHealth.offline>
>    one KDS disconnecting is not a link outage
>    ```
> 4. **Random guard** — `Random(1)` into `PairingRegistry`/`LanHubServer` throws `ArgumentError`. Passed.
>
> **Regression:** `dart run tool/loopback_process_proof.dart` — `{"event":"ticket_received","ticket_id":"…","elapsed_ms":104,"link":"lan"}`.
>
> **Remaining:** JOB 1 (review items 2–3): replace `packages/kds_harness/` and restore/correct the app
> `BUILD_PLAN.md` K ledger; then physical-device smoke.

### K3-SEC follow-up — the six-digit code must never cross the wire (plan, 2026-08-15, before any code)

**Gap found during the K3b-D pass, distinct from §9.** §9 removed the *derived secret* from
`pair_accepted`, but the six-digit code still travels in cleartext inside the `pair` frame
(`lan_socket_transport.dart:87,109`), and the hub derives its pairing secrets from that **wire value**
(`lan_hub_server.dart:217` passes `frame.data['code']` into `claim`). §9's attack model covered a
*passive* listener only. An **active** LAN MITM defeats the handshake as written:

1. It inserts its own X25519 keypair between the KDS and the hub.
2. It captures the KDS's `pair` frame, which still contains the code in cleartext.
3. Because it knows *both* Diffie-Hellman values (KDS↔MITM, MITM↔hub) **and** the code (HKDF salt),
   it can compute both `authKey`s, forge both sides' transcript MACs, and derive the KDS's
   `credentialSecret`. It can then mint/impersonate the credential — the exact attack §23.9/§9 exist
   to stop (a forged credential could sign a `settle_counter`).

The code is operator-supervised (read off the hub screen, typed on the KDS) and must exist only in
the two endpoints. It is never needed on the wire: both sides already fold their *own* copy into the
HKDF salt, and the transcript MACs prove shared knowledge without exposing it.

**Fix (small, surgical):**
- `lib/src/lan_socket_transport.dart` — delete `'code': code` from the transcript `pairFrame` and
  from the sent `pair` frame. The KDS keeps using its local `code` only in `derivePairingSecrets`.
- `lib/src/lan_hub_server.dart` — stop reading `frame.data['code']`; `claim()` no longer takes a code.
- `lib/src/pairing.dart` — `PairingRegistry.claim` derives from `pending.code` (the hub's own on-screen
  code); drop the `code` parameter entirely.
- `test/pairing_protocol_test.dart`, `test/k3_sec_pairing_test.dart` — mirror the wire shape (no code
  field) and add two biting tests (below).

**Proof-of-bite (both new tests written FIRST, against today's code):**
1. **MITM-with-code test** — a raw peer that does its own X25519 keypair, captures the KDS's wire
   transcript (which today contains the code), substitutes its own ephemeral key into a fresh `pair`
   frame and forges both proofs, must be **rejected**. Today the hub accepts it (claim succeeds) →
   test must FAIL with the acceptance shown. After the fix → green.
2. **Code-never-on-wire test** — after a successful end-to-end pairing, the six-digit code must appear
   in none of the captured frames. Today it appears in `pair` → test must FAIL printing the frame.
   After the fix → green.

**Verify:** `dart analyze` clean; full `pos_link` suite green; `dart run tool/loopback_process_proof.dart`
still crosses; `pos_link_flutter` analyze green (vault compiles). Record bite + pass outputs.

**How to resume:** this plan is the whole job — two edits in transport/hub, one in the registry, two
test files, bite-proven, then docs (this RESULT + CONTINUE `c`) and a `pos_link` commit (the package
is still fully untracked; commit the fix with explicit paths).

> ## K3-SEC follow-up RESULT — **DONE 2026-08-15. `dart analyze` clean; `pos_link` 24/24; loopback proof 106 ms.**
>
> **Bite captured BEFORE the fix, via a throwaway probe against the live code:**
> ```
> BITE CONFIRMED: claimed with guessed code "000000" while the on-screen code was "219420"
> — credential minted for kds-cuisine
> ```
> Today the hub derives its pairing keys from the caller-supplied (wire) code and never compares it
> to the on-screen code, so a peer with a valid X25519 agreement and *any* six digits minted a
> credential. An active LAN MITM needs no capture at all — any guess works. Probe deleted after the
> record.
>
> **Implemented (all in `packages/pos_link/`):**
> - `lib/src/pairing.dart` — `PairingRegistry.claim` no longer takes a `code` argument; it derives
>   from `_PendingPairing.code`, the hub's own on-screen value. Doc comment updated: the code must
>   not exist on the wire.
> - `lib/src/lan_hub_server.dart` — dropped `frame.data['code']`; `claim()` derives from `pending.code`.
> - `lib/src/lan_socket_transport.dart` — the KDS no longer writes `'code'` into the transcript
>   `pairFrame` or the sent `pair` frame; it keeps the code only for its local HKDF derivation.
> - Tests: `pairing_protocol_test.dart` (helpers mirror the code-free wire shape; new
>   **guessed-code** test — a real DH + MAC under `'000000'` must throw `incorrectCode` and mint
>   nothing; malformed-key test still needs a pending pairing so it keeps `begin()`); new
>   `k3_sec_pairing_test.dart` tests — **six-digit code never appears in any captured frame** and a
>   **socket-level guessed-code attacker** is rejected with `incorrectCode`; `_RawKds` wire shape
>   updated. Both new tests fail against the pre-fix code (code present / guess accepted) and pass
>   after.
>
> **Verification:** `dart analyze` clean · `dart test` **24/24** · `dart run tool/loopback_process_proof.dart`
> crossed a ticket in **106 ms** · `pos_link_flutter` analyze clean + **6/6** (vault untouched).
>
> **Wire shape note:** the `pair` frame is now `device_id`/`label`/`role`/`eph_pub`/`proof` — no code
> field. The code lives only in the hub's `_PendingPairing` and the KDS operator's hands.

### K3 (finish) — Flutter adapter tests for the mDNS seam (plan + RESULT, 2026-08-15)

The K3 transport work already shipped `NsdHubDiscovery` + `NsdHubServiceCodec` +
`HubEndpoint.parseManual` (manual-IP fallback) + heartbeat/reconnect + the §1.7 badge — but the
Flutter-side adapters had **no tests** (`pos_link_flutter` held only the vault suite). The manual
fallback was already covered in `pos_link`; the mDNS codec contract and discovery lifecycle were not.

**Plan (test-only, no production code changes):** new `test/nsd_hub_discovery_test.dart` with an
injected-fake nsd (no platform channel):
1. Codec round-trip through a "resolved" service; addresses fallback when `host` is null.
2. Codec rejections: foreign service type, version mismatch, empty hub/branch, bad port, no
   host/addresses.
3. `discover()` emits pre-existing services; found/lost stream; foreign services never decode;
   a lost service stops being advertised.
4. `advertise()` replaces (not stacks) a registration; `close()` unregisters + stops and is
   idempotent.

> **RESULT — DONE 2026-08-15. `flutter analyze` clean; `pos_link_flutter` 9/9 (2 vault + 7 nsd).**
> All 7 tests in the new file pass; the two flaky-shaped assertions (pause/lost, take(0)) were
> rewritten deterministically (`StreamSubscription.pause()` is void; `take(0)` never starts the
> generator). Sibling suites re-verified: `pos_core` 116/116, `pos_link` 24/24. The remaining K3
> (finish) items are the real KDS surface (deferred to K5/K9 per owner approval of the
> `kds_harness` deletion) and the device proof (Samsung ↔ Mac over the LAN, then WAN pulled —
> blocked on the second session holding the Samsung).

---

## 10. Stabilization pass — 2026-08-15, full build/test/device loop (before any code)

Owner directive: **a full stabilization pass** — re-read the project rules and current docs/memory,
then build/test, run on the plugged Samsung through adb, watch logs for crashes/blockers, fix, and
repeat until the build/tests/device smoke are clean. Be careful not to damage anything working.
This section is written before any code edit (§0.6).

### Goal
Every package in the app repo builds clean and its suites are green; the shipping app runs on the
Samsung with no crash/blocker in logcat. Fix only what this pass owns; leave the parallel session's
in-flight files alone (CONTINUE §2).

### Baselines established this pass (each command re-run, not remembered)
- `packages/pos_core` — `dart analyze` clean, **116/116**.
- `packages/pos_link` — `dart analyze` clean, **21/21** (K3-SEC suite green).
- `packages/pos_link_flutter` — **BROKEN**: a regression from K3-SEC §9. `DeviceCredential.toWire`/
  `fromWire` were deleted as dead, but the vault (`kds_credential_vault.dart`) and its test still
  call them. `flutter analyze` reports 2 `undefined_method` errors. This is the one known defect.
- App repo — `flutter test` baseline 350/350; `flutter analyze` 5 infos, all in the parallel
  session's `home_screen.dart` / `handwritten_greeting.dart` (do-not-touch).
- `dart run tool/loopback_process_proof.dart` — rerun.

### Plan (small stages; suite green after each)
1. **Fix the vault regression** in `packages/pos_link_flutter/`:
   - Do **not** re-add `toWire`/`fromWire` to `DeviceCredential` — that is exactly what §9 removed
     to keep the secret off any serialization path. Instead move the persistence format into the
     vault as private helpers: JSON `{device_id, secret, issued_at}`; decode rebuilds via the public
     const constructor, `DateTime.parse(...).toUtc()`, and keeps the malformed/identity guards.
   - Re-run `flutter analyze` + `flutter test` in pos_link_flutter (expect the existing 7 green).
2. **Re-verify transports**: pos_core 116, pos_link 21, loopback regression.
3. **App-level pass**: `flutter analyze` (accept the 5 known infos; do not touch those files),
   `flutter test` (expect 350).
4. **Samsung device smoke** (`R58N113RK6J`, wireless adb serial
   `adb-R58N113RK6J-pXlm4k._adb-tls-connect._tcp`, Android 12):
   - Re-run `adb reverse tcp:8801 tcp:8801` after any install (trap 26).
   - Build a debug APK with the **real** dart-defines (`--dart-define=APP_ENV=dev
     --dart-define=SUPABASE_URL=… --dart-define=SUPABASE_ANON_KEY=…` from the owner's root
     `Supabase.txt`, never echoed) — a plain debug APK silently ships the mock login app.
   - Install/launch, then `adb logcat` watch for `AndroidRuntime`/`FATAL EXCEPTION`/`flutter`
     errors; verify the app reaches the home screen without a crash.
   - This pass does not build the KDS harness (deferred to K5/K9); the smoke is the shipping app.
5. **Fix-and-repeat loop**: every defect found gets its own small stage, re-running the affected
   suites, until build/tests/device smoke are clean.
6. **Sync at the end**: this §10 RESULT block, CONTINUE §9 State paragraph, memory file.

### Guards
- Never `git add -A`; no commit unless the owner asks. Do not touch the CONTINUE §2 file list, the
  webapp's uncommitted `ECOSYSTEM.md`, or `BUILD_PLAN.md`. No deploy, no push.
- Fixes land only in files this pass owns; non-trivial test changes are bite-proven where
  applicable (CONTINUE §2).

> ## §10 RESULT — **STABILIZATION PASS DONE on host + Samsung, 2026-08-15.**
>
> One defect found and fixed, one stale lockfile fixed; everything else was already clean and is
> re-verified green below. No commit, no push, no deploy; parallel-session files untouched.
>
> **Defect fixed — `packages/pos_link_flutter` vault regression (caused by §9).** K3-SEC §9 deleted
> `DeviceCredential.toWire/fromWire` as dead, but the secure vault (`kds_credential_vault.dart`) and
> its test still called them → `flutter analyze` 2× `undefined_method`, tests would not compile.
> Fixed without reintroducing serialization on `DeviceCredential`: the keystore-only encoding now
> lives privately inside the vault (JSON `{device_id, secret, issued_at}`, rebuilt via the public
> const constructor, `DateTime.parse(...).toUtc()`, identity/malformed guards retained). The secret
> still has no serialization path on the credential itself.
> **Stale lockfile fixed:** `pos_link_flutter/pubspec.lock` predated the §9 `cryptography: 2.9.0`
> pin; `flutter pub get` refreshed it (cryptography now resolved as transitive, exact 2.9.0).
>
> **Re-verified green this pass (every command run, not remembered):**
> | Suite | Command | Result |
> |---|---|---|
> | pos_core | `dart analyze` + `dart test` | clean · **116/116** |
> | pos_link | `dart analyze` + `dart test` | clean · **21/21** |
> | pos_link_flutter | `flutter analyze` + `flutter test` | clean · **6/6** (was broken) |
> | app repo | `flutter test` | **350/350** |
> | app repo | `flutter analyze` | only the 5 known infos in the parallel session's `home_screen.dart`/`handwritten_greeting.dart` — left untouched |
> | loopback | `dart run tool/loopback_process_proof.dart` | `elapsed_ms: 113`, `link: lan` |
>
> **Samsung device smoke — clean** (`R58N113RK6J` SM-G975F, Android 12, wireless adb):
> debug APK built with real dart-defines via `scripts/run-device.sh apk` (never a mock build),
> `adb install -r` (then `adb reverse tcp:8801 tcp:8801` — trap 26), launched, logcat watched.
> Evidence: `Displayed …MainActivity: +7s3ms` (debug cold start), window focused, Supabase init
> completed, Dart VM service healthy, `debugDumpApp` shows `HomeScreen`+`Scaffold` built with
> **no** mock `Banner` (real catalog), and **zero** `FATAL EXCEPTION`/`E/flutter`/ANR markers. First
> frame took 7 s in debug over wireless adb — cold-start jank is a debug-build artifact; the §12
> budget is enforced at release, not here.
>
> **Remaining:** no blockers. The K3 Flutter adapters now compile and are green; the Samsung-proof
> of the *transport* (hub on the Mac ↔ KDS harness APK on the Samsung) still awaits a real KDS
> surface, which K5/K9 build by plan.

---

## 11. K3b — inbound cloud feed, device presence, fail-open checkout warning (plan, 2026-08-15, before any code)

**Context.** K3's remaining Samsung-transport proof is gated on a real KDS surface (a K5/K9
deliverable), so the next stage in order is **K3b**. The K1 migration already ships the presence
half (§23.7): `pos_devices`, `rpc_device_heartbeat` (returns `now()`, touches `last_seen_at`) and
the `branch_online` view (kiosk-role device, 3-minute window, fail-open `online = NULL`). Two K1
gaps remain and are owed "at K3b in one migration" (CONTINUE traps 9–10):
- **`rpc_menu_snapshot` does not exist** (the K1 brief listed it).
- **No device-role transition RPC**: `rpc_transition_order` is service_role-only, so a `kds`
  device key cannot advance a ticket.

**Goal (whole stage).** The hub can pull every branch order (cursor over a device-key RPC, monotonic
merge — polling is the only mechanism: Realtime cannot reach anon under orders RLS, see the K3b-B
correction below), pin the menu bundle from the server, heartbeat presence every 30 s, and both
customer checkouts warn-but-allow when the branch goes dark — failing open on any
unreadable/malformed presence response.

**Sub-stages, each planned to disk before its code:**
- **K3b-A (this pass) — schema + contract:** ECOSYSTEM §23.10 (canon-first, §0.8) + one
  forward-only migration `20260815170000_kiosk_cloud_feed.sql`. Verified inside a **rolled-back**
  transaction on the pooler (port 6543, the workspace-proven pattern) and **NOT applied to
  production**.
- **K3b-B (DONE, 2026-08-15) — hub cloud adapter:** the new `packages/pos_cloud/` Flutter package
  (`SnapshotSource` over `rpc_menu_snapshot` — the Supabase implementation lives where
  `supabase_flutter` lives, i.e. the app repo, never inside the platform-free `pos_core`); order
  feed cursor pull through a device-key `rpc_order_feed` `(updated_at, id)` merged with the existing
  monotonic guard. **Correction (2026-08-15, while designing K3b-B): Realtime cannot accelerate this
  feed.** `orders`/`order_items`/`payments` have owner-read RLS policies only, so an anon-key hub
  receives zero branch rows on any realtime channel — the feed must be a security-definer RPC keyed
  by the kiosk device key, polled. Migration **applied to production with owner approval** + live
  proof (see K3b-B RESULT below).
- **K3b-C (DONE, folded into K3b-B) — heartbeat client:** 30 s `rpc_device_heartbeat` loop is
  `PosHeartbeat` inside `PosCloudSync`; presence proven live on production.
- **K3b-D — checkout warnings (app + web):** consume `branch_online`; warn-but-allow; fails open
  (unknown = no warning).

### K3b-A contracts

**`rpc_menu_snapshot(p_device_key text, p_version bigint default null) returns jsonb`**
- Resolves a `kiosk`-role device via `fn_resolve_pos_device` — the hub IS the kiosk device, so its
  branch is server-truth; no anon JWT can name another branch.
- Builds the §23.8 bundle over the published catalog for that branch:
  - products: `published` rows (photo_url = first of `images`, sort_index = `sort`, `available` =
    absent `branch_product_availability` row (in stock) or its `in_stock`).
  - variants: `product_variants` by `sort`.
  - option_groups: `product_modifier_groups` → `modifier_groups` → active `modifier_options` by
    `sort`; option `available` = absent `branch_option_availability` row or its `in_stock`.
  - Combo steps are deliberately **not** emitted: the K2 client model (`SnapshotProduct`) carries no
    combo-step data, so the server emits only what the client consumes (§0.1 — the client defines
    the contract).
- `version` = `extract(epoch from max(updated_at))` across all feeding rows for the branch
  (bigint, monotonic, comparable). If it equals `p_version`, the client skips re-pin.
- `checksum` = `encode(digest(fn_canonical_json(payload), 'sha256'), 'hex')` over exactly
  `{version, branch_id, product_count, products}` — **byte-identical to `pos_core`'s
  `canonicalJson`** (keys sorted lexicographically at every level, no whitespace, RFC 8259
  escaping). `MenuSnapshot.validate()` recomputes the checksum client-side; equal bytes are what
  makes "truncated download is detectable" true (§23.8).

**`fn_canonical_json(jsonb) returns text`** — private port of `canonicalJson`; keys sorted
lexicographically (all our keys are ASCII, so text ORDER BY matches Dart's code-unit sort). No
grant to anon/authenticated.

**`fn_transition_order(p_order_id, p_to, p_reason, p_branch_id)`** — the monotonic matrix extracted
verbatim from `rpc_transition_order` plus the K1 branch guard (a supplied branch must own the
order, mirroring `fn_settle_counter_order`).

**`rpc_transition_order(uuid, text, text)`** — refactored to delegate to `fn_transition_order(
..., null)`. Signature unchanged, no overload added, behaviour identical.

**`rpc_device_transition_order(p_device_key, p_order_id, p_to, p_reason)`** — resolves a `kds`-role
device, delegates with the device's branch. A kitchen tablet can only advance its own branch's
tickets.

**Grants.** `rpc_menu_snapshot` + `rpc_device_transition_order` → anon, authenticated (device key
is the credential, §23). `fn_canonical_json`, `fn_transition_order` → none (internal).
`rpc_transition_order` stays closed. Index with the feed query (§4 rule):
`orders_branch_updated_at_idx on orders (branch_id, updated_at)`.

### K3b-A verification (this pass)
1. Read-only K1 presence check — **done**: pooler 6543 works; `fn_resolve_pos_device`,
   `rpc_device_heartbeat`, `rpc_place_kiosk_order`, `rpc_transition_order` all present.
2. Apply the migration inside ONE explicit transaction on the pooler → all objects build → then
   ROLLBACK (nothing persists).
3. **Canonical byte-match proof:** the same synthetic payload serialized by `fn_canonical_json`
   (SQL) and `canonicalJson` (Dart) must be byte-identical; then a live branch's
   `rpc_menu_snapshot` bundle must pass `MenuSnapshot.fromJson` + `validate()` in Dart.
4. **Do NOT apply to production; no deploy, no commit.**

### Guards
- Never `git add -A`; no commit/push/deploy. Preserve ECOSYSTEM's v1.17 (parallel session) and
  v1.18 (§23.9) deltas — append §23.10 + a v1.19 delta line only. Do not touch the CONTINUE §2
  file list. Migration is forward-only and idempotent-safe (`create or replace`, `if not exists`).

### K3b-A RESULT (2026-08-15, this session)

**Written:** ECOSYSTEM §23.10 + v1.19 delta (append-only, above §23.9), and
`supabase/migrations/20260815170000_kiosk_cloud_feed.sql` (updated_at on the four feeding child
tables + their triggers, `orders (branch_id, updated_at)` and `pos_devices (branch_id)` indexes,
`fn_canonical_json`, `rpc_menu_snapshot`, `fn_transition_order`, `rpc_transition_order` delegate,
`rpc_device_transition_order`, grants). **Plan-to-disk order held: §11 above was written before any
code.**

**Verified in one rolled-back transaction on the pooler (6543), nothing persisted:**
- Migration applies cleanly: all ALTER/CREATE/REVOKE/GRANT succeed inside the transaction.
- `fn_canonical_json` output on a control-char fixture
  `{"a":[true,null,{"b":2,"y":"x"}],"c":"héllo\n\t\"wörld\"","z":1}` **byte-matched** Dart's
  `canonicalJson` of the same logical value (direct string equality, `match=true`).
- `rpc_menu_snapshot` built a real 9-product bundle from a live branch (version=1786797849); the
  server checksum re-validated in Dart — `MenuSnapshot.fromJson` + `validate()` passed with
  products=9 declared=9, checksum `79ea2fed…` recomputed identically client-side. This proves the
  server's canonical bytes and the client's canonical bytes are equal on live data with null
  photo_url, non-ASCII names, variants, and per-branch availability.
- `rpc_device_transition_order` (kds role) resolved the device and reached the matrix —
  `order_not_found` on a bogus id; `rpc_transition_order` still works as the dashboard door
  (`order_not_found`). Both fail correctly; the matrix and reason/refund logic are verbatim from the
  original RPC.
- Grants: anon EXECUTE = `f f f t` (fn_transition_order, rpc_transition_order, fn_canonical_json
  revoked; rpc_menu_snapshot granted).
- **Production left byte-identical:** after ROLLBACK, counts of the new routines, columns, indexes
  and triggers are all 0.
- pos_core still 116/116 green (no code touched; verification scripts deleted after the proof).

**Not done / next:** the migration is **not applied** to production (deploys only on owner approval,
with the rest of K3). Remaining: K3b-B hub cloud adapter (SnapshotSource over `rpc_menu_snapshot` in
the app repo — never `pos_core`; device-key cursor feed + monotonic merge; no realtime — see the
correction above), K3b-C heartbeat client, K3b-D checkout warnings. Each gets a plan subsection
before its code.

### K3b-B plan (hub cloud adapter, 2026-08-15, before any code)

**Goal.** The hub (kiosk-role device) can: pin the menu bundle from the server
(`rpc_menu_snapshot`), pull every branch order the kitchen must see — including app/CamPay orders
minted server-side with `client_id = NULL` — and drain the outbox's cloud envelopes into the
device RPCs, with per-order monotonic merge on the way in and `onServerFields` acknowledgement on
the way out.

**Why an RPC, not postgrest/realtime.** `orders`, `order_items`, `payments` enable RLS with
owner-read policies only (20260710200600). An anon-key hub gets nothing from `.from('orders')`
reads or realtime channels. The feed is therefore a security-definer RPC keyed by the kiosk device
key — the same credential model as `rpc_menu_snapshot` (§23.10).

**`rpc_order_feed(p_device_key text, p_since timestamptz, p_after_id uuid, p_limit integer default 200)
returns jsonb`** — added to the SAME migration `20260815170000_kiosk_cloud_feed.sql` (unapplied,
still the right window).
- Resolves a `kiosk`-role device via `fn_resolve_pos_device`; branch = the device's branch.
- One page over `orders` ordered by `(updated_at, id)` strictly greater than `(p_since, p_after_id)`
  (`p_after_id` = the id of the last row of the previous page, null on the first page). Page keys
  never collide on a timestamp, so no row is skipped at a page boundary and no row repeats.
- `p_limit` default 200, clamp 1..1000; `p_since` null → `since_required`.
- Returns `{branch_id, orders: [...], next_since, next_after_id}`; `next_since`/`next_after_id` are
  the cursor of the last returned row (null id when the page is empty). The client advances its
  committed cursor **after** merging a page — a crash re-delivers the page and `mergeRemoteOrder`
  is monotonic, so replay is safe.
- Order payload: `order_id, order_code, daily_code, client_id, source, mode, status,
  payment_status, payment_method, tender, subtotal, discount, delivery_fee, total, menu_version,
  note, placed_at_device, created_at, updated_at` + `items[]` of the raw `order_items` snapshots
  (`product_id, name{fr,en}, variant{id,name,price_delta}|null, modifiers[{id,name,qty,price_delta}],
  combo, unit_price, quantity, line_total`) — verbatim JSONB, mapped in Dart.
- Grant to anon + authenticated (device key is the credential); covered by `orders
  (branch_id, updated_at)` already shipped in K3b-A.

**Dart mapping (app repo — the adapter lives where `supabase_flutter` lives; `pos_core` untouched).**
- Local key for a server row: `orders.client_id` when present, else deterministic
  `'server:<order_id>'`. Remote rows are `origin: remote`, so the outbox never replays them.
- `branch_id` from the feed response (never hardcoded); `deviceSeq: 0`, `ticketNumber: null`
  (the board shows `daily_code` for server-minted tickets); `placedAtDevice = placed_at_device ??
  created_at`; `statusChangedAt = updated_at` (the merge guard preserves local age on re-delivery,
  §23.5); `menuVersion`, `tender`, `note`, `serverOrderId/orderCode/dailyCode` pass through.
- Lines: `name->fr/en`, `variant->id/name->fr/en`, `modifiers[]->{id,name->fr/en,price_delta,qty}`,
  `lineTotal = unit_price × quantity`; combo is deliberately dropped (no client field, §23.8).
- Feed cursor `{since, after_id}` persisted in the store's meta (`readMeta`/`writeMeta`, key
  `feed_cursor`) — local, offline-first, advances after each merged page.
- Poll cadence 5 s (matches the "under 5 s" proof; branch-scale pages are tiny). Re-pin of the
  menu bundle rides the same tick when `version != pinned`.

**Sink mapping (outbox → cloud, `EnvelopeSink` on the hub).** The sink holds the store, so it
resolves `subject` (client_id) → `serverOrderId`; the drain's per-subject ordering guarantees the
`place_order` envelope landed first, so the server id exists by the time settle/transition run.
- `place_order` → `rpc_place_kiosk_order` (payload carries `items`, `menu_version`, `device_seq`,
  `placed_at_device`, `note`); serverFields `{order_id, order_code, daily_code}` → delivered.
  `PostgrestException` → retryable (never quarantine on transport errors).
- `settle_counter` → `rpc_device_mark_counter_paid` (`p_order_id`); resolve `serverOrderId`, null →
  retryable.
- `transition` → `rpc_device_transition_order` (`p_order_id, p_to`; reason null — the device has no
  reason field).
- `expire` → delivered, no RPC: the server cron expires `pending_payment` by `created_at`, so the
  local 15-minute expiry is a mirror only and has nothing to replay upstream.
- Non-`cloud` destinations never reach this sink (assert).

**Tests (deterministic, fake gateway + `SqlitePosStore.inMemory()`).** Sink: each kind maps to the
right RPC + params + outcome (incl. not-acknowledged → retryable, PostgrestException → retryable,
rejection → rejected). Mapper: feed row → PosOrder/lines byte-checks on names, modifier qty × delta,
null client_id → `server:<id>`, `branch_id` passthrough. Poller: cursor advances only after a page
merges, empty page stops, replay of a page after a crash re-merges without moving status backwards
(the §23.5 returning-flood guard). Source: version equal → returns cached, checksum mismatch →
error. Heartbeat: 30 s cadence, failure is silent + retried.

**Verification (this pass).** `rpc_order_feed` was first applied inside ONE rolled-back pooler
transaction (a kiosk device key fetches a page of the live branch: `next_since`/`next_after_id` from
real rows, `branch_id` = the device's branch; `since_required`/`bad_limit` doors raise; grants are
`t f t` on the three anon doors). **Then, with explicit owner approval this session, the migration
`20260815170000_kiosk_cloud_feed.sql` was APPLIED TO PRODUCTION** via a committed pooler transaction
(forward-only, idempotent — `create or replace`/`if not exists` throughout). The new `pos_cloud`
package (sink, feed poller, menu source, heartbeat, sync) is green at 38 tests; pos_core 116/116;
app `flutter analyze` has no new issues.

### K3b-B RESULT — DONE, 2026-08-15, code + live production proof

- **`packages/pos_cloud/` (new Flutter package, `pos_core` path dep + supabase_flutter ^2.8.0)** — the
  hub's cloud link, mirroring `pos_link`/`pos_link_flutter`: `contracts.dart` (PosRpcNames,
  PosRpcParams, PosFeedKeys incl. `serverLocalKeyPrefix='server:'`, PosCloudMeta.feedCursor),
  `feed_cursor.dart` (since/afterId tuple, `beginning` = epoch), `pos_cloud_gateway.dart`
  (`PosCloudGateway` interface + `SupabasePosCloudGateway` + `asServerRejection`:
  `PostgrestException.code == 'P0001'` → reached-server refusal → rejected; anything else →
  retryable), `cloud_order_mapper.dart` (row → CloudOrder{localClientId, PosOrder, lines}; names
  `{fr,en}`, modifier `qty × price_delta`, `combo` dropped client-side), `cloud_sink.dart`
  (kind→RPC mapping, expire = delivered no-op, not_acknowledged → retryable), `order_feed_poller.dart`
  (page-loop with `(updated_at,id)` cursor committed only after a merged page; stuck-cursor guard;
  MergeOutcome counters), `menu_snapshot_source.dart` (`SnapshotSource` over `rpc_menu_snapshot`;
  checksum required, branchId must match, validate-before-return), `heartbeat.dart` (silent failure),
  `pos_cloud_sync.dart` (start/stop: pin menu → feed 5 s + drain 2 s + heartbeat 30 s, per-tick
  fire-and-forget with onError).
- **Tests: 38 green** (`flutter test` in `packages/pos_cloud`): sink (all kinds, P0001 vs 5xx,
  not_acknowledged, replayed still delivered, hub-destination rejected), mapper (names, variant +
  modifier, microsecond timestamps, `server:<id>` fallback), poller (page loop + cursor commit +
  idempotent crash-replay + advancing ticket + stuck-cursor guard + failure leaves cursor), source
  (missing checksum, truncated, branch mismatch, checksum mismatch), heartbeat (server time, silent
  dead/refused line), cursor round-trip, sync composition (pins menu, drains, feeds, beats; failing
  tick reported + loops keep running), and `contract_parity_test.dart` reading the app's
  `rpc_names.dart`/`pos_contract_keys.dart` (drifted literal = release blocker, CLAUDE.md §3).
- **App constants synced:** `lib/core/constants/rpc_names.dart` (six device RPC names) and new
  `lib/core/constants/pos_contract_keys.dart` (PosRpcParams + PosFeedKeys + PosCloudMeta) now carry
  `device_seq`, `to`, `checksum`, `version`, `product_count`, `products` so the package mirror is
  complete and the parity test is bidirectional.
- **Applied to production (owner-approved) + live proof:** kiosk device `a3c7b786-…` registered on
  branch `10000000-0000-4000-8000-000000000001` (key stored chmod 600 in the opencode scratch dir,
  never in git). `rpc_device_heartbeat` → server `now()` + `last_seen_at` write-back verified;
  `rpc_menu_snapshot` → full bundle (version 1786799552, checksum, products with variants/option
  groups); `rpc_order_feed` from epoch → real branch orders incl. combo items; doors
  `device_unknown`/`bad_limit`/`since_required`/`device_role_forbidden` raise; all six doors grant
  EXECUTE to anon + authenticated. The live "CamPay phone order → board < 5 s" proof still awaits the
  checkout-warning surfaces (K3b-D) and the kiosk/KDS UIs.
- **K3b-C is folded into K3b-B:** the 30 s heartbeat loop is `PosHeartbeat` inside `PosCloudSync`
  (start()/stop() tick loops); §23.7 presence now proven in production.
- **K3b-D — checkout warnings (app + web):** DONE 2026-08-15. `branch_online` consumed in the customer
  checkout (app banner + web strip); warn-but-allow; fails open (never blocks a paying customer on an
  offline flag). Full result block below.


### K3b-D plan (checkout warnings, 2026-08-15, before any code)

**Goal.** The phone app and the website warn-but-allow when the store hub has not been seen for 3+
minutes (§23.7, ECOSYSTEM v1.18): a banner on the last screen before paying says the kitchen may not
be reachable, and ordering is **never blocked**. Fails open — if `branch_online` cannot be read, show
nothing (a false warning is its own defect).

**Contract (already in production, K1 migration 20260815120000).** View `public.branch_online`:
`{branch_id, last_seen_at, online}` with `online = max(last_seen_at) > now() - 3 minutes` over active
`kiosk`-role devices; `online = NULL` when the branch has no device → "unknown" → must render no
warning. `grant select to anon, authenticated`. The heartbeat that feeds it is K3b-B's `PosHeartbeat`
(30 s), proven live.

**App (customer app).**
- `lib/data/models/branch_presence.dart` — `BranchPresence {branchId, lastSeenAt?, online?}`
  (`online == false` = known offline; `null` = unknown → fail open).
- `CatalogRepository.getBranchPresence()` → `Future<BranchPresence?>`; Supabase impl reads
  `branch_online` for the active branch (`DbTables.branchOnline`, new `DbColumns.lastSeenAt`/`online`);
  the read is wrapped so any error → `null` (fail open). Mock impl → `null` (deterministic).
- Provider `branchPresenceProvider` (`FutureProvider.autoDispose`, so every checkout entry re-checks).
- Banner `_KitchenPresenceBanner` as the FIRST ListView child in `_CheckoutBody`: shown only when
  `online == false`; loading/error/unknown → zero pixels; non-blocking (no button, no gating of
  `canPlace`). Copy via l10n (`checkoutKitchenOfflineWarning`, fr/en), regenerated with
  `flutter gen-l10n` (ARB is the source; the parallel session's keys survive regeneration).
- Tests: `test/checkout_presence_banner_test.dart` (new, not on the do-not-touch list) — override
  `catalogRepositoryProvider`: `online == false` → banner visible; `online == null` → absent;
  throwing repo → absent. Existing `checkout_test.dart` stays green because the mock returns `null`.

**Web (Laravel webapp).** The public site's checkout: read `branch_online` for the branch and render
a warn-but-allow strip above the order/payment section; same fail-open rule (read error → nothing).
Separate stage, done right after the app side in this pass.

**Verification.** App: new widget test green; `flutter gen-l10n` + `flutter analyze` + the checkout
suite green; banner only ever appears for a known-offline branch. Web: the strip renders when the
device key heartbeat is stale (can be proven by querying the live view), absent on read error.
No store builds, no deploy.
### K3b-D RESULT (2026-08-15, implemented + verified)

**App (customer app).** All code shipped and green.
- `BranchPresence` model (`lib/data/models/branch_presence.dart`) — `online: bool?`, null = unknown → fail open.
- `CatalogRepository.getBranchPresence()` with a concrete default (`null`) so lightweight test doubles stay
  green without touching the protected test files' structure; `SupabaseCatalogRepository` reads `branch_online`
  for the active branch and swallows any read error → `null`; `CachedCatalogRepository` delegates straight to
  the source (NEVER cached — presence is a live 3-minute window); `MockCatalogRepository` returns `null`.
- `DbViews.branchOnline` constant + `DbColumns.lastSeenAt`/`online` constants.
- `branchPresenceProvider` (`FutureProvider.autoDispose`) — re-reads on every checkout entry.
- `_KitchenPresenceBanner` as the FIRST child of the checkout ListView: renders only when `online == false`;
  loading/unknown/error → zero pixels; informational, gates nothing. Styled with tokens (cream/gold/charcoal).
- l10n: `checkoutKitchenOfflineWarning` added to `app_fr.arb` (template) + `app_en.arb`, regenerated with
  `flutter gen-l10n` — the parallel session's in-flight keys (orderThisDish, cartReplacedSnack, closeTooltip)
  survived regeneration, verified in the diff.
- Tests: `test/checkout_presence_banner_test.dart` (3 widget tests: offline shows / null hides / error fails
  open). Riverpod 3 auto-retry backoff timers disabled in the test container (retry → null) so no pending timer
  trips the invariant; `TimeUtil.init` in setUpAll like the checkout suite. Required additive one-line
  `getBranchPresence() => null` overrides in 3 test doubles: `catalog_widgets_test`, `sold_out_ui_test`
  (do-not-touch list — minimal additive change, no parallel-session content touched), `motion_test`.
- **Verify:** `flutter analyze` clean (only the 5 pre-existing infos in protected home files); full suite 353/353
  green, incl. checkout (12) + banner (3) + cached catalog.

**Web (Laravel webapp).** All code shipped and green.
- `CatalogRepository::branchPresence(): ?bool` interface + `SupabaseCatalogRepository::branchPresence()`
  (reads active branch then `branch_online.online`; any failure → `null` via the existing fail-soft `get()`);
  `FakeCatalogRepository::branchPresence()` → `null` (deterministic, no strip in tests).
- `CartController::checkout` injects `CatalogRepository` and passes `branchOnline` to the view.
- `resources/views/public/checkout.blade.php`: `@if ($branchOnline === false)` strip with `role="status"`,
  localized `cart.kitchen_offline_warning` (fr + en added). `timma-overrides.css`: `--color-brand-cream` and
  `--color-brand-charcoal` exported to :root (both already defined in tokens.json) + `.timma-checkout__offline`
  (cream/gold/charcoal — the same trio the Flutter banner uses; charcoal-on-cream 13.9:1).
- Tests: `tests/Unit/BranchPresenceTest.php` (4: offline→false, online→true, no-branch→null, 503→null);
  `tests/Feature/CheckoutPresenceBannerTest.php` (3: offline shows strip + localized text, unknown hides,
  online hides). Full webapp suite 680 passed / 3 pre-existing skips. TranslationKeysTest auto-verifies the new
  key resolves in both locales.
- **LIVE proof (2026-08-15):** `php artisan serve` → `GET /checkout` against production anon key: strip rendered
  with the French warning, because the production kiosk device heartbeat was stale (> 3 min) →
  `branch_online.online = false`. Fail-open and online-hide states are unit-proven; the measured-offline path is
  proven live. A running kiosk clears the strip (nothing deployed, no store builds).

**Done-definition note:** the app side awaits its on-device run (banner visible when the kiosk app is off, absent
when heartbeating) in the next device pass; the code paths are fully unit/widget-tested and the web side is
live-proven.
