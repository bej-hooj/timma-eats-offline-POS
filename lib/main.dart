import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pos_core/pos_core.dart';

import 'package:timma_kiosk/design/time_util.dart';
import 'kiosk/kiosk_app.dart';
import 'kiosk/state/kiosk_session.dart';

/// The kiosk's own entrypoint — a **different product on a different device**
/// from the customer phone app, sharing this repo's design tokens, l10n and
/// `pos_core` and nothing else.
///
///     flutter run --target lib/kiosk_main.dart
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
  final PosDeviceIdentity identity = store.readIdentity()!;

  runApp(
    ProviderScope(
      overrides: [
        kioskEngineProvider.overrideWithValue(
          PosEngine(store: store, identity: identity),
        ),
      ],
      child: const KioskApp(),
    ),
  );
}
