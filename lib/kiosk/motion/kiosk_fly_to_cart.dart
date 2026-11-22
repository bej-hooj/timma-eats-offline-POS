import 'package:flutter/material.dart';

import 'package:timma_kiosk/design/app_tokens.dart';

/// The add-to-cart flight, ported from the customer app so the borne's "+"
/// behaves the way the phone's does (owner, 2026-11-22: *"even the procedure
/// of composing to the cart on the mobile app should be the same on kiosk with
/// even fly add-to-cart"*).
///
/// A green bubble leaves the "+" that was tapped and arcs down to the cart bar.
///
/// ## Why an `OverlayEntry`
///
/// The bubble travels from a card — inside a clipping, scrolling grid — to the
/// cart bar, which is a sibling of that grid. Anything drawn inside the card is
/// clipped at the card's own rounded edge about 20 ms into the flight. The
/// overlay sits above the whole route, so for the 600 ms it exists the bubble
/// owns the screen.
///
/// ## It is decoration over a change that already happened
///
/// ⚠ **The cart is written BEFORE this runs, never when the bubble lands.**
/// Tying the mutation to the end of an animation puts a 600 ms lie between the
/// tap and the truth, and a customer whose idle timer fires mid-flight would
/// have tapped "+" and got nothing. Reduced motion skips the flight entirely —
/// the dish is in the cart either way.
Future<void> kioskFlyToCart(
  BuildContext context, {
  required Offset from,
  required Offset to,
}) async {
  final bool reduced = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
  if (reduced) {
    return;
  }
  final OverlayState? overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) {
    return;
  }
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _Bubble(from: from, to: to, onDone: entry.remove),
  );
  overlay.insert(entry);
}

/// The centre of a widget in global coordinates, or null when it is not laid
/// out. Used for both ends of the flight.
Offset? centerOf(GlobalKey key) {
  final RenderObject? box = key.currentContext?.findRenderObject();
  if (box is! RenderBox || !box.hasSize) {
    return null;
  }
  return box.localToGlobal(box.size.center(Offset.zero));
}

class _Bubble extends StatefulWidget {
  const _Bubble({required this.from, required this.to, required this.onDone});

  final Offset from;
  final Offset to;
  final VoidCallback onDone;

  @override
  State<_Bubble> createState() => _BubbleState();
}

class _BubbleState extends State<_Bubble> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
  );

  static const double _diameter = 26;

  @override
  void initState() {
    super.initState();
    _c.forward().whenComplete(widget.onDone);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (BuildContext context, _) {
        final double t = Curves.easeInOutCubic.transform(_c.value);
        // A straight line reads like a file being moved. The arc is what makes
        // it read as a thing being thrown into the basket: lift early, fall
        // into the target.
        final double lift = -120 * (1 - (2 * t - 1) * (2 * t - 1));
        final Offset p = Offset(
          widget.from.dx + (widget.to.dx - widget.from.dx) * t,
          widget.from.dy + (widget.to.dy - widget.from.dy) * t + lift,
        );
        final double scale = 1 - 0.35 * t;
        return Positioned(
          left: p.dx - _diameter / 2,
          top: p.dy - _diameter / 2,
          child: IgnorePointer(
            child: Opacity(
              opacity: t > 0.85 ? (1 - t) / 0.15 : 1,
              child: Transform.scale(
                scale: scale,
                child: Container(
                  width: _diameter,
                  height: _diameter,
                  decoration: const BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.add,
                    size: 16,
                    color: AppColors.onPrimary,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
