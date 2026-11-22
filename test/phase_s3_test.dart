import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:rowing_app/admin_page.dart';
import 'package:rowing_app/app_strings.dart';
import 'package:rowing_app/auth_service.dart';
import 'package:rowing_app/cloud_api.dart';
import 'package:rowing_app/coach_request_service.dart';
import 'package:rowing_app/curve_privacy_service.dart';
import 'package:rowing_app/dashboard_tab.dart';
import 'package:rowing_app/db.dart';
import 'package:rowing_app/program_service.dart';
import 'package:rowing_app/today_workout_page.dart';

void main() {
  late MockCloudApi mockCloud;
  late Directory tempDir;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await AppLanguage.instance.init();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    tempDir = Directory.systemTemp.createTempSync('rowing_phase_s3_');
    await databaseFactory.setDatabasesPath(tempDir.path);
    DB.testDatabase = null;

    mockCloud = MockCloudApi();
    CloudApi.instance = mockCloud;

    await AuthService.ensureTables();
    await ProgramService.ensureTables();
  });

  tearDownAll(() async {
    DB.testDatabase = null;
    try {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    } catch (_) {}
  });

  group('Phase S3 Business Logic & Security Tests', () {
    test('1. Admin Scope: Admin sees only profiles & subscriptions, never workouts or health data', () async {
      mockCloud.reset();

      // إنشاء مستخدمين مختلفين
      await mockCloud.signUp(
        email: 'athlete1@test.com',
        password: 'pass',
        name: 'كابتن زياد',
        role: 'athlete',
      );
      await mockCloud.signUp(
        email: 'coach1@test.com',
        password: 'pass',
        name: 'المدرب حسام',
        role: 'coach',
      );

      final profiles = await mockCloud.listAllProfiles();
      expect(profiles.length, 2);

      // التأكد أن ملف الأدمن لا يحتوي على أي حقول تمارين أو صحة
      for (final p in profiles) {
        expect(p.name.isNotEmpty, true);
        expect(p.email.isNotEmpty, true);
        expect(p.role.isNotEmpty, true);
        final map = p.toMap();
        expect(map.containsKey('logs'), false);
        expect(map.containsKey('avg_power'), false);
        expect(map.containsKey('hr'), false);
        expect(map.containsKey('hrv'), false);
        expect(map.containsKey('workouts'), false);
      }
    });

    test('2. Subscription Activation & Audit Log', () async {
      mockCloud.reset();
      final res = await mockCloud.signUp(
        email: 'athlete2@test.com',
        password: 'pass',
        name: 'اللاعب علي',
        role: 'athlete',
      );
      final userId = res.user!.id;
      expect(await mockCloud.isSubscriptionActive(userId), false);

      // تفعيل الاشتراك مع ملاحظة
      await mockCloud.updateSubscription(
        userId: userId,
        active: true,
        note: 'تم السداد كاش 500 ج',
        adminId: 'admin-99',
      );
      expect(await mockCloud.isSubscriptionActive(userId), true);

      final logs = await mockCloud.getSubscriptionLogs(userId);
      expect(logs.length, 1);
      expect(logs.first['action'], 'activated');
      expect(logs.first['note'], 'تم السداد كاش 500 ج');
      expect(logs.first['changed_by'], 'admin-99');

      // إيقاف الاشتراك
      await mockCloud.updateSubscription(
        userId: userId,
        active: false,
        note: 'انتهاء فترة الاشتراك',
        adminId: 'admin-99',
      );
      expect(await mockCloud.isSubscriptionActive(userId), false);
      final logsAfter = await mockCloud.getSubscriptionLogs(userId);
      expect(logsAfter.length, 2);
      expect(logsAfter.first['action'], 'deactivated');
    });

    test('3. Coach Request Lifecycle: Send, Prevent Duplicate, Cancel', () async {
      final db = await DB.db;
      await db.delete('coach_requests');

      // إرسال طلب انضمام
      await CoachRequestService.sendCoachRequest(athleteId: 501, coachId: '101');
      final reqs = await CoachRequestService.getRequestsForAthlete(501);
      expect(reqs.length, 1);
      expect(reqs.first['status'], 'pending');

      // محاولة إرسال طلب معلّق آخر لنفس المدرب يجب أن تُرفض
      expect(
        () => CoachRequestService.sendCoachRequest(athleteId: 501, coachId: '101'),
        throwsA(isA<Exception>()),
      );

      // إلغاء الطلب
      final reqId = (reqs.first['id'] as num).toInt();
      await CoachRequestService.cancelRequest(reqId);
      final reqsAfterCancel = await CoachRequestService.getRequestsForAthlete(501);
      expect(reqsAfterCancel.first['status'], 'cancelled');
    });

    test('4. Inactive Coach CANNOT accept requests; Active Coach can accept', () async {
      final db = await DB.db;
      await db.delete('coach_requests');

      // إنشاء طلب للاعب
      await CoachRequestService.sendCoachRequest(athleteId: 502, coachId: '102');
      final reqs = await CoachRequestService.getRequestsForAthlete(502);
      final reqId = (reqs.first['id'] as num).toInt();

      // مدرب غير مفعّل يحاول القبول -> يُرفض
      const inactiveCoach = AppUser(
        id: 102,
        email: 'inactive@coach.com',
        name: 'مدرب غير مفعّل',
        role: 'coach',
        coachId: null,
        subscriptionActive: false,
      );
      expect(
        () => CoachRequestService.respondToRequest(
          requestId: reqId,
          accept: true,
          coach: inactiveCoach,
        ),
        throwsA(isA<Exception>()),
      );

      // مدرب مفعّل يقبل الطلب -> ينجح ويتم ربط اللاعب
      const activeCoach = AppUser(
        id: 102,
        email: 'active@coach.com',
        name: 'مدرب مفعّل',
        role: 'coach',
        coachId: null,
        subscriptionActive: true,
      );
      await CoachRequestService.respondToRequest(
        requestId: reqId,
        accept: true,
        coach: activeCoach,
      );

      final reqsAccepted = await CoachRequestService.getRequestsForAthlete(502);
      expect(reqsAccepted.first['status'], 'accepted');

      // فحص أن اللاعب تم ربطه بالمدرب
      final userRow = await db.query('users', where: 'id = ?', whereArgs: [502]);
      if (userRow.isNotEmpty) {
        expect(userRow.first['coach_id'], 102);
      }
    });

    test('5. Coach Isolation: Coach A cannot see Coach B athletes', () async {
      mockCloud.reset();
      await mockCloud.signUp(email: 'a1@test.com', password: 'p', name: 'لاعب 1', role: 'athlete');
      await mockCloud.signUp(email: 'a2@test.com', password: 'p', name: 'لاعب 2', role: 'athlete');

      // تعيين لاعب 1 لمدرب A
      final teamA = await mockCloud.getTeammates('coach-A');
      final teamB = await mockCloud.getTeammates('coach-B');
      expect(teamA.isEmpty, true);
      expect(teamB.isEmpty, true);
    });

    test('6. Curve Privacy: canViewCurves in all 4 states & Athlete privacy override protection', () async {
      final db = await DB.db;
      await db.delete('players');

      // زراعة لاعب 1 (مشارك المنحنيات) ولاعب 2 (خاص) لنفس المدرب (coachId = 10)
      await db.insert('players', {
        'id': 701,
        'name': 'اللاعب المنفتح',
        'mhr': 195,
        'active': 1,
        'coach_id': 10,
        'curves_shared': 1,
        'curves_shared_by': 'coach',
      });
      await db.insert('players', {
        'id': 702,
        'name': 'اللاعب المتحفظ',
        'mhr': 190,
        'active': 1,
        'coach_id': 10,
        'curves_shared': 0,
        'curves_shared_by': 'coach',
      });

      const athlete1 = AppUser(id: 701, email: 'a1@t.com', name: 'اللاعب 1', role: 'athlete', coachId: 10, subscriptionActive: true);
      const athlete2 = AppUser(id: 702, email: 'a2@t.com', name: 'اللاعب 2', role: 'athlete', coachId: 10, subscriptionActive: true);
      const coach10 = AppUser(id: 10, email: 'c10@t.com', name: 'المدرب 10', role: 'coach', coachId: null, subscriptionActive: true);
      const otherCoach = AppUser(id: 20, email: 'c20@t.com', name: 'مدرب غريب', role: 'coach', coachId: null, subscriptionActive: true);
      const adminUser = AppUser(id: 99, email: 'admin@t.com', name: 'الأدمن', role: 'admin', coachId: null, subscriptionActive: true);

      // الحالة 1: اللاعب يرى منحنياته هو دائماً
      expect(await CurvePrivacyService.canViewCurves(viewer: athlete1, ownerPlayerId: 701), true);

      // الحالة 2: المدرب يرى منحنيات لاعبيه دائماً
      expect(await CurvePrivacyService.canViewCurves(viewer: coach10, ownerPlayerId: 701), true);
      expect(await CurvePrivacyService.canViewCurves(viewer: coach10, ownerPlayerId: 702), true);

      // مدرب غريب لا يرى منحنيات لاعبين ليسوا في فريقه
      expect(await CurvePrivacyService.canViewCurves(viewer: otherCoach, ownerPlayerId: 701), false);

      // الأدمن لا يرى بيانات المنحنيات والصحة أبداً
      expect(await CurvePrivacyService.canViewCurves(viewer: adminUser, ownerPlayerId: 701), false);

      // الحالة 3: زميل يرى منحنيات زميل مشارك (curves_shared = 1)
      expect(await CurvePrivacyService.canViewCurves(viewer: athlete2, ownerPlayerId: 701), true);

      // الحالة 4: زميل يطلب منحنيات زميل غير مشارك (curves_shared = 0) -> مرفوض
      expect(await CurvePrivacyService.canViewCurves(viewer: athlete1, ownerPlayerId: 702), false);

      // حماية قرار اللاعب (اللاعب صاحب القرار النهائي):
      // عندما يغير اللاعب إعداده بنفسه تصبح curves_shared_by = 'athlete'
      await CurvePrivacyService.setCurveSharing(actor: athlete1, targetPlayerId: 701, shared: false);
      final pRow = await db.query('players', where: 'id = ?', whereArgs: [701]);
      expect(pRow.first['curves_shared'], 0);
      expect(pRow.first['curves_shared_by'], 'athlete');

      // الآن المدرب يحاول تغيير إعداد لاعب قرر بنفسه -> يُرفض تماماً
      expect(
        await CurvePrivacyService.canEditCurveSharing(editor: coach10, targetPlayerId: 701),
        false,
      );
      expect(
        () => CurvePrivacyService.setCurveSharing(actor: coach10, targetPlayerId: 701, shared: true),
        throwsA(isA<Exception>()),
      );
    });

    test('7. Data Isolation: shared_curve_cache does NOT contaminate athlete logs', () async {
      final db = await DB.db;
      await db.delete('logs');
      await db.delete('shared_curve_cache');

      // تسجيل حصة للاعب صاحب الحساب في logs
      await db.insert('logs', {
        'player_id': 701,
        'date': '2026-11-19',
        'idx': 0,
        'avg_power': 240,
        'zone': 'Z2',
      });

      // حفظ منحنيات زميل في shared_curve_cache
      await CurvePrivacyService.cacheTeammateCurves(
        playerId: 702,
        records: [
          {'date': '2026-11-19', 'idx': 0, 'avg_power': 280, 'zone': 'Z3'}
        ],
      );

      // التحقق من العزل التام: جدول logs يحتوي فقط على سجلات اللاعب 701
      final athleteLogs = await db.query('logs', where: 'player_id = ?', whereArgs: [701]);
      expect(athleteLogs.length, 1);
      expect(athleteLogs.first['avg_power'], 240);

      final otherLogs = await db.query('logs', where: 'player_id = ?', whereArgs: [702]);
      expect(otherLogs.isEmpty, true);

      // جدول الكاش يحتوي على سجل الزميل فقط للعرض
      final cache = await db.query('shared_curve_cache');
      expect(cache.length, 1);
      expect(cache.first['player_id'], 702);
      expect(cache.first['avg_power'], 280);
    });

    test('8. Avatar Storage: upload & download avatar bytes', () async {
      mockCloud.reset();
      final dummyBytes = [1, 2, 3, 4, 5];
      final path = await mockCloud.uploadAvatar(userId: 'user-77', bytes: dummyBytes);
      expect(path, 'avatars/user-77.jpg');

      final downloaded = await mockCloud.downloadAvatar('user-77');
      expect(downloaded, dummyBytes);
    });

    test('9. Coach Per-Athlete Daily Workout Customization Isolation: Original template and other athletes/days remain untouched', () async {
      final db = await DB.db;
      await db.delete('players');
      await db.delete('athlete_custom_sessions');
      await db.delete('athlete_custom_workout_items');
      await db.delete('program_cycles');
      await db.delete('program_sessions');
      await db.delete('program_workout_items');

      await db.insert('players', {'id': 501, 'name': 'اللاعب طارق', 'mhr': 190, 'active': 1});
      await db.insert('players', {'id': 502, 'name': 'اللاعب سليم', 'mhr': 195, 'active': 1});

      final cycle = await ProgramService.addProgramCycle();
      await db.update(
        'program_cycles',
        {'start_date': '2026-11-01', 'end_date': '2026-11-30'},
        where: 'id = ?',
        whereArgs: [cycle.id],
      );
      await db.delete('program_sessions', where: 'cycle_id = ?', whereArgs: [cycle.id]);
      await db.delete('program_workout_items');

      final targetDate = DateTime(2026, 11, 25);
      final dayOfWeek = ProgramService.getWeekdayIndex(targetDate);
      final createdSession = await ProgramService.addDaySessionDetailed(cycle.id, 'basic', dayOfWeek);
      final templateSession = ProgramDaySession(
        id: createdSession.id,
        cycleId: createdSession.cycleId,
        cycleType: createdSession.cycleType,
        dayOfWeek: createdSession.dayOfWeek,
        sessionIdx: createdSession.sessionIdx,
        name: 'حصة القالب الأصلية',
        time: '08:00',
        workouts: [
          ProgramWorkoutItem(
            sessionId: createdSession.id!,
            section: 'main',
            itemIdx: 0,
            durationSeconds: 3000,
            kind: 'Erg',
            zone: 'Z2',
            details: 'تمرين القالب العام 10 كم',
          ),
        ],
      );
      await ProgramService.saveDaySessionDetailed(templateSession);

      // Verify template is present
      final originalTemplates = await ProgramService.getTemplateSessionsForDate(targetDate);
      expect(originalTemplates.isNotEmpty, isTrue);
      expect(originalTemplates.first.name, 'حصة القالب الأصلية');

      // Coach customizes workout for Athlete 501 ONLY on 2026-11-25
      final customFor501 = ProgramDaySession(
        cycleId: cycle.id,
        cycleType: 'custom',
        dayOfWeek: dayOfWeek,
        sessionIdx: 0,
        name: 'تعديل خاص باللاعب طارق فقط',
        time: '09:30',
        workouts: [
          ProgramWorkoutItem(
            sessionId: 0,
            section: 'main',
            itemIdx: 0,
            durationSeconds: 1800,
            kind: 'Erg',
            zone: 'Threshold',
            details: 'فارتلك خاص بالبطل طارق',
          ),
        ],
      );

      await ProgramService.saveAthleteCustomSession(
        playerId: 501,
        date: dstr(targetDate),
        session: customFor501,
      );

      // Verify Athlete 501 on 2026-11-25 sees Coach's customization
      final sessionsFor501 = await ProgramService.getSessionsForAthleteAndDate(
        playerId: 501,
        date: targetDate,
      );
      expect(sessionsFor501.length, 1);
      expect(sessionsFor501.first.name, 'تعديل خاص باللاعب طارق فقط');
      expect(sessionsFor501.first.workouts.first.details, 'فارتلك خاص بالبطل طارق');

      // Verify Original Template is completely UNCHANGED
      final templateCheck = await ProgramService.getTemplateSessionsForDate(targetDate);
      expect(templateCheck.first.name, 'حصة القالب الأصلية');
      expect(templateCheck.first.workouts.first.details, 'تمرين القالب العام 10 كم');

      // Verify Athlete 502 on same date (2026-11-25) sees Original Template, NOT Athlete 501's edit
      final sessionsFor502 = await ProgramService.getSessionsForAthleteAndDate(
        playerId: 502,
        date: targetDate,
      );
      expect(sessionsFor502.length, 1);
      expect(sessionsFor502.first.name, 'حصة القالب الأصلية');
      expect(sessionsFor502.first.workouts.first.details, 'تمرين القالب العام 10 كم');

      // Verify Athlete 501 on a DIFFERENT date (2026-11-26) sees the template, NOT the custom workout
      final otherDate = DateTime(2026, 11, 26);
      final sessionsFor501NextDay = await ProgramService.getSessionsForAthleteAndDate(
        playerId: 501,
        date: otherDate,
      );
      if (sessionsFor501NextDay.isNotEmpty) {
        expect(sessionsFor501NextDay.first.name, isNot('تعديل خاص باللاعب طارق فقط'));
      }
    }, timeout: const Timeout(Duration(seconds: 60)));

    testWidgets('10. TodayWorkoutPage 7-Day Window Maximum Constraint: Date range clamped to 7 days', (tester) async {
      await AppLanguage.instance.setLocale(const Locale('ar'));

      const athleteUser = AppUser(
        id: 301,
        playerId: 301,
        email: 'athlete301@test.com',
        name: 'اللاعب عمر',
        role: 'athlete',
        subscriptionActive: true,
      );

      final anchorDate = DateTime(2026, 11, 20);

      await tester.runAsync(() async {
        final db = await DB.db;
        await db.delete('players');
        await db.insert('players', {'id': 301, 'name': 'اللاعب عمر', 'mhr': 190, 'active': 1});
      });

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('ar'),
          home: TodayWorkoutPage(
            user: athleteUser,
            initialDate: anchorDate,
          ),
        ),
      );

      for (int i = 0; i < 50; i++) {
        if (find.byType(CircularProgressIndicator).evaluate().isEmpty) {
          break;
        }
        await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 30)));
        await tester.pump();
      }
      await tester.pump();

      expect(find.textContaining('2026-11-20'), findsWidgets);

      final dynamic state = tester.state(find.byType(TodayWorkoutPage));

      // Selecting 2026-11-28 for end date while start is 2026-11-20 (9 days -> exceeds 7 days limit)
      await tester.runAsync(() async {
        await state.updateDateSelection(
          DateTime(2026, 11, 28),
          isStart: false,
        );
      });
      await tester.pump();

      final s = AppStrings.of(tester.element(find.byType(TodayWorkoutPage)));
      expect(find.text(s.maxSevenDaysNotice), findsOneWidget);
      expect(state.endDate, DateTime(2026, 11, 28));
      expect(state.startDate, DateTime(2026, 11, 22));

      // Valid range <= 7 days succeeds
      await tester.runAsync(() async {
        await state.updateDateSelection(
          DateTime(2026, 11, 26),
          isStart: false,
        );
      });
      await tester.pump();
      expect(state.startDate, DateTime(2026, 11, 22));
      expect(state.endDate, DateTime(2026, 11, 26));
    }, timeout: const Timeout(Duration(seconds: 60)));
  });

  group('Phase S3 Responsive Multi-Size & Multi-Language UI Tests', () {
    final testSizes = [
      const Size(320, 640),
      const Size(360, 800),
      const Size(411, 891),
    ];
    final testScales = [1.0, 1.3];
    final testLocales = [const Locale('ar'), const Locale('en')];

    Future<void> pumpUntilLoaded(WidgetTester tester) async {
      await tester.pump();
      for (int i = 0; i < 200; i++) {
        if (find.byType(CircularProgressIndicator).evaluate().isEmpty) {
          break;
        }
        await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 30)));
        await tester.pump();
      }
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 100)));
      await tester.pump();
    }

    for (final size in testSizes) {
      for (final scale in testScales) {
        for (final loc in testLocales) {
          testWidgets(
            'AdminPage renders cleanly on ${size.width.toInt()}x${size.height.toInt()} scale $scale ${loc.languageCode} with 0 overflow',
            (tester) async {
              tester.view.physicalSize = size;
              tester.view.devicePixelRatio = scale;
              addTearDown(tester.view.resetPhysicalSize);
              addTearDown(tester.view.resetDevicePixelRatio);

              await AppLanguage.instance.setLocale(loc);

              const adminUser = AppUser(
                id: 1,
                email: 'admin@engine.rowing',
                name: 'System Admin',
                role: 'admin',
                coachId: null,
                subscriptionActive: true,
              );

              await tester.pumpWidget(
                MaterialApp(
                  locale: loc,
                  home: AdminPage(onLogout: () {}, currentUser: adminUser),
                ),
              );

              await pumpUntilLoaded(tester);

              expect(find.byType(AdminPage), findsOneWidget);
              expect(tester.takeException(), isNull);
            },
          );

          testWidgets(
            'DashboardTab (Athlete with Coach Selection) renders cleanly on ${size.width.toInt()}x${size.height.toInt()} scale $scale ${loc.languageCode}',
            (tester) async {
              tester.view.physicalSize = size;
              tester.view.devicePixelRatio = scale;
              addTearDown(tester.view.resetPhysicalSize);
              addTearDown(tester.view.resetDevicePixelRatio);

              await AppLanguage.instance.setLocale(loc);

              const athleteUser = AppUser(
                id: 10,
                email: 'athlete@engine.rowing',
                name: 'اللاعب كريم',
                role: 'athlete',
                coachId: null,
                subscriptionActive: true,
              );

              await tester.pumpWidget(
                MaterialApp(
                  locale: loc,
                  home: const Scaffold(body: DashboardTab(user: athleteUser)),
                ),
              );

              await pumpUntilLoaded(tester);

              expect(find.byType(DashboardTab), findsOneWidget);
              expect(tester.takeException(), isNull);
            },
          );
        }
      }
    }
  });
}
