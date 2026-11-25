import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_core/pos_core.dart';
import 'package:timma_kiosk/kiosk/manager/manager_gate.dart';
import 'package:timma_kiosk/kiosk/manager/manager_screen.dart';
import 'package:timma_kiosk/kiosk/state/kiosk_session.dart';
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
          // As `KioskApp` does for this stage: the screen the dialog opens
          // over has no field of its own, and shrinking it for someone else's
          // keypad is what put a hazard stripe behind this dialog
          // (`kiosk_attract_layout_test.dart`).
          resizeToAvoidBottomInset: false,
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

  testWidgets('quarantined uploads require a manager PIN and confirmation', (
    WidgetTester tester,
  ) async {
    final store = SqlitePosStore.inMemory();
    addTearDown(store.close);
    const identity = PosDeviceIdentity(
      deviceId: 'borne-test',
      branchId: 'branch-test',
      role: PosDeviceRole.kiosk,
      label: 'Borne test',
    );
    store.appendEnvelope(
      OutboxEnvelope(
        deviceId: identity.deviceId,
        seq: 1,
        kind: EnvelopeKind.transition,
        destination: EnvelopeDestination.cloud,
        subject: 'test-ticket',
        payload: const <String, Object?>{},
        createdAt: DateTime.utc(2026, 11, 25),
        state: EnvelopeState.quarantined,
      ),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          kioskEngineProvider.overrideWithValue(
            PosEngine(store: store, identity: identity),
          ),
        ],
        child: MaterialApp(
          locale: const Locale('fr'),
          theme: KioskTheme.build(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const KioskManagerScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final action = find.text('Relancer les envois bloqués');
    if (KioskManagerGate.isUnset) {
      expect(action, findsNothing);
      return;
    }
    expect(action, findsOneWidget);
    await tester.ensureVisible(action);
    await tester.tap(action);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();
    expect(store.outboxCounts().quarantined, 1);

    await tester.tap(action);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Relancer'));
    await tester.pumpAndSettle();
    expect(store.outboxCounts().quarantined, 0);
    expect(store.outboxCounts().pending, 1);
    expect(find.text('Un envoi remis en file.'), findsOneWidget);
  });

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

        // Every control a manager needs is present. The title is the one thing
        // allowed to go when the keypad leaves no room — the field is
        // autofocused and the screen behind it is unambiguous.
        expect(find.byType(TextField), findsOneWidget);
        expect(find.text('Ouvrir'), findsOneWidget);
        expect(find.text('Annuler'), findsOneWidget);
        if (keyboard.value == 0) {
          expect(find.text('Code responsable'), findsOneWidget);
        }

        // …and nothing overflowed. `pumpAndSettle` would not have thrown for a
        // RenderFlex overflow — it paints an error stripe and carries on — so
        // the assertion has to be explicit.
        expect(
          tester.takeException(),
          isNull,
          reason:
              'the dialog overflowed at ${screen.value} with '
              '${keyboard.value}dp of keyboard',
        );

        // ⚠ **On screen, not merely in the tree, and not merely scrollable.**
        // The version before this one passed every assertion above while
        // drawing *Annuler* and *Ouvrir* below the fold of its own scroll view:
        // legal, no overflow, and a manager staring at a PIN dialog with no
        // visible way to confirm it.
        final Rect visible = Rect.fromLTWH(
          0,
          0,
          screen.value.width,
          screen.value.height - keyboard.value,
        );
        bool fullyVisible(Finder finder) {
          final Rect r = tester.getRect(finder);
          return visible.contains(r.topLeft) && visible.contains(r.bottomRight);
        }

        for (final Finder control in <Finder>[
          find.byType(TextField),
          find.widgetWithText(FilledButton, 'Ouvrir'),
          find.widgetWithText(TextButton, 'Annuler'),
        ]) {
          expect(
            fullyVisible(control),
            isTrue,
            reason:
                'a control was drawn off screen or under the keyboard: '
                '${tester.getRect(control)} outside $visible',
          );
        }
      });
    }
  }
}
