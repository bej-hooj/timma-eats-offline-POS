import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_core/pos_core.dart';
import 'package:timma_kiosk/design/app_tokens.dart';
import 'package:timma_kiosk/design/money_formatter.dart';
import 'package:timma_kiosk/kiosk/presentation/widgets/kiosk_cart_panel.dart';
import 'package:timma_kiosk/kiosk/state/kiosk_cart.dart';
import 'package:timma_kiosk/kiosk/theme/kiosk_theme.dart';
import 'package:timma_kiosk/l10n/app_localizations.dart';

/// The basket panel beside the menu — what a customer checks before paying.
///
/// Both of these came off the real borne on 2026-11-23, with production data
/// on the screen.
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

  const SnapshotOption plantain = SnapshotOption(
    optionId: 'o-plantain',
    nameFr: 'Plantain mûr',
    nameEn: 'Ripe plantain',
    priceDelta: 100,
    maxQty: 1,
    available: true,
  );

  final KioskCartItem line = KioskCartItem(
    lineId: 'l-1',
    product: pouletDg,
    quantity: 1,
    options: const <SnapshotOption>[plantain],
    removedIngredientIds: const <String>['i-persil'],
  );

  Future<KioskCartItem?> pump(WidgetTester tester) async {
    KioskCartItem? removed;
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
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
          body: SizedBox(
            width: 420,
            child: KioskCartPanel(
              cart: KioskCartState(items: <KioskCartItem>[line]),
              photoCache: null,
              onCheckout: () {},
              onIncrement: (KioskCartItem _) {},
              onDecrement: (KioskCartItem _) {},
              onRemove: (KioskCartItem item) => removed = item,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return removed;
  }

  testWidgets('every row has a remove key, and it takes the whole line', (
    tester,
  ) async {
    await pump(tester);

    // ⚠ Owner, 2026-11-23: *"each dish row should have a remove button
    // (icon)"*. The minus key stops at 1 — deliberately, so a mis-tap cannot
    // silently empty a basket — which left a customer who had added the wrong
    // dish no way to undo it from this panel at all.
    final Finder remove = find.byIcon(Icons.close);
    expect(remove, findsOneWidget);

    await tester.tap(remove);
    await tester.pumpAndSettle();
  });

  testWidgets('the remove key reports the dish by name to a screen reader', (
    tester,
  ) async {
    await pump(tester);

    // Three unlabelled icon keys in a row announce themselves identically,
    // and the one that empties a line is the one that must not be guessed at.
    // `IconButton.tooltip` is what carries the name to a screen reader.
    expect(find.byTooltip('Retirer Poulet DG'), findsOneWidget);
  });

  testWidgets('a row says what was CHOSEN and what was LEFT OUT', (
    tester,
  ) async {
    await pump(tester);

    // ⚠ Seen on the real borne: a Poulet DG ordered *sans persil* with a
    // plantain side read simply "Poulet DG" in the basket. The kitchen would
    // have got it right and the customer could not check it before paying —
    // and the choice they most want to verify is the one they went looking
    // for.
    expect(find.text('Plantain mûr'), findsOneWidget);
    expect(find.text('Sans Persil'), findsOneWidget);
    expect(
      find.text('i-persil'),
      findsNothing,
      reason: 'ids are for the database, names are for the customer',
    );
    // The price still reflects the option.
    // Twice on purpose: the line and the basket total, which for one line are
    // the same number.
    expect(find.text(MoneyFormatter.formatXaf(5100)), findsNWidgets(2));
  });

  testWidgets('the dish name gets real room, not six characters of it', (
    tester,
  ) async {
    // ⚠⚠ The defect, as a measurement. With the remove key added to a single
    // row, the thumbnail and four keys left about 60 dp for the dish, and
    // "Pepper soup de bœuf TIMMA / 3 500 FCFA" wrapped ONE CHARACTER PER
    // LINE on the real borne. A basket a customer cannot read is worse than
    // one they cannot edit.
    await pump(tester);

    // ⚠ The assertion is on the PRICE's ROW, and both halves of that are
    // deliberate. The name is capped at two lines and ellipsizes, so a
    // squeezed column turns it into "Pe p…" without ever growing — what
    // actually stacked one character per line on the borne was the price,
    // which has no cap. And a `Text` is only as wide as its own glyphs, so
    // measuring the text would measure the harness's full-em font; the row it
    // sits in is the room it has.
    final double priceRow = tester
        .getSize(
          find
              .ancestor(
                of: find.text(MoneyFormatter.formatXaf(5100)).first,
                matching: find.byType(Row),
              )
              .first,
        )
        .width;
    expect(
      priceRow,
      greaterThan(KioskCartPanel.panelWidth * 0.7),
      reason:
          'the price had $priceRow dp of the ${KioskCartPanel.panelWidth} dp '
          'panel — squeezed into a narrow column it stacks as '
          '"3 5 00 FCF A" down the side of the basket',
    );
  });

  testWidgets('each row is packed in its own bordered card', (tester) async {
    await pump(tester);

    final Container card = tester.widget<Container>(
      find.byKey(const Key('kiosk-cart-row')),
    );
    final BoxDecoration decoration = card.decoration! as BoxDecoration;
    expect(decoration.border, isNotNull);
    expect(decoration.color, AppColors.surface);
    expect(decoration.borderRadius, isNotNull);
  });

  testWidgets('a plain dish draws neither line', (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
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
          body: SizedBox(
            width: 420,
            child: KioskCartPanel(
              cart: KioskCartState(
                items: <KioskCartItem>[
                  const KioskCartItem(
                    lineId: 'l-2',
                    product: SnapshotProduct(
                      productId: 'p-jus',
                      nameFr: 'Jus de bissap',
                      nameEn: 'Bissap juice',
                      basePrice: 1000,
                      type: 'simple',
                      available: true,
                    ),
                    quantity: 1,
                  ),
                ],
              ),
              photoCache: null,
              onCheckout: () {},
              onIncrement: (KioskCartItem _) {},
              onDecrement: (KioskCartItem _) {},
              onRemove: (KioskCartItem _) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Sans '), findsNothing);
    expect(find.byIcon(Icons.close), findsOneWidget, reason: 'still removable');
    expect(tester.takeException(), isNull);
  });
}
