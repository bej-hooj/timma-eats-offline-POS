import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'app_tokens.dart';

/// The TIMMA logo mark — the arched window with the sun behind a thatched
/// hut — drawn as vector geometry, traced from the owner's logo export
/// (`~/Desktop/Timma-eats/logos/logo.png`).
///
/// **Why it is redrawn rather than shipped as a PNG.** The only artwork that
/// exists is a 500×500 raster whose mark occupies 186×214 px. Anything larger
/// than that on screen is an upscale, and the mark is thin line art — the
/// first thing to go soft. Drawn as paths it is exact at any size and on any
/// density, costs no image decode on the cold-start path (§12), and takes the
/// brand colour from a token instead of being baked in.
///
/// Geometry lives in a unit square and is scaled to the box it is given, so
/// the same code serves a 64 dp lockup and a 28 dp emblem on a delivery box.
class TimmaMark extends StatelessWidget {
  const TimmaMark({
    super.key,
    this.size = 64,
    this.color = AppColors.brandGreen,
    this.semanticLabel,
  });

  final double size;
  final Color color;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final Widget mark = CustomPaint(
      size: Size(size * TimmaMarkGeometry.aspect, size),
      painter: _TimmaMarkPainter(color: color),
    );
    if (semanticLabel == null) {
      return ExcludeSemantics(child: mark);
    }
    return Semantics(label: semanticLabel, image: true, child: mark);
  }
}

/// The mark's geometry, exposed so a `CustomPainter` that is already painting
/// (the splash scene) can stamp it without building a widget.
abstract final class TimmaMarkGeometry {
  /// Width ÷ height of the traced artwork (186 × 214).
  static const double aspect = 186 / 214;

  /// Strokes are drawn at this fraction of the mark's height. Measured off
  /// the export rather than guessed: its lines are ~3 px on a 214 px mark.
  /// The first pass used 0.026 and the mark came out looking like a rubber
  /// stamp — the original's elegance is mostly in how thin it is.
  static const double strokeFraction = 0.015;

  /// Paints the mark into [rect] in [color].
  ///
  /// All coordinates below are unit-square fractions read off the export, so
  /// they can be compared against the artwork directly.
  static void paintInto(
    Canvas canvas,
    Rect rect,
    Color color, {
    double? width,
  }) {
    final double w = rect.width;
    final double h = rect.height;
    final Paint line = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = width ?? (h * strokeFraction)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    Offset p(double x, double y) => Offset(rect.left + x * w, rect.top + y * h);

    // ---- the arched window: verticals, semicircular head, sill ----
    const double archL = 0.055;
    const double archR = 0.945;
    const double spring = 0.44;
    const double sill = 0.965;
    final double radius = (archR - archL) / 2 * w;

    canvas.drawPath(
      Path()
        ..moveTo(p(archL, sill).dx, p(archL, sill).dy)
        ..lineTo(p(archL, spring).dx, p(archL, spring).dy)
        ..arcToPoint(
          p(archR, spring),
          radius: Radius.elliptical(radius, spring * h),
        )
        ..lineTo(p(archR, sill).dx, p(archR, sill).dy)
        ..close(),
      line,
    );
    // The impost line the sun's rays run out to.
    canvas.drawLine(p(archL, spring), p(archR, spring), line);

    // ---- the sun: rays from the roof's peak out to the window ----
    final Offset peak = p(0.5, 0.395);
    for (final Offset end in [
      p(0.5, 0.035),
      p(0.255, 0.105),
      p(0.745, 0.105),
      p(0.085, 0.295),
      p(0.915, 0.295),
      p(archL, spring),
      p(archR, spring),
      p(0.10, 0.925),
      p(0.90, 0.925),
    ]) {
      canvas.drawLine(peak, end, line);
    }

    // ---- the hut: thatched roof with a scalloped eave ----
    final Path roof = Path()
      ..moveTo(p(0.030, 0.720).dx, p(0.030, 0.720).dy)
      ..cubicTo(
        p(0.175, 0.665).dx,
        p(0.175, 0.665).dy,
        p(0.340, 0.470).dx,
        p(0.340, 0.470).dy,
        peak.dx,
        peak.dy,
      )
      ..cubicTo(
        p(0.660, 0.470).dx,
        p(0.660, 0.470).dy,
        p(0.825, 0.665).dx,
        p(0.825, 0.665).dy,
        p(0.970, 0.720).dx,
        p(0.970, 0.720).dy,
      );
    canvas.drawPath(roof, line);

    // The eave: four shallow scallops, the detail that says "thatch".
    final Path eave = Path()..moveTo(p(0.120, 0.660).dx, p(0.120, 0.660).dy);
    const List<double> stops = [0.120, 0.310, 0.500, 0.690, 0.880];
    for (int i = 0; i < stops.length - 1; i++) {
      final double x0 = stops[i];
      final double x1 = stops[i + 1];
      eave.quadraticBezierTo(
        p((x0 + x1) / 2, 0.715).dx,
        p((x0 + x1) / 2, 0.715).dy,
        p(x1, 0.660).dx,
        p(x1, 0.660).dy,
      );
    }
    canvas.drawPath(eave, line);

    // Thatch lines fanning down from the peak.
    for (final Offset end in [
      p(0.335, 0.610),
      p(0.415, 0.635),
      p(0.500, 0.645),
      p(0.585, 0.635),
      p(0.665, 0.610),
    ]) {
      canvas.drawLine(p(0.5, 0.430), end, line);
    }

    // ---- the walls, their posts, and the doorway ----
    canvas.drawLine(p(0.175, 0.715), p(0.175, sill), line);
    canvas.drawLine(p(0.825, 0.715), p(0.825, sill), line);
    canvas.drawLine(p(0.175, sill), p(0.825, sill), line);
    for (final double x in const [0.250, 0.315, 0.685, 0.750]) {
      canvas.drawLine(p(x, 0.800), p(x, sill), line);
    }
    canvas.drawPath(
      Path()
        ..moveTo(p(0.410, sill).dx, p(0.410, sill).dy)
        ..lineTo(p(0.410, 0.830).dx, p(0.410, 0.830).dy)
        ..arcToPoint(
          p(0.590, 0.830),
          radius: Radius.elliptical(0.09 * w, 0.075 * h),
        )
        ..lineTo(p(0.590, sill).dx, p(0.590, sill).dy),
      line,
    );
  }

