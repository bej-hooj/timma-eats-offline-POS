import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'package:timma_kiosk/l10n/app_localizations.dart';
import '../state/kiosk_session.dart';
import '../theme/kiosk_scale.dart';
import '../theme/kiosk_theme.dart';

/// Why the kiosk cannot open for business.
enum KioskBootstrapState {
  /// No device identity in the store — a tablet out of the box, or one whose
  /// app data was cleared. It has no branch, so it has no prices and no ticket
  /// sequence, and there is nothing safe to guess.
  unprovisioned,

  /// This hub's branch collection secret is gone from the keystore although the
  /// store says it once had one. Slips already printed cannot be verified, so
  /// trading on would hand out tickets the kitchen must refuse.
  secretLost,
}

/// The smallest possible app: one screen that explains itself to the member of
/// staff standing in front of it.
///
/// It is a whole `MaterialApp` because it runs *instead of* [KioskApp] — before
/// any provider scope exists — and it still has to be localised and legible
/// from across a room. A blank screen or a red crash box here is a tablet
/// nobody can diagnose without a laptop.
class KioskBootstrapApp extends StatelessWidget {
  const KioskBootstrapApp({required this.state, super.key});

  final KioskBootstrapState state;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      // French, the product's default locale — not whatever the tablet was set
      // to in a warehouse.
      locale: KioskLocaleController.defaultLocale,
      debugShowCheckedModeBanner: false,
      theme: KioskTheme.build(),
      localizationsDelegates: const <LocalizationsDelegate<Object>>[
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: KioskBootstrapScreen(state: state),
    );
  }
}

class KioskBootstrapScreen extends StatelessWidget {
  const KioskBootstrapScreen({required this.state, super.key});

  final KioskBootstrapState state;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    final ThemeData theme = Theme.of(context);
    final (String title, String body) = switch (state) {
      KioskBootstrapState.unprovisioned => (
        l10n.kioskSetupTitle,
        l10n.kioskSetupBody,
      ),
      KioskBootstrapState.secretLost => (
        l10n.kioskSecretLostTitle,
        l10n.kioskSecretLostBody,
      ),
    };

    return Scaffold(
      body: SafeArea(
        // Scrollable and width-capped: the `secretLost` body is a long French
        // sentence, and the KDS's equivalent screen provably overflowed at
        // 1280×800 before the same treatment. The layout gives way, never the
        // text — a truncated explanation on an unattended tablet is a support
        // call.
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(KioskScale.gapXl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Icon(
                    state == KioskBootstrapState.unprovisioned
                        ? Icons.settings_outlined
                        : Icons.lock_outline,
                    size: 120,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(height: KioskScale.gapXl),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineLarge,
                  ),
                  const SizedBox(height: KioskScale.gapMd),
                  Text(
                    body,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
