import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pos_core/pos_core.dart';
import 'package:pos_link/pos_link.dart';
import 'package:pos_link_flutter/pos_link_flutter.dart';

import 'package:pos_cloud/pos_cloud.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:timma_kiosk/design/time_util.dart';
import 'kiosk/catalog/cloud_catalog.dart';
import 'kiosk/catalog/dish_photo_cache.dart';
import 'kiosk/hub/collection_secret_owner.dart';
import 'kiosk/hub/dev_provisioning.dart';
import 'kiosk/hub/device_key_vault.dart';
import 'kiosk/kiosk_app.dart';
import 'kiosk/manager/hub_controller.dart';
import 'kiosk/printing/print_queue.dart';
import 'kiosk/printing/socket_printer.dart';
import 'kiosk/presentation/bootstrap_screen.dart';
import 'kiosk/state/kiosk_session.dart';

/// The kiosk's own entrypoint — a **different product on a different device**
/// from the customer phone app, sharing this repo's design tokens, l10n and
/// `pos_core` and nothing else.
///
///     flutter run --dart-define=KIOSK_PRINTER_HOST=192.168.1.50
///
/// It deliberately does **not** initialise Supabase or Hive. The kiosk holds
/// the shift's truth in its own SQLite store (§23.2) and must never carry a
/// customer session: the device stands in a public room facing the street.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  TimeUtil.init();

  // Landscape and edge-to-edge. The tablet is mounted; there is nobody to
  // rotate it, and a kiosk that reflows mid-order is a kiosk that lost one.
  await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  final Directory dir = await getApplicationDocumentsDirectory();
  final PosStore store = SqlitePosStore.open('${dir.path}/kiosk.db');

  // **A fresh install has no identity, and that is not a crash.** This used to
  // be `store.readIdentity()!`, which meant the very first launch on a new
  // tablet died before `runApp` with nothing on screen to explain it. There is
  // no provisioning flow in this build, so the honest thing is to say so:
  // never invent a branch or device id, because a made-up branch id would sign
  // collection codes no kitchen can verify and file sales against a restaurant
  // that does not exist.
  // In debug builds with an explicit `--dart-define`ed identity this seeds the
  // store so the kiosk can be exercised on real hardware; in release it is a
  // plain read of what provisioning wrote. It never overwrites an identity.
  final PosDeviceIdentity? identity = KioskDevProvisioning.seedIfAbsent(store);
  if (identity == null) {
    runApp(const KioskBootstrapApp(state: KioskBootstrapState.unprovisioned));
    return;
  }

  KioskDevProvisioning.seedMenuIfAbsent(store, branchId: identity.branchId);

  // The branch collection secret, loaded once and reused for the life of the
  // branch. A fault here does not stop the kiosk selling — it stops it printing
  // slips it cannot authenticate, which is the honest degradation.
  BranchCollectionSecret? secret;
  CollectionSecretFailure? secretFailure;
  try {
    secret = await CollectionSecretOwner(
      store: store,
      vault: BranchCollectionSecretVault.platform(),
    ).loadOrCreate(identity.branchId);
  } on CollectionSecretException catch (error) {
    secretFailure = error.failure;
  }

  if (secretFailure == CollectionSecretFailure.vanished) {
    // Refusing to trade is right here and only here: this hub HAS printed slips
    // under a secret it can no longer read, so every one of them is
    // unverifiable and silently minting a new secret would hide that.
    runApp(const KioskBootstrapApp(state: KioskBootstrapState.secretLost));
    return;
  }

  final PosEngine engine = PosEngine(store: store, identity: identity);

  // The dashboard's catalogue, if this tablet is credentialed for it. Building
  // it cannot fail the launch: `_cloudCatalog` returns null for every
  // misconfiguration and the kiosk sells the menu already on disk.
  final DishPhotoCache? photos = await _photoCache(dir);
  final KioskCloudCatalog? catalog = await _cloudCatalog(
    store: store,
    engine: engine,
    identity: identity,
    photos: photos,
  );

  runApp(
    ProviderScope(
      overrides: [
        kioskEngineProvider.overrideWithValue(engine),
        kioskCollectionSecretProvider.overrideWithValue(secret),
        kioskPrintQueueProvider.overrideWithValue(_printQueue()),
        kioskPhotoCacheProvider.overrideWithValue(photos),
        // ⚠ **At the ROOT, not in a child `ProviderScope`.** It was in one, and
        // the kitchen stayed empty through a whole sale on the devices while
        // every test passed. Riverpod 3 does not re-instantiate a provider in a
        // child scope just because it reads an overridden one: the session
        // controller lives in the root container, so `ref.read` of the
        // publisher there returned the **default no-op** and the sale was
        // announced to nobody. The unit test could not see it — it built one
        // container and overrode at its root, which is the shape that works.
        kioskBoardPublisherProvider.overrideWith(
          (Ref ref) => () => ref.read(hubProvider.notifier).publishBoard(),
        ),
      ],
      child: const _KioskWithHub(),
    ),
  );

  // ⚠ **After `runApp`, deliberately.** The customer gets the menu that is
  // already pinned on this tablet on the first frame; the dashboard's version
  // arrives behind them. A kiosk that waited on the network before drawing
  // would be a kiosk with a blank screen every time the shop's line is slow —
  // which is the failure §23 exists to prevent.
  unawaited(catalog?.start());
}

