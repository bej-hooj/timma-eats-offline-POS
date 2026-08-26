import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timma_kiosk/kiosk/presentation/widgets/kiosk_dish_card.dart';
import 'package:timma_kiosk/kiosk/theme/kiosk_theme.dart';
import 'package:timma_kiosk/l10n/app_localizations.dart';

/// Stage 3d — the borne's dish card draws the same meta row as the phone.
///
/// The point is not that it *looks* the same. It is that the same three rules
/// hold, each of which the app paid for on a real handset:
///
/// * a region renders **whole or not at all** — "Sud" and "Sud-Ouest" are two
///   places, so an elided origin is a wrong one;
/// * the drop order is **origin, then the chilli, never the prep window**;
/// * **one chilli whatever the level** — the card answers "is this spicy?",
///   the composer answers "how".
Widget harness({
  required double width,
  String? origin,
  int spice = 0,
  int prepMin = 10,
  int prepMax = 15,
  Locale locale = const Locale('fr'),
}) => MaterialApp(
  locale: locale,
  theme: KioskTheme.build(),
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: const <LocalizationsDelegate<Object>>[
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  home: Scaffold(
    body: Center(
      child: SizedBox(
        width: width,
        height: 320,
        child: KioskDishCard(
          name: 'Eru',
          price: '3 500 FCFA',
          soldOut: false,
          soldOutLabel: 'Épuisé',
          prepMin: prepMin,
          prepMax: prepMax,
          spiceLevel: spice,
          origin: origin,
        ),
      ),
    ),
  ),
);

void main() {
  /*
   * ⚠ 900 dp, not the kiosk card's real 320.
   *
   * The widget-test font is FIXED-WIDTH, so every string measures far wider
   * here than the real face does on a tablet — and this row's whole mechanism
   * is measurement. A "realistic" width in this harness would assert that the
   * fake font does not fit, which is true and meaningless. Widths that carry
   * a claim are the SWEEPS below, which assert the ORDER parts drop in.
   */
  testWidgets('a wide card shows the window, the region and one chilli', (
    tester,
  ) async {
    await tester.pumpWidget(harness(width: 900, origin: 'Sud-Ouest', spice: 3));
    await tester.pump();

    expect(find.text('10–15 min'), findsOneWidget);
    expect(find.text('Sud-Ouest'), findsOneWidget);
    expect(
      find.byIcon(Icons.local_fire_department_rounded),
      findsOneWidget,
      reason:
          'ONE chilli whatever the level (owner, 2026-08-26). Three flames '
          'belong on the composer, where the customer is deciding rather '
          'than scanning.',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('a house dish with no region draws no empty separator', (
    tester,
  ) async {
    await tester.pumpWidget(harness(width: 900));
    await tester.pump();

    expect(find.text('10–15 min'), findsOneWidget);
    expect(find.byIcon(Icons.local_fire_department_rounded), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('spice level 0 draws no chilli at all, not an outline one', (
    tester,
  ) async {
    await tester.pumpWidget(harness(width: 900, origin: 'Littoral'));
    await tester.pump();

    expect(find.byIcon(Icons.local_fire_department_rounded), findsNothing);
  });

  /*
   * ⚠ Every assertion below is a SWEEP, never a hardcoded width. The
   * widget-test font is fixed-width, so a string measures nothing like it does
   * on a tablet; a test that pinned "at 220 dp the origin is gone" would be
   * asserting a property of Ahem, not of the card. Narrowing until a part
   * disappears asserts the ORDER things drop in, which is the actual rule.
   */

  /// The narrowest width at which [finder] still matches, stepping down.
  Future<double?> lastWidthWith(
    WidgetTester tester,
    Finder finder, {
    double from = 1000,
    String? origin,
    int spice = 0,
  }) async {
    double? last;
    for (double w = from; w >= 60; w -= 4) {
      await tester.pumpWidget(harness(width: w, origin: origin, spice: spice));
      await tester.pump();
      if (finder.evaluate().isNotEmpty) {
        last = w;
      } else if (last != null) {
        return last;
      }
    }

    return last;
  }

  testWidgets('a narrow card drops the region rather than eliding it', (
    tester,
  ) async {
    final double? lastWithOrigin = await lastWidthWith(
      tester,
      find.text('Sud-Ouest'),
      origin: 'Sud-Ouest',
      spice: 3,
    );
    expect(lastWithOrigin, isNotNull, reason: 'the region never rendered');

    await tester.pumpWidget(
      harness(width: lastWithOrigin! - 4, origin: 'Sud-Ouest', spice: 3),
    );
    await tester.pump();

    expect(find.text('Sud-Ouest'), findsNothing);
    expect(
      find.textContaining('…'),
      findsNothing,
      reason:
          'An elided region reads as a different place. It renders whole or '
          'not at all.',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('the chilli goes before the prep window ever does', (
    tester,
  ) async {
    final double? lastWithSpice = await lastWidthWith(
      tester,
      find.byIcon(Icons.local_fire_department_rounded),
      origin: 'Sud-Ouest',
      spice: 3,
    );
    expect(lastWithSpice, isNotNull);

    // At the width where the chilli has just gone, the window is still there.
    await tester.pumpWidget(
      harness(width: lastWithSpice! - 4, origin: 'Sud-Ouest', spice: 3),
    );
    await tester.pump();

    expect(find.byIcon(Icons.local_fire_department_rounded), findsNothing);
    expect(find.byIcon(Icons.schedule_rounded), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the region goes before the chilli does', (tester) async {
    final double? lastWithOrigin = await lastWidthWith(
      tester,
      find.text('Sud-Ouest'),
      origin: 'Sud-Ouest',
      spice: 3,
    );
    final double? lastWithSpice = await lastWidthWith(
      tester,
      find.byIcon(Icons.local_fire_department_rounded),
      origin: 'Sud-Ouest',
      spice: 3,
    );

    expect(lastWithOrigin, isNotNull);
    expect(lastWithSpice, isNotNull);
    expect(
      lastWithOrigin!,
      greaterThan(lastWithSpice!),
      reason:
          'origin → chilli → never the window: the reverse of how much the '
          'customer is deciding on each.',
    );
  });

  testWidgets('the row never overflows, at any width', (tester) async {
    for (double w = 1000; w >= 60; w -= 4) {
      await tester.pumpWidget(
        harness(width: w, origin: 'Sud-Ouest', spice: 3, prepMax: 145),
      );
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'overflowed at $w dp');
    }
  });

  testWidgets('a screen reader hears everything the DISH carries', (
    tester,
  ) async {
    // ⚠ Not everything the row happened to FIT. Width is a painting
    // constraint; it is not a reason to withhold a fact from someone who
    // cannot see the card at all. Rendered narrow on purpose.
    final SemanticsHandle handle = tester.ensureSemantics();
    await tester.pumpWidget(harness(width: 90, origin: 'Sud-Ouest', spice: 3));
    await tester.pump();

    expect(
      find.bySemanticsLabel(RegExp('Sud-Ouest')),
      findsWidgets,
      reason: 'the region is dropped from the paint, never from the label',
    );
    expect(
      find.bySemanticsLabel(RegExp('épicé', caseSensitive: false)),
      findsWidgets,
    );
    handle.dispose();
  });
}
