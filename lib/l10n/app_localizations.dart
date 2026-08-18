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
