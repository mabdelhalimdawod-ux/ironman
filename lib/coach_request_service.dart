import 'auth_service.dart';
import 'cloud_api.dart';
import 'db.dart';
import 'sync_engine.dart';

/// خدمة إدارة طلبات انضمام اللاعبين للمدرب (Coach Request Service)
class CoachRequestService {
  /// جلب قائمة المدربين المتاحين والمفعّلين
  static Future<List<Map<String, dynamic>>> getActiveCoaches() async {
    final cloud = CloudApi.instance;
    try {
      final coaches = await cloud.getActiveCoaches();
      return coaches.map((c) => {
        'id': c.id,
        'name': c.name,
        'email': c.email,
        'photo_path': c.photoPath,
      }).toList();
    } catch (_) {
      // وضع محلي أو غير متصل: جلب من جدول users المحلي إن وجد
      final db = await DB.db;
      final local = await db.query(
        'users',
        where: 'role = ? AND subscription_active = 1',
        whereArgs: ['coach'],
      );
      return local.map((u) => {
        'id': u['id']?.toString() ?? '',
        'name': u['name']?.toString() ?? '',
        'email': u['email']?.toString() ?? '',
        'photo_path': u['photo_path']?.toString(),
      }).toList();
    }
  }

  /// إرسال طلب انضمام لمدرب
  static Future<void> sendCoachRequest({
    required int athleteId,
    required String coachId,
  }) async {
    final db = await DB.db;
    final now = DateTime.now().toUtc().toIso8601String();

    // التحقق من عدم وجود طلب معلّق لنفس المدرب
    final existing = await db.query(
      'coach_requests',
      where: 'athlete_id = ? AND coach_id = ? AND status = ?',
      whereArgs: [athleteId, coachId, 'pending'],
    );
    if (existing.isNotEmpty) {
      throw Exception('يوجد طلب معلّق بالفعل لهذا المدرب، يرجى انتظار الرد أو إلغاء الطلب السابق');
    }

    await db.insert('coach_requests', {
      'athlete_id': athleteId,
      'coach_id': int.tryParse(coachId) ?? 0,
      'status': 'pending',
      'created_at': now,
      'updated_at': now,
      'dirty': 1,
    });

    try {
      await CloudApi.instance.sendCoachRequest(
        athleteId: athleteId.toString(),
        coachId: coachId,
      );
    } catch (_) {
      // تم الحفظ محلياً وستتكفل المزامنة برفعه
    }

    SyncEngine.instance.scheduleDebouncedSync();
  }

  /// جلب الطلبات المعلقة أو السابقة للاعب
  static Future<List<Map<String, dynamic>>> getRequestsForAthlete(int athleteId) async {
    final db = await DB.db;
    final local = await db.query(
      'coach_requests',
      where: 'athlete_id = ?',
      whereArgs: [athleteId],
      orderBy: 'created_at DESC',
    );
    return local;
  }

  /// جلب الطلب المعلق الحالي للاعب (إن وجد)
  static Future<Map<String, dynamic>?> getPendingRequestForAthlete(int athleteId) async {
    final db = await DB.db;
    final rows = await db.query(
      'coach_requests',
      where: 'athlete_id = ? AND status = ?',
      whereArgs: [athleteId, 'pending'],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first;
  }

  /// إلغاء طلب انضمام معلّق
  static Future<void> cancelRequest(int requestId) async {
    final db = await DB.db;
    final now = DateTime.now().toUtc().toIso8601String();

    await db.update(
      'coach_requests',
      {
        'status': 'cancelled',
        'updated_at': now,
        'dirty': 1,
      },
      where: 'id = ?',
      whereArgs: [requestId],
    );

    try {
      await CloudApi.instance.cancelCoachRequest(requestId.toString());
    } catch (_) {}

    SyncEngine.instance.scheduleDebouncedSync();
  }

  /// جلب الطلبات المعلقة الواردة للمدرب
  static Future<List<Map<String, dynamic>>> getPendingRequestsForCoach(int coachId) async {
    final db = await DB.db;
    final rows = await db.query(
      'coach_requests',
      where: 'coach_id = ? AND status = ?',
      whereArgs: [coachId, 'pending'],
      orderBy: 'created_at DESC',
    );
    return rows;
  }

  /// رد المدرب على الطلب (قبول أو رفض)
  /// يشترط أن يكون اشتراك المدرب نشطاً
  static Future<void> respondToRequest({
    required int requestId,
    required bool accept,
    required AppUser coach,
  }) async {
    if (accept && !coach.subscriptionActive) {
      throw Exception('لا يمكن قبول اللاعبين بينما اشتراك المدرب غير مفعّل، يرجى تجديد الاشتراك أولاً');
    }

    final db = await DB.db;
    final now = DateTime.now().toUtc().toIso8601String();
    final newStatus = accept ? 'accepted' : 'rejected';

    final reqRows = await db.query(
      'coach_requests',
      where: 'id = ?',
      whereArgs: [requestId],
      limit: 1,
    );
    if (reqRows.isEmpty) return;
    final req = reqRows.first;
    final athleteId = req['athlete_id'] as int;

    await db.update(
      'coach_requests',
      {
        'status': newStatus,
        'updated_at': now,
        'dirty': 1,
      },
      where: 'id = ?',
      whereArgs: [requestId],
    );

    if (accept) {
      // ربط اللاعب بالمدرب في جدول users
      await db.update(
        'users',
        {'coach_id': coach.id},
        where: 'id = ?',
        whereArgs: [athleteId],
      );

      // التأكد من وجود اللاعب في قائمة players الخاصة بالمدرب
      final existingPlayer = await db.query(
        'players',
        where: 'id = ?',
        whereArgs: [athleteId],
      );
      if (existingPlayer.isEmpty) {
        final athleteUser = await db.query(
          'users',
          where: 'id = ?',
          whereArgs: [athleteId],
        );
        final name = athleteUser.isNotEmpty ? athleteUser.first['name'] as String : 'لاعب';
        await db.insert('players', {
          'id': athleteId,
          'name': name,
          'mhr': 195,
          'active': 1,
          'curves_shared': 0,
          'curves_shared_by': 'coach',
          'dirty': 1,
        });
      }
    }

    try {
      await CloudApi.instance.respondToCoachRequest(
        requestId: requestId.toString(),
        status: newStatus,
        coachId: coach.id.toString(),
      );
    } catch (_) {}

    SyncEngine.instance.scheduleDebouncedSync();
  }

  /// إزالة لاعب من قائمة مدرب
  static Future<void> removeAthleteFromCoach({
    required int coachId,
    required int athleteId,
  }) async {
    final db = await DB.db;

    await db.update(
      'users',
      {'coach_id': null},
      where: 'id = ? AND coach_id = ?',
      whereArgs: [athleteId, coachId],
    );

    // إلغاء تفعيل في جدول players
    await db.update(
      'players',
      {'active': 0, 'dirty': 1},
      where: 'id = ?',
      whereArgs: [athleteId],
    );

    try {
      await CloudApi.instance.removeAthleteFromCoach(
        coachId: coachId.toString(),
        athleteId: athleteId.toString(),
      );
    } catch (_) {}

    SyncEngine.instance.scheduleDebouncedSync();
  }
}
