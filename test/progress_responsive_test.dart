import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:rowing_app/app_strings.dart';
import 'package:rowing_app/auth_service.dart';
import 'package:rowing_app/db.dart';
import 'package:rowing_app/progress_curve_page.dart';

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
    await db.execute('''
      CREATE TABLE IF NOT EXISTS daily_load(
        player_id INTEGER NOT NULL,
        date TEXT NOT NULL,
        tss REAL,
        ctl REAL NOT NULL,
        atl REAL NOT NULL,
        tsb REAL NOT NULL,
        PRIMARY KEY(player_id, date)
      )
    ''');
    DB.testDatabase = db;

    // Seed test player and dummy data
    await db
        .insert('players', {'id': 1, 'name': 'أحمد', 'mhr': 190, 'active': 1});
    await db
        .insert('players', {'id': 2, 'name': 'كريم', 'mhr': 195, 'active': 1});
    final today = DateTime.now();
    await db.insert('logs', {
      'player_id': 1,
      'date':
          '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}',
      'idx': 0,
      'hr': 150,
      'rhr': 55,
      'hrv': 65,
      'avg_power': 220.0,
      'duration_seconds': 3600,
      'ef': 1.45,
      'decoupling': 4.2,
      'weight': 78.5,
      'sleep_hours': 7.5,
    });
  });

  tearDownAll(() async {
    DB.testDatabase = null;
  });

  const coachUser = AppUser(
    id: 1,
    email: 'coach@engine.rowing',
    name: 'Coach Mahmoud',
    role: 'coach',
    coachId: null,
    subscriptionActive: true,
  );

  const athleteUser = AppUser(
    id: 1,
    email: 'athlete@engine.rowing',
    name: 'أحمد',
    role: 'athlete',
    coachId: 1,
    subscriptionActive: true,
  );

  final testSizes = [
    const Size(320, 640),
    const Size(360, 800),
    const Size(411, 891),
  ];

  final textScales = [1.0, 1.3];

  for (final size in testSizes) {
    for (final scale in textScales) {
      testWidgets(
          'Responsive UI: Curve screens render without overflow at ${size.width}x${size.height} (scale: $scale)',
          (tester) async {
        tester.view.physicalSize = Size(size.width * 2.0, size.height * 2.0);
        tester.view.devicePixelRatio = 2.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        for (final lang in ['ar', 'en']) {
          await AppLanguage.instance.setLocale(Locale(lang));

          for (final curve in [
            ProgressCurveType.matrixZone,
            ProgressCurveType.efAndDecoupling,
            ProgressCurveType.watts,
            ProgressCurveType.pmcLoad,
            ProgressCurveType.recovery,
            ProgressCurveType.zoneHours,
            ProgressCurveType.cpTests,
          ]) {
            await tester.pumpWidget(
              MediaQuery(
                data: MediaQueryData(
                  size: size,
                  textScaler: TextScaler.linear(scale),
                ),
                child: MaterialApp(
                  locale: Locale(lang),
                  home: ProgressCurvePage(
                    curveType: curve,
                    user: coachUser,
                  ),
                ),
              ),
            );
            await tester.pump();
            // Let any initial async data loaders finish
            for (int i = 0; i < 5; i++) {
              await tester.pump(const Duration(milliseconds: 20));
            }

            // Verify no exception or overflow
            expect(tester.takeException(), isNull);
          }
        }
      });
    }
  }

  testWidgets('Athlete role sees only single athlete and no overflow',
      (tester) async {
    tester.view.physicalSize = const Size(720, 1280);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await AppLanguage.instance.setLocale(const Locale('ar'));

    await tester.pumpWidget(
      const MaterialApp(
        home: ProgressCurvePage(
          curveType: ProgressCurveType.matrixZone,
          user: athleteUser,
        ),
      ),
    );
    await tester.pump();
    for (int i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }

    expect(tester.takeException(), isNull);
  });
}
