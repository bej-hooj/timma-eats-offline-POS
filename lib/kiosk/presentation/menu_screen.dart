import 'package:flutter/material.dart';
import 'package:pos_core/pos_core.dart';

import 'package:timma_kiosk/design/money_formatter.dart';
import 'package:timma_kiosk/l10n/app_localizations.dart';
import '../theme/kiosk_scale.dart';
import 'widgets/kiosk_dish_card.dart';

/// How big one dish card is on the screen this kiosk actually has.
///
/// Whole rows only. A grid that shows a band of half-cut cards along the bottom
/// invites a standing customer to try to read them, and a kiosk is not a page
/// people expect to scroll — so the cards shrink to fit instead.
class _DishGridMetrics {
  const _DishGridMetrics({required this.cardWidth, required this.cardHeight});

  factory _DishGridMetrics.fit(double availableHeight) {
    // Below this a card is a thumbnail with an unreadable price from standing
    // distance; at that point scrolling is the lesser evil.
    const double minCardHeight = 190;
    final double usable = availableHeight.isFinite && availableHeight > 0
        ? availableHeight
        : KioskScale.dishCardHeight;

    // Two rows when they genuinely fit, otherwise one.
    final int rows = usable >= (minCardHeight * 2) + KioskScale.gapLg ? 2 : 1;
    final double perRow = (usable - (KioskScale.gapLg * (rows - 1))) / rows;
    final double cardHeight = perRow < minCardHeight ? minCardHeight : perRow;

    // The app's 180 × 208 proportion, kept whichever way the height lands. The
    // card is never made wider than the kiosk's own maximum, or a two-dish menu
    // would stretch into two billboards.
    final double proportional = cardHeight * KioskScale.dishCardAspectRatio;
    return _DishGridMetrics(
      cardWidth: proportional > KioskScale.dishCardWidth
          ? KioskScale.dishCardWidth
          : proportional,
      cardHeight: cardHeight,
    );
  }

  final double cardWidth;
  final double cardHeight;
}

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
            // ⚠ **The card is sized off the HEIGHT, not the width.**
            //
            // Sizing it off width alone was a real defect, measured on the
            // Samsung: in landscape that device is 868 × 411 dp, so the grid
            // viewport is about 259 dp tall and a card 370 dp tall had its
            // price row clipped clean off the bottom. The customer saw a dish
            // and no price. (The previous fixed 350 dp card had the same
            // problem — it had simply never been rendered at this size.)
            //
            // A kiosk gets mounted on whatever the restaurant bought, from a
            // phone in a landscape cradle to an 800 dp tablet, so the card
            // takes the room it actually has and keeps the app's proportion
            // while doing it.
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                final _DishGridMetrics metrics = _DishGridMetrics.fit(
                  constraints.maxHeight,
                );
                return GridView.builder(
                  gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                    // Max-extent rather than the app's fixed 2 columns: the
                    // app grid is two-up because a phone is 411 dp WIDE, and
                    // copying the count to a landscape kiosk would give two
                    // enormous cards and barely one dish per screen. Copying
                    // the card's size and proportion, and letting the column
                    // count fall out of the width, is what preserves the
                    // design here.
                    maxCrossAxisExtent: metrics.cardWidth,
                    // ⚠ The gutter is also the card size (the app card's own
                    // warning). 24 is `AppSpacing.l`, the gutter the app grid
                    // uses, so the space between dishes matches as well.
                    mainAxisSpacing: KioskScale.gapLg,
                    crossAxisSpacing: KioskScale.gapLg,
                    mainAxisExtent: metrics.cardHeight,
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
                      // tappable at all, so the composer can never be reached
                      // for a dish the kitchen cannot make (§K4 rule 4).
                      onTap: product.available ? () => onPick(product) : null,
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
