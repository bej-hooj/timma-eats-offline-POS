import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pos_cloud/pos_cloud.dart';
import 'package:pos_core/pos_core.dart';

import '../../../design/app_tokens.dart';
import '../../../l10n/app_localizations.dart';
import '../../theme/kiosk_scale.dart';

/// *Menu de la semaine* (ECOSYSTEM §25.5): every published dish and the days
/// it is cooked over the next seven days, so a customer who looks for a dish
/// that is not on today's screen learns when to come back.
///
/// Uses the same fail-open rule as the menu: a day with nothing published
/// counts as "everything is cooked".
class KioskWeekMenuSheet extends StatelessWidget {
  const KioskWeekMenuSheet({
    super.key,
    required this.menu,
    required this.dayMenu,
    required this.today,
  });

  /// Number of days shown, today included.
  static const int span = 7;

  final MenuSnapshot menu;
  final KioskDayMenu dayMenu;

  /// Today in Africa/Douala, as a calendar date (time ignored).
  final DateTime today;

  static Future<void> show(
    BuildContext context, {
    required MenuSnapshot menu,
    required KioskDayMenu dayMenu,
    required DateTime today,
  }) => showDialog<void>(
    context: context,
    builder: (_) =>
        KioskWeekMenuSheet(menu: menu, dayMenu: dayMenu, today: today),
  );

  static String isoDate(DateTime day) => DateFormat('yyyy-MM-dd').format(day);

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    final ThemeData theme = Theme.of(context);
    final String locale = Localizations.localeOf(context).languageCode;
    final bool french = locale == 'fr';
    final List<DateTime> days = <DateTime>[
      for (int i = 0; i < span; i++)
        DateTime(today.year, today.month, today.day + i),
    ];
    final List<SnapshotProduct> products = <SnapshotProduct>[...menu.products]
      ..sort(
        (SnapshotProduct a, SnapshotProduct b) =>
            a.sortIndex.compareTo(b.sortIndex),
      );

    return Dialog(
      insetPadding: const EdgeInsets.all(KioskScale.gapXl),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: Padding(
          padding: const EdgeInsets.all(KioskScale.gapLg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                l10n.kioskWeekMenuTitle,
                style: theme.textTheme.headlineSmall,
              ),
              const SizedBox(height: KioskScale.gap),
              Text(l10n.kioskWeekMenuIntro, style: theme.textTheme.bodyLarge),
              const SizedBox(height: KioskScale.gapMd),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: products.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (BuildContext context, int index) {
                    final SnapshotProduct p = products[index];
                    final List<DateTime> cooked = <DateTime>[
                      for (final DateTime d in days)
                        if (dayMenu.isAvailable(p.productId, isoDate(d))) d,
                    ];
                    return Padding(
                      key: ValueKey<String>('week-${p.productId}'),
                      padding: const EdgeInsets.symmetric(
                        vertical: KioskScale.gap,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Expanded(
                            flex: 2,
                            child: Text(
                              french ? p.nameFr : p.nameEn,
                              style: theme.textTheme.titleMedium,
                            ),
                          ),
                          const SizedBox(width: KioskScale.gapMd),
                          Expanded(
                            flex: 3,
                            child: _Days(
                              cooked: cooked,
                              today: days.first,
                              span: span,
                              locale: locale,
                              l10n: l10n,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: KioskScale.gapMd),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(l10n.kioskWeekMenuClose),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Days extends StatelessWidget {
  const _Days({
    required this.cooked,
    required this.today,
    required this.span,
    required this.locale,
    required this.l10n,
  });

  final List<DateTime> cooked;
  final DateTime today;
  final int span;
  final String locale;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    if (cooked.length == span) {
      return Text(l10n.kioskWeekMenuEveryDay, style: text.bodyLarge);
    }
    if (cooked.isEmpty) {
      return Text(
        l10n.kioskWeekMenuNotScheduled,
        style: text.bodyLarge?.copyWith(color: AppColors.textMuted),
      );
    }
    return Wrap(
      spacing: KioskScale.gap,
      runSpacing: KioskScale.gap,
      children: <Widget>[
        for (final DateTime d in cooked)
          Chip(
            label: Text(
              d == today
                  ? l10n.kioskWeekMenuToday
                  : DateFormat.EEEE(locale).format(d),
            ),
            backgroundColor: d == today ? AppColors.primary : null,
            labelStyle: d == today
                ? const TextStyle(color: AppColors.onPrimary)
                : null,
          ),
      ],
    );
  }
}
