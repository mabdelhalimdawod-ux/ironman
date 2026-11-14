import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as p;

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('Database upgrades cleanly from v4 to v5 without losing data', () async {
    final tempDir = Directory.systemTemp.createTempSync('rowing_v5_test_');
    addTearDown(() {
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    });

    final dbPath = p.join(tempDir.path, 'rowing_test.db');

    // 1. إنشاء قاعدة بيانات تجريبية بنسخة v4 وإدخال سجلات فيها
    final v4Db = await openDatabase(
      dbPath,
      version: 4,
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
            PRIMARY KEY(player_id, date, idx)
          )
        ''');
      },
    );

    // زراعة سجل ببيانات حقيقية في v4
    await v4Db.insert('logs', {
      'player_id': 10,
      'date': '2026-11-14',
      'idx': 0,
      'avg_power': 220.5,
      'split_500': 118.4,
      'ef': 1.45,
      'hr': 152,
    });
    await v4Db.close();

    // 2. ضبط المسار لـ DB التابع للتطبيق وفتح القاعدة بنسخة v5
    await databaseFactory.setDatabasesPath(tempDir.path);
    // إعادة تعيين كاش DB الداخلي إن وُجد
    final upgradedDb = await openDatabase(
      dbPath,
      version: 5,
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 5) {
          final cols = await db.rawQuery('PRAGMA table_info(logs)');
          final colNames = cols.map((c) => c['name'] as String).toSet();
          if (!colNames.contains('decoupling')) {
            await db.execute('ALTER TABLE logs ADD COLUMN decoupling REAL');
          }
          if (!colNames.contains('eupnea_1')) {
            await db.execute('ALTER TABLE logs ADD COLUMN eupnea_1 REAL');
          }
          if (!colNames.contains('eupnea_2')) {
            await db.execute('ALTER TABLE logs ADD COLUMN eupnea_2 REAL');
          }
          if (!colNames.contains('eupnea_3')) {
            await db.execute('ALTER TABLE logs ADD COLUMN eupnea_3 REAL');
          }
          if (!colNames.contains('entered_by')) {
            await db.execute('ALTER TABLE logs ADD COLUMN entered_by TEXT');
          }
        }
      },
    );

    // 3. التحقق من بقاء البيانات القديمة بدون أي فقد
    final rows = await upgradedDb.rawQuery('SELECT * FROM logs WHERE player_id = 10');
    expect(rows.length, 1);
    expect(rows.first['avg_power'], 220.5);
    expect(rows.first['split_500'], 118.4);
    expect(rows.first['ef'], 1.45);
    expect(rows.first['hr'], 152);

    // 4. التحقق من وجود الأعمدة الجديدة
    final cols = await upgradedDb.rawQuery('PRAGMA table_info(logs)');
    final colNames = cols.map((c) => c['name'] as String).toSet();
    expect(colNames.contains('decoupling'), isTrue);
    expect(colNames.contains('eupnea_1'), isTrue);
    expect(colNames.contains('eupnea_2'), isTrue);
    expect(colNames.contains('eupnea_3'), isTrue);
    expect(colNames.contains('entered_by'), isTrue);

    // 5. التحقق من أن entered_by فارغ للصفوف القديمة
    expect(rows.first['entered_by'], isNull);

    // 6. التحقق من إمكانية الكتابة في الأعمدة الجديدة
    await upgradedDb.update(
      'logs',
      {
        'decoupling': 3.8,
        'eupnea_1': 42.5,
        'eupnea_2': 38.0,
        'eupnea_3': 35.0,
        'entered_by': 'athlete',
      },
      where: 'player_id = ? AND date = ? AND idx = ?',
      whereArgs: [10, '2026-11-14', 0],
    );

    final updated = await upgradedDb.rawQuery('SELECT * FROM logs WHERE player_id = 10');
    expect(updated.first['decoupling'], 3.8);
    expect(updated.first['eupnea_1'], 42.5);
    expect(updated.first['eupnea_2'], 38.0);
    expect(updated.first['eupnea_3'], 35.0);
    expect(updated.first['entered_by'], 'athlete');

    await upgradedDb.close();
  });
}

