import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:rowing_app/auth_service.dart';
import 'package:rowing_app/db.dart';
import 'package:rowing_app/heart_rate_zones.dart';
import 'package:rowing_app/progress_calcs.dart';
import 'package:rowing_app/progress_tab.dart';

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await db.execute(
        'CREATE TABLE IF NOT EXISTS players(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, mhr INTEGER, active INTEGER DEFAULT 1)');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS logs(
        player_id INTEGER,
        date TEXT,
        idx INTEGER,
        rhr INTEGER,
        hrv INTEGER,
        hr INTEGER,
        hr_max INTEGER,
        hr_post INTEGER,
        hr_1min INTEGER,
        weight REAL,
        fatigue INTEGER,
        sleep_hours REAL,
        readiness INTEGER,
        player_notes TEXT,
        avg_power REAL,
        max_power REAL,
        duration_seconds INTEGER,
        distance INTEGER,
        split_500 REAL,
        ef REAL,
        eupnea REAL,
        decoupling REAL,
        zone TEXT,
        PRIMARY KEY(player_id, date, idx)
      )
    ''');
    DB.testDatabase = db;
  });

  group('Coach Zone Calculations & Karvonen Formula Tests', () {
    test('Karvonen target HR calculation', () {
      // MHR = 200, RHR = 60 => HRR = 140
      // 60% = 60 + (140 * 0.60) = 144
      expect(ProgressCalcs.karvonenTargetHR(mhr: 200, rhr: 60, hrPercent: 0.60),
          144);
      // 70% = 60 + (140 * 0.70) = 158
      expect(ProgressCalcs.karvonenTargetHR(mhr: 200, rhr: 60, hrPercent: 0.70),
          158);
      // 85% = 60 + (140 * 0.85) = 179
      expect(ProgressCalcs.karvonenTargetHR(mhr: 200, rhr: 60, hrPercent: 0.85),
          179);
      // 92% = 60 + (140 * 0.92) = 188.8 -> 189
      expect(ProgressCalcs.karvonenTargetHR(mhr: 200, rhr: 60, hrPercent: 0.92),
          189);
      // 103% = 60 + (140 * 1.03) = 204.2 -> 204
      expect(ProgressCalcs.karvonenTargetHR(mhr: 200, rhr: 60, hrPercent: 1.03),
          204);
    });

    test('Zone classification matches coach 7 zones', () {
      // MHR = 200, RHR = 60, HRR = 140
      // 60% HRR = 144 bpm -> Z1 (55%-65%)
      expect(HeartRateZones.determineZone(hr: 144, mhr: 200, rhr: 60), 'Z1');
      // 70% HRR = 158 bpm -> Z2 (65%-75%)
      expect(HeartRateZones.determineZone(hr: 158, mhr: 200, rhr: 60), 'Z2');
      // 80% HRR = 172 bpm -> Z3 (75%-85%)
      expect(HeartRateZones.determineZone(hr: 172, mhr: 200, rhr: 60), 'Z3');
      // 88% HRR = 183 bpm -> Z4 (85%-90%)
      expect(HeartRateZones.determineZone(hr: 183, mhr: 200, rhr: 60), 'Z4');
      // 93% HRR = 190 bpm -> Threshold (90%-95%)
      expect(HeartRateZones.determineZone(hr: 190, mhr: 200, rhr: 60),
          'Threshold');
      // 96% HRR = 194 bpm -> Z5 (95%-98%)
      expect(HeartRateZones.determineZone(hr: 194, mhr: 200, rhr: 60), 'Z5');
      // 100% HRR = 200 bpm -> VO2 max (98%-105%)
      expect(
          HeartRateZones.determineZone(hr: 200, mhr: 200, rhr: 60), 'VO2 max');
    });

    test('7-Day moving average requires >= 4 data points in 7-day window', () {
      final now = DateTime(2026, 11, 8);
      // Only 3 points -> should be null
      final sparsePoints = [
        DateValuePoint(date: now.subtract(const Duration(days: 6)), value: 100),
        DateValuePoint(date: now.subtract(const Duration(days: 4)), value: 110),
        DateValuePoint(date: now, value: 120),
      ];
      final maSparse = ProgressCalcs.movingAverage7(sparsePoints);
      expect(maSparse.last.value, isNull);

      // 4 points in 7 days -> should have average
      final validPoints = [
        DateValuePoint(date: now.subtract(const Duration(days: 6)), value: 100),
        DateValuePoint(date: now.subtract(const Duration(days: 4)), value: 110),
        DateValuePoint(date: now.subtract(const Duration(days: 2)), value: 120),
        DateValuePoint(date: now, value: 130),
      ];
      final maValid = ProgressCalcs.movingAverage7(validPoints);
      expect(maValid.last.value, isNotNull);
      expect(maValid.last.value, closeTo(115.0, 0.1));
    });

    test(
        'Metric trend evaluations (Watts up is up, Split down is up, Decoupling down is up)',
        () {
      // Watts: higher is improvement (up)
      expect(
          ProgressCalcs.evalWattsTrend(currentWatts: 250, baselineWatts: 230),
          ProgressTrend.up);
      expect(
          ProgressCalcs.evalWattsTrend(currentWatts: 210, baselineWatts: 230),
          ProgressTrend.down);

      // Split: lower time is improvement (up)
      expect(
          ProgressCalcs.evalSplitTrend(
              currentSplit: 100.0, baselineSplit: 105.0),
          ProgressTrend.up);
      expect(
          ProgressCalcs.evalSplitTrend(
              currentSplit: 110.0, baselineSplit: 105.0),
          ProgressTrend.down);

      // Decoupling: lower drift is improvement (up)
      expect(
          ProgressCalcs.evalDecouplingTrend(
              currentDecoupling: 3.5, baselineDecoupling: 6.0),
          ProgressTrend.up);
      expect(
          ProgressCalcs.evalDecouplingTrend(
              currentDecoupling: 7.0, baselineDecoupling: 5.0),
          ProgressTrend.down);
    });
  });

  group('ProgressTab Widget Rendering Tests', () {
    const testUser = AppUser(
      id: 1,
      email: 'mabdelhalimdawod@engine.rowing',
      name: 'Coach Mahmoud',
      role: 'coach',
      coachId: null,
      subscriptionActive: true,
    );

    testWidgets('ProgressTab renders cleanly without layout overflow',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.75;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.runAsync(() async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: ProgressTab(user: testUser),
            ),
          ),
        );
        for (int i = 0; i < 20; i++) {
          await Future.delayed(const Duration(milliseconds: 50));
          await tester.pump();
        }
      });

      // Verify filter chips exist
      expect(find.text('7D'), findsOneWidget);
      expect(find.text('30D'), findsOneWidget);
      expect(find.text('90D'), findsOneWidget);
      expect(find.text('All'), findsOneWidget);

      // Verify warning banner exists
      expect(find.textContaining('أستكمال المدخلات'), findsOneWidget);

      // Verify static note exists under curves
      expect(find.text('منحنى تقديري فقط'), findsWidgets);
    });
  });
}
