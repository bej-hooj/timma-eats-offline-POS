import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_core/pos_core.dart';
import 'package:timma_kiosk/kiosk/presentation/cart_screen.dart';
import 'package:timma_kiosk/kiosk/state/kiosk_cart.dart';
import 'package:timma_kiosk/kiosk/theme/kiosk_theme.dart';
import 'package:timma_kiosk/l10n/app_localizations.dart';

/// Owner, 2026-11-24: *"all the KDS and borne app should be 100% responsive
/// for all types of screens… ALL of them and well good looking"*, and *"in
/// portrait some views were bad"*.
///
/// The basket is the screen a customer is standing at with their money out.
void main() {
  const SnapshotProduct pouletDg = SnapshotProduct(
    productId: 'p-poulet',
    nameFr: 'Poulet DG',
    nameEn: 'Chicken DG',
    basePrice: 5000,
    type: 'composed',
    available: true,
    ingredients: <SnapshotIngredient>[
      SnapshotIngredient(
        ingredientId: 'i-persil',
        nameFr: 'Persil',
        nameEn: 'Parsley',
        icon: '🌿',
        removable: true,
      ),
    ],
  );

  const SnapshotProduct longName = SnapshotProduct(
    productId: 'p-pepper',
    nameFr: 'Pepper soup de bœuf TIMMA',
    nameEn: 'TIMMA beef pepper soup',
    basePrice: 3500,
    type: 'simple',
    available: true,
  );

  final KioskCartState cart = KioskCartState(
    items: <KioskCartItem>[
      const KioskCartItem(
        lineId: 'l-1',
        product: pouletDg,
        quantity: 2,
        options: <SnapshotOption>[
          SnapshotOption(
            optionId: 'o-plantain',
            nameFr: 'Plantain mûr',
            nameEn: 'Ripe plantain',
            priceDelta: 100,
            maxQty: 1,
            available: true,
          ),
        ],
        removedIngredientIds: <String>['i-persil'],
      ),
      const KioskCartItem(lineId: 'l-2', product: longName, quantity: 1),
    ],
  );

  for (final (String name, Size size, double ratio, double scale)
      in <(String, Size, double, double)>[
        ('borne landscape 1097 dp', Size(1920, 1080), 1.75, 1.0),
        ('portrait 1080x1920', Size(1080, 1920), 1.0, 1.0),
        ('portrait tablet 800x1280', Size(1600, 2560), 2.0, 1.0),
        ('television 1080p', Size(1920, 1080), 1.0, 1.0),
        ('television 4K', Size(3840, 2160), 1.0, 1.0),
        ('budget 7-inch 640x400', Size(1280, 800), 2.0, 1.0),
        ('Samsung at text scale 1.3', Size(2280, 1080), 2.625, 1.3),
      ]) {
    testWidgets('the basket holds together — $name', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = ratio;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: MaterialApp(
            locale: const Locale('fr'),
            theme: KioskTheme.build(),
            localizationsDelegates: const <LocalizationsDelegate<Object>>[
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            home: KioskCartScreen(
              cart: cart,
              cache: null,
              onQuantity: (String _, int _) {},
              onRemove: (String _) {},
              onConfirm: () {},
              onKeepBrowsing: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull, reason: 'overflow at $name');

      // ⚠ The one control a customer cannot do without, inside the viewport
      // and not merely present. A basket they cannot confirm is a sale lost
      // while they are standing there.
      final double h = size.height / ratio;
      final double w = size.width / ratio;
      final Finder confirm = find.textContaining('Commander');
      expect(confirm, findsWidgets, reason: name);
      final Rect r = tester.getRect(confirm.first);
      expect(r.bottom, lessThanOrEqualTo(h + 0.5), reason: '$name bottom');
      expect(r.right, lessThanOrEqualTo(w + 0.5), reason: '$name right');
      expect(r.top, greaterThanOrEqualTo(-0.5), reason: '$name top');

      // And the dishes are legible, not one character per line.
      expect(find.text('Poulet DG'), findsWidgets, reason: name);
      expect(
        tester.getSize(find.text('Poulet DG').first).height,
        lessThan(90),
        reason: 'the dish name stacked at $name',
      );
    });
  }
}
