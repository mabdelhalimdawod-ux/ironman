import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as p;

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('Database upgrades cleanly from v9 to v10 adding kind column and config tables without losing data', () async {
    final tempDir = Directory.systemTemp.createTempSync('rowing_v10_test_');
    addTearDown(() {
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    });

    final dbPath = p.join(tempDir.path, 'rowing_test.db');

    // 1. إنشاء قاعدة بيانات تجريبية بنسخة v9 وإدخال سجلات
    final v9Db = await openDatabase(
      dbPath,
      version: 9,
      onCreate: (db, version) async {
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
            decoupling REAL,
            eupnea_1 REAL,
            eupnea_2 REAL,
            eupnea_3 REAL,
            entered_by TEXT,
            zone TEXT,
            PRIMARY KEY(player_id, date, idx)
          )
        ''');
      },
    );

    // زراعة سجل ببيانات حقيقية في v9
    await v9Db.insert('logs', {
      'player_id': 15,
      'date': '2026-11-21',
      'idx': 0,
      'avg_power': 260.0,
      'split_500': 112.5,
      'ef': 1.62,
      'hr': 160,
      'zone': 'Z3',
      'entered_by': 'coach',
    });
    await v9Db.close();

    // 2. ترقية القاعدة إلى v10
    final upgradedDb = await openDatabase(
      dbPath,
      version: 10,
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 10) {
          final logCols = await db.rawQuery("PRAGMA table_info('logs')");
          final logColNames = logCols.map((c) => c['name'] as String).toSet();
          if (!logColNames.contains('kind')) {
            await db.execute("ALTER TABLE logs ADD COLUMN kind TEXT");
          }
          await db.execute('''
            CREATE TABLE IF NOT EXISTS matrix_zone_config (
              indicator_key TEXT PRIMARY KEY,
              weight REAL,
              direction TEXT,
              sort_order INTEGER
            )
          ''');
          await db.execute('''
            CREATE TABLE IF NOT EXISTS progress_baseline_config (
              key TEXT PRIMARY KEY,
              value REAL
            )
          ''');
        }
      },
    );

    // 3. التحقق من بقاء السجل القديم
    final rows = await upgradedDb.rawQuery('SELECT * FROM logs WHERE player_id = 15');
    expect(rows.length, 1);
    expect(rows.first['avg_power'], 260.0);
    expect(rows.first['zone'], 'Z3');
    expect(rows.first['kind'], isNull);

    // 4. التحقق من وجود عمود kind وإمكانية الكتابة فيه
    await upgradedDb.update(
      'logs',
      {'kind': 'Erg'},
      where: 'player_id = 15 AND date = ?',
      whereArgs: ['2026-11-21'],
    );
    final updated = await upgradedDb.rawQuery('SELECT kind FROM logs WHERE player_id = 15');
    expect(updated.first['kind'], 'Erg');

    // 5. التحقق من وجود جدول matrix_zone_config
    await upgradedDb.insert('matrix_zone_config', {
      'indicator_key': 'watts',
      'weight': 40.0,
      'direction': 'up',
      'sort_order': 0,
    });
    final cfgRows = await upgradedDb.rawQuery('SELECT * FROM matrix_zone_config');
    expect(cfgRows.length, 1);
    expect(cfgRows.first['weight'], 40.0);

    // 6. التحقق من أمان إعادة التشغيل مرتين (idempotency)
    final checkCols = await upgradedDb.rawQuery("PRAGMA table_info('logs')");
    final colNames = checkCols.map((c) => c['name'] as String).toSet();
    expect(colNames.contains('kind'), isTrue);

    await upgradedDb.close();
  });
}
