import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pos_core/pos_core.dart';
import 'package:pos_link/pos_link.dart';
import 'package:pos_link_flutter/pos_link_flutter.dart';

import '../state/kiosk_session.dart';
import '../hub/hub_credential_store.dart';

/// What the manager screen knows about the hub.
@immutable
class HubState {
  const HubState({
    this.running = false,
    this.endpoint,
    this.code,
    this.codeExpiresAt,
    this.pairedBoards = 0,
    this.error,
  });

  /// The LAN server is listening and, if mDNS worked, advertising.
  final bool running;

  /// Where a board should connect. Shown on screen because a restaurant wifi
  /// that blocks multicast leaves typing it by hand as the only way in.
  final HubEndpoint? endpoint;

  /// The six digits currently on screen, or null when no pairing is open.
  ///
  /// ⚠ This value NEVER goes near a log, a health endpoint or an analytics
  /// event. It is the input to the key derivation, and it is deliberately the
  /// one secret a human reads off the screen and types on the other device —
  /// it is never transmitted (ECOSYSTEM §23.9).
  final String? code;
  final DateTime? codeExpiresAt;

  /// Boards currently authenticated on the socket.
  final int pairedBoards;

  /// A stable, human-facing failure code. Never an exception's message.
  final String? error;

  HubState copyWith({
    bool? running,
    HubEndpoint? endpoint,
    String? code,
    DateTime? codeExpiresAt,
    int? pairedBoards,
    String? error,
    bool clearCode = false,
    bool clearError = false,
  }) => HubState(
    running: running ?? this.running,
    endpoint: endpoint ?? this.endpoint,
    code: clearCode ? null : (code ?? this.code),
    codeExpiresAt: clearCode ? null : (codeExpiresAt ?? this.codeExpiresAt),
    pairedBoards: pairedBoards ?? this.pairedBoards,
    error: clearError ? null : (error ?? this.error),
  );
}

/// Stable codes the screen turns into French. Never raw exception text: an
/// exception message is written for a developer and can carry internals.
abstract final class HubErrorCode {
  static const String startFailed = 'hub_start_failed';
  static const String pairingFailed = 'hub_pairing_failed';
  static const String noSecret = 'hub_no_collection_secret';
}

/// Runs the kiosk's LAN hub: the socket boards connect to, its mDNS
/// advertisement, and the pairing code a manager reads out.
///
/// **Why the kiosk is the hub.** One writer owns the shift's orders (§23.2). The
/// board applies what the hub sends and sends back intents; it never writes the
/// order state itself, so there is no split brain when the internet returns.
class HubController extends Notifier<HubState> {
  LanHubServer? _server;
  NsdHubDiscovery? _discovery;
  Timer? _poll;
  Timer? _addressWatch;

  /// What the socket actually bound to — `0.0.0.0`, every interface. Kept so
  /// the LAN address can be resolved again later against the same port.
  HubEndpoint? _bound;

  /// How often the kiosk re-checks its own address on the wifi.
  ///
  /// ⚠ **The address is not a constant, and this code used to assume it was.**
  /// It was resolved once, at start-up, and never again — so when the router
  /// handed the tablet a new DHCP lease the manager screen went on printing the
  /// old address and mDNS went on advertising it. A kitchen then dialled an
  /// address nothing answers, and the borne's own screen was the thing telling
  /// it to. Seen on the hardware on 2026-08-20: the screen said
  /// `192.168.1.132` while the tablet was on `192.168.1.245`, and no board
  /// reached the hub at all until the app was restarted by hand.
  ///
  /// Unhurried on purpose — a lease change is rare and this is a syscall — but
  /// far shorter than the time it takes a manager to walk to the kitchen,
  /// because until it fires the screen is lying.
  static const Duration addressWatchEvery = Duration(seconds: 15);

  @override
  HubState build() {
    ref.onDispose(stop);
    return const HubState();
  }

