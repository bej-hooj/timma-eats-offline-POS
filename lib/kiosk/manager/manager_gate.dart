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
      builder: (BuildContext context) => const KioskManagerPinDialog(),
    );
    return ok ?? false;
  }
}

/// The keypad itself, **public on purpose**.
///
/// [KioskManagerGate.unlock] returns immediately when a build carries no
/// `KIOSK_MANAGER_PIN`, which is every test build — so a test that went through
/// the gate never saw a dialog at all, and the geometry of the one door into
/// the manager screen could only be checked by looking at a tablet. It has
/// overflowed twice for exactly that reason.
class KioskManagerPinDialog extends StatefulWidget {
  const KioskManagerPinDialog({super.key});

  @override
  State<KioskManagerPinDialog> createState() => _KioskManagerPinDialogState();
}

class _KioskManagerPinDialogState extends State<KioskManagerPinDialog> {
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

    return Dialog(
      // ⚠ **Not `AlertDialog`, and not `scrollable: true`.** That combination
      // scrolls the title and content but lays the actions out *below* the
      // scroll view, so on a short landscape screen with the keyboard up the
      // buttons still had nowhere to go: the dialog overflowed by 77 px and
      // drew *Annuler* and *Ouvrir* on top of the PIN field — a door with the
      // handle painted over the keyhole. Scrolling the WHOLE dialog, actions
      // included, is what makes it fit at any height.
      insetPadding: const EdgeInsets.symmetric(
        horizontal: KioskScale.gapXl,
        vertical: KioskScale.gap,
      ),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          // ⚠ **Scrolling is the floor, not the answer.** With the keypad up
          // this dialog has about 169 dp on a 448 dp landscape screen, and the
          // full-size version needs 230 — so it fitted, legally, with *Annuler*
          // and *Ouvrir* below the fold. A manager who has to scroll a PIN
          // dialog to find its own OK button has been given a puzzle, not a
          // door. When the room is short the title goes (the field is
          // autofocused and the screen behind it is unambiguous) and the
          // buttons come down to 56 dp — still above the Material floor, and
          // this is a manager with a keyboard open, not a cook with wet hands
          // reaching for a ticket.
          final bool short = constraints.maxHeight < 240;
          final double gap = short ? KioskScale.gap : KioskScale.gapMd;
          final ButtonStyle compact = short
              ? const ButtonStyle(
                  minimumSize: WidgetStatePropertyAll<Size>(Size(0, 56)),
                )
              : const ButtonStyle();
          return SingleChildScrollView(
            padding: EdgeInsets.all(gap),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                if (!short) ...<Widget>[
                  Text(
                    l10n.kioskManagerPinTitle,
                    style: theme.textTheme.titleLarge,
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: gap),
                ],
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
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ],
                SizedBox(height: gap),
                Row(
                  children: <Widget>[
                    // Expanded on both, because the kiosk theme gives buttons an
                    // infinite `minimumSize` width — right for a full-width card
                    // action, an unbounded-width crash inside a Row.
                    Expanded(
                      child: TextButton(
                        style: compact,
                        onPressed: () => Navigator.of(context).pop(false),
                        child: Text(l10n.kioskCancel),
                      ),
                    ),
                    const SizedBox(width: KioskScale.gap),
                    Expanded(
                      child: FilledButton(
                        style: compact,
                        onPressed: _submit,
                        child: Text(l10n.kioskManagerPinOpen),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
