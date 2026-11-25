import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:timma_kiosk/design/app_tokens.dart';
import 'package:timma_kiosk/l10n/app_localizations.dart';
import '../../catalog/dish_photo_cache.dart';
import '../../theme/kiosk_scale.dart';
import 'kiosk_dish_thumb.dart';

/// One dish, photograph first — **the customer app's card, at kiosk scale.**
///
/// The body reserves space for the same rows on every card. The remainder
/// belongs to the full-bleed photo, so titles and quick-add controls cannot
/// move the photo edge or price row out of alignment.
///
/// A null [onTap] is the sold-out state: the card renders greyed with its badge
/// and **cannot be tapped**, so a sold-out dish has no path to the composer at
/// all. Greying a card that still opens is the failure this signature exists to
/// prevent (plan §K4 rule 4).
class KioskDishCard extends StatelessWidget {
  const KioskDishCard({
    required this.name,
    required this.price,
    required this.soldOut,
    required this.soldOutLabel,
    this.prepMin = 10,
    this.prepMax = 15,
    this.spiceLevel = 0,
    this.origin,
    this.photoUrl,
    this.photoCache,
    this.onTap,
    this.onQuickAdd,
    this.quickAddKey,
    super.key,
  });

  final String name;
  final String price;
  final bool soldOut;
  final String soldOutLabel;

  /// R1 meta, straight off `SnapshotProduct`. Defaults mirror the COLUMN
  /// defaults (migration 48) so a bundle pinned before these fields existed
  /// reads "10–15 min" rather than "0–0 min".
  final int prepMin;
  final int prepMax;

  /// 0–3, from `spice_level`. ⚠ **Never from the `spicy` tag** — reading the
  /// tag is what left Koki and Kondré saying nothing about heat at all in the
  /// app (owner, 2026-08-26).
  final int spiceLevel;

  /// The region, already resolved to the screen's language, or null for a
  /// house dish. Riz TIMMA has none and the row omits it rather than printing
  /// a separator with nothing after it.
  final String? origin;

  final String? photoUrl;

  /// Where the dish photographs live once the menu has been pinned.
  ///
  /// Null on a kiosk with no cache configured, which simply means every dish
  /// falls back to the brand panel — the menu still sells.
  final DishPhotoCache? photoCache;

  final VoidCallback? onTap;

  /// Straight into the basket from the card, with no composer in between
  /// (owner, 2026-11-22). Null when the dish HAS choices to make — a required
  /// group skipped is a sale the kitchen cannot cook — and null when it is sold
  /// out, so the "+" is absent rather than present-and-refusing.
  final VoidCallback? onQuickAdd;

  /// Identifies the "+" so the add-to-cart bubble can leave from it.
  final GlobalKey? quickAddKey;

  static const double _titleGap = KioskScale.gap / 2;
  static const double _priceGap = KioskScale.gap;

