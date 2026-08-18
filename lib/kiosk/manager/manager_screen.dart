import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pos_link/pos_link.dart';

import 'package:pos_core/pos_core.dart';

import 'package:timma_kiosk/l10n/app_localizations.dart';
import '../shift/shift_close.dart';
import '../shift/shift_close_screen.dart';
import '../state/kiosk_session.dart';
import '../theme/kiosk_scale.dart';
import 'hub_controller.dart';
import 'manager_gate.dart';

/// The manager's surface: the hub, pairing, and shift close.
///
/// Reached by a long press on the attract screen's mark — deliberately not a
/// visible button. The kiosk stands unattended in a public room, and a button
/// labelled *Responsable* is an invitation to press it.
class KioskManagerScreen extends ConsumerStatefulWidget {
  const KioskManagerScreen({super.key});

  @override
  ConsumerState<KioskManagerScreen> createState() => _KioskManagerScreenState();
}

class _KioskManagerScreenState extends ConsumerState<KioskManagerScreen> {
  @override
  void initState() {
    super.initState();
    // Starting the hub is what makes the kiosk findable at all. It is safe to
    // call repeatedly: the controller is idempotent.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(ref.read(hubProvider.notifier).start());
    });
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    final ThemeData theme = Theme.of(context);
    final HubState hub = ref.watch(hubProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.kioskManagerTitle),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(KioskScale.gapLg),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  if (KioskManagerGate.isUnset) ...<Widget>[
                    // Said out loud rather than assumed: a kiosk built without
                    // a manager code is one long press from its own till.
                    Card(
                      color: theme.colorScheme.error,
                      child: Padding(
                        padding: const EdgeInsets.all(KioskScale.gapMd),
                        child: Text(
                          l10n.kioskManagerPinUnset,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: theme.colorScheme.onError,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: KioskScale.gapLg),
                  ],
                  _HubCard(hub: hub),
                  const SizedBox(height: KioskScale.gapLg),
                  if (hub.code != null)
                    _PairingCodeCard(
                      code: hub.code!,
                      expiresAt: hub.codeExpiresAt,
                      onDone: ref.read(hubProvider.notifier).clearCode,
                    )
                  else
                    FilledButton.icon(
                      onPressed: ref.read(hubProvider.notifier).beginPairing,
                      icon: const Icon(Icons.tablet_android_outlined),
                      label: Text(l10n.kioskManagerPairKitchen),
                    ),
                  const SizedBox(height: KioskScale.gapLg),
                  OutlinedButton.icon(
                    // The shift-close screen has existed since K7 and nothing
                    // ever navigated to it — a manager could not close a till
                    // from the product at all. The report is built here, from
                    // the local store, because closing a shift must work on a
                    // day that was entirely offline.
                    onPressed: () {
                      final PosEngine engine = ref.read(kioskEngineProvider);
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (BuildContext context) => ShiftCloseScreen(
                            report: ShiftClose.build(
                              store: engine.store,
                              deviceId: engine.identity.deviceId,
                            ),
                            onForceDrain: () => unawaited(
                              ref.read(hubProvider.notifier).start(),
                            ),
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.point_of_sale_outlined),
                    label: Text(l10n.shiftCloseTitle),
                  ),
                  if (hub.error != null) ...<Widget>[
                    const SizedBox(height: KioskScale.gapLg),
                    Text(
                      _errorText(l10n, hub.error!),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _errorText(AppLocalizations l10n, String code) => switch (code) {
    HubErrorCode.noSecret => l10n.kioskManagerNoSecret,
    HubErrorCode.pairingFailed => l10n.kioskManagerPairFailed,
    _ => l10n.kioskManagerHubFailed,
  };
}

/// Is the hub up, and where is it? Both questions a manager asks when a board
/// says it cannot find the kiosk.
class _HubCard extends StatelessWidget {
  const _HubCard({required this.hub});

  final HubState hub;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    final ThemeData theme = Theme.of(context);
    final HubEndpoint? endpoint = hub.endpoint;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(KioskScale.gapMd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  hub.running ? Icons.wifi_tethering : Icons.wifi_tethering_off,
                  color: hub.running
                      ? theme.colorScheme.primary
                      : theme.colorScheme.error,
                ),
                const SizedBox(width: KioskScale.gap),
                Text(
                  hub.running
                      ? l10n.kioskManagerHubOn
                      : l10n.kioskManagerHubOff,
                  style: theme.textTheme.titleLarge,
                ),
              ],
            ),
            if (endpoint != null) ...<Widget>[
              const SizedBox(height: KioskScale.gap),
              // Shown because a restaurant router that blocks multicast makes
              // typing this the only way a board can join.
              SelectableText(
                '${endpoint.host}:${endpoint.port}',
                style: theme.textTheme.bodyLarge,
              ),
            ],
            const SizedBox(height: KioskScale.gap),
            Text(
              l10n.kioskManagerBoards(hub.pairedBoards),
              style: theme.textTheme.bodyLarge,
            ),
          ],
        ),
      ),
    );
  }
}

/// The six digits, large enough to read across a counter, with the countdown
/// that tells a manager whether to hurry or start again.
class _PairingCodeCard extends StatefulWidget {
  const _PairingCodeCard({
    required this.code,
    required this.expiresAt,
    required this.onDone,
  });

  final String code;
  final DateTime? expiresAt;
  final VoidCallback onDone;

  @override
  State<_PairingCodeCard> createState() => _PairingCodeCardState();
}

class _PairingCodeCardState extends State<_PairingCodeCard> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    final ThemeData theme = Theme.of(context);
    final Duration left = widget.expiresAt == null
        ? Duration.zero
        : widget.expiresAt!.difference(DateTime.now().toUtc());
    final bool expired = left.isNegative || left == Duration.zero;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(KioskScale.gapLg),
        child: Column(
          children: <Widget>[
            Text(l10n.kioskManagerCodeTitle, style: theme.textTheme.titleLarge),
            const SizedBox(height: KioskScale.gapMd),
            Text(
              // Spaced so it can be read out loud without losing a digit.
              widget.code.split('').join(' '),
              style: TextStyle(
                fontSize: KioskScale.headlineSize * 1.6,
                fontWeight: FontWeight.w800,
                letterSpacing: 2,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: KioskScale.gap),
            Text(
              expired
                  ? l10n.kioskManagerCodeExpired
                  : l10n.kioskManagerCodeLeft(left.inSeconds),
              style: theme.textTheme.bodyLarge?.copyWith(
                color: expired ? theme.colorScheme.error : null,
              ),
            ),
            const SizedBox(height: KioskScale.gapMd),
            Text(
              l10n.kioskManagerCodeHint,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: KioskScale.gapMd),
            OutlinedButton(
              onPressed: widget.onDone,
              child: Text(l10n.kioskCancel),
            ),
          ],
        ),
      ),
    );
  }
}
