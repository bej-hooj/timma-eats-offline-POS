import 'package:flutter/material.dart';
import 'package:pos_core/pos_core.dart';

import 'package:timma_kiosk/design/money_formatter.dart';
import 'package:timma_kiosk/l10n/app_localizations.dart';
import '../theme/kiosk_scale.dart';

/// What the customer built, handed back to the caller.
class KioskComposition {
  const KioskComposition({
    required this.quantity,
    this.variant,
    this.options = const <SnapshotOption>[],
  });

  final int quantity;
  final SnapshotVariant? variant;
  final List<SnapshotOption> options;
}

/// Variants and option groups at parity with the phone app's composer.
///
/// ⚠ **`minSelect`/`maxSelect` count DISTINCT options, not total quantity.**
/// That is stated on [SnapshotOptionGroup] and was a real defect once in the
/// webapp composer (memory `timma-webapp-composer-parity-2026-07-29`). The
/// selection state here is therefore a `Set` of option ids per group, and the
/// gate is its `length` — there is no quantity to confuse it with.
class KioskComposerSheet extends StatefulWidget {
  const KioskComposerSheet({
    required this.product,
    required this.onAdd,
    required this.onCancel,
    super.key,
  });

  final SnapshotProduct product;
  final void Function(KioskComposition composition) onAdd;
  final VoidCallback onCancel;

  @override
  State<KioskComposerSheet> createState() => _KioskComposerSheetState();
}

class _KioskComposerSheetState extends State<KioskComposerSheet> {
  final Map<String, Set<String>> _chosen = <String, Set<String>>{};
  SnapshotVariant? _variant;
  int _quantity = 1;

  @override
  void initState() {
    super.initState();
    // A product with variants has no meaningful price until one is picked, so
    // the first is preselected rather than leaving the customer at a total
    // that is not the total.
    _variant = widget.product.variants.isEmpty
        ? null
        : widget.product.variants.first;
    for (final SnapshotOptionGroup g in widget.product.optionGroups) {
      _chosen[g.groupId] = <String>{};
    }
  }

  /// Every group's minimum is met. A group with `minSelect == 0` is optional
  /// and always satisfied.
  bool get _complete => widget.product.optionGroups.every(
    (SnapshotOptionGroup g) => _chosen[g.groupId]!.length >= g.minSelect,
  );

  List<SnapshotOption> get _selectedOptions => <SnapshotOption>[
    for (final SnapshotOptionGroup g in widget.product.optionGroups)
      for (final SnapshotOption o in g.options)
        if (_chosen[g.groupId]!.contains(o.optionId)) o,
  ];

  /// Priced through the same [Money] helpers the engine uses, so what the
  /// customer reads here is what `PosEngine._price` will charge.
  int get _unitPrice => Money.unitPrice(
    basePrice: widget.product.basePrice,
    variantDelta: _variant?.priceDelta ?? 0,
    options: <OptionCharge>[
      for (final SnapshotOption o in _selectedOptions)
        OptionCharge(priceDelta: o.priceDelta, quantity: 1),
    ],
  );