  /// Starts the socket and begins advertising. Idempotent.
  Future<void> start() async {
    if (_server != null) {
      return;
    }
    final BranchCollectionSecret? secret = ref.read(
      kioskCollectionSecretProvider,
    );
    if (secret == null) {
      // Without the branch secret a paired board could not be handed the key
      // that verifies printed slips, so pairing would produce a board that
      // cannot do its one offline job.
      state = state.copyWith(error: HubErrorCode.noSecret);
      return;
    }

    final PosEngine engine = ref.read(kioskEngineProvider);
    try {
      // ⚠ Hydrated BEFORE the socket opens. `PairingRegistry` defaults to an
      // in-memory credential store, so every restart forgot every paired
      // kitchen: the board kept presenting a credential the hub had never heard
      // of, and a restaurant saw the kiosk asking to pair again while the
      // kitchen insisted it already had.
      final HubCredentialStore credentials = ref.read(
        hubCredentialStoreProvider,
      );
      await credentials.load();

      final LanHubServer server = LanHubServer(
        engine: engine,
        // The registry is owned by the server: every claim it accepts is one
        // the server verified, so there is no second path to a credential.
        pairing: PairingRegistry(
          collectionSecret: secret,
          credentialStore: credentials,
        ),
      );
      final HubEndpoint bound = await server.start();
      // ⚠ The server binds every interface, so it reports `0.0.0.0` — which is
      // exactly the one address a board cannot dial. The screen must show the
      // kiosk's real address on the restaurant LAN, because a manager reads it
      // off this screen and types it into the board when multicast is blocked.
      final HubEndpoint endpoint = await _reachableEndpoint(bound);

      _server = server;
      _bound = bound;
      state = state.copyWith(
        running: true,
        endpoint: endpoint,
        clearError: true,
      );

      // Best effort: a wifi that blocks multicast is common in restaurants, and
      // the address printed on this screen is the documented way through it.
      unawaited(_advertise(engine.identity, endpoint));

      // The peer count is polled rather than streamed because the server
      // exposes a count, and a manager screen refreshing once a second is
      // cheaper to reason about than another broadcast stream.
      _poll = Timer.periodic(const Duration(seconds: 1), (_) {
        final LanHubServer? live = _server;
        if (live == null) {
          return;
        }
        final int peers = live.connectedPeerCount;
        if (peers != state.pairedBoards) {
          state = state.copyWith(pairedBoards: peers);
        }
      });

      // And the address is re-checked for as long as the hub runs, so a new
      // lease costs a kitchen fifteen seconds rather than a restart nobody
      // knows to perform.
      _addressWatch = Timer.periodic(
        ref.read(hubAddressWatchProvider),
        (_) => unawaited(_syncEndpoint(engine.identity)),
      );
    } on Object {
      state = state.copyWith(error: HubErrorCode.startFailed, running: false);
    }
  }

  /// Replaces a wildcard bind address with this device's LAN address.
  ///
  /// Prefers a private-range IPv4 — a restaurant LAN is 192.168/10/172.x — and
  /// falls back to any non-loopback IPv4, then to what the server reported.
  /// A 169.254 link-local address is skipped: that means DHCP failed and
  /// nothing else on the wifi can reach this kiosk anyway.
  Future<HubEndpoint> _reachableEndpoint(HubEndpoint bound) async {
    if (bound.host != '0.0.0.0' && bound.host != '::') {
      return bound;
    }
    try {
      final List<String> addresses = await ref.read(lanAddressesProvider)();
      final String lan = HubLanAddress.pick(addresses);
      if (lan.isNotEmpty) {
        return HubEndpoint(host: lan, port: bound.port);
      }
    } on Object {
      // Cosmetic enough that throwing here — and taking the hub down with it —
      // would be the worse failure.
      debugPrint('[Hub] could not resolve a LAN address');
    }
    return bound;
  }

  /// Re-resolves this device's address and, if it moved, re-publishes it — on
  /// the screen a manager reads and in the mDNS record a board discovers.
  ///
  /// The advertisement is torn down and raised again rather than edited: an
  /// mDNS record carries the address inside it, so leaving the old registration
  /// up would keep pointing boards at an address that has gone.
  Future<void> _syncEndpoint(PosDeviceIdentity identity) async {
    final HubEndpoint? bound = _bound;
    if (_server == null || bound == null) {
      return;
    }
    final HubEndpoint fresh = await _reachableEndpoint(bound);
    final HubEndpoint? shown = state.endpoint;
    if (shown != null && fresh.host == shown.host && fresh.port == shown.port) {
      return;
    }
    debugPrint('[Hub] the LAN address moved — re-advertising');
    state = state.copyWith(endpoint: fresh);
    final NsdHubDiscovery? stale = _discovery;
    _discovery = null;
    await stale?.close();
    await _advertise(identity, fresh);
  }

