import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:pos_cloud/pos_cloud.dart';
import 'package:pos_core/pos_core.dart';
import 'package:timma_kiosk/kiosk/presentation/menu_screen.dart';
import 'package:timma_kiosk/kiosk/presentation/widgets/kiosk_mobile_money_panel.dart';
import 'package:timma_kiosk/kiosk/presentation/widgets/kiosk_week_menu_sheet.dart';
import 'package:timma_kiosk/kiosk/theme/kiosk_theme.dart';
import 'package:timma_kiosk/l10n/app_localizations.dart';

/// ECOSYSTEM §25.4–§25.5 on the borne.
void main() {
  setUpAll(() => initializeDateFormatting('fr'));

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
    ];
    const MenuSnapshot draft = MenuSnapshot(
      version: 1,
      branchId: 'branch-1',
      declaredProductCount: 2,
      products: products,
      checksum: '',
    );
    return MenuSnapshot(
      version: 1,
      branchId: 'branch-1',
      declaredProductCount: 2,
      products: products,
      checksum: draft.computeChecksum(),
    );
  }

  Widget host(Widget child, {Locale locale = const Locale('fr')}) =>
      MaterialApp(
        locale: locale,
        theme: KioskTheme.build(),
        localizationsDelegates: const <LocalizationsDelegate<Object>>[
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: child),
      );

  Future<void> borneSize(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.75;
    addTearDown(tester.view.reset);
  }

  testWidgets('a dish not cooked today is not drawn; the week button shows', (
    WidgetTester tester,
  ) async {
    await borneSize(tester);
    bool weekOpened = false;
    await tester.pumpWidget(
      host(
        KioskMenuScreen(
          menu: menu(),
          onPick: (_) {},
          onToggleLanguage: () {},
          isOnToday: (String id) => id == 'p-ndole',
          restrictedDate: DateTime(2026, 11, 25),
          onShowWeek: () => weekOpened = true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Ndolé aux crevettes'), findsWidgets);
    expect(find.text('Poulet DG'), findsNothing);
    expect(find.text('Menu du jour —\nmercredi 25 novembre'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey<String>('kiosk-week-menu')));
    expect(weekOpened, isTrue);
  });

  testWidgets('no schedule: every dish (no handler given: no button)', (
    WidgetTester tester,
  ) async {
    await borneSize(tester);
    await tester.pumpWidget(
      host(
        KioskMenuScreen(menu: menu(), onPick: (_) {}, onToggleLanguage: () {}),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Poulet DG'), findsWidgets);
    expect(find.text('Notre carte'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('kiosk-week-menu')), findsNothing);
  });

  testWidgets('the restricted heading formats the date in English', (
    tester,
  ) async {
    await borneSize(tester);
    await tester.pumpWidget(
      host(
        KioskMenuScreen(
          menu: menu(),
          onPick: (_) {},
          onToggleLanguage: () {},
          restrictedDate: DateTime(2026, 11, 25),
        ),
        locale: const Locale('en'),
      ),
    );
    expect(find.text('Daily menu —\nWednesday, November 25'), findsOneWidget);
  });

  testWidgets('the week view lists each dish with its days (fail-open days)', (
    WidgetTester tester,
  ) async {
    await borneSize(tester);
    final DateTime today = DateTime(2026, 11, 25);
    final KioskDayMenu days = KioskDayMenu.fromJson(<String, Object?>{
      'enforced': true,
      'days': <Object?>[
        for (int i = 0; i < 7; i++)
          <String, Object?>{
            'date': KioskWeekMenuSheet.isoDate(today.add(Duration(days: i))),
            'product_ids': <Object?>['p-ndole'],
          },
      ],
    });
    await tester.pumpWidget(
      host(KioskWeekMenuSheet(menu: menu(), dayMenu: days, today: today)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Tous les jours'), findsOneWidget);
    expect(find.text('Pas cette semaine'), findsOneWidget);
    expect(find.byIcon(Icons.restaurant_menu), findsNWidgets(2));
  });

  testWidgets('the merchant panel shows each code and the holder', (
    WidgetTester tester,
  ) async {
    await borneSize(tester);
    await tester.pumpWidget(
      host(
        const KioskMobileMoneyPanel(
          foreground: Colors.black,
          codes: <KioskPaymentCode>[
            KioskPaymentCode(
              provider: KioskPaymentProvider.mtnMomo,
              code: '123456',
              holderName: 'TIMMA Eats',
            ),
          ],
        ),
      ),
    );
    expect(find.textContaining('123456'), findsOneWidget);
    expect(find.textContaining('MTN Mobile Money'), findsOneWidget);
    expect(find.textContaining('TIMMA Eats'), findsOneWidget);
  });
}
