import 'package:flutter/material.dart';

import 'package:timma_kiosk/design/app_tokens.dart';
import 'package:timma_kiosk/l10n/app_localizations.dart';
import '../../catalog/dish_photo_cache.dart';
import '../../theme/kiosk_scale.dart';
import 'kiosk_dish_thumb.dart';

/// One dish, photograph first — **the customer app's card, at kiosk scale.**
///
/// The grammar is copied deliberately from
/// `lib/features/catalog/presentation/widgets/product_card.dart` in the app, so
/// a dish looks like the same product whether the customer met it on their phone
/// or on the kiosk (owner, 2026-08-17). Three rules travel with it, and each one
/// is there because the app learned it the hard way:
///
/// * **The photo is exactly half the card**, as two equal `Expanded`s rather
///   than a number anyone picked. A fixed photo height drifted the app's two
///   copies apart and overflowed one text variant by 7 px.
/// * **The photo is full bleed and carries no radius of its own.** The `Card`'s
///   `Clip.antiAlias` rounds its top corners to exactly the card's, which a
///   separately rounded, inset image can only approximate.
/// * **Title, then a spacer, then the price row.** The price sits on the
///   card's bottom edge on every card, so a row of dishes has one price line
///   rather than a ragged one.
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
                  // Half the card, by construction. See the class doc.
                  Expanded(
                    child: _Photo(
                      url: photoUrl,
                      cache: photoCache,
                      soldOut: soldOut,
                      soldOutLabel: soldOutLabel,
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: KioskScale.gapMd,
                        vertical: KioskScale.gap,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          // ⚠ `Expanded` + `Align`, NOT `Flexible` above a
                          // `Spacer`. Both of those default to flex 1, so the
                          // spacer took half the room left for the name and
                          // every dish truncated to a single line on the
                          // Samsung — "Poisson br…" where two whole lines
                          // fitted. The name owns the leftover space and sits
                          // at the top of it; the price keeps the bottom edge,
                          // which is what lines prices up across a row.
                          Expanded(
                            child: Align(
                              alignment: Alignment.topLeft,
                              child: _DishName(name: name, style: style),
                            ),
                          ),
                          _KioskDishMetaRow(
                            prepMin: prepMin,
                            prepMax: prepMax,
                            spiceLevel: spiceLevel,
                            origin: origin,
                          ),
                          const SizedBox(height: KioskScale.gap),
                          Text(
                            price,
                            maxLines: 1,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary,
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
                borderRadius: BorderRadius.circular(KioskScale.gap),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: KioskScale.gapMd,
                  vertical: KioskScale.gap,
                ),
                child: Text(
                  soldOutLabel,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.onError,
                    fontWeight: FontWeight.w700,
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

/// The dish's name, drawing only lines that fit whole.
///
/// **The line count is computed, not declared.** `maxLines: 2` with an ellipsis
/// bounds how many lines are laid out; it does not stop a line being painted in
/// a box too short to show it. The Samsung rendered "Poisson braisé" with its
/// second line sliced through the middle — which reads as a rendering fault
/// rather than a long name. So the text is told how many lines it may use for
/// the height it actually got, and ellipsizes on the last one that fits.
class _DishName extends StatelessWidget {
  const _DishName({required this.name, required this.style});

  final String name;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double lineHeight =
            (style.fontSize ?? 22) * (style.height ?? 1.2);
        final int fits = (constraints.maxHeight / lineHeight).floor();
        return Text(
          name,
          maxLines: fits.clamp(1, 2),
          overflow: TextOverflow.ellipsis,
          style: style,
        );
      },
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
