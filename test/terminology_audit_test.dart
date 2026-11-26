import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:rowing_app/app_strings.dart';

void main() {
  group('Terminology & Language Audit Tests (Phase L / Batch 3)', () {
    test('AppStrings terminology matches Coach standards', () {
      const sAr = AppStrings(true);
      const sEn = AppStrings(false);

      // 1. Cycle terminology
      expect(sAr.trainingCycles.contains('الدورات المرحلية'), isTrue);
      expect(sEn.trainingCycles.toLowerCase().contains('cycle'), isTrue);

      // 2. Zone terminology
      expect(sAr.isArabic, isTrue);
      expect(sEn.isArabic, isFalse);

      // 3. Past badge
      expect(sAr.pastDateBadge, 'منقضي');
      expect(sEn.pastDateBadge, 'Past');

      // 4. Test date
      expect(sAr.testDate, 'تاريخ الاختبار');
      expect(sEn.testDate, 'Test Date');
    });

    test('Source files audit: No hardcoded "Date:" in UI text strings', () {
      final dir = Directory('lib');
      final dartFiles = dir.listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'));

      final dateColonRegex = RegExp(r'''['"]Date:\s*['"]''');
      for (final file in dartFiles) {
        final content = file.readAsStringSync();
        final matches = dateColonRegex.allMatches(content);
        expect(matches.isEmpty, isTrue,
            reason: 'Found hardcoded "Date:" in ${file.path}');
      }
    });

    test('Source files audit: No raw "cycles" in Arabic UI strings', () {
      final file = File('lib/cycle_weekly_cycles_page.dart');
      final content = file.readAsStringSync();
      // Ensure the old '${val} cycles' pattern is gone
      expect(content.contains(r"${RowingNumberFormatter.toEnglishDigits(val.toString())} cycles'"), isFalse);
    });

    test('Source files audit: No "سيكل" in user-facing string literals in lib/', () {
      final dir = Directory('lib');
      final dartFiles = dir.listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'));

      final stringLiteralWithSikel = RegExp(r'''['"][^'"]*سيكل[^'"]*['"]''');
      for (final file in dartFiles) {
        final lines = file.readAsLinesSync();
        for (int i = 0; i < lines.length; i++) {
          final line = lines[i].trim();
          if (line.startsWith('//') || line.startsWith('///')) continue;
          final match = stringLiteralWithSikel.firstMatch(line);
          expect(match, isNull,
              reason: 'Found user-facing "سيكل" in ${file.path}:${i + 1}: "$line"');
        }
      }
    });
  });
}
