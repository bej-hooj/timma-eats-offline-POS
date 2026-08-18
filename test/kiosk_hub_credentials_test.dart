import 'package:flutter_test/flutter_test.dart';
import 'package:pos_link/pos_link.dart';
import 'package:pos_link_flutter/pos_link_flutter.dart';
import 'package:timma_kiosk/kiosk/hub/hub_credential_store.dart';

/// A kitchen paired yesterday is still paired today.
///
/// `PairingRegistry` defaults to `MemoryCredentialStore`, so every restart of
/// the kiosk app forgot every board it had ever paired. The board kept its
/// credential and kept presenting it; the hub refused a device it had never
/// heard of. What a restaurant saw was the kiosk asking to pair again while the
/// kitchen insisted it already had — reported from two devices, 2026-08-18.
void main() {
  late _MemoryStore keystore;

  setUp(() => keystore = _MemoryStore());

  DeviceCredential credential(String deviceId) => DeviceCredential(
    deviceId: deviceId,
    secret: 'secret-for-$deviceId',
    issuedAt: DateTime.utc(2026, 8, 18, 12),
  );

  test('a credential survives the restart that used to erase it', () async {
    final HubCredentialStore before = HubCredentialStore(keystore);
    await before.load();
    before.write(credential('kds-1'));
    // The write is deliberately fire-and-forget so the handshake never waits on
    // a keystore; give it the microtask it needs before pulling the plug.
    await Future<void>.delayed(Duration.zero);

    // The kiosk app restarts: new store object, same keystore.
    final HubCredentialStore after = HubCredentialStore(keystore);
    await after.load();

    final DeviceCredential? restored = after.read('kds-1');
    expect(restored, isNotNull, reason: 'the board is still paired');
    expect(restored!.secret, credential('kds-1').secret);
    expect(restored.issuedAt, credential('kds-1').issuedAt);
  });

  test('several kitchens all come back', () async {
    final HubCredentialStore before = HubCredentialStore(keystore);
    await before.load();
    before.write(credential('kds-1'));
    before.write(credential('kds-2'));
    await Future<void>.delayed(Duration.zero);

    final HubCredentialStore after = HubCredentialStore(keystore);
    await after.load();

    expect(after.pairedCount, 2);
    expect(after.read('kds-1'), isNotNull);
    expect(after.read('kds-2'), isNotNull);
  });

  test('a revoked kitchen does not come back', () async {
    final HubCredentialStore before = HubCredentialStore(keystore);
    await before.load();
    before.write(credential('kds-1'));
    before.write(credential('kds-2'));
    await Future<void>.delayed(Duration.zero);
    before.remove('kds-1');
    await Future<void>.delayed(Duration.zero);

    final HubCredentialStore after = HubCredentialStore(keystore);
    await after.load();

    expect(after.read('kds-1'), isNull, reason: 'revoked stays revoked');
    expect(after.read('kds-2'), isNotNull);
  });

  test('a corrupt entry costs that kitchen only, not the hub', () async {
    final HubCredentialStore before = HubCredentialStore(keystore);
    await before.load();
    before.write(credential('kds-good'));
    before.write(credential('kds-bad'));
    await Future<void>.delayed(Duration.zero);
    keystore.values['timma.pos.hub.credential.kds-bad'] = '{not json';

    final HubCredentialStore after = HubCredentialStore(keystore);
    await after.load();

    expect(after.read('kds-good'), isNotNull);
    expect(
      after.read('kds-bad'),
      isNull,
      reason: 'that kitchen re-pairs; the hub still opens for the others',
    );
  });

  test('a fresh kiosk starts with nothing and does not throw', () async {
    final HubCredentialStore store = HubCredentialStore(keystore);
    await store.load();
    expect(store.pairedCount, 0);
    expect(store.read('anything'), isNull);
  });
}

class _MemoryStore implements SecureValueStore {
  final Map<String, String> values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write({required String key, required String value}) async =>
      values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);
}
