import 'package:pos_core/pos_core.dart';
import 'package:pos_link/pos_link.dart';
import 'package:pos_link_flutter/pos_link_flutter.dart';

/// Why a hub cannot simply mint a collection secret at startup.
///
/// The secret keys the HMAC in every printed slip's QR. If the hub minted a new
/// one on each launch, every slip already in a customer's hand would stop
/// verifying the moment the tablet was restarted — a customer holding a valid
/// ticket that the kitchen refuses. So the branch secret is generated **once**,
/// persisted in the platform keystore, and reused for the life of the branch.
///
/// The pairing registry no longer accepts "no secret" and quietly invents one;
/// this class is the single place allowed to create the first one.
enum CollectionSecretFailure {
  /// The store says this hub already initialised a secret, but the keystore has
  /// nothing. Minting a replacement would invalidate printed slips, so the hub
  /// refuses and asks for the recovery ceremony instead.
  vanished,

  /// Stored bytes could not be decoded, or belong to another branch. Never
  /// recovered by overwriting: that is the same silent rotation by another name.
  unreadable,

  /// The keystore refused to persist or to read back what was written. A secret
  /// that only exists in memory would be lost on the next restart, taking every
  /// slip printed in between with it.
  notPersisted,
}

class CollectionSecretException implements Exception {
  const CollectionSecretException(this.failure, [this.code]);

  final CollectionSecretFailure failure;

  /// The vault's own stable, redacted code, when it had one. Never the bytes.
  final String? code;

  @override
  String toString() => 'CollectionSecretException(${failure.name}, $code)';
}

/// Loads this branch's collection secret, creating it only on a genuinely
/// fresh hub.
///
/// The store keeps a **non-secret witness** beside the keystore value. Two
/// places, because they fail in different ways: app storage can be cleared
/// without the keystore, and a keystore entry can be lost while the database
/// survives. Only "neither has anything" is a new branch; "witness but no
/// secret" is a fault, and faults here are refused rather than papered over.
class CollectionSecretOwner {
  const CollectionSecretOwner({required this.store, required this.vault});

  final PosStore store;
  final BranchCollectionSecretVault vault;

  Future<BranchCollectionSecret> loadOrCreate(String branchId) async {
    final String? witness = store.readMeta(
      MetaKeys.collectionSecretInitializedBranch,
    );

    final BranchCollectionSecret? stored;
    try {
      stored = await vault.read(branchId: branchId);
    } on BranchCollectionSecretVaultException catch (error) {
      throw CollectionSecretException(
        CollectionSecretFailure.unreadable,
        error.code,
      );
    } on Object {
      // A platform keystore can fail in ways that are not the vault's own
      // vocabulary — a dead channel, a locked keychain, an OEM implementation
      // returning something unexpected. This runs before `runApp`, so an
      // escaping exception is a tablet that shows nothing at all. Caught
      // deliberately broadly, and reported without the underlying message so a
      // platform error string can never carry key material into a log.
      throw const CollectionSecretException(CollectionSecretFailure.unreadable);
    }
    if (stored != null) {
      // Repair a missing or stale witness, which is not secret and is cheap to
      // rewrite. The secret itself is never touched on this path.
      if (witness != branchId) {
        store.writeMeta(MetaKeys.collectionSecretInitializedBranch, branchId);
      }
      return stored;
    }

    if (witness != null) {
      throw const CollectionSecretException(CollectionSecretFailure.vanished);
    }

    // A brand-new hub: generate once, from `Random.secure`, and persist before
    // returning so nothing can be signed with a secret that was never stored.
    final BranchCollectionSecret fresh = BranchCollectionSecret.generate();
    try {
      await vault.writeOnce(branchId: branchId, secret: fresh);
    } on BranchCollectionSecretVaultException catch (error) {
      throw CollectionSecretException(
        CollectionSecretFailure.notPersisted,
        error.code,
      );
    } on Object {
      // Same reasoning as the read path: a keystore that raises something the
      // vault does not name must still leave a diagnosable screen, and must
      // never leave a witness behind claiming a secret was stored.
      throw const CollectionSecretException(
        CollectionSecretFailure.notPersisted,
      );
    }
    // The witness is written last, and deliberately so: a crash between the two
    // leaves the keystore holding the secret and the witness absent, which the
    // read path above repairs. The reverse order would manufacture the
    // "vanished" fault out of an ordinary power cut.
    store.writeMeta(MetaKeys.collectionSecretInitializedBranch, branchId);
    return fresh;
  }
}
