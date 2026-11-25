import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:rowing_app/auth_service.dart';
import 'package:rowing_app/db.dart';
import 'package:rowing_app/engine_rowing_ui.dart';
import 'package:rowing_app/main.dart';
import 'package:rowing_app/dashboard_tab.dart';
import 'package:rowing_app/program_tab.dart';
import 'package:rowing_app/sync_engine.dart';
import 'package:rowing_app/workouts_tab.dart';
import 'package:rowing_app/session_workouts_page.dart';
import 'package:rowing_app/program_service.dart';

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final tempDir = Directory.systemTemp.createTempSync('rowing_layout_test_');
    await databaseFactory.setDatabasesPath(tempDir.path);
    DB.testDatabase = null;
    await AuthService.ensureTables();
    await ProgramService.ensureTables();
  });

  tearDown(() {
    SyncEngine.instance.cancelDebounce();
  });

  const testUser = AppUser(
    id: 1,
    email: 'coach@test.local',
    name: 'Coach Mahmoud',
    role: 'coach',
    coachId: null,
    subscriptionActive: true,
  );

  Future<void> settleAsync(WidgetTester tester, {int maxAttempts = 60}) async {
    for (int i = 0; i < maxAttempts; i++) {
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
      final hasLoading = find.byType(CircularProgressIndicator, skipOffstage: false).evaluate().isNotEmpty;
      if (i >= 5 && !hasLoading) {
        break;
      }
    }
  }

  testWidgets('MainNavigationScaffold builds cleanly on mobile viewport and toggles sideNav overlay', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: MainNavigationScaffold(
          user: testUser,
          onLogout: () {},
        ),
      ),
    );

    await tester.pump();
    await settleAsync(tester);

    // Verify hamburger button exists and tap it to open sideNav overlay
    final menuButton = find.byIcon(Icons.menu_rounded);
    expect(menuButton, findsOneWidget);
    await tester.tap(menuButton);
    await tester.pump(const Duration(milliseconds: 300));

    // Tap menu button again to close sideNav
    await tester.tap(menuButton, warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 300));
    await settleAsync(tester);
  });

  testWidgets('DashboardTab builds cleanly', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: DashboardTab(user: testUser),
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 100)));
    await tester.pump(const Duration(milliseconds: 300));
  });

  testWidgets('ProgramTab builds cleanly', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ProgramTab(),
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 100)));
    await tester.pump(const Duration(milliseconds: 300));
  });

  testWidgets('WorkoutsTab builds cleanly', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: WorkoutsTab(user: testUser),
        ),
      ),
    );
    await tester.pump();
    await settleAsync(tester);
  });

  testWidgets('SessionWorkoutsPage builds without overflow on mobile screen', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final mockSession = ProgramDaySession(
      id: 1,
      cycleId: 1,
      cycleType: 'basic',
      dayOfWeek: 0,
      sessionIdx: 0,
      name: 'الحصة الصباحية',
      time: '07:00',
      workouts: [
        ProgramWorkoutItem(
          sessionId: 1,
          section: 'warmup',
          itemIdx: 0,
          time: '07:00',
          durationMinutes: 12,
          distanceMeters: 2500,
          reps: 1,
          kind: 'Stretch',
          zone: 'zone1 = 55%:65%',
          hrPercent: 60,
          hrRange: '55%:65%',
          details: 'إطالات ديناميكية وإحماء مفاصل',
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SessionWorkoutsPage(
          session: mockSession,
          onSaved: () {},
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  });

  testWidgets('RowingTrendIndicator and dynamic RowingMetricCard behavior', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              // Up trend (250 W vs previous 220 W)
              RowingMetricCard(
                title: 'POWER',
                unit: 'W',
                value: '250',
                previousValue: 220,
              ),
              // Down trend (28 spm vs previous 32 spm)
              RowingMetricCard(
                title: 'STROKE RATE',
                unit: 'spm',
                value: '28',
                previousValue: 32,
              ),
              // Neutral (same 200 W)
              RowingMetricCard(
                title: 'POWER',
                unit: 'W',
                value: '200',
                previousValue: 200,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    // Verify RowingTrendIndicator widgets are rendered
    expect(find.byType(RowingTrendIndicator), findsNWidgets(3));
  });
}
