import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_core/pos_core.dart';
import 'package:timma_kiosk/kiosk/presentation/bootstrap_screen.dart';

/// A fresh install must render, not crash.
///
/// The entrypoint used to read `store.readIdentity()!`. On a tablet straight out
/// of the box — or one whose app data was cleared — that threw before `runApp`,
/// so the very first launch on new hardware showed a blank screen with nothing
/// to diagnose it by.
void main() {
  test('a fresh store has no identity — the value the old `!` crashed on', () {
    final PosStore store = SqlitePosStore.inMemory();
    addTearDown(store.close);

    expect(store.readIdentity(), isNull);
  });

  testWidgets('the unprovisioned kiosk explains itself, in French', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(2400, 1600);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const KioskBootstrapApp(state: KioskBootstrapState.unprovisioned),
    );
    await tester.pumpAndSettle();

    expect(find.text('Borne non configurée'), findsOneWidget);
    expect(find.textContaining('rattachée à un restaurant'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a lost collection secret says so rather than trading on', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(2400, 1600);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const KioskBootstrapApp(state: KioskBootstrapState.secretLost),
    );
    await tester.pumpAndSettle();

    expect(find.text('Configuration à restaurer'), findsOneWidget);
    expect(
      find.textContaining('ne peuvent plus être vérifiés'),
      findsOneWidget,
      reason:
          'the consequence is named: slips already printed are now '
          'unverifiable, which is why the kiosk stops instead of minting a new '
          'secret',
    );
  });

  testWidgets('both states lay out at real tablet widths without overflowing', (
    tester,
  ) async {
    // The KDS twin of this screen provably overflowed by 14 px at 1280×800 with
    // the French copy. Same guard here, at every width a mounted tablet ships
    // with, for both messages.
    addTearDown(tester.view.reset);
    for (final KioskBootstrapState state in KioskBootstrapState.values) {
      for (final Size size in <Size>[
        const Size(2400, 1600),
        const Size(1920, 1200),
        const Size(1280, 800),
      ]) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 2;
        await tester.pumpWidget(KioskBootstrapApp(state: state));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '$state at $size');
      }
    }
  });
}
