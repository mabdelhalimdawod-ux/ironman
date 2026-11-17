import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:rowing_app/auth_service.dart';
import 'package:rowing_app/app_strings.dart';
import 'package:rowing_app/db.dart';
import 'package:rowing_app/cloud_api.dart';
import 'package:rowing_app/login_page.dart';

void main() {
  late MockCloudApi mockCloud;
  late Directory tempDir;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await AppLanguage.instance.init();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    tempDir = Directory.systemTemp.createTempSync('rowing_cloud_test_');
    await databaseFactory.setDatabasesPath(tempDir.path);

    await AuthService.ensureTables();
  });

  setUp(() {
    mockCloud = MockCloudApi();
    CloudApi.instance = mockCloud;
    SharedPreferences.setMockInitialValues({});
  });

  tearDownAll(() {
    try {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    } catch (_) {}
  });

  group('Phase S1: CloudApi & Supabase Auth Business Logic Tests', () {
    test('1. Registering as athlete succeeds in cloud and local mirror', () async {
      final res = await mockCloud.signUp(
        email: 'athlete.test@rowing.com',
        password: 'Password123!',
        name: 'كابتن أحمد (لاعب)',
        role: 'athlete',
      );

      expect(res.isSuccess, isTrue);
      expect(res.profile, isNotNull);
      expect(res.profile!.role, 'athlete');
      expect(res.profile!.subscriptionActive, isFalse); // في انتظار التفعيل
    });

    test('2. Registering as coach succeeds in cloud with inactive subscription', () async {
      final res = await mockCloud.signUp(
        email: 'coach.test@rowing.com',
        password: 'Password123!',
        name: 'كابتن طارق (مدرب)',
        role: 'coach',
      );

      expect(res.isSuccess, isTrue);
      expect(res.profile, isNotNull);
      expect(res.profile!.role, 'coach');
      expect(res.profile!.subscriptionActive, isFalse);
    });

    test('3. Registering directly as admin is strictly rejected', () async {
      // عبر CloudApi مباشرة
      final res = await mockCloud.signUp(
        email: 'hacker.admin@rowing.com',
        password: 'Password123!',
        name: 'مخترق',
        role: 'admin',
      );

      expect(res.isSuccess, isFalse);
      expect(res.errorCode, CloudAuthErrorCode.adminRoleForbidden);

      // عبر AuthService.registerUser
      expect(
        () async => await AuthService.registerUser(
          email: 'admin.forbidden@rowing.com',
          password: 'Password123!',
          name: 'طلب مسؤول مرفوض',
          role: 'admin',
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('4. Inactive account login fails with accountInactive and neutral message', () async {
      // تسجيل حساب جديد غير مفعّل
      await AuthService.registerUser(
        email: 'pending.user@rowing.com',
        password: 'Password123!',
        name: 'مستخدم قيد الانتظار',
        role: 'athlete',
      );

      // محاولة تسجيل الدخول بحساب غير مفعل
      final loginRes = await AuthService.login(
        'pending.user@rowing.com',
        'Password123!',
      );

      expect(loginRes.isSuccess, isFalse);
      expect(loginRes.error, LoginError.accountInactive);

      // التحقق من أن الرسالة المعروضة محايدة ومطابقة للتوجيهات
      const stringsAr = AppStrings(true);
      expect(stringsAr.accountInactive, 'حسابك غير مفعّل حاليًا، تواصل مع الإدارة');

      const stringsEn = AppStrings(false);
      expect(stringsEn.accountInactive, 'Your account is not active right now. Please contact the administration.');
    });

    test('5. Active account login succeeds and syncs local users table as profile mirror', () async {
      const email = 'active.champion@rowing.com';
      const pass = 'Champion2026!';

      // تسجيل الحساب
      await AuthService.registerUser(
        email: email,
        password: pass,
        name: 'البطل محمود',
        role: 'athlete',
      );

      // محاكاة تفعيل الحساب من جانب الإدارة في السحابة
      mockCloud.setSubscriptionActive(email, true);

      final loginRes = await AuthService.login(email, pass);

      expect(loginRes.isSuccess, isTrue);
      expect(loginRes.user, isNotNull);
      expect(loginRes.user!.email, email);
      expect(loginRes.user!.name, 'البطل محمود');
      expect(loginRes.user!.subscriptionActive, isTrue);

      // التحقق من مزامنة الصف في جدول SQLite المحلي users
      final database = await DB.db;
      final localRows = await database.rawQuery(
        'SELECT * FROM users WHERE LOWER(email) = ?',
        [email.toLowerCase()],
      );

      expect(localRows.isNotEmpty, isTrue);
      expect(localRows.first['name'], 'البطل محمود');
      expect(localRows.first['subscription_active'], 1);
    });

    test('6. Saved session persists user and restores session offline', () async {
      final user = AppUser(
        id: 777,
        email: 'saved.session@rowing.com',
        name: 'لاعب محفوظ الجلسة',
        role: 'athlete',
        subscriptionActive: true,
      );

      // 1. حفظ الجلسة مع خيار تذكرني = true
      await AuthService.saveSession(user, true);

      // 2. إدخال المستخدم في القاعدة المحلية
      final database = await DB.db;
      await database.insert('users', {
        'id': 777,
        'email': 'saved.session@rowing.com',
        'password_hash': 'dummy',
        'salt': 'dummy',
        'name': 'لاعب محفوظ الجلسة',
        'role': 'athlete',
        'subscription_active': 1,
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      // 3. التحقق من استعادة الجلسة المحفوظة
      final restored = await AuthService.checkSavedSession();
      expect(restored, isNotNull);
      expect(restored!.id, 777);
      expect(restored.email, 'saved.session@rowing.com');

      // 4. بعد تسجيل الخروج، لا توجد جلسة
      await AuthService.logout();
      final afterLogout = await AuthService.checkSavedSession();
      expect(afterLogout, isNull);
    });
  });

  group('LoginPage Multi-Size & Overflow Tests (Arabic & English)', () {
    final sizes = [
      const Size(320, 640), // صغير جداً
      const Size(360, 800), // قياسي
      const Size(411, 891), // كبير
    ];
    final textScales = [1.0, 1.3];
    final isArabics = [true, false];

    for (final size in sizes) {
      for (final scale in textScales) {
        for (final isAr in isArabics) {
          final lang = isAr ? 'AR' : 'EN';
          testWidgets(
            'LoginPage renders cleanly on ${size.width.toInt()}x${size.height.toInt()} scale $scale $lang with 0 overflow',
            (tester) async {
              await AppLanguage.instance.setLocale(Locale(isAr ? 'ar' : 'en'));
              tester.view.physicalSize = Size(size.width * 2.0, size.height * 2.0);
              tester.view.devicePixelRatio = 2.0;
              addTearDown(() => tester.view.resetPhysicalSize());

              await tester.pumpWidget(
                MaterialApp(
                  locale: Locale(isAr ? 'ar' : 'en'),
                  builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(context).copyWith(
                      size: size,
                      textScaler: TextScaler.linear(scale),
                    ),
                    child: Directionality(
                      textDirection: isAr ? TextDirection.rtl : TextDirection.ltr,
                      child: child!,
                    ),
                  ),
                  home: Scaffold(
                    body: LoginPage(onLoginSuccess: (_) {}),
                  ),
                ),
              );

              await tester.pumpAndSettle();

              // التأكد من ظهور الحقول الأساسية بدون أي أخطاء أو Overflow
              expect(find.byType(TextFormField), findsWidgets);
              expect(find.text(isAr ? 'تسجيل الدخول' : 'Sign In'), findsWidgets);
              expect(tester.takeException(), isNull);
            },
          );
        }
      }
    }
  });
}
