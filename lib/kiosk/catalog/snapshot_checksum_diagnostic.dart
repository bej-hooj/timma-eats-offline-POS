import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:pos_cloud/pos_cloud.dart';
import 'package:pos_core/pos_core.dart';

/// Says **which field** a `snapshot_checksum_mismatch` is about.
///
/// The borne has been refusing the real catalogue and selling a seeded sample
/// menu — the red *PRIX NON RÉELS* ribbon — because the checksum the server
/// signs the bundle with does not match the one the tablet computes over what
/// it parsed. Everything cheap was already ruled out by measurement: the live
/// payload run through this exact pinned `pos_core` on the host **matches**, it
/// is not stale local state, not two RPC overloads, not `type`. So the same
/// bytes validate on a Mac and fail on the tablet, and the next useful thing is
/// not another theory.
///
/// This is the measurement. On a mismatch — and only then — it re-fetches the
/// bundle and reports what the two sides disagree about:
///
/// * the **keys** the server sent that the client's model does not carry, and
///   the reverse. A field the server hashes and the client drops is exactly how
///   this fails, and it has happened before: the first version of the
///   categories migration hashed `photo_url` into every category while the
///   shipped Dart model has four fields and no `photo_url`.
/// * whether the payload **without categories** matches instead, which would
///   say the server hashed one shape and sent another.
/// * lengths and counts, to place the difference.
///
/// ⚠ **Names and sizes only — never values.** A menu is not a secret, but a log
/// line is a place data goes to be forgotten about, and the rule in this
/// codebase is that the redacted thing is the one that gets printed.
/// ⚠ **Extends rather than wraps.** `CatalogSync` takes the concrete
/// `SupabaseMenuSnapshotSource`, not the `SnapshotSource` interface, so a
/// decorator cannot be passed to it — and widening that parameter would mean
/// moving the pinned `pos_*` commit in both tablet repos, which is not a thing
/// to do for a diagnostic.
class DiagnosingMenuSnapshotSource extends SupabaseMenuSnapshotSource {
  DiagnosingMenuSnapshotSource({
    required this.gateway,
    required this.deviceKey,
  }) : super(gateway: gateway, deviceKey: deviceKey);

  final PosCloudGateway gateway;
  final String deviceKey;

  /// Once per launch. The sync tick retries on a timer, and a diagnosis that
  /// repeated every tick would bury itself and cost an RPC each time.
  bool _reported = false;

  @override
  Future<MenuSnapshot> fetch({
    required String branchId,
    int? sinceVersion,
  }) async {
    try {
      return await super.fetch(branchId: branchId, sinceVersion: sinceVersion);
    } on PosError catch (error) {
      if (error.code == PosErrorCodes.snapshotChecksumMismatch && !_reported) {
        _reported = true;
        await _diagnose(sinceVersion);
      }
      rethrow;
    }
  }

  Future<void> _diagnose(int? sinceVersion) async {
    try {
      final Map<String, dynamic> raw = await gateway.menuSnapshot(
        deviceKey: deviceKey,
        version: sinceVersion,
      );
      final String? served = raw[PosFeedKeys.checksum] as String?;
      final MenuSnapshot parsed = MenuSnapshot.fromJson(
        raw,
        checksum: served ?? '',
      );

      final String mine = parsed.computeChecksum();
      debugPrint(
        '[SnapshotDiag] served=${_short(served)} computed=${_short(mine)} '
        'products=${parsed.products.length}/${parsed.declaredProductCount} '
        'categories=${parsed.categories.length} '
        'canonicalBytes=${parsed.canonicalPayload().length}',
      );

      // Which shape does the server's checksum actually describe?
      final String withoutCategories = _checksumOf(<String, Object?>{
        'version': parsed.version,
        'branch_id': parsed.branchId,
        'product_count': parsed.declaredProductCount,
        'products': <Object?>[
          for (final SnapshotProduct p in parsed.products) p.toJson(),
        ],
      });
      final String withEmptyCategories = _checksumOf(<String, Object?>{
        'version': parsed.version,
        'branch_id': parsed.branchId,
        'product_count': parsed.declaredProductCount,
        'products': <Object?>[
          for (final SnapshotProduct p in parsed.products) p.toJson(),
        ],
        'categories': const <Object?>[],
      });
      debugPrint(
        '[SnapshotDiag] shape match: '
        'asParsed=${mine == served} '
        'withoutCategories=${withoutCategories == served} '
        'withEmptyCategories=${withEmptyCategories == served}',
      );

      // And which FIELDS the two sides disagree about. This is the line that
      // names the bug when no shape above matches.
      _reportKeys(
        'top',
        served: raw.keys.toSet(),
        // What the client hashes at the top level, from `canonicalPayload`.
        mine: <String>{
          'version',
          'branch_id',
          'product_count',
          'products',
          if (parsed.categories.isNotEmpty) 'categories',
        },
      );
      _reportKeys(
        'product',
        served: _unionKeys(raw['products']),
        mine: parsed.products.isEmpty
            ? const <String>{}
            : parsed.products.first.toJson().keys.toSet(),
      );
      _reportKeys(
        'category',
        served: _unionKeys(raw['categories']),
        mine: parsed.categories.isEmpty
            ? const <String>{}
            : parsed.categories.first.toJson().keys.toSet(),
      );
    } on Object catch (error) {
      // A diagnosis must never become the failure. The type is safe to print;
      // the exception's own text is not — a cloud error can carry a request URL
      // and a request URL can carry the device key.
      debugPrint('[SnapshotDiag] could not diagnose: ${error.runtimeType}');
    }
  }

  void _reportKeys(
    String what, {
    required Set<String> served,
    required Set<String> mine,
  }) {
    final List<String> serverOnly = served.difference(mine).toList()..sort();
    final List<String> clientOnly = mine.difference(served).toList()..sort();
    if (serverOnly.isEmpty && clientOnly.isEmpty) {
      return;
    }
    debugPrint(
      '[SnapshotDiag] $what keys — server not client: $serverOnly · '
      'client not server: $clientOnly',
    );
  }

  static Set<String> _unionKeys(Object? list) {
    if (list is! List) {
      return const <String>{};
    }
    final Set<String> keys = <String>{};
    for (final Object? row in list) {
      if (row is Map) {
        for (final Object? key in row.keys) {
          if (key is String) {
            keys.add(key);
          }
        }
      }
    }
    return keys;
  }

  /// The same two lines `MenuSnapshot.computeChecksum` runs, over a payload
  /// this file shapes by hand — the whole point is to hash a shape the model
  /// would not produce.
  static String _checksumOf(Map<String, Object?> payload) =>
      sha256.convert(utf8.encode(canonicalJson(payload))).toString();

  /// Enough of a hash to tell two apart in a log, never enough to be a value.
  static String _short(String? hash) =>
      hash == null || hash.isEmpty ? '-' : hash.substring(0, 12);
}
