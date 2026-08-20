import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_core/pos_core.dart';
import 'package:pos_link/pos_link.dart';
import 'package:pos_link_flutter/pos_link_flutter.dart';
import 'package:timma_kiosk/kiosk/hub/hub_credential_store.dart';
import 'package:timma_kiosk/kiosk/manager/hub_controller.dart';
import 'package:timma_kiosk/kiosk/state/kiosk_session.dart';

/// **The address on the borne's screen has to be the address it is on.**
///
/// It was resolved once, when the hub started, and never again. So when the
/// router handed the tablet a new DHCP lease the manager screen went on
/// printing the old address, and the mDNS record went on advertising it — and a
/// kitchen dialling what the borne itself told it to dial reached nothing.
///
/// Seen on the hardware on 2026-08-20: *Borne visible sur le wifi ·
/// 192.168.1.132:8801* while the tablet's only address was `192.168.1.245`.
/// The hub was listening and healthy; not one board ever reached it, and the
/// only cure available from the product was restarting the app.
void main() {
  const String branchId = '10000000-0000-4000-8000-000000000001';
  const PosDeviceIdentity identity = PosDeviceIdentity(
    deviceId: 'dev-kiosk-samsung-01',
    branchId: branchId,
    role: PosDeviceRole.kiosk,
    label: 'Borne (test)',
  );

  group('which address a board is told to dial', () {
    test('a private-range address wins over anything else', () {
      expect(
        HubLanAddress.pick(<String>['100.64.3.9', '192.168.1.245']),
        '192.168.1.245',
        reason: 'a restaurant LAN is 192.168/10/172 — the other is carrier NAT',
      );
      expect(HubLanAddress.pick(<String>['10.0.0.7']), '10.0.0.7');
    });

    test('a link-local address is never printed', () {
      // 169.254 means DHCP failed. Nothing on the wifi can reach this kiosk,
      // so showing it sends a manager to type a number that cannot work.
      expect(HubLanAddress.pick(<String>['169.254.11.2']), '');
      expect(
        HubLanAddress.pick(<String>['169.254.11.2', '192.168.0.4']),
        '192.168.0.4',
      );
    });

    test('no address at all is not an address', () {
      expect(HubLanAddress.pick(<String>[]), '');
      expect(HubLanAddress.pick(<String>['']), '');
    });
  });

  test('the borne follows its own address when the lease changes', () async {
    // The tablet starts on one address and is moved to another, exactly as a
    // router does overnight. Nothing about the hub changes: same socket, same
    // pairing registry, same process.
    List<String> addresses = <String>['192.168.1.132'];

    final PosStore store = SqlitePosStore.inMemory();
    addTearDown(store.close);
    store.writeIdentity(identity);

    final ProviderContainer c = ProviderContainer(
      overrides: [
        kioskEngineProvider.overrideWithValue(
          PosEngine(store: store, identity: identity),
        ),
        kioskCollectionSecretProvider.overrideWithValue(
          BranchCollectionSecret.fromBytes(
            List<int>.generate(32, (int i) => (i * 5 + 1) % 256),
          ),
        ),
        hubCredentialStoreProvider.overrideWithValue(
          HubCredentialStore(_MemoryKeystore()),
        ),
        lanAddressesProvider.overrideWithValue(() async => addresses),
        // Short enough for a test to finish, long enough to be a real timer.
        hubAddressWatchProvider.overrideWithValue(
          const Duration(milliseconds: 50),
        ),
      ],
    );
    addTearDown(c.dispose);

    final HubController hub = c.read(hubProvider.notifier);
    await hub.start();
    addTearDown(hub.stop);

    expect(
      c.read(hubProvider).running,
      isTrue,
      reason: 'error was ${c.read(hubProvider).error}',
    );
    expect(c.read(hubProvider).endpoint?.host, '192.168.1.132');
    final int port = c.read(hubProvider).endpoint!.port;

    // The lease changes underneath a running hub.
    addresses = <String>['192.168.1.245'];

    // ⚠ Nothing is called here on purpose. The defect was not a wrong answer
    // from the resolver — the resolver was right both times — it was that
    // nothing ever asked it again. So this waits on the controller's own timer,
    // and a test that poked `_syncEndpoint` by hand would have passed against
    // the broken code.
    await _until(
      () => c.read(hubProvider).endpoint?.host == '192.168.1.245',
      reason: 'the borne kept printing an address it had moved off, which is '
          'what the kitchen was dialling',
    );

    expect(
      c.read(hubProvider).endpoint?.port,
      port,
      reason: 'the socket did not move — only the address did',
    );
    expect(
      c.read(hubProvider).running,
      isTrue,
      reason: 're-advertising must not take the hub down mid-service',
    );
  });

  test('an address that has not moved is left alone', () async {
    // The re-check runs for the whole service. If a steady address churned the
    // mDNS registration every fifteen seconds, discovery would be worse than
    // no discovery — a board would see the borne appear and vanish.
    final PosStore store = SqlitePosStore.inMemory();
    addTearDown(store.close);
    store.writeIdentity(identity);

    final ProviderContainer c = ProviderContainer(
      overrides: [
        kioskEngineProvider.overrideWithValue(
          PosEngine(store: store, identity: identity),
        ),
        kioskCollectionSecretProvider.overrideWithValue(
          BranchCollectionSecret.fromBytes(
            List<int>.generate(32, (int i) => (i * 5 + 1) % 256),
          ),
        ),
        hubCredentialStoreProvider.overrideWithValue(
          HubCredentialStore(_MemoryKeystore()),
        ),
        lanAddressesProvider.overrideWithValue(
          () async => <String>['192.168.1.245'],
        ),
        hubAddressWatchProvider.overrideWithValue(
          const Duration(milliseconds: 20),
        ),
      ],
    );
    addTearDown(c.dispose);

    final HubController hub = c.read(hubProvider.notifier);
    await hub.start();
    addTearDown(hub.stop);
    final HubEndpoint? first = c.read(hubProvider).endpoint;

    await Future<void>.delayed(const Duration(milliseconds: 150));

    expect(identical(c.read(hubProvider).endpoint, first), isTrue);
  });
}

Future<void> _until(
  bool Function() predicate, {
  required String reason,
  Duration within = const Duration(seconds: 5),
}) async {
  final DateTime deadline = DateTime.now().add(within);
  while (DateTime.now().isBefore(deadline)) {
    if (predicate()) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail(reason);
}

class _MemoryKeystore implements SecureValueStore {
  final Map<String, String> values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write({required String key, required String value}) async =>
      values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);
}
