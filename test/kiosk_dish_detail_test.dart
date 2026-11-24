import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_core/pos_core.dart';
import 'package:timma_kiosk/l10n/app_localizations.dart';
import 'package:timma_kiosk/kiosk/presentation/composer_sheet.dart';
import 'package:timma_kiosk/kiosk/theme/kiosk_theme.dart';

/// The dish page says what the dish IS.
///
/// Owner, 2026-11-22: *"when on open a view of a dish, he should see the
/// allergy and all informations about the dish just like on mobile app … even
/// description … ingredients too … same little icons on ingredients"*.
///
/// Until the bundle carried them this screen could not draw any of it: the
/// borne had a name, a price and a photograph. The fields arrived with
/// migration `20261122180000`; these tests are what stops them quietly
/// disappearing again.
void main() {
  /// Ndolé as production actually has it — a description, a tag, six
  /// ingredients with their marks, three of which carry an allergen, and one
  /// the kitchen allows a customer to leave out.
  const SnapshotProduct ndole = SnapshotProduct(
    productId: 'p-ndole',
    nameFr: 'Ndolé',
    nameEn: 'Ndole',
    basePrice: 4500,
    type: 'simple',
    available: true,
    spiceLevel: 1,
    prepMin: 10,
    prepMax: 15,
    originFr: 'Littoral',
    originEn: 'Littoral',
    descriptionFr:
        'Feuilles de ndolé mijotées aux arachides, avec bœuf, poisson fumé '
        'et crevettes, à l\'huile de palme.',
    descriptionEn: 'Bitterleaf simmered with groundnuts, beef and crayfish.',
    tags: <String>['new'],
    ingredients: <SnapshotIngredient>[
      SnapshotIngredient(
        ingredientId: 'i-1',
        nameFr: 'Feuilles de ndolé',
        nameEn: 'Ndolé leaves',
        icon: '🥬',
      ),
      SnapshotIngredient(
        ingredientId: 'i-2',
        nameFr: 'Arachides',
        nameEn: 'Peanuts',
        icon: '🥜',
        allergenTags: <String>['peanuts'],
      ),
      SnapshotIngredient(
        ingredientId: 'i-3',
        nameFr: 'Poisson fumé',
        nameEn: 'Smoked fish',
        icon: '🐟',
        allergenTags: <String>['fish'],
      ),
      SnapshotIngredient(
        ingredientId: 'i-4',
        nameFr: 'Crevettes',
        nameEn: 'Shrimp',
        icon: '🦐',
        allergenTags: <String>['crustaceans'],
      ),
      SnapshotIngredient(
        ingredientId: 'i-5',
        nameFr: 'Huile de palme',
        nameEn: 'Palm oil',
        icon: '🧴',
        removable: true,
      ),
    ],
  );

  Future<void> pump(
    WidgetTester tester,
    SnapshotProduct dish, {
    Size size = const Size(1920, 996),
    double ratio = 1.75,
  }) async {
    // The GM92 the borne runs on: 1920 x 1080 px at 280 dpi.
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = ratio;
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
  }

  testWidgets('the page carries description, ingredients and allergens', (
    tester,
  ) async {
    await pump(tester, ndole);

    expect(
      find.textContaining('Feuilles de ndolé mijotées'),
      findsOneWidget,
      reason: 'a customer deciding should be told what the dish is',
    );
    for (final String ingredient in <String>[
      'Feuilles de ndolé',
      'Poisson fumé',
      'Crevettes',
      'Huile de palme',
    ]) {
      expect(find.text(ingredient), findsOneWidget, reason: ingredient);
    }
    // ⚠ "Arachides" appears TWICE on purpose — once as an ingredient and once
    // in the allergen block. A customer scanning the ingredient list and a
    // customer looking for the warning are two different people, and the one
    // who is allergic must be served by whichever they read first.
    expect(find.text('Arachides'), findsNWidgets(2));
    // The operator-chosen marks reach the screen.
    expect(find.text('🥜'), findsOneWidget);

    // ⚠ The allergens, as WORDS. The tag in the database is `peanuts`; a
    // French customer must never be shown that.
    expect(find.text('Arachides'), findsWidgets);
    expect(find.text('Poisson'), findsOneWidget);
    expect(find.text('Crustacés'), findsOneWidget);
    expect(
      find.text('peanuts'),
      findsNothing,
      reason: 'identifiers are for the database, words are for the customer',
    );
  });

  testWidgets('the allergen block is announced to a screen reader', (
    tester,
  ) async {
    final SemanticsHandle handle = tester.ensureSemantics();
    await pump(tester, ndole);

    // ⚠ Colour and an icon are not enough: this is the one list on the borne
    // where being missed has a consequence worse than a wrong order.
    expect(
      find.bySemanticsLabel(RegExp('Contient.*Arachides.*')),
      findsOneWidget,
    );
    handle.dispose();
  });

  testWidgets('a removable ingredient can be left out, and only that one', (
    tester,
  ) async {
    KioskComposition? added;
    tester.view.physicalSize = const Size(1920, 996);
    tester.view.devicePixelRatio = 1.75;
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
          body: KioskComposerSheet(
            product: ndole,
            cache: null,
            onCancel: () {},
            onAdd: (KioskComposition c) => added = c,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // ⚠ Only the ingredient the KITCHEN marked removable is a control. Palm
    // oil is; ndolé leaves are not — a customer cannot order a ndolé without
    // ndolé, and letting them tap it would send the kitchen a ticket it has to
    // refuse at the counter.
    await tester.ensureVisible(find.text('Feuilles de ndolé'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Feuilles de ndolé'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(
      find.text('Sans Feuilles de ndolé'),
      findsNothing,
      reason: 'a non-removable ingredient is not a control',
    );

    await tester.ensureVisible(find.text('Huile de palme'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Huile de palme'));
    await tester.pumpAndSettle();
    expect(find.text('Sans Huile de palme'), findsOneWidget);
    expect(find.text('Huile de palme'), findsNothing);

    await tester.ensureVisible(find.textContaining('Ajouter'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Ajouter'));
    await tester.pumpAndSettle();
    expect(
      added?.removedIngredientIds,
      <String>['i-5'],
      reason:
          'the removal has to leave the screen or the kitchen never hears '
          'about it',
    );

    // Tapping again puts it back: a mis-tap must be undoable without closing
    // the dish.
    await tester.ensureVisible(find.text('Sans Huile de palme'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sans Huile de palme'));
    await tester.pumpAndSettle();
    expect(find.text('Huile de palme'), findsOneWidget);
  });

  testWidgets('a dish with nothing to say still lays out cleanly', (
    tester,
  ) async {
    // Half the fields are optional, and a bundle pinned before this migration
    // has none of them. The page must not draw empty headings or blank blocks.
    const SnapshotProduct bare = SnapshotProduct(
      productId: 'p-bare',
      nameFr: 'Riz TIMMA',
      nameEn: 'TIMMA rice',
      basePrice: 2000,
      type: 'simple',
      available: true,
    );
    await pump(tester, bare);

    expect(find.text('INGRÉDIENTS'), findsNothing);
    expect(find.text('Contient'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  /// Owner, 2026-11-24: *"the responsiveness of the borne app is not fully
  /// done — in portrait some views were bad"*. The dish page is a two-column
  /// layout, and a column layout on a tall narrow screen is where that shows.
  for (final (String name, Size size, double ratio) in <(String, Size, double)>[
    ('portrait 1080x1920', Size(1080, 1920), 1.0),
    ('portrait tablet 800x1280', Size(1600, 2560), 2.0),
    ('television 1080p', Size(1920, 1080), 1.0),
    ('television 4K', Size(3840, 2160), 1.0),
    ('budget 7-inch 640x400', Size(1280, 800), 2.0),
  ]) {
    testWidgets('the dish page holds together — $name', (tester) async {
      await pump(tester, ndole, size: size, ratio: ratio);

      expect(tester.takeException(), isNull, reason: 'overflow at $name');

      // Everything a customer must be able to see is drawn.
      expect(find.text('Ndolé'), findsWidgets, reason: name);
      expect(find.text('Arachides'), findsWidgets, reason: name);

      // ⚠ And the ACTION is inside the viewport, with no scrolling. The
      // ingredients and the allergen block live in a scroll area and may
      // legitimately sit below the fold — that is what the scrollbar and the
      // edge fade are for — but a customer who cannot reach *Ajouter* cannot
      // order at all. "The widget exists" is what let a clipped price ship.
      final double h = size.height / ratio;
      final double w = size.width / ratio;
      for (final Finder f in <Finder>[
        find.text('Ndolé'),
        find.textContaining('Ajouter'),
      ]) {
        expect(f, findsWidgets, reason: name);
        final Rect r = tester.getRect(f.first);
        expect(r.bottom, lessThanOrEqualTo(h + 0.5), reason: '$name bottom');
        expect(r.right, lessThanOrEqualTo(w + 0.5), reason: '$name right');
        expect(r.top, greaterThanOrEqualTo(-0.5), reason: '$name top');
      }
    });
  }

  testWidgets('nothing overflows at the borne\'s real size, in French', (
    tester,
  ) async {
    // This repo has shipped four French overflow defects found only on
    // hardware. French is the longer language and the GM92 is the real board.
    await pump(tester, ndole);
    expect(tester.takeException(), isNull);
  });
}