  /// Allows two title lines and a price row with a quick-add button.
  /// Measure at the kiosk's current text scale so the grid can size its tiles.
  static double bodyHeight(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final TextStyle ambient = DefaultTextStyle.of(context).style;
    double lineHeight(TextStyle? style) {
      final TextPainter painter = TextPainter(
        text: TextSpan(text: 'Éru', style: ambient.merge(style)),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout();
      final double height = painter.height;
      painter.dispose();
      return height;
    }

    return 2 * lineHeight(text.titleMedium) +
        math.max(
          _KioskDishMetaRow._glyph,
          lineHeight(text.bodySmall?.copyWith(fontSize: KioskScale.labelSize)),
        ) +
        math.max(
          _QuickAddButton._size,
          lineHeight(
            text.bodyLarge?.copyWith(
              fontSize: KioskScale.cardPriceSize,
              fontWeight: FontWeight.w700,
            ),
          ),
        ) +
        2 * KioskScale.gap +
        _titleGap +
        _priceGap;
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    final ThemeData theme = Theme.of(context);
    final TextStyle style = theme.textTheme.titleMedium!;
    /*
     * ⚠ The meta belongs in THIS label, not in a `Semantics` of its own inside
     * the row.
     *
     * The card wraps its whole subtree in `ExcludeSemantics`, so a nested
     * semantics node — the shape the app's `_DishMetaRow` uses, where nothing
     * excludes it — is silently swallowed here and a screen reader hears only
     * the name and the price. Mirroring the app's structure without noticing
     * that difference would have shipped an accessible-looking row that says
     * nothing on the borne.
     *
     * And it names everything the DISH carries, not everything the row
     * happened to fit: width is a painting constraint, never a reason to
     * withhold a fact from someone who cannot see the card at all.
     */
    final String meta = <String>[
      l10n.kioskDishPrepWindowSemantics(prepMin, prepMax),
      if ((origin?.trim() ?? '').isNotEmpty) origin!.trim(),
      if (spiceLevel.clamp(0, 3) > 0)
        l10n.kioskDishSpiceLevel('${spiceLevel.clamp(0, 3)}'),
    ].join(', ');
    return Semantics(
      button: onTap != null,
      enabled: onTap != null,
      label: soldOut ? '$name, $soldOutLabel, $meta' : '$name, $price, $meta',
      child: ExcludeSemantics(
        child: Opacity(
          opacity: soldOut ? 0.5 : 1,
          child: Card(
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Expanded(
                    child: _Photo(
                      url: photoUrl,
                      cache: photoCache,
                      soldOut: soldOut,
                      soldOutLabel: soldOutLabel,
                    ),
                  ),
                  SizedBox(
                    height: bodyHeight(context),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        KioskScale.gapMd,
                        KioskScale.gap,
                        KioskScale.gap,
                        KioskScale.gap,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: style,
                          ),
                          const SizedBox(height: _titleGap),
                          _KioskDishMetaRow(
                            prepMin: prepMin,
                            prepMax: prepMax,
                            spiceLevel: spiceLevel,
                            origin: origin,
                          ),
                          const Spacer(),
                          const SizedBox(height: _priceGap),
                          ConstrainedBox(
                            constraints: const BoxConstraints(
                              minHeight: _QuickAddButton._size,
                            ),
                            child: Row(
                              children: <Widget>[
                                Expanded(
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      price,
                                      maxLines: 1,
                                      style: theme.textTheme.bodyLarge
                                          ?.copyWith(
                                            fontSize: KioskScale.cardPriceSize,
                                            fontWeight: FontWeight.w700,
                                            color: AppColors.primary,
                                          ),
                                    ),
                                  ),
                                ),
                                if (onQuickAdd != null)
                                  _QuickAddButton(
                                    key: quickAddKey,
                                    onPressed: onQuickAdd!,
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Photo extends StatelessWidget {
  const _Photo({
    required this.url,
    required this.cache,
    required this.soldOut,
    required this.soldOutLabel,
  });

  final String? url;
  final DishPhotoCache? cache;
  final bool soldOut;
  final String soldOutLabel;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    // The picture itself is `KioskDishThumb`, shared with the cart row and the
    // composer so a dish cannot look different depending on which screen shows
    // it. This class keeps only what is specific to the card: the sold-out
    // barrier drawn over the top.
    final Widget photo = KioskDishThumb(photoUrl: url, cache: cache);
    if (!soldOut) {
      return photo;
    }
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        photo,
        Align(
          alignment: Alignment.topLeft,
          child: Padding(
            padding: const EdgeInsets.all(KioskScale.gap),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: theme.colorScheme.error,
                borderRadius: BorderRadius.circular(KioskScale.gap / 2),
              ),
              child: Padding(
                // ⚠ Sized down 2026-11-22. At `labelLarge` with 16/8 padding
                // the badge covered roughly a third of the photograph — the
                // owner's "the sold-out badge is too big". A barrier has to be
                // legible, not loud; the grey-out and the dead tap target are
                // what actually stop the sale.
                padding: const EdgeInsets.symmetric(
                  horizontal: KioskScale.gap,
                  vertical: 3,
                ),
                child: Text(
                  soldOutLabel,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontSize: KioskScale.badgeSize,
                    color: theme.colorScheme.onError,
                    fontWeight: FontWeight.w700,
                    height: 1.1,
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

/// The line under a dish name on the borne: how long it takes, where it is
/// from, whether it is hot — **the app's `_DishMetaRow`, and its RULES.**
///
/// Copying the look would have been half the job. Three rules travel with it,
/// each of which the app paid for on a real handset:
///
/// * **It MEASURES and drops whole parts rather than eliding.** With an elided
///   origin the Samsung drew "Sud-Ouest" as "S…" and "Ouest" as "Ou…", and a
///   truncated region is not a shorter region, it is a DIFFERENT one — "Sud"
///   and "Sud-Ouest" are two places. Each part renders whole or not at all.
/// * **The drop order is the reverse of how much the customer decides on it**:
///   origin first, then the chilli; the prep window is a promise and never
///   goes. The row therefore cannot overflow at any width.
/// * **ONE chilli, whatever the level** (owner, 2026-08-26: *"no need for the
///   three or two fire to indicate it on dish card, just one is enough"*). The
///   card answers "is this spicy?"; HOW spicy belongs in the composer, where
///   the customer is deciding rather than scanning. And it is read from
///   `spice_level`, ⚠ never from the `spicy` tag.
///
/// ⚠ There is no vegetarian leaf here and that is not an omission in the
/// layout: `SnapshotProduct` carries no tags at all, so the borne genuinely
/// does not know. Adding them means widening the menu bundle, which breaks
/// `fn_canonical_json` byte-parity and needs a coordinated migration plus a
/// re-pin — queued, not smuggled in here. The drop order already has its slot.
///
/// Everything is CONDITIONAL and the row renders nothing when a dish carries
/// nothing: an empty separator, a zero-minute window or an outline chilli
/// meaning "not spicy" are all worse than the blank line they replace.
class _KioskDishMetaRow extends StatelessWidget {
  const _KioskDishMetaRow({
    required this.prepMin,
    required this.prepMax,
    required this.spiceLevel,
    required this.origin,
  });

  final int prepMin;
  final int prepMax;
  final int spiceLevel;
  final String? origin;

  /// Matched to the metadata role's own cap height rather than set to a round
  /// number, so the glyphs sit on the text baseline instead of floating above
  /// it. Larger than the app's 14 for the same reason every kiosk dimension
  /// is: the customer is standing, not holding the screen.
  static const double _glyph = 20;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    final ThemeData theme = Theme.of(context);
    final Color ink = theme.textTheme.bodySmall?.color ?? theme.hintColor;
    final TextStyle? style = theme.textTheme.bodySmall?.copyWith(
      color: ink,
      fontSize: KioskScale.labelSize,
    );

    final String region = origin?.trim() ?? '';
    final int spice = spiceLevel.clamp(0, 3);
    final String window = l10n.kioskDishPrepWindow(prepMin, prepMax);

    // ⚠ No `Semantics` node here, deliberately — see `KioskDishCard.build`.
    // The card excludes its whole subtree, so a node here would be swallowed;
    // the sentence this row stands for is spoken by the card's own label.
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double free = constraints.maxWidth;
        double used = _glyph + 3 + _measure(context, window, style);

        double cost(double content) => KioskScale.gap + content;

        final double chilliCost = cost(_glyph);
        final double originCost = cost(_measure(context, region, style));

        final bool showSpice = spice > 0 && used + chilliCost <= free;
        if (showSpice) used += chilliCost;

        final bool showOrigin = region.isNotEmpty && used + originCost <= free;

        return Row(
          children: <Widget>[
            Icon(Icons.schedule_rounded, size: _glyph, color: ink),
            const SizedBox(width: 3),
            // `Flexible` is the LAST line of defence, not the mechanism —
            // everything above has already been dropped by then, and a card
            // narrower than its own prep window is a layout bug elsewhere.
            // It exists so that bug shows as a shortened number rather than
            // a debug-only overflow stripe nobody sees in release.
            Flexible(
              child: Text(
                window,
                style: style,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (showOrigin) ...<Widget>[
              const SizedBox(width: KioskScale.gap),
              Text(region, style: style, maxLines: 1),
            ],
            if (showSpice) ...<Widget>[
              const SizedBox(width: KioskScale.gap),
              Icon(
                Icons.local_fire_department_rounded,
                size: _glyph,
                color: theme.colorScheme.error,
              ),
            ],
          ],
        );
      },
    );
  }

  /// The width one line of [text] would take, or 0 for nothing at all.
  static double _measure(BuildContext context, String text, TextStyle? style) {
    if (text.isEmpty) {
      return 0;
    }
    // ⚠ Merged with the ambient `DefaultTextStyle` exactly as `Text` does it.
    // Measuring the bare `style` gave a width 3.6 px short of what the widget
    // then painted, which is enough for the row to overflow by that much — a
    // measurement that does not reproduce the real layout is worse than no
    // measurement, because it fails silently and only at some widths.
    final TextStyle effective = DefaultTextStyle.of(context).style.merge(style);
    final TextPainter painter = TextPainter(
      text: TextSpan(text: text, style: effective),
      maxLines: 1,
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();

    return painter.width;
  }
}

/// The "+" on a dish card: one tap, straight into the basket.
///
/// Its own tap handler adds the item without opening the composer. The card
/// reserves this control's height even when the control is absent.
class _QuickAddButton extends StatelessWidget {
  const _QuickAddButton({required this.onPressed, super.key});

  static const double _size = 52;

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    return Semantics(
      button: true,
      label: l10n.kioskAdd,
      child: SizedBox(
        width: _size,
        height: _size,
        child: Material(
          color: AppColors.primary,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onPressed,
            child: const Icon(Icons.add, color: AppColors.onPrimary, size: 26),
          ),
        ),
      ),
    );
  }
}
