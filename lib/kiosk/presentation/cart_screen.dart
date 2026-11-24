import 'package:flutter/material.dart';

import 'package:timma_kiosk/design/money_formatter.dart';
import 'package:timma_kiosk/l10n/app_localizations.dart';
import '../catalog/dish_photo_cache.dart';
import 'widgets/kiosk_dish_thumb.dart';
import '../state/kiosk_cart.dart';
import '../theme/kiosk_scale.dart';

/// What the customer built, before they commit to it.
///
/// The total here is read, never sent: [KioskCartState.subtotal] uses the same
/// [Money] helpers the engine prices with, and `confirm()` passes ids and
/// quantities only (§23.3).
class KioskCartScreen extends StatelessWidget {
  const KioskCartScreen({
    required this.cart,
    required this.cache,
    required this.onQuantity,
    required this.onRemove,
    required this.onConfirm,
    required this.onKeepBrowsing,
    this.error,
    super.key,
  });

  final KioskCartState cart;

  /// Where the dish photographs live, so the basket shows the same pictures the
  /// menu did — from disk, with no network.
  final DishPhotoCache? cache;
  final void Function(String lineId, int quantity) onQuantity;
  final void Function(String lineId) onRemove;
  final VoidCallback onConfirm;
  final VoidCallback onKeepBrowsing;

  /// A refusal from the engine — a dish that sold out while the customer was
  /// deciding. Shown in words they can act on, never a code.
  final String? error;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    final ThemeData theme = Theme.of(context);
    final bool french = Localizations.localeOf(context).languageCode == 'fr';

    return Padding(
      padding: const EdgeInsets.all(KioskScale.gapXl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(l10n.kioskCartTitle, style: theme.textTheme.headlineLarge),
          if (error != null) ...<Widget>[
            const SizedBox(height: KioskScale.gapMd),
            _ErrorBanner(message: l10n.kioskUnavailableNow),
          ],
          const SizedBox(height: KioskScale.gapLg),
          Expanded(
            child: cart.isEmpty
                ? Center(
                    child: Text(
                      l10n.kioskCartEmpty,
                      style: theme.textTheme.titleLarge,
                    ),
                  )
                : ListView.separated(
                    itemCount: cart.items.length,
                    separatorBuilder: (BuildContext _, int _) =>
                        const SizedBox(height: KioskScale.gapMd),
                    itemBuilder: (BuildContext context, int index) {
                      final KioskCartItem item = cart.items[index];
                      return _CartRow(
                        cache: cache,
                        item: item,
                        french: french,
                        removeLabel: l10n.kioskRemove,
                        onQuantity: (int q) => onQuantity(item.lineId, q),
                        onRemove: () => onRemove(item.lineId),
                      );
                    },
                  ),
          ),
          const Divider(height: KioskScale.gapXl),
          // ⚠ **The footer is laid out for the room it has.** Measured
          // 2026-11-24: side by side, the total and the two kiosk-sized
          // buttons ran 40 px off a 868 dp screen at text scale 1.3 and
          // 30 px off the bottom of a 640x400 one. The control that goes
          // first is *Commander* — a basket a customer cannot confirm while
          // standing there with their money out.
          //
          // Wide: total left, actions right. Narrow: the total on its own
          // line and the two actions sharing the width, each able to shrink
          // its own label rather than push its neighbour off.
          LayoutBuilder(
            builder: (BuildContext context, BoxConstraints box) {
              // Scaled by the viewer's text size — see the note on the row.
              final bool narrow =
                  box.maxWidth <
                  900 * MediaQuery.textScalerOf(context).scale(1);
              final Widget total = Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(l10n.kioskCartTotal, style: theme.textTheme.labelLarge),
                  Text(
                    MoneyFormatter.formatXaf(cart.subtotal),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        (narrow
                                ? theme.textTheme.headlineSmall
                                : theme.textTheme.headlineLarge)
                            ?.copyWith(color: theme.colorScheme.primary),
                  ),
                ],
              );
              final Widget keep = OutlinedButton(
                onPressed: onKeepBrowsing,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(l10n.kioskCartKeepBrowsing, maxLines: 1),
                ),
              );
              final Widget confirm = FilledButton(
                onPressed: cart.isEmpty ? null : onConfirm,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(l10n.kioskCartConfirm, maxLines: 1),
                ),
              );

