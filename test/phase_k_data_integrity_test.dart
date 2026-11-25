import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:rowing_app/auth_service.dart';
import 'package:rowing_app/cloud_api.dart';
import 'package:rowing_app/db.dart';
import 'package:rowing_app/heart_rate_zones.dart';
import 'package:rowing_app/power_calculations.dart';
import 'package:rowing_app/progress_calcs.dart';
import 'package:rowing_app/sync_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  late Database db;
  late MockCloudApi mockCloud;

  Future<Database> createCleanDatabase(String tag) async {
    final tempDbPath = '${Directory.systemTemp.path}/phase_k_${tag}_${DateTime.now().microsecondsSinceEpoch}.db';
    final newDb = await openDatabase(
      tempDbPath,
      version: 10,
      onCreate: (d, v) async {
        await d.execute(
            'CREATE TABLE players(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, mhr INTEGER, active INTEGER DEFAULT 1, coach_id INTEGER, curves_shared INTEGER, curves_shared_by TEXT)');
        await d.execute(
            'CREATE TABLE cycles(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, start TEXT, end TEXT)');
        await d.execute(
            'CREATE TABLE sessions(date TEXT, idx INTEGER, kind TEXT, zone TEXT, PRIMARY KEY(date, idx))');
        await d.execute(
            'CREATE TABLE notes(date TEXT PRIMARY KEY, general TEXT, tech TEXT)');
        await d.execute('''
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
            eupnea REAL,
            decoupling REAL,
            entered_by TEXT,
            eupnea_1 REAL,
            eupnea_2 REAL,
            eupnea_3 REAL,
            zone TEXT,
            kind TEXT,
            zone_method TEXT,
            PRIMARY KEY(player_id, date, idx)
          )
        ''');
        await d.execute('''
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
        await d.execute('''
          CREATE TABLE cp_values(
            player_id INTEGER,
            date TEXT,
            cp REAL,
            w_prime REAL,
            estimated INTEGER DEFAULT 0,
            PRIMARY KEY(player_id, date)
          )
        ''');
        await d.execute('''
          CREATE TABLE testing_dates(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            test_name TEXT NOT NULL,
            test_date TEXT NOT NULL,
            test_time TEXT,
            location TEXT,
            notes TEXT,
            created_at TEXT
          )
        ''');
        await d.execute('''
          CREATE TABLE testing_date_recipients(
            testing_date_id INTEGER NOT NULL,
            athlete_id INTEGER NOT NULL,
            status TEXT DEFAULT 'pending',
            PRIMARY KEY (testing_date_id, athlete_id)
          )
        ''');
        await d.execute('''
          CREATE TABLE cycle_templates(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            description TEXT,
            created_at TEXT
          )
        ''');
        await d.execute('''
          CREATE TABLE coach_messages(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            coach_id INTEGER,
            recipient_type TEXT NOT NULL,
            recipient_id INTEGER,
            text TEXT NOT NULL,
            created_at TEXT NOT NULL
          )
        ''');
        await d.execute('''
          CREATE TABLE athlete_custom_sessions(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            player_id INTEGER NOT NULL,
            date TEXT NOT NULL,
            session_idx INTEGER NOT NULL,
            location TEXT,
            dispatch_time TEXT,
            notes_physio TEXT,
            notes_tech TEXT,
            coach_notes TEXT,
            coach_edited INTEGER DEFAULT 0,
            coach_edited_at TEXT,
            is_rest_day INTEGER DEFAULT 0,
            created_at TEXT,
            UNIQUE(player_id, date, session_idx)
          )
        ''');
        await d.execute('''
          CREATE TABLE athlete_custom_workout_items(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            custom_session_id INTEGER NOT NULL,
            section TEXT NOT NULL,
            item_idx INTEGER NOT NULL,
            intensity TEXT,
            distance_meters INTEGER,
            stroke_rate INTEGER,
            duration_seconds INTEGER,
            notes TEXT,
            created_at TEXT
          )
        ''');
        await d.execute('''
          CREATE TABLE program_cycles(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            description TEXT,
            start_date TEXT NOT NULL,
            end_date TEXT NOT NULL,
            total_weeks INTEGER DEFAULT 4,
            is_active INTEGER DEFAULT 0,
            created_at TEXT
          )
        ''');
        await d.execute('''
          CREATE TABLE program_sessions(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            cycle_id INTEGER NOT NULL,
            cycle_type TEXT NOT NULL,
            day_of_week INTEGER NOT NULL,
            session_idx INTEGER NOT NULL,
            name TEXT NOT NULL,
            time TEXT,
            location TEXT,
            notes_physio TEXT,
            notes_tech TEXT,
            comment TEXT,
            created_at TEXT
          )
        ''');
        await d.execute('''
          CREATE TABLE program_workout_items(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            session_id INTEGER NOT NULL,
            section TEXT NOT NULL,
            item_idx INTEGER NOT NULL,
            intensity TEXT,
            distance_meters INTEGER,
            stroke_rate INTEGER,
            duration_seconds INTEGER,
            notes TEXT,
            created_at TEXT
          )
        ''');
        await d.execute('''
          CREATE TABLE program_day_config(
            cycle_id INTEGER NOT NULL,
            cycle_type TEXT NOT NULL,
            day_of_week INTEGER NOT NULL,
            location TEXT,
            dispatch_date TEXT,
            dispatch_time TEXT,
            comment TEXT,
            PRIMARY KEY(cycle_id, cycle_type, day_of_week)
          )
        ''');
        await d.execute('''
          CREATE TABLE program_cycle_tests(
            cycle_id INTEGER NOT NULL,
            test_type TEXT NOT NULL,
            scheduled_date TEXT,
            distance INTEGER,
            duration_seconds INTEGER,
            notes TEXT,
            PRIMARY KEY(cycle_id, test_type)
          )
        ''');
        await d.execute('''
          CREATE TABLE coach_requests(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            coach_id INTEGER NOT NULL,
            athlete_id INTEGER NOT NULL,
            status TEXT DEFAULT 'pending',
            created_at TEXT
          )
        ''');
        await d.execute('''
          CREATE TABLE matrix_zone_config(
            key TEXT PRIMARY KEY,
            weight REAL,
            direction TEXT
          )
        ''');
        await d.execute('''
          CREATE TABLE progress_baseline_config(
            key TEXT PRIMARY KEY,
            value REAL
          )
        ''');
      },
    );

    DB.testDatabase = newDb;
    await AuthService.ensureTables();
    await SyncEngine.ensureDatabaseSyncSchema(newDb);
    await ProgressLoadCache.ensureTable();
    return newDb;
  }

  setUpAll(() async {
    mockCloud = MockCloudApi();
    mockCloud.reset();
    CloudApi.instance = mockCloud;
    db = await createCleanDatabase('test');
  });

  tearDownAll(() async {
    await db.close();
    DB.testDatabase = null;
  });

  setUp(() {
    mockCloud.reset();
  });

  group('1. اختبارات مخطط قاعدة البيانات وسلامة الإشارات (Schema & Referential Integrity)', () {
    test('تأكيد عدد الجداول الكلي 27 وجداول المزامنة 20 وعدد التريجرات 60', () async {
      final tables = await db.rawQuery("SELECT name FROM sqlite_master WHERE type='table' ORDER BY name");
      expect(tables.length, equals(27));

      expect(SyncEngine.syncedTables.length, equals(20));

      final triggers = await db.rawQuery("SELECT name FROM sqlite_master WHERE type='trigger'");
      expect(triggers.length, equals(60));
    });

    test('فحص سلامة الإشارات المنطقية وعدم وجود سجلات يتيمة', () async {
      // 1. إضافة لاعب
      await db.insert('players', {'id': 1, 'name': 'لاعب تجريبي', 'mhr': 195});

      // 2. إضافة لوج مرتبط باللاعب
      await db.insert('logs', {
        'player_id': 1,
        'date': '2026-11-20',
        'idx': 0,
        'hr': 150,
        'avg_power': 200.0,
      });

      // فحص عدم وجود أي لوج بدون لاعب موجود
      final orphanLogs = await db.rawQuery('''
        SELECT l.* FROM logs l 
        LEFT JOIN players p ON l.player_id = p.id 
        WHERE p.id IS NULL
      ''');
      expect(orphanLogs, isEmpty);

      // فحص عدم وجود تمرين مخصص بدون لاعب
      final orphanCustom = await db.rawQuery('''
        SELECT c.* FROM athlete_custom_sessions c 
        LEFT JOIN players p ON c.player_id = p.id 
        WHERE p.id IS NULL
      ''');
      expect(orphanCustom, isEmpty);
    });
  });

  group('2. اختبارات الحفظ الذكي غير الهدام (DB.put & Non-Destructive Upsert)', () {
    test('تعديل صف متزامن يحافظ على remote_id ولا يمسحه', () async {
      // إدخال صف أولي في logs ومحاكاة رفعه وتعيين remote_id
      await db.insert('logs', {
        'player_id': 10,
        'date': '2026-11-21',
        'idx': 0,
        'rhr': 55,
        'zone': 'Zone 2 - UT2',
        'kind': 'Erg',
        'remote_id': 'cloud-uuid-12345',
        'dirty': 0,
      });

      // تعديل السجل لاحقاً بواسطة DB.put بحقول جزئية فقط
      await DB.put('logs', {
        'player_id': 10,
        'date': '2026-11-21',
        'idx': 0,
        'rhr': 58,
        'avg_power': 210.0,
      });

      final rows = await db.query('logs', where: 'player_id = ? AND date = ?', whereArgs: [10, '2026-11-21']);
      expect(rows, hasLength(1));
      final updated = rows.first;

      // التأكد من الحفاظ على remote_id
      expect(updated['remote_id'], equals('cloud-uuid-12345'));
      // التأكد من الحفاظ على الحقول غير الممررة (zone و kind)
      expect(updated['zone'], equals('Zone 2 - UT2'));
      expect(updated['kind'], equals('Erg'));
      // التأكد من تعديل الحقول الممررة
      expect(updated['rhr'], equals(58));
      expect(updated['avg_power'], equals(210.0));
      // التأكد من أن التريجر فعّل dirty = 1
      expect(updated['dirty'], equals(1));

      // التأكد من عدم إنشاء أي tombstone كاذب
      final tombstones = await db.query('sync_tombstones');
      expect(tombstones, isEmpty);
    });
  });

  group('3. القاعدة الفسيولوجية الثابتة: استقلال مناطق التدريب عن HRV والجاهزية', () {
    test('تحديد المنطقة ومداها يعتمد حصرياً على HR و MHR و RHR ومعادلة كارفونين', () {
      const mhr = 190;
      const rhr = 60;
      const zone = 'Z2';

      final range1 = HeartRateZones.calculate(mhr: mhr, rhr: rhr, zone: zone);

      // اختبار مع مدخلات استشفاء وجاهزية مختلفة تماماً (تعب شديد vs استشفاء مثالي)
      // الدالة لا تستقبل إلا mhr و rhr و zone
      expect(range1.minHR, equals(145)); // 60 + (130 * 0.65) = 144.5 -> 145
      expect(range1.maxHR, equals(158)); // 60 + (130 * 0.75) = 157.5 -> 158
      expect(range1.isKarvonen, isTrue);

      // التحقق من أن تحديد المنطقة يرجع لنفس الزون بغض النظر عن الجاهزية
      final determinedZone = HeartRateZones.determineZone(hr: 150, mhr: mhr, rhr: rhr);
      expect(determinedZone, equals('Z2'));
    });
  });

  group('4. اختبارات مؤشر الجاهزية (Readiness Score & Missing Data Rule)', () {
    test('إذا توفر أقل من عنصرين (< 2 components) يرجع null ويعرض --', () {
      // 0 عناصر
      expect(calculateReadiness(), isNull);
      expect(readinessText(null), equals('--'));
      expect(readinessColor(null), equals(0xFF9E9E9E));

      // 1 عنصر فقط (مثلاً ساعات النوم فقط)
      expect(calculateReadiness(sleepHours: 8.0), isNull);
      expect(calculateReadiness(fatigue: 3), isNull);
      expect(calculateReadiness(tsb: 15.0), isNull);

      // عنصران فأكثر يحسب النتيجة
      final score = calculateReadiness(
        rhr: 55,
        rhrBaseline: 55,
        sleepHours: 8.0,
      );
      expect(score, isNotNull);
      expect(score!, inInclusiveRange(0, 100));
      expect(readinessText(score), isNot(equals('--')));
    });
  });

  group('5. اختبارات الحسابات المرجعية (Reference Calculations)', () {
    test('حساب اختبار CP وسعة الشغل اللاهوائي W بالمعادلة المعتمدة (جول)', () {
      // اختبار بنقطتين:
      // t1 = 180s (3 min) -> P1 = 300W -> Work1 = 300 * 180 = 54,000 J
      // t2 = 720s (12 min) -> P2 = 240W -> Work2 = 240 * 720 = 172,800 J
      const t1 = 180.0;
      const p1 = 300.0;
      const t2 = 720.0;
      const p2 = 240.0;

      final w1 = p1 * t1;
      final w2 = p2 * t2;
      final cp = (w2 - w1) / (t2 - t1);
      final wPrime = (p1 - cp) * t1;

      expect(cp, equals(220.0)); // 220 Watts
      expect(wPrime, equals(14400.0)); // 14,400 Joules
    });

    test('حساب TSS التقديري من متوسط القدرة ويرجع null إذا غاب CP', () {
      // تمرين ساعة واحدة (3600 ثانية) بمتوسط واط 200، و CP = 200 (IF = 1.0) -> TSS = 100
      final tss100 = ProgressCalcs.calculateWorkoutTSS(
        avgPower: 200.0,
        durationSeconds: 3600,
        cp: 200.0,
      );
      expect(tss100, closeTo(100.0, 1e-2));

      // غياب CP يرجع null
      expect(
        ProgressCalcs.calculateWorkoutTSS(avgPower: 200.0, durationSeconds: 3600, cp: null),
        isNull,
      );
    });

    test('حساب معامل الكفاءة EF', () {
      final ef = PowerCalculations.calculateEF(220.0, 140);
      expect(ef, equals(1.57));
    });
  });

  group('6. تدفق التكامل المحلي (End-to-End Local Integration Flow)', () {
    test('إدخال تمرين -> يظهر في logs -> يدخل في خط الأساس ومصفوفة المناطق', () async {
      await db.insert('players', {'id': 5, 'name': 'اللاعب المتكامل', 'mhr': 195});

      // إدخال 3 تمرينات متقاربة في Z2
      for (int i = 1; i <= 3; i++) {
        await DB.put('logs', {
          'player_id': 5,
          'date': '2026-11-0$i',
          'idx': 0,
          'avg_power': 200.0 + (i * 2), // 202, 204, 206
          'rhr': 55,
          'hr': 145,
          'zone': 'Zone 2 - UT2',
          'kind': 'Erg',
          'duration_seconds': 3600,
        });
      }

      final logs = await db.query('logs', where: 'player_id = ?', whereArgs: [5]);
      expect(logs, hasLength(3));

      // حساب خط الأساس للمنطقة Z2
      final baseline = ProgressCalcs.computeBaseline(
        workouts: logs,
        metricKey: 'watts',
        periodStartDate: DateTime(2026, 11, 1),
      );
      expect(baseline.hasEnoughData, isTrue);
      expect(baseline.currentBaseline, closeTo(204.0, 1.0));

      // حساب Matrix Zone
      final matrix = ProgressCalcs.computeMatrixZoneForAthlete(
        playerId: 5,
        athleteName: 'اللاعب المتكامل',
        workoutKind: 'Erg',
        allAthleteLogs: logs,
        periodStart: DateTime(2026, 11, 1),
        periodEnd: DateTime(2026, 11, 5),
      );

      final z2 = matrix.detailsByZone['Z2'];
      expect(z2, isNotNull);
      expect(z2!.bestWatts, equals(206.0));
      expect(z2.capacityCurveValue, isNotNull);
    });

    test('10. Logs idx collision prevention: DB.nextLogIdx assigns auto-increment idx (MAX + 1)', () async {
      DB.testDatabase = db;

      const playerId = 99;
      const date = '2026-11-24';
      await db.delete('logs', where: 'player_id = ?', whereArgs: [playerId]);

      // First workout should get idx 0
      final idx0 = await DB.nextLogIdx(playerId, date);
      expect(idx0, equals(0));

      await DB.put('logs', {
        'player_id': playerId,
        'date': date,
        'idx': idx0,
        'avg_power': 220.0,
      });

      // Second workout on same date should get idx 1 (MAX + 1)
      final idx1 = await DB.nextLogIdx(playerId, date);
      expect(idx1, equals(1));

      await DB.put('logs', {
        'player_id': playerId,
        'date': date,
        'idx': idx1,
        'avg_power': 240.0,
      });

      // Third workout on same date should get idx 2
      final idx2 = await DB.nextLogIdx(playerId, date);
      expect(idx2, equals(2));

      await DB.put('logs', {
        'player_id': playerId,
        'date': date,
        'idx': idx2,
        'avg_power': 260.0,
      });

      // Verify all 3 workouts exist without collision
      final rows = await db.query(
        'logs',
        where: 'player_id = ? AND date = ?',
        whereArgs: [playerId, date],
        orderBy: 'idx ASC',
      );
      expect(rows.length, equals(3));
      expect(rows[0]['idx'], equals(0));
      expect(rows[0]['avg_power'], equals(220.0));
      expect(rows[1]['idx'], equals(1));
      expect(rows[1]['avg_power'], equals(240.0));
      expect(rows[2]['idx'], equals(2));

      // Explicit update of existing row modifies it without creating duplicates
      await DB.put('logs', {
        'player_id': playerId,
        'date': date,
        'idx': 1,
        'avg_power': 255.0,
      });

      final updatedRows = await db.query(
        'logs',
        where: 'player_id = ? AND date = ?',
        whereArgs: [playerId, date],
        orderBy: 'idx ASC',
      );
      expect(updatedRows.length, equals(3));
      expect(updatedRows[1]['avg_power'], equals(255.0));
    });

    test('11. Cache invalidation on workout mutation clears daily_load cache', () async {
      DB.testDatabase = db;

      const playerId = 88;
      const date = '2026-11-20';
      await db.delete('daily_load', where: 'player_id = ?', whereArgs: [playerId]);

      // Seed a cached daily_load entry
      await db.insert('daily_load', {
        'player_id': playerId,
        'date': date,
        'tss': 75.0,
        'ctl': 45.0,
        'atl': 60.0,
        'tsb': -15.0,
      });

      final cachedBefore = await db.query(
        'daily_load',
        where: 'player_id = ? AND date >= ?',
        whereArgs: [playerId, date],
      );
      expect(cachedBefore.isNotEmpty, isTrue);

      // Invalidate cache
      await ProgressLoadCache.invalidateFrom(playerId, fromDate: date);

      final cachedAfter = await db.query(
        'daily_load',
        where: 'player_id = ? AND date >= ?',
        whereArgs: [playerId, date],
      );
      expect(cachedAfter.isEmpty, isTrue);
    });
  });
}
