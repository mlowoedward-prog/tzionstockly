import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tzion_stockly/app/theme.dart';
import 'package:tzion_stockly/l10n/app_localizations.dart';
import 'package:tzion_stockly/l10n/app_localizations_en.dart';
import 'package:tzion_stockly/l10n/app_localizations_sw.dart';

void main() {
  group('Prompt 0 Setup Unit Tests', () {
    test('AppTheme lightTheme and darkTheme verify core colors', () {
      final light = AppTheme.lightTheme;
      final dark = AppTheme.darkTheme;

      expect(light.colorScheme.primary, AppTheme.primaryNavy);
      expect(light.colorScheme.secondary, AppTheme.secondaryTeal);
      expect(dark.colorScheme.primary, AppTheme.secondaryTeal);
      expect(dark.colorScheme.secondary, AppTheme.primaryNavy);
    });

    test('AppLocalizations lookup returns English and Swahili translations', () {
      final en = lookupAppLocalizations(const Locale('en'));
      final sw = lookupAppLocalizations(const Locale('sw'));

      expect(en, isA<AppLocalizationsEn>());
      expect(en.navHome, 'Home');
      expect(en.navProducts, 'Products');
      expect(en.navStock, 'Stock');
      expect(en.navReports, 'Reports');
      expect(en.navMore, 'More');

      expect(sw, isA<AppLocalizationsSw>());
      expect(sw.navHome, 'Mwanzo');
      expect(sw.navProducts, 'Bidhaa');
      expect(sw.navStock, 'Hisa');
      expect(sw.navReports, 'Ripoti');
      expect(sw.navMore, 'Zaidi');
    });
  });
}
