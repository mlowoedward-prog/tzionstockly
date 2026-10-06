// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Swahili (`sw`).
class AppLocalizationsSw extends AppLocalizations {
  AppLocalizationsSw([String locale = 'sw']) : super(locale);

  @override
  String get appTitle => 'Tzion Stockly';

  @override
  String get navHome => 'Mwanzo';

  @override
  String get navProducts => 'Bidhaa';

  @override
  String get navStock => 'Hisa';

  @override
  String get navReports => 'Ripoti';

  @override
  String get navMore => 'Zaidi';

  @override
  String get syncStatusSynced => 'Imelandanishwa';

  @override
  String get syncStatusSyncing => 'Inalandanisha';

  @override
  String get syncStatusOffline => 'Bila Mtandao';

  @override
  String get syncStatusPending => 'Inasubiri';
}
