import 'package:flutter/material.dart';
import 'package:pos_core/pos_core.dart';

import 'package:timma_kiosk/design/app_tokens.dart';
import 'package:timma_kiosk/l10n/app_localizations.dart';

import '../../theme/kiosk_scale.dart';
import 'allergen_labels.dart';

/// Everything a customer may want to know about a dish before they commit.
///
/// Owner, 2026-11-22: *"when on open a view of a dish, he should see the
/// allergy and all informations about the dish just like on mobile app … even
/// description … ingredients too … same little icons on ingredients as on
/// accompagnements"*.
///
/// ## The order is the argument
///
/// Description, then what it is made of, then — last and loudest — what it
/// contains that could hurt someone. A customer reads top to bottom and stops
/// when they have decided; the allergens must still be the thing they cannot
/// miss, so they are a filled block rather than another line of text.
///
/// ## ⚠ The marks are CONTENT, not icons
///
/// The little mark beside an ingredient is `ingredients.icon`, chosen by an
/// operator in the dashboard the way they choose a photo. The structural icons
/// on this screen — the clock, the chilli, the warning — are vector, from one
/// family. A dish whose ingredients have no marks must read perfectly well,
/// because on an older Android a glyph the system font lacks renders as
/// nothing at all, which this project has shipped once already.
class KioskDishDetail extends StatelessWidget {
  const KioskDishDetail({required this.product, required this.french, super.key});

  final SnapshotProduct product;
  final bool french;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    final ThemeData theme = Theme.of(context);
    final String? description = french
        ? product.descriptionFr
        : product.descriptionEn;
    final List<String> allergens = product.allergens;
    final List<String> tags = <String>[
      for (final String t in product.tags)
        if (productTagLabel(t, french: french) != null)
          productTagLabel(t, french: french)!,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (tags.isNotEmpty) ...<Widget>[
          Wrap(
            spacing: KioskScale.gap,
            runSpacing: KioskScale.gap / 2,
            children: <Widget>[
              for (final String tag in tags) _Pill(label: tag),
            ],
          ),
          const SizedBox(height: KioskScale.gapMd),
        ],
        _MetaRow(product: product, french: french, l10n: l10n),
        if (description != null && description.trim().isNotEmpty) ...<Widget>[
          const SizedBox(height: KioskScale.gapMd),
          Text(
            description.trim(),
            style: theme.textTheme.bodyLarge?.copyWith(
              // 1.5 line-height: this is the only paragraph on the borne, and
              // it is read standing up at arm's length.
              height: 1.5,
              color: AppColors.textMuted,
            ),
          ),
        ],
        if (product.ingredients.isNotEmpty) ...<Widget>[
          const SizedBox(height: KioskScale.gapLg),
          _SectionTitle(label: l10n.kioskDishIngredients),
          const SizedBox(height: KioskScale.gap),
          Wrap(
            spacing: KioskScale.gap,
            runSpacing: KioskScale.gap,
            children: <Widget>[
              for (final SnapshotIngredient i in product.ingredients)
                _IngredientChip(ingredient: i, french: french),
            ],
          ),
        ],
        if (allergens.isNotEmpty) ...<Widget>[
          const SizedBox(height: KioskScale.gapLg),
          _AllergenBlock(
            allergens: allergens,
            french: french,
            title: l10n.kioskDishAllergens,
          ),
        ],
      ],
    );
  }
}

/// Prep time, origin and heat on one line — the three facts that are always
/// there, drawn the way the dish card draws them so the two surfaces agree.
class _MetaRow extends StatelessWidget {
  const _MetaRow({
    required this.product,
    required this.french,
    required this.l10n,
  });

