import 'package:flutter/material.dart';

import 'package:timma_kiosk/design/app_tokens.dart';

/// A scrollable region that SAYS it is scrollable.
///
/// Owner, 2026-11-23: *"on every view section that has some informations that
/// the user should scroll the screen to see, it should be clear indicating
/// it"*.
///
/// ⚠ **On a borne this is not a nicety.** A customer standing at a machine for
/// twenty seconds does not experiment: content below the fold is content that
/// does not exist, and the kiosk has already lost one order that way — the
/// counter screen's total sat 336 px off the bottom of the Samsung and nobody
/// thought to scroll (`counter_screen.dart`).
///
/// Two signals, because one of them is colour:
/// - a **fade** at whichever edge has more behind it, so the content visibly
///   runs on rather than stopping;
/// - a **scrollbar**, always visible while there is something to scroll,
///   which is the signal a customer already knows from every other screen.
///
/// Both disappear when everything fits — an affordance that is always there is
/// an affordance nobody reads.
class KioskScrollable extends StatefulWidget {
  const KioskScrollable({
    required this.child,
    required this.controller,
    this.axis = Axis.vertical,
    this.fadeExtent = 32,
    super.key,
  });

  /// The scrollable itself. It must use [controller] — this widget listens to
  /// it rather than guessing, so a list that grows or shrinks keeps the hint
  /// honest.
  final Widget child;
  final ScrollController controller;
  final Axis axis;

  /// How deep the fade runs. Enough to read as "more below", not so deep that
  /// it dims a price.
  final double fadeExtent;

  @override
  State<KioskScrollable> createState() => _KioskScrollableState();
}

class _KioskScrollableState extends State<KioskScrollable> {
  bool _atStart = true;
  bool _atEnd = true;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_sync);
    // The first frame: the controller has no positions until the child has
    // laid out, so the state is read after it has.
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
  }

  @override
  void dispose() {
    widget.controller.removeListener(_sync);
    super.dispose();
  }

  void _sync() {
    if (!mounted || !widget.controller.hasClients) {
      return;
    }
    final ScrollPosition p = widget.controller.position;
    // ⚠ A 1 dp tolerance. A list that fits exactly reports maxScrollExtent 0
    // and these are both true; without the tolerance a rounding error leaves
    // a permanent fade on a list with nothing under it.
    final bool atStart = p.pixels <= p.minScrollExtent + 1;
    final bool atEnd = p.pixels >= p.maxScrollExtent - 1;
    if (atStart != _atStart || atEnd != _atEnd) {
      setState(() {
        _atStart = atStart;
        _atEnd = atEnd;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool vertical = widget.axis == Axis.vertical;
    final Widget bars = Scrollbar(
      controller: widget.controller,
      // Visible whenever there is something to scroll — not only while a
      // finger is down, which is a hint you have to already be scrolling to
      // see.
      thumbVisibility: true,
      thickness: 6,
      radius: const Radius.circular(3),
      child: widget.child,
    );

    // Nothing to say: no fade, no mask, no extra compositing layer.
    if (_atStart && _atEnd) {
      return bars;
    }

    return ShaderMask(
      shaderCallback: (Rect rect) {
        final double extent =
            widget.fadeExtent / (vertical ? rect.height : rect.width);
        return LinearGradient(
          begin: vertical ? Alignment.topCenter : Alignment.centerLeft,
          end: vertical ? Alignment.bottomCenter : Alignment.centerRight,
          colors: <Color>[
            _atStart ? AppColors.surface : AppColors.surface.withAlpha(0),
            AppColors.surface,
            AppColors.surface,
            _atEnd ? AppColors.surface : AppColors.surface.withAlpha(0),
          ],
          stops: <double>[
            0,
            extent.clamp(0.0, 0.3),
            1 - extent.clamp(0.0, 0.3),
            1,
          ],
        ).createShader(rect);
      },
      blendMode: BlendMode.dstIn,
      child: bars,
    );
  }
}
