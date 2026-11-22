import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:rowing_app/app_strings.dart';
import 'package:rowing_app/auth_service.dart';
import 'package:rowing_app/db.dart';
import 'package:rowing_app/heart_rate_zones.dart';
import 'package:rowing_app/progress_calcs.dart';
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
        kind TEXT,
        PRIMARY KEY(player_id, date, idx)
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS matrix_zone_config(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        indicator_key TEXT NOT NULL,
        weight REAL NOT NULL,
        direction TEXT DEFAULT 'up',
        sort_order INTEGER DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS progress_baseline_config(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        min_workouts INTEGER DEFAULT 3,
        max_window INTEGER DEFAULT 5,
        convergence_pct REAL DEFAULT 3.0,
        movement_threshold_pct REAL DEFAULT 1.0
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
        PRIMARY KEY(player_id, date)
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sessions(
        date TEXT,
        idx INTEGER,
        kind TEXT,
        zone TEXT,
        time TEXT,
        PRIMARY KEY(date, idx)
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

    // Seed initial players and workouts
    final today = DateTime.now();
    final todayStr =
        '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    for (int i = 1; i <= 10; i++) {
      await db.insert('players', {
        'id': i,
        'name': 'اللاعب $i',
        'mhr': 190 + i,
        'active': 1,
      });
      await db.insert('logs', {
        'player_id': i,
        'date': todayStr,
        'idx': 0,
        'hr': 150,
        'rhr': 55,
        'hrv': 65,
        'avg_power': 200.0 + (i * 10),
        'duration_seconds': 3600,
        'ef': 1.45,
        'decoupling': 4.2,
        'zone': 'Zone 2 - UT2',
        'kind': 'Erg',
      });
    }
  });

  tearDownAll(() async {
    DB.testDatabase = null;
  });

  group('1. محرك حسابات خط الأساس (computeBaseline)', () {
    test('أقل من 3 تمرينات لا يحسب خط أساس (hasEnoughData = false)', () {
      final workouts = [
        {'date': '2026-11-01', 'avg_power': 200.0},
        {'date': '2026-11-02', 'avg_power': 202.0},
      ];
      final res = ProgressCalcs.computeBaseline(
        workouts: workouts,
        metricKey: 'watts',
      );
      expect(res.hasEnoughData, isFalse);
      expect(res.currentBaseline, isNull);
    });

    test('3 تمرينات متقاربة (<= 3%) تحسب خط الأساس بدقة', () {
      // 200, 202, 201: avg = 201, max-min = 2, avg*0.03 = 6.03 => متقاربة
      final workouts = [
        {'date': '2026-11-01', 'avg_power': 200.0},
        {'date': '2026-11-02', 'avg_power': 202.0},
        {'date': '2026-11-03', 'avg_power': 201.0},
      ];
      final res = ProgressCalcs.computeBaseline(
        workouts: workouts,
        metricKey: 'watts',
      );
      expect(res.hasEnoughData, isTrue);
      expect(res.currentBaseline, closeTo(201.0, 0.01));
      expect(res.historyPoints.length, equals(1));
    });

    test('توسيع النافذة حتى 5 تمرينات إذا لم تتقارب أول 3 تمرينات', () {
      // 180, 220, 200 (غير متقاربة لأن الفارق 40 > 200*0.03)
      // ثم 200, 201 (آخر 3 تمرينات 200, 200, 201 متقاربة)
      final workouts = [
        {'date': '2026-11-01', 'avg_power': 180.0},
        {'date': '2026-11-02', 'avg_power': 220.0},
        {'date': '2026-11-03', 'avg_power': 200.0},
        {'date': '2026-11-04', 'avg_power': 200.0},
        {'date': '2026-11-05', 'avg_power': 201.0},
      ];
      final res = ProgressCalcs.computeBaseline(
        workouts: workouts,
        metricKey: 'watts',
      );
      expect(res.hasEnoughData, isTrue);
      expect(res.currentBaseline, isNotNull);
    });

    test('خط الأساس يتحرك صعوداً أو هبوطاً عند تغير المتوسط >= 1%', () {
      final workouts = [
        {'date': '2026-11-01', 'avg_power': 200.0},
        {'date': '2026-11-02', 'avg_power': 200.0},
        {'date': '2026-11-03', 'avg_power': 200.0}, // baseline = 200
        {'date': '2026-11-04', 'avg_power': 210.0},
        {'date': '2026-11-05', 'avg_power': 210.0},
        {
          'date': '2026-11-06',
          'avg_power': 210.0
        }, // new avg = 210, diff = 5% >= 1% => updates
      ];
      final res = ProgressCalcs.computeBaseline(
        workouts: workouts,
        metricKey: 'watts',
      );
      expect(res.hasEnoughData, isTrue);
      expect(res.currentBaseline, closeTo(210.0, 0.01));
      expect(res.historyPoints.length, equals(2));
    });

    test('فصل خط أساس بداية الفترة عن خط الأساس الحالي', () {
      final workouts = [
        {'date': '2026-10-01', 'avg_power': 200.0},
        {'date': '2026-10-02', 'avg_power': 200.0},
        {'date': '2026-10-03', 'avg_power': 200.0},
        {'date': '2026-11-10', 'avg_power': 220.0},
        {'date': '2026-11-11', 'avg_power': 220.0},
        {'date': '2026-11-12', 'avg_power': 220.0},
      ];
      final res = ProgressCalcs.computeBaseline(
        workouts: workouts,
        metricKey: 'watts',
        periodStartDate: DateTime(2026, 11, 1),
      );
      expect(res.startOfPeriodBaseline, closeTo(200.0, 0.01));
      expect(res.currentBaseline, closeTo(220.0, 0.01));
    });
  });

  group('2. محرك حسابات Matrix Zone ومنحنى القدرة', () {
    test('حساب درجات المؤشرات الأربعة وقاعدة Decoupling التنازلية', () {
      // 3 تمرينات سابقة لبناء خط الأساس + تمرين في الفترة الحالية
      final logs = [
        {
          'date': '2026-10-01',
          'avg_power': 200.0,
          'ef': 1.5,
          'decoupling': 5.0,
          'duration_seconds': 3600,
          'zone': 'Zone 2 - UT2',
          'kind': 'Erg',
        },
        {
          'date': '2026-10-02',
          'avg_power': 200.0,
          'ef': 1.5,
          'decoupling': 5.0,
          'duration_seconds': 3600,
          'zone': 'Zone 2 - UT2',
          'kind': 'Erg',
        },
        {
          'date': '2026-10-03',
          'avg_power': 200.0,
          'ef': 1.5,
          'decoupling': 5.0,
          'duration_seconds': 3600,
          'zone': 'Zone 2 - UT2',
          'kind': 'Erg',
        },
        // تمرين الفترة الحالية: الواط زاد 210 (+5%)، EF زاد 1.575 (+5%)، Decoupling انخفض لـ 3.0 (تحسن +2.0)
        {
          'date': '2026-11-10',
          'avg_power': 210.0,
          'ef': 1.575,
          'decoupling': 3.0,
          'duration_seconds': 3600,
          'zone': 'Zone 2 - UT2',
          'kind': 'Erg',
        },
      ];

      final res = ProgressCalcs.computeMatrixZoneForAthlete(
        playerId: 1,
        athleteName: 'بطل التجديف',
        workoutKind: 'Erg',
        allAthleteLogs: logs,
        periodStart: DateTime(2026, 11, 1),
        periodEnd: DateTime(2026, 11, 30),
      );

      final z2 = res.detailsByZone['Z2'];
      expect(z2, isNotNull);
      expect(z2!.hasEnoughData, isTrue);
      // طول الشريط = أفضل واط في الفترة الحالية (210)
      expect(z2.bestWatts, closeTo(210.0, 0.1));

      // درجة Decoupling موجبة لأن الانخفاض من 5 إلى 3 تحسن
      final decScore = z2.metricScores['decoupling'];
      expect(decScore?.score, isNotNull);
      expect(decScore!.score!, isPositive);

      // درجة الزون محسوبة وموجبة ومحصورة بين -15 و +15
      expect(z2.zoneScore, isNotNull);
      expect(z2.zoneScore!, inInclusiveRange(-15.0, 15.0));

      // عرض الشريط متزايد بين 14 و 32
      expect(z2.barWidth, inInclusiveRange(14.0, 32.0));

      // منحنى القدرة متناقص مع درجة الزون (أقل قيمة = أفضل قدرة)
      expect(z2.capacityCurveValue, isNotNull);
      expect(z2.capacityCurveValue!, lessThan(145.0));
    });

    test('إعادة توزيع الأوزان عند غياب أحد المؤشرات', () {
      // بيانات تحتوي على واط فقط بدون decoupling
      final logs = [
        {'date': '2026-11-01', 'avg_power': 200.0, 'zone': 'Z2', 'kind': 'Erg'},
        {'date': '2026-11-02', 'avg_power': 200.0, 'zone': 'Z2', 'kind': 'Erg'},
        {'date': '2026-11-03', 'avg_power': 200.0, 'zone': 'Z2', 'kind': 'Erg'},
        {'date': '2026-11-15', 'avg_power': 210.0, 'zone': 'Z2', 'kind': 'Erg'},
      ];

      final res = ProgressCalcs.computeMatrixZoneForAthlete(
        playerId: 1,
        athleteName: 'اللاعب 1',
        workoutKind: 'Erg',
        allAthleteLogs: logs,
        periodStart: DateTime(2026, 11, 10),
        periodEnd: DateTime(2026, 11, 20),
      );

      final z2 = res.detailsByZone['Z2'];
      expect(z2, isNotNull);
      expect(z2!.hasEnoughData, isTrue);
      // يحسب درجة الزون بدون كراش
      expect(z2.zoneScore, isNotNull);
    });

    test('تصاعد منحنى القدرة عبر المناطق التدريبية السبعة', () {
      final logs = [
        {
          'date': '2026-11-01',
          'avg_power': 150.0,
          'zone': 'Zone 1 - UT3',
          'kind': 'Erg'
        },
        {
          'date': '2026-11-01',
          'avg_power': 180.0,
          'zone': 'Zone 2 - UT2',
          'kind': 'Erg'
        },
        {
          'date': '2026-11-01',
          'avg_power': 220.0,
          'zone': 'Zone 3 - UT1',
          'kind': 'Erg'
        },
        {
          'date': '2026-11-01',
          'avg_power': 250.0,
          'zone': 'Zone 4 - AT',
          'kind': 'Erg'
        },
        {
          'date': '2026-11-01',
          'avg_power': 280.0,
          'zone': 'Threshold - AT',
          'kind': 'Erg'
        },
        {
          'date': '2026-11-01',
          'avg_power': 310.0,
          'zone': 'Zone 5 - TR',
          'kind': 'Erg'
        },
        {
          'date': '2026-11-01',
          'avg_power': 350.0,
          'zone': 'VO2 max - AN',
          'kind': 'Erg'
        },
      ];

      final res = ProgressCalcs.computeMatrixZoneForAthlete(
        playerId: 1,
        athleteName: 'بطل',
        workoutKind: 'Erg',
        allAthleteLogs: logs,
        periodStart: DateTime(2026, 11, 1),
        periodEnd: DateTime(2026, 11, 2),
      );

      final zones = HeartRateZones.orderedZones;
      for (int i = 0; i < zones.length - 1; i++) {
        final d1 = res.detailsByZone[zones[i]];
        final d2 = res.detailsByZone[zones[i + 1]];
        if (d1?.capacityCurveValue != null && d2?.capacityCurveValue != null) {
          expect(d1!.capacityCurveValue!, lessThan(d2!.capacityCurveValue!));
        }
      }
    });
  });

  group('3. إعدادات المؤشرات وحفظها في قاعدة البيانات', () {
    test('حفظ واسترجاع إعدادات المؤشرات مع التحقق من الترتيب', () async {
      const customConfigs = [
        MatrixZoneIndicatorConfig(
            key: 'watts', weight: 50.0, direction: 'up', sortOrder: 0),
        MatrixZoneIndicatorConfig(
            key: 'ef', weight: 30.0, direction: 'up', sortOrder: 1),
        MatrixZoneIndicatorConfig(
            key: 'time', weight: 20.0, direction: 'up', sortOrder: 2),
      ];

      await ProgressCalcs.saveMatrixZoneConfig(customConfigs);
      final loaded = await ProgressCalcs.loadMatrixZoneConfig();

      expect(loaded.length, equals(3));
      expect(loaded[0].key, equals('watts'));
      expect(loaded[0].weight, equals(50.0));
      expect(loaded[1].key, equals('ef'));
      expect(loaded[2].key, equals('time'));
    });
  });

  group('4. اختبارات الواجهة واستجابة الشاشة (Widget & Responsive)', () {
    const coachUser = AppUser(
      id: 1,
      email: 'coach@engine.rowing',
      name: 'Coach Mahmoud',
      role: 'coach',
      subscriptionActive: true,
    );

    testWidgets(
        'Matrix Zone يعرض لوحة مقارنة اللاعبين والشرائط والأعمدة بدون كراش',
        (tester) async {
      await AppLanguage.instance.setLocale(const Locale('ar'));

      await tester.runAsync(() async {
        await tester.pumpWidget(
          const MaterialApp(
            locale: Locale('ar'),
            home: ProgressCurvePage(
              curveType: ProgressCurveType.matrixZone,
              user: coachUser,
            ),
          ),
        );
        for (int i = 0; i < 15; i++) {
          await Future.delayed(const Duration(milliseconds: 40));
          await tester.pump();
        }
      });
      await tester.pump();

      // التحقق من ظهور عنوان Matrix Zone والفلتر
      final s = AppStrings.of(tester.element(find.byType(ProgressCurvePage)));
      expect(find.text(s.matrixZoneTitle), findsWidgets);

      // التحقق من ظهور عبارة "منحنى تقديري فقط"
      expect(find.text(s.estimatedCurveNotice), findsWidgets);

      // التحقق من عدم ذكر مصطلح lactate إطلاقاً في الواجهة
      expect(find.textContaining('lactate', findRichText: true), findsNothing);
      expect(find.textContaining('لاكتات', findRichText: true), findsNothing);
    });

    testWidgets('استجابة الشاشة لمختلف الأحجام بدون أي أخطاء تجاوز (Overflow)',
        (tester) async {
      final sizes = [
        const Size(320, 640),
        const Size(360, 800),
        const Size(411, 891),
      ];

      for (final sz in sizes) {
        tester.view.physicalSize = Size(sz.width * 2.0, sz.height * 2.0);
        tester.view.devicePixelRatio = 2.0;

        await tester.pumpWidget(
          MediaQuery(
            data: MediaQueryData(size: sz),
            child: const MaterialApp(
              home: ProgressCurvePage(
                curveType: ProgressCurveType.matrixZone,
                user: coachUser,
              ),
            ),
          ),
        );
        await tester.pump();
        for (int i = 0; i < 5; i++) {
          await tester.pump(const Duration(milliseconds: 20));
        }

        expect(tester.takeException(), isNull);
      }
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
    });
  });
}
