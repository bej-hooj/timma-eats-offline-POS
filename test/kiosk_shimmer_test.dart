import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timma_kiosk/kiosk/catalog/dish_photo_cache.dart';
import 'package:timma_kiosk/kiosk/presentation/widgets/kiosk_dish_thumb.dart';
import 'package:timma_kiosk/kiosk/presentation/widgets/kiosk_shimmer.dart';

/// Owner, 2026-11-22: *"i really want the kiosk menu to be like the mobile app
/// menu view. even on the loading waving"*.
///
/// The borne's menu itself comes out of SQLite and paints instantly — there is
/// no list to wait for. What a customer DOES wait for is the photographs, and
/// until now an uncached one drew nothing at all: a hole in a menu card on a
/// machine facing the street, which reads as broken rather than as slow.
void main() {
  /// A 1x1 PNG. Real bytes, so `Image.memory` decodes rather than erroring
  /// into the fallback and passing these tests for the wrong reason.
  final Uint8List png = Uint8List.fromList(<int>[
    0x89,
    0x50,
    0x4E,
    0x47,
    0x0D,
    0x0A,
    0x1A,
    0x0A,
    0x00,
    0x00,
    0x00,
    0x0D,
    0x49,
    0x48,
    0x44,
    0x52,
    0x00,
    0x00,
    0x00,
    0x01,
    0x00,
    0x00,
    0x00,
    0x01,
    0x08,
    0x06,
    0x00,
    0x00,
    0x00,
    0x1F,
    0x15,
    0xC4,
    0x89,
    0x00,
    0x00,
    0x00,
    0x0A,
    0x49,
    0x44,
    0x41,
    0x54,
    0x78,
    0x9C,
    0x63,
    0x00,
    0x01,
    0x00,
    0x00,
    0x05,
    0x00,
    0x01,
    0x0D,
    0x0A,
    0x2D,
    0xB4,
    0x00,
    0x00,
    0x00,
    0x00,
    0x49,
    0x45,
    0x4E,
    0x44,
    0xAE,
    0x42,
    0x60,
    0x82,
  ]);

  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('kiosk-shimmer');
    addTearDown(() {
      if (dir.existsSync()) {
        dir.deleteSync(recursive: true);
      }
    });
  });

  /// A real cache with the bytes already on disk — the state a borne is in
  /// after it has pinned its menu, which is the normal state during service.
  DishPhotoCache warm(Uint8List bytes) {
    final DishPhotoCache cache = DishPhotoCache(
      directory: dir,
      allowedHost: 'cdn.timmaeats.com',
    );
    cache.fileFor(_url)!.writeAsBytesSync(bytes);
    return cache;
  }

  Widget host(Widget child, {bool reduceMotion = false}) => MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: reduceMotion),
      child: Scaffold(
        body: Center(child: SizedBox(width: 200, height: 200, child: child)),
      ),
    ),
  );

  testWidgets('a photograph still arriving shows the shimmer, not a hole', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(const KioskDishThumb(photoUrl: _url, cache: null, radius: 16)),
    );

    // ⚠ The builder is called directly rather than waited for. `flutter_test`
    // answers every network image with a 400, so the real load fails in the
    // same frame it starts — the waiting state a customer actually sees for a
    // second or two on a borne cannot be reached by pumping here, and a test
    // that pumped would be asserting the harness's timing, not the rule.
    final Image image = tester.widget<Image>(find.byType(Image));
    final Widget waiting = image.frameBuilder!(
      tester.element(find.byType(Image)),
      const SizedBox.shrink(),
      null, // no frame yet
      false,
    );
    expect(waiting, isA<AnimatedSwitcher>());
    expect(
      ((waiting as AnimatedSwitcher).child! as KioskShimmer).radius,
      16,
      reason: 'the panel has to match the card corner it is filling',
    );

    // And a cached photograph paints straight through, with no fade.
    final Widget cached = image.frameBuilder!(
      tester.element(find.byType(Image)),
      const SizedBox.shrink(),
      0,
      true, // was synchronously loaded
    );
    expect(cached, isA<SizedBox>());
  });

  testWidgets('the sweep actually moves', (tester) async {
    await tester.pumpWidget(host(const KioskShimmer(radius: 16)));
    await tester.pump();

    final Gradient? first = _gradientOf(tester);
    await tester.pump(const Duration(milliseconds: 350));
    final Gradient? later = _gradientOf(tester);

    // A static panel would pass "the shimmer is on screen" perfectly well.
    expect(first, isNotNull);
    expect(later, isNot(first));
  });

  testWidgets('a viewer who asked for less motion gets the panel, still', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(const KioskShimmer(radius: 16), reduceMotion: true),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    // ⚠ The panel stays: *something is coming here* is the information, and
    // the movement is only how fast it says so. Removing both would leave the
    // hole this exists to fill.
    expect(find.byType(KioskShimmer), findsOneWidget);
    expect(
      tester.takeException(),
      isNull,
      reason: 'a repeating controller under reduced motion must not spin on',
    );
  });

  testWidgets('a cached photograph never shimmers — it is already there', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(KioskDishThumb(photoUrl: _url, cache: warm(png), radius: 16)),
    );
    await tester.pump();

    expect(find.byType(KioskShimmer), findsNothing);
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('a dish with no photograph shows the brand panel, not a sweep', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(const KioskDishThumb(photoUrl: null, cache: null, radius: 16)),
    );
    await tester.pump();

    // Nothing is coming, so nothing should suggest it is.
    expect(find.byType(KioskShimmer), findsNothing);
    expect(find.byIcon(Icons.restaurant_menu), findsOneWidget);
  });
}

Gradient? _gradientOf(WidgetTester tester) {
  final DecoratedBox box = tester.widget<DecoratedBox>(
    find
        .descendant(
          of: find.byType(KioskShimmer),
          matching: find.byType(DecoratedBox),
        )
        .first,
  );
  return (box.decoration as BoxDecoration).gradient;
}

const String _url = 'https://cdn.timmaeats.com/catalog/ndole.webp';
