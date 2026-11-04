import 'package:flutter_test/flutter_test.dart';
import 'package:rowing_app/app_strings.dart';
import 'package:rowing_app/program_service.dart';

void main() {
  group('Program Tab & Workouts Hierarchy Tests', () {
    test('6 Zones & Automatic HR% mapping verification', () {
      expect(kProgramZonesDetailed.length, 6);
      expect(kProgramZonesDetailed[0], 'zone1 = 55%:65%');
      expect(kProgramZonesDetailed[1], 'zone2 = 65%:75%');
      expect(kProgramZonesDetailed[2], 'zone3 = 75%:85%');
      expect(kProgramZonesDetailed[3], 'zone4 = 85%:90%');
      expect(kProgramZonesDetailed[4], 'Threshold = 90%:95%');
      expect(kProgramZonesDetailed[5], 'zone5 = 95%:100%');

      // Check automatic HR% drop map
      expect(kZoneToHrPercentMap['zone1 = 55%:65%'], '55%:65%');
      expect(kZoneToHrPercentMap['zone2 = 65%:75%'], '65%:75%');
      expect(kZoneToHrPercentMap['zone3 = 75%:85%'], '75%:85%');
      expect(kZoneToHrPercentMap['zone4 = 85%:90%'], '85%:90%');
      expect(kZoneToHrPercentMap['Threshold = 90%:95%'], '90%:95%');
      expect(kZoneToHrPercentMap['zone5 = 95%:100%'], '95%:100%');
    });

    test('Zone normalization maps all variations to base keys', () {
      expect(normalizeZoneKey('zone1 = 55%:65%'), 'Z1');
      expect(normalizeZoneKey('zone2 = 65%:75%'), 'Z2');
      expect(normalizeZoneKey('zone3 = 75%:85%'), 'Z3');
      expect(normalizeZoneKey('zone4 = 85%:90%'), 'Z4');
      expect(normalizeZoneKey('Threshold = 90%:95%'), 'Threshold');
      expect(normalizeZoneKey('zone5 = 95%:100%'), 'Z5');

      // Also backward compatibility keys
      expect(normalizeZoneKey('Z1'), 'Z1');
      expect(normalizeZoneKey('Z2'), 'Z2');
      expect(normalizeZoneKey('Z3'), 'Z3');
      expect(normalizeZoneKey('Z4'), 'Z4');
      expect(normalizeZoneKey('Threshold'), 'Threshold');
      expect(normalizeZoneKey('Z5'), 'Z5');
    });

    test('Workout item correctly duplicates specs when added via (+)', () {
      final original = ProgramWorkoutItem(
        sessionId: 1,
        section: 'main',
        itemIdx: 0,
        time: '08:30',
        durationMinutes: 45,
        distanceMeters: 8000,
        reps: 2,
        kind: 'Erg',
        zone: 'zone4 = 85%:90%',
        hrPercent: 88,
        hrRange: '85%:90%',
        details: 'تمرين عتبة مكثف',
      );

      final duplicate = ProgramWorkoutItem(
        sessionId: original.sessionId,
        section: original.section,
        itemIdx: 1,
        time: original.time,
        durationMinutes: original.durationMinutes,
        distanceMeters: original.distanceMeters,
        reps: original.reps,
        kind: original.kind,
        zone: original.zone,
        hrPercent: original.hrPercent,
        hrRange: original.hrRange,
      );

      expect(duplicate.time, '08:30');
      expect(duplicate.durationMinutes, 45);
      expect(duplicate.distanceMeters, 8000);
      expect(duplicate.reps, 2);
      expect(duplicate.kind, 'Erg');
      expect(duplicate.zone, 'zone4 = 85%:90%');
      expect(duplicate.hrRange, '85%:90%');
      expect(duplicate.totalSeconds, 45 * 60 * 2);
    });

    test('Session zone duration accumulation respects normalized zones', () {
      final w1 = ProgramWorkoutItem(
        sessionId: 10,
        section: 'warmup',
        itemIdx: 0,
        durationMinutes: 10,
        zone: 'zone1 = 55%:65%',
      );
      final w2 = ProgramWorkoutItem(
        sessionId: 10,
        section: 'main',
        itemIdx: 1,
        durationMinutes: 30,
        reps: 2,
        zone: 'zone3 = 75%:85%',
      );
      final w3 = ProgramWorkoutItem(
        sessionId: 10,
        section: 'cooldown',
        itemIdx: 2,
        durationMinutes: 5,
        zone: 'Threshold = 90%:95%',
      );

      final session = ProgramDaySession(
        id: 10,
        cycleId: 1,
        cycleType: 'basic',
        dayOfWeek: 0,
        sessionIdx: 0,
        name: 'الحصة 1',
        workouts: [w1, w2, w3],
      );

      final durations = session.zoneDurations;
      expect(durations['Z1'], 10 * 60);
      expect(durations['Z3'], 30 * 60 * 2);
      expect(durations['Threshold'], 5 * 60);
      expect(durations['Z2'], 0);
    });

    test('Four standard test types are correctly registered', () {
      expect(kProgramTestTypes, contains('500 m test'));
      expect(kProgramTestTypes, contains('750 m test'));
      expect(kProgramTestTypes, contains('1500 m test'));
      expect(kProgramTestTypes, contains('3000 m test'));
      expect(kProgramTestTypes.length, 4);
    });

    test('Hamburger Hub strings are defined in Arabic and English', () {
      const ar = AppStrings(true);
      const en = AppStrings(false);

      expect(ar.hamburgerTitle.isNotEmpty, isTrue);
      expect(en.hamburgerTitle.isNotEmpty, isTrue);
      expect(ar.multiDashboardNav, contains('الانتقال'));
      expect(en.multiDashboardNav, contains('Navigation'));
      expect(ar.hardwareIntegration, contains('الاستشعار'));
      expect(en.hardwareIntegration, contains('Hardware'));
      expect(ar.advancedDataExport, contains('تصدير'));
      expect(en.advancedDataExport, contains('Export'));
    });
  });
}

