// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get kioskAttractTitle => 'Order here';

  @override
  String get kioskAttractSubtitle => 'Touch the screen to start';

  @override
  String get kioskAttractStart => 'Start';

  @override
  String get kioskMenuTitle => 'Our menu';

  @override
  String get kioskSoldOut => 'Sold out';

  @override
  String get kioskAdd => 'Add';

  @override
  String get kioskBack => 'Back';

  @override
  String get kioskCancel => 'Cancel';

  @override
  String get kioskQuantity => 'Quantity';

  @override
  String get kioskRemove => 'Remove';

  @override
  String get kioskCartTitle => 'Your order';

  @override
  String get kioskCartEmpty => 'Your order is empty.';

  @override
  String get kioskCartTotal => 'Total';

  @override
  String get kioskCartConfirm => 'Place order';

  @override
  String get kioskCartKeepBrowsing => 'Keep browsing';

  @override
  String get kioskGroupOptional => 'Optional';

  @override
  String kioskGroupChooseExactly(int count) {
    return 'Choose $count';
  }

  @override
  String kioskGroupChooseUpTo(int count) {
    return 'Choose up to $count';
  }

  @override
  String kioskGroupChooseAtLeast(int count) {
    return 'Choose at least $count';
  }

  @override
  String get kioskCounterTitle => 'Pay at the counter';

  @override
  String get kioskCounterSubtitle => 'Show this number';

  @override
  String get kioskCounterThanks => 'Thank you!';

  @override
  String get kioskCounterNewOrder => 'New order';

  @override
  String get kioskOutOfServiceTitle => 'Kiosk unavailable';

  @override
  String get kioskOutOfServiceBody => 'Please order at the counter.';

  @override
  String get kioskUnavailableNow =>
      'A dish in your order is no longer available. Please remove it.';

  @override
  String get kioskTakeAway => 'Take away';

  @override
  String get kioskCategoryAll => 'All';

  @override
  String get kioskSearchHint => 'Search for a dish';

  @override
  String get kioskSearchEmpty => 'No dish matches your search.';

  @override
  String get kioskSearchClear => 'Clear';

  @override
  String get kioskSlipHeader => 'TIMMA EATS';

  @override
  String get kioskSetupTitle => 'Kiosk not set up';

  @override
  String get kioskSetupBody =>
      'This tablet is not attached to a restaurant yet. Ask the manager to set it up.';

  @override
  String get kioskSecretLostTitle => 'Setup needs restoring';

  @override
  String get kioskSecretLostBody =>
      'This kiosk\'s slip security key is missing. Slips already printed can no longer be verified. Ask the manager before taking more orders.';

  @override
  String get kioskPrintPrinting => 'Printing your slip…';

  @override
  String get kioskPrintFailed =>
      'Slip not printed. Show this number at the counter.';

  @override
  String get kioskPrintRetry => 'Print again';

  @override
  String get shiftCloseTitle => 'Shift close';

  @override
  String get shiftCloseTickets => 'Tickets';

  @override
  String get shiftCloseAcknowledged => 'Confirmed by the cloud';

  @override
  String get shiftCloseUnsent => 'Not sent yet';

  @override
  String get shiftCloseCash => 'Cash (count against the drawer)';

  @override
  String get shiftCloseMomo => 'Mobile money at the counter';

  @override
  String get shiftCloseUntendered => 'Paid, method not recorded';

  @override
  String get shiftCloseStranded => 'Stuck tickets';

  @override
  String get shiftCloseSettled => 'Everything is synced.';

  @override
  String get shiftCloseForceDrain => 'Force sync';

  @override
  String shiftCloseTicketLine(String number, String reason) {
    return 'Ticket $number · $reason';
  }

  @override
  String get shiftCloseNoTicketNumber => 'no number';
}
