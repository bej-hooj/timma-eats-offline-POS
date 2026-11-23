import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_core/pos_core.dart';
import 'package:timma_kiosk/kiosk/kiosk_app.dart';
import 'package:timma_kiosk/kiosk/presentation/attract_screen.dart';
import 'package:timma_kiosk/kiosk/presentation/cart_screen.dart';
import 'package:timma_kiosk/kiosk/presentation/composer_sheet.dart';
import 'package:timma_kiosk/kiosk/presentation/counter_screen.dart';
import 'package:timma_kiosk/kiosk/presentation/menu_screen.dart';
import 'package:timma_kiosk/kiosk/state/kiosk_cart.dart';
import 'package:timma_kiosk/kiosk/state/kiosk_session.dart';
import 'package:timma_kiosk/kiosk/theme/kiosk_scale.dart';

/// K4 — the kiosk UI, proven against a real `pos_core` engine on an in-memory
/// store rather than a mocked one: the whole point of this surface is that it
/// prices and places locally, so a fake engine would prove nothing.
void main() {
  late PosStore store;
  late PosEngine engine;

  const PosDeviceIdentity identity = PosDeviceIdentity(
    deviceId: 'kiosk-door',
    branchId: 'branch-1',
    role: PosDeviceRole.kiosk,
    label: 'Borne entrée',
  );

  MenuSnapshot draftMenu() => const MenuSnapshot(
    version: 1,
    branchId: 'branch-1',
    declaredProductCount: 2,
    products: <SnapshotProduct>[
      SnapshotProduct(
        productId: 'p-poulet',
        nameFr: 'Poulet DG',
        nameEn: 'Chicken DG',
        basePrice: 3500,
        type: 'dish',
        available: true,
        optionGroups: <SnapshotOptionGroup>[
          SnapshotOptionGroup(
            groupId: 'g-accompagnement',
            nameFr: 'Accompagnement',
            nameEn: 'Side',
            minSelect: 1,
            maxSelect: 1,
            options: <SnapshotOption>[
              SnapshotOption(
                optionId: 'o-plantain',
                nameFr: 'Plantain',
                nameEn: 'Plantain',
                priceDelta: 0,
                maxQty: 1,
                available: true,
              ),
              SnapshotOption(
                optionId: 'o-frites',
                nameFr: 'Frites',
                nameEn: 'Fries',
                priceDelta: 500,
                maxQty: 1,
                available: true,
              ),
            ],
          ),
        ],
      ),
      SnapshotProduct(
        productId: 'p-poisson',
        nameFr: 'Poisson braisé',
        nameEn: 'Grilled fish',
        basePrice: 4000,
        type: 'dish',
        available: false,
        sortIndex: 1,
      ),
    ],
    checksum: '',
  );

  /// Built with a **real** checksum, not a placeholder: `stageSnapshot`
  /// validates before it stores, and a bundle whose checksum does not match its
  /// bytes is exactly what §23.8 exists to reject. A test that skipped this
  /// would be testing a path the kiosk can never reach.
  MenuSnapshot buildMenu() {
    final MenuSnapshot draft = draftMenu();
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
  });

  tearDown(() => store.close());

  void pinMenu() {
    final MenuSnapshot menu = buildMenu();
    store.stageSnapshot(menu, DateTime.utc(2026, 8, 16));
    store.activateSnapshot(menu.version, DateTime.utc(2026, 8, 16));
  }

  Widget app() => ProviderScope(
    // NB: `Override` is not exported by Riverpod 3 — no type annotation here.
    overrides: [kioskEngineProvider.overrideWithValue(engine)],
    child: const KioskApp(),
  );

  Future<void> pump(WidgetTester tester) async {
    // A mounted kiosk tablet, landscape.
    tester.view.physicalSize = const Size(2400, 1600);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    // The attract screen's invitation breathes forever, so `pumpAndSettle`
    // would never settle. Rather than special-casing the test, drive the
    // accessibility flag the screen already honours — which also means every
    // flow test below runs the same path a customer with reduced-motion set
    // would get. The animation itself is covered separately.
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
  }

  /// The add button states its price ("Ajouter  4 000 FCFA"), so it is found
  /// by the button wrapping that label rather than by an exact string.
  Finder addButton() => find.ancestor(
    of: find.textContaining('Ajouter'),
    matching: find.byType(FilledButton),
  );

  group('the four-taps path', () {
    testWidgets('attract → menu → composer → cart → counter', (tester) async {
      pinMenu();
      await pump(tester);

      expect(find.byType(KioskAttractScreen), findsOneWidget);

      await tester.tap(find.byType(KioskAttractScreen));
      await tester.pumpAndSettle();
      expect(find.byType(KioskMenuScreen), findsOneWidget);

      await tester.tap(find.text('Poulet DG'));
      await tester.pumpAndSettle();
      expect(find.byType(KioskComposerSheet), findsOneWidget);

      // A required group blocks the add until it is satisfied.
      final Finder add = addButton();
      expect(
        tester.widget<FilledButton>(add).onPressed,
        isNull,
        reason: 'a group with minSelect 1 is not satisfied yet',
      );

      await tester.tap(find.text('Plantain'));
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(add).onPressed, isNotNull);

      await tester.tap(add);
      await tester.pumpAndSettle();
      expect(find.byType(KioskCartScreen), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Commander'));
      await tester.pumpAndSettle();

      expect(find.byType(KioskCounterScreen), findsOneWidget);
      // The CODE is local and instant — no network was involved. Four
      // characters since 2026-11-23: a customer cannot hold on to "1", and it
      // is also what the other borne calls its first sale.
      expect(
        // The station is DERIVED from the device id here, so it is derived in
        // the assertion too — a literal would be asserting the test's own
        // guess at `stationCodeFor`.
        find.text(
          ticketLabel(number: 1, station: stationCodeFor('kiosk-door')),
        ),
        findsWidgets,
        reason: 'the counter screen shows the printed code, not the sequence',
      );

      final List<PosOrder> orders = store.allOrders();
      expect(orders, hasLength(1));
      expect(orders.single.status, PosOrderStatus.pendingPayment);
      expect(orders.single.mode, PosOrderMode.pickup);
      expect(
        orders.single.total,
        3500,
        reason: 'the free side adds nothing; the engine priced it, not the UI',
      );
    });

    testWidgets('a sold-out dish cannot be opened at all', (tester) async {
      pinMenu();
      await pump(tester);
      await tester.tap(find.byType(KioskAttractScreen));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Poisson braisé'), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(
        find.byType(KioskComposerSheet),
        findsNothing,
        reason: 'sold out is a barrier, not a badge (plan §K4 rule 4)',
      );
      expect(find.text('Épuisé'), findsOneWidget);
    });

    testWidgets('no pinned menu refuses loudly instead of showing an empty '
        'menu', (tester) async {
      // Nothing pinned.
      await pump(tester);
      expect(find.byType(KioskOutOfServiceScreen), findsOneWidget);
      expect(find.byType(KioskAttractScreen), findsNothing);
    });
  });

  group('the idle timeout', () {
    testWidgets('an abandoned cart never becomes the next customer\'s order', (
      tester,
    ) async {
      pinMenu();
      await pump(tester);
      await tester.tap(find.byType(KioskAttractScreen));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Poulet DG'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Plantain'));
      await tester.pumpAndSettle();
      await tester.tap(addButton());
      await tester.pumpAndSettle();
      expect(find.byType(KioskCartScreen), findsOneWidget);

      // The customer walks away.
      await tester.pump(KioskSessionController.idleAfter);
      await tester.pumpAndSettle();

      expect(find.byType(KioskAttractScreen), findsOneWidget);

      // And the next person finds a clean screen, not a stranger's basket.
      await tester.tap(find.byType(KioskAttractScreen));
      await tester.pumpAndSettle();
      final ProviderContainer container = ProviderScope.containerOf(
        tester.element(find.byType(KioskMenuScreen)),
      );
      expect(container.read(kioskCartProvider).isEmpty, isTrue);
    });

    testWidgets('a touch restarts the clock', (tester) async {
      pinMenu();
      await pump(tester);
      await tester.tap(find.byType(KioskAttractScreen));
      await tester.pumpAndSettle();

      // Just under the timeout, then a touch, then just under it again: a
      // customer reading the menu must not be thrown out mid-decision.
      await tester.pump(
        KioskSessionController.idleAfter - const Duration(seconds: 5),
      );
      await tester.tap(find.text('Notre carte'), warnIfMissed: false);
      await tester.pump(
        KioskSessionController.idleAfter - const Duration(seconds: 5),
      );
      await tester.pumpAndSettle();

      expect(find.byType(KioskMenuScreen), findsOneWidget);
    });
  });

  group('the composer', () {
    testWidgets('min/max count DISTINCT options, never total quantity', (
      tester,
    ) async {
      pinMenu();
      await pump(tester);
      await tester.tap(find.byType(KioskAttractScreen));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Poulet DG'));
      await tester.pumpAndSettle();

      // maxSelect is 1, so picking a second side swaps rather than adding.
      await tester.tap(find.text('Plantain'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Frites'));
      await tester.pumpAndSettle();

      await tester.tap(addButton());
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Commander'));
      await tester.pumpAndSettle();

      final PosOrder order = store.allOrders().single;
      expect(
        order.total,
        4000,
        reason:
            'base 3500 + fries 500 — the swap replaced plantain, and a '
            'quantity-counting bug would have charged for both',
      );
    });

    testWidgets('the price shown is the price the engine charges', (
      tester,
    ) async {
      pinMenu();
      await pump(tester);
      await tester.tap(find.byType(KioskAttractScreen));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Poulet DG'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Frites'));
      await tester.pumpAndSettle();

      // The composer's own button states the unit price.
      expect(find.textContaining('4 000'), findsWidgets);

      await tester.tap(addButton());
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Commander'));
      await tester.pumpAndSettle();

      expect(store.allOrders().single.total, 4000);
    });
  });

  group('the kiosk collects nothing about the customer', () {
    testWidgets('no PII field exists anywhere on the path', (tester) async {
      // The rule is **the kiosk collects nothing about the customer** — no
      // name, no phone, no email, no loyalty number. It is NOT "no text field
      // exists": the menu has a dish search, which asks about the food and not
      // about the person typing.
      //
      // So the assertion is on what a field could capture. A search box with a
      // text keyboard and no autofill hint cannot become a phone number field
      // by accident, and if one ever is added this test fails on its keyboard
      // type rather than on its existence.
      pinMenu();
      await pump(tester);
      await tester.tap(find.byType(KioskAttractScreen));
      await tester.pumpAndSettle();

      void expectNoPiiFields() {
        expect(find.byType(TextFormField), findsNothing);
        for (final TextField field in tester.widgetList<TextField>(
          find.byType(TextField),
        )) {
          expect(
            field.keyboardType,
            isNot(TextInputType.phone),
            reason:
                'a phone keypad on a kiosk is a phone number being asked for',
          );
          expect(field.keyboardType, isNot(TextInputType.emailAddress));
          expect(field.keyboardType, isNot(TextInputType.name));
          expect(
            field.autofillHints,
            anyOf(isNull, isEmpty),
            reason:
                'an autofill hint is the platform being told what personal '
                'value belongs here',
          );
          expect(
            field.obscureText,
            isFalse,
            reason: 'nothing on this screen is a secret being typed',
          );
        }
      }

      expectNoPiiFields();

      await tester.tap(find.text('Poulet DG'));
      await tester.pumpAndSettle();
      expectNoPiiFields();

      // And nothing on the placed order carries a customer either.
      final PosOrder? order = store.allOrders().firstOrNull;
      expect(order, isNull, reason: 'nothing was placed in this test');
    });
  });

  group('French and English', () {
    testWidgets(
      'the kiosk opens in French regardless of the tablet OS locale',
      (tester) async {
        pinMenu();
        await pump(tester);
        await tester.tap(find.byType(KioskAttractScreen));
        await tester.pumpAndSettle();
        expect(
          find.text('Notre carte'),
          findsOneWidget,
          reason:
              'a kiosk in Douala defaults to the product locale, not to '
              'whatever the tablet was set to in a warehouse',
        );
      },
    );

    testWidgets('the toggle switches the menu, and the session resets it', (
      tester,
    ) async {
      pinMenu();
      await pump(tester);
      await tester.tap(find.byType(KioskAttractScreen));
      await tester.pumpAndSettle();

      // ⚠ The label is the language it switches TO, and it is RESPONSIVE
      // (owner, 2026-11-23): the word where there is room for it, two letters
      // where the header is tight. This harness is 1200 dp wide, so the word.
      // A French customer looking for English scans for "English", never for
      // "Anglais".
      await tester.tap(find.widgetWithText(OutlinedButton, 'English'));
      await tester.pumpAndSettle();
      expect(find.text('Our menu'), findsOneWidget);
      expect(find.text('Chicken DG'), findsOneWidget);
      expect(find.text('Sold out'), findsOneWidget);

      // The next customer is a different person.
      await tester.pump(KioskSessionController.idleAfter);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(KioskAttractScreen));
      await tester.pumpAndSettle();
      expect(find.text('Notre carte'), findsOneWidget);
    });
  });

  group('touch targets are sized for a standing customer', () {
    testWidgets('every control on the menu path is at least 72dp', (
      tester,
    ) async {
      pinMenu();
      await pump(tester);
      await tester.tap(find.byType(KioskAttractScreen));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Poulet DG'));
      await tester.pumpAndSettle();

      for (final Element element
          in find.byType(FilledButton).evaluate().toList()) {
        final Size size = element.size!;
        expect(
          size.height,
          greaterThanOrEqualTo(KioskScale.minTarget),
          reason: 'a standing customer at arm\'s length misses a phone target',
        );
      }
      for (final Element element
          in find.byType(OutlinedButton).evaluate().toList()) {
        expect(
          element.size!.height,
          greaterThanOrEqualTo(KioskScale.minTarget),
        );
      }
    });
  });

  group('K8 hardening — no back-door out of the app', () {
    testWidgets('the Android back gesture never leaves the kiosk', (
      tester,
    ) async {
      pinMenu();
      await pump(tester);
      await tester.tap(find.byType(KioskAttractScreen));
      await tester.pumpAndSettle();
      expect(find.byType(KioskMenuScreen), findsOneWidget);

      // At the root route, an unhandled back BACKGROUNDS the app — which on an
      // unattended kiosk hands the next customer a home screen and a tablet.
      final bool popped = await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(
        popped,
        isTrue,
        reason: 'the app must CONSUME the back, not pass it to the platform',
      );
      expect(
        find.byType(KioskMenuScreen),
        findsOneWidget,
        reason: 'and it must not navigate anywhere either',
      );
    });

    testWidgets(
      'back is treated as activity, so it does not idle out mid-use',
      (tester) async {
        pinMenu();
        await pump(tester);
        await tester.tap(find.byType(KioskAttractScreen));
        await tester.pumpAndSettle();

        await tester.pump(
          KioskSessionController.idleAfter - const Duration(seconds: 5),
        );
        await tester.binding.handlePopRoute();
        await tester.pump(
          KioskSessionController.idleAfter - const Duration(seconds: 5),
        );
        await tester.pumpAndSettle();

        expect(find.byType(KioskMenuScreen), findsOneWidget);
      },
    );

    testWidgets('the kiosk exposes no navigation to any other surface', (
      tester,
    ) async {
      pinMenu();
      await pump(tester);
      await tester.tap(find.byType(KioskAttractScreen));
      await tester.pumpAndSettle();

      // One route, ever. A kiosk with a navigation stack is a kiosk somebody
      // can walk backwards out of.
      final NavigatorState navigator = tester.state(find.byType(Navigator));
      expect(
        navigator.canPop(),
        isFalse,
        reason: 'there is no stack to unwind — the kiosk has no router',
      );
    });
  });
}
