import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:pos_cloud/pos_cloud.dart';
import 'package:pos_core/pos_core.dart';

import 'dish_photo_cache.dart';

/// Pulls the dashboard's published catalogue down and pins it, then makes sure
/// its photographs are on disk before the line drops.
///
/// **The order of those two things is the feature.** A pinned snapshot whose
/// photos are still on the internet is a menu that turns into grey panels the
/// moment the shop's line goes — which is exactly the situation the kiosk
/// exists for. So a pin is only "finished" once the pictures are local too.
///
/// ## Offline-first, in the strong sense
///
/// The store's pinned snapshot is the source of truth for selling. This class
/// only ever *improves* it. Every failure path here — no internet, a refused
/// device key, a malformed bundle — leaves the kiosk exactly as it was, selling
/// yesterday's pinned menu at yesterday's prices, which is the correct
/// behaviour and not a degraded one.
///
/// It also never blocks the first frame: the customer sees the menu that is
/// already on the tablet while this runs behind them.
class KioskCloudCatalog {
  KioskCloudCatalog({
    required this.sync,
    required this.store,
    required this.photos,
    this.refreshInterval = const Duration(seconds: 60),
    bool Function()? canPin,
    this.pinNow,
    this.config,
  }) : canPin = canPin ?? _alwaysIdle;

  static bool _alwaysIdle() => true;

  /// The fetch-and-pin itself, overridable **only** so the `canPin` gate can be
  /// asserted against a live route. A test that proved the gate with no cloud
  /// at all would prove nothing: the cloud-less path returns early anyway, and
  /// this repo has already shipped one vacuous link test that let a real bug
  /// through for exactly that reason.
  final Future<void> Function()? pinNow;

  /// The cloud half, or null on a tablet with no device key.
  ///
  /// Null does not make this class pointless: the photographs of whatever menu
  /// IS pinned still have to reach the disk, or a kiosk running on a seeded or
  /// previously-synced menu would lose its pictures the moment the line drops.
  /// The cloud is one input to a local catalogue, not the catalogue itself.
  final PosCloudSync? sync;
  final PosStore store;
  final DishPhotoCache photos;

  /// How often a running kiosk asks the dashboard whether anything moved —
  /// and, when the line was down, how soon it notices the internet is back
  /// (ECOSYSTEM §25.6, owner: "keep checking every x time"). Cheap: an
  /// unedited menu answers `{unchanged}` without a bundle.
  final Duration refreshInterval;

  /// Merchant codes and the day menu (ECOSYSTEM §25). Null on a tablet
  /// with no cloud credential.
  final BranchConfigSync? config;

  /// Bumped when the merchant codes or the day menu changed.
  final ValueNotifier<int> configRevision = ValueNotifier<int>(0);

  /// Whether it is safe to swap the menu **right now**.
  ///
  /// ⚠ This is a money rule, not politeness. `PosEngine.placeKioskOrder`
  /// re-prices from `store.activeSnapshot()` **at placement time**, so a pin
  /// that lands while a customer is choosing charges them the *new* price for
  /// the screen they read at the *old* one — silently — and a dish the
  /// dashboard withdrew mid-order throws instead of selling. So a pin waits for
  /// an idle kiosk. Nothing is lost: the bundle is not consumed, and the next
  /// tick takes it the moment the customer is done.
  final bool Function() canPin;

  /// Bumped once per pin that actually **changed** the menu being sold.
  ///
  /// The screen reads the pinned menu live from the store, so it only ever
  /// needed a reason to rebuild — and for months it had none: the dashboard's
  /// new prices landed in SQLite and stayed invisible until someone restarted
  /// the app. Bumped on a *change*, never on a tick, so a kiosk that has been
  /// up all day with an unedited menu rebuilds nothing.
  final ValueNotifier<int> menuRevision = ValueNotifier<int>(0);

  Timer? _timer;
  bool _running = false;
  KioskCatalogStatus _status = KioskCatalogStatus.idle;

  KioskCatalogStatus get status => _status;

