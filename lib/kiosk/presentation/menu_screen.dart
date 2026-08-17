import 'package:flutter/material.dart';
import 'package:pos_core/pos_core.dart';

import 'package:timma_kiosk/design/money_formatter.dart';
import 'package:timma_kiosk/l10n/app_localizations.dart';
import '../theme/kiosk_scale.dart';
import 'widgets/kiosk_dish_card.dart';

/// The pinned menu, as dish photography a standing customer can read.
///
/// The menu comes from [MenuSnapshot] — the bundle pinned on this device — and
/// never from the network. There is no loading state here on purpose: the
/// snapshot is already on disk or the kiosk is out of service, and a spinner
/// would be a third state that cannot happen (§23.1, offline is the normal
/// mode).
class KioskMenuScreen extends StatelessWidget {
  const KioskMenuScreen({
    required this.menu,
    required this.onPick,
    required this.onToggleLanguage,
    super.key,
  });

  final MenuSnapshot menu;
  final void Function(SnapshotProduct product) onPick;

  /// FR ↔ EN. A bilingual market means the kiosk cannot assume; the toggle is
  /// on the menu header where a customer looks first, and it resets to French
  /// with the session because the next person is a different person.
  final VoidCallback onToggleLanguage;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    final ThemeData theme = Theme.of(context);
    final bool french = Localizations.localeOf(context).languageCode == 'fr';
    final List<SnapshotProduct> products = <SnapshotProduct>[...menu.products]
      ..sort(
        (SnapshotProduct a, SnapshotProduct b) =>
            a.sortIndex.compareTo(b.sortIndex),
      );

    return Padding(
      padding: const EdgeInsets.all(KioskScale.gapXl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(l10n.kioskMenuTitle, style: theme.textTheme.headlineLarge),
              const Spacer(),
              OutlinedButton(
                onPressed: onToggleLanguage,
                child: Text(french ? 'English' : 'Français'),
              ),
            ],
          ),
          const SizedBox(height: KioskScale.gapLg),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.only(bottom: KioskScale.gapXxl),
              gridDelegate:
                  const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: KioskScale.dishCardWidth,
                    mainAxisSpacing: KioskScale.gapLg,
                    crossAxisSpacing: KioskScale.gapLg,
                    // Photo + name + price, at kiosk type sizes.
                    mainAxisExtent: KioskScale.dishCardImageHeight + 150,
                  ),
              itemCount: products.length,
              itemBuilder: (BuildContext context, int index) {
                final SnapshotProduct product = products[index];
                return KioskDishCard(
                  name: french ? product.nameFr : product.nameEn,
                  price: MoneyFormatter.formatXaf(product.basePrice),
                  photoUrl: product.photoUrl,
                  soldOut: !product.available,
                  soldOutLabel: l10n.kioskSoldOut,
                  // Sold out is a barrier, not a badge: the card is not
                  // tappable at all, so the composer can never be reached for
                  // a dish the kitchen cannot make (plan §K4 rule 4).
                  onTap: product.available ? () => onPick(product) : null,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
