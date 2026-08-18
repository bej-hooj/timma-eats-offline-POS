import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timma_kiosk/kiosk/presentation/attract_screen.dart';
import 'package:timma_kiosk/kiosk/theme/kiosk_theme.dart';
import 'package:timma_kiosk/l10n/app_localizations.dart';

/// **The first thing a customer ever sees must not have a hazard stripe on it.**
///
/// The attract column sizes itself off the height it is given, which is right —
/// and it is exactly why it broke when something else took the height away.
/// Long-pressing the screen opens the manager keypad, the software keyboard
/// took 263 dp of a 448 dp landscape screen, the Scaffold resized the body
/// underneath the dialog, and this column overflowed by 77 px in yellow and
/// black behind it. Measured on the emulator; it had already overflowed once
/// before, by 91 px, for the unrelated reason that it used to be sized off
/// constants.
///
/// The screen has no text field of its own, so the fix is that it does not
/// resize at all — and this pins the geometry either way.
void main() {
  Widget host({required Size screen, required double keyboard}) => MediaQuery(
    data: MediaQueryData(
      size: screen,
      viewInsets: EdgeInsets.only(bottom: keyboard),
    ),
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
      // ⚠ **Resizing is left ON here on purpose.** `KioskApp` turns it off for
      // this stage, and a test that copied that would prove nothing: the column
      // would get the whole screen and could not overflow whatever it did. This
      // hands it the 185 dp the keypad actually left, which is the geometry
      // that produced the stripe.
      home: Scaffold(
        body: SafeArea(
          child: KioskAttractScreen(onStart: () {}, onManager: () {}),
        ),
      ),
    ),
  );

  const Map<String, Size> screens = <String, Size>{
    'Samsung SM-G975F': Size(868, 411),
    'Pixel emulator': Size(997, 448),
  };

  for (final MapEntry<String, Size> screen in screens.entries) {
    testWidgets('${screen.key}: the attract screen survives the keypad', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = screen.value * 3;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      // 263 dp is what the numeric keypad actually took on the emulator.
      await tester.pumpWidget(host(screen: screen.value, keyboard: 263));
      await tester.pump();

      expect(
        tester.takeException(),
        isNull,
        reason: 'the attract screen overflowed with the manager keypad open',
      );
      // The invitation to touch is the one thing that must never be clipped.
      expect(find.text('Touchez l\'écran pour commencer'), findsOneWidget);
    });
  }
}
