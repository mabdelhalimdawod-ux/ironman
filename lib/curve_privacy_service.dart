import 'auth_service.dart';
import 'db.dart';
import 'sync_engine.dart';

/// خدمة خصوصية وصلاحيات مشاركة المنحنيات (Curve Privacy Service)
/// تطبق بدقة قاعدة كوتش: "اللاعب له حق الخصوصية وقراره هو النهائي"
class CurvePrivacyService {
  /// التحقق المركزي مما إذا كان المستخدم يملك صلاحية رؤية منحنيات لاعب محدد
  /// viewer: المستخدم الحالي (لاعب، مدرب، أو أدمن)
  /// ownerPlayerId: معرف اللاعب صاحب المنحنيات
  static Future<bool> canViewCurves({
    required AppUser viewer,
    required int ownerPlayerId,
  }) async {
    // 1. الأدمن محظور تماماً من رؤية بيانات التمارين والمنحنيات والصحة
    if (viewer.isAdmin) {
      return false;
    }

    final db = await DB.db;

    // 2. إذا كان المشاهد هو نفسه صاحب المنحنيات -> مسموح دائماً
    if (viewer.isAthlete && viewer.id == ownerPlayerId) {
      return true;
    }

    // جلب بيانات اللاعب صاحب المنحنيات من قاعدة البيانات المحلية
    final rows = await db.query(
      'players',
      where: 'id = ?',
      whereArgs: [ownerPlayerId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return false;
    }
    final targetPlayer = rows.first;
    int? targetCoachId = (targetPlayer['coach_id'] as num?)?.toInt();
    if (targetCoachId == null) {
      try {
        final uRows = await db.rawQuery(
          'SELECT coach_id FROM users WHERE player_id = ? OR id = ? LIMIT 1',
          [ownerPlayerId, ownerPlayerId],
        );
        if (uRows.isNotEmpty) {
          targetCoachId = (uRows.first['coach_id'] as num?)?.toInt();
        }
      } catch (_) {}
    }

    // 3. إذا كان المشاهد مدرباً
    if (viewer.isCoach) {
      // المدرب يرى منحنيات لاعبيه دائماً
      if (targetCoachId != null && targetCoachId != viewer.id) {
        // مدرب آخر -> ممنوع
        return false;
      }
      return true;
    }

    // 4. إذا كان المشاهد لاعباً آخر (زميل في الفريق)
    if (viewer.isAthlete) {
      // تحقق من أنهما زميلان لنفس المدرب
      final viewerCoachId = viewer.coachId;
      if (viewerCoachId == null) {
        return false; // ليس لديه مدرب
      }

      // تحقق من أن اللاعب الآخر يتبع نفس المدرب
      if (targetCoachId != null && targetCoachId != viewerCoachId) {
        return false; // ليس زميلاً في نفس الفريق
      }

      // التحقق من مفتاح مشاركة المنحنيات
      final curvesShared = (targetPlayer['curves_shared'] as num?)?.toInt() ?? 0;
      return curvesShared == 1;
    }

    return false;
  }

  /// هل يستطيع المستخدم الحالي تعديل خيار مشاركة المنحنيات للاعب معين؟
  /// اللاعب يستطيع دائماً تعديل خياره بنفسه.
  /// المدرب يستطيع فقط إذا لم يسبق للاعب أن قرر بنفسه (curves_shared_by != 'athlete').
  static Future<bool> canEditCurveSharing({
    required AppUser editor,
    required int targetPlayerId,
  }) async {
    // الأدمن لا يعدل
    if (editor.isAdmin) return false;

    // اللاعب يعدل لنفسه دائماً
    if (editor.isAthlete && editor.id == targetPlayerId) {
      return true;
    }

    // المدرب يعدل فقط إذا لم يقرر اللاعب بنفسه
    if (editor.isCoach) {
      final db = await DB.db;
      final rows = await db.query(
        'players',
        columns: ['curves_shared_by'],
        where: 'id = ?',
        whereArgs: [targetPlayerId],
        limit: 1,
      );
      if (rows.isEmpty) return false;
      final sharedBy = rows.first['curves_shared_by'] as String?;
      return sharedBy != 'athlete';
    }

    return false;
  }

  /// تحديث حالة مشاركة المنحنيات مع تطبيق قواعد الأولوية
  /// إذا قام اللاعب بتغييرها بنفسه تصبح curves_shared_by = 'athlete' بشكل نهائي
  static Future<void> setCurveSharing({
    required AppUser actor,
    required int targetPlayerId,
    required bool shared,
  }) async {
    final canEdit = await canEditCurveSharing(editor: actor, targetPlayerId: targetPlayerId);
    if (!canEdit) {
      throw Exception('اللاعب حدد خصوصيته مسبقاً ولا يمكن للمدرب تغيير قراره');
    }

    final db = await DB.db;
    final byWho = actor.isAthlete ? 'athlete' : 'coach';

    await db.update(
      'players',
      {
        'curves_shared': shared ? 1 : 0,
        'curves_shared_by': byWho,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
        'dirty': 1,
      },
      where: 'id = ?',
      whereArgs: [targetPlayerId],
    );

    SyncEngine.instance.scheduleDebouncedSync();
  }

  /// جلب بيانات المنحنيات للاعب مع العزل التام:
  /// - اللاعب نفسه أو المدرب: من جدول logs
  /// - الزميل المصرح له: من جدول shared_curve_cache حصراً (لا يختلط أبداً بـ logs)
  static Future<List<Map<String, dynamic>>> getCurvesDataForPlayer({
    required AppUser viewer,
    required int targetPlayerId,
  }) async {
    final allowed = await canViewCurves(viewer: viewer, ownerPlayerId: targetPlayerId);
    if (!allowed) {
      return [];
    }

    final db = await DB.db;

    // إذا كان زميلاً مصرحاً له، نجلب من shared_curve_cache المخصص للعرض فقط
    if (viewer.isAthlete && viewer.id != targetPlayerId) {
      final cacheRows = await db.query(
        'shared_curve_cache',
        where: 'player_id = ?',
        whereArgs: [targetPlayerId],
        orderBy: 'date DESC',
      );
      return cacheRows;
    }

    // إذا كان اللاعب نفسه أو المدرب، نجلب من logs
    final logs = await db.query(
      'logs',
      where: 'player_id = ?',
      whereArgs: [targetPlayerId],
      orderBy: 'date DESC',
    );
    return logs;
  }

  /// حفظ وتحديث كاش منحنيات الزميل في الجدول المنفصل shared_curve_cache
  static Future<void> cacheTeammateCurves({
    required int playerId,
    required List<Map<String, dynamic>> records,
  }) async {
    final db = await DB.db;
    final now = DateTime.now().toUtc().toIso8601String();

    await db.transaction((txn) async {
      await txn.delete(
        'shared_curve_cache',
        where: 'player_id = ?',
        whereArgs: [playerId],
      );

      for (final r in records) {
        await txn.insert('shared_curve_cache', {
          'player_id': playerId,
          'date': r['date'] ?? '',
          'idx': (r['idx'] as num?)?.toInt() ?? 0,
          'split_500': (r['split_500'] as num?)?.toDouble(),
          'avg_power': (r['avg_power'] as num?)?.toDouble(),
          'hr': (r['hr'] as num?)?.toInt(),
          'hr_max': (r['hr_max'] as num?)?.toInt(),
          'distance': (r['distance'] as num?)?.toInt(),
          'duration_seconds': (r['duration_seconds'] as num?)?.toInt(),
          'zone': r['zone']?.toString(),
          'ef': (r['ef'] as num?)?.toDouble(),
          'decoupling': (r['decoupling'] as num?)?.toDouble(),
          'eupnea_1': (r['eupnea_1'] as num?)?.toDouble(),
          'eupnea_2': (r['eupnea_2'] as num?)?.toDouble(),
          'eupnea_3': (r['eupnea_3'] as num?)?.toDouble(),
          'cached_at': now,
        });
      }
    });
  }
}
