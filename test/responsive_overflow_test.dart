import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:rowing_app/auth_service.dart';
import 'package:rowing_app/app_strings.dart';
import 'package:rowing_app/db.dart';
import 'package:rowing_app/program_service.dart';
import 'package:rowing_app/dashboard_tab.dart';
import 'package:rowing_app/program_tab.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await AppLanguage.instance.init();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    final tempDir = Directory.systemTemp.createTempSync('rowing_multi_size_');
    await databaseFactory.setDatabasesPath(tempDir.path);

    // بذرة بيانات أساسية لإظهار الحصة القادمة ومواعيد الاختبارات والدورات
    await AuthService.ensureTables();
    await ProgramService.ensureTables();
    await ProgramService.addProgramCycle();

    final today = dstr(DateTime.now());
    await DB.put('sessions', {
      'date': today,
      'idx': 0,
      'kind': 'Erg',
      'zone': 'Z2',
    });

    final database = await DB.db;
    final testDateStr = dstr(DateTime.now().add(const Duration(days: 3)));
    await database.insert('testing_dates', {
      'coach_id': 1,
      'test_name': '2000m Erg Test',
      'test_date': testDateStr,
      'created_at': today,
    });
  });

  const testUser = AppUser(
    id: 1,
    email: 'coach@engine.rowing',
    name: 'Coach Mahmoud',
    role: 'coach',
    coachId: null,
    subscriptionActive: true,
  );

  final testSizes = [
    const Size(320, 640),
    const Size(411, 891),
  ];

  final locales = [
    const Locale('ar'),
    const Locale('en'),
  ];

  Future<void> pumpUntilLoaded(WidgetTester tester) async {
    await tester.pump();
    for (int i = 0; i < 50; i++) {
      if (find.byType(CircularProgressIndicator).evaluate().isEmpty) {
        break;
      }
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 100)));
      await tester.pump();
    }
  }

  group('DashboardTab Multi-Size & Language Overflow Tests', () {
    for (final size in testSizes) {
      for (final loc in locales) {
        testWidgets(
          'DashboardTab renders cards cleanly on ${size.width.toInt()}x${size.height.toInt()} ${loc.languageCode}',
          (tester) async {
            tester.view.physicalSize = size;
            tester.view.devicePixelRatio = 1.0;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);

            await AppLanguage.instance.setLocale(loc);

            await tester.pumpWidget(
              MaterialApp(
                locale: loc,
                home: Scaffold(body: DashboardTab(user: testUser)),
              ),
            );

            // استنى لحد ما الكروت تظهر فعلًا وتختفي دايرة التحميل
            await pumpUntilLoaded(tester);

            expect(find.byType(CircularProgressIndicator), findsNothing);
            expect(find.byType(ListView), findsWidgets);

            // فحص وجود كروت مؤشرات التدريب وزرار فتح التحليل
            expect(
              find.text(loc.languageCode == 'ar' ? '5 منحنيات' : '5 Curves'),
              findsOneWidget,
            );
            expect(
              find.text(loc.languageCode == 'ar'
                  ? 'فتح التحليل والمنحنيات'
                  : 'Open Analytics & Curves'),
              findsOneWidget,
            );

            // فحص عدم حدوث أي خطأ overflow
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  });

  group('ProgramTab (Cycles) Multi-Size & Language Overflow Tests', () {
    for (final size in testSizes) {
      for (final loc in locales) {
        testWidgets(
          'ProgramTab (Cycles) renders cleanly on ${size.width.toInt()}x${size.height.toInt()} ${loc.languageCode}',
          (tester) async {
            tester.view.physicalSize = size;
            tester.view.devicePixelRatio = 1.0;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);

            await AppLanguage.instance.setLocale(loc);

            await tester.pumpWidget(
              MaterialApp(
                locale: loc,
                home: const Scaffold(body: ProgramTab()),
              ),
            );

            // استنى لحد ما الكروت تظهر فعلًا وتختفي دايرة التحميل
            await pumpUntilLoaded(tester);

            expect(find.byType(CircularProgressIndicator), findsNothing);
            expect(find.byType(ListView), findsWidgets);

            // فحص زرار إضافة دورة جديدة وعنوان الدورات
            expect(
              find.text(loc.languageCode == 'ar' ? '+ دورة جديدة' : '+ New Cycle'),
              findsOneWidget,
            );

            // فحص عدم حدوث أي خطأ overflow
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  });
}
