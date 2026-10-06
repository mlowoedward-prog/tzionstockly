import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tzion_stockly/app/theme.dart';
import 'package:tzion_stockly/l10n/app_localizations.dart';
import 'package:tzion_stockly/l10n/app_localizations_en.dart';
import 'package:tzion_stockly/l10n/app_localizations_sw.dart';

void main() {
  group('Prompt 0 Setup Unit Tests', () {
    test('AppTheme verifies core brand colors', () {
      expect(AppTheme.primaryNavy, const Color(0xFF1F3864));
      expect(AppTheme.secondaryTeal, const Color(0xFF14B8A6));
      expect(AppTheme.successGreen, const Color(0xFF10B981));
      expect(AppTheme.warningAmber, const Color(0xFFF59E0B));
      expect(AppTheme.errorRed, const Color(0xFFEF4444));
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