  /// A deliberately simplified stamp for small sizes.
  ///
  /// Below roughly 40 dp the traced mark's nine rays and five thatch lines
  /// collapse into a smudge — more ink than the pixels can carry. This keeps
  /// the silhouette that identifies the brand (arch, sun, hut) and drops the
  /// detail that cannot survive.
  static void paintCompact(Canvas canvas, Rect rect, Color color) {
    final double w = rect.width;
    final double h = rect.height;
    final Paint line = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = h * 0.055
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    Offset p(double x, double y) => Offset(rect.left + x * w, rect.top + y * h);

    canvas.drawPath(
      Path()
        ..moveTo(p(0.08, 0.95).dx, p(0.08, 0.95).dy)
        ..lineTo(p(0.08, 0.45).dx, p(0.08, 0.45).dy)
        ..arcToPoint(
          p(0.92, 0.45),
          radius: Radius.elliptical(0.42 * w, 0.45 * h),
        )
        ..lineTo(p(0.92, 0.95).dx, p(0.92, 0.95).dy)
        ..close(),
      line,
    );
    final Offset peak = p(0.5, 0.40);
    for (final double a in const [
      -math.pi / 2,
      -math.pi / 2 - 0.8,
      -math.pi / 2 + 0.8,
    ]) {
      canvas.drawLine(
        peak,
        peak + Offset(math.cos(a), math.sin(a)) * (0.30 * h),
        line,
      );
    }
    canvas.drawPath(
      Path()
        ..moveTo(p(0.16, 0.72).dx, p(0.16, 0.72).dy)
        ..lineTo(peak.dx, peak.dy)
        ..lineTo(p(0.84, 0.72).dx, p(0.84, 0.72).dy),
      line,
    );
    canvas.drawLine(p(0.24, 0.72), p(0.24, 0.95), line);
    canvas.drawLine(p(0.76, 0.72), p(0.76, 0.95), line);
    canvas.drawLine(p(0.24, 0.95), p(0.76, 0.95), line);
  }
}

class _TimmaMarkPainter extends CustomPainter {
  const _TimmaMarkPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    TimmaMarkGeometry.paintInto(canvas, Offset.zero & size, color);
  }

  @override
  bool shouldRepaint(_TimmaMarkPainter oldDelegate) =>
      oldDelegate.color != color;
}
