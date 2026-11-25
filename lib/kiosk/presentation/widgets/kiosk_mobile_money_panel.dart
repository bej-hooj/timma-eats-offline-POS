import 'package:flutter/material.dart';
import 'package:pos_cloud/pos_cloud.dart';

import '../../../l10n/app_localizations.dart';
import '../../theme/kiosk_scale.dart';

/// ECOSYSTEM §25.4 — "no cash? pay with mobile money", under the ticket code.
///
/// Drawn only when the dashboard defined at least one active merchant code;
/// with none, the caller does not build this at all — a heading over nothing
/// would send a customer looking for a code that does not exist.
///
/// The customer pays from their own phone and shows the confirmation at the
/// counter; the cashier then settles the ticket with tender *Mobile Money*.
/// Nothing here touches money: it is information, read from the dashboard.
class KioskMobileMoneyPanel extends StatelessWidget {
  const KioskMobileMoneyPanel({
    super.key,
    required this.codes,
    required this.foreground,
    this.crossAxisAlignment = CrossAxisAlignment.center,
  });

  final List<KioskPaymentCode> codes;

  /// The colour the panel's text uses — it sits on the brand-green screen.
  final Color foreground;
  final CrossAxisAlignment crossAxisAlignment;

  static String providerName(AppLocalizations l10n, String provider) =>
      switch (provider) {
        KioskPaymentProvider.mtnMomo => l10n.kioskPayMobileProviderMtn,
        KioskPaymentProvider.orangeMoney => l10n.kioskPayMobileProviderOrange,
        _ => provider,
      };

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    final TextTheme text = Theme.of(context).textTheme;
    final TextAlign align = crossAxisAlignment == CrossAxisAlignment.center
        ? TextAlign.center
        : TextAlign.start;
    return Container(
      key: const ValueKey<String>('kiosk-mobile-money'),
      padding: const EdgeInsets.all(KioskScale.gapMd),
      decoration: BoxDecoration(
        border: Border.all(color: foreground.withValues(alpha: 0.6), width: 2),
        borderRadius: BorderRadius.circular(KioskScale.radius),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: crossAxisAlignment,
        children: <Widget>[
          Text(
            l10n.kioskPayMobileTitle,
            textAlign: align,
            style: text.titleMedium?.copyWith(
              color: foreground,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: KioskScale.gap),
          for (final KioskPaymentCode code in codes) ...<Widget>[
            Text(
              '${providerName(l10n, code.provider)} — '
              '${l10n.kioskPayMobileCode(code.code)}',
              textAlign: align,
              style: text.titleLarge?.copyWith(color: foreground),
            ),
            if (code.holderName case final String name)
              Text(
                l10n.kioskPayMobileHolder(name),
                textAlign: align,
                style: text.bodyLarge?.copyWith(
                  color: foreground.withValues(alpha: 0.85),
                ),
              ),
            const SizedBox(height: KioskScale.gap),
          ],
          Text(
            l10n.kioskPayMobileHint,
            textAlign: align,
            style: text.bodyMedium?.copyWith(
              color: foreground.withValues(alpha: 0.85),
            ),
          ),
        ],
      ),
    );
  }
}
