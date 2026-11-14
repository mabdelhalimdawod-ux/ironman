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
  nextSessionStarted,
  nextSessionLogged,
  lastSessionExpired,
}

class SessionLockService {
  /// تفحص هل الحصة مقفولة على اللاعب للتعديل، وترجع سبب القفل
  static SessionLockReason checkLockReason({
    required ScheduledSessionInfo session,
    required List<ScheduledSessionInfo> allSessions,
    required List<Map<String, Object?>> athleteLogs,
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

    // ترتيب كل حصص البرنامج ترتيباً زمنياً تصاعدياً
    final sorted = List<ScheduledSessionInfo>.from(allSessions)..sort((a, b) {
      final dCmp = a.date.compareTo(b.date);
      if (dCmp != 0) return dCmp;
      final tCmp = a.startDateTime.compareTo(b.startDateTime);
      if (tCmp != 0) return tCmp;
      return a.idx.compareTo(b.idx);
    });

    final currentIndex = sorted.indexWhere(
      (s) => s.date == session.date && s.idx == session.idx,
    );

    // إذا لم تكن الحصة ضمن البرنامج (fallback): تفحص مهلة الـ 24 ساعة
    if (currentIndex == -1) {
      final deadline = session.startDateTime.add(const Duration(hours: 24));
      return (now.isAfter(deadline) || now.isAtSameMomentAs(deadline))
          ? SessionLockReason.lastSessionExpired
          : SessionLockReason.none;
    }

    final hasNext = currentIndex + 1 < sorted.length;

    if (hasNext) {
      final nextSession = sorted[currentIndex + 1];

      // أ) وقت بداية الحصة التالية جه
      if (now.isAfter(nextSession.startDateTime) ||
          now.isAtSameMomentAs(nextSession.startDateTime)) {
        return SessionLockReason.nextSessionStarted;
      }

      // ب) اللاعب كتب أول رقم في الحصة التالية
      Map<String, Object?>? nextSessionLog;
      for (final l in athleteLogs) {
        if (l['date'] == nextSession.date &&
            (l['idx'] as num?)?.toInt() == nextSession.idx) {
          nextSessionLog = l;
          break;
        }
      }

      if (nextSessionLog != null && nextSessionLog.isNotEmpty) {
        final enteredBy = nextSessionLog['entered_by'] as String?;
        // أرقام المدرب لا تقفل الحصة، فقط أرقام اللاعب نفسه
        if (enteredBy == 'athlete') {
          if (_logHasAthleteNumbers(nextSessionLog)) {
            return SessionLockReason.nextSessionLogged;
          }
        }
      }

      return SessionLockReason.none;
    } else {
      // آخر حصة في البرنامج: تفضل مفتوحة للاعب 24 ساعة من وقت بدايتها
      final deadline = session.startDateTime.add(const Duration(hours: 24));
      if (now.isAfter(deadline) || now.isAtSameMomentAs(deadline)) {
        return SessionLockReason.lastSessionExpired;
      }
      return SessionLockReason.none;
    }
  }

  /// دالة نقية ترجع boolean مباشرة
  static bool isSessionLocked({
    required ScheduledSessionInfo session,
    required List<ScheduledSessionInfo> allSessions,
    required List<Map<String, Object?>> athleteLogs,
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

  static bool _logHasAthleteNumbers(Map<String, Object?> log) {
    const numberFields = [
      'avg_power',
      'split_500',
      'distance',
      'hr',
      'hr_post',
      'hr_1min',
      'decoupling',
      'eupnea_1',
      'eupnea_2',
      'eupnea_3',
    ];
    for (final f in numberFields) {
      final val = log[f];
      if (val != null) {
        if (val is num && val > 0) return true;
        if (val is String && val.trim().isNotEmpty) return true;
      }
    }
    return false;
  }
}
