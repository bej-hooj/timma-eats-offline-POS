import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_cloud/pos_cloud.dart';
import 'package:pos_core/pos_core.dart';
import 'package:timma_kiosk/kiosk/catalog/dish_photo_cache.dart';
import 'package:timma_kiosk/kiosk/presentation/menu_screen.dart';
import 'package:timma_kiosk/kiosk/presentation/widgets/kiosk_week_menu_sheet.dart';
import 'package:timma_kiosk/kiosk/theme/kiosk_theme.dart';
import 'package:timma_kiosk/l10n/app_localizations.dart';

/// **Online it loads the dashboard's catalogue; offline it keeps showing it.**
///
/// That sentence is the owner's requirement and this file is its proof. The
/// interesting half is the second one: a menu is not offline-capable because it
/// was downloaded once, it is offline-capable because the pictures are on the
/// tablet's own disk and the widget reads them from there.
void main() {
  late Directory dir;
  const String host = 'abcdefgh.supabase.co';
  final String photoUrl =
      'https://$host/storage/v1/object/public/catalog/poulet.jpg';

  /// A 1×1 PNG — real bytes, so `Image.memory` genuinely decodes it rather
  /// than erroring straight into the fallback and passing for the wrong reason.
  final Uint8List png = Uint8List.fromList(<int>[
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
    0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
    0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
    0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
    0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
    0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
    0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
    0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
    0x42, 0x60, 0x82,
  ]);

  setUp(() => dir = Directory.systemTemp.createTempSync('offline_menu'));
  tearDown(() {
    if (dir.existsSync()) {
      dir.deleteSync(recursive: true);
    }
  });

  MenuSnapshot menuWithPhoto() {
    final MenuSnapshot draft = MenuSnapshot(
      version: 7,
      branchId: 'branch-1',
      declaredProductCount: 1,
      products: <SnapshotProduct>[
        SnapshotProduct(
          productId: 'p-poulet',
          nameFr: 'Poulet DG',
          nameEn: 'Chicken DG',
          basePrice: 4500,
          type: 'dish',
          available: true,
          photoUrl: photoUrl,
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

  Widget app(DishPhotoCache? cache, {Widget? body}) => MaterialApp(
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
      body:
          body ??
          KioskMenuScreen(
            menu: menuWithPhoto(),
            photoCache: cache,
            onPick: (SnapshotProduct _) {},
            onToggleLanguage: () {},
          ),
    ),
  );

  testWidgets('the week menu renders a cached photo offline', (tester) async {
    final cache = DishPhotoCache(directory: dir, allowedHost: host);
    final file = cache.fileFor(photoUrl)!;
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(png);

    await tester.pumpWidget(
      app(
        cache,
        body: KioskWeekMenuSheet(
          menu: menuWithPhoto(),
          dayMenu: KioskDayMenu.fromJson(const {}),
          today: DateTime(2026, 11, 25),
          photoCache: cache,
        ),
      ),
    );
    expect(tester.widget<Image>(find.byType(Image)).image, isA<MemoryImage>());
  });

  testWidgets('a cached dish photo renders with NO network at all', (
    tester,
  ) async {
    // The photo is on disk, exactly as the warming pass would have left it.
    final DishPhotoCache cache = DishPhotoCache(
      directory: dir,
      allowedHost: host,
    );
    final File file = cache.fileFor(photoUrl)!;
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(png);

    tester.view.physicalSize = const Size(2280, 1080);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);

    // No HTTP override is installed, so any attempt to reach the network in
    // this test throws — which is precisely the offline condition under test.
    await tester.pumpWidget(app(cache));
    await tester.pumpAndSettle();

    expect(
      find.byType(Image),
      findsOneWidget,
      reason: 'the dish photograph must come from the tablet, not the line',
    );
    final Image image = tester.widget<Image>(find.byType(Image));
    expect(
      image.image,
      isA<MemoryImage>(),
      reason: 'MemoryImage means disk bytes; NetworkImage would mean a request',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('an uncached photo falls back without reaching for the network '
      'when the cache refuses its URL', (tester) async {
    // A menu row carrying a plaintext or foreign URL must not become an HTTP
    // request just because the cache happens to be empty. The refusal has to
    // hold on the miss path too, or it holds only until the first cache miss.
    final DishPhotoCache cache = DishPhotoCache(
      directory: dir,
      allowedHost: 'other.supabase.co',
    );

    tester.view.physicalSize = const Size(2280, 1080);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(app(cache));
    await tester.pumpAndSettle();

    expect(find.byType(Image), findsNothing, reason: 'no request was made');
    expect(tester.takeException(), isNull);
  });

  testWidgets('with no cache configured the menu still sells', (tester) async {
    tester.view.physicalSize = const Size(2280, 1080);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(app(null));
    await tester.pumpAndSettle();

    // The dish, its price and its card are all there; only the photograph is
    // a brand panel. An unprovisioned kiosk is a working kiosk.
    expect(find.text('Poulet DG'), findsOneWidget);
    expect(find.byIcon(Icons.restaurant_menu), findsOneWidget);
  });
}
