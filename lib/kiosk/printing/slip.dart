import 'dart:typed_data';

import 'package:pos_core/pos_core.dart';
import 'package:pos_link/pos_link.dart';

import 'package:timma_kiosk/design/money_formatter.dart';
import 'escpos.dart';

/// The printed slip.
///
/// Layout order is the order a customer and a cashier read it in: **the ticket
/// number dominates**, then what was ordered, then what is owed, then where to
/// pay, then the QR that releases the food. A slip whose number is the same
/// size as its line items is a slip that gets read wrong across a counter.
///
/// Strings are passed in rather than localised here: the printer is a byte
/// sink, and a layout that reaches for `AppLocalizations` would need a
/// `BuildContext` to print — which is how printing ends up coupled to whether a
/// screen happens to be mounted.
class SlipLabels {
  const SlipLabels({
    required this.header,
    required this.payAtCounter,
    required this.total,
    required this.takeAway,
    required this.without,
  });

  final String header;
  final String payAtCounter;
  final String total;
  final String takeAway;

  /// The pattern for a removed ingredient — "SANS {ingredient}" — with the
  /// placeholder still in it.
  ///
  /// ⚠ A PATTERN and not a finished string, because one slip can carry several
  /// removals and the printer has no localisations delegate to ask again. The
  /// substitution happens in [Slip._line], once per ingredient.
  final String without;
}

abstract final class Slip {
  /// Characters per line. 58 mm paper at font A is 32; 80 mm is 48. The kiosk
  /// ships with 58 mm because it is what the local supplier stocks, and a
  /// layout that assumes 48 silently wraps every line on the printer that
  /// actually arrives.
  static const int columns = 32;

  static Uint8List build({
    required PosOrder order,
    required List<PosOrderLine> lines,
    required SlipLabels labels,
    required CollectionCode code,
    required bool french,
  }) {
    return EscPos.build(<List<int>>[
      EscPos.initialize,
      EscPos.align(1),
      EscPos.bold(true),
      EscPos.text(labels.header),
      <int>[EscPos.lf],
      EscPos.bold(false),
      EscPos.text(labels.takeAway),
      <int>[EscPos.lf, EscPos.lf],

      /*
       * The number, as large as the printer can make it — and the STATION with
       * it.
       *
       * ⚠ At triple width this line is 10 characters wide on a 32-column
       * printer, and `B1-07` is 5. The station fits; a third character in the
       * code would not, which is why `stationAlphabet` is two.
       *
       * The station is here because `allocateTicketNumber` counts per till and
       * restarts at 1 each Douala day: a branch running two bornes hands two
       * different customers a slip that says the same thing. The fallback is
       * the bare number, never an invented letter.
       */
      EscPos.size(width: 3, height: 3),
      EscPos.bold(true),
      EscPos.text(order.ticketLabelOrNull ?? '-'),
      <int>[EscPos.lf],
      EscPos.size(),
      EscPos.bold(false),
      <int>[EscPos.lf],

      EscPos.align(0),
      ..._rule(),
      for (final PosOrderLine line in lines) ..._line(line, french, labels),
      ..._rule(),

      EscPos.bold(true),
      EscPos.text(_row(labels.total, MoneyFormatter.formatXaf(order.total))),
      <int>[EscPos.lf],
      EscPos.bold(false),
      <int>[EscPos.lf],

      EscPos.align(1),
      EscPos.bold(true),
      EscPos.text(labels.payAtCounter),
      <int>[EscPos.lf, EscPos.lf],
      EscPos.bold(false),

      EscPos.qr(code.payload),
      <int>[EscPos.lf],
      EscPos.text(_stamp(order.placedAtDevice)),
      <int>[EscPos.lf],

      EscPos.feed(3),
      EscPos.cut,
    ]);
  }

  static List<List<int>> _line(
    PosOrderLine line,
    bool french,
    SlipLabels labels,
  ) {
    final String name = french ? line.nameFr : line.nameEn;
    final String qty = '${line.quantity}x ';
    final List<List<int>> out = <List<int>>[
      EscPos.text(_row('$qty$name', MoneyFormatter.formatXaf(line.lineTotal))),
      <int>[EscPos.lf],
    ];
    for (final PosLineModifier m in line.modifiers) {
      out
        ..add(EscPos.text('   ${french ? m.nameFr : m.nameEn}'))
        ..add(<int>[EscPos.lf]);
    }
    /*
     * R2 (migrations 49 + 52) — what the customer asked to LEAVE OUT.
     *
     * ⚠ BOLD, in capitals, and AFTER the modifiers rather than mixed among
     * them. A cook reads a modifier as something to add and a removal as
     * something to withhold; a removal printed in the same weight, in the same
     * list, reads as "add onion" — the opposite of the request. Paper has no
     * colour to fall back on, so emphasis and word order carry the whole
     * distinction.
     *
     * The label is the FROZEN name from the order line (§6.5), so a reprint
     * next week says what the customer actually asked for.
     */
    for (final PosRemovedIngredient i in line.removedIngredients) {
      out
        ..add(EscPos.bold(true))
        ..add(
          EscPos.text(
            '   ${labels.without.replaceFirst('{ingredient}', (french ? i.nameFr : i.nameEn).toUpperCase())}',
          ),
        )
        ..add(EscPos.bold(false))
        ..add(<int>[EscPos.lf]);
    }
    return out;
  }

  /// Left label, right amount, padded to [columns]. When the two together
  /// exceed the width the **label** is truncated, never the amount — a slip
  /// that clips its own price is worse than one with a shortened dish name.
  static String _row(String left, String right) {
    final int room = columns - right.length - 1;
    final String label = left.length > room && room > 0
        ? left.substring(0, room)
        : left;
    final int pad = columns - label.length - right.length;
    return '$label${' ' * (pad < 1 ? 1 : pad)}$right';
  }

  static List<List<int>> _rule() => <List<int>>[
    EscPos.text('-' * columns),
    <int>[EscPos.lf],
  ];

  static String _stamp(DateTime at) {
    // The device's own clock, in Douala time. The slip is printed offline, so
    // there is no server timestamp to prefer and pretending otherwise would be
    // a lie about which clock the number came from (§23.4).
    final DateTime local = at.toUtc().add(const Duration(hours: 1));
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(local.day)}/${two(local.month)} '
        '${two(local.hour)}:${two(local.minute)}';
  }
}
