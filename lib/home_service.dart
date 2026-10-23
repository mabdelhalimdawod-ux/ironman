import 'package:flutter/material.dart';
import 'db.dart';

/// بطاقة إحصائية مميزة (Highlight Card Model)
class HighlightItem {
  final String id;
  final String titleAr;
  final String titleEn;
  final String value;
  final String? subtitle;
  final IconData icon;
  final int colorHex;

  const HighlightItem({
    required this.id,
    required this.titleAr,
    required this.titleEn,
    required this.value,
    this.subtitle,
    required this.icon,
    required this.colorHex,
  });
}

/// موعد اختبار تدريبي (Testing Date Model)
class TestingDateItem {
  final int id;
  final int coachId;
  final String testName;
  final String testDate;
  final List<int> recipientIds;

  const TestingDateItem({
    required this.id,
    required this.coachId,
    required this.testName,
    required this.testDate,
    required this.recipientIds,
  });
}

/// رسالة المدرب (Coach Message Model)
class CoachMessageItem {
  final int id;
  final int athleteId;
  final int coachId;
  final String coachName;
  final String message;
  final String date;
  final bool isRead;

  const CoachMessageItem({
    required this.id,
    required this.athleteId,
    required this.coachId,
    required this.coachName,
    required this.message,
    required this.date,
    required this.isRead,
  });
}

/// خدمة بيانات الشاشة الرئيسية (Home Service)
class HomeService {
  /// جلب بطاقات المؤشرات (Highlights) للاعب أو الفريق
  /// الكارت لا يُعرض إلا إذا توفرت بيانات حقيقية
  static Future<List<HighlightItem>> getHighlights({int? playerId}) async {
    final highlights = <HighlightItem>[];
    final database = await DB.db;

    try {
      // 1. Dynamic Zone - آخر زون تدريبي مستخدم من سجلات logs
      String? latestZone;
      if (playerId != null) {
        final r = await database.rawQuery('''
          SELECT s.zone FROM logs l
          JOIN sessions s ON l.date = s.date AND l.idx = s.idx
          WHERE l.player_id = ? AND s.zone IS NOT NULL AND s.zone != ''
          ORDER BY l.date DESC LIMIT 1
        ''', [playerId]);
        if (r.isNotEmpty) {
          latestZone = r.first['zone'] as String?;
        }
      }
      if (latestZone == null) {
        // فحص آخر حصة تدريبية عامة تم تسجيلها
        final r2 = await database.rawQuery('''
          SELECT zone FROM sessions WHERE zone IS NOT NULL AND zone != '' ORDER BY date DESC LIMIT 1
        ''');
        if (r2.isNotEmpty) {
          latestZone = r2.first['zone'] as String?;
        }
      }

      if (latestZone != null && latestZone.isNotEmpty) {
        highlights.add(HighlightItem(
          id: 'dynamic_zone',
          titleAr: 'آخر زون تدريبي',
          titleEn: 'Latest Zone',
          value: latestZone,
          subtitle: 'Target HR Training Zone',
          icon: Icons.speed_rounded,
          colorHex: 0xFF2196F3,
        ));
      }

      // 2. Critical Power (CP) - آخر قيمة CP محسوبة
      double? cpValue;
      if (playerId != null) {
        cpValue = await DB.playerCP(playerId);
      } else {
        // متوسط CP لجميع اللاعبين النشطين
        final r = await database.rawQuery(
          'SELECT AVG(cp) as avg_cp FROM cp_values WHERE cp > 0',
        );
        if (r.isNotEmpty && r.first['avg_cp'] != null) {
          cpValue = (r.first['avg_cp'] as num).toDouble();
        }
      }

      if (cpValue != null && cpValue > 0) {
        highlights.add(HighlightItem(
          id: 'cp_power',
          titleAr: 'القدرة الحرجة (CP)',
          titleEn: 'Critical Power (CP)',
          value: '${cpValue.round()} W',
          subtitle: 'Aerobic Threshold Power',
          icon: Icons.bolt_rounded,
          colorHex: 0xFFFFC93C,
        ));
      }

      // 3. Daily Wellness - آخر HRV + نبض راحة + نوم
      Map<String, dynamic>? latestLog;
      if (playerId != null) {
        latestLog = await DB.latestLog(playerId);
      } else {
        final r = await database.rawQuery(
          'SELECT rhr, hrv, fatigue, sleep_hours FROM logs ORDER BY date DESC LIMIT 1',
        );
        if (r.isNotEmpty) latestLog = r.first;
      }

      if (latestLog != null && (latestLog['hrv'] != null || latestLog['rhr'] != null)) {
        final hrv = latestLog['hrv'];
        final rhr = latestLog['rhr'];
        final sleep = latestLog['sleep_hours'];
        final parts = <String>[];
        if (hrv != null) parts.add('HRV: $hrv ms');
        if (rhr != null) parts.add('RHR: $rhr bpm');
        if (sleep != null) parts.add('Sleep: ${sleep}h');

        highlights.add(HighlightItem(
          id: 'daily_wellness',
          titleAr: 'المؤشرات الحيوية اليومية',
          titleEn: 'Daily Wellness',
          value: parts.isNotEmpty ? parts.first : 'Active',
          subtitle: parts.length > 1 ? parts.sublist(1).join(' • ') : null,
          icon: Icons.favorite_rounded,
          colorHex: 0xFF4CAF50,
        ));
      }
    } catch (_) {}

    return highlights;
  }

