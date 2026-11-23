import 'package:flutter/material.dart';
import 'package:pos_core/pos_core.dart';

import 'package:timma_kiosk/design/app_tokens.dart';
import 'package:timma_kiosk/design/money_formatter.dart';
import 'package:timma_kiosk/l10n/app_localizations.dart';
import '../catalog/dish_photo_cache.dart';
import '../theme/kiosk_scale.dart';
import 'package:timma_kiosk/kiosk/motion/kiosk_fly_to_cart.dart';
import 'widgets/kiosk_category_pill.dart';
import 'widgets/kiosk_scrollable.dart';
import 'widgets/kiosk_dish_card.dart';

/// How big one dish card is on the screen this kiosk actually has.
///
/// Whole rows only. A grid that shows a band of half-cut cards along the bottom
/// invites a standing customer to try to read them, and a kiosk is not a page
/// people expect to scroll — so the cards shrink to fit instead.
/// Above this width the language control spells the language out.
///
/// 1100 dp: the borne itself is 1920, a 10-inch tablet 1280, and the Samsung
/// in landscape 868 — so the word appears everywhere there is room for it and
/// the two letters stay on the screens where the header is already tight.
const double _languageLabelWidth = 1100;

class _DishGridMetrics {
  const _DishGridMetrics({required this.cardWidth, required this.cardHeight});

  /// ⚠ Sized from the **width first**, then the height.
  ///
  /// It used to fit one or two rows into the available HEIGHT and let the card
  /// width fall out of that. On a 1097 dp borne that produced three enormous
  /// tiles and barely a screenful of menu — "the cards are too big, the screen
  /// is very large, get the screen size in consideration" (owner, 2026-11-22).
  /// A kiosk screen is wide, so the column count has to come from the width,
  /// the way every reference kiosk lays a menu out: four to six compact tiles
  /// a customer can take in at a glance.
  ///
  /// [_idealCardWidth] is a TARGET, not a minimum: the columns are whole, so
  /// the real width lands near it and the cards still fill the row edge to
  /// edge at any screen size.
  factory _DishGridMetrics.fit(double availableWidth, double availableHeight) {
    const double idealCardWidth = 200;
    const double minCardWidth = 168;
    const double maxCardWidth = KioskScale.dishCardWidth;

    final double width = availableWidth.isFinite && availableWidth > 0
        ? availableWidth
        : idealCardWidth * 4;

    // Whole columns, at least two — a single enormous column is the failure
    // this is replacing.
    int columns = (width / idealCardWidth).round().clamp(2, 8);
    double cardWidth = (width - (KioskScale.gapLg * (columns - 1))) / columns;

    // A screen so narrow that the ideal count would squeeze past legibility
    // drops a column rather than shrinking the type.
    while (cardWidth < minCardWidth && columns > 2) {
      columns -= 1;
      cardWidth = (width - (KioskScale.gapLg * (columns - 1))) / columns;
    }
    if (cardWidth > maxCardWidth) {
      cardWidth = maxCardWidth;
    }

    double cardHeight = cardWidth / KioskScale.dishCardAspectRatio;

    // And never taller than the viewport can show in one go: a card that does
    // not fit on screen is a card a standing customer has to scroll to read.
    final double usableHeight = availableHeight.isFinite && availableHeight > 0
        ? availableHeight
        : cardHeight;
    if (cardHeight > usableHeight) {
      cardHeight = usableHeight;
    }
    return _DishGridMetrics(cardWidth: cardWidth, cardHeight: cardHeight);
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
    this.onQuickAdd,
    super.key,
  });

  final MenuSnapshot menu;

  /// The dish photographs already on disk. Null renders every dish as the
  /// brand panel, which is what an unconfigured kiosk should do.
  final DishPhotoCache? photoCache;
  final void Function(SnapshotProduct product) onPick;

  /// One tap from the grid into the basket, with the bubble flying from the
  /// "+" that was pressed (owner, 2026-11-22). The `Offset` is where the flight
  /// starts, in global coordinates.
  ///
  /// ⚠ Offered **only** for a dish with nothing to decide — see
  /// [_canQuickAdd]. Skipping a required group would put a line in the basket
  /// the kitchen cannot cook, which is the composer's whole reason to exist.
  final void Function(SnapshotProduct product, Offset from)? onQuickAdd;

  /// FR ↔ EN. A bilingual market means the kiosk cannot assume; the toggle is
  /// on the menu header where a customer looks first, and it resets to French
  /// with the session because the next person is a different person.
  final VoidCallback onToggleLanguage;

  @override
  State<KioskMenuScreen> createState() => _KioskMenuScreenState();
}

/// A dish a customer can put in the basket without being asked anything.
///
/// A variant choice or any group with `minSelect > 0` is a question, and a
/// question skipped is a wrong order. Optional groups are deliberately NOT a
/// blocker: the customer can still tap the card to add a side, and refusing
/// the "+" over an optional extra would make most of the menu feel broken.
bool _canQuickAdd(SnapshotProduct product) {
  if (!product.available) {
    return false;
  }
  if (product.variants.length > 1) {
    return false;
  }
  return product.optionGroups.every(
    (SnapshotOptionGroup g) => g.minSelect <= 0,
  );
}

class _KioskMenuScreenState extends State<KioskMenuScreen> {
  /// The dish grid's own controller — [KioskScrollable] listens to it to know
  /// whether there is menu below the fold. On a borne that matters more than
  /// anywhere else: a customer who does not know the menu continues does not
  /// experiment, they order from what they can see.
  final ScrollController _gridScroll = ScrollController();
  final TextEditingController _search = TextEditingController();

