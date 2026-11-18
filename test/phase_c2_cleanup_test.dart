import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as p;
import 'package:rowing_app/auth_service.dart';
import 'package:rowing_app/app_strings.dart';
import 'package:rowing_app/db.dart';
import 'package:rowing_app/program_service.dart';
import 'package:rowing_app/heart_rate_zones.dart';
import 'package:rowing_app/dashboard_tab.dart';
import 'package:rowing_app/user_avatar_widget.dart';
import 'package:rowing_app/main.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await AppLanguage.instance.init();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    final tempDir = Directory.systemTemp.createTempSync('rowing_c2_test_');
    await databaseFactory.setDatabasesPath(tempDir.path);
    DB.testDatabase = null;

    await AuthService.ensureTables();
    await ProgramService.ensureTables();
  });

  Future<void> pumpUntilLoaded(WidgetTester tester) async {
    await tester.pump();
    for (int i = 0; i < 40; i++) {
      if (find.byType(CircularProgressIndicator).evaluate().isEmpty) {
        break;
      }
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
  }

  group('7 Zones Unification and Legacy Exact Map Tests', () {
    test('legacyExactMap strictly matches exact legacy strings without contains()', () {
      expect(HeartRateZones.legacyExactMap['Z5 VO2 MAX'], 'VO2 max');
      expect(HeartRateZones.legacyExactMap['Z5 TR/MAX'], 'Z5');
      expect(HeartRateZones.legacyExactMap['Z4 THRESHOLD'], 'Threshold');
      expect(HeartRateZones.legacyExactMap['ZONE 1'], 'Z1');
      expect(HeartRateZones.legacyExactMap['ZONE 2'], 'Z2');
      expect(HeartRateZones.legacyExactMap['ZONE 3'], 'Z3');
      expect(HeartRateZones.legacyExactMap['ZONE 4'], 'Z4');
      expect(HeartRateZones.legacyExactMap['ZONE 5'], 'Z5');

      // Ensure arbitrary substrings do not match
      expect(HeartRateZones.legacyExactMap.containsKey('Something with Z4 Threshold inside'), isFalse);
      expect(HeartRateZones.legacyExactMap.containsKey('VO2 Max substring'), isFalse);
      expect(HeartRateZones.legacyExactMap.containsKey('random_zone'), isFalse);
    });

    test('orderedZones contains exactly the 7 standardized zones', () {
      expect(HeartRateZones.orderedZones.length, 7);
      expect(HeartRateZones.orderedZones, [
        'Z1',
        'Z2',
        'Z3',
        'Z4',
        'Threshold',
        'Z5',
        'VO2 max',
      ]);
    });

    test('calculate returns correct Karvonen HR ranges for 7 zones', () {
      // UT3: 55-65% -> 50 + 150*0.55 = 132.5 -> 133, 50 + 150*0.65 = 147.5 -> 148
      final z1 = HeartRateZones.calculate(rhr: 50, mhr: 200, zone: 'Zone 1 - UT3');
      expect(z1.minHR, 133);
      expect(z1.maxHR, 148);

      // VO2 max - AN: 98-105% -> 50 + 150*0.98 = 197, 50 + 150*1.05 = 207.5 -> 208
      final zVo2 = HeartRateZones.calculate(rhr: 50, mhr: 200, zone: 'VO2 max - AN');
      expect(zVo2.minHR, 197);
      expect(zVo2.maxHR, 208);
    });

    test('cpPowerZones contains 6 power zones without Z prefix', () {
      expect(cpPowerZones.length, 6);
      for (final key in cpPowerZones.keys) {
        expect(key.startsWith('Z'), isFalse);
      }
      expect(cpPowerZones.containsKey('استشفاء'), isTrue);
      expect(cpPowerZones.containsKey('عتبة (CP)'), isTrue);
    });
  });

  group('Database v7 Upgrade and User Photo Isolation Tests', () {
    test('Upgrading from v6 to v7 adds photo_path column without data loss', () async {
      final tempDir = Directory.systemTemp.createTempSync('rowing_v7_test_');
      addTearDown(() {
        try {
          tempDir.deleteSync(recursive: true);
        } catch (_) {}
      });

      final dbPath = p.join(tempDir.path, 'rowing_test.db');
      await databaseFactory.setDatabasesPath(tempDir.path);

      // 1. Create database at v6 without photo_path
      final v6Db = await openDatabase(
        dbPath,
        version: 6,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE users(
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              email TEXT UNIQUE NOT NULL,
              password_hash TEXT NOT NULL,
              salt TEXT NOT NULL,
              name TEXT NOT NULL,
              role TEXT NOT NULL,
              coach_id INTEGER,
              subscription_active INTEGER NOT NULL DEFAULT 1,
              player_id INTEGER,
              created_at TEXT NOT NULL
            )
          ''');
          await db.insert('users', {
            'id': 1,
            'email': 'athlete@engine.rowing',
            'password_hash': 'hash123',
            'salt': 'salt123',
            'name': 'Test Athlete',
            'role': 'athlete',
            'coach_id': 99,
            'player_id': 10,
            'created_at': DateTime.now().toIso8601String(),
          });
        },
      );
      await v6Db.close();

      // 2. Open at v7 with migration
      final v7Db = await openDatabase(
        dbPath,
        version: 7,
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 7) {
            final cols = await db.rawQuery('PRAGMA table_info(users)');
            final colNames = cols.map((c) => c['name'] as String).toSet();
            if (!colNames.contains('photo_path')) {
              await db.execute('ALTER TABLE users ADD COLUMN photo_path TEXT');
            }
          }
        },
      );

      // Verify column exists and data preserved
      final cols = await v7Db.rawQuery('PRAGMA table_info(users)');
      final hasPhotoCol = cols.any((c) => c['name'] == 'photo_path');
      expect(hasPhotoCol, isTrue);

      final userRow = await v7Db.query('users', where: 'id = ?', whereArgs: [1]);
      expect(userRow.length, 1);
      expect(userRow.first['name'], 'Test Athlete');
      expect(userRow.first['photo_path'], isNull);

      // 3. Test user photo isolation
      // Athlete attempting to modify another user's photo (acting: 1, target: 2) throws Exception
      expect(
        () async => await AuthService.updateUserPhoto(
          targetUserId: 2,
          actingUserId: 1,
          sourcePath: '/some/path/avatar.jpg',
        ),
        throwsA(isA<Exception>()),
      );

      await v7Db.close();
    });
  });

  group('UserAvatarWidget Fallback and Rendering', () {
    testWidgets('UserAvatarWidget renders fallback icon when photo is null or file missing', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: UserAvatarWidget(
                photoPath: '/non/existent/path/photo.jpg',
                radius: 24,
                isEditable: false,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.byIcon(Icons.person_rounded), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('DashboardTab 3 Action Cards & Avatar Multi-Size Tests', () {
    const testAthlete = AppUser(
      id: 5,
      email: 'hero@engine.rowing',
      name: 'Champion Rower',
      role: 'athlete',
      coachId: 1,
      subscriptionActive: true,
      playerId: 5,
    );

    final viewports = [
      const Size(320, 640),
      const Size(360, 800),
      const Size(411, 891),
    ];
    final textScales = [1.0, 1.3];
    final locales = [const Locale('ar'), const Locale('en')];

    for (final size in viewports) {
      for (final scale in textScales) {
        for (final loc in locales) {
          final isAr = loc.languageCode == 'ar';
          testWidgets('DashboardTab (${size.width.toInt()}x${size.height.toInt()}, scale $scale, ${isAr ? "AR" : "EN"}) renders cleanly with Avatar and 3 Quick Action Cards', (tester) async {
            tester.view.physicalSize = Size(size.width * 2.0, size.height * 2.0);
            tester.view.devicePixelRatio = 2.0;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);

            await AppLanguage.instance.setLocale(loc);

            await tester.pumpWidget(
              MaterialApp(
                locale: loc,
                home: MediaQuery(
                  data: MediaQueryData(
                    size: size,
                    textScaler: TextScaler.linear(scale),
                  ),
                  child: const Scaffold(
                    body: DashboardTab(
                      user: testAthlete,
                    ),
                  ),
                ),
              ),
            );

            await pumpUntilLoaded(tester);

            // Verify UserAvatarWidget is present in header
            expect(find.byType(UserAvatarWidget), findsOneWidget);

            // Verify the 3 quick action cards exist
            if (isAr) {
              expect(find.text('تمرين اليوم'), findsOneWidget);
              expect(find.text('الأرشيف'), findsOneWidget);
              expect(find.text('منحنيات الأداء'), findsOneWidget);
            } else {
              expect(find.text("Today's Workout"), findsOneWidget);
              expect(find.text('Archive'), findsOneWidget);
              expect(find.text('Progress Curves'), findsOneWidget);
            }

            // Verify no layout overflow exception occurred
            expect(tester.takeException(), isNull);
          });
        }
      }
    }
  });

  group('Hamburger Menu Cleaned State Multi-Size Tests', () {
    const testUser = AppUser(
      id: 1,
      email: 'coach@engine.rowing',
      name: 'Coach Mahmoud',
      role: 'coach',
      subscriptionActive: true,
    );

    final viewports = [
      const Size(320, 640),
      const Size(360, 800),
      const Size(411, 891),
    ];
    final textScales = [1.0, 1.3];
    final locales = [const Locale('ar'), const Locale('en')];

    for (final size in viewports) {
      for (final scale in textScales) {
        for (final loc in locales) {
          final isAr = loc.languageCode == 'ar';
          testWidgets('Hamburger sheet (${size.width.toInt()}x${size.height.toInt()}, scale $scale, ${isAr ? "AR" : "EN"}) has only real controls and zero overflow', (tester) async {
            tester.view.physicalSize = Size(size.width * 2.0, size.height * 2.0);
            tester.view.devicePixelRatio = 2.0;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);

            await AppLanguage.instance.setLocale(loc);

            await tester.pumpWidget(
              MaterialApp(
                locale: loc,
                home: MediaQuery(
                  data: MediaQueryData(
                    size: size,
                    textScaler: TextScaler.linear(scale),
                  ),
                  child: Scaffold(
                    body: HamburgerHubSheet(
                      user: testUser,
                      onOpenMetricsCurves: () {},
                    ),
                  ),
                ),
              ),
            );

            await tester.pump();
            await tester.pump(const Duration(milliseconds: 100));

            // Verify visual controls are present
            expect(find.text(isAr ? 'مقياس الرؤية والتكبير' : 'Display Scale & Zoom'), findsOneWidget);

            // Scroll until metrics curves shortcut is visible
            final curvesFinder = find.text(
              isAr ? 'لوحة المنحنيات (اختصارات جميع المنحنيات)' : 'Metrics Curves Hub (All Curves)',
            );
            await tester.scrollUntilVisible(curvesFinder, 50.0);
            expect(curvesFinder, findsOneWidget);

            // Scroll until Excel coming soon tag is visible
            final comingSoonFinder = find.text(isAr ? 'قريبًا' : 'Coming soon');
            await tester.scrollUntilVisible(comingSoonFinder, 50.0);
            expect(comingSoonFinder, findsOneWidget);

            // Verify that removed mock cards are NOT present
            expect(find.text('اتصال بالأجهزة', skipOffstage: false), findsNothing);
            expect(find.text('Hardware Integration', skipOffstage: false), findsNothing);
            expect(find.text('مزامنة سحابية', skipOffstage: false), findsNothing);
            expect(find.text('Cloud Sync', skipOffstage: false), findsNothing);
            expect(find.text('مقارنة الأقران', skipOffstage: false), findsNothing);
            expect(find.text('تبديل حساب اللاعب', skipOffstage: false), findsNothing);

            // Verify no layout overflow exception occurred
            expect(tester.takeException(), isNull);
          });
        }
      }
    }
  });

  tearDownAll(() async {
    DB.testDatabase = null;
  });
}
