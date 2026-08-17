import 'dart:async';

import 'package:flutter/widgets.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pos_core/pos_core.dart';

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

class KioskSessionState {
  const KioskSessionState({
    required this.stage,
    this.placed,
    this.error,
  });

  final KioskStage stage;

  /// The sale just placed, for the counter screen. Cleared on the way back to
  /// attract so a number never outlives its customer.
  final PlacedOrder? placed;

  /// A refusal the customer needs to see — a sold-out dish caught at placement,
  /// for instance. Never a stack trace.
  final String? error;
}

/// Drives the kiosk's one flow and owns the idle timeout.
///
/// **Idle clears the cart.** A basket abandoned by someone who walked away must
/// never become the next customer's order (plan §K4 rule 6) — that is a
/// stranger paying for food they did not choose, and it is the failure a public
/// unattended screen is most likely to produce.
class KioskSessionController extends Notifier<KioskSessionState> {
  Timer? _idle;

  /// Long enough that a customer reading the menu is not thrown out, short
  /// enough that the next person finds a clean screen.
  static const Duration idleAfter = Duration(seconds: 90);

  /// After a sale the number is the whole point of the screen, so it holds
  /// longer than a browsing timeout — but it still returns on its own, because
  /// the customer has already walked to the counter.
  static const Duration counterHold = Duration(seconds: 45);

  @override
  KioskSessionState build() {
    ref.onDispose(() => _idle?.cancel());
    final PosEngine engine = ref.read(kioskEngineProvider);
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

  /// Places the sale through [PosEngine]. The engine prices it from the pinned
  /// snapshot; nothing this class computed is sent.
  void confirm() {
    final List<PosCartLine> lines = ref.read(kioskCartProvider.notifier)
        .toCartLines();
    if (lines.isEmpty) {
      return;
    }
    try {
      final PlacedOrder placed = ref
          .read(kioskEngineProvider)
          .placeKioskOrder(lines: lines);
      ref.read(kioskCartProvider.notifier).clear();
      state = KioskSessionState(stage: KioskStage.counter, placed: placed);
      _arm(counterHold);
    } on PosError catch (error) {
      // A dish sold out between browsing and confirming is the expected case
      // here, not an exceptional one: the snapshot can be re-pinned while a
      // customer is deciding. They go back to the menu with a reason.
      state = KioskSessionState(stage: KioskStage.cart, error: error.code);
    }
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

  void toggle() => state = state.languageCode == 'fr'
      ? const Locale('en')
      : defaultLocale;

  void reset() => state = defaultLocale;
}

final NotifierProvider<KioskLocaleController, Locale> kioskLocaleProvider =
    NotifierProvider<KioskLocaleController, Locale>(
      KioskLocaleController.new,
    );

/// Overridden at the shell with the real engine, and in tests with one built on
/// an in-memory store. Nothing in `lib/kiosk/` constructs an engine itself.
final Provider<PosEngine> kioskEngineProvider = Provider<PosEngine>(
  (Ref ref) => throw UnimplementedError(
    'kioskEngineProvider must be overridden at the app shell',
  ),
);
