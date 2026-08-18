import 'package:flutter/material.dart';

import 'package:timma_kiosk/design/timma_mark.dart';
import 'package:timma_kiosk/l10n/app_localizations.dart';
import '../theme/kiosk_scale.dart';

/// The screen nobody is standing at. Its whole job is to say *this is where you
/// order* from across the room, and to invite one tap.
///
/// **Motion budget: one element** (the F-pass rule is 1–2 per view, and this
/// view has the least reason of any to spend both). The invitation breathes;
/// nothing else moves. The attract loop is the one place a slower motion is
/// allowed, because there is no customer waiting on it — a 200 ms curve here
/// would read as a twitch in an empty room.
class KioskAttractScreen extends StatefulWidget {
  const KioskAttractScreen({required this.onStart, this.onManager, super.key});

  final VoidCallback onStart;

  /// Opened by a **long press on the mark**, and by nothing else.
  ///
  /// The kiosk is unattended and facing the street: a visible *Responsable*
  /// button is a door for whoever walks up to it. A long press on the logo is
  /// discoverable by staff who are told about it once, and invisible to
  /// everyone else. `PopScope` still refuses the back gesture, so this remains
  /// the only way out of the customer flow (§K8).
  final VoidCallback? onManager;

  @override
  State<KioskAttractScreen> createState() => _KioskAttractScreenState();
}

class _KioskAttractScreenState extends State<KioskAttractScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _breath = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 3),
  );

  @override
  void initState() {
    super.initState();
    // Only when the platform allows it. `disableAnimations` is the
    // accessibility setting a customer with vestibular sensitivity has already
    // set on their own device and expects every screen to honour.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      if (!MediaQuery.of(context).disableAnimations) {
        _breath.repeat(reverse: true);
      }
    });
  }

  @override
  void dispose() {
    _breath.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    final ThemeData theme = Theme.of(context);
    return Semantics(
      button: true,
      label: l10n.kioskAttractTitle,
      child: GestureDetector(
        // The whole screen is the target. A customer walking up does not look
        // for a button.
        behavior: HitTestBehavior.opaque,
        onTap: widget.onStart,
        // ⚠ On the SAME detector as `onTap`, deliberately. A long press on an
        // inner widget wrapped by this one lost the gesture arena: Flutter's
        // tap recogniser has no maximum duration, so a hold-then-release fired
        // `onStart` as well and the manager screen never appeared (measured on
        // the Samsung). One detector means the arena picks exactly one winner.
        onLongPress: widget.onManager,
        child: ColoredBox(
          color: theme.colorScheme.primary,
          // ⚠ Sized off the height it has, not off constants. At 411 dp — the
          // Samsung in landscape — the fixed 160 dp mark plus two `gapXxl`
          // spacers overflowed this column by 91 px, on the one screen a
          // customer sees before they have touched anything. The mark and the
          // gaps give way; the invitation to touch never does.
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final double height = constraints.maxHeight.isFinite
                  ? constraints.maxHeight
                  : 800;
              final double markSize = (height * 0.22).clamp(72.0, 160.0);
              final double breather = (height * 0.08).clamp(
                KioskScale.gapMd,
                KioskScale.gapXxl,
              );
              // ⚠ **And it must not overflow even when the height is taken
              // away.** Not resizing (see `kiosk_app.dart`) is the right
              // behaviour; being unable to survive a short viewport is a
              // separate fragility, and this screen has now overflowed twice —
              // 91 px from fixed sizes, 77 px from the manager keypad. A scroll
              // view cannot overflow, so at any height the worst case is a
              // screen a finger can move rather than a hazard stripe across the
              // first thing a customer sees.
              return SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: height),
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        // The real TIMMA logo, the same asset the customer app
                        // ships. A customer who met the brand on their phone should
                        // recognise the screen they walk up to — the abstract mark
                        // this replaced was ours, not theirs.
                        //
                        // It degrades to the vector mark rather than to a broken
                        // image box: an attract screen with a grey glyph on it is
                        // the first thing anyone sees of the restaurant.
                        Image.asset(
                          'assets/branding/logo_inline.png',
                          height: markSize,
                          fit: BoxFit.contain,
                          errorBuilder:
                              (BuildContext _, Object _, StackTrace? _) =>
                                  TimmaMark(
                                    size: markSize,
                                    color: theme.colorScheme.onPrimary,
                                  ),
                        ),
                        SizedBox(height: breather),
                        Text(
                          l10n.kioskAttractTitle,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.displayLarge?.copyWith(
                            color: theme.colorScheme.onPrimary,
                          ),
                        ),
                        const SizedBox(height: KioskScale.gap),
                        Text(
                          l10n.kioskTakeAway,
                          style: theme.textTheme.titleLarge?.copyWith(
                            color: theme.colorScheme.onPrimary.withValues(
                              alpha: 0.75,
                            ),
                          ),
                        ),
                        SizedBox(height: breather),
                        FadeTransition(
                          opacity: Tween<double>(begin: 0.45, end: 1).animate(
                            CurvedAnimation(
                              parent: _breath,
                              curve: Curves.easeInOut,
                            ),
                          ),
                          child: Text(
                            l10n.kioskAttractSubtitle,
                            style: theme.textTheme.headlineLarge?.copyWith(
                              color: theme.colorScheme.onPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
