import 'package:flutter/material.dart';

import 'app_tokens.dart';

/// The TIMMA eats mark — the arch with the served cloche (owner's `tamm`
/// artwork, 2026-11-25, ECOSYSTEM §25.7). Replaces the old hand-traced hut.
///
/// One single-colour asset (white on transparent, trimmed to the artwork) and
/// a `srcIn` tint, so the colour still comes from a token: green on cream,
/// gold on green, cream on the delivery box.
class TimmaMark extends StatelessWidget {
  const TimmaMark({
    super.key,
    this.size = 64,
    this.color = AppColors.brandGreen,
    this.semanticLabel,
  });

  /// Height of the mark; the width follows [TimmaMarkAsset.aspect].
  final double size;
  final Color color;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final Widget mark = Image.asset(
      TimmaMarkAsset.path,
      height: size,
      width: size * TimmaMarkAsset.aspect,
      color: color,
      colorBlendMode: BlendMode.srcIn,
      fit: BoxFit.contain,
      // A missing asset degrades to empty space, never a broken-image box.
      errorBuilder: (BuildContext _, Object _, StackTrace? _) =>
          SizedBox(height: size, width: size * TimmaMarkAsset.aspect),
    );
    if (semanticLabel == null) {
      return ExcludeSemantics(child: mark);
    }
    return Semantics(label: semanticLabel, image: true, child: mark);
  }
}

/// The mark's asset and proportions.
abstract final class TimmaMarkAsset {
  static const String path = 'assets/branding/timma_mark.png';

  /// Width ÷ height of the trimmed artwork (393 × 577 px).
  static const double aspect = 393 / 577;
}
