# BUG (owner, 2026-11-27) — the ticket code on the borne ≠ the code on the KDS and the TVs

> Status: **Fix built and tested. Borne updated on the Samsung. KDS release published. Restaurant acceptance pending.**

Owner: « Le code du ticket affiché sur la borne et qu'on demande au client de
noter ne correspond pas au code qui apparaît sur le KDS et la commande et donc
sur les écrans. La commande ne peut donc pas être convenablement suivie sur
tout son parcours. »

Rule to restore: ONE customer code end to end — the code on the borne screen and
the printed slip == the KDS card == Écran salle == Écran cuisine == (ideally)
the app/web order view and the dashboard.

## What is known (read 2026-11-27)
- Format: `ticketLabel(number, station)` in
  `timmaeat-app-flutter/packages/pos_core/lib/src/station_code.dart:108` =
  station code + `ticketSequenceCode(number)` (scrambled 2 chars). Without a
  station it returns the BARE number padded (`04`).
- Borne: `counter_screen.dart:51` and `printing/slip.dart:118` show
  `order.ticketLabelOrNull` (station + number of the LOCAL row).
- KDS card: `kds_ticket_card.dart:~111` shows `ticketLabelOrNull ?? dailyCode
  ?? orderCode`. TV (`lib/tv/domain/tv_board.dart` `_labelOf`) has the same
  fallback order.
- So the same function is used everywhere; the mismatch must come from the
  DATA the KDS holds: `ticketNumber` and/or `stationCode` differ or are null on
  the KDS row → it falls back to `dailyCode` (server's kitchen code) or prints
  the bare number.

## Suspects to check, in order
1. LAN wire `pos_link/lib/src/wire.dart:170/221/251` carries `ticket_number` +
   `station_code` (fixed in 151adba) — confirm the HUB snapshot builder fills
   them for every order (borne side: what builds the board snapshot).
2. Cloud path: `pos_cloud/cloud_order_mapper.dart:64` reads
   `PosFeedKeys.ticketNumber/stationCode` from `rpc_order_feed`. If the server
   feed does not return `ticket_number`/`station_code` for kiosk orders (or
   `rpc_place_kiosk_order` never stored them), a cloud merge OVERWRITES the KDS
   row with nulls → KDS shows `dailyCode` (a different code). Check the live
   function + `orders` columns (read-only SQL).
3. `mergeRemoteOrder` in pos_core: does a remote merge replace a non-null
   local ticketNumber/stationCode with null? It must keep the existing value
   (or the server must echo it).
4. Reproduce: one borne order → compare borne screen code, slip, KDS card,
   TV, and the row in `orders` (ticket_number, station_code, daily_code).

## Fix principles
- The borne's `ticketLabel` is THE customer code (it is printed). Every
  surface must show it; `dailyCode` only as a last resort for non-kiosk orders.
- If the server lacks the columns: migration (owner yes required) + feed +
  mapper; never apply without the owner's yes.
- Tests: a merge from the feed keeps ticket_number/station_code; the KDS label
  equals the borne label for the same order; TV label equals KDS label.
- Then rebuild borne APK (version > 1.0.2+2013) and KDS 1.0.5+2016 (APK +
  Windows Setup via CI) — publishing needs the owner's yes.


## Results — 2026-11-27

### Cause and repair

- The connected Samsung reports borne `1.0.0+2011` and KDS `1.0.3+2014`.
  The borne's original package pin `6b1de23` sends `ticket_number` but omits
  `station_code`. Its local screen and slip already format the four-character
  label. The published borne `1.0.2+2013` and KDS `1.0.4+2015` include the
  corrected wire contract from `151adba`. The hub builds the snapshot from its
  SQLite orders. The decoder preserves both fields.
- Supabase SELECT-only verification found both columns populated for all 21
  kiosk orders. The live `rpc_place_kiosk_order` inserts both and the live
  `rpc_order_feed` selects both with `client_id`. The cloud mapper reads them.
  No migration is required.
- The old merge preserved fields already present. It also discarded missing
  ticket fields supplied by a later snapshot, even when their absence caused a
  bare sequence or a fallback code. A regression test first reproduced this
  with an unchanged status and payment. The repair fills missing fields on a
  kiosk mirror, preserves known values and the age clock, and leaves the
  locally issued ticket code immutable.
- Borne, KDS and both TVs use the same printed label. The tablet and kitchen
  TV use the same card. The dining-room TV also uses the shared label for
  speech. The staff order list, detail and web KDS use the same formula, and
  staff can search by the printed code. Executing the staff query on Supabase
  returned a printable label for every kiosk order, different from the
  server's daily code on all 21. SQL and Dart agreed on all 1,024 sequence
  slots and four fallback cases. Daily-code fallback is for online orders.
- Both tablet pubspecs and lockfiles pin all four shared packages to
  `a9b185ab7f2768b06ab3b482303270c4d2e74838`.

### Verification and rollout

- Same sale test covers the borne screen, printed ESC/POS bytes and the LAN
  mirror before a cloud echo and after it advances the order with a different
  daily code and missing ticket fields. The KDS suite also checks a real
  paired LAN connection and the label in both TV surfaces.
- Flutter gates passed on the schema-owner app (880 tests), borne (202), and
  KDS (173), with zero analyzer issues. The `pos_core` suite passed all 156
  tests with `dart test`. Its four process durability tests require the Dart
  executable, so invoking the standalone Dart package suite via `flutter test`
  gives a test harness failure. `pos_cloud` passed 74 tests and `pos_link` 91.
- Borne APK `1.0.3+2014` and KDS APK `1.0.5+2016` verified against the
  previously published Android signing certificate. Windows installer
  workflow run `46033823775` succeeded. The installer and both APKs are in
  `verification-2026-11-27-ticket-code` with SHA-256 checksums and draft
  release notes.
- KDS `1.0.5+2016` published on `cuisine-win-20261123` with owner approval.
  Both GitHub asset hashes match the verified builds. The release notes show
  the current version as 1.0.5 (2016).
- Samsung: owner approved installing the production borne APK. Android
  accepted the in-place update from `1.0.0+2011` to `1.0.3+2014` and kept
  the original install timestamp. The app launched and displayed the real
  menu of the day. No production test sale was created.
- Dashboard commit `629eb47`: 82 targeted tests passed and Pint passed.
  The full PHP suite has the same nine homepage and link failures reproduced
  on the previous commit. No new full-suite failures were found.
- The current borne release is public and its existing APK includes the
  device credential. The new production APK is kept local pending a private
  delivery channel. Publication, staff web rollout and any credential change
  need explicit owner approval.
- On-site acceptance: update both apps in place. With the store LAN connected
  and internet disconnected, place one new borne order. Compare the screen
  and slip with the till card. Settle it and compare the KDS card and both TVs
  while it is preparing and ready. Restore internet, let the same order sync,
  then compare the staff order detail and search result with the original
  slip. The order must keep its code throughout the test.
