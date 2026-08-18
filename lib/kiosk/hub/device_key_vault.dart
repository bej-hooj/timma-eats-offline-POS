import 'package:pos_link_flutter/pos_link_flutter.dart';

/// The kiosk's **server device key**, kept in the platform keystore.
///
/// This is the credential `rpc_menu_snapshot`, the order feed, the heartbeat
/// and the relay-token exchange all authenticate with. It is not the LAN
/// pairing credential and not the branch collection secret — three different
/// authorities, deliberately, so that losing one does not surrender the others.
///
/// **It never lives in the APK.** A key baked into a build with a
/// `--dart-define` ships to every tablet that build reaches and cannot be
/// rotated without a release. So a provisioning value is accepted **once**,
/// written to the keystore, and read from there forever after; the build-time
/// value becomes irrelevant on the second launch.
class KioskDeviceKeyVault {
  const KioskDeviceKeyVault(this._store);

  factory KioskDeviceKeyVault.platform() =>
      KioskDeviceKeyVault(FlutterSecureValueStore.platform());

  static const String _storageKey = 'timma.pos.device_key.v1';

  /// Long enough that guessing is hopeless, short enough to catch a paste of
  /// something that is obviously not a key.
  static const int _minLength = 16;
  static const int _maxLength = 256;

  final SecureValueStore _store;

  /// The stored key, or null when this tablet has never been provisioned.
  ///
  /// A keystore that raises returns null rather than throwing: the kiosk must
  /// still open for business offline, and "no key" and "cannot read the key"
  /// have the same consequence — no cloud this launch.
  Future<String?> read() async {
    try {
      final String? value = await _store.read(_storageKey);
      if (value == null || !isPlausible(value)) {
        return null;
      }
      return value;
    } on Object {
      return null;
    }
  }

  /// Stores [key] if nothing is stored yet, and returns the key in force.
  ///
  /// Write-once, like the collection secret: silently replacing a live device
  /// key would point a running till at a different device identity. Rotation is
  /// an explicit ceremony, not a side effect of a rebuild.
  Future<String?> provisionIfAbsent(String? key) async {
    final String? existing = await read();
    if (existing != null) {
      return existing;
    }
    if (key == null || !isPlausible(key)) {
      return null;
    }
    try {
      await _store.write(key: _storageKey, value: key);
    } on Object {
      // Unstored means uncredentialed next launch; say so by returning null
      // rather than letting this launch look provisioned.
      return null;
    }
    return read();
  }

  /// Shape only. The server decides whether a key is real — this just refuses
  /// an empty string, a placeholder, or a pasted paragraph.
  static bool isPlausible(String value) =>
      value.length >= _minLength &&
      value.length <= _maxLength &&
      value.trim() == value;
}
