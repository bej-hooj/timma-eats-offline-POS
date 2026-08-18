import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:pos_link/pos_link.dart';
import 'package:pos_link_flutter/pos_link_flutter.dart';

/// The kiosk's memory of every kitchen it has ever paired.
///
/// **The bug this exists for.** `PairingRegistry` defaults to
/// `MemoryCredentialStore`, so the hub forgot every paired board the moment the
/// kiosk app restarted. The board still held its credential and kept presenting
/// it; the hub had never heard of it and refused. What a restaurant saw was the
/// kiosk asking to pair again while the kitchen sat there insisting it already
/// had. Reported from two devices, 2026-08-18.
///
/// The interface is synchronous — `read` is called while a frame is being
/// authenticated — so the credentials live in memory and are **hydrated once**
/// at startup from the platform keystore. Writes go to memory immediately and to
/// the keystore behind them.
///
/// Credentials are secrets: they belong in the keystore and never in the SQLite
/// store, which is a plain file that a backup or a support dump could carry off.
class HubCredentialStore implements DeviceCredentialStore {
  HubCredentialStore(this._store);

  factory HubCredentialStore.platform() =>
      HubCredentialStore(FlutterSecureValueStore.platform());

  static const String _indexKey = 'timma.pos.hub.paired_devices.v1';
  static const String _keyPrefix = 'timma.pos.hub.credential.';

  static const String _deviceIdKey = 'device_id';
  static const String _secretKey = 'secret';
  static const String _issuedAtKey = 'issued_at';

  final SecureValueStore _store;
  final Map<String, DeviceCredential> _cache = <String, DeviceCredential>{};

  /// Loads what previous services paired. Call once, before the hub starts
  /// accepting connections, or a board that paired yesterday is refused today.
  Future<void> load() async {
    try {
      final String? index = await _store.read(_indexKey);
      if (index == null) {
        return;
      }
      final Object? decoded = jsonDecode(index);
      if (decoded is! List) {
        return;
      }
      for (final Object? entry in decoded) {
        if (entry is! String) {
          continue;
        }
        final DeviceCredential? credential = await _read(entry);
        if (credential != null) {
          _cache[entry] = credential;
        }
      }
    } on Object {
      // A keystore this hub cannot read is a hub that pairs afresh — bad, but
      // not a reason to refuse to open the restaurant.
      debugPrint('[Hub] could not restore paired kitchens');
    }
  }

  int get pairedCount => _cache.length;

  @override
  DeviceCredential? read(String deviceId) => _cache[deviceId];

  @override
  void write(DeviceCredential credential) {
    _cache[credential.deviceId] = credential;
    // Fire and forget: the pairing handshake must not wait on a keystore, and
    // the in-memory copy already makes this service work. The next restart is
    // what depends on the write landing, and a failure there is logged.
    unawaited(_persist(credential));
  }

  @override
  void remove(String deviceId) {
    _cache.remove(deviceId);
    unawaited(_forget(deviceId));
  }

  Future<DeviceCredential?> _read(String deviceId) async {
    final String? raw = await _store.read('$_keyPrefix$deviceId');
    if (raw == null) {
      return null;
    }
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return null;
      }
      final Object? id = decoded[_deviceIdKey];
      final Object? secret = decoded[_secretKey];
      final Object? issuedAt = decoded[_issuedAtKey];
      if (id is! String || secret is! String || issuedAt is! int) {
        return null;
      }
      return DeviceCredential(
        deviceId: id,
        secret: secret,
        issuedAt: DateTime.fromMillisecondsSinceEpoch(issuedAt, isUtc: true),
      );
    } on Object {
      // Corrupt entry: treat as absent. The kitchen re-pairs, which is a
      // two-minute inconvenience rather than a hub that will not start.
      return null;
    }
  }

  Future<void> _persist(DeviceCredential credential) async {
    try {
      await _store.write(
        key: '$_keyPrefix${credential.deviceId}',
        value: jsonEncode(<String, Object?>{
          _deviceIdKey: credential.deviceId,
          _secretKey: credential.secret,
          _issuedAtKey: credential.issuedAt.toUtc().millisecondsSinceEpoch,
        }),
      );
      await _writeIndex();
    } on Object {
      debugPrint('[Hub] a paired kitchen was not saved for the next restart');
    }
  }

  Future<void> _forget(String deviceId) async {
    try {
      await _store.delete('$_keyPrefix$deviceId');
      await _writeIndex();
    } on Object {
      debugPrint('[Hub] a revoked kitchen was not removed from storage');
    }
  }

  /// The index exists because a keystore cannot be listed: without it, a
  /// restarted hub would have no way to know which device ids to look up.
  Future<void> _writeIndex() =>
      _store.write(key: _indexKey, value: jsonEncode(_cache.keys.toList()));
}
