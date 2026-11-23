import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:timma_kiosk/design/app_tokens.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pos_core/pos_core.dart';

import 'package:timma_kiosk/l10n/app_localizations.dart';
import 'catalog/dish_photo_cache.dart';
import 'motion/kiosk_fly_to_cart.dart';
import 'presentation/widgets/kiosk_cart_panel.dart';
import 'printing/slip.dart';
import 'hub/dev_provisioning.dart';
import 'manager/manager_gate.dart';
import 'manager/manager_screen.dart';
import 'presentation/attract_screen.dart';
import 'presentation/cart_screen.dart';
import 'presentation/composer_sheet.dart';
import 'presentation/counter_screen.dart';
import 'presentation/menu_screen.dart';
import 'state/kiosk_cart.dart';
import 'state/kiosk_session.dart';
import 'theme/kiosk_scale.dart';
import 'theme/kiosk_theme.dart';

/// The kiosk surface: one flow, no router, no auth, no Supabase session.
///
/// There is no `go_router` here on purpose. The kiosk has exactly one path —
/// attract → menu → cart → counter — with no deep links, no back stack a
/// customer can reach, and nothing to restore after a restart except a clean
/// screen. A router would be five concepts serving a state machine with five
/// states.
class KioskApp extends ConsumerWidget {
  const KioskApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      locale: ref.watch(kioskLocaleProvider),
      onGenerateTitle: (BuildContext context) =>
          AppLocalizations.of(context)!.kioskAttractTitle,
      debugShowCheckedModeBanner: false,
      theme: KioskTheme.build(),
      localizationsDelegates: const <LocalizationsDelegate<Object>>[
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      // The sample-menu ribbon wraps the whole app rather than one screen, so it
      // is visible on every stage of the flow including the counter screen.
      // The app repo learned this the expensive way: a build with fake data and
      // no visible marker cost a whole session of chasing "missing images" that
      // were never configured. If the prices on screen are not real, the screen
      // says so.
      builder: (BuildContext context, Widget? child) => child == null
          ? const SizedBox.shrink()
          : _SampleMenuRibbon(child: child),
      home: const KioskShell(),
    );
  }
}

