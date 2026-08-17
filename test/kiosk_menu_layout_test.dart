import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_core/pos_core.dart';
import 'package:timma_kiosk/design/money_formatter.dart';
import 'package:timma_kiosk/kiosk/presentation/menu_screen.dart';
import 'package:timma_kiosk/kiosk/presentation/widgets/kiosk_dish_card.dart';
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
      expect(name.maxLines, 2);
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

  testWidgets('a sold-out dish still cannot be tapped through', (tester) async {
    tester.view.physicalSize = const Size(2280, 1080);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    // Scroll the sold-out dish into view if the row does not reach it.
    await tester.scrollUntilVisible(find.text('Koki de haricots'), 200);
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