  Future<void> _advertise(
    PosDeviceIdentity identity,
    HubEndpoint endpoint,
  ) async {
    try {
      final NsdHubDiscovery discovery = NsdHubDiscovery();
      await discovery.advertise(
        HubAdvertisement(
          endpoint: endpoint,
          hubDeviceId: identity.deviceId,
          hubLabel: identity.label,
          branchId: identity.branchId,
        ),
      );
      _discovery = discovery;
    } on Object {
      // Not an error the manager can act on: the screen already shows the
      // address, which is the fallback for exactly this case.
      debugPrint('[Hub] mDNS advertise unavailable — address shown instead');
    }
  }

  /// Opens a pairing window and returns the six digits to show.
  Future<void> beginPairing() async {
    final LanHubServer? server = _server;
    if (server == null) {
      await start();
    }
    final LanHubServer? live = _server;
    if (live == null) {
      return;
    }
    try {
      final PairingCode code = await live.beginPairing();
      state = state.copyWith(
        code: code.value,
        codeExpiresAt: code.expiresAt,
        clearError: true,
      );
    } on Object {
      state = state.copyWith(error: HubErrorCode.pairingFailed);
    }
  }

  /// Drops the code from the screen and from state once it expires or the
  /// manager closes the sheet. The registry keeps its own expiry; this is the
  /// visible half.
  void clearCode() => state = state.copyWith(clearCode: true);

  /// Pushes the current board to every authenticated kitchen.
  ///
  /// Safe to call when no hub is running or no board is paired — the kiosk sells
  /// either way, and this is the notification, not the sale.
  void publishBoard() => _server?.publishBoard();

  Future<void> stop() async {
    _poll?.cancel();
    _poll = null;
    _addressWatch?.cancel();
    _addressWatch = null;
    _bound = null;
    final LanHubServer? server = _server;
    final NsdHubDiscovery? discovery = _discovery;
    _server = null;
    _discovery = null;
    await discovery?.close();
    await server?.close();
  }
}

/// The hub's keystore-backed credential store.
///
/// Behind a provider for the same reason the vaults on the board are: a
/// platform channel cannot exist on a host, and without a seam the whole of
/// [HubController.start] — the socket, the advertisement, the address watch —
/// could only be exercised by hand on a tablet.
final Provider<HubCredentialStore> hubCredentialStoreProvider =
    Provider<HubCredentialStore>((Ref ref) => HubCredentialStore.platform());

/// How often [HubController] re-checks its own LAN address. Overridden in tests
/// so the timer itself is proven, rather than only the method it calls.
final Provider<Duration> hubAddressWatchProvider = Provider<Duration>(
  (Ref ref) => HubController.addressWatchEvery,
);

/// Picks the address a board should dial, out of everything this device has.
///
/// Prefers a private-range IPv4 — a restaurant LAN is 192.168/10/172.x — and
/// falls back to any other non-loopback IPv4. A `169.254` link-local address is
/// skipped: that means DHCP failed, and nothing else on the wifi can reach this
/// kiosk anyway, so printing it would send a manager chasing a dead number.
///
/// Pure, and separate from the controller, because this is the part with the
/// rules in it and a rule that can only be exercised by changing a router's
/// lease is a rule nobody checks again.
abstract final class HubLanAddress {
  static String pick(List<String> addresses) {
    final Iterable<String> usable = addresses.where(
      (String a) => a.isNotEmpty && !a.startsWith('169.254.'),
    );
    if (usable.isEmpty) {
      return '';
    }
    return usable.firstWhere(
      (String a) =>
          a.startsWith('192.168.') ||
          a.startsWith('10.') ||
          a.startsWith('172.'),
      orElse: () => usable.first,
    );
  }
}

/// This device's own IPv4 addresses.
///
/// Behind a provider so the address-change path can be proven on a host: a test
/// cannot make a router hand out a new lease, and that path had shipped
/// unexercised once already.
final Provider<Future<List<String>> Function()> lanAddressesProvider =
    Provider<Future<List<String>> Function()>((Ref ref) => _deviceAddresses);

Future<List<String>> _deviceAddresses() async {
  final List<NetworkInterface> interfaces = await NetworkInterface.list(
    includeLoopback: false,
    type: InternetAddressType.IPv4,
  );
  return <String>[
    for (final NetworkInterface interface in interfaces)
      for (final InternetAddress address in interface.addresses)
        address.address,
  ];
}

final NotifierProvider<HubController, HubState> hubProvider =
    NotifierProvider<HubController, HubState>(HubController.new);
