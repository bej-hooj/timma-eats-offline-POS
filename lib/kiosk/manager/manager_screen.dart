import 'dart:async';

import 'package:flutter/material.dart';

import 'package:timma_kiosk/design/app_tokens.dart';
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
                  // ⚠ Requests first. When a cuisine is waiting, the decision
                  // is the only thing on this screen that matters, and a
                  // manager hunting for it under a code they no longer need to
                  // read is how a cook ends up typing six digits anyway.
                  for (final PendingApproval approval in hub.approvals)
                    Padding(
                      padding: const EdgeInsets.only(
                        bottom: KioskScale.gapLg,
                      ),
                      child: _ApprovalCard(
                        approval: approval,
                        onAccept: () => ref
                            .read(hubProvider.notifier)
                            .approve(approval.id),
                        onRefuse: () =>
                            ref.read(hubProvider.notifier).refuse(approval.id),
                      ),
                    ),
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
            // ⚠⚠ The window LEADS with the tap, not the code.
            //
            // Owner, looking at this very screen: *"why i still see the
            // pairing code procedure as the main one?"* — because it was still
            // the headline here, in 96 pt, with the tap path nowhere on the
            // borne at all until a request arrived. The code is the second
            // procedure now, so it reads as one: small, below, after the
            // instruction that actually applies.
            Text(
              l10n.kioskManagerPairWaiting,
              style: theme.textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: KioskScale.gap),
            Text(
              l10n.kioskManagerPairWaitingBody,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: KioskScale.gapLg),
            const Divider(),
            const SizedBox(height: KioskScale.gapMd),
            Text(
              l10n.kioskManagerPairCodeFallback,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppColors.textMuted,
              ),
            ),
            const SizedBox(height: KioskScale.gap),
            Text(
              // Spaced so it can be read out loud without losing a digit.
              widget.code.split('').join(' '),
              style: TextStyle(
                // Half the size it was: still readable across a counter,
                // no longer the thing the eye lands on first.
                fontSize: KioskScale.headlineSize * 0.8,
                fontWeight: FontWeight.w700,
                letterSpacing: 2,
                color: expired
                    ? theme.colorScheme.error
                    : AppColors.textMuted,
              ),
            ),
            const SizedBox(height: KioskScale.gap),
            Text(
              expired
                  ? l10n.kioskManagerCodeExpired
                  : l10n.kioskManagerCodeLeft(left.inSeconds),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: expired
                    ? theme.colorScheme.error
                    : AppColors.textMuted,
              ),
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


/// A cuisine waiting to be let in, and the number that says it is the right
/// one.
///
/// ⚠⚠ **The six digits are not decoration.** With no code typed, the key
/// agreement is authenticated by a human confirming that the same number
/// appears on both screens. A man in the middle has to run two key agreements,
/// so his numbers differ — but only if somebody actually looks. The screen
/// therefore leads with the number and says what to do with it, rather than
/// putting a green button where a thumb already is.
class _ApprovalCard extends StatelessWidget {
  const _ApprovalCard({
    required this.approval,
    required this.onAccept,
    required this.onRefuse,
  });

  final PendingApproval approval;
  final VoidCallback onAccept;
  final VoidCallback onRefuse;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    final ThemeData theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(KioskScale.gapLg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              l10n.kioskManagerApprovalTitle,
              style: theme.textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: KioskScale.gap),
            Text(
              approval.label,
              style: theme.textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: KioskScale.gapMd),
            Text(
              // Spaced in pairs: six digits read as one number are compared
              // digit by digit and misread; "47 82 15" is three glances.
              _spaced(approval.comparisonDigits),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: KioskScale.headlineSize,
                fontWeight: FontWeight.w800,
                letterSpacing: 6,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: KioskScale.gap),
            Text(
              l10n.kioskManagerApprovalCompare,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: KioskScale.gapLg),
            Row(
              children: <Widget>[
                Expanded(
                  child: SizedBox(
                    height: KioskScale.minTarget,
                    child: OutlinedButton(
                      onPressed: onRefuse,
                      child: Text(l10n.kioskManagerApprovalRefuse),
                    ),
                  ),
                ),
                const SizedBox(width: KioskScale.gapMd),
                Expanded(
                  child: SizedBox(
                    height: KioskScale.minTarget,
                    child: FilledButton(
                      onPressed: onAccept,
                      child: Text(l10n.kioskManagerApprovalAccept),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _spaced(String digits) {
    final StringBuffer out = StringBuffer();
    for (int i = 0; i < digits.length; i++) {
      if (i > 0 && i % 2 == 0) {
        out.write('\u2009');
      }
      out.write(digits[i]);
    }
    return out.toString();
  }
}