  final SnapshotProduct product;
  final bool french;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final String? origin = french ? product.originFr : product.originEn;
    final int heat = product.spiceLevel.clamp(0, 3);
    return Wrap(
      spacing: KioskScale.gapMd,
      runSpacing: KioskScale.gap,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        _Fact(
          icon: Icons.schedule,
          label: l10n.kioskDishPrepWindow(product.prepMin, product.prepMax),
        ),
        if ((origin?.trim() ?? '').isNotEmpty)
          _Fact(icon: Icons.place_outlined, label: origin!.trim()),
        if (heat > 0)
          // ⚠ Heat is `spice_level`, NEVER the `spicy` tag — the tag is
          // marketing, the level is the kitchen's.
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              for (int i = 0; i < heat; i++)
                const Padding(
                  padding: EdgeInsets.only(right: 2),
                  child: Icon(
                    Icons.local_fire_department,
                    size: 20,
                    color: AppColors.error,
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(icon, size: 20, color: AppColors.textMuted),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            fontSize: KioskScale.labelSize,
            color: AppColors.textMuted,
          ),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Text(
    label,
    style: const TextStyle(
      fontSize: KioskScale.labelSize,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.4,
      color: AppColors.textMuted,
    ),
  );
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: AppColors.primarySoft,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: KioskScale.gapMd, vertical: 4),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: KioskScale.labelSize,
          fontWeight: FontWeight.w700,
          color: AppColors.primary,
        ),
      ),
    ),
  );
}

/// One ingredient: its mark, its name, and — when the kitchen allows it — the
/// fact that it can be left out.
class _IngredientChip extends StatelessWidget {
  const _IngredientChip({required this.ingredient, required this.french});

  final SnapshotIngredient ingredient;
  final bool french;

  @override
  Widget build(BuildContext context) {
    final String name = french ? ingredient.nameFr : ingredient.nameEn;
    final bool allergenic = ingredient.allergenTags.isNotEmpty;
    final String? mark = ingredient.icon?.trim();
    return Semantics(
      label: allergenic
          ? '$name, ${french ? 'allergène' : 'allergen'}'
          : name,
      child: ExcludeSemantics(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(KioskScale.radius),
            border: Border.all(
              // An allergenic ingredient is outlined here as well as listed
              // below: the customer who is scanning the list is the one who
              // needs it, and they may never reach the block.
              color: allergenic ? AppColors.error : AppColors.controlBorder,
              width: allergenic ? 2 : 1,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: KioskScale.gapMd,
              vertical: KioskScale.gap,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (mark != null && mark.isNotEmpty) ...<Widget>[
                  Text(mark, style: const TextStyle(fontSize: 18)),
                  const SizedBox(width: 6),
                ],
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: KioskScale.labelSize,
                    color: AppColors.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// ⚠ The one block on this screen that must not be missable.
class _AllergenBlock extends StatelessWidget {
  const _AllergenBlock({
    required this.allergens,
    required this.french,
    required this.title,
  });

  final List<String> allergens;
  final bool french;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$title: '
          '${allergens.map((String a) => allergenLabel(a, french: french)).join(', ')}',
      child: ExcludeSemantics(
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(KioskScale.gapMd),
          decoration: BoxDecoration(
            // ⚠ A TINT of the error token, derived here, not a new pigment in
            // `lib/design/`: that file mirrors `design-tokens/tokens.json` and
            // a hex invented in it is a fork of the brand.
            color: AppColors.error.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(KioskScale.radius),
            border: Border.all(color: AppColors.error, width: 2),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  const Icon(
                    Icons.warning_amber_rounded,
                    size: 22,
                    color: AppColors.error,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: KioskScale.labelSize,
                      fontWeight: FontWeight.w800,
                      color: AppColors.error,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: KioskScale.gap),
              Wrap(
                spacing: KioskScale.gap,
                runSpacing: KioskScale.gap / 2,
                children: <Widget>[
                  for (final String a in allergens)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Icon(allergenIcon(a), size: 18, color: AppColors.error),
                        const SizedBox(width: 4),
                        // ⚠ The WORD, always. Colour and an icon alone fail a
                        // colour-blind customer, and this is the one list
                        // where being missed has a consequence worse than a
                        // wrong order.
                        Text(
                          allergenLabel(a, french: french),
                          style: const TextStyle(
                            fontSize: KioskScale.labelSize,
                            fontWeight: FontWeight.w700,
                            color: AppColors.error,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
