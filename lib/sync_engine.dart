import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'auth_service.dart';
import 'cloud_api.dart';
import 'db.dart';

/// حالة المزامنة اللحظية
enum SyncStatus {
  synced,
  syncing,
  offline,
  error,
}

/// معلومات تعريف الجدول المتزامن ومفاتيحه
class SyncTableDef {
  final String name;
  final List<String> keyColumns;
  final bool hasIdColumn;

  const SyncTableDef({
    required this.name,
    required this.keyColumns,
    this.hasIdColumn = true,
  });

  String get deleteKeyExpr {
    if (hasIdColumn) {
      return 'cast(OLD.id as text)';
    }
    return keyColumns.map((c) => 'OLD.$c').join(" || '_' || ");
  }
}

/// محرك المزامنة المحلي أولاً (Local-First Sync Engine)
class SyncEngine extends ChangeNotifier {
  static final SyncEngine instance = SyncEngine._();
  SyncEngine._();

  SyncStatus _status = SyncStatus.synced;
  SyncStatus get status => _status;

  DateTime? _lastSyncedAt;
  DateTime? get lastSyncedAt => _lastSyncedAt;

  String? _lastError;
  String? get lastError => _lastError;

  int _pendingDirtyCount = 0;
  int get pendingDirtyCount => _pendingDirtyCount;

  Timer? _debounceTimer;
  Timer? _retryTimer;
  int _retryBackoffSeconds = 5;

  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;

  Function(String message)? onServerLockRejection;

  /// قائمة الجداول المتزامنة الـ 19 مرتبة بدقة حسب الاعتماديات
  static const List<SyncTableDef> syncedTables = [
    SyncTableDef(name: 'players', keyColumns: ['id']),
    SyncTableDef(name: 'sessions', keyColumns: ['date', 'idx'], hasIdColumn: false),
    SyncTableDef(name: 'notes', keyColumns: ['date'], hasIdColumn: false),
    SyncTableDef(name: 'program_cycles', keyColumns: ['id']),
    SyncTableDef(name: 'program_cycle_tests', keyColumns: ['cycle_id', 'test_type'], hasIdColumn: false),
    SyncTableDef(name: 'program_day_config', keyColumns: ['cycle_id', 'cycle_type', 'day_of_week'], hasIdColumn: false),
    SyncTableDef(name: 'program_sessions', keyColumns: ['id']),
    SyncTableDef(name: 'program_workout_items', keyColumns: ['id']),
    SyncTableDef(name: 'cycle_templates', keyColumns: ['id']),
    SyncTableDef(name: 'logs', keyColumns: ['player_id', 'date', 'idx'], hasIdColumn: false),
    SyncTableDef(name: 'athlete_custom_sessions', keyColumns: ['player_id', 'date', 'session_idx']),
    SyncTableDef(name: 'athlete_custom_workout_items', keyColumns: ['custom_session_id', 'section', 'item_idx']),
    SyncTableDef(name: 'cp_tests', keyColumns: ['id']),
    SyncTableDef(name: 'cp_values', keyColumns: ['player_id', 'date'], hasIdColumn: false),
    SyncTableDef(name: 'testing_dates', keyColumns: ['id']),
    SyncTableDef(name: 'testing_date_recipients', keyColumns: ['testing_date_id', 'athlete_id'], hasIdColumn: false),
    SyncTableDef(name: 'coach_messages', keyColumns: ['id']),
    SyncTableDef(name: 'progress_baseline_config', keyColumns: ['key'], hasIdColumn: false),
    SyncTableDef(name: 'matrix_zone_config', keyColumns: ['key'], hasIdColumn: false),
  ];

