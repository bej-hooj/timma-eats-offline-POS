import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timma_kiosk/kiosk/manager/manager_gate.dart';
import 'package:timma_kiosk/kiosk/theme/kiosk_theme.dart';
import 'package:timma_kiosk/l10n/app_localizations.dart';

/// **The one door into the manager screen must fit on the screen.**
///
/// This dialog has now overflowed twice — by 88 px, then, after a `scrollable:
/// true` that only scrolled half of it, by 77 px on the emulator, where it drew
/// *Annuler* and *Ouvrir* across its own PIN field. Both times it was found by
/// looking at a device, never by the suite, because nothing had ever rendered
/// it at a real height with a keyboard up.
///
/// So: the Samsung's real landscape geometry, and the emulator's, each with and
/// without the software keyboard. A kiosk whose manager cannot get in cannot be
/// paired to a kitchen or have its shift closed.
void main() {
  Widget host({required EdgeInsets viewInsets}) => MediaQuery(
    data: MediaQueryData(viewInsets: viewInsets),
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
      home: Builder(
        builder: (BuildContext context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              // The dialog directly, not `KioskManagerGate.unlock`: a test
              // build carries no `KIOSK_MANAGER_PIN`, so the gate opens without
              // ever showing a keypad — which is why this never had a test.
              onPressed: () => showDialog<bool>(
                context: context,
                builder: (BuildContext _) => const KioskManagerPinDialog(),
              ),
              child: const Text('ouvrir'),
            ),
          ),
        ),
      ),
    ),
  );

  /// dp, landscape, as measured on the hardware. `wm size` has lied about both;
  /// these come from `dumpsys display` + density.
  const Map<String, Size> screens = <String, Size>{
    'Samsung SM-G975F': Size(868, 411),
    'Pixel emulator': Size(997, 448),
  };

  /// A software keyboard eats a little over half a short landscape screen.
  const Map<String, double> keyboards = <String, double>{
    'clavier fermé': 0,
    'clavier ouvert': 250,
  };

  for (final MapEntry<String, Size> screen in screens.entries) {
    for (final MapEntry<String, double> keyboard in keyboards.entries) {
      testWidgets('${screen.key}, ${keyboard.key}: the PIN dialog fits', (
        WidgetTester tester,
      ) async {
        tester.view.physicalSize = screen.value * 3;
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          host(viewInsets: EdgeInsets.only(bottom: keyboard.value)),
        );
        await tester.tap(find.text('ouvrir'));
        await tester.pumpAndSettle();

        // Every control a manager needs is present…
        expect(find.text('Code responsable'), findsOneWidget);
        expect(find.byType(TextField), findsOneWidget);
        expect(find.text('Ouvrir'), findsOneWidget);
        expect(find.text('Annuler'), findsOneWidget);

        // …and nothing overflowed. `pumpAndSettle` would not have thrown for a
        // RenderFlex overflow — it paints an error stripe and carries on — so
        // the assertion has to be explicit.
        expect(
          tester.takeException(),
          isNull,
          reason: 'the dialog overflowed at ${screen.value} with '
              '${keyboard.value}dp of keyboard',
        );

        // The field is what a manager types into; it must be on screen, not
        // merely in the tree.
        final Rect field = tester.getRect(find.byType(TextField));
        final Rect visible = Rect.fromLTWH(
          0,
          0,
          screen.value.width,
          screen.value.height - keyboard.value,
        );
        expect(
          visible.contains(field.topLeft) && visible.contains(field.bottomRight),
          isTrue,
          reason: 'the PIN field was drawn off screen, or under the keyboard',
        );
      });
    }
  }
}
