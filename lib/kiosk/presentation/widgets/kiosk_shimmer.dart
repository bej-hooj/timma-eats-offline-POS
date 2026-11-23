import 'package:flutter/material.dart';

import 'package:timma_kiosk/design/app_tokens.dart';

/// The waiting state of anything on the borne that is still arriving.
///
/// Owner, 2026-11-22: *"i really want the kiosk menu to be like the mobile app
/// menu view. even on the loading waving"* — the shimmer the app shows while a
/// list is coming.
///
/// ⚠ **It exists because the alternative is nothing at all.** A dish photograph
/// that is not in the cache yet renders as an empty hole until the bytes land:
/// no spinner, no panel, no sign that anything is happening. CLAUDE.md §13.2
/// calls the loading state mandatory and names skeletons rather than spinners,
/// and on a kiosk facing the street a hole in a menu card reads as a broken
/// machine rather than as a slow one.
///
/// A band of light sweeping across a muted panel, 1.4 s, which is slow enough
/// to read as *waiting* rather than as something flashing for attention on a
/// screen a queue of people is looking at.
class KioskShimmer extends StatefulWidget {
  const KioskShimmer({this.radius = 0, super.key});

  final double radius;

  @override
  State<KioskShimmer> createState() => _KioskShimmerState();
}

class _KioskShimmerState extends State<KioskShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final BorderRadius radius = BorderRadius.circular(widget.radius);

    // ⚠ A viewer who has asked for less motion gets the panel without the
    // sweep. The information — *something is coming here* — is carried by the
    // panel; the movement is only how quickly it says so.
    if (MediaQuery.disableAnimationsOf(context)) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.surfaceMuted,
          borderRadius: radius,
        ),
      );
    }

    return ClipRRect(
      borderRadius: radius,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (BuildContext context, Widget? _) {
          // -1 → 2 so the band starts and ends fully off the panel; a sweep
          // that begins at its own edge reads as a flash.
          final double t = -1 + _controller.value * 3;
          return DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment(t - 1, -0.3),
                end: Alignment(t + 1, 0.3),
                colors: const <Color>[
                  AppColors.surfaceMuted,
                  AppColors.surface,
                  AppColors.surfaceMuted,
                ],
                stops: const <double>[0.35, 0.5, 0.65],
              ),
            ),
            child: const SizedBox.expand(),
          );
        },
      ),
    );
  }
}
