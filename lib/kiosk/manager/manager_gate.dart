import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:timma_kiosk/l10n/app_localizations.dart';
import '../theme/kiosk_scale.dart';

/// The PIN between a long press and the manager's screen.
///
/// **Why a PIN at all.** The manager surface can close a shift and pair a new
/// kitchen tablet, and the way in is a long press on an unattended screen in a
/// public room. A customer resting a finger on the logo must not land in it.
/// The long press hides the door; the PIN locks it.
///
/// **What this is not.** It is not a cryptographic boundary — it protects
/// against a passer-by, not against someone who has taken the tablet away. The
/// things that actually matter are protected elsewhere: prices come from the
/// server, the collection secret lives in the keystore, and pairing still needs
/// a code read off this screen.
abstract final class KioskManagerGate {
  /// Configured per branch at build time, never a literal in source (§5).
  static const String pin = String.fromEnvironment('KIOSK_MANAGER_PIN');

  /// True when this build was given no PIN. The screen then says so out loud
  /// rather than pretending to be protected.
  static bool get isUnset => pin.isEmpty;

  /// Shows the keypad and resolves true when the PIN matches.
  static Future<bool> unlock(BuildContext context) async {
    if (isUnset) {
      return true;
    }
    final bool? ok = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) => const _PinDialog(),
    );
    return ok ?? false;
  }
}

class _PinDialog extends StatefulWidget {
  const _PinDialog();

  @override
  State<_PinDialog> createState() => _PinDialogState();
}

class _PinDialogState extends State<_PinDialog> {
  final TextEditingController _entry = TextEditingController();
  bool _wrong = false;

  @override
  void dispose() {
    _entry.dispose();
    super.dispose();
  }

  void _submit() {
    // Constant-time-ish comparison is pointless here — the attacker is standing
    // at the counter, not measuring microseconds — but a wrong entry must not
    // say WHICH digit was wrong, and it must not count down out loud either.
    if (_entry.text == KioskManagerGate.pin) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _wrong = true;
      _entry.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    final ThemeData theme = Theme.of(context);

    return AlertDialog(
      // ⚠ Scrollable, and the title is compact. In landscape on a phone-sized
      // kiosk the software keyboard takes half the screen: the first version of
      // this dialog overflowed by 88 px and hid its own PIN field, which is as
      // good as no way in at all.
      scrollable: true,
      insetPadding: const EdgeInsets.symmetric(
        horizontal: KioskScale.gapXl,
        vertical: KioskScale.gap,
      ),
      titlePadding: const EdgeInsets.fromLTRB(
        KioskScale.gapMd,
        KioskScale.gapMd,
        KioskScale.gapMd,
        KioskScale.gap,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: KioskScale.gapMd),
      title: Text(l10n.kioskManagerPinTitle, style: theme.textTheme.titleLarge),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          TextField(
            controller: _entry,
            autofocus: true,
            obscureText: true,
            keyboardType: TextInputType.number,
            inputFormatters: <TextInputFormatter>[
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(8),
            ],
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: KioskScale.bodySize,
              letterSpacing: 6,
            ),
            decoration: const InputDecoration(counterText: ''),
            onSubmitted: (_) => _submit(),
          ),
          if (_wrong) ...<Widget>[
            const SizedBox(height: KioskScale.gap),
            Text(
              l10n.kioskManagerPinWrong,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.kioskCancel),
        ),
        FilledButton(onPressed: _submit, child: Text(l10n.kioskManagerPinOpen)),
      ],
    );
  }
}