  void _toggle(SnapshotOptionGroup group, SnapshotOption option) {
    final Set<String> selected = _chosen[group.groupId]!;
    setState(() {
      if (selected.contains(option.optionId)) {
        selected.remove(option.optionId);
        return;
      }
      // DISTINCT options, not quantity. At the ceiling, a single-choice group
      // swaps rather than refusing — refusing a tap on a radio-shaped control
      // reads as a broken screen.
      if (selected.length >= group.maxSelect) {
        if (group.maxSelect == 1) {
          selected
            ..clear()
            ..add(option.optionId);
        }
        return;
      }
      selected.add(option.optionId);
    });
  }

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
          Text(
            french ? widget.product.nameFr : widget.product.nameEn,
            style: theme.textTheme.headlineLarge,
          ),
          const SizedBox(height: KioskScale.gapLg),
          Expanded(
            child: ListView(
              children: <Widget>[
                if (widget.product.variants.isNotEmpty)
                  _VariantGroup(
                    variants: widget.product.variants,
                    selected: _variant,
                    french: french,
                    onPick: (SnapshotVariant v) =>
                        setState(() => _variant = v),
                  ),
                for (final SnapshotOptionGroup group
                    in widget.product.optionGroups)
                  _OptionGroupBlock(
                    group: group,
                    selected: _chosen[group.groupId]!,
                    french: french,
                    onToggle: (SnapshotOption o) => _toggle(group, o),
                  ),
              ],
            ),
          ),
          const SizedBox(height: KioskScale.gapLg),
          Row(
            children: <Widget>[
              _QuantityStepper(
                quantity: _quantity,
                label: l10n.kioskQuantity,
                onChanged: (int q) => setState(() => _quantity = q),
              ),
              const Spacer(),
              OutlinedButton(
                onPressed: widget.onCancel,
                child: Text(l10n.kioskCancel),
              ),
              const SizedBox(width: KioskScale.gapMd),
              FilledButton(
                // Disabled until every required group is satisfied. The gate is
                // the same `_complete` the engine's own option validation would
                // reach, so the customer is never allowed to build something
                // that will be refused at placement.
                onPressed: _complete
                    ? () => widget.onAdd(
                        KioskComposition(
                          quantity: _quantity,
                          variant: _variant,
                          options: _selectedOptions,
                        ),
                      )
                    : null,
                child: Text(
                  '${l10n.kioskAdd}  '
                  '${MoneyFormatter.formatXaf(_unitPrice * _quantity)}',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _VariantGroup extends StatelessWidget {
  const _VariantGroup({
    required this.variants,
    required this.selected,
    required this.french,
    required this.onPick,
  });

  final List<SnapshotVariant> variants;
  final SnapshotVariant? selected;
  final bool french;
  final void Function(SnapshotVariant variant) onPick;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: KioskScale.gapLg),
      child: Wrap(
        spacing: KioskScale.gapMd,
        runSpacing: KioskScale.gapMd,
        children: <Widget>[
          for (final SnapshotVariant v in variants)
            _ChoiceChip(
              label: french ? v.nameFr : v.nameEn,
              delta: v.priceDelta,
              selected: v.variantId == selected?.variantId,
              onTap: () => onPick(v),
            ),
        ],
      ),
    );
  }
}

class _OptionGroupBlock extends StatelessWidget {
  const _OptionGroupBlock({
    required this.group,
    required this.selected,
    required this.french,
    required this.onToggle,
  });

  final SnapshotOptionGroup group;
  final Set<String> selected;
  final bool french;
  final void Function(SnapshotOption option) onToggle;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: KioskScale.gapLg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            french ? group.nameFr : group.nameEn,
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: KioskScale.gap),
          Text(_rule(l10n), style: theme.textTheme.labelLarge),
          const SizedBox(height: KioskScale.gapMd),
          Wrap(
            spacing: KioskScale.gapMd,
            runSpacing: KioskScale.gapMd,
            children: <Widget>[
              for (final SnapshotOption o in group.options)
                _ChoiceChip(
                  label: french ? o.nameFr : o.nameEn,
                  delta: o.priceDelta,
                  selected: selected.contains(o.optionId),
                  // A sold-out option is unselectable for the same reason a
                  // sold-out dish is unopenable.
                  onTap: o.available ? () => onToggle(o) : null,
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// The rule in words. Counts are **distinct options**.
  String _rule(AppLocalizations l10n) {
    if (group.minSelect == 0 && group.maxSelect >= group.options.length) {
      return l10n.kioskGroupOptional;
    }
    if (group.minSelect == group.maxSelect) {
      return l10n.kioskGroupChooseExactly(group.minSelect);
    }
    if (group.minSelect == 0) {
      return l10n.kioskGroupChooseUpTo(group.maxSelect);
    }
    return l10n.kioskGroupChooseAtLeast(group.minSelect);
  }
}

class _ChoiceChip extends StatelessWidget {
  const _ChoiceChip({
    required this.label,
    required this.delta,
    required this.selected,
    this.onTap,
  });

  final String label;
  final int delta;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool enabled = onTap != null;
    return Semantics(
      button: true,
      enabled: enabled,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(KioskScale.radius),
        child: Container(
          constraints: const BoxConstraints(
            minHeight: KioskScale.minTarget,
            minWidth: KioskScale.minTarget * 2,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: KioskScale.gapLg,
            vertical: KioskScale.gapMd,
          ),
          decoration: BoxDecoration(
            color: selected
                ? theme.colorScheme.primary
                : theme.colorScheme.surface,
            border: Border.all(
              color: selected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outline,
              width: 2,
            ),
            borderRadius: BorderRadius.circular(KioskScale.radius),
          ),
          child: Opacity(
            opacity: enabled ? 1 : 0.4,
            child: Text(
              delta == 0
                  ? label
                  : '$label  +${MoneyFormatter.formatXaf(delta)}',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: selected
                    ? theme.colorScheme.onPrimary
                    : theme.colorScheme.onSurface,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _QuantityStepper extends StatelessWidget {
  const _QuantityStepper({
    required this.quantity,
    required this.label,
    required this.onChanged,
  });

  final int quantity;
  final String label;
  final void Function(int quantity) onChanged;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        IconButton.outlined(
          iconSize: 36,
          onPressed: quantity > 1 ? () => onChanged(quantity - 1) : null,
          icon: const Icon(Icons.remove),
          constraints: const BoxConstraints(
            minWidth: KioskScale.minTarget,
            minHeight: KioskScale.minTarget,
          ),
          tooltip: label,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: KioskScale.gapLg),
          child: Text('$quantity', style: theme.textTheme.headlineLarge),
        ),
        IconButton.outlined(
          iconSize: 36,
          onPressed: () => onChanged(quantity + 1),
          icon: const Icon(Icons.add),
          constraints: const BoxConstraints(
            minWidth: KioskScale.minTarget,
            minHeight: KioskScale.minTarget,
          ),
          tooltip: label,
        ),
      ],
    );
  }
}
