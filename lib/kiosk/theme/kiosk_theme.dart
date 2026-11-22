import 'package:flutter/material.dart';

import 'package:timma_kiosk/design/app_tokens.dart';
import 'kiosk_scale.dart';

/// The kiosk's Material theme, **derived from [AppColors] and never editing
/// it**.
///
/// One brand, three surfaces (ECOSYSTEM §15.5): the kiosk is allowed its own
/// scale and its own page colour role, and is not allowed to disagree with the
/// brand about what green is. Every colour here comes from the shared tokens;
/// only sizes are the kiosk's own, and those are in [KioskScale].
abstract final class KioskTheme {
  static ThemeData build() {
    const ColorScheme scheme = ColorScheme.light(
      primary: AppColors.primary,
      onPrimary: AppColors.onPrimary,
      secondary: AppColors.secondary,
      onSecondary: AppColors.onSecondary,
      onSurface: AppColors.onSurface,
      error: AppColors.error,
      outline: AppColors.outline,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.canvas,
      textTheme: _textTheme,
      splashFactory: InkRipple.splashFactory,
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(
            KioskScale.minTarget * 3,
            KioskScale.minTarget,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: KioskScale.gapXl,
            vertical: KioskScale.gapMd,
          ),
          textStyle: const TextStyle(
            fontSize: KioskScale.titleSize,
            fontWeight: FontWeight.w600,
          ),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(KioskScale.radius)),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(
            KioskScale.minTarget * 2,
            KioskScale.minTarget,
          ),
          side: const BorderSide(color: AppColors.controlBorder, width: 2),
          textStyle: const TextStyle(
            fontSize: KioskScale.bodySize,
            fontWeight: FontWeight.w600,
          ),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(KioskScale.radius)),
          ),
        ),
      ),
      cardTheme: const CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(KioskScale.radiusLg)),
          side: BorderSide(color: AppColors.outline),
        ),
      ),
    );
  }

  static const TextTheme _textTheme = TextTheme(
    displayLarge: TextStyle(
      fontSize: KioskScale.displaySize,
      fontWeight: FontWeight.w700,
      color: AppColors.onSurface,
      height: 1.1,
    ),
    headlineLarge: TextStyle(
      fontSize: KioskScale.headlineSize,
      fontWeight: FontWeight.w700,
      color: AppColors.onSurface,
      height: 1.15,
    ),
    titleLarge: TextStyle(
      fontSize: KioskScale.titleSize,
      fontWeight: FontWeight.w600,
      color: AppColors.onSurface,
    ),
    // **The card-title role**, mirroring the customer app, where `titleMedium`
    // became exactly that on 2026-08-16 so no call site decides a dish name's
    // weight or line height for itself.
    //
    // Sized down from [KioskScale.titleSize] deliberately. At 28 pt a dish name
    // in a ~224 dp card truncated after about seven characters — the Samsung
    // showed "Poulet …" and "Ndolé a…", which on the one screen whose job is
    // naming food is worse than smaller type. 22 pt over two lines carries
    // "Ndolé aux crevettes" whole and is still readable at standing distance.
    titleMedium: TextStyle(
      // ⚠ 22 → 17 on 2026-11-22. 22 was sized for a 320 dp tile; the grid now
      // lays out ~240 dp cards on a wide borne and "Pepper soup de bœuf TIMMA"
      // wrapped to three lines and ellipsized. This is the ROLE, so the card
      // and anything else that means "card title" move together — a call site
      // overriding the size is what the layout test forbids, and rightly.
      fontSize: KioskScale.cardTitleSize,
      fontWeight: FontWeight.w600,
      color: AppColors.onSurface,
      height: 1.2,
    ),
    bodyLarge: TextStyle(
      fontSize: KioskScale.bodySize,
      color: AppColors.onSurface,
      height: 1.35,
    ),
    labelLarge: TextStyle(
      fontSize: KioskScale.labelSize,
      color: AppColors.textMuted,
      fontWeight: FontWeight.w500,
    ),
  );
}