/// Where dish photographs live, or null when this build has no cloud host to
/// trust.
///
/// The host is derived from the configured Supabase URL rather than configured
/// separately: two sources for "which server is ours" is one source too many,
/// and the wrong one would eventually be the one edited.
Future<DishPhotoCache?> _photoCache(Directory documents) async {
  final Uri? supabase = _supabaseUri();
  if (supabase == null) {
    return null;
  }
  final Directory dir = Directory('${documents.path}/dish_photos');
  final DishPhotoCache cache = DishPhotoCache(
    directory: dir,
    allowedHost: supabase.host,
  );
  return cache;
}

/// Composes the cloud catalogue, or returns null when anything it needs is
/// missing.
///
/// Null is the ordinary state of an unprovisioned tablet, not an error: the
/// kiosk still opens, still sells, still prints. Only the dashboard's menu is
/// absent, and only until someone provisions the device.
Future<KioskCloudCatalog?> _cloudCatalog({
  required PosStore store,
  required PosEngine engine,
  required PosDeviceIdentity identity,
  required DishPhotoCache? photos,
}) async {
  if (photos == null) {
    return null;
  }
  // With no cloud credential the catalogue still runs, photo-only: whatever
  // menu is pinned on this tablet gets its pictures onto the disk. Skipping
  // that would leave a seeded or previously-synced kiosk with a grid of grey
  // panels the first time the line drops.
  KioskCloudCatalog photosOnly() =>
      KioskCloudCatalog(sync: null, store: store, photos: photos);

  final Uri? url = _supabaseUri();
  const String anonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  if (url == null || anonKey.isEmpty) {
    return photosOnly();
  }

  // The device key is read from the platform keystore. A `--dart-define` is
  // accepted ONCE, to provision a tablet, and never read again after that —
  // see `KioskDeviceKeyVault`.
  const String provisioningKey = String.fromEnvironment('KIOSK_DEVICE_KEY');
  final String? deviceKey = await KioskDeviceKeyVault.platform()
      .provisionIfAbsent(provisioningKey.isEmpty ? null : provisioningKey);
  if (deviceKey == null) {
    debugPrint(
      '[KioskCatalog] no device key — pinned menu only, photos still cached',
    );
    return photosOnly();
  }

  try {
    // `publishableKey`, not the deprecated `anonKey` parameter — the value
    // itself is whatever this build was configured with, and Supabase accepts
    // both an anon JWT and a publishable key in this slot.
    await Supabase.initialize(url: url.toString(), publishableKey: anonKey);
  } on Object {
    // Already initialised, or a malformed URL. Neither is worth a blank screen.
    debugPrint('[KioskCatalog] cloud client unavailable');
    return photosOnly();
  }

  final PosCloudGateway gateway = SupabasePosCloudGateway(
    Supabase.instance.client,
  );
  return KioskCloudCatalog(
    store: store,
    photos: photos,
    sync: PosCloudSync(
      store: store,
      branchId: identity.branchId,
      drain: OutboxDrain(
        store: store,
        sink: PosCloudSink(
          store: store,
          gateway: gateway,
          deviceKey: deviceKey,
        ),
        // What the server minted for an order it accepted — `order_id`,
        // `order_code`, `daily_code` — comes back down here. Without this the
        // local row keeps only its offline ticket number and never learns the
        // order's cloud identity.
        onServerFields:
            (OutboxEnvelope envelope, Map<String, Object?> fields) =>
                engine.acknowledge(envelope.subject, fields),
      ),
      feed: OrderFeedPoller(
        store: store,
        engine: engine,
        gateway: gateway,
        deviceKey: deviceKey,
      ),
      heartbeat: PosHeartbeat(gateway: gateway, deviceKey: deviceKey),
      menuSource: SupabaseMenuSnapshotSource(
        gateway: gateway,
        deviceKey: deviceKey,
      ),
      onError: (Object _) {
        // Counted, never printed: a cloud error can carry a request URL, and a
        // request URL can carry a device key.
        debugPrint('[KioskCatalog] a sync tick failed');
      },
    ),
  );
}

