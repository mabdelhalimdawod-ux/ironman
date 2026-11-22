/// خدمة فحص قفل تعديل الحصص للاعب وفق القواعد المعتمدة من الكوتش
class ScheduledSessionInfo {
  final String date; // yyyy-MM-dd
  final int idx;
  final String time; // HH:mm
  final String kind;
  final String zone;

  const ScheduledSessionInfo({
    required this.date,
    required this.idx,
    required this.time,
    this.kind = 'Erg',
    this.zone = 'Z2',
  });

  DateTime get startDateTime {
    final cleanTime = time.trim().isEmpty ? '00:00' : time.trim();
    final parts = cleanTime.split(':');
    final hour = parts.isNotEmpty ? int.tryParse(parts[0]) ?? 0 : 0;
    final minute = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
    final d = DateTime.tryParse(date) ?? DateTime.now();
    return DateTime(d.year, d.month, d.day, hour, minute);
  }
}

enum SessionLockReason {
  none,
  notStartedYet,
  lastSessionExpired,
}

class SessionLockService {
  /// تفحص هل الحصة مقفولة على اللاعب للتعديل، وترجع سبب القفل
  /// وفق قواعد الكوتش: تقفل الحصة على اللاعب تماماً عند الساعة 12:00 منتصف الليل
  /// (بداية اليوم التالي لتاريخ الحصة) بالتوقيت المحلي، وتظل جميع حصص نفس اليوم مفتوحة حتى منتصف الليل.
  /// والمدرب/الأدمن يمكنه التعديل في أي وقت.
  static SessionLockReason checkLockReason({
    required ScheduledSessionInfo session,
    List<ScheduledSessionInfo> allSessions = const [],
    List<Map<String, Object?>> athleteLogs = const [],
    required String userRole,
    DateTime? currentTime,
  }) {
    // المدرب والأدمن لهما حق التعديل دائماً في أي وقت
    if (userRole == 'coach' || userRole == 'admin') {
      return SessionLockReason.none;
    }

    final now = currentTime ?? DateTime.now();

    // 1. اللاعب لا يسجل حصة لم تبدأ بعد
    if (now.isBefore(session.startDateTime)) {
      return SessionLockReason.notStartedYet;
    }

    // 2. قفل الحصة عند الساعة 12:00 منتصف الليل (بداية اليوم التالي لتاريخ الحصة) بالتوقيت المحلي
    final d = DateTime.tryParse(session.date) ?? DateTime.now();
    final midnightNextDay = DateTime(d.year, d.month, d.day + 1, 0, 0, 0);

    if (now.isAfter(midnightNextDay) || now.isAtSameMomentAs(midnightNextDay)) {
      return SessionLockReason.lastSessionExpired;
    }

    return SessionLockReason.none;
  }

  /// دالة نقية ترجع boolean مباشرة
  static bool isSessionLocked({
    required ScheduledSessionInfo session,
    List<ScheduledSessionInfo> allSessions = const [],
    List<Map<String, Object?>> athleteLogs = const [],
    required String userRole,
    DateTime? currentTime,
  }) {
    return checkLockReason(
          session: session,
          allSessions: allSessions,
          athleteLogs: athleteLogs,
          userRole: userRole,
          currentTime: currentTime,
        ) !=
        SessionLockReason.none;
  }
}
