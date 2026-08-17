import 'package:flutter/material.dart';
import 'package:pos_core/pos_core.dart';

import 'package:timma_kiosk/design/money_formatter.dart';
import 'package:timma_kiosk/l10n/app_localizations.dart';
import '../state/kiosk_session.dart';
import '../theme/kiosk_scale.dart';

/// The last screen: a **large calm number** and where to take it.
///
/// It renders [PosOrder.ticketNumber] — assigned instantly and locally at the
/// moment of sale, reset at the Douala day boundary. Deliberately **not**
/// `dailyCode`, which is the kitchen's and is minted by the server: an offline
/// ticket does not have one yet, and a screen that waits on the network to tell
/// a customer where to pay is the whole failure §23 exists to prevent.
///
/// **No PII.** The kiosk never collects a name or a phone, and this screen
/// faces the room.
class KioskCounterScreen extends StatelessWidget {
  const KioskCounterScreen({
    required this.placed,
    required this.onDone,
    required this.printState,
    required this.onRetryPrint,
    super.key,
  });

  final PlacedOrder placed;
  final VoidCallback onDone;

  /// What became of this sale's slip. The order is already durable either way;
  /// this line exists so a customer never walks to the counter believing they
  /// are holding a ticket that was never printed.
  final KioskPrintState printState;
  final VoidCallback onRetryPrint;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    final ThemeData theme = Theme.of(context);
    final int? number = placed.order.ticketNumber;

    return ColoredBox(
      color: theme.colorScheme.primary,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(KioskScale.gapXl),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Text(
                l10n.kioskCounterThanks,
                style: theme.textTheme.headlineLarge?.copyWith(
                  color: theme.colorScheme.onPrimary,
                ),
              ),
              const SizedBox(height: KioskScale.gapLg),
              Text(
                l10n.kioskCounterSubtitle,
                style: theme.textTheme.titleLarge?.copyWith(
                  color: theme.colorScheme.onPrimary.withValues(alpha: 0.8),
                ),
              ),
              const SizedBox(height: KioskScale.gapMd),
              Text(
                number == null ? '—' : '$number',
                style: TextStyle(
                  fontSize: KioskScale.counterNumberSize,
                  fontWeight: FontWeight.w800,
                  height: 1,
                  color: theme.colorScheme.onPrimary,
                ),
              ),
              const SizedBox(height: KioskScale.gapXl),
              Text(
                l10n.kioskCounterTitle,
                textAlign: TextAlign.center,
                style: theme.textTheme.displayLarge?.copyWith(
                  color: theme.colorScheme.onPrimary,
                ),
              ),
              const SizedBox(height: KioskScale.gapMd),
              Text(
                MoneyFormatter.formatXaf(placed.order.total),
                style: theme.textTheme.headlineLarge?.copyWith(
                  color: theme.colorScheme.onPrimary.withValues(alpha: 0.85),
                ),
              ),
              const SizedBox(height: KioskScale.gapLg),
              _SlipStatus(printState: printState, onRetryPrint: onRetryPrint),
              const SizedBox(height: KioskScale.gapXl),
              OutlinedButton(
                onPressed: onDone,
                style: OutlinedButton.styleFrom(
                  side: BorderSide(
                    color: theme.colorScheme.onPrimary,
                    width: 2,
                  ),
                  foregroundColor: theme.colorScheme.onPrimary,
                ),
                child: Text(l10n.kioskCounterNewOrder),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The slip's fate, in one line the customer can act on.
///
/// A successful print says nothing at all: the paper is in their hand and a
/// label confirming it would be noise. Only *printing* and *not printed* are
/// worth screen space, and the failure carries the recovery — reprint — beside
/// the number they can still show at the counter.
class _SlipStatus extends StatelessWidget {
  const _SlipStatus({required this.printState, required this.onRetryPrint});

  final KioskPrintState printState;
  final VoidCallback onRetryPrint;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    final ThemeData theme = Theme.of(context);
    final Color on = theme.colorScheme.onPrimary;

    switch (printState) {
      case KioskPrintState.none:
      case KioskPrintState.printed:
        return const SizedBox.shrink();

      case KioskPrintState.printing:
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: on),
            ),
            const SizedBox(width: KioskScale.gapMd),
            Text(
              l10n.kioskPrintPrinting,
              style: theme.textTheme.titleMedium?.copyWith(color: on),
            ),
          ],
        );

      case KioskPrintState.failed:
        return Column(
          children: <Widget>[
            Text(
              l10n.kioskPrintFailed,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(color: on),
            ),
            const SizedBox(height: KioskScale.gap),
            TextButton.icon(
              onPressed: onRetryPrint,
              icon: Icon(Icons.print_outlined, color: on),
              label: Text(
                l10n.kioskPrintRetry,
                style: theme.textTheme.titleMedium?.copyWith(color: on),
              ),
            ),
          ],
        );
    }
  }
}

/// No menu is pinned, so the kiosk has no prices and refuses loudly.
///
/// An empty menu would read as a closed kitchen and send the customer away; a
/// kiosk that says *order at the counter* keeps the sale in the building
/// (plan §K4 rule 5).
class KioskOutOfServiceScreen extends StatelessWidget {
  const KioskOutOfServiceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    final ThemeData theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(KioskScale.gapXl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(
              Icons.storefront_outlined,
              size: 120,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: KioskScale.gapXl),
            Text(
              l10n.kioskOutOfServiceTitle,
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineLarge,
            ),
            const SizedBox(height: KioskScale.gapMd),
            Text(
              l10n.kioskOutOfServiceBody,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge,
            ),
          ],
        ),
      ),
    );
  }
}
