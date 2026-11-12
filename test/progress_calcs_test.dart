import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:rowing_app/db.dart';
import 'package:rowing_app/heart_rate_zones.dart';
import 'package:rowing_app/progress_calcs.dart';

void main() {
  late Database db;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);

    await db.execute(
      'CREATE TABLE players(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, mhr INTEGER, active INTEGER DEFAULT 1)',
    );
    await db.execute('''
      CREATE TABLE logs(
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
        PRIMARY KEY(player_id, date, idx)
      )
    ''');
    await db.execute('''
      CREATE TABLE cp_tests(
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
      CREATE TABLE cp_values(
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

  tearDown(() async {
    await db.delete('logs');
    await db.delete('cp_tests');
    await db.delete('cp_values');
    await db.delete('players');
    try {
      await db.delete('daily_load');
    } catch (_) {}
  });

  group('TSS & PMC Calculations', () {
    test('One hour at exact CP produces TSS = 100', () {
      final tss = ProgressCalcs.calculateWorkoutTSS(
        avgPower: 260.0,
        durationSeconds: 3600,
        cp: 260.0,
      );
      expect(tss, isNotNull);
      expect(tss!, closeTo(100.0, 1e-6));
    });

    test('Missing or invalid CP returns null TSS ("--")', () {
      expect(
        ProgressCalcs.calculateWorkoutTSS(
          avgPower: 250.0,
          durationSeconds: 1800,
          cp: null,
        ),
        isNull,
      );
      expect(
        ProgressCalcs.calculateWorkoutTSS(
          avgPower: 250.0,
          durationSeconds: 1800,
          cp: 0.0,
        ),
        isNull,
      );
    });

    test('Constant 100 TSS every day converges CTL and ATL close to 100', () {
      final start = DateTime(2026, 1, 1);
      final tssList = List.generate(
        250,
        (i) => {'date': start.add(Duration(days: i)), 'tss': 100.0},
      );

      final result = ProgressCalcs.calculatePMC(dailyTssList: tssList);
      final ctl = result['currentCTL'] as double;
      final atl = result['currentATL'] as double;
      final tsb = result['currentTSB'] as double;
      final tsbPoints = (result['tsbPoints'] as List).cast<DateValuePoint>();

      expect(ctl, closeTo(100.0, 0.5));
      expect(atl, closeTo(100.0, 0.05));
      expect(tsb, closeTo(0.0, 0.5));
      // Day 0 TSB_today = CTL_yesterday (0) - ATL_yesterday (0) = 0
      expect(tsbPoints.first.value, equals(0.0));
    });

    test('TSB_today equals CTL_yesterday minus ATL_yesterday & rest days use TSS = 0', () {
      final d0 = DateTime(2026, 10, 1);
      final d2 = DateTime(2026, 10, 3);
      final res = ProgressCalcs.calculatePMC(dailyTssList: [
        {'date': d0, 'tss': 100.0},
        {'date': d2, 'tss': 0.0},
      ]);

      final ctlPts = (res['ctlPoints'] as List).cast<DateValuePoint>();
      final atlPts = (res['atlPoints'] as List).cast<DateValuePoint>();
      final tsbPts = (res['tsbPoints'] as List).cast<DateValuePoint>();

      expect(ctlPts.length, equals(3));
      expect(tsbPts[0].value, equals(0.0));
      // Day 1 TSB uses Day 0 CTL - Day 0 ATL
      expect(
        tsbPts[1].value!,
        closeTo(ctlPts[0].value! - atlPts[0].value!, 0.02),
      );
      // Day 2 TSB uses Day 1 CTL - Day 1 ATL
      expect(
        tsbPts[2].value!,
        closeTo(ctlPts[1].value! - atlPts[1].value!, 0.02),
      );
    });

    test('TSB status classification matches all five named thresholds', () {
      expect(ProgressCalcs.classifyTsb(30.0), TsbStatus.excessRest);
      expect(ProgressCalcs.classifyTsb(25.0), TsbStatus.raceReady);
      expect(ProgressCalcs.classifyTsb(10.0), TsbStatus.raceReady);
      expect(ProgressCalcs.classifyTsb(5.0), TsbStatus.raceReady);
      expect(ProgressCalcs.classifyTsb(0.0), TsbStatus.neutral);
      expect(ProgressCalcs.classifyTsb(-10.0), TsbStatus.neutral);
      expect(ProgressCalcs.classifyTsb(-20.0), TsbStatus.productiveBuild);
      expect(ProgressCalcs.classifyTsb(-30.0), TsbStatus.productiveBuild);
      expect(ProgressCalcs.classifyTsb(-35.0), TsbStatus.overreachRisk);
    });
  });

  group('Karvonen Zone Boundaries & Zone Hours', () {
    test('MHR 190 and RHR 50 (HRR 140) exact 7-zone boundaries', () {
      final bounds = ProgressCalcs.karvonenAllZoneBounds(mhr: 190, rhr: 50);

      expect(bounds['Z1']!.minHR, equals(127.0));
      expect(bounds['Z1']!.maxHR, equals(141.0));

      expect(bounds['Z2']!.minHR, equals(141.0));
      expect(bounds['Z2']!.maxHR, equals(155.0));

      expect(bounds['Z3']!.minHR, equals(155.0));
      expect(bounds['Z3']!.maxHR, equals(169.0));

      expect(bounds['Z4']!.minHR, equals(169.0));
      expect(bounds['Z4']!.maxHR, equals(176.0));

      expect(bounds['Threshold']!.minHR, equals(176.0));
      expect(bounds['Threshold']!.maxHR, equals(183.0));

      expect(bounds['Z5']!.minHR, equals(183.0));
      expect(bounds['Z5']!.maxHR, equals(187.2));

      expect(bounds['VO2 max']!.minHR, equals(187.2));
      expect(bounds['VO2 max']!.maxHR, equals(197.0));
    });

    test('HeartRateZones threshold percentage constant is 90% to 95%', () {
      expect(HeartRateZones.zonePercentages['Threshold'], equals([0.90, 0.95]));
    });

    test('computeZoneHours assigns no-HR workouts to NO_ZONE and computes %', () {
      final logs = [
        // 1h in Z2 (HR=148 with MHR=190, RHR=50 => 70% HRR)
        {'hr': 148, 'rhr': 50, 'player_mhr': 190, 'duration_seconds': 3600},
        // 30m in Threshold (HR=179 => 92.1% HRR)
        {'hr': 179, 'rhr': 50, 'player_mhr': 190, 'duration_seconds': 1800},
        // 30m without HR => NO_ZONE
        {'hr': null, 'rhr': 50, 'player_mhr': 190, 'duration_seconds': 1800},
      ];

      final rows = ProgressCalcs.computeZoneHours(logs);
      expect(rows.length, equals(8)); // 7 zones + NO_ZONE

      final z2 = rows.firstWhere((r) => r.zoneKey == 'Z2');
      final thr = rows.firstWhere((r) => r.zoneKey == 'Threshold');
      final noZone = rows.firstWhere((r) => r.zoneKey == 'NO_ZONE');

      expect(z2.hours, closeTo(1.0, 1e-6));
      expect(z2.percentage, closeTo(50.0, 1e-6));

      expect(thr.hours, closeTo(0.5, 1e-6));
      expect(thr.percentage, closeTo(25.0, 1e-6));

      expect(noZone.hours, closeTo(0.5, 1e-6));
      expect(noZone.percentage, closeTo(25.0, 1e-6));
    });
  });

  group('getCpForDate & daily_load Cache Sync', () {
    test('getCpForDate resolves official cp_values, cp_tests fallback, and null', () async {
      await db.insert('players', {'id': 1, 'name': 'Rower A', 'mhr': 190});
      // Before any CP test/value
      expect(await ProgressCalcs.getCpForDate(1, '2026-10-01'), isNull);

      // Single CP test on 2026-10-05 => estimateCPFromSingle fallback
      await db.insert('cp_tests', {
        'player_id': 1,
        'date': '2026-10-05',
        'test_type': '2000m',
        'duration_seconds': 420,
        'avg_power': 300.0,
      });
      final singleEst = await ProgressCalcs.getCpForDate(1, '2026-10-06');
      expect(singleEst, closeTo(estimateCPFromSingle(300.0, 420), 1e-6));
      // Earlier date still has no CP
      expect(await ProgressCalcs.getCpForDate(1, '2026-10-04'), isNull);

      // Official CP value saved on 2026-10-10 overrides earlier estimate on >= 2026-10-10
      await db.insert('cp_values', {
        'player_id': 1,
        'date': '2026-10-10',
        'cp': 275.0,
        'w_prime': 18000.0,
        'method': 'two_point',
      });
      expect(await ProgressCalcs.getCpForDate(1, '2026-10-12'), closeTo(275.0, 1e-6));
      expect(await ProgressCalcs.getCpForDate(1, DateTime(2026, 10, 8)),
          closeTo(estimateCPFromSingle(300.0, 420), 1e-6));
    });

    test('daily_load table created via IF NOT EXISTS, excludes no-CP workouts, and recomputes from earliest changed date', () async {
      await db.insert('players', {'id': 2, 'name': 'Rower B', 'mhr': 190});
      await db.insert('cp_values', {
        'player_id': 2,
        'date': '2026-10-05',
        'cp': 250.0,
        'w_prime': 15000.0,
        'method': 'regression',
      });

      // Workout BEFORE CP exists (should be excluded & reported missingCpDates)
      await db.insert('logs', {
        'player_id': 2,
        'date': '2026-10-02',
        'idx': 0,
        'avg_power': 250.0,
        'duration_seconds': 3600,
      });
      // Workouts WITH CP (TSS = 100 each)
      await db.insert('logs', {
        'player_id': 2,
        'date': '2026-10-05',
        'idx': 0,
        'avg_power': 250.0,
        'duration_seconds': 3600,
      });
      await db.insert('logs', {
        'player_id': 2,
        'date': '2026-10-06',
        'idx': 0,
        'avg_power': 250.0,
        'duration_seconds': 3600,
      });

      final firstSync = await ProgressLoadCache.syncForPlayer(
        2,
        upToDate: DateTime(2026, 10, 7),
      );
      expect(firstSync.missingCpDates, contains('2026-10-02'));
      expect(firstSync.allEntries.first.date, equals('2026-10-05'));
      expect(firstSync.allEntries.length, equals(3));
      expect(firstSync.allEntries[0].tss, closeTo(100.0, 1e-4));
      expect(firstSync.allEntries[0].tsb, equals(0.0));

      // Second sync with NO edits should skip recomputation
      final noOpSync = await ProgressLoadCache.syncForPlayer(
        2,
        upToDate: DateTime(2026, 10, 7),
      );
      expect(noOpSync.recomputedFromDate, isNull);

      // Edit workout on 2026-10-06 -> must recompute from 2026-10-06 forward only
      await db.update(
        'logs',
        {'duration_seconds': 1800},
        where: 'player_id = ? AND date = ?',
        whereArgs: [2, '2026-10-06'],
      );
      final editedSync = await ProgressLoadCache.syncForPlayer(
        2,
        upToDate: DateTime(2026, 10, 7),
      );
      expect(editedSync.recomputedFromDate, equals('2026-10-06'));
      expect(editedSync.allEntries[1].tss, closeTo(50.0, 1e-4));
    });
  });
}

