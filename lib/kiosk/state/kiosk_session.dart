import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pos_core/pos_core.dart';
import 'package:pos_link/pos_link.dart';

import '../branch_config/kiosk_branch_config.dart';
import '../catalog/dish_photo_cache.dart';
import '../printing/print_queue.dart';
import '../printing/slip.dart';
import 'kiosk_cart.dart';

/// Where the customer is in the four-taps path.
enum KioskStage {
  /// Nobody is here. Dish photography, gentle motion, and a single invitation.
  attract,

  /// Browsing the pinned menu.
  menu,

  /// Reviewing what they built.
  cart,

  /// The sale is placed; a large calm number tells them where to pay.
  counter,

  /// No menu is pinned. The kiosk refuses loudly rather than showing an empty
  /// menu that reads as a closed kitchen (plan §K4 rule 5).
  outOfService,
}

/// What happened to this sale's slip.
///
/// It is deliberately separate from [KioskStage]: the sale is already durable
/// and the customer already has a number on screen, so printing is a **second,
/// weaker** outcome that must be reported truthfully without ever putting the
/// order itself in doubt.
enum KioskPrintState {
  /// Nothing has been queued — no sale yet, or a sale that predates printing.
  none,

  /// Queued and being sent. The customer sees "your slip is printing".
  printing,

  /// The printer acknowledged the bytes.
  printed,

  /// Every attempt failed, or no printer is provisioned. The job stays in the
  /// queue's `failed` list until a human deals with it, and the screen says so
  /// rather than implying a slip exists.
  failed,
}

class KioskSessionState {
  const KioskSessionState({
    required this.stage,
    this.placed,
    this.error,
    this.printState = KioskPrintState.none,
  });

  final KioskStage stage;

  /// The sale just placed, for the counter screen. Cleared on the way back to
  /// attract so a number never outlives its customer.
  final PlacedOrder? placed;

  /// A refusal the customer needs to see — a sold-out dish caught at placement,
  /// for instance. Never a stack trace.
  final String? error;

  /// The fate of this sale's slip. Never `printed` unless the transport said so.
  final KioskPrintState printState;
}

/// Drives the kiosk's one flow and owns the idle timeout.
///
/// **Idle clears the cart.** A basket abandoned by someone who walked away must
/// never become the next customer's order (plan §K4 rule 6) — that is a
/// stranger paying for food they did not choose, and it is the failure a public
/// unattended screen is most likely to produce.
class KioskSessionController extends Notifier<KioskSessionState> {
  Timer? _idle;

  /// True from the moment placement starts until it has committed or refused.
  bool _placing = false;

  /// The printer answers asynchronously; the screen it answers about may be
  /// long gone.
  bool _disposed = false;

  /// Long enough that a customer reading the menu is not thrown out, short
  /// enough that the next person finds a clean screen.
  static const Duration idleAfter = Duration(seconds: 90);

  /// After a sale the number is the whole point of the screen, so it holds
  /// longer than a browsing timeout — but it still returns on its own, because
  /// the customer has already walked to the counter.
  static const Duration counterHold = Duration(seconds: 45);

  @override
  KioskSessionState build() {
    ref.onDispose(() {
      _disposed = true;
      _idle?.cancel();
    });
    final PosEngine engine = ref.read(kioskEngineProvider);

    // ⚠ A fresh tablet has nothing pinned at its first launch, so it opens
    // out-of-service — and this used to be decided **once**, which meant the
    // dashboard's catalogue could arrive thirty seconds later and the borne
    // would still be showing *Borne indisponible* to every customer until
    // someone restarted it. A kiosk that has a menu must sell.
    final ValueListenable<int> revision = ref.read(kioskMenuRevisionProvider);
    void onMenuChanged() {
      if (_disposed) {
        return;
      }
      final bool haveMenu = engine.pinnedMenu != null;
      if (haveMenu && state.stage == KioskStage.outOfService) {
        state = const KioskSessionState(stage: KioskStage.attract);
      } else if (!haveMenu && state.stage == KioskStage.attract) {
        // The other direction is just as real: a branch whose whole menu is
        // withdrawn must stop taking orders rather than sell from a stale one.
        state = const KioskSessionState(stage: KioskStage.outOfService);
      }
    }

    revision.addListener(onMenuChanged);
    ref.onDispose(() => revision.removeListener(onMenuChanged));

    return KioskSessionState(
      stage: engine.pinnedMenu == null
          ? KioskStage.outOfService
          : KioskStage.attract,
    );
  }

  /// Any touch anywhere restarts the clock. Wired once at the shell so no
  /// screen has to remember to do it.
  void noteActivity() {
    if (state.stage == KioskStage.attract ||
        state.stage == KioskStage.outOfService) {
      return;
    }
    _arm(state.stage == KioskStage.counter ? counterHold : idleAfter);
  }

  void _arm(Duration after) {
    _idle?.cancel();
    _idle = Timer(after, reset);
  }

  void start() {
    if (ref.read(kioskEngineProvider).pinnedMenu == null) {
      state = const KioskSessionState(stage: KioskStage.outOfService);
      return;
    }
    state = const KioskSessionState(stage: KioskStage.menu);
    _arm(idleAfter);
  }

