import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_fr.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('fr'),
  ];

  /// Screen-reader label for the remove key on a basket row.
  ///
  /// In fr, this message translates to:
  /// **'Retirer {dish}'**
  String kioskCartRemoveLine(String dish);

  /// Above the four-character code on the confirmation screen.
  ///
  /// In fr, this message translates to:
  /// **'Code de votre commande'**
  String get kioskCounterCodeLabel;

  /// Tells the customer to note the code before leaving the borne.
  ///
  /// In fr, this message translates to:
  /// **'Notez ce code'**
  String get kioskCounterNoteCode;

  /// No description provided for @kioskAttractTitle.
  ///
  /// In fr, this message translates to:
  /// **'Commandez ici'**
  String get kioskAttractTitle;

  /// No description provided for @kioskAttractSubtitle.
  ///
  /// In fr, this message translates to:
  /// **'Touchez l\'écran pour commencer'**
  String get kioskAttractSubtitle;

  /// No description provided for @kioskAttractStart.
  ///
  /// In fr, this message translates to:
  /// **'Commencer'**
  String get kioskAttractStart;

  /// No description provided for @kioskMenuTitle.
  ///
  /// In fr, this message translates to:
  /// **'Notre carte'**
  String get kioskMenuTitle;

  /// No description provided for @kioskSoldOut.
  ///
  /// In fr, this message translates to:
  /// **'Épuisé'**
  String get kioskSoldOut;

  /// No description provided for @kioskAdd.
  ///
  /// In fr, this message translates to:
  /// **'Ajouter'**
  String get kioskAdd;

  /// No description provided for @kioskBack.
  ///
  /// In fr, this message translates to:
  /// **'Retour'**
  String get kioskBack;

  /// No description provided for @kioskCancel.
  ///
  /// In fr, this message translates to:
  /// **'Annuler'**
  String get kioskCancel;

  /// No description provided for @kioskQuantity.
  ///
  /// In fr, this message translates to:
  /// **'Quantité'**
  String get kioskQuantity;

  /// No description provided for @kioskRemove.
  ///
  /// In fr, this message translates to:
  /// **'Retirer'**
  String get kioskRemove;

  /// No description provided for @kioskCartTitle.
  ///
  /// In fr, this message translates to:
  /// **'Votre commande'**
  String get kioskCartTitle;

  /// No description provided for @kioskCartEmpty.
  ///
  /// In fr, this message translates to:
  /// **'Votre commande est vide.'**
  String get kioskCartEmpty;

  /// No description provided for @kioskCartTotal.
  ///
  /// In fr, this message translates to:
  /// **'Total'**
  String get kioskCartTotal;

  /// No description provided for @kioskCartConfirm.
  ///
  /// In fr, this message translates to:
  /// **'Commander'**
  String get kioskCartConfirm;

  /// No description provided for @kioskCartKeepBrowsing.
  ///
  /// In fr, this message translates to:
  /// **'Continuer'**
  String get kioskCartKeepBrowsing;

  /// No description provided for @kioskGroupOptional.
  ///
  /// In fr, this message translates to:
  /// **'Facultatif'**
  String get kioskGroupOptional;

  /// No description provided for @kioskGroupChooseExactly.
  ///
  /// In fr, this message translates to:
  /// **'Choisissez {count}'**
  String kioskGroupChooseExactly(int count);

  /// No description provided for @kioskGroupChooseUpTo.
  ///
  /// In fr, this message translates to:
  /// **'Jusqu\'à {count} au choix'**
  String kioskGroupChooseUpTo(int count);

  /// No description provided for @kioskGroupChooseAtLeast.
  ///
  /// In fr, this message translates to:
  /// **'Au moins {count}'**
  String kioskGroupChooseAtLeast(int count);

  /// No description provided for @kioskCounterTitle.
  ///
  /// In fr, this message translates to:
  /// **'Payez à la caisse'**
  String get kioskCounterTitle;

  /// No description provided for @kioskCounterSubtitle.
  ///
  /// In fr, this message translates to:
  /// **'Présentez ce numéro'**
  String get kioskCounterSubtitle;

  /// No description provided for @kioskCounterThanks.
  ///
  /// In fr, this message translates to:
  /// **'Merci !'**
  String get kioskCounterThanks;

  /// No description provided for @kioskCounterNewOrder.
  ///
  /// In fr, this message translates to:
  /// **'Nouvelle commande'**
  String get kioskCounterNewOrder;

  /// No description provided for @kioskOutOfServiceTitle.
  ///
  /// In fr, this message translates to:
  /// **'Borne indisponible'**
  String get kioskOutOfServiceTitle;

  /// No description provided for @kioskOutOfServiceBody.
  ///
  /// In fr, this message translates to:
  /// **'Merci de commander directement à la caisse.'**
  String get kioskOutOfServiceBody;

  /// No description provided for @kioskUnavailableNow.
  ///
  /// In fr, this message translates to:
  /// **'Un plat de votre commande n\'est plus disponible. Merci de le retirer.'**
  String get kioskUnavailableNow;

  /// No description provided for @kioskTakeAway.
  ///
  /// In fr, this message translates to:
  /// **'À emporter'**
  String get kioskTakeAway;

  /// No description provided for @kioskCategoryAll.
  ///
  /// In fr, this message translates to:
  /// **'Tout'**
  String get kioskCategoryAll;

  /// No description provided for @kioskSearchHint.
  ///
  /// In fr, this message translates to:
  /// **'Rechercher un plat'**
  String get kioskSearchHint;

  /// No description provided for @kioskSearchEmpty.
  ///
  /// In fr, this message translates to:
  /// **'Aucun plat ne correspond à votre recherche.'**
  String get kioskSearchEmpty;

  /// No description provided for @kioskSearchClear.
  ///
  /// In fr, this message translates to:
  /// **'Effacer'**
  String get kioskSearchClear;

  /// No description provided for @kioskSlipHeader.
  ///
  /// In fr, this message translates to:
  /// **'TIMMA EATS'**
  String get kioskSlipHeader;

  /// No description provided for @kioskSetupTitle.
  ///
  /// In fr, this message translates to:
  /// **'Borne non configurée'**
  String get kioskSetupTitle;

  /// No description provided for @kioskSetupBody.
  ///
  /// In fr, this message translates to:
  /// **'Cette tablette n\'est pas encore rattachée à un restaurant. Contactez le responsable pour la configurer.'**
  String get kioskSetupBody;

  /// No description provided for @kioskSecretLostTitle.
  ///
  /// In fr, this message translates to:
  /// **'Configuration à restaurer'**
  String get kioskSecretLostTitle;

  /// No description provided for @kioskSecretLostBody.
  ///
  /// In fr, this message translates to:
  /// **'La clé de sécurité des tickets de cette borne est introuvable. Les tickets déjà imprimés ne peuvent plus être vérifiés. Contactez le responsable avant de reprendre les commandes.'**
  String get kioskSecretLostBody;

  /// No description provided for @kioskPrintPrinting.
  ///
  /// In fr, this message translates to:
  /// **'Impression du ticket…'**
  String get kioskPrintPrinting;

  /// No description provided for @kioskPrintFailed.
  ///
  /// In fr, this message translates to:
  /// **'Ticket non imprimé. Présentez ce numéro à la caisse.'**
  String get kioskPrintFailed;

  /// No description provided for @kioskPrintRetry.
  ///
  /// In fr, this message translates to:
  /// **'Réimprimer'**
  String get kioskPrintRetry;

  /// No description provided for @shiftCloseTitle.
  ///
  /// In fr, this message translates to:
  /// **'Clôture de service'**
  String get shiftCloseTitle;

  /// No description provided for @shiftCloseTickets.
  ///
  /// In fr, this message translates to:
  /// **'Tickets'**
  String get shiftCloseTickets;

  /// No description provided for @shiftCloseAcknowledged.
  ///
  /// In fr, this message translates to:
  /// **'Confirmés par le cloud'**
  String get shiftCloseAcknowledged;

  /// No description provided for @shiftCloseUnsent.
  ///
  /// In fr, this message translates to:
  /// **'Pas encore envoyés'**
  String get shiftCloseUnsent;

  /// No description provided for @shiftCloseCash.
  ///
  /// In fr, this message translates to:
  /// **'Espèces (à compter en caisse)'**
  String get shiftCloseCash;

  /// No description provided for @shiftCloseMomo.
  ///
  /// In fr, this message translates to:
  /// **'Mobile money au comptoir'**
  String get shiftCloseMomo;

  /// No description provided for @shiftCloseUntendered.
  ///
  /// In fr, this message translates to:
  /// **'Payés, moyen non enregistré'**
  String get shiftCloseUntendered;

  /// No description provided for @shiftCloseStranded.
  ///
  /// In fr, this message translates to:
  /// **'Tickets bloqués'**
  String get shiftCloseStranded;

  /// No description provided for @shiftCloseSettled.
  ///
  /// In fr, this message translates to:
  /// **'Tout est synchronisé.'**
  String get shiftCloseSettled;

  /// No description provided for @shiftCloseForceDrain.
  ///
  /// In fr, this message translates to:
  /// **'Forcer la synchronisation'**
  String get shiftCloseForceDrain;

  /// No description provided for @shiftCloseTicketLine.
  ///
  /// In fr, this message translates to:
  /// **'Ticket {number} · {reason}'**
  String shiftCloseTicketLine(String number, String reason);

  /// No description provided for @shiftCloseNoTicketNumber.
  ///
  /// In fr, this message translates to:
  /// **'sans numéro'**
  String get shiftCloseNoTicketNumber;

  /// No description provided for @kioskManagerTitle.
  ///
  /// In fr, this message translates to:
  /// **'Responsable'**
  String get kioskManagerTitle;

  /// No description provided for @kioskManagerPairKitchen.
  ///
  /// In fr, this message translates to:
  /// **'Apparier une cuisine'**
  String get kioskManagerPairKitchen;

  /// No description provided for @kioskManagerHubOn.
  ///
  /// In fr, this message translates to:
  /// **'Borne visible sur le wifi'**
  String get kioskManagerHubOn;

  /// No description provided for @kioskManagerHubOff.
  ///
  /// In fr, this message translates to:
  /// **'Borne non démarrée'**
  String get kioskManagerHubOff;

  /// No description provided for @kioskManagerBoards.
  ///
  /// In fr, this message translates to:
  /// **'{count} cuisine(s) connectée(s)'**
  String kioskManagerBoards(int count);

  /// No description provided for @kioskManagerCodeTitle.
  ///
  /// In fr, this message translates to:
  /// **'Code d\'appairage'**
  String get kioskManagerCodeTitle;

  /// No description provided for @kioskManagerCodeHint.
  ///
  /// In fr, this message translates to:
  /// **'Saisissez ce code sur la tablette cuisine.'**
  String get kioskManagerCodeHint;

  /// No description provided for @kioskManagerCodeLeft.
  ///
  /// In fr, this message translates to:
  /// **'Valable encore {seconds} s'**
  String kioskManagerCodeLeft(int seconds);

  /// No description provided for @kioskManagerCodeExpired.
  ///
  /// In fr, this message translates to:
  /// **'Code expiré. Recommencez.'**
  String get kioskManagerCodeExpired;

  /// No description provided for @kioskManagerNoSecret.
  ///
  /// In fr, this message translates to:
  /// **'Clé de sécurité manquante : impossible d\'apparier.'**
  String get kioskManagerNoSecret;

  /// No description provided for @kioskManagerPairFailed.
  ///
  /// In fr, this message translates to:
  /// **'L\'appairage n\'a pas pu démarrer.'**
  String get kioskManagerPairFailed;

  /// No description provided for @kioskManagerHubFailed.
  ///
  /// In fr, this message translates to:
  /// **'La borne n\'a pas pu démarrer sur le wifi.'**
  String get kioskManagerHubFailed;

  /// No description provided for @kioskManagerPinTitle.
  ///
  /// In fr, this message translates to:
  /// **'Code responsable'**
  String get kioskManagerPinTitle;

  /// No description provided for @kioskManagerPinWrong.
  ///
  /// In fr, this message translates to:
  /// **'Code incorrect.'**
  String get kioskManagerPinWrong;

  /// No description provided for @kioskManagerPinOpen.
  ///
  /// In fr, this message translates to:
  /// **'Ouvrir'**
  String get kioskManagerPinOpen;

  /// No description provided for @kioskManagerPinUnset.
  ///
  /// In fr, this message translates to:
  /// **'Aucun code responsable configuré sur cette borne.'**
  String get kioskManagerPinUnset;

  /// No description provided for @kioskSlipWithout.
  ///
  /// In fr, this message translates to:
  /// **'SANS {ingredient}'**
  String kioskSlipWithout(String ingredient);

  /// Q69 — une ligne de composition sur le ticket imprimé. Le motif garde ses placeholders : un ticket porte plusieurs groupes et l'imprimante n'a pas de délégué de localisation à qui redemander.
  ///
  /// In fr, this message translates to:
  /// **'{group} : {answer}'**
  String kioskSlipGroupLabel(String group, String answer);

  /// Q69 — la réponse « rien choisi » pour un groupe QUI A ÉTÉ PROPOSÉ. Ne rien imprimer serait indiscernable d'un plat qui n'a jamais posé la question.
  ///
  /// In fr, this message translates to:
  /// **'AUCUN'**
  String get kioskSlipGroupNone;

  /// Preparation window on the kiosk dish card. Mirrors the app's `dishPrepWindow` literal-for-literal: the same dish must read the same on the borne as on the phone.
  ///
  /// In fr, this message translates to:
  /// **'{min}–{max} min'**
  String kioskDishPrepWindow(int min, int max);

  /// No description provided for @kioskDishPrepWindowSemantics.
  ///
  /// In fr, this message translates to:
  /// **'Préparation : {min} à {max} minutes'**
  String kioskDishPrepWindowSemantics(int min, int max);

  /// Screen-reader name for the chilli. A `select`, not a `plural`. ⚠ The CARD draws ONE chilli whatever the level; the composer is where a level belongs. Level 0 draws nothing at all.
  ///
  /// In fr, this message translates to:
  /// **'{level, select, 1{Peu épicé} 2{Épicé} 3{Très épicé} other{Non épicé}}'**
  String kioskDishSpiceLevel(String level);

  /// No description provided for @kioskManagerApprovalTitle.
  ///
  /// In fr, this message translates to:
  /// **'Une cuisine demande à s\'apparier'**
  String get kioskManagerApprovalTitle;

  /// No description provided for @kioskManagerApprovalCompare.
  ///
  /// In fr, this message translates to:
  /// **'Vérifiez que ce nombre est le même sur la tablette cuisine.'**
  String get kioskManagerApprovalCompare;

  /// No description provided for @kioskManagerApprovalAccept.
  ///
  /// In fr, this message translates to:
  /// **'Accepter'**
  String get kioskManagerApprovalAccept;

  /// No description provided for @kioskManagerApprovalRefuse.
  ///
  /// In fr, this message translates to:
  /// **'Refuser'**
  String get kioskManagerApprovalRefuse;

  /// No description provided for @kioskManagerPairOrCode.
  ///
  /// In fr, this message translates to:
  /// **'Ou saisissez ce code sur la tablette cuisine'**
  String get kioskManagerPairOrCode;

  /// No description provided for @kioskManagerPairWaiting.
  ///
  /// In fr, this message translates to:
  /// **'En attente d\'une cuisine'**
  String get kioskManagerPairWaiting;

  /// No description provided for @kioskManagerPairWaitingBody.
  ///
  /// In fr, this message translates to:
  /// **'Sur la tablette cuisine, touchez « Apparier en un geste ».'**
  String get kioskManagerPairWaitingBody;

  /// No description provided for @kioskManagerPairCodeFallback.
  ///
  /// In fr, this message translates to:
  /// **'Ou saisissez ce code sur la cuisine'**
  String get kioskManagerPairCodeFallback;

  /// No description provided for @kioskDishIngredients.
  ///
  /// In fr, this message translates to:
  /// **'INGRÉDIENTS'**
  String get kioskDishIngredients;

  /// No description provided for @kioskDishAllergens.
  ///
  /// In fr, this message translates to:
  /// **'Contient'**
  String get kioskDishAllergens;

  /// No description provided for @kioskDishWithout.
  ///
  /// In fr, this message translates to:
  /// **'Sans {name}'**
  String kioskDishWithout(String name);

  /// No description provided for @kioskDishRemovableHint.
  ///
  /// In fr, this message translates to:
  /// **'Touchez pour retirer'**
  String get kioskDishRemovableHint;

  /// No description provided for @kioskWeekMenuTitle.
  ///
  /// In fr, this message translates to:
  /// **'Menu de la semaine'**
  String get kioskWeekMenuTitle;

  /// No description provided for @kioskWeekMenuIntro.
  ///
  /// In fr, this message translates to:
  /// **'Les plats et les jours où ils sont cuisinés.'**
  String get kioskWeekMenuIntro;

  /// No description provided for @kioskWeekMenuEveryDay.
  ///
  /// In fr, this message translates to:
  /// **'Tous les jours'**
  String get kioskWeekMenuEveryDay;

  /// No description provided for @kioskWeekMenuNotScheduled.
  ///
  /// In fr, this message translates to:
  /// **'Pas cette semaine'**
  String get kioskWeekMenuNotScheduled;

  /// No description provided for @kioskWeekMenuToday.
  ///
  /// In fr, this message translates to:
  /// **'Aujourd\'hui'**
  String get kioskWeekMenuToday;

  /// No description provided for @kioskWeekMenuClose.
  ///
  /// In fr, this message translates to:
  /// **'Fermer'**
  String get kioskWeekMenuClose;

  /// No description provided for @kioskPayMobileTitle.
  ///
  /// In fr, this message translates to:
  /// **'Pas d\'espèces ? Payez par Mobile Money ou Orange Money'**
  String get kioskPayMobileTitle;

  /// No description provided for @kioskPayMobileHint.
  ///
  /// In fr, this message translates to:
  /// **'Composez le code marchand, puis montrez la confirmation à la caisse avec votre ticket.'**
  String get kioskPayMobileHint;

  /// No description provided for @kioskPayMobileProviderMtn.
  ///
  /// In fr, this message translates to:
  /// **'MTN Mobile Money'**
  String get kioskPayMobileProviderMtn;

  /// No description provided for @kioskPayMobileProviderOrange.
  ///
  /// In fr, this message translates to:
  /// **'Orange Money'**
  String get kioskPayMobileProviderOrange;

  /// No description provided for @kioskPayMobileCode.
  ///
  /// In fr, this message translates to:
  /// **'Code marchand : {code}'**
  String kioskPayMobileCode(String code);

  /// No description provided for @kioskPayMobileHolder.
  ///
  /// In fr, this message translates to:
  /// **'Au nom de : {name}'**
  String kioskPayMobileHolder(String name);

  /// No description provided for @kioskSlipMobileTitle.
  ///
  /// In fr, this message translates to:
  /// **'Pas d\'espèces ? Payez par :'**
  String get kioskSlipMobileTitle;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'fr'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'fr':
      return AppLocalizationsFr();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
