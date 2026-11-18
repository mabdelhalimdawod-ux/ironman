import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:rowing_app/auth_service.dart';
import 'package:rowing_app/cloud_api.dart';
import 'package:rowing_app/sync_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  late MockCloudApi mockCloud;
  late AppUser coachUser;
  late AppUser athlete1User;
  late AppUser athlete2User;

  setUp(() {
    mockCloud = MockCloudApi();
    mockCloud.reset();
    CloudApi.instance = mockCloud;

    coachUser = const AppUser(
      id: 1,
      email: 'coach@engine.rowing',
      name: 'الكوتش',
      role: 'coach',
      subscriptionActive: true,
    );

    athlete1User = const AppUser(
      id: 101,
      email: 'athlete1@engine.rowing',
      name: 'أحمد اللاعب',
      role: 'athlete',
      coachId: 1,
      subscriptionActive: true,
    );

    athlete2User = const AppUser(
      id: 102,
      email: 'athlete2@engine.rowing',
      name: 'محمود اللاعب',
      role: 'athlete',
      coachId: 1,
      subscriptionActive: true,
    );
  });

  /// إنشاء قاعدة بيانات v8 نظيفة في ملف مؤقت فريد
  Future<Database> createTestDb(String name) async {
    final tempDbPath = '${Directory.systemTemp.path}/rowing_${name}_${DateTime.now().microsecondsSinceEpoch}.db';
    return await openDatabase(
      tempDbPath,
      version: 8,
      onCreate: (d, v) async {
        await d.execute(
            'CREATE TABLE players(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, mhr INTEGER, active INTEGER DEFAULT 1, curves_shared INTEGER, curves_shared_by TEXT)');
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
            decoupling REAL,
            eupnea_1 REAL,
            eupnea_2 REAL,
            eupnea_3 REAL,
            entered_by TEXT,
            zone TEXT,
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
            method TEXT,
            PRIMARY KEY(player_id, date)
          )
        ''');
        await d.execute('''
          CREATE TABLE IF NOT EXISTS athlete_custom_sessions(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            player_id INTEGER NOT NULL,
            date TEXT NOT NULL,
            session_idx INTEGER NOT NULL,
            name TEXT,
            time TEXT,
            notes_physio TEXT,
            notes_tech TEXT,
            comment TEXT,
            edited_by TEXT,
            created_at TEXT,
            updated_at TEXT,
            UNIQUE(player_id, date, session_idx)
          )
        ''');
        await d.execute('''
          CREATE TABLE IF NOT EXISTS athlete_custom_workout_items(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            custom_session_id INTEGER NOT NULL,
            section TEXT NOT NULL,
            item_idx INTEGER NOT NULL,
            time TEXT,
            duration_minutes INTEGER,
            duration_seconds INTEGER,
            hr_percent REAL,
            hr_range TEXT,
            distance_meters INTEGER,
            reps INTEGER,
            kind TEXT,
            zone TEXT,
            details TEXT,
            UNIQUE(custom_session_id, section, item_idx)
          )
        ''');
        await d.execute(
            'CREATE TABLE IF NOT EXISTS progress_baseline_config(key TEXT PRIMARY KEY, value REAL)');
        await d.execute('''
          CREATE TABLE IF NOT EXISTS program_cycles (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            start_date TEXT NOT NULL,
            end_date TEXT NOT NULL,
            location TEXT DEFAULT '',
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            basic_reps INTEGER DEFAULT 3,
            secondary_reps INTEGER DEFAULT 1,
            notes_physio TEXT DEFAULT '',
            notes_tech TEXT DEFAULT '',
            comment TEXT DEFAULT ''
          )
        ''');
        await d.execute('''
          CREATE TABLE IF NOT EXISTS program_cycle_tests (
            cycle_id INTEGER NOT NULL,
            test_type TEXT NOT NULL,
            test_date TEXT DEFAULT '',
            target_value TEXT DEFAULT '',
            is_completed INTEGER DEFAULT 0,
            PRIMARY KEY (cycle_id, test_type)
          )
        ''');
        await d.execute('''
          CREATE TABLE IF NOT EXISTS program_day_config (
            cycle_id INTEGER NOT NULL,
            cycle_type TEXT NOT NULL,
            day_of_week INTEGER NOT NULL,
            location TEXT DEFAULT '',
            dispatch_date TEXT DEFAULT '',
            dispatch_time TEXT DEFAULT '',
            comment TEXT DEFAULT '',
            PRIMARY KEY (cycle_id, cycle_type, day_of_week)
          )
        ''');
        await d.execute('''
          CREATE TABLE IF NOT EXISTS program_sessions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            cycle_id INTEGER NOT NULL,
            cycle_type TEXT NOT NULL,
            day_of_week INTEGER NOT NULL,
            session_idx INTEGER NOT NULL,
            name TEXT NOT NULL,
            time TEXT NOT NULL,
            notes_physio TEXT DEFAULT '',
            notes_tech TEXT DEFAULT '',
            comment TEXT DEFAULT ''
          )
        ''');
        await d.execute('''
          CREATE TABLE IF NOT EXISTS program_workout_items (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            session_id INTEGER NOT NULL,
            section TEXT NOT NULL,
            item_idx INTEGER NOT NULL,
            time TEXT DEFAULT '',
            duration_minutes INTEGER DEFAULT 0,
            duration_seconds INTEGER DEFAULT 0,
            hr_percent INTEGER DEFAULT 0,
            hr_range TEXT DEFAULT '',
            distance_meters INTEGER DEFAULT 0,
            reps INTEGER DEFAULT 1,
            kind TEXT DEFAULT 'Erg',
            zone TEXT DEFAULT 'Z2',
            details TEXT DEFAULT ''
          )
        ''');
        await d.execute('''
          CREATE TABLE IF NOT EXISTS cycle_templates (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            cycle_id INTEGER,
            day_of_week INTEGER NOT NULL,
            slot_idx INTEGER NOT NULL,
            name TEXT DEFAULT '',
            time TEXT DEFAULT '',
            kind TEXT DEFAULT 'Erg',
            zone TEXT DEFAULT 'Z2'
          )
        ''');
        await d.execute('''
          CREATE TABLE IF NOT EXISTS testing_dates (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            test_name TEXT NOT NULL,
            test_date TEXT NOT NULL
          )
        ''');
        await d.execute('''
          CREATE TABLE IF NOT EXISTS testing_date_recipients (
            testing_date_id INTEGER NOT NULL,
            athlete_id INTEGER NOT NULL,
            PRIMARY KEY (testing_date_id, athlete_id)
          )
        ''');
        await d.execute('''
          CREATE TABLE IF NOT EXISTS coach_messages (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            athlete_id INTEGER NOT NULL,
            message TEXT NOT NULL,
            date TEXT NOT NULL,
            is_read INTEGER DEFAULT 0
          )
        ''');
        await d.execute('''
          CREATE TABLE IF NOT EXISTS matrix_zone_config (
            key TEXT PRIMARY KEY,
            value TEXT
          )
        ''');

        await SyncEngine.ensureDatabaseSyncSchema(d);
      },
    );
  }

  group('SyncEngine - Schema & Triggers', () {
    test('Schema includes all sync tables, columns and triggers', () async {
      final db = await createTestDb('schema_test');

      // التحقق من جداول المزامنة
      final stateTable = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name='sync_state'");
      expect(stateTable, isNotEmpty);

      final tombstonesTable = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name='sync_tombstones'");
      expect(tombstonesTable, isNotEmpty);

      final flagTable = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name='sync_flag'");
      expect(flagTable, isNotEmpty);

      // التحقق من أعمدة المزامنة في جدول logs
      final logCols = await db.rawQuery("PRAGMA table_info('logs')");
      final colNames = logCols.map((c) => c['name'] as String).toSet();
      expect(colNames.contains('remote_id'), isTrue);
      expect(colNames.contains('updated_at'), isTrue);
      expect(colNames.contains('dirty'), isTrue);

      // اختبار تريجر الإدخال التلقائي (Insert Trigger)
      await db.insert('sessions', {
        'date': '2026-11-20',
        'idx': 1,
        'kind': 'Erg',
        'zone': 'Zone 2 - UT2',
      });

      final rows = await db.query('sessions', where: 'date = ?', whereArgs: ['2026-11-20']);
      expect(rows, hasLength(1));
      expect(rows.first['dirty'], equals(1));
      expect(rows.first['updated_at'], isNotNull);

      // اختبار تريجر التعديل التلقائي (Update Trigger)
      await db.update(
        'sessions',
        {'kind': 'Water'},
        where: 'date = ?',
        whereArgs: ['2026-11-20'],
      );
      final updated = await db.query('sessions', where: 'date = ?', whereArgs: ['2026-11-20']);
      expect(updated.first['kind'], equals('Water'));
      expect(updated.first['dirty'], equals(1));

      // اختبار تريجر الحذف (Delete Trigger) والتسجيل في tombstones
      await db.delete('sessions', where: 'date = ?', whereArgs: ['2026-11-20']);
      final tombstones = await db.query('sync_tombstones');
      expect(tombstones, hasLength(1));
      expect(tombstones.first['table_name'], equals('sessions'));
      expect(tombstones.first['remote_key'], equals('2026-11-20_1'));

      await db.close();
    });

    test('DB upgrade from v7 to v8 preserves all existing rows and adds sync columns', () async {
      // إنشاء قاعدة بيانات v7 ببيانات قديمة
      final tempUpgradeDbPath = '${Directory.systemTemp.path}/rowing_upgrade_${DateTime.now().microsecondsSinceEpoch}.db';
      final db = await openDatabase(
        tempUpgradeDbPath,
        version: 7,
        onCreate: (d, v) async {
          await d.execute(
              'CREATE TABLE players(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, mhr INTEGER, active INTEGER DEFAULT 1, curves_shared INTEGER, curves_shared_by TEXT)');
          await d.execute(
              'CREATE TABLE sessions(date TEXT, idx INTEGER, kind TEXT, zone TEXT, PRIMARY KEY(date, idx))');
          await d.execute(
              'CREATE TABLE notes(date TEXT PRIMARY KEY, general TEXT, tech TEXT)');
          await d.execute(
              'CREATE TABLE logs(player_id INTEGER, date TEXT, idx INTEGER, rhr INTEGER, zone TEXT, PRIMARY KEY(player_id, date, idx))');
        },
      );

      // إدراج بيانات قديمة
      await db.insert('players', {'name': 'كابتن محمود', 'mhr': 195});
      await db.insert('sessions', {'date': '2026-11-15', 'idx': 1, 'kind': 'Erg', 'zone': 'Z2'});
      await db.insert('logs', {'player_id': 1, 'date': '2026-11-15', 'idx': 1, 'rhr': 55, 'zone': 'Z2'});

      // تشغيل ترقية v8 بأمان
      await SyncEngine.ensureDatabaseSyncSchema(db);

      // التحقق من بقاء البيانات القديمة سليمة تماماً
      final players = await db.query('players');
      expect(players, hasLength(1));
      expect(players.first['name'], equals('كابتن محمود'));

      final logs = await db.query('logs');
      expect(logs, hasLength(1));
      expect(logs.first['rhr'], equals(55));

      // التحقق من إضافة الأعمدة والتريجرات
      final logCols = await db.rawQuery("PRAGMA table_info('logs')");
      final names = logCols.map((c) => c['name'] as String).toSet();
      expect(names.contains('dirty'), isTrue);
      expect(names.contains('remote_id'), isTrue);
      expect(names.contains('updated_at'), isTrue);

      await db.close();
    });
  });

  group('SyncEngine - Multi-device Two-Way Sync', () {
    test('Athlete logs a workout -> pushes to cloud -> Coach pulls and receives it', () async {
      final dbAthlete = await createTestDb('db_athlete');
      final dbCoach = await createTestDb('db_coach');

      final todayStr = DateTime.now().toUtc().toIso8601String().substring(0, 10);

      // 1. اللاعب يسجل تمرينه في جهازه المحلي
      await dbAthlete.insert('logs', {
        'player_id': athlete1User.id,
        'date': todayStr,
        'idx': 1,
        'rhr': 52,
        'hr': 148,
        'avg_power': 225.0,
        'duration_seconds': 3600,
        'distance': 10500,
        'zone': 'Zone 2 - UT2',
      });

      // التحقق من أن السجل محلي ومُعَلَّم بـ dirty=1
      var athleteRows = await dbAthlete.query('logs');
      expect(athleteRows.first['dirty'], equals(1));

      // 2. مزامنة جهاز اللاعب (Push ثم Pull)
      final engine = SyncEngine.instance;
      await engine.syncNow(targetDb: dbAthlete, user: athlete1User);

      // بعد المزامنة: dirty = 0 وتم تعيين remote_id
      athleteRows = await dbAthlete.query('logs');
      expect(athleteRows.first['dirty'], equals(0));
      final remoteId = athleteRows.first['remote_id'];
      expect(remoteId, isNotNull);

      // 3. جهاز المدرب فارغ قبل المزامنة
      var coachLogs = await dbCoach.query('logs');
      expect(coachLogs, isEmpty);

      // 4. المدرب يقوم بالمزامنة في جهازه
      await engine.syncNow(targetDb: dbCoach, user: coachUser);

      // 5. التحقق من وصول بيانات تمرين اللاعب إلى جهاز المدرب مطابقة تماماً
      coachLogs = await dbCoach.query('logs');
      expect(coachLogs, hasLength(1));
      expect(coachLogs.first['player_id'], equals(athlete1User.id));
      expect(coachLogs.first['avg_power'], equals(225.0));
      expect(coachLogs.first['zone'], equals('Zone 2 - UT2'));
      expect(coachLogs.first['dirty'], equals(0));
      expect(coachLogs.first['remote_id'], equals(remoteId));

      await dbAthlete.close();
      await dbCoach.close();
    });

    test('Coach edits session -> pushes -> Athlete pulls and receives coach edit', () async {
      final dbAthlete = await createTestDb('db_athlete_2');
      final dbCoach = await createTestDb('db_coach_2');

      final engine = SyncEngine.instance;

      // المدرب يخطط حصة تدريبية
      await dbCoach.insert('sessions', {
        'date': '2026-11-25',
        'idx': 1,
        'kind': 'Erg',
        'zone': 'Zone 3 - UT1',
      });

      await engine.syncNow(targetDb: dbCoach, user: coachUser);

      // اللاعب يسحب الحصة المخططة
      await engine.syncNow(targetDb: dbAthlete, user: athlete1User);
      var athleteSessions = await dbAthlete.query('sessions');
      expect(athleteSessions, hasLength(1));
      expect(athleteSessions.first['zone'], equals('Zone 3 - UT1'));

      // المدرب يعدل زون الحصة إلى Zone 4
      await dbCoach.update(
        'sessions',
        {'zone': 'Zone 4 - AT'},
        where: 'date = ? AND idx = ?',
        whereArgs: ['2026-11-25', 1],
      );
      await engine.syncNow(targetDb: dbCoach, user: coachUser);

      // اللاعب يسحب التعديل
      await engine.syncNow(targetDb: dbAthlete, user: athlete1User);
      athleteSessions = await dbAthlete.query('sessions');
      expect(athleteSessions.first['zone'], equals('Zone 4 - AT'));

      await dbAthlete.close();
      await dbCoach.close();
    });

    test('Offline entry: saved locally with dirty=1, pushes when back online', () async {
      final db = await createTestDb('offline_db');
      final engine = SyncEngine.instance;

      // إدخال تمرين محلياً
      await db.insert('notes', {
        'date': '2026-11-21',
        'general': 'ملاحظات تدريب قوية',
        'tech': 'التركيز على مد الذراعين',
      });

      final localNotes = await db.query('notes');
      expect(localNotes.first['dirty'], equals(1));

      // مزامنة فور الاتصال
      await engine.syncNow(targetDb: db, user: coachUser);

      final syncedNotes = await db.query('notes');
      expect(syncedNotes.first['dirty'], equals(0));
      expect(syncedNotes.first['remote_id'], isNotNull);

      await db.close();
    });

    test('Server midnight lock rejects athlete editing past session and reverts local change', () async {
      final dbAthlete = await createTestDb('db_lock_test');
      final engine = SyncEngine.instance;

      String? rejectedMessage;
      engine.onServerLockRejection = (msg) {
        rejectedMessage = msg;
      };

      // حصة قديمة قبل اليوم
      const pastDate = '2026-11-01';

      // اللاعب يحاول تعديل حصة منقضية بعد منتصف الليل
      await dbAthlete.insert('logs', {
        'player_id': athlete1User.id,
        'date': pastDate,
        'idx': 1,
        'rhr': 50,
        'zone': 'Zone 1 - UT3',
      });

      // محاولة المزامنة
      await engine.syncNow(targetDb: dbAthlete, user: athlete1User);

      // التحقق من رفض السيرفر للتعديل واستدعاء التنبيه
      expect(rejectedMessage, isNotNull);
      expect(rejectedMessage, contains('منتصف الليل'));

      // التحقق من إلغاء حالة dirty حتى لا يعلق الجهاز في محاولات فاشلة
      final logs = await dbAthlete.query('logs');
      expect(logs.first['dirty'], equals(0));

      await dbAthlete.close();
    });

    test('Soft delete tombstone: deleting locally creates tombstone and syncs to other device', () async {
      final dbCoach = await createTestDb('tombstone_coach');
      final dbAthlete = await createTestDb('tombstone_athlete');
      final engine = SyncEngine.instance;

      // 1. المدرب يضيف موعد اختبار
      await dbCoach.insert('testing_dates', {
        'id': 1,
        'test_name': '2000m Erg Test',
        'test_date': '2026-12-01',
      });

      await engine.syncNow(targetDb: dbCoach, user: coachUser);
      await engine.syncNow(targetDb: dbAthlete, user: athlete1User);

      var athleteTests = await dbAthlete.query('testing_dates');
      expect(athleteTests, hasLength(1));

      // 2. المدرب يحذف موعد الاختبار
      await dbCoach.delete('testing_dates', where: 'id = ?', whereArgs: [1]);
      final tombstones = await dbCoach.query('sync_tombstones');
      expect(tombstones, hasLength(1));

      // 3. المدرب يرفع الحذف
      await engine.syncNow(targetDb: dbCoach, user: coachUser);
      expect(await dbCoach.query('sync_tombstones'), isEmpty);

      // 4. اللاعب يسحب التحديثات -> يحذف من جهازه تلقائياً
      await engine.syncNow(targetDb: dbAthlete, user: athlete1User);
      athleteTests = await dbAthlete.query('testing_dates');
      expect(athleteTests, isEmpty);

      await dbCoach.close();
      await dbAthlete.close();
    });

    test('Idempotent sync: multiple consecutive syncs produce stable state', () async {
      final db = await createTestDb('idempotent_test');
      final engine = SyncEngine.instance;

      await db.insert('progress_baseline_config', {
        'key': 'baseline_ef',
        'value': 1.65,
      });

      // تشغيل المزامنة ثلاث مرات متتالية
      await engine.syncNow(targetDb: db, user: coachUser);
      await engine.syncNow(targetDb: db, user: coachUser);
      await engine.syncNow(targetDb: db, user: coachUser);

      expect(engine.status, equals(SyncStatus.synced));
      final rows = await db.query('progress_baseline_config');
      expect(rows, hasLength(1));
      expect(rows.first['value'], equals(1.65));
      expect(rows.first['dirty'], equals(0));

      await db.close();
    });

    test('Athlete privacy isolation: athlete does not pull another athlete logs', () async {
      final dbAthlete1 = await createTestDb('db_ath1');
      final dbAthlete2 = await createTestDb('db_ath2');
      final engine = SyncEngine.instance;

      final todayStr = DateTime.now().toUtc().toIso8601String().substring(0, 10);

      // اللاعب 1 يسجل تمرينه ويرفعه
      await dbAthlete1.insert('logs', {
        'player_id': athlete1User.id,
        'date': todayStr,
        'idx': 1,
        'rhr': 55,
        'zone': 'Zone 2 - UT2',
      });
      await engine.syncNow(targetDb: dbAthlete1, user: athlete1User);

      // اللاعب 2 يزامن جهازه
      await engine.syncNow(targetDb: dbAthlete2, user: athlete2User);

      // التأكد من أن اللاعب 2 لم يسحب سجلات اللاعب 1 الخاصة
      final ath2Logs = await dbAthlete2.query('logs');
      expect(ath2Logs, isEmpty);

      await dbAthlete1.close();
      await dbAthlete2.close();
    });
  });
}
