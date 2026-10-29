import 'package:flutter_test/flutter_test.dart';
import 'package:rowing_app/app_strings.dart';
import 'package:rowing_app/auth_service.dart';

void main() {
  group('AuthService - Time-based Greetings Tests', () {
    test('getGreetingPeriod returns morning before 12:00', () {
      final t1 = DateTime(2026, 10, 23, 6, 0);
      final t2 = DateTime(2026, 10, 23, 11, 59, 59);

      expect(AuthService.getGreetingPeriod(t1), equals('morning'));
      expect(AuthService.getGreetingPeriod(t2), equals('morning'));
    });

    test('getGreetingPeriod returns afternoon between 12:00 and 16:59', () {
      final t1 = DateTime(2026, 10, 23, 12, 0);
      final t2 = DateTime(2026, 10, 23, 14, 30);
      final t3 = DateTime(2026, 10, 23, 16, 59, 59);

      expect(AuthService.getGreetingPeriod(t1), equals('afternoon'));
      expect(AuthService.getGreetingPeriod(t2), equals('afternoon'));
      expect(AuthService.getGreetingPeriod(t3), equals('afternoon'));
    });

    test('getGreetingPeriod returns evening from 17:00 onwards', () {
      final t1 = DateTime(2026, 10, 23, 17, 0);
      final t2 = DateTime(2026, 10, 23, 21, 15);
      final t3 = DateTime(2026, 10, 23, 23, 59, 59);

      expect(AuthService.getGreetingPeriod(t1), equals('evening'));
      expect(AuthService.getGreetingPeriod(t2), equals('evening'));
      expect(AuthService.getGreetingPeriod(t3), equals('evening'));
    });

    test('AppStrings formats greeting with name correctly in Arabic and English', () {
      const arStrings = AppStrings(true);
      const enStrings = AppStrings(false);

      expect(arStrings.greetingWithName('زياد', 'صباح الخير'), equals('صباح الخير يا زياد'));
      expect(enStrings.greetingWithName('Ziad', 'Good Morning'), equals('Good Morning, Ziad'));
    });
  });

  group('AuthService - Password Hashing & Security', () {
    test('hashPassword produces consistent SHA-256 hex string', () {
      final hash1 = AuthService.hashPassword('admin123', 'test_salt');
      final hash2 = AuthService.hashPassword('admin123', 'test_salt');
      final hashDiff = AuthService.hashPassword('different_password', 'test_salt');

      expect(hash1, equals(hash2));
      expect(hash1.length, equals(64)); // 256 bits = 64 hex characters
      expect(hash1, isNot(equals(hashDiff)));
    });
  });

  group('AppUser Model & Roles', () {
    test('AppUser parses role correctly', () {
      final admin = AppUser(
        id: 1,
        email: 'admin@engine.rowing',
        name: 'Admin',
        role: 'admin',
        subscriptionActive: true,
      );
      expect(admin.isAdmin, isTrue);
      expect(admin.isCoach, isFalse);
      expect(admin.isAthlete, isFalse);

      final coach = AppUser(
        id: 2,
        email: 'coach@engine.rowing',
        name: 'Coach Tamer',
        role: 'coach',
        subscriptionActive: true,
      );
      expect(coach.isAdmin, isFalse);
      expect(coach.isCoach, isTrue);
      expect(coach.isAthlete, isFalse);

      final athlete = AppUser(
        id: 3,
        email: 'athlete@engine.rowing',
        name: 'Ziad',
        role: 'athlete',
        coachId: 2,
        subscriptionActive: true,
        playerId: 1,
      );
      expect(athlete.isAdmin, isFalse);
      expect(athlete.isCoach, isFalse);
      expect(athlete.isAthlete, isTrue);
      expect(athlete.coachId, equals(2));
      expect(athlete.playerId, equals(1));
    });

    test('AppUser serialization to and from Map', () {
      final original = AppUser(
        id: 42,
        email: 'test@example.com',
        name: 'Test Athlete',
        role: 'athlete',
        coachId: 10,
        subscriptionActive: true,
        playerId: 5,
        createdAt: '2026-10-23T04:00:00Z',
      );

      final map = original.toMap();
      final restored = AppUser.fromMap(map);

      expect(restored.id, equals(original.id));
      expect(restored.email, equals(original.email));
      expect(restored.name, equals(original.name));
      expect(restored.role, equals(original.role));
      expect(restored.coachId, equals(original.coachId));
      expect(restored.subscriptionActive, equals(original.subscriptionActive));
      expect(restored.playerId, equals(original.playerId));
      expect(restored.createdAt, equals(original.createdAt));
    });
  });
}