/// The configured Supabase origin, validated.
///
/// **https only.** The kiosk sends a device key on every RPC; a plaintext
/// origin would put it on the shop's wifi in clear. A build configured with
/// `http://` gets no cloud at all rather than a downgraded one.
Uri? _supabaseUri() {
  const String raw = String.fromEnvironment('SUPABASE_URL');
  if (raw.isEmpty) {
    return null;
  }
  final Uri? uri = Uri.tryParse(raw);
  if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
    debugPrint('[KioskCatalog] refusing a non-https SUPABASE_URL');
    return null;
  }
  return uri;
}

/// The counter printer, or null when this build was given no printer address.
///
/// The address is build configuration, never a hardcoded hex or IP in source
/// (§5): branches differ, and a kiosk pointed at the wrong LAN printer prints
/// another restaurant's tickets. With no address configured the kiosk still
/// sells and the counter screen reports every slip as not printed, rather than
/// pretending a printer exists.
PrintQueue? _printQueue() {
  const String host = String.fromEnvironment('KIOSK_PRINTER_HOST');
  if (host.isEmpty) {
    return null;
  }
  const int port = int.fromEnvironment(
    'KIOSK_PRINTER_PORT',
    defaultValue: 9100,
  );
  return PrintQueue(
    transport: SocketPrinter(host: host, port: port),
  );
}

/// Starts the hub once the first frame is up.
///
/// The sale path must not depend on the LAN server — an unpaired kiosk sells
/// perfectly well — so the dependency points the other way: the composition
/// root tells the session controller HOW to publish (above, at the root scope),
/// and the controller never knows what a hub is.
class _KioskWithHub extends ConsumerStatefulWidget {
  const _KioskWithHub();

  @override
  ConsumerState<_KioskWithHub> createState() => _KioskWithHubState();
}

class _KioskWithHubState extends ConsumerState<_KioskWithHub> {
  @override
  void initState() {
    super.initState();
    // ⚠ **The kiosk IS the hub, from the moment it opens** — not from the moment
    // a manager visits a screen. The hub used to start only inside the manager
    // screen, so after any restart the kitchen was orphaned until somebody went
    // looking for it, and a restaurant reboots a tablet far more often than it
    // opens a manager screen.
    //
    // It lives here, in the production composition root, and not in the shell
    // widget: widget tests build `KioskApp` directly, and a real `HttpServer`
    // inside a `FakeAsync` test is a pending timer that fails the suite for a
    // reason that has nothing to do with the test.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(ref.read(hubProvider.notifier).start());
    });
  }

  @override
  Widget build(BuildContext context) => const KioskApp();
}
