import 'package:intl/intl.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// The ONE time utility (ECOSYSTEM §15.2): storage UTC, display Africa/Douala,
/// all day-boundary and slot math goes through here.
abstract final class TimeUtil {
  static const String displayZone = 'Africa/Douala';
  static bool _initialized = false;

  /// Call once at app start (and in test setUp).
  static void init() {
    if (_initialized) return;
    tz_data.initializeTimeZones();
    _initialized = true;
  }

  static tz.Location get _douala => tz.getLocation(displayZone);

  static tz.TZDateTime toDouala(DateTime utc) =>
      tz.TZDateTime.from(utc.toUtc(), _douala);

  static tz.TZDateTime nowInDouala() => tz.TZDateTime.now(_douala);

  /// Start of the Douala calendar day containing [utc] — the boundary used for
  /// daily codes and slots (ECOSYSTEM §6.4, §10).
  static tz.TZDateTime doualaDayStart(DateTime utc) {
    final tz.TZDateTime local = toDouala(utc);
    return tz.TZDateTime(_douala, local.year, local.month, local.day);
  }

  static String formatTime(DateTime utc, {String? locale}) =>
      DateFormat.Hm(locale).format(toDouala(utc));

  static String formatDate(DateTime utc, {String? locale}) =>
      DateFormat.yMMMMd(locale).format(toDouala(utc));

  static const List<String> _dayKeys = [
    'mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun', // DateTime.weekday 1…7
  ];

  static const int slotMinutes = 30;

  /// Selectable slot starts (UTC) for today + tomorrow in Douala, generated
  /// from the §8.1 `hours` shape minus the prep lead — the client-side twin
  /// of migration 17's server validation. Unset hours yield no slots
  /// (fail-closed, matching `branch_closed`).
  static List<DateTime> scheduleSlots({
    required Map<String, Object?> hours,
    required int leadMinutes,
    DateTime? nowUtc,
  }) {
    final tz.TZDateTime now = toDouala(nowUtc ?? DateTime.now().toUtc());
    final List<DateTime> slots = [];

    for (var dayOffset = 0; dayOffset < 2; dayOffset++) {
      final tz.TZDateTime day = tz.TZDateTime(
        _douala,
        now.year,
        now.month,
        now.day + dayOffset,
      );
      final Object? intervals = hours[_dayKeys[day.weekday - 1]];
      if (intervals is! List) {
        continue;
      }
      for (final interval in intervals) {
        if (interval is! Map) {
          continue;
        }
        final tz.TZDateTime? open = _atWallTime(day, interval['open']);
        final tz.TZDateTime? close = _atWallTime(day, interval['close']);
        if (open == null || close == null) {
          continue;
        }
        // Start on the 30-minute grid, not on `open`. The RPC demands
        // minute ∈ {0,30} (`bad_slot`) AND >= open (`branch_closed`), so an
        // ops-entered open of "10:15" makes 10:30 the first legal slot —
        // walking from 10:15 offered 10:15, 10:45, … every one of which the
        // server refuses. Found while writing the web twin's tests
        // (timmaeat-webapp/docs/checkout-slot-and-table-2026-07-31.md).
        for (
          tz.TZDateTime slot = _snapUpToGrid(open);
          slot.isBefore(close);
          slot = slot.add(const Duration(minutes: slotMinutes))
        ) {
          if (slot.subtract(Duration(minutes: leadMinutes)).isAfter(now)) {
            slots.add(slot.toUtc());
          }
        }
      }
    }
    return slots..sort();
  }

  /// The first :00/:30 at or after [at], seconds and sub-seconds dropped.
  ///
  /// Not cosmetic: `rpc_place_order` raises `bad_slot` for any other minute,
  /// so this is the difference between a pickable time and a rejected order.
  static tz.TZDateTime _snapUpToGrid(tz.TZDateTime at) {
    if (at.minute % slotMinutes == 0 &&
        at.second == 0 &&
        at.millisecond == 0 &&
        at.microsecond == 0) {
      return at;
    }
    return tz.TZDateTime(
      _douala,
      at.year,
      at.month,
      at.day,
      at.hour,
      (at.minute ~/ slotMinutes) * slotMinutes + slotMinutes,
    );
  }

  static tz.TZDateTime? _atWallTime(tz.TZDateTime day, Object? hhmm) {
    if (hhmm is! String) {
      return null;
    }
    final parts = hhmm.split(':');
    final int? hour = parts.length == 2 ? int.tryParse(parts[0]) : null;
    final int? minute = parts.length == 2 ? int.tryParse(parts[1]) : null;
    if (hour == null || minute == null) {
      return null;
    }
    return tz.TZDateTime(_douala, day.year, day.month, day.day, hour, minute);
  }
}
