import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_core/pos_core.dart';
import 'package:pos_link/pos_link.dart';
import 'package:timma_kiosk/kiosk/kiosk_app.dart';
import 'package:timma_kiosk/kiosk/presentation/attract_screen.dart';
import 'package:timma_kiosk/kiosk/presentation/counter_screen.dart';
import 'package:timma_kiosk/kiosk/printing/escpos.dart';
import 'package:timma_kiosk/kiosk/printing/print_queue.dart';
import 'package:timma_kiosk/kiosk/printing/slip.dart';
import 'package:timma_kiosk/kiosk/state/kiosk_cart.dart';
import 'package:timma_kiosk/kiosk/state/kiosk_session.dart';
import 'package:timma_kiosk/kiosk/theme/kiosk_theme.dart';
import 'package:timma_kiosk/l10n/app_localizations.dart';

/// K6 wiring — **confirm places the sale, then prints its slip.**
///
/// The order of those two things is the whole subject. Every test here runs
/// against a real `pos_core` engine on an in-memory store and a real
/// [PrintQueue] over a fake transport, because the defects worth catching live
/// exactly in the seam between them: a slip printed for an order that was never
/// committed, an order abandoned because a printer was off, a sale placed twice
/// by one impatient customer, or a failure reported as a success.
///
/// It runs in **French**, the default locale, at a real mounted-tablet width.
/// The logical height a device reports for these physical pixels.
double screenHeightOf(Size physical, double ratio) => physical.height / ratio;
double screenWidthOf(Size physical, double ratio) => physical.width / ratio;

