import 'package:flutter_test/flutter_test.dart';
import '../power_calculations.dart';
import '../app_strings.dart';

void main() {
  group('Phase 1 - Power & Decoupling Calculations Tests', () {
    test('calculateNormalizedPower works correctly with rolling 4th power algorithm', () {
      final samples = [200.0, 210.0, 220.0, 230.0, 220.0, 200.0];
      final np = PowerCalculations.calculateNormalizedPower(samples);
      expect(np, isNotNull);
      expect(np! >= 200.0 && np <= 230.0, isTrue);
    });

    test('parseSeries correctly handles comma and whitespace separated values', () {
      final text = '200, 210، 225  230, 240';
      final parsed = PowerCalculations.parseSeries(text);
      expect(parsed, equals([200.0, 210.0, 225.0, 230.0, 240.0]));
    });

    test('calculateEF calculates Watts / HR accurately', () {
      final ef = PowerCalculations.calculateEF(225.0, 150);
      expect(ef, equals(1.5));
    });

    test('calculateDecoupling computes drift percentage between halves', () {
      final watts = [200.0, 200.0, 200.0, 200.0];
      final hrs = [140.0, 140.0, 150.0, 150.0]; // HR drifted up in second half
      final decoupling = PowerCalculations.calculateDecoupling(watts, hrs);
      expect(decoupling, isNotNull);
      expect(decoupling! > 0, isTrue); // Positive cardiac drift
    });
  });

  group('Phase 1 - Localization Tests', () {
    test('AppLanguage switches between Arabic and English', () {
      final lang = AppLanguage.instance;
      expect(lang.isArabic, isTrue);
      
      final stringsAr = AppStrings(true);
      expect(stringsAr.tabDashboard, equals('Engine Rowing Dashboard'));
      expect(stringsAr.tabWorkouts, equals('التمارين'));
      expect(stringsAr.tabSettings, equals('الإعدادات'));

      final stringsEn = AppStrings(false);
      expect(stringsEn.tabWorkouts, equals('Workouts'));
      expect(stringsEn.tabSettings, equals('Settings'));
    });
  });
}
