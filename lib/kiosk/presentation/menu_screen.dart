import 'package:flutter/material.dart';
import 'package:pos_core/pos_core.dart';

import 'package:timma_kiosk/design/app_tokens.dart';
import 'package:timma_kiosk/design/money_formatter.dart';
import 'package:timma_kiosk/l10n/app_localizations.dart';
import '../catalog/dish_photo_cache.dart';
import '../theme/kiosk_scale.dart';
import 'widgets/kiosk_category_pill.dart';
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
class KioskMenuScreen extends StatefulWidget {
  const KioskMenuScreen({
    required this.menu,
    required this.onPick,
    required this.onToggleLanguage,
    this.photoCache,
    super.key,
  });

  final MenuSnapshot menu;

  /// The dish photographs already on disk. Null renders every dish as the
  /// brand panel, which is what an unconfigured kiosk should do.
  final DishPhotoCache? photoCache;
  final void Function(SnapshotProduct product) onPick;

  /// FR ↔ EN. A bilingual market means the kiosk cannot assume; the toggle is
  /// on the menu header where a customer looks first, and it resets to French
  /// with the session because the next person is a different person.
  final VoidCallback onToggleLanguage;

  @override
  State<KioskMenuScreen> createState() => _KioskMenuScreenState();
}

class _KioskMenuScreenState extends State<KioskMenuScreen> {
  final TextEditingController _search = TextEditingController();

