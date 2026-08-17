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
    final ThemeData theme = Theme.of(context);
    final int? number = placed.order.ticketNumber;

    return ColoredBox(
      color: theme.colorScheme.primary,
      // ⚠ **Everything on this screen has to fit, on whatever the kiosk is
      // mounted on.** Measured on the Samsung: in landscape that device is
      // 411 dp tall and this content overflowed a single column by 336 px,
      // pushing the total, the slip line and *Nouvelle commande* clean off the
      // bottom. The sale itself was fine — the customer simply had no way to
      // see its price or start the next order, and a kiosk customer does not
      // think to scroll.
      //
      // So on a short screen the layout uses the axis it actually has: the
      // number takes the left half and everything else stacks on the right.
      // Stacked vertically it cannot fit at 411 dp however the type is tuned;
      // side by side it fits with room to spare.
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final double height = constraints.maxHeight.isFinite
              ? constraints.maxHeight
              : 800;
          final bool sideBySide =
              height < _stackedNeeds && constraints.maxWidth > height;
          final Widget ticket = _Ticket(
            number: number,
            size: _numberSize(height, sideBySide: sideBySide),
            showCaption: !sideBySide,
          );
          final Widget details = _Details(
            placed: placed,
            printState: printState,
            onRetryPrint: onRetryPrint,
            onDone: onDone,
            crossAxisAlignment: sideBySide
                ? CrossAxisAlignment.start
                : CrossAxisAlignment.center,
          );

          return SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: height),
              child: Padding(
                padding: const EdgeInsets.all(KioskScale.gapLg),
                child: sideBySide
                    ? Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: <Widget>[
                          Expanded(child: Center(child: ticket)),
                          const SizedBox(width: KioskScale.gapLg),
                          Expanded(child: details),
                        ],
                      )
                    : Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: <Widget>[
                            ticket,
                            const SizedBox(height: KioskScale.gapMd),
                            details,
                          ],
                        ),
                      ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// Roughly what the stacked layout needs before it starts pushing its own
  /// actions off the bottom. Below this the side-by-side layout takes over.
  static const double _stackedNeeds = 620;

  /// The ticket number's type size for the height this screen actually got.
  ///
  /// It stays the biggest thing on the screen — a customer reads it across a
  /// room — but it is a share of the available height rather than a constant, so
  /// it cannot push the rest of the screen off a short one.
  static double _numberSize(
    double availableHeight, {
    required bool sideBySide,
  }) {
    if (!availableHeight.isFinite || availableHeight <= 0) {
      return KioskScale.counterNumberSize;
    }
    // Side by side the number owns its half, so it can spend more of the height
    // than when it is one item in a stack.
    final double share = availableHeight * (sideBySide ? 0.45 : 0.28);
    return share > KioskScale.counterNumberSize
        ? KioskScale.counterNumberSize
        : (share < 48 ? 48 : share);
  }
}

/// The number a customer shows at the counter, and nothing else.
class _Ticket extends StatelessWidget {
  const _Ticket({
    required this.number,
    required this.size,
    required this.showCaption,
  });

  final int? number;
  final double size;

  /// The stacked layout keeps "Merci !" and "Présentez ce numéro" above the
  /// number; side by side they belong with the rest of the words, so the left
  /// half is the number alone and reads from across the room.
  final bool showCaption;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    final ThemeData theme = Theme.of(context);
    final Color on = theme.colorScheme.onPrimary;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (showCaption) ...<Widget>[
          Text(
            l10n.kioskCounterThanks,
            style: theme.textTheme.headlineLarge?.copyWith(color: on),
          ),
          const SizedBox(height: KioskScale.gap),
          Text(
            l10n.kioskCounterSubtitle,
            style: theme.textTheme.titleLarge?.copyWith(
              color: on.withValues(alpha: 0.8),
            ),
          ),
        ],
        Text(
          number == null ? '—' : '$number',
          maxLines: 1,
          style: TextStyle(
            fontSize: size,
            fontWeight: FontWeight.w800,
            height: 1.1,
            color: on,
          ),
        ),
      ],
    );
  }
}

/// Where to pay, how much, what happened to the slip, and the way out.
class _Details extends StatelessWidget {
  const _Details({
    required this.placed,
    required this.printState,
    required this.onRetryPrint,
    required this.onDone,
    required this.crossAxisAlignment,
  });

  final PlacedOrder placed;
  final KioskPrintState printState;
  final VoidCallback onRetryPrint;
  final VoidCallback onDone;
  final CrossAxisAlignment crossAxisAlignment;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    final ThemeData theme = Theme.of(context);
    final Color on = theme.colorScheme.onPrimary;
    final bool stacked = crossAxisAlignment == CrossAxisAlignment.center;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: crossAxisAlignment,
      children: <Widget>[
        if (!stacked)
          Text(
            l10n.kioskCounterThanks,
            style: theme.textTheme.titleLarge?.copyWith(color: on),
          ),
        Text(
          l10n.kioskCounterTitle,
          textAlign: stacked ? TextAlign.center : TextAlign.start,
          style: theme.textTheme.headlineLarge?.copyWith(color: on),
        ),
        const SizedBox(height: KioskScale.gap),
        Text(
          MoneyFormatter.formatXaf(placed.order.total),
          style: theme.textTheme.titleLarge?.copyWith(
            color: on.withValues(alpha: 0.85),
          ),
        ),
        const SizedBox(height: KioskScale.gapMd),
        _SlipStatus(printState: printState, onRetryPrint: onRetryPrint),
        const SizedBox(height: KioskScale.gapMd),
        OutlinedButton(
          onPressed: onDone,
          style: OutlinedButton.styleFrom(
            side: BorderSide(color: on, width: 2),
            foregroundColor: on,
          ),
          child: Text(l10n.kioskCounterNewOrder),
        ),
      ],
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
