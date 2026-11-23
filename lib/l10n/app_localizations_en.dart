// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String kioskCartRemoveLine(String dish) {
    return 'Remove $dish';
  }

  @override
  String get kioskCounterCodeLabel => 'Your order code';

  @override
  String get kioskCounterNoteCode => 'Write this code down';

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

  @override
  String get kioskManagerTitle => 'Manager';

  @override
  String get kioskManagerPairKitchen => 'Pair a kitchen';

  @override
  String get kioskManagerHubOn => 'Kiosk visible on the wifi';

  @override
  String get kioskManagerHubOff => 'Kiosk not started';

  @override
  String kioskManagerBoards(int count) {
    return '$count kitchen(s) connected';
  }

  @override
  String get kioskManagerCodeTitle => 'Pairing code';

  @override
  String get kioskManagerCodeHint => 'Type this code on the kitchen tablet.';

  @override
  String kioskManagerCodeLeft(int seconds) {
    return 'Valid for $seconds s';
  }

  @override
  String get kioskManagerCodeExpired => 'Code expired. Start again.';

  @override
  String get kioskManagerNoSecret =>
      'Security key missing: pairing is not possible.';

  @override
  String get kioskManagerPairFailed => 'Pairing could not start.';

  @override
  String get kioskManagerHubFailed => 'The kiosk could not start on the wifi.';

  @override
  String get kioskManagerPinTitle => 'Manager code';

  @override
  String get kioskManagerPinWrong => 'Wrong code.';

  @override
  String get kioskManagerPinOpen => 'Open';

  @override
  String get kioskManagerPinUnset =>
      'No manager code is configured on this kiosk.';

  @override
  String kioskSlipWithout(String ingredient) {
    return 'NO $ingredient';
  }

  @override
  String kioskSlipGroupLabel(String group, String answer) {
    return '$group: $answer';
  }

  @override
  String get kioskSlipGroupNone => 'NONE';

  @override
  String kioskDishPrepWindow(int min, int max) {
    return '$min–$max min';
  }

  @override
  String kioskDishPrepWindowSemantics(int min, int max) {
    return 'Preparation: $min to $max minutes';
  }

  @override
  String kioskDishSpiceLevel(String level) {
    String _temp0 = intl.Intl.selectLogic(level, {
      '1': 'Mildly spicy',
      '2': 'Spicy',
      '3': 'Very spicy',
      'other': 'Not spicy',
    });
    return '$_temp0';
  }

  @override
  String get kioskManagerApprovalTitle => 'A kitchen is asking to pair';

  @override
  String get kioskManagerApprovalCompare =>
      'Check this number is the same on the kitchen tablet.';

  @override
  String get kioskManagerApprovalAccept => 'Accept';

  @override
  String get kioskManagerApprovalRefuse => 'Refuse';

  @override
  String get kioskManagerPairOrCode =>
      'Or type this code on the kitchen tablet';

  @override
  String get kioskManagerPairWaiting => 'Waiting for a kitchen';

  @override
  String get kioskManagerPairWaitingBody =>
      'On the kitchen tablet, tap “Pair with one tap”.';

  @override
  String get kioskManagerPairCodeFallback => 'Or type this code on the kitchen';

  @override
  String get kioskDishIngredients => 'INGREDIENTS';

  @override
  String get kioskDishAllergens => 'Contains';

  @override
  String kioskDishWithout(String name) {
    return 'No $name';
  }

  @override
  String get kioskDishRemovableHint => 'Tap to leave out';
}
