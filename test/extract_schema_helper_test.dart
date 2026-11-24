import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:rowing_app/auth_service.dart';
import 'package:rowing_app/db.dart';
import 'package:rowing_app/progress_calcs.dart';
import 'package:rowing_app/sync_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  test('Extract exact SQLite schema to JSON and verify onCreate + upgrade', () async {
    final tempDbPath = '${Directory.systemTemp.path}/schema_extract_${DateTime.now().microsecondsSinceEpoch}.db';
    final db = await openDatabase(
      tempDbPath,
      version: 10,
      onCreate: (d, v) async {
        // Run full onCreate as in DB._open
        await d.execute('CREATE TABLE players(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, mhr INTEGER, active INTEGER DEFAULT 1, coach_id INTEGER, curves_shared INTEGER, curves_shared_by TEXT)');
        await d.execute('CREATE TABLE cycles(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, start TEXT, end TEXT)');
        await d.execute('CREATE TABLE sessions(date TEXT, idx INTEGER, kind TEXT, zone TEXT, PRIMARY KEY(date, idx))');
        await d.execute('CREATE TABLE notes(date TEXT PRIMARY KEY, general TEXT, tech TEXT)');
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

    DB.testDatabase = db;

    // Initialize all runtime tables and sync schema
    await AuthService.ensureTables();
    await SyncEngine.ensureDatabaseSyncSchema(db);
    await ProgressLoadCache.ensureTable();

    // Query sqlite_master
    final tables = await db.rawQuery(
        "SELECT name, sql FROM sqlite_master WHERE type='table' ORDER BY name ASC");
    final triggers = await db.rawQuery(
        "SELECT name, tbl_name, sql FROM sqlite_master WHERE type='trigger' ORDER BY tbl_name, name");

    final result = <String, dynamic>{
      'total_tables': tables.length,
      'synced_tables_count': SyncEngine.syncedTables.length,
      'tables': [],
      'triggers_count': triggers.length,
      'triggers': triggers,
    };

    for (final t in tables) {
      final tableName = t['name'] as String;
      final cols = await db.rawQuery("PRAGMA table_info('$tableName')");
      final fks = await db.rawQuery("PRAGMA foreign_key_list('$tableName')");
      final idxs = await db.rawQuery("PRAGMA index_list('$tableName')");

      (result['tables'] as List).add({
        'name': tableName,
        'sql': t['sql'],
        'columns': cols,
        'foreign_keys': fks,
        'indexes': idxs,
      });
    }

    final outDir = Directory('docs');
    if (!outDir.existsSync()) outDir.createSync(recursive: true);
    File('docs/extracted_schema.json').writeAsStringSync(const JsonEncoder.withIndent('  ').convert(result));

    expect(result['synced_tables_count'], equals(20));
    print('TOTAL TABLES EXTRACTED: ${result['total_tables']}');
    print('SYNCED TABLES COUNT: ${result['synced_tables_count']}');
    print('TRIGGERS COUNT: ${result['triggers_count']}');

    await db.close();
    DB.testDatabase = null;
  });
}
