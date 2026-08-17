import 'package:flutter_test/flutter_test.dart';
import 'package:pos_core/pos_core.dart';
import 'package:pos_link/pos_link.dart';
import 'package:pos_link_flutter/pos_link_flutter.dart';
import 'package:timma_kiosk/kiosk/hub/collection_secret_owner.dart';

/// The hub owns ONE branch collection secret, for the life of the branch.
///
/// The defect these tests exist for is not exotic: a hub that mints a secret at
/// startup passes every test anyone would think to write, ships, and then
/// invalidates every slip in the building the first time somebody reboots the
/// tablet. So the assertions are about *identity across restarts* and about
/// refusing to rotate — not about the cryptography, which `pos_link` proves.
void main() {
  const String branch = 'branch-1';

  late PosStore store;
  late _MemoryValueStore keystore;

  CollectionSecretOwner owner() => CollectionSecretOwner(
    store: store,
    vault: BranchCollectionSecretVault(keystore),
  );

  setUp(() {
    store = SqlitePosStore.inMemory();
    store.writeIdentity(
      const PosDeviceIdentity(
        deviceId: 'kiosk-door',
        branchId: branch,
        role: PosDeviceRole.kiosk,
        label: 'Borne entrée',
      ),
    );
    keystore = _MemoryValueStore();
  });

  tearDown(() => store.close());

  test('a fresh hub mints one secret and records that it did', () async {
    final BranchCollectionSecret first = await owner().loadOrCreate(branch);

    expect(first.bytes, hasLength(32));
    expect(
      store.readMeta(MetaKeys.collectionSecretInitializedBranch),
      branch,
      reason:
          'the witness names the branch, so another branch cannot inherit '
          'this secret by copying app storage',
    );
    expect(
      keystore.values.values.single.contains(branch),
      isTrue,
      reason: 'the branch travels beside the encrypted value',
    );
  });

  test(
    'a restart returns the SAME secret, so printed slips still verify',
    () async {
      final BranchCollectionSecret before = await owner().loadOrCreate(branch);
      // A slip goes out of the printer here, in a customer's hand.
      final PosOrder order = _order();
      final CollectionCode printed = CollectionCode.forOrder(
        order,
        secret: before,
      );

      // Restart: brand-new owner, brand-new vault instance, same keystore and
      // same database — exactly what relaunching the app looks like.
      final BranchCollectionSecret after = await owner().loadOrCreate(branch);

      expect(after.matches(before), isTrue);
      expect(
        printed.verifies(secret: after, branchId: branch),
        isTrue,
        reason:
            'the whole reason the secret is persisted: a slip printed before '
            'the restart must still collect food after it',
      );
    },
  );

  test(
    'every paired KDS receives that one secret, not a per-pairing one',
    () async {
      final BranchCollectionSecret hub = await owner().loadOrCreate(branch);
      // Two pairings, two device credentials, one branch secret.
      final PairingRegistry first = PairingRegistry(collectionSecret: hub);
      final PairingRegistry second = PairingRegistry(collectionSecret: hub);

      expect(first.collectionSecret.matches(hub), isTrue);
      expect(second.collectionSecret.matches(hub), isTrue);
    },
  );

  test('a lost keystore value is refused, never quietly replaced', () async {
    await owner().loadOrCreate(branch);
    // The keystore entry is gone but the database remembers there was one:
    // a restored backup, a cleared keychain, a re-provisioned device.
    keystore.values.clear();

    await expectLater(
      owner().loadOrCreate(branch),
      throwsA(
        isA<CollectionSecretException>().having(
          (CollectionSecretException e) => e.failure,
          'failure',
          CollectionSecretFailure.vanished,
        ),
      ),
    );
    expect(
      keystore.values,
      isEmpty,
      reason:
          'refusing means refusing — a replacement secret here would make '
          'every slip already printed unverifiable, silently',
    );
  });

  test('corrupt stored bytes fail closed rather than rotating', () async {
    keystore.values['timma.pos.branch_collection_secret.v1'] = '{not json';

    await expectLater(
      owner().loadOrCreate(branch),
      throwsA(
        isA<CollectionSecretException>().having(
          (CollectionSecretException e) => e.failure,
          'failure',
          CollectionSecretFailure.unreadable,
        ),
      ),
    );
  });

  test("another branch's stored secret is refused", () async {
    await owner().loadOrCreate(branch);

    await expectLater(
      owner().loadOrCreate('branch-2'),
      throwsA(isA<CollectionSecretException>()),
    );
  });

  test(
    'a witness lost without the secret is repaired, not treated as a fault',
    () async {
      final BranchCollectionSecret before = await owner().loadOrCreate(branch);
      // A crash between the keystore write and the witness write leaves exactly
      // this state. It is an ordinary power cut, not a security event.
      store.writeMeta(MetaKeys.collectionSecretInitializedBranch, '');

      final BranchCollectionSecret after = await owner().loadOrCreate(branch);

      expect(after.matches(before), isTrue);
      expect(
        store.readMeta(MetaKeys.collectionSecretInitializedBranch),
        branch,
        reason: 'and the witness is put back',
      );
    },
  );

  test(
    'a keystore that cannot persist is a failure, not a secret in memory',
    () async {
      keystore.failWrites = true;

      await expectLater(
        owner().loadOrCreate(branch),
        throwsA(
          isA<CollectionSecretException>().having(
            (CollectionSecretException e) => e.failure,
            'failure',
            CollectionSecretFailure.notPersisted,
          ),
        ),
      );
      expect(
        store.readMeta(MetaKeys.collectionSecretInitializedBranch),
        isNull,
        reason:
            'no witness for a secret that was never stored, or the next '
            'launch would report it as vanished',
      );
    },
  );

  test('the secret never appears in a diagnostic string', () async {
    final BranchCollectionSecret secret = await owner().loadOrCreate(branch);
    final String rendered = '$secret';
    final String hex = secret.bytes
        .map((int byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();

    // Asserting per-byte would be meaningless: "redacted" itself contains
    // hex-looking pairs like "ed" and "ac". What matters is that no run of the
    // key survives into the rendering, and that a crash log line built from it
    // carries nothing back to a support ticket.
    expect(rendered, 'BranchCollectionSecret([redacted])');
    expect(rendered.contains(hex), isFalse);
    for (int start = 0; start + 8 <= hex.length; start += 2) {
      expect(
        rendered.contains(hex.substring(start, start + 8)),
        isFalse,
        reason: 'a secret in a crash log is a secret on a support ticket',
      );
    }
  });
}

PosOrder _order() => PosOrder(
  clientId: 'c-1',
  branchId: 'branch-1',
  origin: PosOrderOrigin.local,
  source: PosOrderSource.kiosk,
  mode: PosOrderMode.pickup,
  status: PosOrderStatus.pendingPayment,
  paymentStatus: PosPaymentStatus.unpaid,
  paymentMethod: PosPaymentMethod.payAtCounter,
  deviceSeq: 1,
  subtotal: 3500,
  discount: 0,
  deliveryFee: 0,
  total: 3500,
  ticketNumber: 42,
  placedAtDevice: DateTime.utc(2026, 8, 17, 11, 30),
  statusChangedAt: DateTime.utc(2026, 8, 17, 11, 30),
);

/// The platform keystore, in memory, with a switch for the failure that matters.
class _MemoryValueStore implements SecureValueStore {
  final Map<String, String> values = <String, String>{};
  bool failWrites = false;

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write({required String key, required String value}) async {
    if (failWrites) {
      throw StateError('keystore unavailable');
    }
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async => values.remove(key);
}