void main() {
  late PosStore store;
  late PosEngine engine;
  late _FakePrinter printer;

  const PosDeviceIdentity identity = PosDeviceIdentity(
    deviceId: 'kiosk-door',
    branchId: 'branch-1',
    role: PosDeviceRole.kiosk,
    label: 'Borne entrée',
  );

  final BranchCollectionSecret secret = BranchCollectionSecret.fromBytes(
    List<int>.generate(32, (int index) => (index * 11 + 3) % 256),
  );

  MenuSnapshot buildMenu() {
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
    store = SqlitePosStore.inMemory();
    store.writeIdentity(identity);
    engine = PosEngine(store: store, identity: identity);
    final MenuSnapshot menu = buildMenu();
    store.stageSnapshot(menu, DateTime.utc(2026, 8, 17));
    store.activateSnapshot(menu.version, DateTime.utc(2026, 8, 17));
    printer = _FakePrinter();
  });

  tearDown(() => store.close());

  /// A queue with no retry delay: the retry *rules* are proven in
  /// `kiosk_slip_test.dart`; here the wiring is the subject and two real
  /// seconds per attempt would only slow it down.
  PrintQueue queue({int maxAttempts = 3}) => PrintQueue(
    transport: printer,
    maxAttempts: maxAttempts,
    retryDelay: Duration.zero,
  );

  Widget app({
    PrintQueue? printQueue,
    BranchCollectionSecret? branchSecret,
  }) => ProviderScope(
    // NB: `Override` is not exported by Riverpod 3 — no type annotation here.
    overrides: [
      kioskEngineProvider.overrideWithValue(engine),
      kioskPrintQueueProvider.overrideWithValue(printQueue),
      kioskCollectionSecretProvider.overrideWithValue(branchSecret ?? secret),
    ],
    child: const KioskApp(),
  );

  Future<void> pump(WidgetTester tester, Widget widget) async {
    tester.view.physicalSize = const Size(2400, 1600);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await tester.pumpWidget(widget);
    await tester.pumpAndSettle();
  }

  /// attract → menu → add the dish → cart. Stops one tap short of confirming so
  /// each test owns that tap.
  Future<void> toCart(WidgetTester tester) async {
    await tester.tap(find.byType(KioskAttractScreen));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Poulet DG'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.ancestor(
        of: find.textContaining('Ajouter'),
        matching: find.byType(FilledButton),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder confirmButton() => find.widgetWithText(FilledButton, 'Commander');

  testWidgets('confirm places the sale, then queues exactly one slip', (
    tester,
  ) async {
    await pump(tester, app(printQueue: queue()));
    await toCart(tester);
    await tester.tap(confirmButton());
    await tester.pumpAndSettle();

    expect(find.byType(KioskCounterScreen), findsOneWidget);

    final List<PosOrder> orders = store.allOrders();
    expect(orders, hasLength(1), reason: 'one sale, committed durably');
    expect(printer.sent, hasLength(1), reason: 'one slip, printed once');

    // The QR on the paper must be the authenticated code for THIS order under
    // the branch secret — not the ticket number, and not a code the kitchen
    // cannot verify from its own store.
    final CollectionCode code = CollectionCode.forOrder(
      orders.single,
      secret: secret,
    );
    expect(
      _contains(printer.sent.single, EscPos.text(code.payload)),
      isTrue,
      reason: 'the slip carries the verifiable payload',
    );
    expect(
      code.verifies(secret: secret, branchId: 'branch-1'),
      isTrue,
      reason: 'and the KDS verifies it offline with no lookup',
    );
    // Nothing is printing and nothing failed, so the screen says nothing about
    // the slip — the paper is in the customer's hand.
    expect(find.textContaining('non imprimé'), findsNothing);
  });

  testWidgets('the slip verifies against a secret reloaded after a restart', (
    tester,
  ) async {
    await pump(tester, app(printQueue: queue()));
    await toCart(tester);
    await tester.tap(confirmButton());
    await tester.pumpAndSettle();

    // The same 32 bytes, arriving as a fresh instance the way a hub restart
    // would deliver them out of the keystore. A hub that minted a new secret
    // instead would leave this slip unverifiable in the customer's hand.
    final BranchCollectionSecret reloaded = BranchCollectionSecret.fromBytes(
      secret.bytes,
    );
    final CollectionCode printed = CollectionCode.forOrder(
      store.allOrders().single,
      secret: secret,
    );
    expect(printed.verifies(secret: reloaded, branchId: 'branch-1'), isTrue);
  });

  testWidgets(
    'a printer that never answers leaves the sale placed and says so',
    (tester) async {
      printer.failForever = true;
      await pump(tester, app(printQueue: queue()));
      await toCart(tester);
      await tester.tap(confirmButton());
      await tester.pumpAndSettle();

      expect(
        store.allOrders(),
        hasLength(1),
        reason: 'a failed print never unpicks a committed sale',
      );
      expect(printer.sent, isEmpty);
      expect(
        find.byType(KioskCounterScreen),
        findsOneWidget,
        reason: 'the customer still gets their number on screen',
      );
      expect(
        find.text('Ticket non imprimé. Présentez ce numéro à la caisse.'),
        findsOneWidget,
        reason: 'and is told, in French, that there is no paper coming',
      );
      expect(find.text('Réimprimer'), findsOneWidget);
    },
  );

  testWidgets('the failure is retryable, and a recovered printer prints', (
    tester,
  ) async {
    printer.failForever = true;
    await pump(tester, app(printQueue: queue()));
    await toCart(tester);
    await tester.tap(confirmButton());
    await tester.pumpAndSettle();
    expect(find.text('Réimprimer'), findsOneWidget);

    // Somebody switched the printer on / loaded paper.
    printer.failForever = false;
    await tester.tap(find.text('Réimprimer'));
    await tester.pumpAndSettle();

    expect(printer.sent, hasLength(1), reason: 'the held slip finally printed');
    expect(
      find.text('Ticket non imprimé. Présentez ce numéro à la caisse.'),
      findsNothing,
      reason: 'and the failure line is gone once it really printed',
    );
    expect(
      store.allOrders(),
      hasLength(1),
      reason: 'a reprint is not a second sale',
    );
  });

  testWidgets('an unprovisioned kiosk still sells, and prints nothing', (
    tester,
  ) async {
    // No print queue and no branch secret: a tablet whose printer has not
    // arrived, or which has not been paired yet. It must take the sale rather
    // than refuse the customer at the last tap.
    await pump(tester, app());
    await toCart(tester);
    await tester.tap(confirmButton());
    await tester.pumpAndSettle();

    expect(store.allOrders(), hasLength(1));
    expect(
      find.text('Ticket non imprimé. Présentez ce numéro à la caisse.'),
      findsOneWidget,
    );
  });

  test('two confirms racing over a slow printer buy one lunch, not two', () async {
    // Driven at the controller rather than through two taps, deliberately: two
    // taps in one frame never reach a second placement, so a widget test would
    // pass no matter what the code did. The window that genuinely exists is
    // asynchronous — the first confirm is parked on a printer that has not
    // answered, and a second confirm arrives.
    //
    // What this locks down is the **invariant**, not one mechanism. Two things
    // independently prevent a second sale: the cart is cleared before the print
    // is awaited, and `confirm` refuses to re-enter. Measured by removing each:
    // either alone is sufficient, and with both gone this test reports two
    // PosOrders for one customer. So it fails exactly when the last line of
    // defence is dropped, which is what a regression test is for.
    final _BlockingPrinter blocking = _BlockingPrinter();
    final ProviderContainer container = ProviderContainer(
      overrides: [
        kioskEngineProvider.overrideWithValue(engine),
        kioskPrintQueueProvider.overrideWithValue(
          PrintQueue(transport: blocking, retryDelay: Duration.zero),
        ),
        kioskCollectionSecretProvider.overrideWithValue(secret),
      ],
    );
    addTearDown(container.dispose);

    const SlipLabels labels = SlipLabels(
      header: 'TIMMA EATS',
      payAtCounter: 'Payez à la caisse',
      total: 'Total',
      takeAway: 'À emporter',
      without: 'SANS {ingredient}',
      // Q69 — the composition patterns, placeholders intact.
      groupLabel: '{group} : {answer}',
      groupNone: 'AUCUN',
    );

    final KioskSessionController controller = container.read(
      kioskSessionProvider.notifier,
    );
    controller.start();
    container
        .read(kioskCartProvider.notifier)
        .add(
          product: buildMenu().products.single,
          quantity: 1,
          variant: null,
          options: const <SnapshotOption>[],
        );

    // Neither future is awaited yet: both confirms are in flight.
    final Future<void> first = controller.confirm(labels: labels, french: true);
    final Future<void> second = controller.confirm(
      labels: labels,
      french: true,
    );
    blocking.release();
    await Future.wait(<Future<void>>[first, second]);

    expect(store.allOrders(), hasLength(1), reason: 'one order');
    expect(blocking.sent, hasLength(1), reason: 'one slip');
    expect(
      container.read(kioskSessionProvider).printState,
      KioskPrintState.printed,
    );
  });

  testWidgets('the next customer can still buy — the guard is not a latch', (
    tester,
  ) async {
    // The mirror of the race test. A guard keyed off "we are on the counter
    // screen" would be a fine way to break the kiosk for everyone after the
    // first sale of the day, so the second real order must go through.
    await pump(tester, app(printQueue: queue()));
    await toCart(tester);
    await tester.tap(confirmButton());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nouvelle commande'));
    await tester.pumpAndSettle();

    await toCart(tester);
    await tester.tap(confirmButton());
    await tester.pumpAndSettle();

    expect(store.allOrders(), hasLength(2), reason: 'two customers, two sales');
    expect(printer.sent, hasLength(2), reason: 'and two slips');
    expect(
      store.allOrders().map((PosOrder o) => o.ticketNumber),
      <int>[1, 2],
      reason: 'numbering continues rather than reusing a printed number',
    );
  });

  testWidgets('the counter screen fits every real tablet size, in French', (
    tester,
  ) async {
    // Found on the Samsung, not in a test: at 411 dp tall this screen
    // overflowed by 336 px and pushed the total, the slip line and *Nouvelle
    // commande* off the bottom. The sale was placed correctly and the customer
    // could neither see its price nor start another order. Sixth defect of this
    // exact shape in this project, so it gets a test at real sizes, in French,
    // in the tallest variant — the failed-print state, which carries two extra
    // rows.
    //
    // ⚠ The screen is pumped DIRECTLY rather than reached by tapping through
    // the flow. Driving the whole flow here would fail on the composer for a
    // reason that is not a defect: `flutter_test` substitutes a fixed-width
    // font where every glyph advances a full em, so "Ajouter  3 500 FCFA"
    // measures 418 dp in this harness against roughly 230 on the device, and
    // any width-sensitive row "overflows". Vertical geometry does not depend on
    // that substitution, which is why this test asserts heights and positions
    // and leaves the flow's widths to the device proof.
    addTearDown(tester.view.reset);
    final PlacedOrder placed = engine.placeKioskOrder(
      lines: <PosCartLine>[
        const PosCartLine(productId: 'p-poulet', quantity: 1),
      ],
    );
    for (final (Size size, double ratio) in <(Size, double)>[
      (const Size(2280, 1080), 2.625), // Samsung S10 landscape, 868x411 dp
      (const Size(2560, 1600), 2.0), // mounted 10-inch tablet, 1280x800 dp
      (const Size(1920, 1200), 2.0), // small 7-inch tablet, 960x600 dp
      // ⚠ The narrow one, and the reason the code is shrink-to-fit: at 640 dp
      // wide the side-by-side half is 320 dp and four characters at this
      // height's type size want 392. Without `BoxFit.scaleDown` the code is
      // clipped here — proven by removing it.
      (const Size(1280, 800), 2.0), // budget 7-inch, 640x400 dp
      // ⚠ And the other end. Owner, 2026-11-23: the borne may be shown on a
      // television, which reports its pixels at a ratio of 1 — four times the
      // logical width a tablet hands the layout.
      (const Size(1920, 1080), 1.0), // television 1080p
      (const Size(3840, 2160), 1.0), // television 4K
    ]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = ratio;
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('fr'),
          theme: KioskTheme.build(),
          localizationsDelegates: const <LocalizationsDelegate<Object>>[
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: KioskCounterScreen(
              placed: placed,
              printState: KioskPrintState.failed,
              onRetryPrint: () {},
              onDone: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull, reason: 'no overflow at $size');

      // ⚠ **The code must fit AND stay big.** Since 2026-11-23 this is four
      // characters rather than one or two digits — roughly twice as wide at
      // the same type size, which is itself a share of the screen HEIGHT and
      // therefore knows nothing about the width it has to fit in. Measured on
      // the Samsung's 411 dp landscape: the code's own type wants 490 dp and
      // the left half gives it 398, so WITHOUT `BoxFit.scaleDown` the last
      // character is cut off — silently, with no overflow warning.
      //
      // Both halves of the assertion matter. "No overflow" alone passes with
      // the code scaled to nothing, and a size floor alone passes with it
      // clipped — and the thing at stake is whether a customer can read out
      // the one string they have to say at the counter.
      final bool expectSideBySide = screenHeightOf(size, ratio) < 620;
      final String code = placed.order.ticketLabelOrNull!;
      final Rect drawn = tester.getRect(find.text(code));
      // Side by side the code gets HALF the screen, not all of it. Asserting
      // against the full width is what let a clipped code pass.
      final double room = expectSideBySide
          ? screenWidthOf(size, ratio) / 2
          : screenWidthOf(size, ratio);
      expect(
        drawn.width,
        lessThanOrEqualTo(room + 0.5),
        reason: 'the code runs past its half at $size (had $room dp)',
      );
      expect(
        drawn.height,
        greaterThan(40),
        reason: 'readable across a room, not merely present, at $size',
      );

      // ⚠ **The assertion that actually catches a clipped code.** A `Text`
      // under `maxLines: 1` that does not fit its constraint lays out AT the
      // constraint and clips the glyphs silently — no exception, and a width
      // check against the room it was given passes by construction. What
      // changes is the SHAPE: a scaled code keeps its aspect ratio, a clipped
      // one loses width while keeping its line height.
      final Text drawnText = tester.widget<Text>(find.text(code));
      final TextPainter painter = TextPainter(
        text: TextSpan(text: code, style: drawnText.style),
        textDirection: TextDirection.ltr,
        textScaler: TextScaler.noScaling,
      )..layout();
      expect(
        drawn.width / drawn.height,
        closeTo(painter.width / painter.height, 0.05),
        reason:
            'the code is clipped at $size — it is '
            '${drawn.width.toStringAsFixed(0)} dp wide where its own type '
            'wants ${painter.width.toStringAsFixed(0)}',
      );

      // Both the way out and the print recovery are built at every size.
      expect(find.text('Nouvelle commande'), findsOneWidget, reason: '$size');
      expect(find.text('Réimprimer'), findsOneWidget, reason: '$size');

      // ⚠ Structural, not pixel-positional. Whether a widget lands above the
      // fold cannot be measured in this harness: the substituted fixed-width
      // font wraps the French failure line onto three lines where the device
      // uses two, which moves everything below it. What IS font-independent is
      // WHICH layout the screen chose — and choosing the stacked one on a short
      // screen is the actual defect. 411 dp must go side by side; 800 must not.
      expect(
        find.text('Présentez ce numéro'),
        expectSideBySide ? findsNothing : findsOneWidget,
        reason: expectSideBySide
            ? 'a 411 dp screen must use the wide axis, where the number stands '
                  'alone and its caption moves in with the other words'
            : 'a tall screen keeps the caption above the number',
      );
    }
  });

  testWidgets('the kitchen is told about the sale, before the slip', (
    tester,
  ) async {
    // ⚠ The defect this exists for, reported from two paired devices: a customer
    // ordered at the kiosk and the kitchen stayed empty. `LanHubServer`
    // broadcasts when it applies an intent FROM a board, and its own
    // documentation says the kiosk controller must call `publishBoard()` after a
    // local sale — nothing did. The sale was durable and invisible.
    int published = 0;
    printer.failForever = true; // paper is optional; the kitchen is not
    await pump(
      tester,
      ProviderScope(
        overrides: [
          kioskEngineProvider.overrideWithValue(engine),
          kioskPrintQueueProvider.overrideWithValue(queue()),
          kioskCollectionSecretProvider.overrideWithValue(secret),
          kioskBoardPublisherProvider.overrideWithValue(() => published++),
        ],
        child: const KioskApp(),
      ),
    );
    await toCart(tester);
    await tester.tap(confirmButton());
    await tester.pumpAndSettle();

    expect(store.allOrders(), hasLength(1));
    expect(
      published,
      1,
      reason:
          'exactly one board publish per sale — the kitchen learns of it '
          'even though this printer never answered',
    );
  });

  testWidgets(
    'the publisher must be overridden at the ROOT, not in a child scope',
    (tester) async {
      // ⚠ **The second half of the same defect, and the half a green suite hid
      // for a whole release.** The call site above was fixed and proven — by a
      // test that built one container and overrode at its root, which is the
      // shape that works. Production put the override in a child
      // `ProviderScope` wrapping `KioskApp`, and Riverpod 3 does not
      // re-instantiate a provider in a child scope merely because it reads an
      // overridden one: `kioskSessionProvider` lives in the root container, so
      // it read the **default no-op** and announced every sale to nobody. On
      // the devices the kitchen stayed empty through a complete order while
      // `/health` cheerfully reported one connected board.
      //
      // This pins the semantics rather than the symptom, so the wiring cannot
      // quietly go back to a shape that compiles, passes, and sells in silence.
      int published = 0;
      await pump(
        tester,
        ProviderScope(
          overrides: [
            kioskEngineProvider.overrideWithValue(engine),
            kioskPrintQueueProvider.overrideWithValue(queue()),
            kioskCollectionSecretProvider.overrideWithValue(secret),
          ],
          child: ProviderScope(
            overrides: [
              kioskBoardPublisherProvider.overrideWithValue(() => published++),
            ],
            child: const KioskApp(),
          ),
        ),
      );
      await toCart(tester);
      await tester.tap(confirmButton());
      await tester.pumpAndSettle();

      expect(store.allOrders(), hasLength(1), reason: 'the sale is durable');
      expect(
        published,
        0,
        reason:
            'if this ever reaches 1, Riverpod has started scoping by '
            'transitive dependency and the root-scope requirement in '
            'main.dart can be relaxed — until then, moving the override '
            'into a child scope silently unplugs the kitchen',
      );
    },
  );

  testWidgets('a refused sale tells the kitchen nothing', (tester) async {
    int published = 0;
    await pump(
      tester,
      ProviderScope(
        overrides: [
          kioskEngineProvider.overrideWithValue(engine),
          kioskPrintQueueProvider.overrideWithValue(queue()),
          kioskCollectionSecretProvider.overrideWithValue(secret),
          kioskBoardPublisherProvider.overrideWithValue(() => published++),
        ],
        child: const KioskApp(),
      ),
    );
    await toCart(tester);

    // Sold out between browsing and confirming.
    const MenuSnapshot draft = MenuSnapshot(
      version: 2,
      branchId: 'branch-1',
      declaredProductCount: 1,
      products: <SnapshotProduct>[
        SnapshotProduct(
          productId: 'p-poulet',
          nameFr: 'Poulet DG',
          nameEn: 'Chicken DG',
          basePrice: 3500,
          type: 'dish',
          available: false,
        ),
      ],
      checksum: '',
    );
    final MenuSnapshot soldOut = MenuSnapshot(
      version: draft.version,
      branchId: draft.branchId,
      declaredProductCount: draft.declaredProductCount,
      products: draft.products,
      checksum: draft.computeChecksum(),
    );
    store.stageSnapshot(soldOut, DateTime.utc(2026, 8, 18));
    store.activateSnapshot(soldOut.version, DateTime.utc(2026, 8, 18));

    await tester.tap(confirmButton());
    await tester.pumpAndSettle();

    expect(store.allOrders(), isEmpty);
    expect(
      published,
      0,
      reason:
          'a ticket for an order that does not exist is the worst thing '
          'this screen could put in a kitchen',
    );
  });

  testWidgets('a dish sold out at the last moment prints nothing at all', (
    tester,
  ) async {
    await pump(tester, app(printQueue: queue()));
    await toCart(tester);

    // The snapshot is re-pinned while the customer is deciding — the expected
    // case, not an exceptional one.
    const MenuSnapshot draft = MenuSnapshot(
      version: 2,
      branchId: 'branch-1',
      declaredProductCount: 1,
      products: <SnapshotProduct>[
        SnapshotProduct(
          productId: 'p-poulet',
          nameFr: 'Poulet DG',
          nameEn: 'Chicken DG',
          basePrice: 3500,
          type: 'dish',
          available: false,
        ),
      ],
      checksum: '',
    );
    final MenuSnapshot soldOut = MenuSnapshot(
      version: draft.version,
      branchId: draft.branchId,
      declaredProductCount: draft.declaredProductCount,
      products: draft.products,
      checksum: draft.computeChecksum(),
    );
    store.stageSnapshot(soldOut, DateTime.utc(2026, 8, 17));
    store.activateSnapshot(soldOut.version, DateTime.utc(2026, 8, 17));

    await tester.tap(confirmButton());
    await tester.pumpAndSettle();

    expect(store.allOrders(), isEmpty, reason: 'the sale was refused');
    expect(
      printer.sent,
      isEmpty,
      reason:
          'a slip for an order that does not exist is the worst outcome '
          'available: the customer holds a ticket the kitchen never got',
    );
    expect(find.byType(KioskCounterScreen), findsNothing);
  });
}

/// A printer that holds the first job until it is released, so a second
/// `confirm()` can arrive while the first is still parked mid-print.
class _BlockingPrinter implements PrinterTransport {
  final Completer<void> _gate = Completer<void>();
  final List<Uint8List> sent = <Uint8List>[];

  void release() {
    if (!_gate.isCompleted) {
      _gate.complete();
    }
  }

  @override
  Future<void> send(Uint8List bytes) async {
    await _gate.future;
    sent.add(bytes);
  }

  @override
  Future<int?> status() async => 0x00;
}

/// A printer that can be switched off and on again, and that records what it
/// was actually asked to print.
class _FakePrinter implements PrinterTransport {
  bool failForever = false;
  final List<Uint8List> sent = <Uint8List>[];

  @override
  Future<void> send(Uint8List bytes) async {
    if (failForever) {
      throw StateError('socket closed');
    }
    sent.add(bytes);
  }

  @override
  Future<int?> status() async => 0x00;
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
