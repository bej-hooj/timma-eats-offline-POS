import 'package:flutter/material.dart';

import 'package:timma_kiosk/design/money_formatter.dart';
import 'package:timma_kiosk/l10n/app_localizations.dart';
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
    required this.onQuantity,
    required this.onRemove,
    required this.onConfirm,
    required this.onKeepBrowsing,
    this.error,
    super.key,
  });

  final KioskCartState cart;
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
          Row(
            children: <Widget>[
              // Stacked, and flexible: at the real kiosk width (1200 logical,
              // landscape) a side-by-side label + total + two kiosk-sized
              // buttons overflowed by 83 px, which on the tablet is a customer
              // who cannot see the *Commander* button at all.
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      l10n.kioskCartTotal,
                      style: theme.textTheme.labelLarge,
                    ),
                    Text(
                      MoneyFormatter.formatXaf(cart.subtotal),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.headlineLarge?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: KioskScale.gapMd),
              OutlinedButton(
                onPressed: onKeepBrowsing,
                child: Text(l10n.kioskCartKeepBrowsing),
              ),
              const SizedBox(width: KioskScale.gapMd),
              FilledButton(
                onPressed: cart.isEmpty ? null : onConfirm,
                child: Text(l10n.kioskCartConfirm),
              ),
            ],
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
    required this.french,
    required this.removeLabel,
    required this.onQuantity,
    required this.onRemove,
  });

  final KioskCartItem item;
  final bool french;
  final String removeLabel;
  final void Function(int quantity) onQuantity;
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

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(KioskScale.gapMd),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(name, style: theme.textTheme.titleLarge),
                  if (extras.isNotEmpty) ...<Widget>[
                    const SizedBox(height: KioskScale.gap),
                    Text(extras.join(' · '), style: theme.textTheme.labelLarge),
                  ],
                ],
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
              padding: const EdgeInsets.symmetric(horizontal: KioskScale.gapMd),
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
        ),
      ),
    );
  }
}
