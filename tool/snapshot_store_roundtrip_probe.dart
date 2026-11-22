import 'dart:convert';
import 'dart:io';

import 'package:pos_core/pos_core.dart';

/// Does a bundle that validates in memory still validate **after the store**?
///
/// `tool/snapshot_checksum_probe.dart` proved the server's bytes and the
/// kiosk's Dart agree — on the host, in memory, with no SQLite in the path.
/// The borne still refuses the same bundle with `snapshot_checksum_mismatch`.
/// The one thing the device does that the probe does not is **write the
/// snapshot to SQLite and read it back**, so that is what this measures.
///
///     dart run tool/snapshot_store_roundtrip_probe.dart <snapshot.json>
void main(List<String> args) {
  final Map<String, Object?> wire =
      jsonDecode(File(args.first).readAsStringSync()) as Map<String, Object?>;
  final String served = wire['checksum']! as String;

  final MenuSnapshot parsed = MenuSnapshot.fromJson(wire, checksum: served);
  stdout.writeln('served        : $served');
  stdout.writeln('in memory     : ${parsed.computeChecksum()}');

  final PosStore store = SqlitePosStore.inMemory();
  store.writeIdentity(
    PosDeviceIdentity(
      deviceId: 'probe',
      branchId: parsed.branchId,
      role: PosDeviceRole.kiosk,
      label: 'probe',
    ),
  );

  final DateTime now = DateTime.utc(2026, 11, 22);
  try {
    store.stageSnapshot(parsed, now);
    store.activateSnapshot(parsed.version, now);
  } on Object catch (error) {
    stdout.writeln('STAGE/ACTIVATE THREW: $error');
    store.close();
    return;
  }

  final MenuSnapshot? back = store.activeSnapshot();
  if (back == null) {
    stdout.writeln('nothing came back out of the store');
    store.close();
    return;
  }
  final String after = back.computeChecksum();
  stdout.writeln('after store   : $after');
  stdout.writeln(after == served ? 'MATCH' : 'MISMATCH');

  if (after != served) {
    final String a = parsed.canonicalPayload();
    final String b = back.canonicalPayload();
    stdout.writeln('canonical in  : ${a.length} bytes');
    stdout.writeln('canonical out : ${b.length} bytes');
    final int n = a.length < b.length ? a.length : b.length;
    for (int i = 0; i < n; i++) {
      if (a[i] != b[i]) {
        final int from = (i - 80).clamp(0, i);
        stdout.writeln('first difference at byte $i');
        stdout.writeln('  in : ...${a.substring(from, (i + 80).clamp(0, a.length))}');
        stdout.writeln('  out: ...${b.substring(from, (i + 80).clamp(0, b.length))}');
        store.close();
        return;
      }
    }
    stdout.writeln('identical for $n bytes; only the lengths differ');
  }
  store.close();
}