  /// تهيئة جداول وتريجرات المزامنة في SQLite
  static Future<void> ensureDatabaseSyncSchema(Database db) async {
    // 1. جداول حالة المزامنة
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sync_state (
        table_name TEXT PRIMARY KEY,
        last_pulled_at TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS sync_tombstones (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        table_name TEXT NOT NULL,
        remote_key TEXT NOT NULL,
        deleted_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS sync_flag (
        id INTEGER PRIMARY KEY,
        active INTEGER DEFAULT 0
      )
    ''');

    await db.execute('''
      INSERT OR IGNORE INTO sync_flag (id, active) VALUES (1, 0)
    ''');

    // 2. فحص وإضافة أعمدة المزامنة والتريجرات للجداول المتزامنة
    for (final table in syncedTables) {
      final tableCheck = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name='${table.name}'");
      if (tableCheck.isEmpty) continue;

      final cols = await db.rawQuery("PRAGMA table_info('${table.name}')");
      final colNames = cols.map((c) => c['name'] as String).toSet();

      if (!colNames.contains('remote_id')) {
        await db.execute("ALTER TABLE '${table.name}' ADD COLUMN remote_id TEXT");
      }
      if (!colNames.contains('updated_at')) {
        await db.execute("ALTER TABLE '${table.name}' ADD COLUMN updated_at TEXT");
      }
      if (!colNames.contains('dirty')) {
        await db.execute("ALTER TABLE '${table.name}' ADD COLUMN dirty INTEGER DEFAULT 0");
      }

      // 3. تريجرات المزامنة التلقائية
      // تريجر الإدخال: يضع dirty=1 إلا إذا كان sync_flag.active=1
      await db.execute('''
        CREATE TRIGGER IF NOT EXISTS trg_${table.name}_insert
        AFTER INSERT ON '${table.name}'
        WHEN (SELECT active FROM sync_flag WHERE id = 1) = 0 AND (NEW.dirty IS NULL OR NEW.dirty != 1)
        BEGIN
          UPDATE '${table.name}'
          SET dirty = 1, updated_at = strftime('%Y-%m-%dT%H:%M:%SZ', 'now')
          WHERE rowid = NEW.rowid;
        END;
      ''');

      // تريجر التعديل: يضع dirty=1 إلا إذا كان sync_flag.active=1
      await db.execute('''
        CREATE TRIGGER IF NOT EXISTS trg_${table.name}_update
        AFTER UPDATE ON '${table.name}'
        WHEN (SELECT active FROM sync_flag WHERE id = 1) = 0 AND NEW.dirty != 1
        BEGIN
          UPDATE '${table.name}'
          SET dirty = 1, updated_at = strftime('%Y-%m-%dT%H:%M:%SZ', 'now')
          WHERE rowid = NEW.rowid;
        END;
      ''');

      // تريجر الحذف: يسجل في sync_tombstones إلا إذا كان sync_flag.active=1
      await db.execute('''
        CREATE TRIGGER IF NOT EXISTS trg_${table.name}_delete
        AFTER DELETE ON '${table.name}'
        WHEN (SELECT active FROM sync_flag WHERE id = 1) = 0
        BEGIN
          INSERT INTO sync_tombstones (table_name, remote_key, deleted_at)
          VALUES ('${table.name}', COALESCE(OLD.remote_id, ${table.deleteKeyExpr}), strftime('%Y-%m-%dT%H:%M:%SZ', 'now'));
        END;
      ''');
    }
  }

  /// بدء الاستماع لتغيرات الشبكة
  void initConnectivityListener() {
    _connectivitySub?.cancel();
    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      final isOnline = results.any((r) => r != ConnectivityResult.none);
      if (isOnline) {
        syncNow();
      } else {
        _status = SyncStatus.offline;
        notifyListeners();
      }
    });
  }

  /// جدولة مزامنة مؤجلة (Debounced Sync) بعد الحفظ بخمس ثوانٍ
  void scheduleDebouncedSync([Duration delay = const Duration(seconds: 5)]) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(delay, () {
      syncNow();
    });
  }

  /// تنفيذ مزامنة كاملة فوراً (Push ثم Pull)
  Future<void> syncNow({Database? targetDb, AppUser? user}) async {
    final activeUser = user ?? AuthService.currentUser;
    final database = targetDb ?? await DB.db;

    if (!CloudApi.instance.isAvailable) {
      _status = SyncStatus.offline;
      notifyListeners();
      return;
    }

    _status = SyncStatus.syncing;
    notifyListeners();

    try {
      // 1. مرحلة الرفع (Push)
      await _push(database, activeUser);

      // 2. مرحلة السحب (Pull)
      await _pull(database, activeUser);

      _status = SyncStatus.synced;
      _lastSyncedAt = DateTime.now();
      _lastError = null;
      _retryBackoffSeconds = 5;
      _retryTimer?.cancel();
    } catch (e) {
      _status = SyncStatus.error;
      _lastError = e.toString();
      _scheduleRetry();
    } finally {
      _updatePendingCount(database);
      notifyListeners();
    }
  }

  /// رفع السجلات المعدلة (dirty=1) والـ Tombstones
  Future<void> _push(Database db, AppUser? user) async {
    for (final table in syncedTables) {
      final tableCheck = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name='${table.name}'");
      if (tableCheck.isEmpty) continue;

      final dirtyRows = await db.query(
        table.name,
        where: 'dirty = ?',
        whereArgs: [1],
      );

      if (dirtyRows.isEmpty) continue;

      final recordsToPush = dirtyRows.map((r) {
        final m = Map<String, dynamic>.from(r);
        m.remove('dirty');
        return m;
      }).toList();

      try {
        final pushed = await CloudApi.instance.pushBatch(
          table.name,
          recordsToPush,
          userRole: user?.role,
          userId: user?.id.toString(),
        );

        // تحديث حالة السجلات محلياً بدون إطلاق التريجرات
        await db.update('sync_flag', {'active': 1}, where: 'id = ?', whereArgs: [1]);

        for (int i = 0; i < dirtyRows.length; i++) {
          final original = dirtyRows[i];
          final remoteId = (i < pushed.length) ? pushed[i]['remote_id'] ?? pushed[i]['id'] : null;

          final whereClauses = <String>[];
          final whereArgs = <Object?>[];

          for (final key in table.keyColumns) {
            whereClauses.add('$key = ?');
            whereArgs.add(original[key]);
          }

          final updateData = <String, Object?>{
            'dirty': 0,
            if (remoteId != null) 'remote_id': remoteId,
          };

          await db.update(
            table.name,
            updateData,
            where: whereClauses.join(' AND '),
            whereArgs: whereArgs,
          );
        }
      } on ServerLockException catch (e) {
        // إذا رفض السيرفر تعديل الحصة بسبب قفل منتصف الليل
        // نضع dirty = 0 لإلغاء التعديل المحلي واستعادة نسخة السيرفر
        await db.update('sync_flag', {'active': 1}, where: 'id = ?', whereArgs: [1]);
        await db.update(table.name, {'dirty': 0}, where: 'dirty = ?', whereArgs: [1]);
        onServerLockRejection?.call(e.message);
      } finally {
        await db.update('sync_flag', {'active': 0}, where: 'id = ?', whereArgs: [1]);
      }
    }

    // رفع الـ Tombstones (الحذف الناعم)
    final tombstones = await db.query('sync_tombstones');
    if (tombstones.isNotEmpty) {
      final grouped = <String, List<String>>{};
      for (final t in tombstones) {
        final tbl = t['table_name'] as String;
        final k = t['remote_key'] as String;
        grouped.putIfAbsent(tbl, () => []).add(k);
      }

      for (final entry in grouped.entries) {
        await CloudApi.instance.softDeleteBatch(entry.key, entry.value);
      }

      await db.delete('sync_tombstones');
    }
  }

  /// سحب التحديثات من السحابة وتطبيقها محلياً
  Future<void> _pull(Database db, AppUser? user) async {
    // تفعيل sync_flag لمنع التريجرات أثناء تطبيق السحب
    await db.update('sync_flag', {'active': 1}, where: 'id = ?', whereArgs: [1]);

    try {
      final nowUtcStr = DateTime.now().toUtc().toIso8601String();

      for (final table in syncedTables) {
        final tableCheck = await db.rawQuery(
            "SELECT name FROM sqlite_master WHERE type='table' AND name='${table.name}'");
        if (tableCheck.isEmpty) continue;

        // جلب آخر تاريخ سحب للجدول
        final stateRows = await db.query(
          'sync_state',
          where: 'table_name = ?',
          whereArgs: [table.name],
        );
        final lastPulledAt = stateRows.isNotEmpty
            ? stateRows.first['last_pulled_at'] as String?
            : null;

        final incoming = await CloudApi.instance.pullBatch(
          table.name,
          since: lastPulledAt,
          userRole: user?.role,
          userId: user?.id.toString(),
          coachId: user?.coachId?.toString(),
        );

        for (final row in incoming) {
          final isDeleted = (row['deleted_at'] != null);
          final remoteId = row['remote_id'] ?? row['id'];

          final whereClauses = <String>[];
          final whereArgs = <Object?>[];

          for (final key in table.keyColumns) {
            whereClauses.add('$key = ?');
            whereArgs.add(row[key]);
          }

          if (isDeleted) {
            // حذف محلي مطابق للحذف الناعم في السحابة
            await db.delete(
              table.name,
              where: whereClauses.join(' AND '),
              whereArgs: whereArgs,
            );
          } else {
            // حل التعارض (Last Write Wins): فحص السجل المحلي إن وجد
            final existing = await db.query(
              table.name,
              where: whereClauses.join(' AND '),
              whereArgs: whereArgs,
            );

            bool shouldApply = true;
            if (existing.isNotEmpty) {
              final localRow = existing.first;
              final localDirty = (localRow['dirty'] as int? ?? 0) == 1;
              final localUpdated = localRow['updated_at'] as String? ?? '';
              final serverUpdated = row['updated_at'] as String? ?? '';

              if (localDirty) {
                // إذا كان هناك تعديل محلي لم يُرفع بعد:
                // المدرب يكسب على اللاعب دائماً بعد القفل، وإلا الأحدث يكسب
                if (user?.isCoach == true) {
                  shouldApply = false; // نسخة المدرب المحلية أولى
                } else if (serverUpdated.compareTo(localUpdated) < 0) {
                  shouldApply = false;
                }
              }
            }

            if (shouldApply) {
              final insertData = Map<String, dynamic>.from(row);
              insertData['dirty'] = 0;
              insertData['remote_id'] = remoteId;
              insertData.remove('deleted_at');

              // تصفية الأعمدة غير الموجودة في SQLite
              final cols = await db.rawQuery("PRAGMA table_info('${table.name}')");
              final validCols = cols.map((c) => c['name'] as String).toSet();
              insertData.removeWhere((k, v) => !validCols.contains(k));

              await db.insert(
                table.name,
                insertData,
                conflictAlgorithm: ConflictAlgorithm.replace,
              );
            }
          }
        }

        // تحديث آخر تاريخ سحب للجدول
        await db.insert(
          'sync_state',
          {'table_name': table.name, 'last_pulled_at': nowUtcStr},
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    } finally {
      await db.update('sync_flag', {'active': 0}, where: 'id = ?', whereArgs: [1]);
    }
  }

  /// جدولة محاولة إعادة المزامنة بتأخير متزايد (Exponential Backoff)
  void _scheduleRetry() {
    _retryTimer?.cancel();
    _retryTimer = Timer(Duration(seconds: _retryBackoffSeconds), () {
      _retryBackoffSeconds = (_retryBackoffSeconds * 2).clamp(5, 60);
      syncNow();
    });
  }

  Future<void> _updatePendingCount(Database db) async {
    try {
      int count = 0;
      for (final table in syncedTables) {
        final tableCheck = await db.rawQuery(
            "SELECT name FROM sqlite_master WHERE type='table' AND name='${table.name}'");
        if (tableCheck.isEmpty) continue;

        final rows = await db.rawQuery(
            "SELECT COUNT(*) as cnt FROM '${table.name}' WHERE dirty = 1");
        if (rows.isNotEmpty) {
          count += (rows.first['cnt'] as num?)?.toInt() ?? 0;
        }
      }
      _pendingDirtyCount = count;
    } catch (_) {}
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _retryTimer?.cancel();
    _connectivitySub?.cancel();
    super.dispose();
  }
}
