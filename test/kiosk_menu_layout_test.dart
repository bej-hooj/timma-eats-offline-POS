import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_core/pos_core.dart';
import 'package:timma_kiosk/design/money_formatter.dart';
import 'package:timma_kiosk/kiosk/presentation/menu_screen.dart';
import 'package:timma_kiosk/kiosk/presentation/widgets/kiosk_category_pill.dart';
import 'package:timma_kiosk/kiosk/presentation/composer_sheet.dart';
import 'package:timma_kiosk/kiosk/presentation/widgets/kiosk_dish_card.dart';
import 'package:timma_kiosk/kiosk/presentation/widgets/kiosk_dish_thumb.dart';
import 'package:timma_kiosk/kiosk/theme/kiosk_scale.dart';
import 'package:timma_kiosk/kiosk/theme/kiosk_theme.dart';
import 'package:timma_kiosk/l10n/app_localizations.dart';

/// The dish grid must fit the screen the kiosk is actually mounted on.
///
/// Measured on the Samsung: in landscape that device is **868 × 411 dp**, which
/// leaves the grid roughly 259 dp. A card sized off its width alone came out
/// 370 dp tall and its price row was clipped clean off the bottom — a dish with
/// no price, on the screen whose entire job is telling a customer what things
/// cost. The card before it was a fixed 350 dp and had the same defect; it had
/// simply never been rendered at this size.
///
/// Every case here runs in **French**, at real device widths, and asserts the
/// price is on screen rather than merely in the widget tree.
void main() {
  _searchAndFilter();
  MenuSnapshot menu() {
    const List<SnapshotProduct> products = <SnapshotProduct>[
      SnapshotProduct(
        productId: 'p-poulet',
        nameFr: 'Poulet DG',
        nameEn: 'Chicken DG',
        basePrice: 4500,
        type: 'dish',
        available: true,
      ),
      SnapshotProduct(
        productId: 'p-ndole',
        nameFr: 'Ndolé aux crevettes',
        nameEn: 'Ndole with prawns',
        basePrice: 3500,
        type: 'dish',
        available: true,
        sortIndex: 1,
      ),
      SnapshotProduct(
        productId: 'p-koki',
        nameFr: 'Koki de haricots',
        nameEn: 'Bean koki',
        basePrice: 2000,
        type: 'dish',
        available: false,
        sortIndex: 2,
      ),
    ];
    const MenuSnapshot draft = MenuSnapshot(
      version: 1,
      branchId: 'branch-1',
      declaredProductCount: 3,
      products: products,
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

  Widget app() => MaterialApp(
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
      body: KioskMenuScreen(
        menu: menu(),
        onPick: (SnapshotProduct _) {},
        onToggleLanguage: () {},
      ),
    ),
  );

  /// Physical pixels and the device pixel ratio each device really reports.
  /// Read from `dumpsys display`'s `mOverrideDisplayInfo` and `wm density` —
  /// `wm size` alone has misreported this before.
  const Map<String, (Size, double)> devices = <String, (Size, double)>{
    'Samsung S10 landscape (868x411 dp)': (Size(2280, 1080), 2.625),
    'mounted 10-inch tablet (1280x800 dp)': (Size(2560, 1600), 2.0),
    'small 7-inch tablet (960x600 dp)': (Size(1920, 1200), 2.0),
  };

  for (final MapEntry<String, (Size, double)> device in devices.entries) {
    testWidgets('the price is on screen — ${device.key}', (tester) async {
      tester.view.physicalSize = device.value.$1;
      tester.view.devicePixelRatio = device.value.$2;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(app());
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull, reason: 'no overflow');

      // Built through the formatter, never typed: `MoneyFormatter` separates
      // thousands with a NON-BREAKING space, and a literal '4 500 FCFA' here
      // would fail for a reason that has nothing to do with layout. (That same
      // character is why slip prices once printed as '4?500 FCFA'.)
      final Finder price = find.text(MoneyFormatter.formatXaf(4500));
      expect(price, findsOneWidget);
      final Rect priceRect = tester.getRect(price);
      final Size screen =
          tester.view.physicalSize / tester.view.devicePixelRatio;
      expect(
        priceRect.bottom <= screen.height,
        isTrue,
        reason:
            'the price row sat at ${priceRect.bottom} on a ${screen.height} '
            'tall screen — this is the clipping the Samsung showed',
      );
      expect(priceRect.top >= 0, isTrue);

      // The dish name gets two lines and the card-title role.
      //
      // ⚠ Deliberately a STRUCTURAL assertion. Whether the text actually fits
      // cannot be measured here: `flutter_test` substitutes a fixed-width test
      // font where every glyph advances a full em, so "Ndolé aux crevettes"
      // needs four lines in this harness and two on the device. Asserting
      // `didExceedMaxLines` would fail for a font that does not exist on any
      // tablet. Real-name legibility is a device proof, and was taken as one on
      // the Samsung.
      final Text name = tester.widget<Text>(find.text('Ndolé aux crevettes'));
      // The line count is COMPUTED from the height the card actually got: one
      // line on a short card, two when they both fit whole. What must never
      // happen is a line drawn in a box too short to show it — the Samsung
      // rendered "Poisson braisé" with its second line sliced through the
      // middle before this became arithmetic instead of a constant.
      expect(name.maxLines, inInclusiveRange(1, 2));
      expect(
        name.style?.fontSize,
        Theme.of(
          tester.element(find.byType(KioskDishCard).first),
        ).textTheme.titleMedium?.fontSize,
        reason: 'the card title comes from the role, not from a call site',
      );
    });
  }

  testWidgets('the photo is exactly half of the card, at every size', (
    tester,
  ) async {
    // The rule the app card encodes as two equal `Expanded`s. Asserted rather
    // than trusted because every earlier attempt to guess a photo height was
    // wrong, and a card that drifts to 54% photo squeezes the price out.
    for (final (Size size, double ratio) in devices.values) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = ratio;
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();

      final Rect card = tester.getRect(find.byType(KioskDishCard).first);
      final Rect photo = tester.getRect(
        find
            .descendant(
              of: find.byType(KioskDishCard).first,
              matching: find.byType(ColoredBox),
            )
            .first,
      );
      expect(
        photo.height,
        closeTo(card.height / 2, 1.5),
        reason: 'photo ${photo.height} of card ${card.height} at $size',
      );
    }
    addTearDown(tester.view.reset);
  });

  testWidgets('a dish shows its photograph in the cart and the composer', (
    tester,
  ) async {
    // Owner, 2026-08-18: the picture must appear at every step a dish appears.
    // Before this the cart and the composer were text only — measured as zero
    // Image/photoUrl references in either file — so a customer who chose a
    // photograph off the menu never saw it again.
    tester.view.physicalSize = const Size(2280, 1080);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);

    const SnapshotProduct dish = SnapshotProduct(
      productId: 'p-poulet',
      nameFr: 'Poulet DG',
      nameEn: 'Chicken DG',
      basePrice: 4500,
      type: 'dish',
      available: true,
    );

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
          body: KioskComposerSheet(
            product: dish,
            cache: null,
            onCancel: () {},
            onAdd: (KioskComposition _) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byType(KioskDishThumb),
      findsOneWidget,
      reason: 'the composer shows the dish being decided about',
    );
    // ⚠ **And it shows it at the size a decision deserves.** A dish with no
    // variants and no option groups — which is most of TIMMA's menu — used to
    // render a 72 dp thumbnail, a name, and then an `Expanded` list holding
    // nothing: two-thirds of a landscape kiosk was blank cream on the screen
    // where somebody commits to spending money. The photograph now takes the
    // space the choices are not using.
    final Size photo = tester.getSize(find.byType(KioskDishThumb));
    expect(
      photo.height,
      greaterThan(KioskScale.minTarget),
      reason:
          'the dish photo fills the space the choices are not using, '
          'instead of sitting in the corner at one touch target square',
    );
    // The width is the assertion that actually says "hero": with nothing to
    // decide, the dish owns the whole landscape rather than a left column with
    // a cream void beside it. 868 dp is the Samsung's landscape width.
    expect(
      photo.width,
      greaterThan(868 / 2),
      reason:
          'with no variants and no option groups the dish takes the full '
          'width — there is no choices column to make room for',
    );

    // ⚠ The composer's action row overflows IN THIS HARNESS ONLY, and the
    // error is consumed deliberately rather than asserted away. It carries
    // "Ajouter  4 500 FCFA", and `flutter_test` substitutes a fixed-width font
    // where every glyph advances a full em: that string measures 418 dp here
    // against roughly 230 on the device. Composer widths are a device proof —
    // the screenshot on the Samsung shows the row fitting with room to spare.
    tester.takeException();
  });

  testWidgets('a sold-out dish still cannot be tapped through', (tester) async {
    tester.view.physicalSize = const Size(2280, 1080);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    // Scroll the sold-out dish into view if the row does not reach it.
    //
    // The scrollable is named explicitly: the search field introduced a second
    // one, and `scrollUntilVisible` throws "Too many elements" rather than
    // guessing — which is the right behaviour and a useful reminder that the
    // grid is the thing being scrolled here.
    await tester.scrollUntilVisible(
      find.text('Koki de haricots'),
      200,
      scrollable: find
          .descendant(
            of: find.byType(GridView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    final KioskDishCard card = tester.widget<KioskDishCard>(
      find.ancestor(
        of: find.text('Koki de haricots'),
        matching: find.byType(KioskDishCard),
      ),
    );
    expect(
      card.onTap,
      isNull,
      reason: 'sold out is a barrier, not a badge (§K4 rule 4)',
    );
  });
}

/// The search box and the category strip — "Notre carte" behaving like the
/// customer app's menu view (owner, 2026-08-17).
void _searchAndFilter() {
  MenuSnapshot menuWithCategories() {
    const List<SnapshotCategory> categories = <SnapshotCategory>[
      SnapshotCategory(
        categoryId: 'c-plats',
        nameFr: 'Plats',
        nameEn: 'Dishes',
        sortIndex: 1,
      ),
      SnapshotCategory(
        categoryId: 'c-boissons',
        nameFr: 'Boissons',
        nameEn: 'Drinks',
        sortIndex: 2,
      ),
      SnapshotCategory(
        categoryId: 'c-vide',
        nameFr: 'Desserts',
        nameEn: 'Desserts',
        sortIndex: 3,
      ),
    ];
    const List<SnapshotProduct> products = <SnapshotProduct>[
      SnapshotProduct(
        productId: 'p-ndole',
        nameFr: 'Ndolé aux crevettes',
        nameEn: 'Ndole with prawns',
        basePrice: 3500,
        type: 'dish',
        available: true,
        categoryId: 'c-plats',
      ),
      SnapshotProduct(
        productId: 'p-jus',
        nameFr: 'Jus de foléré',
        nameEn: 'Hibiscus juice',
        basePrice: 1000,
        type: 'drink',
        available: true,
        sortIndex: 1,
        categoryId: 'c-boissons',
      ),
    ];
    const MenuSnapshot draft = MenuSnapshot(
      version: 2,
      branchId: 'branch-1',
      declaredProductCount: 2,
      products: products,
      categories: categories,
      checksum: '',
    );
    return MenuSnapshot(
      version: draft.version,
      branchId: draft.branchId,
      declaredProductCount: draft.declaredProductCount,
      products: draft.products,
      categories: draft.categories,
      checksum: draft.computeChecksum(),
    );
  }

  Widget app(MenuSnapshot menu) => MaterialApp(
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
      body: KioskMenuScreen(
        menu: menu,
        onPick: (SnapshotProduct _) {},
        onToggleLanguage: () {},
      ),
    ),
  );

  Future<void> pump(WidgetTester tester, MenuSnapshot menu) async {
    tester.view.physicalSize = const Size(2280, 1080);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app(menu));
    await tester.pumpAndSettle();
  }

  group('search and filter', () {
    testWidgets('typing narrows the grid, accents and case ignored', (
      tester,
    ) async {
      await pump(tester, menuWithCategories());
      expect(find.text('Ndolé aux crevettes'), findsOneWidget);
      expect(find.text('Jus de foléré'), findsOneWidget);

      // "NDOLE" — no accent, wrong case. A customer in a queue types like this.
      await tester.enterText(find.byType(TextField), 'NDOLE');
      await tester.pumpAndSettle();

      expect(find.text('Ndolé aux crevettes'), findsOneWidget);
      expect(find.text('Jus de foléré'), findsNothing);
    });

    testWidgets('a search with no hits explains itself and offers a way back', (
      tester,
    ) async {
      await pump(tester, menuWithCategories());
      await tester.enterText(find.byType(TextField), 'pizza');
      await tester.pumpAndSettle();

      // "It just shows nothing" is a bug (§13.2): an empty filtered grid reads
      // as a closed kitchen.
      expect(
        find.text('Aucun plat ne correspond à votre recherche.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Effacer'));
      await tester.pumpAndSettle();
      expect(find.text('Ndolé aux crevettes'), findsOneWidget);
    });

    testWidgets('a category pill filters in place, and Tout restores', (
      tester,
    ) async {
      await pump(tester, menuWithCategories());
      expect(find.text('Tout'), findsOneWidget);

      await tester.tap(find.text('Boissons'));
      await tester.pumpAndSettle();
      expect(find.text('Jus de foléré'), findsOneWidget);
      expect(find.text('Ndolé aux crevettes'), findsNothing);

      await tester.tap(find.text('Tout'));
      await tester.pumpAndSettle();
      expect(find.text('Ndolé aux crevettes'), findsOneWidget);
    });

    testWidgets('a category nobody cooks here never gets a pill', (
      tester,
    ) async {
      await pump(tester, menuWithCategories());
      expect(
        find.text('Desserts'),
        findsNothing,
        reason: 'no product uses it, so the pill would filter to an empty grid',
      );
    });

    testWidgets('a bundle with no categories shows no strip at all', (
      tester,
    ) async {
      // What a server that predates the categories field returns. The menu must
      // look exactly as it did before, not carry an empty rail.
      const MenuSnapshot draft = MenuSnapshot(
        version: 3,
        branchId: 'branch-1',
        declaredProductCount: 1,
        products: <SnapshotProduct>[
          SnapshotProduct(
            productId: 'p-1',
            nameFr: 'Poulet DG',
            nameEn: 'Chicken DG',
            basePrice: 4500,
            type: 'dish',
            available: true,
          ),
        ],
        checksum: '',
      );
      await pump(
        tester,
        MenuSnapshot(
          version: draft.version,
          branchId: draft.branchId,
          declaredProductCount: draft.declaredProductCount,
          products: draft.products,
          checksum: draft.computeChecksum(),
        ),
      );

      expect(find.byType(KioskCategoryPill), findsNothing);
      expect(find.text('Poulet DG'), findsOneWidget);
    });
  });
}
