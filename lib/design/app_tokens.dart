import 'package:flutter/material.dart';

/// Design-token seeds. Source of truth will be
/// `timmaeat-webapp/design-tokens/tokens.json` (ECOSYSTEM §15.5) once the
/// owner confirms §19.8 — sync these values from there, never fork them.
/// Color values below are the exact measurements from the logo exports.
abstract final class AppColors {
  static const Color brandGreen = Color(0xFF205A39);
  static const Color brandGold = Color(0xFFEFCF9D);
  static const Color brandCream = Color(0xFFFEF8D8);
  static const Color brandCharcoal = Color(0xFF282828);

  // Roles (ECOSYSTEM §13.1: color roles, not raw hexes, in widget code).
  static const Color primary = brandGreen;
  static const Color onPrimary = brandGold;
  static const Color secondary = brandGold;
  static const Color onSecondary = brandCharcoal;
  static const Color surface = Colors.white;
  static const Color onSurface = brandCharcoal;
  static const Color surfaceTint = brandCream;
  static const Color error = Color(0xFFA32D2D);
  static const Color onError = Colors.white;

  // Neutral surfaces & lines (design pass 4, 2026-07-22). A warm-neutral family
  // so the cream/gold brand can act as an ACCENT (selected states, the summary
  // receipt) instead of the fill of every card — which read as flat
  // "yellow-on-white everywhere" (owner-reported). Depth now comes from a
  // three-step ladder: canvas < white card < muted field / soft-green selected.
  /// Page background: warm paper so white cards separate from it.
  static const Color canvas = Color(0xFFFAF8F2);

  /// Neutral field / unselected-tile fill (hairline-bordered).
  static const Color surfaceMuted = Color(0xFFF1EFE7);

  /// Hairline border / divider on cards and fields.
  static const Color outline = Color(0xFFE6E1D4);

  /// Faint green wash for a selected tile — ties selection to [primary].
  static const Color primarySoft = Color(0xFFE7F0E9);

  /// Unchecked checkbox/radio boundary (ECOSYSTEM §15.7).
  ///
  /// Deliberately NOT [outline]: that measures 1.31:1 against white, and WCAG
  /// 1.4.11 asks for 3:1 on the boundary of a UI component. This measures
  /// 3.99:1 on white, 3.75:1 on [canvas], 3.46:1 on [surfaceMuted].
  static const Color controlBorder = Color(0xFF847F74);

  /// Muted secondary/hint text. Warm neutral that clears WCAG 4.5:1 on BOTH
  /// white (6.5:1) and cream (6.1:1) — replaces the old `Colors.black45` hint
  /// (3.4:1, a contrast fail) and consolidates scattered `black54` labels
  /// (ECOSYSTEM §13.1 roles, §13.5 contrast). Never use raw black-opacity for text.
  static const Color textMuted = Color(0xFF5F5E5A);
}

/// 8pt spacing grid (CLAUDE.md §13.1).
abstract final class AppSpacing {
  static const double xs = 4;
  static const double s = 8;
  static const double m = 16;
  static const double l = 24;
  static const double xl = 32;
  static const double xxl = 48;
}

abstract final class AppRadii {
  static const double s = 8;
  static const double m = 12;
  static const double l = 16;

  /// Kit sheet top corners (design pass 2).
  static const double xl = 24;
}

/// Selection controls — checkbox and radio (ECOSYSTEM §15.7).
///
/// Mirrors the `control` block of `timmaeat-webapp/design-tokens/tokens.json`;
/// `DesignTokensTest` over there fails the build if these names stop matching.
///
/// **Shape carries the meaning and is never decorative**: a circle means pick
/// one, a rounded square means pick any number. That is why [radiusRadio] and
/// [radiusCheckbox] are two values and not one.
///
/// [size] is what the eye sees; [target] is what the finger hits. The 48dp
/// minimum belongs to the row around the control, never to the glyph — growing
/// the glyph to 48 would be the wrong fix (CLAUDE.md §13.3).
abstract final class AppControl {
  static const double size = 22;
  static const double borderWidth = 2;
  static const double radiusCheckbox = 6;

  /// A circle. The web writes this as `999px`; here any value ≥ [size] / 2 is
  /// the same circle, and Material draws the radio round regardless.
  static const double radiusRadio = 999;

  /// The radio's inner dot. Measured on a Samsung SM-G975F (1080×2280 @ 420dpi,
  /// scale 2.625) on 2026-07-31: Material's own dot came out **12.2dp inside a
  /// 21.7dp glyph** — 56% of the control, against the web's 36% — which read as
  /// a visibly fatter dot for the same choice. `AppTheme` passes
  /// `dotSize / 2 / radioScale` as `innerRadius` to undo that.
  static const double dotSize = 8;

  static const double gap = 12;
  static const double target = 48;
  static const double focusRingWidth = 3;
  static const double focusRingOffset = 2;
  static const double disabledOpacity = 0.45;

  /// Material hardcodes its glyph sizes — `Checkbox.width` is 18 and the
  /// radio's outer radius is 8 (a 16px circle) — and neither is reachable from
  /// `ThemeData`. `TimmaCheckbox`/`TimmaRadio` scale by these factors so [size]
  /// is honoured rather than aspirational, and divide the stroke by the same
  /// number so [borderWidth] survives the scale.
  static const double materialCheckboxSize = 18;
  static const double materialRadioSize = 16;

  static const double checkboxScale = size / materialCheckboxSize;
  static const double radioScale = size / materialRadioSize;
}

abstract final class AppTypeScale {
  static const double display = 32;
  static const double headline = 24;
  static const double title = 20;
  static const double body = 16;
  static const double label = 14;
  static const double caption = 12;
}

/// Font families (CLAUDE.md §3: no magic strings).
abstract final class AppFonts {
  /// The handwriting face used for the home greeting.
  ///
  /// Declared here even before the file is bundled: an unregistered family
  /// falls back to the default face, so the greeting still renders and still
  /// animates — dropping the .ttf into `assets/fonts/` and listing it in
  /// `pubspec.yaml` is the only step left.
  static const String script = 'TimmaScript';

  /// The display face used for screen and section titles.
  ///
  /// Registered under a NEUTRAL family name for the same reason as [script]:
  /// the code names a ROLE, so swapping the face is one line in `pubspec.yaml`
  /// and nothing in Dart.
  ///
  /// Deliberately not applied to body or label text. It is a marker face — it
  /// carries a title and becomes hard work over a paragraph, and §13.5 wants
  /// body copy legible at 4.5:1 and dynamic-font sizes.
  static const String display = 'TimmaDisplay';

  /// The body and UI face — everything that is not a title.
  ///
  /// Chosen to pair with [display] rather than merely coexist: both have
  /// rounded terminals, so the two read as one family instead of two
  /// decisions. A geometric alternative was rejected because this app is full
  /// of dish names, prices and statuses, where a humanist face stays legible
  /// and a geometric one turns into rows of circles.
  static const String body = 'TimmaBody';
}
