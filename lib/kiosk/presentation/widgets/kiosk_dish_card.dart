import 'package:flutter/material.dart';

import 'package:timma_kiosk/design/app_tokens.dart';
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
    this.photoUrl,
    this.photoCache,
    this.onTap,
    super.key,
  });

  final String name;
  final String price;
  final bool soldOut;
  final String soldOutLabel;
  final String? photoUrl;

  /// Where the dish photographs live once the menu has been pinned.
  ///
  /// Null on a kiosk with no cache configured, which simply means every dish
  /// falls back to the brand panel — the menu still sells.
  final DishPhotoCache? photoCache;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final TextStyle style = theme.textTheme.titleMedium!;
    return Semantics(
      button: onTap != null,
      enabled: onTap != null,
      label: soldOut ? '$name, $soldOutLabel' : '$name, $price',
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
