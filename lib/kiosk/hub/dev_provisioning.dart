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

  /// True when this build carries a complete identity to seed.
  ///
  /// ⚠⚠ **This used to require `kDebugMode`, and that made a release build
  /// unable to sell.** There is no provisioning flow in this app — `main()`
  /// says so — so a release borne found no identity, showed the unprovisioned
  /// screen, and stopped. The restaurant opens tomorrow on a release build;
  /// "the identity only exists in debug" is not a safety property, it is the
  /// absence of one.
  ///
  /// What the gate was really protecting is still protected, and more
  /// precisely:
  /// - **Nothing is invented.** Both values come from explicit
  ///   `--dart-define`s and an empty one seeds nothing, so a build that was
  ///   not told which branch it serves still refuses rather than guessing —
  ///   which is what would file sales against a restaurant that does not
  ///   exist.
  /// - **Nothing is overwritten.** [seedIfAbsent] returns an existing identity
  ///   untouched.
  /// - **The SAMPLE MENU stays debug-only** ([seedMenu]). That is the gate
  ///   that matters: fake prices on a machine facing the street.
  ///
  /// This is the shape CLAUDE.md §5 asks for anyway — keys and identities from
  /// build configuration, never a literal and never a default.
  static bool get isConfigured => branchId.isNotEmpty && deviceId.isNotEmpty;

  /// The sample menu's version. Deliberately the lowest a snapshot can carry,
  /// so any real bundle from `rpc_menu_snapshot` supersedes it on first fetch.
  static const int seedVersion = 1;

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
    debugPrint('[KioskProvisioning] seeded identity for branch $branchId');
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
    // The photo URLs are the REAL ones the dashboard publishes, from the public
    // `catalog` bucket. The prices are not real (hence the ribbon), but the
    // picture path has to be exercised against the real storage host or the
    // proof proves nothing: a fake URL would only ever test the fallback.
    const String bucket =
        'https://lsjwcleesyplevpmqdjt.supabase.co/storage/v1/object/public/catalog/dishes';
    const List<SnapshotProduct> products = <SnapshotProduct>[
      SnapshotProduct(
        productId: 'dev-poulet',
        nameFr: 'Poulet DG',
        nameEn: 'Chicken DG',
        basePrice: 4500,
        type: 'dish',
        available: true,
        photoUrl: '$bucket/poulet-dg.webp',
      ),
      SnapshotProduct(
        productId: 'dev-poisson',
        nameFr: 'Poisson braisé',
        nameEn: 'Grilled fish',
        basePrice: 5000,
        type: 'dish',
        available: true,
        sortIndex: 1,
        photoUrl: '$bucket/poisson-braise.webp',
      ),
      SnapshotProduct(
        productId: 'dev-ndole',
        nameFr: 'Ndolé aux crevettes',
        nameEn: 'Ndole with prawns',
        basePrice: 3500,
        type: 'dish',
        available: true,
        sortIndex: 2,
        photoUrl: '$bucket/ndole-miondo.webp',
        // Shaped like the real bundle (migration 20261122180000) so the dish
        // page can be built and seen without touching production: a
        // description, tags, ingredients with their marks, and — the point of
        // the exercise — ingredients that carry allergens.
        descriptionFr:
            'Feuilles de ndolé mijotées aux arachides, avec bœuf, poisson '
            'fumé et crevettes, à l\'huile de palme.',
        descriptionEn:
            'Bitterleaf simmered with groundnuts, beef, smoked fish and '
            'crayfish in palm oil.',
        spiceLevel: 1,
        originFr: 'Littoral',
        originEn: 'Littoral',
        tags: <String>['new'],
        ingredients: <SnapshotIngredient>[
          SnapshotIngredient(
            ingredientId: 'i-ndole',
            nameFr: 'Feuilles de ndolé',
            nameEn: 'Ndolé leaves',
            icon: '🥬',
          ),
          SnapshotIngredient(
            ingredientId: 'i-arachide',
            nameFr: 'Arachides',
            nameEn: 'Peanuts',
            icon: '🥜',
            allergenTags: <String>['peanuts'],
          ),
          SnapshotIngredient(
            ingredientId: 'i-boeuf',
            nameFr: 'Bœuf',
            nameEn: 'Beef',
            icon: '🥩',
          ),
          SnapshotIngredient(
            ingredientId: 'i-poisson',
            nameFr: 'Poisson fumé',
            nameEn: 'Smoked fish',
            icon: '🐟',
            allergenTags: <String>['fish'],
          ),
          SnapshotIngredient(
            ingredientId: 'i-crevette',
            nameFr: 'Crevettes',
            nameEn: 'Shrimp',
            icon: '🦐',
            allergenTags: <String>['crustaceans'],
          ),
          SnapshotIngredient(
            ingredientId: 'i-palme',
            nameFr: 'Huile de palme',
            nameEn: 'Palm oil',
            icon: '🧴',
            removable: true,
          ),
        ],
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
      // ⚠ **Version 1, never `now()`.** This stamped itself with the current
      // epoch seconds, and the server's version is the epoch of the last
      // dashboard edit — always in the past. So the sample menu outranked
      // production permanently: `activateSnapshot` refuses anything at or below
      // the active version, and every real fetch came back
      // `snapshot_downgrade`. A tablet that had once run a seeded build could
      // never accept the real menu again, and the only symptom was the DEBUG
      // ribbon staying up. A fixture must never be able to beat real data.
      version: seedVersion,
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
