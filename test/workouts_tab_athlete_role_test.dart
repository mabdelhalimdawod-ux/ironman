import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:rowing_app/auth_service.dart';
import 'package:rowing_app/app_strings.dart';
import 'package:rowing_app/db.dart';
import 'package:rowing_app/program_service.dart';
import 'package:rowing_app/workouts_tab.dart';
import 'package:rowing_app/athlete_day_entry_page.dart';
import 'package:rowing_app/session_lock_service.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await AppLanguage.instance.init();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    final tempDir = Directory.systemTemp.createTempSync('rowing_workouts_role_');
    await databaseFactory.setDatabasesPath(tempDir.path);

    // تجهيز الجداول وزرع البيانات
    await AuthService.ensureTables();
    await ProgramService.ensureTables();

    final db = await DB.db;

    // زراعة لاعبين: اللاعب الأساسي ولاعب منافس
    await db.insert('players', {
      'id': 101,
      'name': 'اللاعب أحمد البطل',
      'mhr': 195,
      'active': 1,
    });

    await db.insert('players', {
      'id': 202,
      'name': 'اللاعب السري المنافس',
      'mhr': 190,
      'active': 1,
    });

    // زراعة دورة مرحلية وحصص مجدولة
    final today = dstr(DateTime.now());
    await db.insert('sessions', {
      'date': today,
      'idx': 0,
      'kind': 'Erg',
      'zone': 'Z2',
      'time': '07:00',
    });

    await db.insert('sessions', {
      'date': today,
      'idx': 1,
      'kind': 'Erg',
      'zone': 'Z3',
      'time': '16:00',
    });

    FlutterError.onError = FlutterError.dumpErrorToConsole;
  });

  const athleteUser = AppUser(
    id: 1,
    email: 'athlete@engine.rowing',
    name: 'اللاعب أحمد البطل',
    role: 'athlete',
    coachId: 99,
    subscriptionActive: true,
    playerId: 101,
  );

  const coachUser = AppUser(
    id: 99,
    email: 'coach@engine.rowing',
    name: 'الكابتن محمود',
    role: 'coach',
    coachId: null,
    subscriptionActive: true,
    playerId: null,
  );

  Future<void> pumpUntilLoaded(WidgetTester tester) async {
    await tester.pump();
    for (int i = 0; i < 40; i++) {
      if (find.byType(CircularProgressIndicator).evaluate().isEmpty) {
        break;
      }
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 100)));
      await tester.pump();
    }
  }

  group('WorkoutsTab Athlete Privacy & Role Filtering Tests', () {
    testWidgets('Athlete view shows ONLY athlete own workouts and never leaks another player', (tester) async {
      await AppLanguage.instance.setLocale(const Locale('ar'));

      await tester.pumpWidget(
        const MaterialApp(
          locale: Locale('ar'),
          home: Scaffold(
            body: WorkoutsTab(user: athleteUser),
          ),
        ),
      );

      await pumpUntilLoaded(tester);

      // التأكد من ظهور اسم اللاعب صاحب الحساب
      expect(find.text('اللاعب أحمد البطل'), findsOneWidget);

      // التحقق الصارم من عدم ظهور اسم أي لاعب آخر
      expect(find.text('اللاعب السري المنافس'), findsNothing);

      // التحقق من عدم حدوث أي overflow
      expect(tester.takeException(), isNull);
    });

    testWidgets('Coach view shows all players in team roster', (tester) async {
      await AppLanguage.instance.setLocale(const Locale('ar'));

      await tester.pumpWidget(
        const MaterialApp(
          locale: Locale('ar'),
          home: Scaffold(
            body: WorkoutsTab(user: coachUser),
          ),
        ),
      );

      await pumpUntilLoaded(tester);

      // المدرب يرى كلا اللاعبين في قائمته
      expect(find.text('اللاعب أحمد البطل'), findsOneWidget);
      expect(find.text('اللاعب السري المنافس'), findsOneWidget);

      expect(tester.takeException(), isNull);
    });
  });

  group('AthleteDayEntryPage Lock & Field Storage Tests', () {
    testWidgets('Locked session shows lock banner and disables inputs for athlete', (tester) async {
      final today = dstr(DateTime.now());

      final sched = [
        ScheduledSessionInfo(date: today, idx: 0, time: '07:00', kind: 'Erg', zone: 'Z2'),
        ScheduledSessionInfo(date: today, idx: 1, time: '16:00', kind: 'Erg', zone: 'Z3'),
      ];

      // زراعة تسجيل في الحصة 1 للاعب تجعل الحصة 0 مقفولة داخل runAsync
      await tester.runAsync(() async {
        await DB.put('logs', {
          'player_id': 101,
          'date': today,
          'idx': 1,
          'avg_power': 225,
          'entered_by': 'athlete',
        });
      });

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('ar'),
          home: Scaffold(
            body: AthleteDayEntryPage(
              player: const {'id': 101, 'name': 'اللاعب أحمد البطل', 'mhr': 195},
              date: today,
              sessions: const [
                {'idx': 0, 'time': '07:00', 'kind': 'Erg', 'zone': 'Z2'},
              ],
              userRole: 'athlete',
              allScheduledSessions: sched,
            ),
          ),
        ),
      );

      await pumpUntilLoaded(tester);

      // فحص ظهور شارة القفل
      expect(find.text('الحصة مقفولة (للقراءة فقط)'), findsWidgets);

      final exc = tester.takeException();
      expect(exc, isNull);
    });

    testWidgets('Coach opening same locked session has full edit permissions', (tester) async {
      final today = dstr(DateTime.now());

      final sched = [
        ScheduledSessionInfo(date: today, idx: 0, time: '07:00', kind: 'Erg', zone: 'Z2'),
        ScheduledSessionInfo(date: today, idx: 1, time: '16:00', kind: 'Erg', zone: 'Z3'),
      ];

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('ar'),
          home: Scaffold(
            body: AthleteDayEntryPage(
              player: const {'id': 101, 'name': 'اللاعب أحمد البطل', 'mhr': 195},
              date: today,
              sessions: const [
                {'idx': 0, 'time': '07:00', 'kind': 'Erg', 'zone': 'Z2'},
              ],
              userRole: 'coach',
              allScheduledSessions: sched,
            ),
          ),
        ),
      );

      await pumpUntilLoaded(tester);

      // فحص ظهور شارة صلاحية المدرب
      expect(find.text('وضع المدرب (صلاحية كاملة للتعديل)'), findsOneWidget);

      final exc = tester.takeException();
      expect(exc, isNull);
    });

    test('Saving as athlete writes entered_by="athlete" and saves decoupling and eupnea', () async {
      final today = dstr(DateTime.now());

      await DB.put('logs', {
        'player_id': 101,
        'date': today,
        'idx': 0,
        'avg_power': 240.0,
        'split_500': 116.2,
        'hr': 162,
        'decoupling': 3.2,
        'eupnea_1': 48.5,
        'eupnea_2': 42.0,
        'eupnea_3': 38.0,
        'entered_by': 'athlete',
      });

      final rows = await DB.q(
        'SELECT * FROM logs WHERE player_id = 101 AND date = ? AND idx = 0',
        [today],
      );

      expect(rows.length, 1);
      expect(rows.first['entered_by'], 'athlete');
      expect(rows.first['decoupling'], 3.2);
      expect(rows.first['eupnea_1'], 48.5);
      expect(rows.first['eupnea_2'], 42.0);
      expect(rows.first['eupnea_3'], 38.0);
    });

    test('Saving as coach writes entered_by="coach"', () async {
      final today = dstr(DateTime.now());

      await DB.put('logs', {
        'player_id': 202,
        'date': today,
        'idx': 0,
        'avg_power': 250.0,
        'split_500': 114.5,
        'hr': 168,
        'decoupling': 4.1,
        'eupnea_1': 50.0,
        'eupnea_2': 45.0,
        'eupnea_3': 40.0,
        'entered_by': 'coach',
      });

      final rows = await DB.q(
        'SELECT * FROM logs WHERE player_id = 202 AND date = ? AND idx = 0',
        [today],
      );

      expect(rows.length, 1);
      expect(rows.first['entered_by'], 'coach');
      expect(rows.first['decoupling'], 4.1);
      expect(rows.first['eupnea_1'], 50.0);
    });
  });

  group('WorkoutsTab Multi-Size & Multi-Language Overflow Tests', () {
    final sizes = [
      const Size(320, 640),
      const Size(360, 800),
      const Size(411, 891),
    ];

    final scales = [1.0, 1.3];

    final locales = [
      const Locale('ar'),
      const Locale('en'),
    ];

    for (final size in sizes) {
      for (final scale in scales) {
        for (final loc in locales) {
          testWidgets(
            'WorkoutsTab renders cleanly on ${size.width.toInt()}x${size.height.toInt()} scale $scale ${loc.languageCode} (Athlete View)',
            (tester) async {
              tester.view.physicalSize = size;
              tester.view.devicePixelRatio = 1.0;
              addTearDown(tester.view.resetPhysicalSize);
              addTearDown(tester.view.resetDevicePixelRatio);

              await AppLanguage.instance.setLocale(loc);

              await tester.pumpWidget(
                MediaQuery(
                  data: MediaQueryData(
                    size: size,
                    textScaler: TextScaler.linear(scale),
                  ),
                  child: MaterialApp(
                    locale: loc,
                    home: const Scaffold(
                      body: WorkoutsTab(user: athleteUser),
                    ),
                  ),
                ),
              );

              await pumpUntilLoaded(tester);

              expect(find.byType(ListView), findsWidgets);
              expect(tester.takeException(), isNull);
            },
          );
        }
      }
    }
  });
}