  void toMenu() {
    state = KioskSessionState(stage: KioskStage.menu, error: state.error);
    _arm(idleAfter);
  }

  void toCart() {
    state = const KioskSessionState(stage: KioskStage.cart);
    _arm(idleAfter);
  }

  /// Places the sale through [PosEngine], then prints its slip.
  ///
  /// **Order first, slip second, and never the other way round.** The engine
  /// prices from the pinned snapshot and commits in one transaction; nothing
  /// this class computed is sent. Only once that sale is durable does the slip
  /// get built and queued — so a printer that is off, out of paper or missing
  /// entirely costs the customer a piece of paper, never their order.
  ///
  /// [labels] and [french] come from the shell, which has the localisations
  /// already resolved to the language the customer chose. Printing must not
  /// depend on whether a screen happens to be mounted, so no `BuildContext`
  /// reaches this far.
  Future<void> confirm({
    required SlipLabels labels,
    required bool french,
  }) async {
    // A customer pressing *Commander* twice on a laggy tablet must not buy
    // their lunch twice. The guard covers the whole placement, and the stage
    // check covers a stale button in a rebuilt tree.
    if (_placing || state.stage == KioskStage.counter) {
      return;
    }
    final List<PosCartLine> lines = ref
        .read(kioskCartProvider.notifier)
        .toCartLines();
    if (lines.isEmpty) {
      return;
    }
    _placing = true;
    final PlacedOrder placed;
    try {
      placed = ref.read(kioskEngineProvider).placeKioskOrder(lines: lines);
    } on PosError catch (error) {
      // A dish sold out between browsing and confirming is the expected case
      // here, not an exceptional one: the snapshot can be re-pinned while a
      // customer is deciding. They go back to the menu with a reason.
      state = KioskSessionState(stage: KioskStage.cart, error: error.code);
      return;
    } finally {
      _placing = false;
    }

    ref.read(kioskCartProvider.notifier).clear();
    state = KioskSessionState(
      stage: KioskStage.counter,
      placed: placed,
      printState: KioskPrintState.printing,
    );
    _arm(counterHold);

    // The kitchen learns about the sale here, before the slip is even printed:
    // paper is optional, the kitchen is not.
    try {
      ref.read(kioskBoardPublisherProvider)();
    } on Object {
      // A board nobody is listening to must not cost the customer their order.
      debugPrint('[Kiosk] board publish failed — order is placed regardless');
    }
    await _printSlip(placed, labels: labels, french: french);
  }

  /// Builds the authenticated slip and queues it exactly once.
  ///
  /// The collection code is an HMAC over this order's own identity under the
  /// **persisted** branch secret, so a slip printed before a hub restart still
  /// verifies at the kitchen afterwards. Without a secret there is nothing
  /// honest to print — a slip carrying an unverifiable QR is worse than no
  /// slip, because the kitchen would refuse it at the counter instead of at
  /// the printer.
  Future<void> _printSlip(
    PlacedOrder placed, {
    required SlipLabels labels,
    required bool french,
  }) async {
    final PrintQueue? queue = ref.read(kioskPrintQueueProvider);
    final BranchCollectionSecret? secret = ref.read(
      kioskCollectionSecretProvider,
    );
    if (queue == null || secret == null) {
      _reportPrint(placed, KioskPrintState.failed);
      return;
    }
    try {
      final CollectionCode code = CollectionCode.forOrder(
        placed.order,
        secret: secret,
      );
      final Uint8List bytes = Slip.build(
        order: placed.order,
        lines: placed.lines,
        labels: labels,
        code: code,
        french: french,
        paymentCodes: ref.read(kioskBranchConfigProvider).paymentCodes,
      );
      // The order's client id IS the job id: one sale, one slip, and a reprint
      // is a deliberate separate action rather than an accident of retrying.
      final PrintJob job = await queue.enqueue(placed.order.clientId, bytes);
      _reportPrint(
        placed,
        job.state == PrintJobState.printed
            ? KioskPrintState.printed
            : KioskPrintState.failed,
      );
    } on Object {
      // Includes a slip that could not even be built — a missing ticket number
      // would be one. It is still not a reason to unpick a committed sale.
      _reportPrint(placed, KioskPrintState.failed);
    }
  }

  /// Retries the failed slip for the sale currently on the counter screen.
  Future<void> retryPrint() async {
    final PlacedOrder? placed = state.placed;
    final PrintQueue? queue = ref.read(kioskPrintQueueProvider);
    if (placed == null || queue == null || queue.failed.isEmpty) {
      return;
    }
    _reportPrint(placed, KioskPrintState.printing);
    // The customer is standing here waiting for paper, so the clock restarts.
    _arm(counterHold);
    try {
      await queue.retryFailed();
    } on Object {
      _reportPrint(placed, KioskPrintState.failed);
      return;
    }
    _reportPrint(
      placed,
      queue.failed.isEmpty ? KioskPrintState.printed : KioskPrintState.failed,
    );
  }

