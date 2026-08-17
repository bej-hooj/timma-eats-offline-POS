import 'package:flutter/foundation.dart';
import 'package:pos_core/pos_core.dart';

/// Seeds a device identity **in debug builds only**, from values the operator
/// passes at build time.
///
/// The kiosk has no provisioning UI yet, and without an identity it correctly
/// refuses to trade — which also means it cannot be exercised on real hardware
/// at all. This is the seam that makes a device smoke possible without pretending
/// a tablet is provisioned when it is not.
///
/// Two rules make it safe:
///
/// 1. **`kDebugMode` only.** A release APK ignores this file entirely, so no
///    shipped build can self-provision.
/// 2. **Nothing is invented.** Every value comes from an explicit
///    `--dart-define`. With no defines the seed does nothing and the kiosk shows
///    its unprovisioned screen. A hardcoded fallback branch id would file real
///    sales against a restaurant that does not exist and sign collection codes
///    no kitchen can verify.
///
/// It is deliberately **not** a substitute for the real pairing/provisioning
/// flow, and it never writes over an identity that is already there.
abstract final class KioskDevProvisioning {
  static const String branchId = String.fromEnvironment('KIOSK_DEV_BRANCH_ID');
  static const String deviceId = String.fromEnvironment('KIOSK_DEV_DEVICE_ID');
  static const String label = String.fromEnvironment(
    'KIOSK_DEV_LABEL',
    defaultValue: 'Borne (debug)',
  );

  /// True when this build carries a complete debug identity to seed.
  static bool get isConfigured =>
      kDebugMode && branchId.isNotEmpty && deviceId.isNotEmpty;

  /// True when this build was told to pin a **sample** menu.
  ///
  /// The real menu arrives through `pos_cloud`'s snapshot sync. This exists so
  /// the selling flow can be exercised on hardware before that is composed, and
  /// it is loud on screen for a reason: this project has already lost a session
  /// to a build whose data was fake and whose UI said nothing about it.
  static const bool seedMenu =
      bool.fromEnvironment('KIOSK_DEV_SEED_MENU') && kDebugMode;

  /// Writes the identity if, and only if, the store has none.
  ///
  /// Returns what the caller should treat as the device identity. An existing
  /// identity always wins: re-seeding a live till would repoint its ticket
  /// sequence and its outbox at another branch.
  static PosDeviceIdentity? seedIfAbsent(PosStore store) {
    final PosDeviceIdentity? existing = store.readIdentity();
    if (existing != null || !isConfigured) {
      return existing;
    }
    final PosDeviceIdentity seeded = PosDeviceIdentity(
      deviceId: deviceId,
      branchId: branchId,
      role: PosDeviceRole.kiosk,
      label: label,
    );
    store.writeIdentity(seeded);
    debugPrint(
      '[KioskDev] seeded a DEBUG identity for branch $branchId — '
      'this path does not exist in release builds',
    );
    return seeded;
  }

  /// Pins a small sample menu when [seedMenu] is set and nothing is pinned.
  ///
  /// The snapshot is built and activated through the ordinary store API —
  /// including its real checksum — so it exercises the same validation path a
  /// cloud-synced bundle does. A bundle whose checksum does not match its bytes
  /// is exactly what the store exists to reject, and a seed that skipped it
  /// would be testing a path the kiosk can never reach.
  static void seedMenuIfAbsent(PosStore store, {required String branchId}) {
    if (!seedMenu || store.activeSnapshot() != null) {
      return;
    }
    const List<SnapshotProduct> products = <SnapshotProduct>[
      SnapshotProduct(
        productId: 'dev-poulet',
        nameFr: 'Poulet DG',
        nameEn: 'Chicken DG',
        basePrice: 4500,
        type: 'dish',
        available: true,
      ),
      SnapshotProduct(
        productId: 'dev-poisson',
        nameFr: 'Poisson braisé',
        nameEn: 'Grilled fish',
        basePrice: 5000,
        type: 'dish',
        available: true,
        sortIndex: 1,
      ),
      SnapshotProduct(
        productId: 'dev-ndole',
        nameFr: 'Ndolé aux crevettes',
        nameEn: 'Ndole with prawns',
        basePrice: 3500,
        type: 'dish',
        available: true,
        sortIndex: 2,
      ),
      SnapshotProduct(
        productId: 'dev-eru',
        nameFr: 'Eru et water fufu',
        nameEn: 'Eru and water fufu',
        basePrice: 2500,
        type: 'dish',
        available: true,
        sortIndex: 3,
      ),
      SnapshotProduct(
        productId: 'dev-riz',
        nameFr: 'Riz sauté au bœuf',
        nameEn: 'Beef fried rice',
        basePrice: 3000,
        type: 'dish',
        available: true,
        sortIndex: 4,
      ),
      SnapshotProduct(
        // Deliberately unavailable: the sold-out barrier is a rule worth
        // seeing on a real screen, not only in a widget test.
        productId: 'dev-koki',
        nameFr: 'Koki de haricots',
        nameEn: 'Bean koki',
        basePrice: 2000,
        type: 'dish',
        available: false,
        sortIndex: 5,
      ),
    ];
    final MenuSnapshot draft = MenuSnapshot(
      version: DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000,
      branchId: branchId,
      declaredProductCount: products.length,
      products: products,
      checksum: '',
    );
    final MenuSnapshot menu = MenuSnapshot(
      version: draft.version,
      branchId: draft.branchId,
      declaredProductCount: draft.declaredProductCount,
      products: draft.products,
      checksum: draft.computeChecksum(),
    );
    final DateTime now = DateTime.now().toUtc();
    store.stageSnapshot(menu, now);
    store.activateSnapshot(menu.version, now);
    debugPrint('[KioskDev] pinned a SAMPLE menu — prices here are not real');
  }
}