              if (!narrow) {
                return Row(
                  children: <Widget>[
                    Expanded(child: total),
                    const SizedBox(width: KioskScale.gapMd),
                    keep,
                    const SizedBox(width: KioskScale.gapMd),
                    confirm,
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  total,
                  const SizedBox(height: KioskScale.gap),
                  Row(
                    children: <Widget>[
                      Expanded(child: keep),
                      const SizedBox(width: KioskScale.gapMd),
                      // The primary action gets the larger share: it is the
                      // one a customer is reaching for.
                      Expanded(flex: 2, child: confirm),
                    ],
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(KioskScale.gapMd),
      decoration: BoxDecoration(
        color: theme.colorScheme.error.withValues(alpha: 0.1),
        border: Border.all(color: theme.colorScheme.error, width: 2),
        borderRadius: BorderRadius.circular(KioskScale.radius),
      ),
      child: Text(
        message,
        style: theme.textTheme.bodyLarge?.copyWith(
          color: theme.colorScheme.error,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _CartRow extends StatelessWidget {
  const _CartRow({
    required this.item,
    required this.cache,
    required this.french,
    required this.removeLabel,
    required this.onQuantity,
    required this.onRemove,
  });

  final KioskCartItem item;
  final bool french;
  final String removeLabel;
  final void Function(int quantity) onQuantity;
  final DishPhotoCache? cache;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String name = french ? item.product.nameFr : item.product.nameEn;
    final List<String> extras = <String>[
      if (item.variant != null)
        french ? item.variant!.nameFr : item.variant!.nameEn,
      for (final o in item.options) french ? o.nameFr : o.nameEn,
    ];

    // ⚠ **Two rows below 720 dp.** Measured 2026-11-24: at 640 dp the
    // thumbnail, the name, two 72 dp quantity keys, the line total and the
    // remove key ran 168 px past the card — the same mistake the side basket
    // panel made an hour earlier. Six fixed things do not fit a narrow row,
    // and shaving the controls is not the answer: the dish and its price get
    // the width, the controls get their own line.
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(KioskScale.gapMd),
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints box) {
            // ⚠ Scaled by the viewer's own text size. At text scale 1.3 the
            // same 868 dp screen holds a third less text, and a threshold in
            // raw dp let the wide layout run 40 px off the edge there — the
            // same blind spot that kept a kitchen heading truncated through
            // three attempts.
            final bool stacked =
                box.maxWidth < 720 * MediaQuery.textScalerOf(context).scale(1);

            final Widget dish = Row(
              children: <Widget>[
                // The dish the customer actually chose, not just its name.
                // They picked a photograph off the menu; seeing it again in
                // the basket is how they check it at a glance.
                KioskDishThumb(
                  photoUrl: item.product.photoUrl,
                  cache: cache,
                  size: KioskScale.minTarget,
                  radius: KioskScale.gap,
                  iconSize: 28,
                ),
                const SizedBox(width: KioskScale.gapMd),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(name, style: theme.textTheme.titleLarge),
                      if (extras.isNotEmpty) ...<Widget>[
                        const SizedBox(height: KioskScale.gap),
                        Text(
                          extras.join(' · '),
                          style: theme.textTheme.labelLarge,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            );

            final Widget controls = Row(
              mainAxisSize: stacked ? MainAxisSize.max : MainAxisSize.min,
              children: <Widget>[
                if (stacked)
                  Expanded(
                    child: Text(
                      MoneyFormatter.formatXaf(item.lineTotal),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                IconButton.outlined(
                  iconSize: 32,
                  onPressed: () => onQuantity(item.quantity - 1),
                  icon: const Icon(Icons.remove),
                  constraints: const BoxConstraints(
                    minWidth: KioskScale.minTarget,
                    minHeight: KioskScale.minTarget,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: KioskScale.gapMd,
                  ),
                  child: Text(
                    '${item.quantity}',
                    style: theme.textTheme.titleLarge,
                  ),
                ),
                IconButton.outlined(
                  iconSize: 32,
                  onPressed: () => onQuantity(item.quantity + 1),
                  icon: const Icon(Icons.add),
                  constraints: const BoxConstraints(
                    minWidth: KioskScale.minTarget,
                    minHeight: KioskScale.minTarget,
                  ),
                ),
                if (!stacked) ...<Widget>[
                  const SizedBox(width: KioskScale.gapLg),
                  ConstrainedBox(
                    constraints: const BoxConstraints(minWidth: 160),
                    child: Text(
                      MoneyFormatter.formatXaf(item.lineTotal),
                      textAlign: TextAlign.right,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                ],
                IconButton(
                  iconSize: 32,
                  onPressed: onRemove,
                  tooltip: removeLabel,
                  icon: const Icon(Icons.close),
                  constraints: const BoxConstraints(
                    minWidth: KioskScale.minTarget,
                    minHeight: KioskScale.minTarget,
                  ),
                ),
              ],
            );

            if (!stacked) {
              return Row(
                children: <Widget>[
                  Expanded(child: dish),
                  controls,
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                dish,
                const SizedBox(height: KioskScale.gap),
                controls,
              ],
            );
          },
        ),
      ),
    );
  }
}
