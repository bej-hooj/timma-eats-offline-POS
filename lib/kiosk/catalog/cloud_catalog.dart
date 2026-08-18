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
    this.refreshInterval = const Duration(minutes: 15),
  });

  /// The cloud half, or null on a tablet with no device key.
  ///
  /// Null does not make this class pointless: the photographs of whatever menu
  /// IS pinned still have to reach the disk, or a kiosk running on a seeded or
  /// previously-synced menu would lose its pictures the moment the line drops.
  /// The cloud is one input to a local catalogue, not the catalogue itself.
  final PosCloudSync? sync;
  final PosStore store;
  final DishPhotoCache photos;

  /// How often a running kiosk asks the dashboard whether the menu moved.
  /// Ops edit a menu a few times a day, not a few times a minute.
  final Duration refreshInterval;

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
    if (cloud == null) {
      _status = KioskCatalogStatus.local;
      await warmPhotos();
      return;
    }
    try {
      await cloud.start();
      _status = KioskCatalogStatus.pinned;
    } on Object {
      // No internet, a refused key, a bundle that failed validation — all the
      // same to the customer standing here, and none of them a reason to stop
      // selling. The exception is not logged with its message: it can carry a
      // URL with a key in it.
      _status = KioskCatalogStatus.offline;
      debugPrint('[KioskCatalog] pin skipped — selling the pinned menu');
    }
    await warmPhotos();
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

  /// This tablet has no cloud credential at all, so the local menu is the only
  /// menu by design.
  local,
}
