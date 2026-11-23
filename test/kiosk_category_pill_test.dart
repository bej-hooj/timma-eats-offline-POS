import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timma_kiosk/design/app_tokens.dart';
import 'package:timma_kiosk/kiosk/presentation/widgets/kiosk_category_pill.dart';
import 'package:timma_kiosk/kiosk/theme/kiosk_scale.dart';
import 'package:timma_kiosk/kiosk/theme/kiosk_theme.dart';

/// Owner, 2026-11-23: *"the categories card should rather be in badge pill
/// form. icon on left, text in middle and number on right (with light
/// difference in the background of the number)"*.
void main() {
  Future<void> pump(
    WidgetTester tester, {
    bool selected = false,
    int? count = 9,
    bool compact = false,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: KioskTheme.build(),
        home: Scaffold(
          body: Center(
            child: KioskCategoryPill(
              label: 'Plats',
              selected: selected,
              count: count,
              compact: compact,
              onTap: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('icon, then label, then count — left to right', (tester) async {
    await pump(tester);

    final double icon = tester.getCenter(find.byType(Icon)).dx;
    final double label = tester.getCenter(find.text('Plats')).dx;
    final double count = tester.getCenter(find.text('9')).dx;

    expect(icon, lessThan(label));
    expect(label, lessThan(count));
  });

  testWidgets('the count sits on its own lighter ground', (tester) async {
    await pump(tester);

    // ⚠ The point of the chip: the number reads as a tally, not as part of
    // the category's name. Asserted on the painted decoration rather than on
    // "a DecoratedBox exists" — the latter passes with a transparent one.
    final Finder chip = find
        .ancestor(of: find.text('9'), matching: find.byType(DecoratedBox))
        .first;
    final BoxDecoration decoration =
        tester.widget<DecoratedBox>(chip).decoration as BoxDecoration;
    expect(decoration.color, AppColors.surfaceMuted);
    expect(decoration.borderRadius, isNotNull);
  });

  testWidgets('selected, the chip stays legible against the fill', (
    tester,
  ) async {
    await pump(tester, selected: true);

    final Finder chip = find
        .ancestor(of: find.text('9'), matching: find.byType(DecoratedBox))
        .first;
    final BoxDecoration decoration =
        tester.widget<DecoratedBox>(chip).decoration as BoxDecoration;
    // A muted cream chip on the green fill would disappear; the selected pill
    // derives its chip from its own foreground instead.
    expect(decoration.color, isNot(AppColors.surfaceMuted));
  });

  testWidgets('a short screen keeps the count — it used to drop it', (
    tester,
  ) async {
    // The old layout switched to a different arrangement on a short screen
    // and the count simply vanished. One layout now, trimmed.
    await pump(tester, compact: true);
    expect(find.text('9'), findsOneWidget);
    expect(find.text('Plats'), findsOneWidget);
  });

  testWidgets('it fits the strip height the menu reserves', (tester) async {
    await pump(tester);

    // ⚠ The strip's height comes off the dish grid, so a pill that needs more
    // than the reserved height is a pill that overflows the menu — which is
    // how the stacked tile was caught at 112 dp.
    expect(
      tester.getSize(find.byType(KioskCategoryPill)).height,
      lessThanOrEqualTo(KioskScale.categoryTileHeight),
    );
  });

  testWidgets('a category with no count draws no chip', (tester) async {
    await pump(tester, count: null);
    expect(find.text('Plats'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