/// A permanent, unmissable band across a kiosk whose prices are **not real**.
///
/// ⚠ It used to key on `KioskDevProvisioning.seedMenu` — the *build flag* — and
/// that is backwards. The seed carries the lowest version a snapshot can hold
/// precisely so the dashboard's catalogue supersedes it on the first fetch, so
/// a seeded build that reached the internet was selling **real prices under a
/// red band saying they were fake**. A marker that cries wolf is worse than
/// none: it is the one people learn to read past.
///
/// It now states a fact about the menu **being sold**: the band is up when, and
/// only when, the active snapshot is the sample one.
class _SampleMenuRibbon extends ConsumerWidget {
  const _SampleMenuRibbon({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Rebuilt whenever a pin changes the menu, so the band disappears the
    // moment the real catalogue takes over — no restart.
    return ValueListenableBuilder<int>(
      valueListenable: ref.watch(kioskMenuRevisionProvider),
      builder: (BuildContext context, _, Widget? _) {
        final MenuSnapshot? menu = ref.read(kioskEngineProvider).pinnedMenu;
        if (menu == null || menu.version != KioskDevProvisioning.seedVersion) {
          return child;
        }
        return _band(context);
      },
    );
  }

  Widget _band(BuildContext context) {
    return Stack(
      children: <Widget>[
        child,
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: IgnorePointer(
            child: ColoredBox(
              color: const Color(0xFFA32D2D),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text(
                    'DEBUG — MENU D\'EXEMPLE · PRIX NON RÉELS',
                    textAlign: TextAlign.center,
                    // Not localised on purpose: it is a developer marker, not
                    // product copy, and it must never be mistaken for a string
                    // a customer is meant to read.
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Owns the idle clock and swaps the one screen that is showing.
class KioskShell extends ConsumerStatefulWidget {
  const KioskShell({super.key});

  @override
  ConsumerState<KioskShell> createState() => _KioskShellState();
}

class _KioskShellState extends ConsumerState<KioskShell> {
  SnapshotProduct? _composing;

  @override
  Widget build(BuildContext context) {
    final KioskSessionState session = ref.watch(kioskSessionProvider);
    final KioskSessionController controller = ref.read(
      kioskSessionProvider.notifier,
    );

    return PopScope(
      // **No back-door out of the app** (plan §K8). At the root route Android's
      // back gesture backgrounds the app, which on an unattended kiosk hands
      // the next customer a home screen and a tablet. Refusing the pop turns
      // back into a no-op; the *real* lock is Android device owner + screen
      // pinning, but that is device configuration and this is the half that
      // travels with the code.
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (didPop) {
          return;
        }
        // A back press is treated as activity — someone is standing here — but
        // it never navigates.
        controller.noteActivity();
      },
      child: Listener(
        // Every touch anywhere restarts the idle clock, wired once here so no
        // screen has to remember to do it — a screen that forgets is a cart that
        // vanishes under a customer's hands.
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => controller.noteActivity(),
        child: Scaffold(
          // ⚠ **The colour has to go under the cutout, not stop at it.** In
          // landscape the display cutout takes a strip off one side, `SafeArea`
          // insets the content past it, and whatever the Scaffold is painted
          // with shows through — so the brand-green attract and counter screens
          // each had a pale cream band down one edge, on a screen mounted
          // facing a room. Painting the Scaffold in the stage's own colour puts
          // the green behind the cutout, where a full-bleed screen expects it,
          // and leaves every cream stage exactly as it was.
          backgroundColor: switch (session.stage) {
            KioskStage.attract ||
            KioskStage.counter ||
            KioskStage.outOfService => Theme.of(context).colorScheme.primary,
            _ => AppColors.canvas,
          },
          // ⚠ **The attract screen must not shrink for somebody else's
          // keyboard.** Long-pressing it opens the manager PIN dialog, whose
          // keypad took 263 dp of a 448 dp landscape screen; the Scaffold
          // dutifully resized the body under the dialog and the attract
          // column — which sizes itself off the height it is given — overflowed
          // by 77 px, painting a hazard stripe across the first thing a
          // customer ever sees. It has no field of its own, so it has no
          // business resizing. Every other stage keeps the default: the menu
          // has a search bar, and hiding that under the keyboard would be the
          // same bug pointing the other way.
          resizeToAvoidBottomInset: session.stage == KioskStage.attract
              ? false
              : null,
          body: SafeArea(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: _body(session, controller),
            ),
          ),
        ),
      ),
    );
  }

  /// The PIN is checked before the screen is built, so nothing about the shift
  /// or the hub is on screen until it passes.
  Future<void> _openManager(BuildContext context) async {
    final NavigatorState navigator = Navigator.of(context);
    if (!await KioskManagerGate.unlock(context) || !mounted) {
      return;
    }
    await navigator.push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => const KioskManagerScreen(),
      ),
    );
  }

  Widget _body(KioskSessionState session, KioskSessionController controller) {
    switch (session.stage) {
      case KioskStage.outOfService:
        return const KioskOutOfServiceScreen(key: ValueKey<String>('oos'));

      case KioskStage.attract:
        return KioskAttractScreen(
          key: const ValueKey<String>('attract'),
          onStart: controller.start,
          onManager: () => _openManager(context),
        );

      case KioskStage.menu:
        final SnapshotProduct? composing = _composing;
        if (composing != null) {
          return KioskComposerSheet(
            key: ValueKey<String>('composer-${composing.productId}'),
            product: composing,
            cache: ref.watch(kioskPhotoCacheProvider),
            onCancel: () => setState(() => _composing = null),
            onAdd: (KioskComposition composition) {
              ref
                  .read(kioskCartProvider.notifier)
                  .add(
                    product: composing,
                    quantity: composition.quantity,
                    variant: composition.variant,
                    options: composition.options,
                  );
              setState(() => _composing = null);
              controller.toCart();
            },
          );
        }
        return _MenuWithCartBar(
          key: const ValueKey<String>('menu'),
          onPick: (SnapshotProduct product) =>
              setState(() => _composing = product),
          onCart: controller.toCart,
        );

      case KioskStage.cart:
        final KioskCartState cart = ref.watch(kioskCartProvider);
        return KioskCartScreen(
          key: const ValueKey<String>('cart'),
          cart: cart,
          cache: ref.watch(kioskPhotoCacheProvider),
          error: session.error,
          onQuantity: ref.read(kioskCartProvider.notifier).setQuantity,
          onRemove: ref.read(kioskCartProvider.notifier).remove,
          // The slip's strings are resolved here, where the localisations
          // already reflect the language this customer chose, and handed to the
          // controller as plain text. The printer is a byte sink; it must never
          // need a mounted screen to know what to print.
          onConfirm: () => controller.confirm(
            labels: _slipLabels(context),
            french: Localizations.localeOf(context).languageCode == 'fr',
          ),
          onKeepBrowsing: controller.toMenu,
        );

      case KioskStage.counter:
        return KioskCounterScreen(
          key: const ValueKey<String>('counter'),
          placed: session.placed!,
          printState: session.printState,
          onRetryPrint: controller.retryPrint,
          onDone: controller.reset,
        );
    }
  }
}

/// The slip's four strings, in the customer's language.
///
/// They live here rather than in `Slip` because the printer has no
/// localisations delegate — and rather than in the controller because a state
/// notifier with a `BuildContext` is a controller that can only print while a
/// screen is mounted.
SlipLabels _slipLabels(BuildContext context) {
  final AppLocalizations l10n = AppLocalizations.of(context)!;
  return SlipLabels(
    header: l10n.kioskSlipHeader,
    payAtCounter: l10n.kioskCounterTitle,
    total: l10n.kioskCartTotal,
    takeAway: l10n.kioskTakeAway,
    // The PATTERN, placeholder intact — `Slip` substitutes per ingredient.
    without: l10n.kioskSlipWithout('{ingredient}'),
    // Q69 — the same PATTERN rule as `without`: one slip carries several
    // groups, and the printer cannot come back for a second translation.
    groupLabel: l10n.kioskSlipGroupLabel('{group}', '{answer}'),
    groupNone: l10n.kioskSlipGroupNone,
  );
}

class _MenuWithCartBar extends ConsumerWidget {
  /// Marks the cart bar so the add-to-cart bubble knows where to land.
  static final GlobalKey cartBarKey = GlobalKey();

  const _MenuWithCartBar({
    required this.onPick,
    required this.onCart,
    super.key,
  });

  final void Function(SnapshotProduct product) onPick;
  final VoidCallback onCart;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // ⚠ The menu lives in SQLite and `pinnedMenu` reads it live, so this
    // widget was always one rebuild away from the dashboard's new prices — and
    // nothing ever asked for that rebuild, which is why an edited menu only
    // appeared after an app restart. `ref.watch` on the provider cannot do it:
    // the notifier's identity never changes, only its value. So the listenable
    // is watched here, during build, and the menu is re-read on each tick.
    final ValueListenable<int> revision = ref.watch(kioskMenuRevisionProvider);
    final PosEngine engine = ref.read(kioskEngineProvider);
    final KioskCartState cart = ref.watch(kioskCartProvider);
    final DishPhotoCache? photos = ref.watch(kioskPhotoCacheProvider);
    final VoidCallback onToggleLanguage = ref
        .read(kioskLocaleProvider.notifier)
        .toggle;
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    final KioskCartController cartController = ref.read(
      kioskCartProvider.notifier,
    );
    return ValueListenableBuilder<int>(
      valueListenable: revision,
      builder: (BuildContext context, _, Widget? _) => _body(
        context: context,
        menu: engine.pinnedMenu,
        cart: cart,
        photos: photos,
        onToggleLanguage: onToggleLanguage,
        l10n: l10n,
        cartController: cartController,
      ),
    );
  }

  Widget _body({
    required BuildContext context,
    required MenuSnapshot? menu,
    required KioskCartState cart,
    required DishPhotoCache? photos,
    required VoidCallback onToggleLanguage,
    required AppLocalizations l10n,
    required KioskCartController cartController,
  }) {
    if (menu == null) {
      return const KioskOutOfServiceScreen();
    }
    // ⚠ The panel is a LAYOUT choice, not a different product: both shapes
    // read the same cart and reach the same confirm step. On a wide borne the
    // basket stands beside the menu, the way every reference till does it; on
    // a narrow one the bar stays, because a 340 dp panel there would squeeze
    // the grid to two columns and cost more menu than it is worth.
    final bool sideBySide = KioskCartPanel.fitsBeside(
      MediaQuery.sizeOf(context).width,
    );
    final Widget menuPane = Column(
      children: <Widget>[
        Expanded(
          child: KioskMenuScreen(
            menu: menu,
            onPick: onPick,
            onToggleLanguage: onToggleLanguage,
            photoCache: photos,
            // ⚠ The basket is written FIRST and the bubble is decoration over
            // a change that already happened. Tying the line to the end of a
            // 600 ms animation would put a lie between the tap and the truth,
            // and an idle timeout mid-flight would lose the dish entirely.
            onQuickAdd: (SnapshotProduct product, Offset from) {
              cartController.add(product: product, quantity: 1);
              final Offset? to = centerOf(cartBarKey);
              if (to != null) {
                unawaited(kioskFlyToCart(context, from: from, to: to));
              }
            },
          ),
        ),
        if (!cart.isEmpty && !sideBySide)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              KioskScale.gapXl,
              0,
              KioskScale.gapXl,
              KioskScale.gapLg,
            ),
            child: SizedBox(
              key: cartBarKey,
              width: double.infinity,
              child: FilledButton(
                onPressed: onCart,
                child: Text('${l10n.kioskCartTitle}  ·  ${cart.count}'),
              ),
            ),
          ),
      ],
    );
    if (!sideBySide) {
      return menuPane;
    }
    return Row(
      children: <Widget>[
        Expanded(child: menuPane),
        KioskCartPanel(
          cart: cart,
          photoCache: photos,
          onCheckout: onCart,
          onIncrement: (KioskCartItem item) =>
              cartController.setQuantity(item.lineId, item.quantity + 1),
          onDecrement: (KioskCartItem item) =>
              cartController.setQuantity(item.lineId, item.quantity - 1),
          onRemove: (KioskCartItem item) => cartController.remove(item.lineId),
        ),
      ],
    );
  }
}
