import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pos_core/pos_core.dart';
import 'package:pos_link/pos_link.dart';
import 'package:timma_kiosk/kiosk/printing/escpos.dart';
import 'package:timma_kiosk/kiosk/printing/print_queue.dart';
import 'package:timma_kiosk/kiosk/printing/slip.dart';

/// K6 — the slip and the collection code.
///
/// The printer itself is hardware-blocked, but the byte stream and the code's
/// verification rules are the parts that can be wrong in ways a physical test
/// would not catch: a slip that prints beautifully with a QR the KDS cannot
/// verify offline is a slip that fails only during an outage.
void main() {
  // The branch secret is `pos_link`'s typed 32-byte value, shared with the KDS
  // that verifies these codes. The kiosk deliberately holds no second copy of
  // this logic: one file, one wire format.
  final BranchCollectionSecret secret = BranchCollectionSecret.fromBytes(
    List<int>.generate(32, (int index) => index * 7 % 256),
  );

  PosOrder order({
    String clientId = 'c-1',
    String branchId = 'b-1',
    int? ticketNumber = 42,
    String? stationCode,
  }) => PosOrder(
    clientId: clientId,
    branchId: branchId,
    origin: PosOrderOrigin.local,
    source: PosOrderSource.kiosk,
    mode: PosOrderMode.pickup,
    status: PosOrderStatus.pendingPayment,
    paymentStatus: PosPaymentStatus.unpaid,
    paymentMethod: PosPaymentMethod.payAtCounter,
    deviceSeq: 1,
    subtotal: 3500,
    discount: 0,
    deliveryFee: 0,
    total: 3500,
    ticketNumber: ticketNumber,
    stationCode: stationCode,
    placedAtDevice: DateTime.utc(2026, 8, 16, 11, 30),
    statusChangedAt: DateTime.utc(2026, 8, 16, 11, 30),
  );

  group('the collection code verifies offline, with no lookup', () {
    test('a code round trips through its printed payload', () {
      final CollectionCode code = CollectionCode.forOrder(
        order(),
        secret: secret,
      );
      final CollectionCode? scanned = CollectionCode.tryParse(code.payload);
      expect(scanned, isNotNull);
      expect(scanned!.ticketNumber, 42);
      expect(
        scanned.verifies(secret: secret, branchId: 'b-1'),
        isTrue,
        reason:
            'the KDS must verify from its own store — a QR needing a round '
            'trip breaks collection in exactly the outage it was printed for',
      );
    });

    test('a slip from another branch does not collect food here', () {
      final CollectionCode code = CollectionCode.forOrder(
        order(branchId: 'b-other'),
        secret: secret,
      );
      expect(
        code.verifies(secret: secret, branchId: 'b-1'),
        isFalse,
        reason: 'two branches share a menu and a ticket-number sequence',
      );
    });

    test('a forged code with the right shape is refused', () {
      final CollectionCode real = CollectionCode.forOrder(
        order(),
        secret: secret,
      );
      // Someone reads a genuine slip and writes their own with a higher number.
      final CollectionCode forged = CollectionCode(
        clientId: real.clientId,
        branchId: real.branchId,
        ticketNumber: 99,
        mac: real.mac,
      );
      expect(forged.verifies(secret: secret, branchId: 'b-1'), isFalse);
    });

    test('a code minted under a different secret is refused', () {
      final CollectionCode code = CollectionCode.forOrder(
        order(),
        secret: BranchCollectionSecret.fromBytes(List<int>.filled(32, 9)),
      );
      expect(code.verifies(secret: secret, branchId: 'b-1'), isFalse);
    });

    test('an order with no ticket number cannot mint a code at all', () {
      // The kiosk's own earlier copy of this class turned a null ticket into
      // `0` and signed it, so a slip could carry a perfectly valid MAC over a
      // ticket number no customer was ever given. The shared implementation
      // refuses instead, and `confirm()` reports the slip as not printed.
      expect(
        () =>
            CollectionCode.forOrder(order(ticketNumber: null), secret: secret),
        throwsA(isA<FormatException>()),
      );
    });

    test('garbage from a scanner is null, never an exception', () {
      // A scanner reads packaging barcodes, other restaurants' slips and the
      // back of a hand. Garbage in is the normal case at a busy counter.
      for (final String junk in <String>[
        '',
        'hello',
        'TIMMA1|only|three',
        'TIMMA1|c|b|not-a-number|mac',
        'OTHER|c|b|1|mac',
        '||||',
      ]) {
        expect(CollectionCode.tryParse(junk), isNull, reason: 'input: "$junk"');
      }
    });

    test('the ticket number alone is not a code', () {
      expect(CollectionCode.tryParse('42'), isNull);
    });
  });

  group('the slip', () {
    const SlipLabels labels = SlipLabels(
      header: 'TIMMA',
      payAtCounter: 'Payez en espèces à la caisse',
      total: 'Total',
      takeAway: 'À emporter',
      without: 'SANS {ingredient}',
    );

    List<PosOrderLine> lines() => <PosOrderLine>[
      const PosOrderLine(
        lineNo: 0,
        productId: 'p-poulet',
        nameFr: 'Poulet DG',
        nameEn: 'Chicken DG',
        unitPrice: 3500,
        quantity: 1,
        lineTotal: 3500,
      ),
    ];

    Uint8List build() => Slip.build(
      order: order(),
      lines: lines(),
      labels: labels,
      code: CollectionCode.forOrder(order(), secret: secret),
      french: true,
    );

    test('it opens with a reset and ends with a cut', () {
      final Uint8List bytes = build();
      expect(
        bytes.take(2),
        EscPos.initialize,
        reason:
            'the previous job may have died mid-format and left the '
            'printer bold or upside down',
      );
      expect(bytes.sublist(bytes.length - EscPos.cut.length), EscPos.cut);
    });

    test('the ticket number is printed at the largest size', () {
      final Uint8List bytes = build();
      final List<int> large = EscPos.size(width: 3, height: 3);
      expect(
        _contains(bytes, large),
        isTrue,
        reason:
            'a slip whose number is the size of its line items gets read '
            'wrong across a counter',
      );
    });

    test('the number is printed WITH its station, so two bornes differ', () {
      /*
       * ⚠ `42` alone is not an identifier. `allocateTicketNumber` counts per
       * till and restarts at 1 at the Douala boundary, so a branch running a
       * second borne hands two different customers a slip saying the same
       * thing. Migration 54 / `ticketLabelOrNull`.
       *
       * Asserted on the REAL medium — the bytes that reach the printer.
       */
      final Uint8List bytes = Slip.build(
        order: order(ticketNumber: 42, stationCode: 'B1'),
        lines: lines(),
        labels: labels,
        code: CollectionCode.forOrder(order(), secret: secret),
        french: true,
      );

      expect(_contains(bytes, utf8.encode('B1-42')), isTrue);
      expect(
        _contains(bytes, utf8.encode('B1-42')) &&
            !_contains(bytes, utf8.encode('B2-42')),
        isTrue,
      );
    });

    test('a sale from before stations prints the bare number', () {
      // Never an invented letter: a wrong station sends a customer to the
      // wrong borne, which is worse than a number with no station on it.
      final Uint8List bytes = Slip.build(
        order: order(ticketNumber: 42),
        lines: lines(),
        labels: labels,
        code: CollectionCode.forOrder(order(), secret: secret),
        french: true,
      );

      expect(_contains(bytes, utf8.encode('42')), isTrue);
    });

    test('the QR carries the verifiable payload, not the ticket number', () {
      final CollectionCode code = CollectionCode.forOrder(
        order(),
        secret: secret,
      );
      final Uint8List bytes = build();
      expect(_contains(bytes, utf8.encode(code.payload)), isTrue);
    });

    test('a removal prints in CAPITALS, bold, on its own line', () {
      /*
       * R2 / Stage 3d, and the same rule as the KDS board: a cook reads a
       * modifier as something to ADD and a removal as something to WITHHOLD.
       * Paper has no colour to fall back on, so emphasis and word order carry
       * the whole distinction — bold, capitals, and AFTER the modifiers rather
       * than mixed among them.
       *
       * ⚠ Asserted on the REAL medium: the bytes that reach the printer, in
       * French, through the same code page that has printed "?" for a
       * non-breaking space before.
       */
      final Uint8List bytes = Slip.build(
        order: order(),
        lines: <PosOrderLine>[
          const PosOrderLine(
            lineNo: 0,
            productId: 'p-poulet',
            nameFr: 'Poulet DG',
            nameEn: 'Chicken DG',
            unitPrice: 3500,
            quantity: 1,
            lineTotal: 3500,
            modifiers: <PosLineModifier>[
              PosLineModifier(
                optionId: 'o-plantain',
                nameFr: 'Plantain',
                nameEn: 'Plantain',
                priceDelta: 500,
                quantity: 1,
              ),
            ],
            removedIngredients: <PosRemovedIngredient>[
              PosRemovedIngredient(
                id: 'ing-onion',
                nameFr: 'Oignon',
                nameEn: 'Onion',
              ),
            ],
          ),
        ],
        labels: labels,
        code: CollectionCode.forOrder(order(), secret: secret),
        french: true,
      );

      expect(_contains(bytes, EscPos.text('SANS OIGNON')), isTrue);
      // The modifier is still there, and still NOT in the same breath.
      expect(_contains(bytes, EscPos.text('Plantain')), isTrue);
      expect(
        _contains(bytes, EscPos.text('Plantain SANS OIGNON')),
        isFalse,
        reason: 'a removal joined to a modifier reads as an instruction to add',
      );
      // Bold on, then the words. Emphasis is the only signal paper has.
      expect(
        _contains(bytes, <int>[
          ...EscPos.bold(true),
          ...EscPos.text('   SANS'),
        ]),
        isTrue,
      );
    });

    test('an accented removal survives the code page too', () {
      // "Piment frais" is fine; "Céleri" is the one that turns into "C?leri"
      // if a removal ever bypasses the shared text encoder.
      final Uint8List bytes = Slip.build(
        order: order(),
        lines: <PosOrderLine>[
          const PosOrderLine(
            lineNo: 0,
            productId: 'p-koki',
            nameFr: 'Koki',
            nameEn: 'Koki',
            unitPrice: 2000,
            quantity: 1,
            lineTotal: 2000,
            removedIngredients: <PosRemovedIngredient>[
              PosRemovedIngredient(
                id: 'ing-celery',
                nameFr: 'Céleri',
                nameEn: 'Celery',
              ),
            ],
          ),
        ],
        labels: labels,
        code: CollectionCode.forOrder(order(), secret: secret),
        french: true,
      );

      expect(_contains(bytes, EscPos.text('SANS CÉLERI')), isTrue);
    });

    test('a line with nothing removed prints no extra row', () {
      final Uint8List bytes = build();

      expect(_contains(bytes, EscPos.text('SANS')), isFalse);
    });

    test('French accents survive the code page', () {
      final Uint8List bytes = build();
      // "espèces" and "À emporter" must not print as "esp?ces".
      expect(_contains(bytes, EscPos.text('espèces')), isTrue);
      expect(EscPos.text('è'), <int>[0x8A]);
      expect(EscPos.text('à'), <int>[0x85]);
      expect(EscPos.text('ç'), <int>[0x87]);
      expect(
        bytes.where((int b) => b == 0x3F),
        isEmpty,
        reason: 'a question mark means a character fell off the code page',
      );
    });

    test('a long dish name truncates the label, never the amount', () {
      final Uint8List bytes = Slip.build(
        order: order(),
        lines: <PosOrderLine>[
          const PosOrderLine(
            lineNo: 0,
            productId: 'p-long',
            nameFr: 'Poulet Directeur General avec plantains et sauce',
            nameEn: 'Very long dish name indeed for one line',
            unitPrice: 3500,
            quantity: 1,
            lineTotal: 3500,
          ),
        ],
        labels: labels,
        code: CollectionCode.forOrder(order(), secret: secret),
        french: true,
      );
      expect(
        _contains(bytes, EscPos.text('3 500 FCFA')),
        isTrue,
        reason:
            'a slip that clips its own price is worse than one with a '
            'shortened dish name',
      );
    });

    test('paper-out is read from the status byte before a job', () {
      expect(EscPos.paperStatus, <int>[0x10, 0x04, 0x04]);
      expect(EscPos.paperOut(0x60), isTrue);
      expect(EscPos.paperOut(0x00), isFalse);
    });
  });

  group('the print queue — a lost slip is a lost order', () {
    Uint8List job(String s) => Uint8List.fromList(utf8.encode(s));

    test('a transient failure is retried, not dropped', () async {
      final _FakePrinter printer = _FakePrinter(failTimes: 2);
      final PrintQueue queue = PrintQueue(
        transport: printer,
        retryDelay: Duration.zero,
      );
      final PrintJob printed = await queue.enqueue('j1', job('slip'));
      expect(printed.state, PrintJobState.printed);
      expect(printed.attempts, 3);
      expect(printer.sent, hasLength(1));
      expect(queue.failed, isEmpty);
    });

    test(
      'an exhausted job stays VISIBLE as failed, never silently dropped',
      () async {
        final _FakePrinter printer = _FakePrinter(failTimes: 99);
        final PrintQueue queue = PrintQueue(
          transport: printer,
          retryDelay: Duration.zero,
        );
        await queue.enqueue('j1', job('slip'));
        expect(queue.failed, hasLength(1));
        expect(
          queue.failed.single.state,
          PrintJobState.failed,
          reason:
              'a customer with no ticket has no way to collect and no proof '
              'they paid — the failure must be one a human dismisses',
        );
        expect(queue.pendingCount, 0);
      },
    );

    test('paper-out is caught BEFORE the job, not after', () async {
      final _FakePrinter printer = _FakePrinter(statusByte: 0x60);
      final PrintQueue queue = PrintQueue(
        transport: printer,
        retryDelay: Duration.zero,
      );
      await queue.enqueue('j1', job('slip'));
      expect(queue.paperOut, isTrue);
      expect(
        printer.sent,
        isEmpty,
        reason:
            'a slip that fails halfway has already taken the customer\'s '
            'place in the queue',
      );
      expect(queue.failed.single.lastError, 'paper_out');
    });

    test('loading paper and retrying clears the backlog', () async {
      final _FakePrinter printer = _FakePrinter(statusByte: 0x60);
      final PrintQueue queue = PrintQueue(
        transport: printer,
        retryDelay: Duration.zero,
      );
      await queue.enqueue('j1', job('slip'));
      expect(queue.failed, hasLength(1));

      printer.statusByte = 0x00;
      await queue.retryFailed();
      expect(queue.failed, isEmpty);
      expect(printer.sent, hasLength(1));
    });

    test('reprint-last does not drift backwards on repeated use', () async {
      final _FakePrinter printer = _FakePrinter();
      final PrintQueue queue = PrintQueue(
        transport: printer,
        retryDelay: Duration.zero,
      );
      await queue.enqueue('j1', job('first'));
      await queue.enqueue('j2', job('second'));

      await queue.reprintLast();
      await queue.reprintLast();

      expect(printer.sent, hasLength(4));
      expect(
        utf8.decode(printer.sent.last),
        'second',
        reason:
            'a reprint must not become what the NEXT reprint copies, or '
            '"print that again" walks one job further back each time',
      );
    });

    test('nothing printed yet means nothing to reprint', () async {
      final PrintQueue queue = PrintQueue(transport: _FakePrinter());
      expect(await queue.reprintLast(), isNull);
    });
  });
}

bool _contains(List<int> haystack, List<int> needle) {
  if (needle.isEmpty || needle.length > haystack.length) {
    return false;
  }
  for (int i = 0; i <= haystack.length - needle.length; i++) {
    bool hit = true;
    for (int j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) {
        hit = false;
        break;
      }
    }
    if (hit) {
      return true;
    }
  }
  return false;
}

/// The print queue's retry rules — the part that decides whether a customer
/// ends up holding a slip, provable without a printer on the desk.
class _FakePrinter implements PrinterTransport {
  _FakePrinter({this.failTimes = 0, this.statusByte = 0x00});

  int failTimes;
  int statusByte;
  final List<Uint8List> sent = <Uint8List>[];

  @override
  Future<void> send(Uint8List bytes) async {
    if (failTimes > 0) {
      failTimes--;
      throw StateError('socket closed');
    }
    sent.add(bytes);
  }

  @override
  Future<int?> status() async => statusByte;
}
