import 'package:flutter/material.dart';
import 'package:pos_core/pos_core.dart';

import 'package:timma_kiosk/design/app_tokens.dart';
import 'package:timma_kiosk/design/money_formatter.dart';
import 'package:timma_kiosk/l10n/app_localizations.dart';

import '../../catalog/dish_photo_cache.dart';
import '../../state/kiosk_cart.dart';
import '../../theme/kiosk_scale.dart';
import 'kiosk_dish_thumb.dart';
import 'kiosk_scrollable.dart';

/// The basket, standing permanently beside the menu (owner, 2026-11-22:
/// *"we can even have a side menu to show what's on the cart already and
/// price"*, with three reference tills that all do exactly this).
///
/// ## Why a panel and not a better bottom bar
///
/// A kiosk screen is landscape and wide; a basket hidden behind a button is a
/// basket a customer has to trust. Every till in the references keeps the
/// order list in view while the customer builds it, so the running total is a
/// fact on screen rather than something to go and check. The panel appears
/// only where there is room for it — see [KioskCartPanel.fitsBeside] — and the
/// narrow layout keeps the bar.
///
/// ## It never prices anything
///
/// ⚠ Every figure here is [KioskCartState.subtotal] and [KioskCartItem.lineTotal],
/// the same values the cart screen reads and the same the engine re-computes
/// from the pinned bundle at placement. The client never does money arithmetic
/// of its own (CLAUDE.md §0.2) — a panel that added up its own rows would be a
/// second opinion about a price, and the one on the slip would win.
class KioskCartPanel extends StatefulWidget {
  const KioskCartPanel({
    required this.cart,
    required this.onCheckout,
    required this.onIncrement,
    required this.onDecrement,
    required this.onRemove,
    this.photoCache,
    super.key,
  });

  /// Below this the panel would squeeze the grid to two columns, which costs
  /// more menu than the basket is worth. Measured against the borne (1097 dp,
  /// comfortable) and a 7-inch tablet (960 dp, still fine).
  static const double minWidthToFit = 900;

  static bool fitsBeside(double width) => width >= minWidthToFit;

  /// ⚠ 340 was too narrow the moment a row carried more than a name. The
  /// basket only appears beside the menu on a screen of 900 dp or more, so
  /// these 40 dp come out of a grid that has them to spare.
  static const double panelWidth = 380;

  final KioskCartState cart;
  final VoidCallback onCheckout;
  final void Function(KioskCartItem item) onIncrement;
  final void Function(KioskCartItem item) onDecrement;

  /// Take the whole line out, however many of it there are.
  final void Function(KioskCartItem item) onRemove;

  /// The same disk cache the menu draws from, so a line in the basket shows
  /// the picture the customer just tapped — and keeps showing it when the
  /// line drops, which is the whole point of caching the photos at all.
  final DishPhotoCache? photoCache;

  @override
  State<KioskCartPanel> createState() => _KioskCartPanelState();
}

