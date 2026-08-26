import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_core/pos_core.dart';
import 'package:pos_core/testing.dart';
import 'package:timma_kiosk/design/money_formatter.dart';
import 'package:timma_kiosk/kiosk/shift/shift_close.dart';
import 'package:timma_kiosk/kiosk/shift/shift_close_screen.dart';
import 'package:timma_kiosk/l10n/app_localizations.dart';

/// K7 — sync, replay and reconciliation.
///
/// The stage's own proof: **an hour offline with orders across every status,
/// then reconnect — cloud state matches local exactly, and a deliberate
/// duplicate drain changes nothing.** That is what the last group does, against
/// a real engine, a real outbox and a real drain over a sink that can be taken
/// offline and back.
void main() {
  late PosStore store;
  late PosEngine engine;
  late ManualClock clock;

  const PosDeviceIdentity identity = PosDeviceIdentity(
    deviceId: 'kiosk-door',
    branchId: 'branch-1',
    role: PosDeviceRole.kiosk,
    label: 'Borne',
  );

  MenuSnapshot menu() {
    const MenuSnapshot draft = MenuSnapshot(
      version: 1,
      branchId: 'branch-1',
      declaredProductCount: 1,
      products: <SnapshotProduct>[
        SnapshotProduct(
          productId: 'p-poulet',
          nameFr: 'Poulet DG',
          nameEn: 'Chicken DG',
          basePrice: 3500,
          type: 'dish',
          available: true,
        ),
      ],
      checksum: '',
    );
    return MenuSnapshot(
      version: draft.version,
      branchId: draft.branchId,
      declaredProductCount: draft.declaredProductCount,
      products: draft.products,
      checksum: draft.computeChecksum(),
    );
  }

  setUp(() {
    clock = ManualClock(DateTime.utc(2026, 8, 16, 9));
    store = SqlitePosStore.inMemory();
    store.writeIdentity(identity);
    final MenuSnapshot m = menu();
    store.stageSnapshot(m, clock.nowUtc());
    store.activateSnapshot(m.version, clock.nowUtc());
    engine = PosEngine(store: store, identity: identity, clock: clock);
  });

  tearDown(() => store.close());

  PlacedOrder ring() => engine.placeKioskOrder(
    lines: const <PosCartLine>[PosCartLine(productId: 'p-poulet', quantity: 1)],
  );

  ShiftCloseReport close() =>
      ShiftClose.build(store: store, deviceId: identity.deviceId);

  group('shift close reports cash and momo as two separate totals', () {
    test('an unsettled ticket contributes to neither', () {
      ring();
      final ShiftCloseReport report = close();
      expect(report.localTickets, 1);
      expect(report.cashTotal, 0);
      expect(report.mobileMoneyTotal, 0);
    });

    test('cash settles into the countable figure', () {
      final PlacedOrder a = ring();
      final PlacedOrder b = ring();
      engine.settleCounterCash(a.order.clientId);
      engine.settleCounterCash(b.order.clientId);

      final ShiftCloseReport report = close();
      expect(report.cashTotal, 7000);
      expect(report.mobileMoneyTotal, 0);
      expect(
        report.countable,
        7000,
        reason: 'the cash figure is the one countable against the drawer',
      );
    });

    test('a momo-at-till ticket never lands in the cash column', () {
      final PlacedOrder a = ring();
      engine.settleCounterCash(a.order.clientId);
      // The dashboard settled this one as mobile money; the tablet never can
      // (§7.4), which is precisely why the two are reported apart.
      final PlacedOrder b = ring();
      store.updateOrder(
        store
            .findOrder(b.order.clientId)!
            .copyWith(
              status: PosOrderStatus.placed,
              paymentStatus: PosPaymentStatus.paid,
              tender: PosTender.mobileMoney,
            ),
      );

      final ShiftCloseReport report = close();
      expect(report.cashTotal, 3500);
      expect(report.mobileMoneyTotal, 3500);
      expect(
        report.countable,
        3500,
        reason: 'a single till total mixing both is a number nobody can check',
      );
    });

    test(
      'a paid ticket with NO tender is its own line, never folded into cash',
      () {
        final PlacedOrder a = ring();
        store.updateOrder(
          store
              .findOrder(a.order.clientId)!
              .copyWith(
                status: PosOrderStatus.placed,
                paymentStatus: PosPaymentStatus.paid,
              ),
        );
        final ShiftCloseReport report = close();
        expect(
          report.cashTotal,
          0,
          reason:
              'null tender NEVER means cash (§7.4) — folding it in would '
              'hand a manager a drawer figure that cannot be counted',
        );
        expect(report.untenderedTotal, 3500);
      },
    );
  });

  group('the unsent list is nameable', () {
    test('every owed ticket is named, not just counted', () {
      final PlacedOrder placed = ring();
      final ShiftCloseReport report = close();

      expect(report.unsent, 1);
      expect(report.stranded, isNotEmpty);
      expect(
        report.stranded.first.ticketNumber,
        placed.order.ticketNumber,
        reason:
            '"sync failed" is not actionable — a manager cannot act '
            'without knowing WHICH order',
      );
      expect(report.stranded.first.kind, EnvelopeKind.placeOrder);
      expect(report.stranded.first.reason, 'pending');
      expect(report.isSettled, isFalse);
    });

    test('a quarantined ticket sorts above a merely pending one', () {
      final PlacedOrder stuck = ring();
      ring();
      final OutboxEnvelope envelope = store
          .envelopesForSubject(stuck.order.clientId)
          .first;
      store.saveEnvelope(
        envelope.copyWith(
          state: EnvelopeState.quarantined,
          lastError: 'bad_transition',
        ),
      );

      final ShiftCloseReport report = close();
      expect(
        report.stranded.first.reason,
        'bad_transition',
        reason:
            'a stuck ticket needs a human now; a pending one only needs '
            'the network back',
      );
    });
  });

  group('an hour offline, then reconnect — the K7 proof', () {
    test('cloud state matches local exactly, and a duplicate drain changes '
        'nothing', () async {
      final _FakeSink sink = _FakeSink()..online = false;
      final OutboxDrain drain = OutboxDrain(
        store: store,
        sink: sink,
        clock: clock,
        onServerFields:
            (OutboxEnvelope envelope, Map<String, Object?> fields) =>
                engine.acknowledge(envelope.subject, fields),
      );

      // An hour of trading with the WAN down, across every status the kiosk
      // can reach on its own.
      for (int i = 0; i < 20; i++) {
        final PlacedOrder placed = ring();
        if (i % 2 == 0) {
          engine.settleCounterCash(placed.order.clientId);
        }
        if (i % 4 == 0) {
          engine.advance(placed.order.clientId, PosOrderStatus.accepted);
        }
        clock.advance(const Duration(minutes: 3));
      }

      // Nothing left. Every attempt failed, nothing was quarantined, and the
      // shift close says so honestly.
      await drain.drainOnce(limit: 100);
      expect(sink.delivered, isEmpty);
      ShiftCloseReport report = close();
      expect(report.localTickets, 20);
      expect(report.acknowledged, 0);
      expect(report.unsent, 20);
      expect(report.isSettled, isFalse);
      expect(
        report.cashTotal,
        10 * 3500,
        reason: 'the till is countable offline — that is the whole point',
      );

      // The WAN comes back and the manager forces a drain.
      sink.online = true;
      clock.advance(const Duration(hours: 1));
      for (int pass = 0; pass < 10; pass++) {
        final DrainReport pass1 = await drain.drainOnce(limit: 100);
        if (!pass1.madeProgress) {
          break;
        }
        clock.advance(const Duration(seconds: 30));
      }

      report = close();
      expect(
        report.unsent,
        0,
        reason: 'cloud state must match local exactly after reconnect',
      );
      expect(report.acknowledged, 20);
      expect(report.outbox.pending, 0);
      expect(report.outbox.quarantined, 0);
      expect(report.isSettled, isTrue);
      expect(report.stranded, isEmpty);

      // The deliberate duplicate: a manager taps "force drain" again.
      final int deliveredBefore = sink.delivered.length;
      final int cashBefore = report.cashTotal;
      await drain.drainOnce(limit: 100);

      final ShiftCloseReport after = close();
      expect(
        sink.delivered.length,
        deliveredBefore,
        reason:
            'a duplicate drain must change nothing — every envelope is '
            'already done, so there is nothing left to send',
      );
      expect(after.cashTotal, cashBefore);
      expect(after.localTickets, 20);
      expect(after.acknowledged, 20);
      expect(after.isSettled, isTrue);
    });
  });

  group('the shift-close screen', () {
    Future<void> pumpScreen(
      WidgetTester tester,
      ShiftCloseReport report,
    ) async {
      tester.view.physicalSize = const Size(2400, 1600);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('fr'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ShiftCloseScreen(report: report, onForceDrain: () {}),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('cash and momo are stated apart, never summed', (tester) async {
      final PlacedOrder a = ring();
      engine.settleCounterCash(a.order.clientId);
      final PlacedOrder b = ring();
      store.updateOrder(
        store
            .findOrder(b.order.clientId)!
            .copyWith(
              status: PosOrderStatus.placed,
              paymentStatus: PosPaymentStatus.paid,
              tender: PosTender.mobileMoney,
            ),
      );

      await pumpScreen(tester, close());

      expect(find.text('Espèces (à compter en caisse)'), findsOneWidget);
      expect(find.text('Mobile money au comptoir'), findsOneWidget);
      expect(
        find.text(MoneyFormatter.formatXaf(7000)),
        findsNothing,
        reason: 'a combined till total is a number nobody can check',
      );
      expect(find.text(MoneyFormatter.formatXaf(3500)), findsNWidgets(2));
    });

    testWidgets('stuck tickets are named on screen, not counted', (
      tester,
    ) async {
      final PlacedOrder stuck = ring();
      final OutboxEnvelope envelope = store
          .envelopesForSubject(stuck.order.clientId)
          .first;
      store.saveEnvelope(
        envelope.copyWith(
          state: EnvelopeState.quarantined,
          lastError: 'bad_transition',
        ),
      );

      await pumpScreen(tester, close());
      expect(
        find.textContaining('bad_transition'),
        findsOneWidget,
        reason: 'a manager cannot chase "3 failed"',
      );
      expect(find.textContaining('${stuck.order.ticketNumber}'), findsWidgets);
    });

    testWidgets('a settled shift says so plainly', (tester) async {
      await pumpScreen(
        tester,
        const ShiftCloseReport(
          localTickets: 4,
          acknowledged: 4,
          unsent: 0,
          cashTotal: 14000,
          mobileMoneyTotal: 0,
          untenderedTotal: 0,
          stranded: <StrandedTicket>[],
          outbox: OutboxCounts(pending: 0, done: 8, quarantined: 0),
        ),
      );
      expect(find.text('Tout est synchronisé.'), findsOneWidget);
    });
  });
}

/// A cloud sink that can be taken offline and back, and that mints the server
/// fields a real RPC returns.
class _FakeSink implements EnvelopeSink {
  bool online = true;
  final List<OutboxEnvelope> delivered = <OutboxEnvelope>[];
  final Map<String, String> _serverIds = <String, String>{};
  int _next = 0;

  @override
  Future<DeliveryResult> deliver(OutboxEnvelope envelope) async {
    if (!online) {
      // The normal outcome during an outage. It must never quarantine.
      return const DeliveryResult.retryable('offline');
    }
    delivered.add(envelope);
    return DeliveryResult.delivered(
      // The same field names the real PosCloudSink returns (`order_id`,
      // `order_code`, `daily_code`) — a fake that invents its own key would
      // prove the drain works against a contract nothing else speaks.
      fields: <String, Object?>{
        'order_id': _uuidFor(envelope.subject),
        'order_code': 'OC-${envelope.seq}',
      },
    );
  }

  /// One stable server id per subject. It must be **stable** (a retry of the
  /// same order must not mint a second cloud row) and **unique across orders**
  /// — `server_order_id` is uniquely indexed in the store, and a fake that
  /// collides would fail for a reason the product never would. Derived ids from
  /// UUIDv7 client ids collide: v7 is time-ordered, so orders rung in the same
  /// window share a long prefix.
  String _uuidFor(String subject) =>
      _serverIds.putIfAbsent(subject, () => 'srv-${_next++}');
}
