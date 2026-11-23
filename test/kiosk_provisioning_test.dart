import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_core/pos_core.dart';
import 'package:timma_kiosk/kiosk/hub/dev_provisioning.dart';

/// What decides whether a borne can sell at all.
///
/// ⚠ The restaurant opens 2026-11-24 on a **release** build, and until today a
/// release build could not sell: the identity was gated on `kDebugMode`,
/// `main()` has no provisioning flow, so a release borne found no identity and
/// showed the unprovisioned screen. These are the three properties that gate
/// was conflated with — each of which still holds on its own.
void main() {
  late PosStore store;

  setUp(() => store = SqlitePosStore.inMemory());
  tearDown(() => store.close());

  const PosDeviceIdentity live = PosDeviceIdentity(
    deviceId: 'borne-gm92',
    branchId: '10000000-0000-4000-8000-000000000001',
    role: PosDeviceRole.kiosk,
    label: 'Borne entrée',
  );

  test('a build told nothing invents nothing', () {
    // This suite runs with no `--dart-define`s at all, which is exactly the
    // case that matters: a build that was not told which branch it serves must
    // refuse rather than guess. A made-up branch id would file real sales
    // against a restaurant that does not exist and sign collection codes no
    // kitchen can verify.
    expect(KioskDevProvisioning.isConfigured, isFalse);
    expect(KioskDevProvisioning.seedIfAbsent(store), isNull);
    expect(store.readIdentity(), isNull);
  });

  test('an identity already on the tablet always wins', () {
    store.writeIdentity(live);

    // Re-seeding a live till would repoint its ticket sequence and its outbox
    // at another branch, mid-service.
    expect(KioskDevProvisioning.seedIfAbsent(store)?.deviceId, 'borne-gm92');
    expect(store.readIdentity()?.branchId, live.branchId);
  });

  test('the SAMPLE MENU is the thing that stays debug-only', () {
    // ⚠ This is the gate that actually protects a customer: fake prices on a
    // machine facing the street. It is compiled against `kDebugMode`, so it
    // cannot be turned on by a flag in a release build.
    //
    // The suite runs in debug, so the assertion is on the compile-time AND:
    // without `KIOSK_DEV_SEED_MENU` it is off here too.
    expect(KioskDevProvisioning.seedMenu, isFalse);
    expect(
      kDebugMode,
      isTrue,
      reason: 'if this ever runs in release the assertion above is vacuous',
    );

    // And with nothing pinned, the seed does nothing at all.
    KioskDevProvisioning.seedMenuIfAbsent(store, branchId: live.branchId);
    expect(store.activeSnapshot(), isNull);
  });

  test('the sample menu can never outrank a real bundle', () {
    // Belt and braces for the same risk from the other side: the seed's
    // version is the lowest a snapshot can carry, so the first real bundle
    // from `rpc_menu_snapshot` supersedes it whatever happens.
    expect(KioskDevProvisioning.seedVersion, 1);
  });
}
