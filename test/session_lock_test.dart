import 'package:flutter_test/flutter_test.dart';
import 'package:rowing_app/session_lock_service.dart';

void main() {
  group('SessionLockService Tests (Coach Lock Rules)', () {
    final sessionMorning = ScheduledSessionInfo(
      date: '2026-11-14',
      idx: 0,
      time: '07:00',
      kind: 'Erg',
      zone: 'Z2',
    );

    final sessionEvening = ScheduledSessionInfo(
      date: '2026-11-14',
      idx: 1,
      time: '16:00',
      kind: 'Erg',
      zone: 'Z3',
    );

    final sessionTomorrow = ScheduledSessionInfo(
      date: '2026-11-15',
      idx: 0,
      time: '08:00',
      kind: 'Erg',
      zone: 'Z4',
    );

    final allSessions = [sessionMorning, sessionEvening, sessionTomorrow];

    test('1. Next session start time arrived -> locks previous session for athlete', () {
      // الوقت 16:05 (بعد موعد الحصة المسائية 16:00)
      final now = DateTime(2026, 11, 14, 16, 5);

      final isLocked = SessionLockService.isSessionLocked(
        session: sessionMorning,
        allSessions: allSessions,
        athleteLogs: [],
        userRole: 'athlete',
        currentTime: now,
      );

      expect(isLocked, isTrue);
      expect(
        SessionLockService.checkLockReason(
          session: sessionMorning,
          allSessions: allSessions,
          athleteLogs: [],
          userRole: 'athlete',
          currentTime: now,
        ),
        SessionLockReason.nextSessionStarted,
      );
    });

    test('2. Athlete entered first number in next session -> locks previous session even before next time', () {
      // الوقت 12:00 (قبل موعد الحصة المسائية 16:00)
      final now = DateTime(2026, 11, 14, 12, 0);

      final athleteLogs = [
        {
          'date': '2026-11-14',
          'idx': 1, // الحصة المسائية
          'entered_by': 'athlete',
          'avg_power': 210,
        }
      ];

      final isLocked = SessionLockService.isSessionLocked(
        session: sessionMorning,
        allSessions: allSessions,
        athleteLogs: athleteLogs,
        userRole: 'athlete',
        currentTime: now,
      );

      expect(isLocked, isTrue);
      expect(
        SessionLockService.checkLockReason(
          session: sessionMorning,
          allSessions: allSessions,
          athleteLogs: athleteLogs,
          userRole: 'athlete',
          currentTime: now,
        ),
        SessionLockReason.nextSessionLogged,
      );
    });

    test('3. Coach numbers in next session do NOT lock session for athlete before next time', () {
      // الوقت 12:00 (قبل موعد المسائية)، والمدرب هو من أدخل أرقاماً في المسائية
      final now = DateTime(2026, 11, 14, 12, 0);

      final coachLogs = [
        {
          'date': '2026-11-14',
          'idx': 1,
          'entered_by': 'coach',
          'avg_power': 210,
        }
      ];

      final isLocked = SessionLockService.isSessionLocked(
        session: sessionMorning,
        allSessions: allSessions,
        athleteLogs: coachLogs,
        userRole: 'athlete',
        currentTime: now,
      );

      expect(isLocked, isFalse);
    });

    test('4. Empty/null entered_by (legacy rows) do NOT lock session for athlete', () {
      final now = DateTime(2026, 11, 14, 12, 0);

      final legacyLogs = [
        {
          'date': '2026-11-14',
          'idx': 1,
          'entered_by': null,
          'avg_power': 210,
        }
      ];

      final isLocked = SessionLockService.isSessionLocked(
        session: sessionMorning,
        allSessions: allSessions,
        athleteLogs: legacyLogs,
        userRole: 'athlete',
        currentTime: now,
      );

      expect(isLocked, isFalse);
    });

    test('5. Two sessions in same day: morning session is open during its window', () {
      // الساعة 10:00 صباحاً (بين 07:00 و 16:00) وبدون تسجيل في المسائية
      final now = DateTime(2026, 11, 14, 10, 0);

      final isLocked = SessionLockService.isSessionLocked(
        session: sessionMorning,
        allSessions: allSessions,
        athleteLogs: [],
        userRole: 'athlete',
        currentTime: now,
      );

      expect(isLocked, isFalse);
    });

    test('6. Last session in schedule: stays open for 24 hours, locks after 24h', () {
      // موعد الحصة الأخيرة: 2026-11-15 08:00
      // تجربة بعد 10 ساعات (نفس اليوم 18:00) -> مفتوحة
      final during24h = DateTime(2026, 11, 15, 18, 0);
      expect(
        SessionLockService.isSessionLocked(
          session: sessionTomorrow,
          allSessions: allSessions,
          athleteLogs: [],
          userRole: 'athlete',
          currentTime: during24h,
        ),
        isFalse,
      );

      // تجربة بعد 25 ساعة (2026-11-16 09:00) -> مقفولة
      final after24h = DateTime(2026, 11, 16, 9, 0);
      expect(
        SessionLockService.isSessionLocked(
          session: sessionTomorrow,
          allSessions: allSessions,
          athleteLogs: [],
          userRole: 'athlete',
          currentTime: after24h,
        ),
        isTrue,
      );
      expect(
        SessionLockService.checkLockReason(
          session: sessionTomorrow,
          allSessions: allSessions,
          athleteLogs: [],
          userRole: 'athlete',
          currentTime: after24h,
        ),
        SessionLockReason.lastSessionExpired,
      );
    });

    test('7. Coach can always edit any session even after lock', () {
      final pastTime = DateTime(2026, 11, 20, 12, 0);

      final isLockedForCoach = SessionLockService.isSessionLocked(
        session: sessionMorning,
        allSessions: allSessions,
        athleteLogs: [
          {'date': '2026-11-14', 'idx': 1, 'entered_by': 'athlete', 'avg_power': 200}
        ],
        userRole: 'coach',
        currentTime: pastTime,
      );

      expect(isLockedForCoach, isFalse);
    });

    test('8. Future session that has not started yet is locked for athlete, open for coach', () {
      // الوقت 06:30 (قبل موعد الصباحية 07:00)
      final beforeStart = DateTime(2026, 11, 14, 6, 30);

      expect(
        SessionLockService.isSessionLocked(
          session: sessionMorning,
          allSessions: allSessions,
          athleteLogs: [],
          userRole: 'athlete',
          currentTime: beforeStart,
        ),
        isTrue,
      );
      expect(
        SessionLockService.checkLockReason(
          session: sessionMorning,
          allSessions: allSessions,
          athleteLogs: [],
          userRole: 'athlete',
          currentTime: beforeStart,
        ),
        SessionLockReason.notStartedYet,
      );

      // للمدرب مفتوحة
      expect(
        SessionLockService.isSessionLocked(
          session: sessionMorning,
          allSessions: allSessions,
          athleteLogs: [],
          userRole: 'coach',
          currentTime: beforeStart,
        ),
        isFalse,
      );
    });
  });
}

