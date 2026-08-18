import 'package:flutter/material.dart';

import 'package:timma_kiosk/design/app_tokens.dart';
import 'package:timma_kiosk/design/money_formatter.dart';
import 'package:timma_kiosk/l10n/app_localizations.dart';
import '../theme/kiosk_scale.dart';
import 'shift_close.dart';

/// What a manager reads at the end of a day that may have been entirely
/// offline.
///
/// It states **cash and mobile money apart**, never summed: the cash figure is
/// the one countable against the drawer, and a combined "till total" is a
/// number nobody can check. A third line names money that was paid with **no
/// tender recorded**, because null tender never means cash (§7.4) and folding
/// it in would hand a manager a drawer figure that does not match.
class ShiftCloseScreen extends StatelessWidget {
  const ShiftCloseScreen({
    required this.report,
    required this.onForceDrain,
    super.key,
  });

  final ShiftCloseReport report;
  final VoidCallback onForceDrain;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(KioskScale.gapXl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(l10n.shiftCloseTitle, style: theme.textTheme.headlineLarge),
              const SizedBox(height: KioskScale.gapLg),
              Expanded(
                child: ListView(
                  children: <Widget>[
                    _Figure(
                      label: l10n.shiftCloseCash,
                      value: MoneyFormatter.formatXaf(report.cashTotal),
                      emphasis: true,
                    ),
                    _Figure(
                      label: l10n.shiftCloseMomo,
                      value: MoneyFormatter.formatXaf(report.mobileMoneyTotal),
                    ),
                    if (report.untenderedTotal > 0)
                      _Figure(
                        label: l10n.shiftCloseUntendered,
                        value: MoneyFormatter.formatXaf(report.untenderedTotal),
                        warn: true,
                      ),
                    const Divider(height: KioskScale.gapXl),
                    _Figure(
                      label: l10n.shiftCloseTickets,
                      value: '${report.localTickets}',
                    ),
                    _Figure(
                      label: l10n.shiftCloseAcknowledged,
                      value: '${report.acknowledged}',
                    ),
                    _Figure(
                      label: l10n.shiftCloseUnsent,
                      value: '${report.unsent}',
                      warn: report.unsent > 0,
                    ),
                    const SizedBox(height: KioskScale.gapLg),
                    if (report.isSettled)
                      Text(
                        l10n.shiftCloseSettled,
                        style: theme.textTheme.titleLarge?.copyWith(
                          color: AppColors.primary,
                        ),
                      )
                    else ...<Widget>[
                      Text(
                        l10n.shiftCloseStranded,
                        style: theme.textTheme.titleLarge,
                      ),
                      const SizedBox(height: KioskScale.gapMd),
                      // Named, never counted. A manager cannot chase "3 failed".
                      for (final StrandedTicket t in report.stranded)
                        Padding(
                          padding: const EdgeInsets.only(
                            bottom: KioskScale.gap,
                          ),
                          child: Text(
                            l10n.shiftCloseTicketLine(
                              t.ticketNumber?.toString() ??
                                  l10n.shiftCloseNoTicketNumber,
                              t.reason,
                            ),
                            style: theme.textTheme.bodyLarge,
                          ),
                        ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: KioskScale.gapLg),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: onForceDrain,
                  child: Text(l10n.shiftCloseForceDrain),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({
    required this.label,
    required this.value,
    this.emphasis = false,
    this.warn = false,
  });

  final String label;
  final String value;
  final bool emphasis;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color? colour = warn
        ? theme.colorScheme.error
        : emphasis
        ? AppColors.primary
        : null;
    return Padding(
      padding: const EdgeInsets.only(bottom: KioskScale.gapMd),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          // Flexible both sides: the French labels here are long
          // ("Espèces (à compter en caisse)") and a clipped money label on a
          // reconciliation screen is worse than a wrapped one.
          Expanded(
            child: Text(
              label,
              style: emphasis
                  ? theme.textTheme.titleLarge
                  : theme.textTheme.bodyLarge,
            ),
          ),
          const SizedBox(width: KioskScale.gapMd),
          Text(
            value,
            style:
                (emphasis
                        ? theme.textTheme.headlineLarge
                        : theme.textTheme.titleLarge)
                    ?.copyWith(color: colour, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}
