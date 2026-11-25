import 'package:flutter/material.dart';

import 'package:timma_kiosk/design/app_tokens.dart';
import '../../theme/kiosk_scale.dart';
import 'category_icons.dart';

/// One category pill — **the customer app's control, at kiosk scale.**
///
/// Copied in behaviour from `features/catalog/presentation/widgets/
/// category_pill.dart` in the app, including the rule that earned its own
/// warning there:
///
/// ⚠ **The label's weight does not change with selection — the fill does.** A
/// heavier label on the selected pill would make it wider and reflow the whole
/// strip on every tap, under the finger that just tapped it. On a kiosk, where
/// the next tap is often immediate, that reflow is a mis-tap.
class KioskCategoryPill extends StatelessWidget {
  const KioskCategoryPill({
    required this.label,
    required this.selected,
    required this.onTap,
    this.count,
    this.compact = false,
    super.key,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  /// How many dishes are behind this filter, or null to say nothing.
  ///
  /// The reference tills all print it ("50 items", "20 Items"), and on a kiosk
  /// it earns its space: it tells a customer whether a tap is worth making
  /// before they make it.
  final int? count;

  /// Tighten the pill for a short screen: a smaller icon, nothing else.
  ///
  /// ⚠ It used to switch between two different layouts — a stacked tile and a
  /// row — which meant the count was simply absent on a short screen and two
  /// arrangements had to be kept working. The pill is one layout at every
  /// size; this only trims it.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color foreground = selected
        ? theme.colorScheme.onPrimary
        : AppColors.primary;

    return Semantics(
      button: true,
      selected: selected,
      label: count == null ? label : '$label, $count',
      child: ExcludeSemantics(
        child: Material(
          color: selected ? AppColors.primary : AppColors.surface,
          shape: RoundedRectangleBorder(
            // Fully round: a pill, not a rounded card.
            borderRadius: BorderRadius.circular(999),
            side: BorderSide(
              color: selected ? AppColors.primary : AppColors.controlBorder,
              width: selected ? 2 : 1,
            ),
          ),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(999),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: KioskScale.gapMd,
                // ⚠ The HEIGHT now comes from the strip
                // ([KioskScale.categoryTileHeight]), so this padding only has
                // to leave the icon, the name and the count room inside it.
                // At `gapMd` the three of them ran 7.6 px past the tile.
                vertical: KioskScale.gap,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  // ⚠ **A pill, not a tile.** Owner, 2026-11-23: *"the
                  // categories card should rather be in badge pill form. icon
                  // on left, text in middle and number on right (with light
                  // difference in the background of the number)"*.
                  //
                  // The stacked tile was 112 dp tall and took that height off
                  // the dish grid on every screen; a pill reads left to right
                  // in one line and gives it back. The same layout now serves
                  // the short-screen case, so there is one thing to get right
                  // instead of two.
                  categoryIcon(
                    label,
                    size: compact ? 20 : 24,
                    color: foreground,
                  ),
                  const SizedBox(width: KioskScale.gap),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: foreground,
                    ),
                  ),
                  if (count != null) ...<Widget>[
                    const SizedBox(width: KioskScale.gap),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        // The "light difference" the owner asked for: the
                        // count sits on its own ground so it reads as a
                        // tally rather than as part of the name. Derived from
                        // the pill's own colours, so it works selected and
                        // unselected without a second rule.
                        color: selected
                            ? theme.colorScheme.onPrimary.withValues(
                                alpha: 0.18,
                              )
                            : AppColors.surfaceMuted,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: KioskScale.gap,
                          vertical: 2,
                        ),
                        child: Text(
                          '$count',
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: foreground,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
