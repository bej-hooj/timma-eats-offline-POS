import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_core/pos_core.dart';
import 'package:timma_kiosk/design/money_formatter.dart';
import 'package:timma_kiosk/kiosk/catalog/cloud_catalog.dart';
import 'package:timma_kiosk/kiosk/catalog/dish_photo_cache.dart';
import 'package:timma_kiosk/kiosk/hub/dev_provisioning.dart';
import 'package:timma_kiosk/kiosk/kiosk_app.dart';
import 'package:timma_kiosk/kiosk/presentation/attract_screen.dart';
import 'package:timma_kiosk/kiosk/presentation/composer_sheet.dart';
import 'package:timma_kiosk/kiosk/presentation/menu_screen.dart';
import 'package:timma_kiosk/kiosk/state/kiosk_session.dart';

/// The dashboard is the menu, and the borne has to follow it **while it runs**.
///
/// Owner, 2026-11-22: *"Every price, every menu everything on borne is made
/// from the dashboard and loaded when the borne connects internet."* The data
/// half of that has worked since K3b — `rpc_menu_snapshot` lands a new bundle
/// in SQLite every 15 minutes. The screen half never did: the menu was read
/// once and nothing asked for a rebuild, so an edited price only appeared after
/// an app restart.
///
/// ⚠ Every widget test here runs at the **GM92's real geometry** — 1097 × 569
/// logical pixels, the borne the owner put in the shop — and in French. This
/// repo has shipped four French overflow defects found only on hardware, each
/// at a width no test used.
void main() {
  late PosStore store;
  late PosEngine engine;

  const PosDeviceIdentity identity = PosDeviceIdentity(
    deviceId: 'kiosk-gm92',
    branchId: 'branch-1',
    role: PosDeviceRole.kiosk,
    label: 'Borne entrée',
  );

  /// Built with a REAL checksum: `stageSnapshot` validates before it stores,
  /// and a bundle whose checksum does not match its bytes is the one thing the
  /// borne must refuse. A draft would test a path the kiosk cannot reach.
  MenuSnapshot menuAt({required int version, required int poulet}) {
    final MenuSnapshot draft = MenuSnapshot(
      version: version,
      branchId: 'branch-1',
      declaredProductCount: 1,
      products: <SnapshotProduct>[
        SnapshotProduct(
          productId: 'p-poulet',
          nameFr: 'Poulet DG',
          nameEn: 'Chicken DG',
          basePrice: poulet,
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

  void pin(MenuSnapshot menu) {
    store.stageSnapshot(menu, DateTime.utc(2026, 11, 22));
    store.activateSnapshot(menu.version, DateTime.utc(2026, 11, 22));
  }

  setUp(() {
    store = SqlitePosStore.inMemory();
    store.writeIdentity(identity);
    engine = PosEngine(store: store, identity: identity);
  });

  tearDown(() => store.close());

  Future<void> pump(WidgetTester tester, ValueNotifier<int> revision) async {
    // The GM92: 1920 × 1080 px at 280 dpi → 1.75 dpr → 1097 × 569 dp.
    tester.view.physicalSize = const Size(1920, 996);
    tester.view.devicePixelRatio = 1.75;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          kioskEngineProvider.overrideWithValue(engine),
          kioskMenuRevisionProvider.overrideWithValue(revision),
        ],
        child: const KioskApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('the dashboard reaches the screen without a restart', () {
    testWidgets('a new price replaces the old one on the menu', (tester) async {
      pin(menuAt(version: 100, poulet: 3500));
      final ValueNotifier<int> revision = ValueNotifier<int>(0);
      addTearDown(revision.dispose);
      await pump(tester, revision);

      await tester.tap(find.byType(KioskAttractScreen));
      await tester.pumpAndSettle();
      expect(find.byType(KioskMenuScreen), findsOneWidget);
      // ⚠ The formatter groups with a NON-BREAKING space. A literal ' ' here
      // finds nothing and the test would be asserting against a string the app
      // never renders — the trap that printed '3?500?FCFA' on every slip.
      expect(find.textContaining(MoneyFormatter.formatXaf(3500)), findsWidgets);

      // Ops edits the price in the dashboard; the catalogue pins the bundle and
      // ticks the revision. Nothing restarts.
      pin(menuAt(version: 101, poulet: 4200));
      revision.value++;
      await tester.pumpAndSettle();

      expect(
        find.textContaining(MoneyFormatter.formatXaf(4200)),
        findsWidgets,
        reason: 'the dashboard price must be on screen with no restart',
      );
      expect(
        find.textContaining(MoneyFormatter.formatXaf(3500)),
        findsNothing,
        reason: 'the superseded price must be gone, not merely outnumbered',
      );
    });

    testWidgets('a borne that opened with no menu starts selling when one '
        'arrives', (tester) async {
      // A fresh tablet: nothing pinned at first launch, which is exactly the
      // GM92 today. This used to be decided once and never revisited, so the
      // borne showed *Borne indisponible* to every customer until a restart.
      final ValueNotifier<int> revision = ValueNotifier<int>(0);
      addTearDown(revision.dispose);
      await pump(tester, revision);

      expect(find.byType(KioskAttractScreen), findsNothing);

      pin(menuAt(version: 100, poulet: 3500));
      revision.value++;
      await tester.pumpAndSettle();

      expect(
        find.byType(KioskAttractScreen),
        findsOneWidget,
        reason: 'a borne holding a menu must sell it',
      );
    });
  });

  group('the sample-menu band states a fact about the menu being sold', () {
    testWidgets('up on the seed, down on the dashboard bundle', (tester) async {
      pin(menuAt(version: KioskDevProvisioning.seedVersion, poulet: 1000));
      final ValueNotifier<int> revision = ValueNotifier<int>(0);
      addTearDown(revision.dispose);
      await pump(tester, revision);

      expect(
        find.textContaining('PRIX NON RÉELS'),
        findsOneWidget,
        reason: 'the seed is on sale, so the band must be up',
      );

      pin(menuAt(version: 1789043850, poulet: 3500));
      revision.value++;
      await tester.pumpAndSettle();

      expect(
        find.textContaining('PRIX NON RÉELS'),
        findsNothing,
        reason: 'real prices under a band calling them fake is the one way '
            'this marker can do harm — people learn to read past it',
      );
    });
  });

  group('the "+" adds only what there is nothing to decide about', () {
    // Owner, 2026-11-22: the borne must compose like the phone, "with even fly
    // add-to-cart". The flight is decoration; the RULE is which dishes get a
    // "+" at all. Live data makes the point: of nine published dishes, eight
    // have nothing to choose and Poulet DG has a required Accompagnement.
    MenuSnapshot withPoulet() {
      final MenuSnapshot draft = MenuSnapshot(
        version: 200,
        branchId: 'branch-1',
        declaredProductCount: 2,
        checksum: '',
        products: const <SnapshotProduct>[
          SnapshotProduct(
            productId: 'p-simple',
            nameFr: 'Koki',
            nameEn: 'Koki',
            basePrice: 2000,
            type: 'dish',
            available: true,
          ),
          SnapshotProduct(
            productId: 'p-choix',
            nameFr: 'Poulet DG',
            nameEn: 'Chicken DG',
            basePrice: 5000,
            type: 'dish',
            available: true,
            optionGroups: <SnapshotOptionGroup>[
              SnapshotOptionGroup(
                groupId: 'g-acc',
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
                ],
              ),
            ],
          ),
        ],
      );
      return MenuSnapshot(
        version: draft.version,
        branchId: draft.branchId,
        declaredProductCount: draft.declaredProductCount,
        products: draft.products,
        checksum: draft.computeChecksum(),
      );
    }

    testWidgets('a dish with a required group has NO "+"', (tester) async {
      pin(withPoulet());
      final ValueNotifier<int> revision = ValueNotifier<int>(0);
      addTearDown(revision.dispose);
      await pump(tester, revision);
      await tester.tap(find.byType(KioskAttractScreen));
      await tester.pumpAndSettle();

      // Two dishes on screen, exactly one quick-add: skipping a required
      // choice would put a line in the basket the kitchen cannot cook.
      expect(find.text('Koki'), findsOneWidget);
      expect(find.text('Poulet DG'), findsOneWidget);
      expect(find.byIcon(Icons.add), findsOneWidget);
    });

    testWidgets('the "+" puts the dish straight in the basket', (tester) async {
      pin(withPoulet());
      final ValueNotifier<int> revision = ValueNotifier<int>(0);
      addTearDown(revision.dispose);
      await pump(tester, revision);
      await tester.tap(find.byType(KioskAttractScreen));
      await tester.pumpAndSettle();

      expect(find.byType(KioskComposerSheet), findsNothing);
      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();

      // No composer in the way, and the cart bar is showing one line.
      expect(
        find.byType(KioskComposerSheet),
        findsNothing,
        reason: 'a dish with nothing to decide must not open a sheet',
      );
      expect(find.textContaining('1'), findsWidgets);
    });
  });

  group('a pin never lands under a customer', () {
    // `PosEngine.placeKioskOrder` re-prices from the ACTIVE snapshot at
    // placement time, so swapping the menu mid-order charges a price the
    // customer never read. The gate is the whole protection, and it is asserted
    // here against a LIVE pin route — a recorded call, not an absent cloud.
    late Directory tmp;

    setUp(() => tmp = Directory.systemTemp.createTempSync('kiosk-photos'));
    tearDown(() => tmp.deleteSync(recursive: true));

    KioskCloudCatalog catalogWith({
      required bool Function() canPin,
      required Future<void> Function() pinNow,
    }) => KioskCloudCatalog(
      sync: null,
      store: store,
      photos: DishPhotoCache(directory: tmp, allowedHost: 'example.invalid'),
      canPin: canPin,
      pinNow: pinNow,
    );

    test('an idle borne pins, and the screen is told exactly once', () async {
      pin(menuAt(version: 100, poulet: 3500));
      int pins = 0;
      final KioskCloudCatalog catalog = catalogWith(
        canPin: () => true,
        pinNow: () async {
          pins++;
          pin(menuAt(version: 101, poulet: 4200));
        },
      );
      addTearDown(catalog.dispose);

      await catalog.refresh();

      expect(pins, 1);
      expect(catalog.status, KioskCatalogStatus.pinned);
      expect(store.activeSnapshot()!.version, 101);
      expect(catalog.menuRevision.value, 1, reason: 'the menu changed');
    });

    test('a borne with a customer mid-order does NOT pin', () async {
      pin(menuAt(version: 100, poulet: 3500));
      int pins = 0;
      final KioskCloudCatalog catalog = catalogWith(
        canPin: () => false,
        pinNow: () async {
          pins++;
          pin(menuAt(version: 101, poulet: 4200));
        },
      );
      addTearDown(catalog.dispose);

      await catalog.refresh();

      expect(pins, 0, reason: 'the price a customer read must not move');
      expect(catalog.status, KioskCatalogStatus.busy);
      expect(store.activeSnapshot()!.version, 100);
      expect(catalog.menuRevision.value, 0);
    });

    test('an unchanged menu never disturbs the screen', () async {
      pin(menuAt(version: 100, poulet: 3500));
      final KioskCloudCatalog catalog = catalogWith(
        canPin: () => true,
        pinNow: () async {},
      );
      addTearDown(catalog.dispose);

      await catalog.refresh();
      await catalog.refresh();

      expect(
        catalog.menuRevision.value,
        0,
        reason: 'a tick that changed nothing must not rebuild the menu',
      );
    });
  });
}