  /// Publishes a print outcome, but only while this sale is still the one on
  /// screen. A queue that answers after the next customer walked up must not
  /// relabel their session — and a disposed notifier must not be written at all.
  void _reportPrint(PlacedOrder placed, KioskPrintState printState) {
    if (_disposed ||
        state.stage != KioskStage.counter ||
        state.placed?.order.clientId != placed.order.clientId) {
      return;
    }
    state = KioskSessionState(
      stage: KioskStage.counter,
      placed: placed,
      printState: printState,
    );
  }

  /// Back to attract with nothing left behind.
  void reset() {
    _idle?.cancel();
    _idle = null;
    ref.read(kioskCartProvider.notifier).clear();
    ref.read(kioskLocaleProvider.notifier).reset();
    state = const KioskSessionState(stage: KioskStage.attract);
  }

  void dismissError() =>
      state = KioskSessionState(stage: state.stage, placed: state.placed);
}

final NotifierProvider<KioskSessionController, KioskSessionState>
kioskSessionProvider =
    NotifierProvider<KioskSessionController, KioskSessionState>(
      KioskSessionController.new,
    );

/// The kiosk's language. **Defaults to French**, the product's default locale
/// (CLAUDE.md §3) and the restaurant's — not to whatever the tablet's OS was
/// set to in a warehouse. A customer flips it for their own order and it
/// returns to French when the session resets, because the next person is a
/// different person.
class KioskLocaleController extends Notifier<Locale> {
  static const Locale defaultLocale = Locale('fr');

  @override
  Locale build() => defaultLocale;

  void toggle() =>
      state = state.languageCode == 'fr' ? const Locale('en') : defaultLocale;

  void reset() => state = defaultLocale;
}

final NotifierProvider<KioskLocaleController, Locale> kioskLocaleProvider =
    NotifierProvider<KioskLocaleController, Locale>(KioskLocaleController.new);

/// Overridden at the shell with the real engine, and in tests with one built on
/// an in-memory store. Nothing in `lib/kiosk/` constructs an engine itself.
final Provider<PosEngine> kioskEngineProvider = Provider<PosEngine>(
  (Ref ref) => throw UnimplementedError(
    'kioskEngineProvider must be overridden at the app shell',
  ),
);

/// The hub's persisted branch collection secret, or null on a tablet that has
/// not been provisioned yet.
///
/// Null is a deliberate, *visible* state rather than a thrown error: a kiosk
/// with no secret must still be able to take a sale and show a number. It
/// simply cannot print a slip anyone could verify, and the screen says so.
/// It is never minted here — minting on demand is what silently invalidated
/// every slip already in a customer's hand.
final Provider<BranchCollectionSecret?> kioskCollectionSecretProvider =
    Provider<BranchCollectionSecret?>((Ref ref) => null);

/// Ticks once each time the dashboard's catalogue replaces the menu on sale.
///
/// ⚠ **This is what makes "the borne updates from the dashboard" true.** The
/// menu is read live from the store, so the screen was always one rebuild away
/// from the dashboard's new prices — and nothing ever asked for that rebuild.
/// A new catalogue landed in SQLite every 15 minutes and stayed invisible until
/// somebody restarted the app.
///
/// Overridden at the shell with the catalogue's own notifier. The default never
/// ticks, which is correct for a tablet with no cloud credential: its menu
/// genuinely cannot change while it runs.
final Provider<ValueListenable<int>> kioskMenuRevisionProvider =
    Provider<ValueListenable<int>>((Ref ref) {
      final ValueNotifier<int> never = ValueNotifier<int>(0);
      ref.onDispose(never.dispose);
      return never;
    });

/// The dish photographs on disk, or null on a kiosk with no cache configured.
///
/// Overridden at the shell with a cache rooted in app-private storage. It is
/// deliberately a plain value rather than something the menu screen builds: the
/// same instance warms on every menu pin and reads on every frame, and two
/// caches over one directory would race each other's writes.
final Provider<DishPhotoCache?> kioskPhotoCacheProvider =
    Provider<DishPhotoCache?>((Ref ref) => null);

/// Publishes the authoritative board to every paired kitchen.
///
/// ⚠ **This is what makes an order appear in the kitchen.** `LanHubServer`
/// broadcasts when it applies an intent FROM a board, and its own documentation
/// says the kiosk controller must call `publishBoard()` after a local sale — and
/// nothing did. So a customer could order at the kiosk and the kitchen would sit
/// empty until a cook happened to touch something. Reported from the devices.
///
/// A function rather than the hub itself, so the sale path does not depend on
/// the LAN server at all: an unpaired kiosk overrides nothing and still sells.
final Provider<void Function()> kioskBoardPublisherProvider =
    Provider<void Function()>((Ref ref) => () {});

/// The kiosk's print queue, or null when no printer is provisioned.
///
/// Overridden at the shell with a queue over the real socket transport, and in
/// tests with one over a fake. Defaulting to null keeps the queue out of every
/// test that is not about printing, and keeps a kiosk selling on a branch whose
/// printer has not arrived yet.
final Provider<PrintQueue?> kioskPrintQueueProvider = Provider<PrintQueue?>(
  (Ref ref) => null,
);