  /// One key per dish, so the bubble can start from the "+" that was actually
  /// tapped rather than from the middle of the screen.
  final Map<String, GlobalKey> _addKeys = <String, GlobalKey>{};

  /// null = "Tout", the strip's first pill. Exactly one pill is lit at a time,
  /// like the app's "Notre menu".
  String? _categoryId;

  @override
  void dispose() {
    _gridScroll.dispose();
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

    // ⚠ A kiosk screen is whatever the restaurant mounted. The stacked icon
    // tile needs 112 dp of strip; on a 411 dp-tall landscape handset that
    // comes straight off the dish grid and the page overflows. Below this the
    // strip falls back to icon-beside-label at the ordinary touch height.
    final bool compactCategories = MediaQuery.sizeOf(context).height < 560;

    // ⚠ The chrome was eating the menu. Measured on the GM92 (569 dp tall):
    // 40 dp of padding top and bottom, a 40 pt title, a 224 dp language
    // button and a 112 dp category strip left the dish grid under half the
    // screen. The page keeps its generous SIDE margins — a kiosk is touched,
    // not read at a desk — and gives the vertical back to the dishes.
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        KioskScale.gapXl,
        KioskScale.gapLg,
        KioskScale.gapXl,
        KioskScale.gapLg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // Title, search and language on ONE row. The search bar deliberately
          // costs no vertical space: at 411 dp the grid has ~259 dp to work
          // with, and a second row would come straight off the dish cards.
          Row(
            children: <Widget>[
              // ⚠ `Flexible`, not a bare `Text`. The title is the one thing on
              // this row that can give way, and it has to: the basket panel
              // takes 340 dp off the menu pane, and at 757 dp an unyielding
              // 40 pt heading pushed the row 6 px over — caught by a widget
              // test at the borne's real width, not on the device.
              Flexible(
                child: Text(
                  l10n.kioskMenuTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  // One step down from `headlineLarge`: the title names the
                  // screen, the dishes are the screen.
                  style: theme.textTheme.headlineSmall,
                ),
              ),
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
              const SizedBox(width: KioskScale.gapMd),
              // ⚠ NOT the themed `OutlinedButton`. That theme is built for the
              // menu path — a 144 dp minimum plus 40 dp of horizontal padding,
              // so a two-word label came out about 224 dp wide for a control
              // nobody came here to press. The HIT AREA stays the full 72 dp
              // touch target; only the ink shrinks, and the label becomes the
              // language it switches TO.
              SizedBox(
                height: KioskScale.minTarget,
                child: OutlinedButton(
                  onPressed: widget.onToggleLanguage,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(
                      KioskScale.minTarget,
                      KioskScale.minTarget,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: KioskScale.gapMd,
                    ),
                    side: const BorderSide(
                      color: AppColors.controlBorder,
                      width: 2,
                    ),
                    textStyle: const TextStyle(
                      fontSize: KioskScale.labelSize,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  // ⚠ **The label is responsive, not fixed.** It was cut to
                  // two letters because the themed button made "English" about
                  // 224 dp wide on a control nobody came here to press — but
                  // on a wide screen, and certainly on a television, two
                  // letters are a puzzle where there is room for the word.
                  // Owner, 2026-11-23: full text on a larger screen.
                  //
                  // The language it switches TO, in that language: a French
                  // customer looking for English scans for "English", not for
                  // "Anglais".
                  child: Text(
                    MediaQuery.sizeOf(context).width >= _languageLabelWidth
                        ? (french ? 'English' : 'Français')
                        : (french ? 'EN' : 'FR'),
                  ),
                ),
              ),
            ],
          ),
          if (categories.isNotEmpty) ...<Widget>[
            const SizedBox(height: KioskScale.gapMd),
            SizedBox(
              // One row, horizontally scrollable — the strip must never wrap
              // onto a second line and eat the dish grid's height.
              //
              // ⚠ `minTarget` (72) was the height of a one-line pill. The tile
              // now stacks an icon, the name and the dish count, and at 72 it
              // overflowed by 30 px — caught by the filter tests, not on the
              // device. Sized to the tile, with the touch rule still met
              // several times over.
              height: compactCategories
                  ? KioskScale.minTarget
                  : KioskScale.categoryTileHeight,
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
                      // ⚠ The WHOLE menu, not what the search has narrowed to.
                      // A count that moved while someone typed would be a
                      // second, quieter search result.
                      count: products.length,
                      compact: compactCategories,
                      onTap: () => setState(() => _categoryId = null),
                    );
                  }
                  final SnapshotCategory category = categories[index - 1];
                  return KioskCategoryPill(
                    label: french ? category.nameFr : category.nameEn,
                    selected: selected == category.categoryId,
                    count: products
                        .where(
                          (SnapshotProduct p) =>
                              p.categoryId == category.categoryId,
                        )
                        .length,
                    compact: compactCategories,
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
                  constraints.maxWidth,
                  constraints.maxHeight,
                );
                return KioskScrollable(
                  controller: _gridScroll,
                  child: GridView.builder(
                    controller: _gridScroll,
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
                        quickAddKey: _addKeys.putIfAbsent(
                          product.productId,
                          GlobalKey.new,
                        ),
                        onQuickAdd:
                            widget.onQuickAdd != null && _canQuickAdd(product)
                            ? () {
                                final GlobalKey key =
                                    _addKeys[product.productId]!;
                                widget.onQuickAdd!(
                                  product,
                                  centerOf(key) ?? Offset.zero,
                                );
                              }
                            : null,
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