  /// null = "Tout", the strip's first pill. Exactly one pill is lit at a time,
  /// like the app's "Notre menu".
  String? _categoryId;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// Accent- and case-insensitive: nobody types "Ndolé" with the accent while
  /// a queue forms behind them, and a search that demands it is a search that
  /// gets abandoned.
  static String _fold(String value) {
    const String accented = 'àâäáãåçéèêëíìîïñóòôöõúùûüýÿ';
    const String plain = 'aaaaaaceeeeiiiinooooouuuuyy';
    final StringBuffer out = StringBuffer();
    for (final int unit in value.toLowerCase().runes) {
      final int index = accented.runes.toList().indexOf(unit);
      out.write(index < 0 ? String.fromCharCode(unit) : plain[index]);
    }
    return out.toString();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    final ThemeData theme = Theme.of(context);
    final bool french = Localizations.localeOf(context).languageCode == 'fr';
    final String query = _fold(_search.text.trim());
    final List<SnapshotProduct> products =
        <SnapshotProduct>[...widget.menu.products]..sort(
          (SnapshotProduct a, SnapshotProduct b) =>
              a.sortIndex.compareTo(b.sortIndex),
        );
    // Categories the server sent, narrowed to those this menu actually uses.
    // A bundle from a server that predates the categories field simply has
    // none, and the strip disappears rather than showing an empty rail.
    final Set<String> usedCategories = products
        .map((SnapshotProduct p) => p.categoryId)
        .whereType<String>()
        .toSet();
    final List<SnapshotCategory> categories =
        <SnapshotCategory>[
          ...widget.menu.categories.where(
            (SnapshotCategory c) => usedCategories.contains(c.categoryId),
          ),
        ]..sort(
          (SnapshotCategory a, SnapshotCategory b) =>
              a.sortIndex.compareTo(b.sortIndex),
        );
    // A filter pointing at a category that just left the menu (ops unpublished
    // it while someone was browsing) falls back to "Tout" rather than showing
    // an empty grid.
    final String? selected =
        categories.any((SnapshotCategory c) => c.categoryId == _categoryId)
        ? _categoryId
        : null;

    final List<SnapshotProduct> shown = products
        .where(
          (SnapshotProduct p) => selected == null || p.categoryId == selected,
        )
        .where(
          (SnapshotProduct p) =>
              query.isEmpty ||
              _fold(p.nameFr).contains(query) ||
              _fold(p.nameEn).contains(query),
        )
        .toList(growable: false);

    return Padding(
      padding: const EdgeInsets.all(KioskScale.gapXl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // Title, search and language on ONE row. The search bar deliberately
          // costs no vertical space: at 411 dp the grid has ~259 dp to work
          // with, and a second row would come straight off the dish cards.
          Row(
            children: <Widget>[
              Text(l10n.kioskMenuTitle, style: theme.textTheme.headlineLarge),
              const SizedBox(width: KioskScale.gapLg),
              Expanded(
                child: TextField(
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  textInputAction: TextInputAction.search,
                  style: theme.textTheme.bodyLarge,
                  decoration: InputDecoration(
                    hintText: l10n.kioskSearchHint,
                    prefixIcon: const Icon(Icons.search),
                    // The clear button matters more here than in an app: a
                    // customer who walks away mid-search must not leave the
                    // next person looking at a filtered menu, and the idle
                    // reset is the other half of that (see `didUpdateWidget`).
                    suffixIcon: _search.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: l10n.kioskSearchClear,
                            icon: const Icon(Icons.close),
                            onPressed: () => setState(_search.clear),
                          ),
                    filled: true,
                    fillColor: AppColors.surface,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: KioskScale.gapMd,
                      vertical: KioskScale.gap,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(KioskScale.radius),
                      borderSide: const BorderSide(
                        color: AppColors.controlBorder,
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(KioskScale.radius),
                      borderSide: const BorderSide(
                        color: AppColors.controlBorder,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: KioskScale.gapLg),
              OutlinedButton(
                onPressed: widget.onToggleLanguage,
                child: Text(french ? 'English' : 'Français'),
              ),
            ],
          ),
          if (categories.isNotEmpty) ...<Widget>[
            const SizedBox(height: KioskScale.gapMd),
            SizedBox(
              // One row, horizontally scrollable — the strip must never wrap
              // onto a second line and eat the dish grid's height.
              height: KioskScale.minTarget,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: categories.length + 1,
                separatorBuilder: (_, _) =>
                    const SizedBox(width: KioskScale.gapMd),
                itemBuilder: (BuildContext context, int index) {
                  if (index == 0) {
                    return KioskCategoryPill(
                      label: l10n.kioskCategoryAll,
                      selected: selected == null,
                      onTap: () => setState(() => _categoryId = null),
                    );
                  }
                  final SnapshotCategory category = categories[index - 1];
                  return KioskCategoryPill(
                    label: french ? category.nameFr : category.nameEn,
                    selected: selected == category.categoryId,
                    onTap: () =>
                        setState(() => _categoryId = category.categoryId),
                  );
                },
              ),
            ),
          ],
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
                // The empty state is mandatory on an async-ish surface (§13.2),
                // and doubly so here: a filtered menu with no hits and no
                // message reads as "the kitchen is closed".
                if (shown.isEmpty) {
                  // Scrollable for the same reason every other kiosk surface
                  // is: this sits in whatever height the grid had, which on a
                  // 411 dp screen with a category strip above is not much, and
                  // a long French line must not clip its own retry button.
                  return SingleChildScrollView(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight,
                      ),
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: <Widget>[
                            Text(
                              l10n.kioskSearchEmpty,
                              textAlign: TextAlign.center,
                              style: theme.textTheme.titleLarge,
                            ),
                            const SizedBox(height: KioskScale.gapMd),
                            OutlinedButton(
                              onPressed: () => setState(_search.clear),
                              child: Text(l10n.kioskSearchClear),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }
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
                  itemCount: shown.length,
                  itemBuilder: (BuildContext context, int index) {
                    final SnapshotProduct product = shown[index];
                    return KioskDishCard(
                      name: french ? product.nameFr : product.nameEn,
                      price: MoneyFormatter.formatXaf(product.basePrice),
                      photoUrl: product.photoUrl,
                      photoCache: widget.photoCache,
                      soldOut: !product.available,
                      soldOutLabel: l10n.kioskSoldOut,
                      // R1 meta, straight off the pinned bundle (migration 53).
                      // ⚠ Heat is `spice_level`, never the `spicy` tag.
                      prepMin: product.prepMin,
                      prepMax: product.prepMax,
                      spiceLevel: product.spiceLevel,
                      origin: french ? product.originFr : product.originEn,
                      // Sold out is a barrier, not a badge: the card is not
                      // tappable at all, so the composer can never be reached
                      // for a dish the kitchen cannot make (§K4 rule 4).
                      onTap: product.available
                          ? () => widget.onPick(product)
                          : null,
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