  /// جلب أحدث رسالة غير مقروءة من المدرب للاعب
  static Future<CoachMessageItem?> getUnreadCoachMessage(int athleteUserId) async {
    final database = await DB.db;
    try {
      final rows = await database.rawQuery('''
        SELECT m.*, u.name as coach_name
        FROM coach_messages m
        LEFT JOIN users u ON m.coach_id = u.id
        WHERE m.athlete_id = ? AND m.is_read = 0
        ORDER BY m.id DESC LIMIT 1
      ''', [athleteUserId]);

      if (rows.isEmpty) return null;
      final r = rows.first;
      return CoachMessageItem(
        id: r['id'] as int,
        athleteId: r['athlete_id'] as int,
        coachId: r['coach_id'] as int,
        coachName: (r['coach_name'] as String?) ?? 'Coach',
        message: (r['message'] as String?) ?? '',
        date: (r['date'] as String?) ?? '',
        isRead: (r['is_read'] as int? ?? 0) == 1,
      );
    } catch (_) {
      return null;
    }
  }

  /// تحديد رسالة كمقروءة
  static Future<void> markMessageRead(int messageId) async {
    final database = await DB.db;
    await database.update(
      'coach_messages',
      {'is_read': 1},
      where: 'id = ?',
      whereArgs: [messageId],
    );
  }

  /// إرسال رسالة من المدرب للاعب
  static Future<void> sendCoachMessage({
    required int athleteUserId,
    required int coachUserId,
    required String message,
  }) async {
    final database = await DB.db;
    await database.insert('coach_messages', {
      'athlete_id': athleteUserId,
      'coach_id': coachUserId,
      'message': message.trim(),
      'date': DateTime.now().toIso8601String().substring(0, 10),
      'is_read': 0,
    });
  }

  /// جلب مواعيد الاختبارات القادمة (test_date >= today)
  static Future<List<TestingDateItem>> getUpcomingTestingDates({
    int? athleteUserId,
    int? coachUserId,
  }) async {
    final database = await DB.db;
    final now = DateTime.now();
    final today =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    try {
      List<Map<String, dynamic>> rows;
      if (coachUserId != null) {
        // المدرب يرى الاختبارات التي جدولها هو
        rows = await database.rawQuery('''
          SELECT * FROM testing_dates
          WHERE coach_id = ? AND test_date >= ?
          ORDER BY test_date ASC
        ''', [coachUserId, today]);
      } else if (athleteUserId != null) {
        // اللاعب يرى الاختبارات الموجهة له أو العامة
        rows = await database.rawQuery('''
          SELECT t.* FROM testing_dates t
          JOIN testing_date_recipients r ON t.id = r.testing_date_id
          WHERE r.athlete_id = ? AND t.test_date >= ?
          ORDER BY t.test_date ASC
        ''', [athleteUserId, today]);
      } else {
        rows = await database.rawQuery('''
          SELECT * FROM testing_dates
          WHERE test_date >= ?
          ORDER BY test_date ASC
        ''', [today]);
      }

      final items = <TestingDateItem>[];
      for (final r in rows) {
        final testId = r['id'] as int;
        final recRows = await database.rawQuery(
          'SELECT athlete_id FROM testing_date_recipients WHERE testing_date_id = ?',
          [testId],
        );
        final recIds = recRows.map((e) => e['athlete_id'] as int).toList();

        items.add(TestingDateItem(
          id: testId,
          coachId: r['coach_id'] as int,
          testName: (r['test_name'] as String?) ?? '',
          testDate: (r['test_date'] as String?) ?? '',
          recipientIds: recIds,
        ));
      }
      return items;
    } catch (_) {
      return [];
    }
  }

  /// إضافة موعد اختبار جديد مع تحديد المستلمين
  static Future<void> addTestingDate({
    required int coachUserId,
    required String testName,
    required String testDate,
    required List<int> athleteUserIds,
  }) async {
    final database = await DB.db;
    final id = await database.insert('testing_dates', {
      'coach_id': coachUserId,
      'test_name': testName.trim(),
      'test_date': testDate,
      'created_at': DateTime.now().toIso8601String(),
    });

    for (final athleteId in athleteUserIds) {
      await database.insert('testing_date_recipients', {
        'testing_date_id': id,
        'athlete_id': athleteId,
      });
    }
  }

  /// حذف موعد اختبار
  static Future<void> deleteTestingDate(int testId) async {
    final database = await DB.db;
    await database.delete('testing_date_recipients', where: 'testing_date_id = ?', whereArgs: [testId]);
    await database.delete('testing_dates', where: 'id = ?', whereArgs: [testId]);
  }

  /// جلب قائمة اللاعبين التابعين للمدرب
  static Future<List<Map<String, dynamic>>> getCoachAthletes(int coachUserId) async {
    final database = await DB.db;
    try {
      final rows = await database.rawQuery('''
        SELECT id, name, email FROM users
        WHERE role = 'athlete' AND coach_id = ?
        ORDER BY name ASC
      ''', [coachUserId]);
      if (rows.isNotEmpty) return rows;

      // لو مفيش، هات كل اللاعبين
      return await database.rawQuery('''
        SELECT id, name, email FROM users WHERE role = 'athlete' ORDER BY name ASC
      ''');
    } catch (_) {
      return [];
    }
  }
}
