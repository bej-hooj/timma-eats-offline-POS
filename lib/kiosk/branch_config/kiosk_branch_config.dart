import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pos_cloud/pos_cloud.dart';
import 'package:pos_core/pos_core.dart';

/// The branch's operational settings as the borne's screens read them
/// (ECOSYSTEM §25.4–§25.5): merchant codes, the KDS roster and the day menu.
///
/// A read-only view over [BranchConfigSync]'s cache. A borne with no cloud
/// credential reads [KioskBranchConfig.empty]: no merchant codes (the ticket
/// screen shows no section), no roster (every KDS stays the full board) and
/// no day restriction (every dish shows).
class KioskBranchConfig {
  const KioskBranchConfig._(this._sync);

  factory KioskBranchConfig.of(BranchConfigSync sync) =>
      KioskBranchConfig._(sync);

  static const KioskBranchConfig empty = KioskBranchConfig._(null);

  final BranchConfigSync? _sync;

  List<KioskPaymentCode> get paymentCodes =>
      _sync?.paymentCodes() ?? const <KioskPaymentCode>[];

  KioskDayMenu get dayMenu => _sync?.dayMenu() ?? KioskDayMenu.none;

  /// Null when the hub has never pulled a roster: the hub then sends none and
  /// every KDS keeps the full board.
  KitchenRoster? get roster => _sync?.roster();
}

final Provider<KioskBranchConfig> kioskBranchConfigProvider =
    Provider<KioskBranchConfig>((Ref ref) => KioskBranchConfig.empty);

/// Ticks when a pull changed the merchant codes or the day menu, so the
/// screens that show them rebuild without a restart — the same pattern as
/// `kioskMenuRevisionProvider`. The default never ticks.
final Provider<ValueListenable<int>> kioskConfigRevisionProvider =
    Provider<ValueListenable<int>>((Ref ref) {
      final ValueNotifier<int> never = ValueNotifier<int>(0);
      ref.onDispose(never.dispose);
      return never;
    });
