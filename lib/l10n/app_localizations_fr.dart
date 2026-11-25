// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class AppLocalizationsFr extends AppLocalizations {
  AppLocalizationsFr([String locale = 'fr']) : super(locale);

  @override
  String kioskCartRemoveLine(String dish) {
    return 'Retirer $dish';
  }

  @override
  String get kioskCounterCodeLabel => 'Code de votre commande';

  @override
  String get kioskCounterNoteCode => 'Notez ce code';

  @override
  String get kioskAttractTitle => 'Commandez ici';

  @override
  String get kioskAttractSubtitle => 'Touchez l\'écran pour commencer';

  @override
  String get kioskAttractStart => 'Commencer';

  @override
  String get kioskMenuTitle => 'Notre carte';

  @override
  String kioskDailyMenuTitle(String date) {
    return 'Menu du jour — $date';
  }

  @override
  String get kioskDrinksTitle => 'Boissons dispo';

  @override
  String get kioskSoldOut => 'Épuisé';

  @override
  String get kioskAdd => 'Ajouter';

  @override
  String get kioskBack => 'Retour';

  @override
  String get kioskCancel => 'Annuler';

  @override
  String get kioskQuantity => 'Quantité';

  @override
  String get kioskRemove => 'Retirer';

  @override
  String get kioskCartTitle => 'Votre commande';

  @override
  String get kioskCartEmpty => 'Votre commande est vide.';

  @override
  String get kioskCartTotal => 'Total';

  @override
  String get kioskCartConfirm => 'Commander';

  @override
  String get kioskCartKeepBrowsing => 'Continuer';

  @override
  String get kioskGroupOptional => 'Facultatif';

  @override
  String kioskGroupChooseExactly(int count) {
    return 'Choisissez $count';
  }

  @override
  String kioskGroupChooseUpTo(int count) {
    return 'Jusqu\'à $count au choix';
  }

  @override
  String kioskGroupChooseAtLeast(int count) {
    return 'Au moins $count';
  }

  @override
  String get kioskCounterTitle => 'Payez à la caisse';

  @override
  String get kioskCounterSubtitle => 'Présentez ce numéro';

  @override
  String get kioskCounterThanks => 'Merci !';

  @override
  String get kioskCounterNewOrder => 'Nouvelle commande';

  @override
  String get kioskOutOfServiceTitle => 'Borne indisponible';

  @override
  String get kioskOutOfServiceBody =>
      'Merci de commander directement à la caisse.';

  @override
  String get kioskUnavailableNow =>
      'Un plat de votre commande n\'est plus disponible. Merci de le retirer.';

  @override
  String get kioskTakeAway => 'À emporter';

  @override
  String get kioskCategoryAll => 'Tout';

  @override
  String get kioskSearchHint => 'Rechercher un plat';

  @override
  String get kioskSearchEmpty => 'Aucun plat ne correspond à votre recherche.';

  @override
  String get kioskSearchClear => 'Effacer';

  @override
  String get kioskSlipHeader => 'TIMMA EATS';

  @override
  String get kioskSetupTitle => 'Borne non configurée';

  @override
  String get kioskSetupBody =>
      'Cette tablette n\'est pas encore rattachée à un restaurant. Contactez le responsable pour la configurer.';

  @override
  String get kioskSecretLostTitle => 'Configuration à restaurer';

  @override
  String get kioskSecretLostBody =>
      'La clé de sécurité des tickets de cette borne est introuvable. Les tickets déjà imprimés ne peuvent plus être vérifiés. Contactez le responsable avant de reprendre les commandes.';

  @override
  String get kioskPrintPrinting => 'Impression du ticket…';

  @override
  String get kioskPrintFailed =>
      'Ticket non imprimé. Présentez ce numéro à la caisse.';

  @override
  String get kioskPrintRetry => 'Réimprimer';

  @override
  String get shiftCloseTitle => 'Clôture de service';

  @override
  String get shiftCloseTickets => 'Tickets';

  @override
  String get shiftCloseAcknowledged => 'Confirmés par le cloud';

  @override
  String get shiftCloseUnsent => 'Pas encore envoyés';

  @override
  String get shiftCloseCash => 'Espèces (à compter en caisse)';

  @override
  String get shiftCloseMomo => 'Mobile money au comptoir';

  @override
  String get shiftCloseUntendered => 'Payés, moyen non enregistré';

  @override
  String get shiftCloseStranded => 'Tickets bloqués';

  @override
  String get shiftCloseSettled => 'Tout est synchronisé.';

  @override
  String get shiftCloseForceDrain => 'Forcer la synchronisation';

  @override
  String shiftCloseTicketLine(String number, String reason) {
    return 'Ticket $number · $reason';
  }

  @override
  String get shiftCloseNoTicketNumber => 'sans numéro';

  @override
  String get kioskManagerTitle => 'Responsable';

  @override
  String get kioskManagerPairKitchen => 'Apparier une cuisine';

  @override
  String get kioskManagerHubOn => 'Borne visible sur le wifi';

  @override
  String get kioskManagerHubOff => 'Borne non démarrée';

  @override
  String kioskManagerBoards(int count) {
    return '$count cuisine(s) connectée(s)';
  }

  @override
  String get kioskManagerCodeTitle => 'Code d\'appairage';

  @override
  String get kioskManagerCodeHint =>
      'Saisissez ce code sur la tablette cuisine.';

  @override
  String kioskManagerCodeLeft(int seconds) {
    return 'Valable encore $seconds s';
  }

  @override
  String get kioskManagerCodeExpired => 'Code expiré. Recommencez.';

  @override
  String get kioskManagerNoSecret =>
      'Clé de sécurité manquante : impossible d\'apparier.';

  @override
  String get kioskManagerPairFailed => 'L\'appairage n\'a pas pu démarrer.';

  @override
  String get kioskManagerHubFailed =>
      'La borne n\'a pas pu démarrer sur le wifi.';

  @override
  String get kioskManagerPinTitle => 'Code responsable';

  @override
  String get kioskManagerPinWrong => 'Code incorrect.';

  @override
  String get kioskManagerPinOpen => 'Ouvrir';

  @override
  String get kioskManagerPinUnset =>
      'Aucun code responsable configuré sur cette borne.';

  @override
  String kioskSlipWithout(String ingredient) {
    return 'SANS $ingredient';
  }

  @override
  String kioskSlipGroupLabel(String group, String answer) {
    return '$group : $answer';
  }

  @override
  String get kioskSlipGroupNone => 'AUCUN';

  @override
  String kioskDishPrepWindow(int min, int max) {
    return '$min–$max min';
  }

  @override
  String kioskDishPrepWindowSemantics(int min, int max) {
    return 'Préparation : $min à $max minutes';
  }

  @override
  String kioskDishSpiceLevel(String level) {
    String _temp0 = intl.Intl.selectLogic(level, {
      '1': 'Peu épicé',
      '2': 'Épicé',
      '3': 'Très épicé',
      'other': 'Non épicé',
    });
    return '$_temp0';
  }

  @override
  String get kioskManagerApprovalTitle => 'Une cuisine demande à s\'apparier';

  @override
  String get kioskManagerApprovalCompare =>
      'Vérifiez que ce nombre est le même sur la tablette cuisine.';

  @override
  String get kioskManagerApprovalAccept => 'Accepter';

  @override
  String get kioskManagerApprovalRefuse => 'Refuser';

  @override
  String get kioskManagerPairOrCode =>
      'Ou saisissez ce code sur la tablette cuisine';

  @override
  String get kioskManagerPairWaiting => 'En attente d\'une cuisine';

  @override
  String get kioskManagerPairWaitingBody =>
      'Sur la tablette cuisine, touchez « Apparier en un geste ».';

  @override
  String get kioskManagerPairCodeFallback =>
      'Ou saisissez ce code sur la cuisine';

  @override
  String get kioskDishIngredients => 'INGRÉDIENTS';

  @override
  String get kioskDishAllergens => 'Contient';

  @override
  String kioskDishWithout(String name) {
    return 'Sans $name';
  }

  @override
  String get kioskDishRemovableHint => 'Touchez pour retirer';

  @override
  String get kioskWeekMenuTitle => 'Menu de la semaine';

  @override
  String get kioskWeekMenuIntro =>
      'Les plats et les jours où ils sont cuisinés.';

  @override
  String get kioskWeekMenuEveryDay => 'Tous les jours';

  @override
  String get kioskWeekMenuNotScheduled => 'Pas cette semaine';

  @override
  String get kioskWeekMenuToday => 'Aujourd\'hui';

  @override
  String get kioskWeekMenuClose => 'Fermer';

  @override
  String get kioskPayMobileTitle =>
      'Pas d\'espèces ? Payez par Mobile Money ou Orange Money';

  @override
  String get kioskPayMobileHint =>
      'Composez le code marchand, puis montrez la confirmation à la caisse avec votre ticket.';

  @override
  String get kioskPayMobileProviderMtn => 'MTN Mobile Money';

  @override
  String get kioskPayMobileProviderOrange => 'Orange Money';

  @override
  String kioskPayMobileCode(String code) {
    return 'Code marchand : $code';
  }

  @override
  String kioskPayMobileHolder(String name) {
    return 'Au nom de : $name';
  }

  @override
  String get kioskSlipMobileTitle => 'Pas d\'espèces ? Payez par :';
}
