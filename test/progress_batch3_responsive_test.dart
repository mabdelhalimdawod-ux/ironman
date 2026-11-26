import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:rowing_app/app_strings.dart';
import 'package:rowing_app/auth_service.dart';
import 'package:rowing_app/db.dart';
import 'package:rowing_app/decoupling_curve.dart';
import 'package:rowing_app/decoupling_trend_curve.dart';
import 'package:rowing_app/dynamic_watts_curve.dart';
import 'package:rowing_app/ef_zone_curve.dart';
import 'package:rowing_app/program_service.dart';

void main() {
  Directory? tempDir;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await AppLanguage.instance.init();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    tempDir = Directory.systemTemp.createTempSync('rowing_batch3_test_');
    await databaseFactory.setDatabasesPath(tempDir!.path);
    DB.testDatabase = null;

    await AuthService.ensureTables();
    await ProgramService.ensureTables();
    await ProgramService.addProgramCycle();

    final database = await DB.db;

    // Seed test player
    await database.insert('players', {
      'id': 1,
      'name': 'أحمد البطل',
      'mhr': 195,
      'active': 1,
    });

    // Seed test logs
    await database.insert('logs', {
      'player_id': 1,
      'date': '2026-11-05',
      'idx': 0,
      'avg_power': 210.0,
      'hr': 148,
      'ef': 1.42,
      'decoupling': 4.5,
      'zone': 'Z2',
      'kind': 'Erg',
      'duration_seconds': 3600,
    });
    await database.insert('logs', {
      'player_id': 1,
      'date': '2026-11-12',
      'idx': 0,
      'avg_power': 225.0,
      'hr': 155,
      'ef': 1.45,
      'decoupling': 3.8,
      'zone': 'Z2',
      'kind': 'Erg',
      'duration_seconds': 4200,
    });
  });

  tearDownAll(() async {
    DB.testDatabase = null;
    try {
      if (tempDir != null && tempDir!.existsSync()) {
        tempDir!.deleteSync(recursive: true);
      }
    } catch (_) {}
  });

  final testSizes = [
    const Size(320, 640),
    const Size(360, 800),
    const Size(411, 891),
  ];

  final textScales = [1.0, 1.3];

  for (final size in testSizes) {
    for (final scale in textScales) {
      testWidgets(
          'EfZoneCurveWidget renders without overflow at ${size.width.toInt()}x${size.height.toInt()} (scale: $scale)',
          (tester) async {
        tester.view.physicalSize = Size(size.width * 2.0, size.height * 2.0);
        tester.view.devicePixelRatio = 2.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        for (final lang in ['ar', 'en']) {
          await AppLanguage.instance.setLocale(Locale(lang));

          final widget = EfZoneCurveWidget(
            workouts: const [
              {
                'date': '2026-11-05',
                'avg_power': 210.0,
                'hr': 148,
                'ef': 1.42,
                'zone': 'Z2',
                'kind': 'Erg',
                'duration_seconds': 3600,
              }
            ],
            periodStart: DateTime(2026, 11, 1),
            periodEnd: DateTime(2026, 11, 28),
            athleteName: 'أحمد البطل',
            playerId: 1,
          );

          await tester.pumpWidget(
            MediaQuery(
              data: MediaQueryData(
                size: size,
                textScaler: TextScaler.linear(scale),
              ),
              child: MaterialApp(
                locale: Locale(lang),
                home: Scaffold(
                  body: SingleChildScrollView(child: widget),
                ),
              ),
            ),
          );
          await tester.pump();
          for (int i = 0; i < 5; i++) {
            await tester.pump(const Duration(milliseconds: 20));
          }
          expect(tester.takeException(), isNull, reason: 'Failed for EfZoneCurveWidget ($lang)');
        }
      });

      testWidgets(
          'DecouplingTrendCurveWidget renders without overflow at ${size.width.toInt()}x${size.height.toInt()} (scale: $scale)',
          (tester) async {
        tester.view.physicalSize = Size(size.width * 2.0, size.height * 2.0);
        tester.view.devicePixelRatio = 2.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        for (final lang in ['ar', 'en']) {
          await AppLanguage.instance.setLocale(Locale(lang));

          final widget = DecouplingTrendCurveWidget(
            workouts: const [
              {
                'date': '2026-11-05',
                'decoupling': 4.5,
                'zone': 'Z2',
                'kind': 'Erg',
                'duration_seconds': 3600,
              }
            ],
            periodStart: DateTime(2026, 11, 1),
            periodEnd: DateTime(2026, 11, 28),
            athleteName: 'أحمد البطل',
            playerId: 1,
          );

          await tester.pumpWidget(
            MediaQuery(
              data: MediaQueryData(
                size: size,
                textScaler: TextScaler.linear(scale),
              ),
              child: MaterialApp(
                locale: Locale(lang),
                home: Scaffold(
                  body: SingleChildScrollView(child: widget),
                ),
              ),
            ),
          );
          await tester.pump();
          for (int i = 0; i < 5; i++) {
            await tester.pump(const Duration(milliseconds: 20));
          }
          expect(tester.takeException(), isNull, reason: 'Failed for DecouplingTrendCurveWidget ($lang)');
        }
      });

      testWidgets(
          'DynamicWattsCurveWidget renders without overflow at ${size.width.toInt()}x${size.height.toInt()} (scale: $scale)',
          (tester) async {
        tester.view.physicalSize = Size(size.width * 2.0, size.height * 2.0);
        tester.view.devicePixelRatio = 2.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        for (final lang in ['ar', 'en']) {
          await AppLanguage.instance.setLocale(Locale(lang));

          final widget = DynamicWattsCurveWidget(
            workouts: const [
              {
                'date': '2026-11-05',
                'avg_power': 210.0,
                'hr': 148,
                'zone': 'Z2',
                'kind': 'Erg',
                'duration_seconds': 3600,
              }
            ],
            periodStart: DateTime(2026, 11, 1),
            periodEnd: DateTime(2026, 11, 28),
            athleteName: 'أحمد البطل',
            playerId: 1,
          );

          await tester.pumpWidget(
            MediaQuery(
              data: MediaQueryData(
                size: size,
                textScaler: TextScaler.linear(scale),
              ),
              child: MaterialApp(
                locale: Locale(lang),
                home: Scaffold(
                  body: SingleChildScrollView(child: widget),
                ),
              ),
            ),
          );
          await tester.pump();
          for (int i = 0; i < 5; i++) {
            await tester.pump(const Duration(milliseconds: 20));
          }
          expect(tester.takeException(), isNull, reason: 'Failed for DynamicWattsCurveWidget ($lang)');
        }
      });

      testWidgets(
          'WorkoutDecouplingCurve renders without overflow at ${size.width.toInt()}x${size.height.toInt()} (scale: $scale)',
          (tester) async {
        tester.view.physicalSize = Size(size.width * 2.0, size.height * 2.0);
        tester.view.devicePixelRatio = 2.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        for (final lang in ['ar', 'en']) {
          await AppLanguage.instance.setLocale(Locale(lang));

          const widget = WorkoutDecouplingCurve(
            rawReadingsText:
                'W200-HR140-T5, W205-HR142-T10, W210-HR145-T15, W215-HR148-T20, W212-HR149-T25, W210-HR150-T30',
            durationMinutes: 60.0,
            zoneKey: 'Z2',
          );

          await tester.pumpWidget(
            MediaQuery(
              data: MediaQueryData(
                size: size,
                textScaler: TextScaler.linear(scale),
              ),
              child: MaterialApp(
                locale: Locale(lang),
                home: const Scaffold(
                  body: SingleChildScrollView(child: widget),
                ),
              ),
            ),
          );
          await tester.pump();
          for (int i = 0; i < 5; i++) {
            await tester.pump(const Duration(milliseconds: 20));
          }
          expect(tester.takeException(), isNull, reason: 'Failed for WorkoutDecouplingCurve ($lang)');
        }
      });
    }
  }
}