  /// Starts the cloud loops and warms the photos for whatever is pinned.
  ///
  /// Safe to call with no internet: `PosCloudSync.start()` reports the failure
  /// and keeps its loops running, and the photo pass then warms from whatever
  /// the store already holds — which on a second launch is the whole menu.
  Future<void> start() async {
    if (_running) {
      return;
    }
    _running = true;
    await refresh();
    _timer = Timer.periodic(refreshInterval, (_) => unawaited(refresh()));
  }

  /// One pass: pin what the dashboard published, then put its photos on disk.
  Future<void> refresh() async {
    final PosCloudSync? cloud = sync;
    if (cloud == null && pinNow == null) {
      _status = KioskCatalogStatus.local;
      await warmPhotos();
      return;
    }
    if (!canPin()) {
      // A customer is mid-order. Not an error and not a skipped update — the
      // periodic tick comes back, and the photos of what IS pinned still get
      // their pass, which is the half that has to work offline.
      _status = KioskCatalogStatus.busy;
      debugPrint('[KioskCatalog] pin deferred — a customer is ordering');
      await warmPhotos();
      return;
    }
    final int? before = store.activeSnapshot()?.version;
    await _pullConfig();
    try {
      // ⚠ `start()` pins only the FIRST time — it is idempotent once the
      // loops run. Calling it on every tick (as this did) meant a running
      // borne never saw a dashboard edit again until it was restarted.
      await (pinNow ?? (cloud!.isStarted ? cloud.refreshMenu : cloud.start))();
      _status = KioskCatalogStatus.pinned;
    } on Object {
      // No internet, a refused key, a bundle that failed validation — all the
      // same to the customer standing here, and none of them a reason to stop
      // selling. The exception is not logged with its message: it can carry a
      // URL with a key in it.
      _status = KioskCatalogStatus.offline;
      debugPrint('[KioskCatalog] pin skipped — selling the pinned menu');
    }
    // Photos BEFORE the screen is told, so a menu that appears has its
    // pictures on disk rather than a grid that fills in afterwards.
    await warmPhotos();
    final int? after = store.activeSnapshot()?.version;
    if (after != before) {
      debugPrint('[KioskCatalog] menu v$before → v$after');
      menuRevision.value++;
    }
  }

  /// Pulled on every tick, independent of the customer: none of it re-prices
  /// a basket, so it never has to wait for an idle borne.
  Future<void> _pullConfig() async {
    final BranchConfigSync? sync = config;
    if (sync == null) {
      return;
    }
    final BranchConfigPullResult result = await sync.pullOnce();
    if (result.failures > 0) {
      // Counts only — never an error message (it can carry a key).
      debugPrint(
        '[KioskCatalog] branch config: ${result.failures} pull(s) failed',
      );
    }
    if (result.settingsChanged || result.dayMenuChanged) {
      configRevision.value++;
    }
  }

  /// Fetches every photo the pinned menu references that is not already local.
  ///
  /// Runs after every pin AND after a failed pin: the menu on disk may have
  /// been pinned by an earlier launch that never got to its pictures.
  Future<void> warmPhotos() async {
    final MenuSnapshot? menu = store.activeSnapshot();
    if (menu == null) {
      return;
    }
    final List<String> urls = menu.products
        .map((SnapshotProduct product) => product.photoUrl)
        .whereType<String>()
        .where((String url) => url.isNotEmpty)
        .toList(growable: false);
    if (urls.isEmpty) {
      return;
    }
    final DishPhotoCacheResult result = await photos.warm(urls);
    // Counts only — never a URL, never a key. A kiosk that has been up for a
    // week should be able to answer "are my pictures local?" from logcat.
    debugPrint('[KioskCatalog] photos $result');
  }

  Future<void> dispose() async {
    _timer?.cancel();
    _timer = null;
    _running = false;
    menuRevision.dispose();
    configRevision.dispose();
    await sync?.stop();
  }
}

/// Whether the dashboard was reachable on the last pass. Diagnostics only —
/// nothing about selling depends on it.
enum KioskCatalogStatus {
  idle,

  /// The dashboard answered and its bundle is pinned.
  pinned,

  /// The dashboard could not be reached; the pinned menu is in force.
  offline,

  /// A customer was mid-order, so the menu was deliberately left alone.
  busy,

  /// This tablet has no cloud credential at all, so the local menu is the only
  /// menu by design.
  local,
}
