import 'package:flutter_test/flutter_test.dart';
import 'package:rowing_app/session_lock_service.dart';

void main() {
  group('SessionLockService Tests (المرحلة ج - Midnight Lock Rules)', () {
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

    test('1. Morning session is open at 23:59:59 on the same day', () {
      final now = DateTime(2026, 11, 14, 23, 59, 59);

      final isLocked = SessionLockService.isSessionLocked(
        session: sessionMorning,
        userRole: 'athlete',
        currentTime: now,
      );

      expect(isLocked, isFalse);
      expect(
        SessionLockService.checkLockReason(
          session: sessionMorning,
          userRole: 'athlete',
          currentTime: now,
        ),
        SessionLockReason.none,
      );
    });

    test(
        '2. Multiple sessions on same day both remain open until midnight even after evening session starts/logged',
        () {
      final now = DateTime(2026, 11, 14, 18, 0); // Evening session started

      // Morning session remains open
      expect(
        SessionLockService.isSessionLocked(
          session: sessionMorning,
          athleteLogs: [
            {
              'date': '2026-11-14',
              'idx': 1,
              'entered_by': 'athlete',
              'avg_power': 220
            }
          ],
          userRole: 'athlete',
          currentTime: now,
        ),
        isFalse,
      );

      // Evening session is also open
      expect(
        SessionLockService.isSessionLocked(
          session: sessionEvening,
          userRole: 'athlete',
          currentTime: now,
        ),
        isFalse,
      );
    });

    test('3. Session locks strictly at 00:00 (start of next day)', () {
      final midnightNextDay = DateTime(2026, 11, 15, 0, 0, 0);

      final isLocked = SessionLockService.isSessionLocked(
        session: sessionMorning,
        userRole: 'athlete',
        currentTime: midnightNextDay,
      );

      expect(isLocked, isTrue);
      expect(
        SessionLockService.checkLockReason(
          session: sessionMorning,
          userRole: 'athlete',
          currentTime: midnightNextDay,
        ),
        SessionLockReason.lastSessionExpired,
      );
    });

    test('4. Yesterday session is locked, today session is open', () {
      final todayNow = DateTime(2026, 11, 15, 10, 0);

      // Yesterday (14th) is locked
      expect(
        SessionLockService.isSessionLocked(
          session: sessionMorning, // 2026-11-14
          userRole: 'athlete',
          currentTime: todayNow,
        ),
        isTrue,
      );

      // Today (15th) is open
      expect(
        SessionLockService.isSessionLocked(
          session: sessionTomorrow, // 2026-11-15 08:00
          userRole: 'athlete',
          currentTime: todayNow,
        ),
        isFalse,
      );
    });

    test('5. Coach can always edit any session even after midnight lock', () {
      final pastTime = DateTime(2026, 11, 20, 12, 0);

      final isLockedForCoach = SessionLockService.isSessionLocked(
        session: sessionMorning,
        userRole: 'coach',
        currentTime: pastTime,
      );

      expect(isLockedForCoach, isFalse);
      expect(
        SessionLockService.checkLockReason(
          session: sessionMorning,
          userRole: 'coach',
          currentTime: pastTime,
        ),
        SessionLockReason.none,
      );
    });

    test(
        '6. Future session that has not started yet is locked for athlete, open for coach',
        () {
      final beforeStart = DateTime(2026, 11, 14, 6, 30);

      expect(
        SessionLockService.isSessionLocked(
          session: sessionMorning,
          userRole: 'athlete',
          currentTime: beforeStart,
        ),
        isTrue,
      );
      expect(
        SessionLockService.checkLockReason(
          session: sessionMorning,
          userRole: 'athlete',
          currentTime: beforeStart,
        ),
        SessionLockReason.notStartedYet,
      );

      expect(
        SessionLockService.isSessionLocked(
          session: sessionMorning,
          userRole: 'coach',
          currentTime: beforeStart,
        ),
        isFalse,
      );
    });
  });
}
