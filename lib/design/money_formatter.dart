/// The ONE money formatter (ECOSYSTEM §15.1). Money is integer XAF everywhere;
/// floats for currency are a review-blocking bug.
abstract final class MoneyFormatter {
  /// Non-breaking space — keeps '12 500 FCFA' on one line.
  static const String nbsp = '\u00A0';
  static const String _currency = 'FCFA';

  /// 12500 -> '12 500 FCFA' (non-breaking spaces).
  static String formatXaf(int amount) {
    final bool negative = amount < 0;
    final String digits = amount.abs().toString();
    final StringBuffer grouped = StringBuffer();
    for (int i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) {
        grouped.write(nbsp);
      }
      grouped.write(digits[i]);
    }
    return '${negative ? '-' : ''}$grouped$nbsp$_currency';
  }
}
