# BUG (owner, 2026-11-27) — the ticket code on the borne ≠ the code on the KDS and the TVs

> Status: **OPEN — investigation started, nothing fixed.**

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
