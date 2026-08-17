import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pos_core/pos_core.dart';
import 'package:pos_link/pos_link.dart';
import 'package:pos_link_flutter/pos_link_flutter.dart';

import 'package:timma_kiosk/design/time_util.dart';
import 'kiosk/hub/collection_secret_owner.dart';
import 'kiosk/hub/dev_provisioning.dart';
import 'kiosk/kiosk_app.dart';
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

  runApp(
    ProviderScope(
      overrides: [
        kioskEngineProvider.overrideWithValue(
          PosEngine(store: store, identity: identity),
        ),
        kioskCollectionSecretProvider.overrideWithValue(secret),
        kioskPrintQueueProvider.overrideWithValue(_printQueue()),
      ],
      child: const KioskApp(),
    ),
  );
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
