import 'package:flutter/material.dart';

import 'package:timma_kiosk/design/app_tokens.dart';
import '../../theme/kiosk_scale.dart';

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
    super.key,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color foreground = selected
        ? theme.colorScheme.onPrimary
        : AppColors.primary;

    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: ExcludeSemantics(
        child: Material(
          color: selected ? AppColors.primary : AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
            side: BorderSide(
              color: selected ? AppColors.primary : AppColors.controlBorder,
            ),
          ),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(999),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: KioskScale.gapLg,
                // Tall enough to clear the 48 dp touch minimum with room to
                // spare — a standing customer taps less precisely than a seated
                // one holding a phone.
                vertical: KioskScale.gapMd,
              ),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(color: foreground),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
