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

  /// Lay the icon BESIDE the label instead of above it, and drop the count.
  ///
  /// ⚠ Not a style choice. The stacked tile is 112 dp tall, and the Samsung
  /// the cuisine runs on is **411 dp tall in landscape** — there the strip ate
  /// the dish grid and the page overflowed. A kiosk screen is whatever the
  /// restaurant mounted, so the strip has to work on both.
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
            borderRadius: BorderRadius.circular(KioskScale.radius),
            side: BorderSide(
              color: selected ? AppColors.primary : AppColors.controlBorder,
              width: selected ? 2 : 1,
            ),
          ),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(KioskScale.radius),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: KioskScale.gapMd,
                // ⚠ The HEIGHT now comes from the strip
                // ([KioskScale.categoryTileHeight]), so this padding only has
                // to leave the icon, the name and the count room inside it.
                // At `gapMd` the three of them ran 7.6 px past the tile.
                vertical: KioskScale.gap,
              ),
              child: compact
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Icon(categoryIcon(label), size: 22, color: foreground),
                        const SizedBox(width: KioskScale.gap),
                        Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: foreground,
                          ),
                        ),
                      ],
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Icon(categoryIcon(label), size: 30, color: foreground),
                        const SizedBox(height: KioskScale.gap / 2),
                        Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: foreground,
                          ),
                        ),
                        if (count != null)
                          Text(
                            '$count',
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: foreground.withValues(alpha: 0.7),
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
