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
  const KioskAttractScreen({required this.onStart, super.key});

  final VoidCallback onStart;

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
        child: ColoredBox(
          color: theme.colorScheme.primary,
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                TimmaMark(size: 160, color: theme.colorScheme.onPrimary),
                const SizedBox(height: KioskScale.gapXxl),
                Text(
                  l10n.kioskAttractTitle,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.displayLarge?.copyWith(
                    color: theme.colorScheme.onPrimary,
                  ),
                ),
                const SizedBox(height: KioskScale.gapMd),
                Text(
                  l10n.kioskTakeAway,
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: theme.colorScheme.onPrimary.withValues(alpha: 0.75),
                  ),
                ),
                const SizedBox(height: KioskScale.gapXxl),
                FadeTransition(
                  opacity: Tween<double>(begin: 0.45, end: 1).animate(
                    CurvedAnimation(parent: _breath, curve: Curves.easeInOut),
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
      ),
    );
  }
}
