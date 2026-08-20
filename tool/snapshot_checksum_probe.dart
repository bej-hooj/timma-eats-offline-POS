import 'dart:convert';
import 'dart:io';

import 'package:pos_core/pos_core.dart';

/// Compares the checksum the SERVER computed with the one the KIOSK recomputes.
///
/// The two are computed from different code in different languages over what is
/// supposed to be identical canonical bytes, and when they disagree the kiosk
/// refuses the whole bundle and cannot sell. This prints the first byte at
/// which they diverge instead of leaving `snapshot_checksum_mismatch` as the
/// only evidence.
///
///     dart run tool/snapshot_checksum_probe.dart <snapshot.json>
void main(List<String> args) {
  final Map<String, Object?> wire =
      jsonDecode(File(args.first).readAsStringSync()) as Map<String, Object?>;
  final String server = wire['checksum']! as String;

  final MenuSnapshot snapshot = MenuSnapshot.fromJson(wire, checksum: server);
  final String mine = snapshot.computeChecksum();

  stdout.writeln('server : $server');
  stdout.writeln('kiosk  : $mine');
  stdout.writeln(server == mine ? 'MATCH' : 'MISMATCH');
  stdout.writeln('parsed : ${snapshot.products.length} products, '
      '${snapshot.categories.length} categories, v${snapshot.version}');

  if (server == mine) {
    return;
  }
  // Where do the canonical bytes diverge? The server does not return its own
  // canonical string, so rebuild the payload the way the SQL did and compare
  // against what Dart canonicalises — the first differing index names the field.
  final String dartCanonical = snapshot.canonicalPayload();
  final Map<String, Object?> asSent = Map<String, Object?>.from(wire)
    ..remove('checksum');
  final String sentCanonical = canonicalJson(asSent);
  stdout.writeln('dart canonical bytes: ${dartCanonical.length}');
  stdout.writeln('wire canonical bytes: ${sentCanonical.length}');
  final int n = dartCanonical.length < sentCanonical.length
      ? dartCanonical.length
      : sentCanonical.length;
  for (int i = 0; i < n; i++) {
    if (dartCanonical[i] != sentCanonical[i]) {
      final int from = (i - 60).clamp(0, i);
      stdout.writeln('first difference at byte $i');
      stdout.writeln('  dart: ...${dartCanonical.substring(from, (i + 60).clamp(0, dartCanonical.length))}');
      stdout.writeln('  wire: ...${sentCanonical.substring(from, (i + 60).clamp(0, sentCanonical.length))}');
      return;
    }
  }
  stdout.writeln('identical up to $n bytes; lengths differ');
}
