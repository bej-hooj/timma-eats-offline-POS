import 'package:pos_core/pos_core.dart';

/// One ticket the manager has to be told about by name.
///
/// "Sync failed" is not actionable. The whole reason an envelope is set aside
/// rather than retried forever is that a human now has to do something, and
/// they cannot do it without knowing **which order**.
class StrandedTicket {
  const StrandedTicket({
    required this.clientId,
    required this.ticketNumber,
    required this.total,
    required this.reason,
    required this.kind,
  });

  final String clientId;
  final int? ticketNumber;
  final int total;

  /// Why it is stuck — the envelope's own last error, or `pending` when it is
  /// simply still owed.
  final String reason;

  /// Which intent is stranded: a placement, a settlement, a transition. A
  /// stranded *settlement* means the cloud thinks a paid ticket is unpaid,
  /// which is a different conversation from a stranded transition.
  final String kind;
}

/// What the shift-close screen states, computed from the local store alone.
///
/// **Cash and mobile money are two separate totals**, and that is the whole
/// point of the screen (plan §K7). The cash number is the one countable against
/// what is in the drawer; a single "till total" mixing both is a number nobody
/// can check. Neither figure was computable before K1 made the tender a column
/// instead of a sentence — a free-text note cannot be summed, which is why the
/// till has never been reportable.
class ShiftCloseReport {
  const ShiftCloseReport({
    required this.localTickets,
    required this.acknowledged,
    required this.unsent,
    required this.cashTotal,
    required this.mobileMoneyTotal,
    required this.untenderedTotal,
    required this.stranded,
    required this.outbox,
  });

  /// Every ticket this device rang this shift.
  final int localTickets;

  /// Tickets the cloud has confirmed it holds. `serverOrderId` is the only
  /// honest evidence of that — a drained envelope says *we sent it*, not *they
  /// have it*.
  final int acknowledged;

  /// Rung here, not yet acknowledged. The gap the manager is closing.
  final int unsent;

  /// Minor units, settled in cash. Countable against the drawer.
  final int cashTotal;

  /// Minor units, settled as mobile money at the till. **A tablet can never
  /// contribute to this** — the tablet KDS is cash-only (§7.4) — so a non-zero
  /// figure here came from the dashboard, and that is exactly why the two are
  /// reported apart rather than summed.
  final int mobileMoneyTotal;

  /// Paid, but with no tender recorded. **Null tender never means cash**
  /// (§7.4): these are rows from before the column existed, or a settlement
  /// that landed without one. Shown as its own line so it can never be quietly
  /// folded into the cash figure a manager counts against the drawer.
  final int untenderedTotal;

  /// Named, not counted.
  final List<StrandedTicket> stranded;

  final OutboxCounts outbox;

  /// The only state in which "it probably synced" is a fact rather than a hope.
  bool get isSettled => outbox.isSettled && unsent == 0;

  /// What the drawer should hold.
  int get countable => cashTotal;
}

abstract final class ShiftClose {
  /// Builds the report from the local store. **No network**: a shift is closed
  /// at the end of a day that may have been entirely offline, and a screen that
  /// needs the WAN to tell a manager what they took is a screen that fails on
  /// the day it matters most.
  static ShiftCloseReport build({
    required PosStore store,
    required String deviceId,
  }) {
    final List<PosOrder> orders = store.allOrders();
    final List<PosOrder> mine = <PosOrder>[
      for (final PosOrder o in orders)
        if (o.origin == PosOrderOrigin.local) o,
    ];

    int cash = 0;
    int momo = 0;
    int untendered = 0;
    int acknowledged = 0;

    for (final PosOrder order in mine) {
      if (order.serverOrderId != null) {
        acknowledged++;
      }
      if (order.paymentStatus != PosPaymentStatus.paid) {
        continue;
      }
      switch (order.tender) {
        case PosTender.cash:
          cash += order.total;
        case PosTender.mobileMoney:
          momo += order.total;
        default:
          untendered += order.total;
      }
    }

    return ShiftCloseReport(
      localTickets: mine.length,
      acknowledged: acknowledged,
      unsent: mine.length - acknowledged,
      cashTotal: cash,
      mobileMoneyTotal: momo,
      untenderedTotal: untendered,
      stranded: _stranded(store, mine),
      outbox: store.outboxCounts(),
    );
  }

  /// Every ticket with an envelope that has not landed, named.
  static List<StrandedTicket> _stranded(PosStore store, List<PosOrder> orders) {
    final List<StrandedTicket> out = <StrandedTicket>[];
    for (final PosOrder order in orders) {
      for (final OutboxEnvelope envelope in store.envelopesForSubject(
        order.clientId,
      )) {
        if (envelope.state == EnvelopeState.done) {
          continue;
        }
        out.add(
          StrandedTicket(
            clientId: order.clientId,
            ticketNumber: order.ticketNumber,
            total: order.total,
            kind: envelope.kind,
            reason: envelope.state == EnvelopeState.quarantined
                ? (envelope.lastError ?? 'quarantined')
                : 'pending',
          ),
        );
      }
    }
    // Quarantined first: a stuck ticket needs a human now, a pending one only
    // needs the network back.
    out.sort((StrandedTicket a, StrandedTicket b) {
      final bool aStuck = a.reason != 'pending';
      final bool bStuck = b.reason != 'pending';
      if (aStuck == bStuck) {
        return (a.ticketNumber ?? 0).compareTo(b.ticketNumber ?? 0);
      }
      return aStuck ? -1 : 1;
    });
    return out;
  }
}