class _KioskCartPanelState extends State<KioskCartPanel> {
  /// Owned here: [KioskScrollable] listens to it.
  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    final ThemeData theme = Theme.of(context);
    return Container(
      width: KioskCartPanel.panelWidth,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.horizontal(
          left: Radius.circular(KioskScale.radiusLg),
        ),
      ),
      padding: const EdgeInsets.all(KioskScale.gapLg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(l10n.kioskCartTitle, style: theme.textTheme.headlineSmall),
          const SizedBox(height: KioskScale.gapMd),
          Expanded(
            child: widget.cart.isEmpty
                ? _Empty(l10n: l10n)
                : KioskScrollable(
                    controller: _scroll,
                    child: ListView.separated(
                      controller: _scroll,
                      itemCount: widget.cart.items.length,
                      separatorBuilder: (_, _) =>
                          const SizedBox(height: KioskScale.gap),
                      itemBuilder: (BuildContext context, int index) {
                        final KioskCartItem item = widget.cart.items[index];
                        return _Line(
                          item: item,
                          photoCache: widget.photoCache,
                          onIncrement: () => widget.onIncrement(item),
                          onDecrement: () => widget.onDecrement(item),
                          onRemove: () => widget.onRemove(item),
                        );
                      },
                    ),
                  ),
          ),
          const Divider(height: KioskScale.gapLg),
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  l10n.kioskCartTotal,
                  style: theme.textTheme.titleMedium,
                ),
              ),
              Text(
                MoneyFormatter.formatXaf(widget.cart.subtotal),
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: KioskScale.gapMd),
          SizedBox(
            height: KioskScale.minTarget,
            // ⚠ Disabled, not hidden, on an empty basket. A button that
            // appears when the first dish is added moves the whole panel under
            // the customer's finger mid-tap.
            child: FilledButton(
              onPressed: widget.cart.isEmpty ? null : widget.onCheckout,
              child: Text(l10n.kioskCartConfirm),
            ),
          ),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(
            Icons.shopping_basket_outlined,
            size: 56,
            color: theme.disabledColor,
          ),
          const SizedBox(height: KioskScale.gapMd),
          Text(
            l10n.kioskCartEmpty,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.disabledColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({
    required this.item,
    required this.onIncrement,
    required this.onDecrement,
    required this.onRemove,
    this.photoCache,
  });

  final KioskCartItem item;
  final DishPhotoCache? photoCache;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Locale locale = Localizations.localeOf(context);
    final bool french = locale.languageCode == 'fr';
    // ⚠⚠ **Two rows, because six controls do not fit one.**
    //
    // Measured on the borne 2026-11-23, with the remove key added: thumbnail
    // 56 + three 56 dp keys + the remove key left about 60 dp for the dish,
    // and "Pepper soup de bœuf TIMMA / 3 500 FCFA" wrapped ONE CHARACTER PER
    // LINE. A basket a customer cannot read is worse than one they cannot
    // edit, and the fix is not to shave the controls — it is to stop asking a
    // 340 dp panel to lay six things side by side.
    //
    // The dish and its composition get the full width; the price and the
    // quantity keys sit under them.
    // Owner, 2026-11-23: *"every dish row could even be improved in its
    // design and packed in borders"*. A card per line, which is also what the
    // full cart screen does — two surfaces showing the same basket should not
    // show it two different ways.
    return Container(
      key: const Key('kiosk-cart-row'),
      padding: const EdgeInsets.all(KioskScale.gap),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(KioskScale.radius),
        border: Border.all(color: AppColors.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // The dish, not a word for it. Every reference order list carries
              // the picture, and on a kiosk it is what lets a customer check
              // their basket at a glance instead of reading it.
              ClipRRect(
                borderRadius: BorderRadius.circular(KioskScale.gap),
                child: SizedBox(
                  width: 56,
                  height: 56,
                  child: KioskDishThumb(
                    photoUrl: item.product.photoUrl,
                    cache: photoCache,
                  ),
                ),
              ),
              const SizedBox(width: KioskScale.gap),
              if (item.hasPepper) ...<Widget>[
                const Icon(
                  Icons.local_fire_department_rounded,
                  color: AppColors.error,
                ),
                const SizedBox(width: KioskScale.gap),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      french ? item.product.nameFr : item.product.nameEn,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium,
                    ),
                    // ⚠ **What the customer actually composed, not just the
                    // dish name.** Seen on the real borne: a Poulet DG ordered
                    // *sans persil* with a plantain side read simply "Poulet
                    // DG" in the basket. The kitchen would get it right and the
                    // customer had no way to check it before paying — and the
                    // one choice they are most likely to want to verify is the
                    // one they had to go looking for.
                    if (_composition(french).isNotEmpty)
                      Text(
                        _composition(french),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.textMuted,
                        ),
                      ),
                    if (_removed(french).isNotEmpty)
                      Text(
                        _removed(french),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          // A removal is the line a kitchen can get wrong and a
                          // customer can react to, so it is not grey with the
                          // rest.
                          color: AppColors.error,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                  ],
                ),
              ),
              // ⚠ **A way out of the line, not just down to one.** Owner,
              // 2026-11-23: *"each dish row should have a remove button
              // (icon)"*. The minus key stops at 1 — by design, so a mis-tap
              // cannot silently empty a basket — which left a customer who had
              // added the wrong dish with no way to undo it from this panel.
              //
              // At the top right, away from the quantity keys: the one control
              // here that cannot be undone is the one that should not be hit by
              // habit.
              _Step(
                icon: Icons.close,
                onPressed: onRemove,
                color: AppColors.textMuted,
                // Named, not just an icon. Several unlabelled icon keys in one
                // row announce themselves identically, and the one that empties
                // a line must not be guessed at. `tooltip` is what `IconButton`
                // turns into the semantics label.
                tooltip: AppLocalizations.of(context)!.kioskCartRemoveLine(
                  french ? item.product.nameFr : item.product.nameEn,
                ),
              ),
            ],
          ),
          Row(
            children: <Widget>[
              Text(
                MoneyFormatter.formatXaf(item.lineTotal),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              _Step(icon: Icons.remove, onPressed: onDecrement),
              SizedBox(
                width: 32,
                child: Text(
                  '${item.quantity}',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium,
                ),
              ),
              _Step(icon: Icons.add, onPressed: onIncrement),
            ],
          ),
        ],
      ),
    );
  }

  /// Variant and chosen options, as one quiet line.
  String _composition(bool french) {
    final List<String> parts = <String>[
      if (item.variant != null)
        french ? item.variant!.nameFr : item.variant!.nameEn,
      for (final SnapshotOption o in item.options) french ? o.nameFr : o.nameEn,
    ];
    return parts.join(' · ');
  }

  /// What was left out, named — ids never reach a customer's eyes.
  String _removed(bool french) {
    final List<String> names = <String>[
      for (final String id in item.removedIngredientIds)
        for (final SnapshotIngredient i in item.product.ingredients)
          if (i.ingredientId == id) (french ? i.nameFr : i.nameEn),
    ];
    return names.isEmpty
        ? ''
        : names.map((String n) => french ? 'Sans $n' : 'No $n').join(' · ');
  }
}

/// A quantity step. 48 dp of ink inside a 56 dp hit box — smaller than the
/// menu's 72 dp rule on purpose: this is a correction a customer makes with the
/// basket already in front of them, not a control they hunt for across the room.
class _Step extends StatelessWidget {
  const _Step({
    required this.icon,
    required this.onPressed,
    this.color,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final String? tooltip;

  /// The remove key is drawn quieter than the quantity keys: it is the one a
  /// customer should reach for deliberately, not by habit.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 56,
      height: 56,
      child: IconButton(
        onPressed: onPressed,
        tooltip: tooltip,
        icon: Icon(icon, color: color),
      ),
    );
  }
}
