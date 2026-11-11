import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:rowing_app/app_strings.dart';
import 'package:rowing_app/auth_service.dart';
import 'package:rowing_app/db.dart';
import 'package:rowing_app/heart_rate_zones.dart';
import 'package:rowing_app/progress_calcs.dart';
import 'package:rowing_app/progress_curve_header.dart';
import 'package:rowing_app/progress_curve_page.dart';
import 'package:rowing_app/progress_period_filter.dart';
import 'package:rowing_app/progress_tab.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
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
    await db.execute('''
      CREATE TABLE IF NOT EXISTS cp_tests(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        player_id INTEGER,
        date TEXT,
        test_type TEXT,
        duration_seconds INTEGER,
        avg_power REAL,
        max_power REAL,
        distance INTEGER,
        avg_hr INTEGER,
        max_hr INTEGER,
        split_500 REAL,
        notes TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS cp_values(
        player_id INTEGER,
        date TEXT,
        cp REAL,
        w_prime REAL,
        method TEXT,
        PRIMARY KEY(player_id, date)
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

  group('ProgressTab & ProgressCurvePage Widget Tests', () {
    const testUser = AppUser(
      id: 1,
      email: 'mabdelhalimdawod@engine.rowing',
      name: 'Coach Mahmoud',
      role: 'coach',
      coachId: null,
      subscriptionActive: true,
    );

    testWidgets('ProgressTab shows all 7 curve menu icons & opens curve screens',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.75;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await AppLanguage.instance.setLocale(const Locale('ar'));

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ProgressTab(user: testUser),
          ),
        ),
      );
      await tester.pump();

      // Verify all 7 menu entries appear cleanly without layout overflow
      expect(find.text('Matrix Zone'), findsOneWidget);
      expect(find.text('EF و Decoupling'), findsOneWidget);
      expect(find.text('الواط'), findsOneWidget);
      expect(find.text('PMC (الحمل)'), findsOneWidget);
      expect(find.text('الاستشفاء'), findsOneWidget);
      expect(find.text('ساعات الزونات'), findsOneWidget);
      expect(find.text('اختبارات CP'), findsOneWidget);

      // Tap Zone Hours to verify opening ProgressCurvePage
      await tester.runAsync(() async {
        await tester.tap(find.text('ساعات الزونات'));
        await tester.pump();
        for (int i = 0; i < 12; i++) {
          await Future.delayed(const Duration(milliseconds: 30));
          await tester.pump();
        }
      });
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.byType(ProgressPeriodFilter), findsOneWidget);
      expect(find.byType(ProgressCurveHeader), findsOneWidget);
    });

    testWidgets('ProgressPeriodFilter handles empty cycles gracefully without crashing',
        (tester) async {
      await AppLanguage.instance.setLocale(const Locale('ar'));
      ProgressPeriodSelection selection = ProgressPeriodSelection.defaultWeek(
        DateTime(2026, 10, 31),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return Column(
                  children: [
                    ProgressPeriodFilter(
                      selection: selection,
                      cyclesLoader: () async => const [],
                      onChanged: (next) => setState(() => selection = next),
                    ),
                    ProgressCurveHeader(
                      curveName: 'HRV',
                      period: ProgressPeriodSelection(
                        mode: ProgressPeriodMode.custom,
                        start: DateTime(2026, 10, 1),
                        end: DateTime(2026, 10, 31),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      );
      await tester.pump();

      // Verify ProgressCurveHeader exact date format in Arabic
      expect(find.text('HRV، من 1/10/2026 إلى 31/10/2026'), findsOneWidget);

      // Tap Cycle filter with zero cycles in DB -> must show message without crash
      await tester.runAsync(() async {
        await tester.tap(find.text('سايكل'));
        await tester.pump();
        await Future.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();

      expect(find.text('لسه مفيش سايكلات متسجلة'), findsOneWidget);
    });

    testWidgets('ProgressCurveHeader English format matches From D/M/YYYY to D/M/YYYY',
        (tester) async {
      await AppLanguage.instance.setLocale(const Locale('en'));
      addTearDown(() => AppLanguage.instance.setLocale(const Locale('ar')));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProgressCurveHeader(
              curveName: 'HRV',
              period: ProgressPeriodSelection(
                mode: ProgressPeriodMode.custom,
                start: DateTime(2026, 10, 1),
                end: DateTime(2026, 10, 31),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('HRV, From 1/10/2026 to 31/10/2026'), findsOneWidget);
    });

    testWidgets('Zone Hours screen displays 8 zone rows and toggles players locally',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.75;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await AppLanguage.instance.setLocale(const Locale('ar'));

      await tester.runAsync(() async {
        final database = await DB.db;
        await database.delete('logs');
        await database.delete('players');
        await database.insert('players', {'id': 1, 'name': 'أحمد', 'mhr': 190, 'active': 1});
        await database.insert('players', {'id': 2, 'name': 'كريم', 'mhr': 195, 'active': 1});
        await database.insert('logs', {
          'player_id': 1,
          'date': dstr(DateTime.now()),
          'idx': 0,
          'hr': 148,
          'rhr': 50,
          'duration_seconds': 3600,
        });

        await tester.pumpWidget(
          const MaterialApp(
            home: ProgressCurvePage(
              curveType: ProgressCurveType.zoneHours,
              user: testUser,
            ),
          ),
        );
        for (int i = 0; i < 15; i++) {
          await Future.delayed(const Duration(milliseconds: 40));
          await tester.pump();
        }
      });
      await tester.pump();

      expect(find.text('Zone 1 - UT3'), findsOneWidget);
      expect(find.text('Zone 2 - UT2'), findsOneWidget);
      expect(find.text('Zone 3 - UT1'), findsOneWidget);
      expect(find.text('Zone 4 - AT'), findsOneWidget);
      expect(find.text('Threshold - AT'), findsOneWidget);
      expect(find.text('Zone 5 - TR'), findsOneWidget);
      expect(find.text('VO2 max - AN'), findsOneWidget);
      expect(find.text('بدون زون'), findsOneWidget);

      // Toggle second athlete ('كريم') on -> now two 8-row tables appear
      await tester.runAsync(() async {
        await tester.tap(find.text('كريم'));
        await tester.pump();
        for (int i = 0; i < 10; i++) {
          await Future.delayed(const Duration(milliseconds: 30));
          await tester.pump();
        }
      });
      await tester.pump();
      expect(find.text('Zone 1 - UT3'), findsNWidgets(2));

      // Toggle second athlete ('كريم') off -> back to 1 table (local setState removal)
      await tester.tap(find.text('كريم').first);
      await tester.pump();
      expect(find.text('Zone 1 - UT3'), findsOneWidget);
    });

    testWidgets('PMC Load renders Today cards, lines, TSB bars & missing CP notice',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.75;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await AppLanguage.instance.setLocale(const Locale('ar'));

      final today = DateTime.now();
      final yesterday = today.subtract(const Duration(days: 1));
      final twoDaysAgo = today.subtract(const Duration(days: 2));

      await tester.runAsync(() async {
        final database = await DB.db;
        await database.delete('logs');
        await database.delete('cp_values');
        await database.delete('players');
        try {
          await database.delete('daily_load');
        } catch (_) {}

        await database.insert('players', {'id': 1, 'name': 'أحمد', 'mhr': 190, 'active': 1});
        await database.insert('cp_values', {
          'player_id': 1,
          'date': dstr(yesterday),
          'cp': 250.0,
          'w_prime': 15000.0,
          'method': 'two_point',
        });
        // Workout before CP -> missing CP notice ("--")
        await database.insert('logs', {
          'player_id': 1,
          'date': dstr(twoDaysAgo),
          'idx': 0,
          'avg_power': 240.0,
          'duration_seconds': 3600,
        });
        // Workout after CP -> included in daily_load
        await database.insert('logs', {
          'player_id': 1,
          'date': dstr(yesterday),
          'idx': 0,
          'avg_power': 250.0,
          'duration_seconds': 3600,
        });

        await tester.pumpWidget(
          const MaterialApp(
            home: ProgressCurvePage(
              curveType: ProgressCurveType.pmcLoad,
              user: testUser,
            ),
          ),
        );
        for (int i = 0; i < 20; i++) {
          await Future.delayed(const Duration(milliseconds: 40));
          await tester.pump();
        }
      });
      await tester.pump();

      expect(find.textContaining('CTL'), findsWidgets);
      expect(find.textContaining('ATL'), findsWidgets);
      expect(find.textContaining('TSB'), findsWidgets);
      expect(find.textContaining('--'), findsWidgets);
    });

    testWidgets('Matrix Zone renders single shared dual-axis chart for multiple athletes',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.75;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await AppLanguage.instance.setLocale(const Locale('ar'));

      await tester.runAsync(() async {
        final database = await DB.db;
        await database.delete('logs');
        await database.delete('players');
        await database.insert('players', {'id': 1, 'name': 'أحمد', 'mhr': 190, 'active': 1});
        await database.insert('players', {'id': 2, 'name': 'كريم', 'mhr': 195, 'active': 1});
        await database.insert('logs', {
          'player_id': 1,
          'date': dstr(DateTime.now()),
          'idx': 0,
          'hr': 155,
          'rhr': 50,
          'avg_power': 230.0,
        });

        await tester.pumpWidget(
          const MaterialApp(
            home: ProgressCurvePage(
              curveType: ProgressCurveType.matrixZone,
              user: testUser,
            ),
          ),
        );
        for (int i = 0; i < 15; i++) {
          await Future.delayed(const Duration(milliseconds: 40));
          await tester.pump();
        }
      });
      await tester.pump();

      expect(find.textContaining('Matrix Zone،'), findsOneWidget);
      expect(find.textContaining('محور أفقي'), findsOneWidget);
      // Add second athlete and confirm Matrix Zone keeps a single shared chart
      await tester.runAsync(() async {
        await tester.tap(find.text('كريم'));
        await tester.pump();
        for (int i = 0; i < 10; i++) {
          await Future.delayed(const Duration(milliseconds: 30));
          await tester.pump();
        }
      });
      await tester.pump();
      expect(find.byType(ProgressCurveHeader), findsOneWidget);
    });

    testWidgets('Recovery renders all 5 curve headers (4 curves + Eupnea)',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.75;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await AppLanguage.instance.setLocale(const Locale('ar'));

      await tester.runAsync(() async {
        final database = await DB.db;
        await database.delete('logs');
        await database.delete('players');
        await database.insert('players', {'id': 1, 'name': 'أحمد', 'mhr': 190, 'active': 1});

        await tester.pumpWidget(
          const MaterialApp(
            home: ProgressCurvePage(
              curveType: ProgressCurveType.recovery,
              user: testUser,
            ),
          ),
        );
        for (int i = 0; i < 15; i++) {
          await Future.delayed(const Duration(milliseconds: 40));
          await tester.pump();
        }
      });
      await tester.pump();

      expect(find.byType(ProgressCurveHeader), findsNWidgets(5));
    });
  });
}
