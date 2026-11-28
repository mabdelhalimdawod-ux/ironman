import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:rowing_app/app_strings.dart';
import 'package:rowing_app/auth_service.dart';
import 'package:rowing_app/cp_bars_curve.dart';
import 'package:rowing_app/db.dart';
import 'package:rowing_app/decoupling_curve.dart';
import 'package:rowing_app/decoupling_trend_curve.dart';
import 'package:rowing_app/dynamic_watts_curve.dart';
import 'package:rowing_app/ef_zone_curve.dart';
import 'package:rowing_app/eupnea_curve.dart';
import 'package:rowing_app/heart_rate_zones.dart';
import 'package:rowing_app/progress_calcs.dart';
import 'package:rowing_app/progress_curve_page.dart';
import 'package:rowing_app/progress_period_filter.dart';
import 'package:rowing_app/recovery_curves.dart';
import 'package:rowing_app/scrollable_chart_container.dart';
import 'package:rowing_app/workout_kinds.dart';

Widget _wrapTestApp({
  required Widget child,
  bool isArabic = true,
  double textScale = 1.0,
}) {
  return MaterialApp(
    locale: Locale(isArabic ? 'ar' : 'en'),
    home: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
        ),
        child: Directionality(
          textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
          child: Scaffold(
            backgroundColor: const Color(0xFF0A1424),
            body: SingleChildScrollView(child: child),
          ),
        ),
      ),
    ),
  );
}

void _assertAllVisibleTextsMinFont12(WidgetTester tester) {
  final textWidgets = tester.widgetList<Text>(find.byType(Text));
  for (final t in textWidgets) {
    final fontSize = t.style?.fontSize;
    if (fontSize != null) {
      expect(
        fontSize,
        greaterThanOrEqualTo(12.0),
        reason: 'Font size < 12 found on text "${t.data}": $fontSize',
      );
    }
  }
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('المرحلة (ن) — 1. القائمة المركزية لأنواع التمرين وفرز الأداء', () {
    test('القائمة المركزية تطابق القائمة الأصلية والمحلية', () {
      expect(
        WorkoutKinds.all,
        equals(['Erg', 'Row', 'Run', 'bike', 'Fitness', 'Stretch', 'Mob']),
      );
      expect(
        WorkoutKinds.performanceKinds,
        equals(['Erg', 'Row', 'Run', 'bike', 'Fitness']),
      );

      final sAr = AppStrings(true);
      final sEn = AppStrings(false);
      expect(WorkoutKinds.displayName('Erg', sAr), equals(sAr.typeErg));
      expect(WorkoutKinds.displayName('Row', sAr), equals(sAr.typeWaterRowing));
      expect(WorkoutKinds.displayName('Water', sEn), equals(sEn.typeWaterRowing));
      expect(WorkoutKinds.displayName('Stretch', sAr), equals(sAr.typeStretch));
      expect(WorkoutKinds.displayName('Mob', sEn), equals(sEn.typeMobility));

      expect(WorkoutKinds.isPerformanceKind('Erg'), isTrue);
      expect(WorkoutKinds.isPerformanceKind('Water'), isTrue);
      expect(WorkoutKinds.isPerformanceKind('Running'), isTrue);
      expect(WorkoutKinds.isPerformanceKind('Cycling'), isTrue);
      expect(WorkoutKinds.isPerformanceKind('Stretch'), isFalse);
      expect(WorkoutKinds.isPerformanceKind('Mob'), isFalse);
      expect(WorkoutKinds.isPerformanceKind('Warmup'), isFalse);
      expect(WorkoutKinds.isPerformanceKind('تهدئة'), isFalse);
      expect(WorkoutKinds.isPerformanceKind('إحماء'), isFalse);
    });
  });

  group('المرحلة (ن) — 2. سياسة كل تمرينة نقطة + التواريخ الفعلية + الأفضل في اليوم', () {
    test('buildWorkoutDateSeries يفصل التمرينات في نفس اليوم ويرسم التواريخ الفعلية فقط', () {
      final workouts = <Map<String, Object?>>[
        // خارج الفترة (أكتوبر وديسمبر) يجب استبعاده
        {'date': '2026-10-30', 'avg_power': 190.0, 'hr': 142, 'zone': 'Z2', 'kind': 'Erg'},
        // يوم 2 نوفمبر (تمرينة واحدة)
        {'date': '2026-11-02', 'avg_power': 200.0, 'hr': 145, 'zone': 'Z2', 'kind': 'Erg'},
        // يوم 5 نوفمبر: تمرينتان نفس اليوم (الثانية أفضل 230 > 205)
        {'date': '2026-11-05', 'avg_power': 205.0, 'hr': 148, 'zone': 'Z2', 'kind': 'Erg'},
        {'date': '2026-11-05', 'avg_power': 230.0, 'hr': 150, 'zone': 'Z2', 'kind': 'Erg'},
        // يوم 12 نوفمبر (تمرينة واحدة)
        {'date': '2026-11-12', 'avg_power': 220.0, 'hr': 149, 'zone': 'Z2', 'kind': 'Erg'},
        {'date': '2026-12-01', 'avg_power': 250.0, 'hr': 152, 'zone': 'Z2', 'kind': 'Erg'},
      ];

      final resHigher = ProgressCalcs.buildWorkoutDateSeries(
        workouts: workouts,
        periodStart: DateTime(2026, 11, 1),
        periodEnd: DateTime(2026, 11, 30),
        extractValue: (r) => (r['avg_power'] as num?)?.toDouble(),
        higherIsBetter: true,
      );

      // التواريخ الفعلية فقط بدون فراغات (3 تواريخ وليس 30 يوم)
      expect(resHigher.activeDates.length, equals(3));
      expect(resHigher.activeDates[0], equals(DateTime(2026, 11, 2)));
      expect(resHigher.activeDates[1], equals(DateTime(2026, 11, 5)));
      expect(resHigher.activeDates[2], equals(DateTime(2026, 11, 12)));

      // إجمالي 4 تمرينات في الفترة
      expect(resHigher.allPoints.length, equals(4));
      // الخط يمر بـ 3 نقاط فقط (الأعلى في كل يوم)
      expect(resHigher.bestPoints.length, equals(3));
      expect(resHigher.bestPoints[1].value, equals(230.0));
      expect(resHigher.bestPoints[1].dayOrder, equals(2));
      expect(resHigher.bestPoints[1].isBestOfDay, isTrue);

      // النقطة الأخرى في يوم 5 نوفمبر تظهر باهتة بدون خط
      expect(resHigher.dimmedPoints.length, equals(1));
      expect(resHigher.dimmedPoints[0].value, equals(205.0));
      expect(resHigher.dimmedPoints[0].dayOrder, equals(1));
      expect(resHigher.dimmedPoints[0].xSlotIndex, equals(1));
      expect(resHigher.dimmedPoints[0].isBestOfDay, isFalse);

      // عند higherIsBetter = false (مثل Decoupling و Eupnea): الأقل هو الأفضل
      final resLower = ProgressCalcs.buildWorkoutDateSeries(
        workouts: [
          {'date': '2026-11-05', 'decoupling': 6.4, 'hr': 150, 'zone': 'Z2', 'kind': 'Erg'},
          {'date': '2026-11-05', 'decoupling': 2.8, 'hr': 146, 'zone': 'Z2', 'kind': 'Erg'},
        ],
        periodStart: DateTime(2026, 11, 1),
        periodEnd: DateTime(2026, 11, 30),
        extractValue: (r) => (r['decoupling'] as num?)?.toDouble(),
        higherIsBetter: false,
      );
      expect(resLower.bestPoints.single.value, equals(2.8));
      expect(resLower.dimmedPoints.single.value, equals(6.4));
    });
  });

  group('المرحلة (ن) — 3. منحنيات الأداء: شروط الواجهة والنصوص والـ Tooltip والتمرير', () {
    final sampleWorkouts = <Map<String, Object?>>[
      {'date': '2026-11-02', 'avg_power': 200.0, 'hr': 142, 'decoupling': 5.5, 'eupnea_1': 42.0, 'eupnea_2': 44.0, 'eupnea_3': 46.0, 'zone': 'Z2', 'kind': 'Erg'},
      {'date': '2026-11-05', 'avg_power': 210.0, 'hr': 148, 'decoupling': 6.0, 'eupnea_1': 45.0, 'eupnea_2': 46.0, 'eupnea_3': 48.0, 'zone': 'Z2', 'kind': 'Erg'},
      {'date': '2026-11-05', 'avg_power': 235.0, 'hr': 147, 'decoupling': 2.5, 'eupnea_1': 33.0, 'eupnea_2': 35.0, 'eupnea_3': 37.0, 'zone': 'Z2', 'kind': 'Erg'},
      {'date': '2026-11-12', 'avg_power': 225.0, 'hr': 146, 'decoupling': 3.2, 'eupnea_1': 36.0, 'eupnea_2': 38.0, 'eupnea_3': 40.0, 'zone': 'Z2', 'kind': 'Erg'},
      // نوع Stretch لا يجب أن يظهر في منحنيات الأداء أو التنفس
      {'date': '2026-11-14', 'avg_power': 120.0, 'hr': 110, 'decoupling': 1.0, 'eupnea_1': 20.0, 'zone': 'Z1', 'kind': 'Stretch'},
      // نوع Mob لا يجب أن يظهر في منحنيات الأداء أو التنفس
      {'date': '2026-11-15', 'avg_power': 110.0, 'hr': 105, 'decoupling': 1.0, 'eupnea_1': 19.0, 'zone': 'Z1', 'kind': 'Mob'},
    ];

    testWidgets('DynamicWattsCurveWidget: كل تمرينة نقطة + باهت نفس اليوم + لا MA7 + لا Stretch/Mob/All + Tooltip كامل', (tester) async {
      await AppLanguage.instance.setLocale(const Locale('ar'));
      final s = AppStrings(true);

      await tester.pumpWidget(_wrapTestApp(
        isArabic: true,
        child: DynamicWattsCurveWidget(
          workouts: sampleWorkouts,
          periodStart: DateTime(2026, 11, 1),
          periodEnd: DateTime(2026, 11, 20),
          athleteName: 'كريم',
          playerId: 1,
        ),
      ));
      await tester.pump();

      // العنوان بدون MA7 ولا All ولا Stretch ولا Mob
      expect(find.text(s.dynamicWattsTitle), findsOneWidget);
      expect(find.text(s.movingAverage7Legend), findsNothing);
      expect(find.textContaining('متوسط متحرك'), findsNothing);
      expect(find.text(s.allWorkoutsKind), findsNothing);
      expect(find.text(s.typeStretch), findsNothing);
      expect(find.text(s.typeMobility), findsNothing);
      expect(find.text(s.typeWaterRowing), findsOneWidget);
      expect(find.text(s.sameDayDimmedLegend), findsOneWidget);

      // التحقق من الخط الأساسي (3 نقاط أفضل يومية) والخط الباهت (barWidth == 0 ونقطة 210)
      final chart = tester.widget<LineChart>(find.byType(LineChart));
      final bars = chart.data.lineBarsData;
      final dimmedBar = bars.firstWhere((b) => b.barWidth == 0);
      final bestBar = bars.firstWhere((b) => b.barWidth > 0);
      expect(dimmedBar.spots.single.x, equals(1.0));
      expect(dimmedBar.spots.single.y, equals(210.0));
      expect(bestBar.spots.length, equals(3));
      expect(bestBar.spots[1].y, equals(235.0));

      // التحقق من الـ Tooltip عند لمس نقطة في اليوم الثاني
      final bestBarIdx = bars.indexOf(bestBar);
      final tooltipItems = chart.data.lineTouchData.touchTooltipData.getTooltipItems(
        [LineBarSpot(bestBar, bestBarIdx, bestBar.spots[1])],
      );
      final tipText = tooltipItems.first?.text ?? '';
      expect(tipText, contains('5/11/2026'));
      expect(tipText, contains(s.workoutNumberInDay));
      expect(tipText, contains('235 W'));
      expect(tipText, contains('147 bpm'));
      expect(tipText, contains('Zone 2 - UT2'));
      expect(tipText, contains(s.typeErg));

      // التحقق من محور Y ثابت خارج ScrollView وأحجام الخطوط >= 12 والـ Legend في سطر واحد
      expect(find.byType(ScrollableChartFrame), findsOneWidget);
      expect(find.byType(SingleLineLegend), findsOneWidget);
      _assertAllVisibleTextsMinFont12(tester);
    });

    testWidgets('EfZoneCurveWidget يعرض معامل الكفاءة (EF) لكل تمرينة بدون متوسط أسبوعي أو MA7', (tester) async {
      for (final isAr in [true, false]) {
        await AppLanguage.instance.setLocale(Locale(isAr ? 'ar' : 'en'));
        final s = AppStrings(isAr);

        await tester.pumpWidget(_wrapTestApp(
          isArabic: isAr,
          child: EfZoneCurveWidget(
            workouts: sampleWorkouts,
            periodStart: DateTime(2026, 11, 1),
            periodEnd: DateTime(2026, 11, 20),
            athleteName: 'كريم',
            playerId: 1,
          ),
        ));
        await tester.pump();

        expect(find.text(s.efPerWorkoutTitle), findsOneWidget);
        expect(find.textContaining('متوسط EF أسبوعي'), findsNothing);
        expect(find.textContaining('Weekly Avg'), findsNothing);
        expect(find.text(s.movingAverage7Legend), findsNothing);
        expect(find.text(s.typeStretch), findsNothing);
        expect(find.text(s.typeMobility), findsNothing);

        final chart = tester.widget<LineChart>(find.byType(LineChart));
        final bestBar = chart.data.lineBarsData.firstWhere((b) => b.barWidth > 0);
        // 3 أيام فعلية (2, 5, 12 نوفمبر) والأعلى EF في 5 نوفمبر هو 235/147 ≈ 1.598
        expect(bestBar.spots.length, equals(3));
        expect(bestBar.spots[1].y, closeTo(235.0 / 147.0, 0.01));
        _assertAllVisibleTextsMinFont12(tester);
      }
    });

    testWidgets('DecouplingTrendCurveWidget: العنوان الصحيح (التفكك القلبي %) والأقل يومياً على الخط', (tester) async {
      for (final isAr in [true, false]) {
        await AppLanguage.instance.setLocale(Locale(isAr ? 'ar' : 'en'));
        final s = AppStrings(isAr);

        await tester.pumpWidget(_wrapTestApp(
          isArabic: isAr,
          child: DecouplingTrendCurveWidget(
            workouts: sampleWorkouts,
            periodStart: DateTime(2026, 11, 1),
            periodEnd: DateTime(2026, 11, 20),
            athleteName: 'كريم',
            playerId: 1,
          ),
        ));
        await tester.pump();

        expect(find.text(s.decouplingPerWorkoutTitle), findsOneWidget);
        expect(find.text(s.chipEF), findsNothing);
        expect(find.text(s.movingAverage7Legend), findsNothing);

        final chart = tester.widget<LineChart>(find.byType(LineChart));
        final dimmedBar = chart.data.lineBarsData.firstWhere((b) => b.barWidth == 0);
        final bestBar = chart.data.lineBarsData.firstWhere((b) => b.barWidth > 0);
        // الأقل أفضل: 2.5 على الخط، و 6.0 باهت
        expect(bestBar.spots[1].y, equals(2.5));
        expect(dimmedBar.spots.single.y, equals(6.0));
        _assertAllVisibleTextsMinFont12(tester);
      }
    });

    testWidgets('EupneaCurveBlock: عزل (النوع + المنطقة + القياس) وبدون ALL ولا Stretch/Mob', (tester) async {
      await AppLanguage.instance.setLocale(const Locale('ar'));
      final s = AppStrings(true);

      final eupneaWorkouts = [
        ...sampleWorkouts,
        // منطقة Z4 مختلفة عن Z2 لا يجب أن تختلط بـ Z2 عند اختيار Z2
        {'date': '2026-11-08', 'eupnea_1': 80.0, 'eupnea_2': 82.0, 'eupnea_3': 85.0, 'hr': 168, 'zone': 'Z4', 'kind': 'Erg'},
      ];

      await tester.pumpWidget(_wrapTestApp(
        isArabic: true,
        child: EupneaCurveBlock(
          s: s,
          athleteName: 'خالد',
          athleteColor: Colors.tealAccent,
          workouts: eupneaWorkouts,
          periodStart: DateTime(2026, 11, 1),
          periodEnd: DateTime(2026, 11, 20),
          mhr: 190,
          effectiveRhr: 60,
          isLoading: false,
        ),
      ));
      await tester.pump();

      expect(find.text(s.allZonesLabel), findsNothing);
      expect(find.text(s.allWorkoutsKind), findsNothing);
      expect(find.text(s.typeStretch), findsNothing);
      expect(find.text(s.typeMobility), findsNothing);
      expect(find.text(s.reading1Label), findsWidgets);
      expect(find.text(s.reading2Label), findsWidgets);
      expect(find.text(s.reading3Label), findsWidgets);

      final chart = tester.widget<LineChart>(find.byType(LineChart));
      // 3 خطوط أساسية للقياسات (3 أيام في Erg-Z2 فقط، بدون يوم 8 نوفمبر Z4 ولا Stretch يوم 14)
      final bestBars = chart.data.lineBarsData.where((b) => b.barWidth > 2.0).toList();
      expect(bestBars.length, equals(3));
      expect(bestBars[0].spots.length, equals(3));
      // أقل ثانية يوم 5 نوفمبر للقياس 1 هي 33 ثانية (وليست 45)
      expect(bestBars[0].spots[1].y, equals(33.0));
      _assertAllVisibleTextsMinFont12(tester);
    });
  });

  group('المرحلة (ن) — 4. تعطيل الزيادات غير المطلوبة وإزالة MA7 من الاستشفاء و CP Bars', () {
    testWidgets('HRV يخفي حزام SWC و MA7، و RHR يخفي تنبيه الارتفاع، و CP Bars يعرض BI كرقم فقط بدون تصنيف ميل', (tester) async {
      await AppLanguage.instance.setLocale(const Locale('ar'));
      final s = AppStrings(true);
      final now = DateTime(2026, 11, 10);

      final points = [
        for (int i = 0; i < 7; i++)
          DateValuePoint(date: now.subtract(Duration(days: 7 - i)), value: 58.0),
        DateValuePoint(date: now, value: 78.0), // مرتفع جداً لتأكيد إخفاء تنبيه RHR
      ];

      await tester.pumpWidget(_wrapTestApp(
        isArabic: true,
        child: Column(
          children: [
            HrvCurveBlock(
              s: s,
              athleteName: 'أحمد',
              athleteColor: Colors.cyanAccent,
              points: points,
              isLoading: false,
            ),
            RhrCurveBlock(
              s: s,
              athleteName: 'محمد',
              athleteColor: Colors.orangeAccent,
              points: points,
              isLoading: false,
            ),
            CpBarsCurveBlock(
              s: s,
              athleteName: 'عمر',
              athleteColor: Colors.limeAccent,
              playerId: 1,
              periodStart: DateTime(2026, 11, 1),
              periodEnd: DateTime(2026, 11, 30),
              cpTestRows: const [
                {'date': '2026-11-05', 'test_type': '500m', 'distance': 500, 'duration_seconds': 85},
                {'date': '2026-11-05', 'test_type': '1500m', 'distance': 1500, 'duration_seconds': 285},
                {'date': '2026-11-05', 'test_type': '2000m', 'distance': 2000, 'duration_seconds': 405},
                {'date': '2026-11-15', 'test_type': '500m', 'distance': 500, 'duration_seconds': 80},
                {'date': '2026-11-15', 'test_type': '1500m', 'distance': 1500, 'duration_seconds': 280},
                {'date': '2026-11-15', 'test_type': '2000m', 'distance': 2000, 'duration_seconds': 410},
              ],
              cpValuePoints: const [],
              isLoading: false,
            ),
          ],
        ),
      ));
      await tester.pump();

      expect(find.text(s.swcBandLegend), findsNothing);
      expect(find.text(s.ma7Label), findsNothing);
      expect(find.text(s.rhrElevatedAlert), findsNothing);
      expect(find.text(s.explosiveLeaning), findsNothing);
      expect(find.text(s.enduranceLeaning), findsNothing);
      expect(find.text(s.balancedLeaning), findsNothing);

      // المنطق الحسابي الداخلي ما زال سليماً بدون حذف
      expect(ProgressCalcs.isRhrElevated(todayRhr: 78, ma7Rhr: 58), isTrue);
      expect(
        ProgressCalcs.classifyBalanceIndex(bi: 90, avgBi: 50),
        equals(BalanceIndexLeaning.explosive),
      );
      _assertAllVisibleTextsMinFont12(tester);
    });
  });

  group('المرحلة (ن) — 5. مسميات مؤشر الطاقة واقتصاد الطاقة + التمرير لآخر تاريخ + الاستجابة', () {
    test('مسميات مؤشر الطاقة واقتصاد الطاقة مطابقة لقرار كوتش في اللغتين', () {
      final sAr = AppStrings(true);
      final sEn = AppStrings(false);

      expect(sAr.energyIndexCurveTitle, equals('منحنى مؤشر الطاقة'));
      expect(sAr.energyEconomyIndexCurveTitle, equals('منحنى مؤشر اقتصاد الطاقة'));
      expect(
        sAr.energyEconomyExplanation,
        equals('كلما انخفض المنحنى عند منطقة دلّ على اقتصاد طاقة أفضل (تكلفة طاقة أقل) للاعب في هذه المنطقة. تقديري.'),
      );

      expect(sEn.energyIndexCurveTitle, equals('Energy Index Curve'));
      expect(sEn.energyEconomyIndexCurveTitle, equals('Energy Economy Index Curve'));
      expect(sEn.energyEconomyExplanation, contains('lower the curve'));
    });

    testWidgets('Matrix Zone يظهر الاسم الجديد وتسمية اقتصاد الطاقة وشرحها عند توفر بيانات', (tester) async {
      Database? db;
      try {
        await AppLanguage.instance.setLocale(const Locale('ar'));
        await tester.runAsync(() async {
          db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
          await db!.execute(
              'CREATE TABLE IF NOT EXISTS players(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, mhr INTEGER, active INTEGER DEFAULT 1)');
          await db!.execute('''
            CREATE TABLE IF NOT EXISTS logs(
              player_id INTEGER,
              date TEXT,
              idx INTEGER,
              rhr INTEGER,
              hrv INTEGER,
              hr INTEGER,
              hr_max INTEGER,
              hr_post INTEGER,
              hr_1min INTEGER,
              weight REAL,
              fatigue INTEGER,
              sleep_hours REAL,
              readiness INTEGER,
              player_notes TEXT,
              avg_power REAL,
              max_power REAL,
              duration_seconds INTEGER,
              distance INTEGER,
              split_500 REAL,
              ef REAL,
              eupnea REAL,
              decoupling REAL,
              zone TEXT,
              kind TEXT,
              PRIMARY KEY(player_id, date, idx)
            )
          ''');
          await db!.execute('''
            CREATE TABLE IF NOT EXISTS matrix_zone_config(
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              indicator_key TEXT NOT NULL,
              weight REAL NOT NULL,
              direction TEXT DEFAULT 'up',
              sort_order INTEGER DEFAULT 0
            )
          ''');
          await db!.execute('''
            CREATE TABLE IF NOT EXISTS progress_baseline_config(
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              min_workouts INTEGER DEFAULT 3,
              max_window INTEGER DEFAULT 5,
              convergence_pct REAL DEFAULT 3.0,
              movement_threshold_pct REAL DEFAULT 1.0
            )
          ''');
          await db!.execute('''
            CREATE TABLE IF NOT EXISTS cp_tests(
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              player_id INTEGER,
              date TEXT,
              test_type TEXT,
              duration_seconds INTEGER,
              avg_power REAL,
              max_power REAL,
              distance INTEGER,
              avg_hr INTEGER,
              max_hr INTEGER,
              split_500 REAL,
              notes TEXT
            )
          ''');
          await db!.execute('''
            CREATE TABLE IF NOT EXISTS cp_values(
              player_id INTEGER,
              date TEXT,
              cp REAL,
              w_prime REAL,
              PRIMARY KEY(player_id, date)
            )
          ''');
          await db!.execute('''
            CREATE TABLE IF NOT EXISTS sessions(
              date TEXT,
              idx INTEGER,
              kind TEXT,
              zone TEXT,
              time TEXT,
              PRIMARY KEY(date, idx)
            )
          ''');
          await db!.execute('''
            CREATE TABLE IF NOT EXISTS daily_load(
              player_id INTEGER NOT NULL,
              date TEXT NOT NULL,
              tss REAL,
              ctl REAL NOT NULL,
              atl REAL NOT NULL,
              tsb REAL NOT NULL,
              PRIMARY KEY(player_id, date)
            )
          ''');
          await db!.execute('''
            CREATE TABLE IF NOT EXISTS shared_curve_cache(
              player_id INTEGER,
              date TEXT,
              idx INTEGER,
              avg_power REAL,
              hr INTEGER,
              zone TEXT,
              kind TEXT,
              PRIMARY KEY(player_id, date, idx)
            )
          ''');
          DB.testDatabase = db;

          await db!.insert('players', {'id': 1, 'name': 'أحمد كمال', 'mhr': 195, 'active': 1});

          for (final z in ['Z1', 'Z2', 'Z3', 'Z4']) {
            for (int i = 0; i < 4; i++) {
              final d = '2026-11-0${i + 1}';
              await db!.insert('logs', {
                'player_id': 1,
                'date': d,
                'idx': HeartRateZones.orderedZones.indexOf(z),
                'avg_power': 180.0 + HeartRateZones.orderedZones.indexOf(z) * 35.0 + i * 2,
                'hr': 130 + HeartRateZones.orderedZones.indexOf(z) * 12,
                'duration_seconds': 2400,
                'ef': 1.3 + HeartRateZones.orderedZones.indexOf(z) * 0.1,
                'decoupling': 4.0,
                'zone': z,
                'kind': 'Erg',
              });
            }
          }

          await tester.pumpWidget(
            MaterialApp(
              locale: const Locale('ar'),
              home: ProgressCurvePage(
                curveType: ProgressCurveType.matrixZone,
                user: const AppUser(
                  id: 1,
                  email: 'coach@test.local',
                  name: 'Coach',
                  role: 'coach',
                  subscriptionActive: true,
                ),
                initialPeriod: ProgressPeriodSelection(
                  mode: ProgressPeriodMode.custom,
                  start: DateTime(2026, 11, 1),
                  end: DateTime(2026, 11, 20),
                ),
              ),
            ),
          );
          for (int i = 0; i < 15; i++) {
            await Future.delayed(const Duration(milliseconds: 30));
            await tester.pump();
          }
        });
        await tester.pump();

        final s = AppStrings(true);
        expect(find.text(s.energyIndexCurveTitle), findsWidgets);
        expect(find.text(s.energyEconomyIndexCurveTitle), findsWidgets);
        expect(find.text(s.energyEconomyExplanation), findsWidgets);
        expect(find.text('منحنى القدرة'), findsNothing);
        expect(find.text('Capacity Curve'), findsNothing);
        _assertAllVisibleTextsMinFont12(tester);
      } finally {
        await tester.runAsync(() async {
          DB.testDatabase = null;
          await db?.close();
        });
      }
    });

    testWidgets('التمرير الأفقي يبدأ من أحدث تاريخ (maxScrollExtent > 0) مع 20 نقطة على شاشة 320px', (tester) async {
      tester.view.physicalSize = const Size(320 * 2.0, 640 * 2.0);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final manyWorkouts = List.generate(20, (i) {
        final d = DateTime(2026, 11, 1).add(Duration(days: i));
        return {
          'date': ProgressCalcs.formatDate(d),
          'avg_power': 200.0 + i * 2,
          'hr': 145,
          'zone': 'Z2',
          'kind': 'Erg',
        };
      });

      await tester.pumpWidget(_wrapTestApp(
        isArabic: true,
        child: DynamicWattsCurveWidget(
          workouts: manyWorkouts,
          periodStart: DateTime(2026, 11, 1),
          periodEnd: DateTime(2026, 11, 25),
          athleteName: 'لاعب',
          playerId: 1,
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final hScrollFinder = find.descendant(
        of: find.byType(ScrollableChartFrame),
        matching: find.byWidgetPredicate(
          (w) => w is SingleChildScrollView && w.scrollDirection == Axis.horizontal,
        ),
      );
      final hScroll = tester.widget<SingleChildScrollView>(hScrollFinder);
      expect(hScroll.controller, isNotNull);
      expect(hScroll.controller!.position.maxScrollExtent, greaterThan(0));
      expect(
        hScroll.controller!.offset,
        closeTo(hScroll.controller!.position.maxScrollExtent, 1.0),
      );
    });

    for (final size in [const Size(320, 640), const Size(360, 800), const Size(411, 891)]) {
      for (final scale in [1.0, 1.3]) {
        for (final isAr in [true, false]) {
          testWidgets(
            'توافق الأحجام ${size.width.toInt()}x${size.height.toInt()} scale=$scale (${isAr ? "AR" : "EN"}) بدون overflow',
            (tester) async {
              tester.view.physicalSize = Size(size.width * 2.0, size.height * 2.0);
              tester.view.devicePixelRatio = 2.0;
              addTearDown(() {
                tester.view.resetPhysicalSize();
                tester.view.resetDevicePixelRatio();
              });

              await AppLanguage.instance.setLocale(Locale(isAr ? 'ar' : 'en'));
              final s = AppStrings(isAr);
              final workouts = [
                {'date': '2026-11-05', 'avg_power': 210.0, 'hr': 145, 'decoupling': 4.5, 'eupnea_1': 35.0, 'eupnea_2': 37.0, 'eupnea_3': 40.0, 'zone': 'Z2', 'kind': 'Erg'},
                {'date': '2026-11-05', 'avg_power': 230.0, 'hr': 146, 'decoupling': 2.5, 'eupnea_1': 31.0, 'eupnea_2': 33.0, 'eupnea_3': 35.0, 'zone': 'Z2', 'kind': 'Erg'},
                {'date': '2026-11-12', 'avg_power': 225.0, 'hr': 144, 'decoupling': 3.1, 'eupnea_1': 32.0, 'eupnea_2': 34.0, 'eupnea_3': 36.0, 'zone': 'Z2', 'kind': 'Erg'},
              ];

              await tester.pumpWidget(_wrapTestApp(
                isArabic: isAr,
                textScale: scale,
                child: Column(
                  children: [
                    DynamicWattsCurveWidget(
                      workouts: workouts,
                      periodStart: DateTime(2026, 11, 1),
                      periodEnd: DateTime(2026, 11, 20),
                      athleteName: 'Athlete',
                      playerId: 1,
                    ),
                    EfZoneCurveWidget(
                      workouts: workouts,
                      periodStart: DateTime(2026, 11, 1),
                      periodEnd: DateTime(2026, 11, 20),
                      athleteName: 'Athlete',
                      playerId: 1,
                    ),
                    DecouplingTrendCurveWidget(
                      workouts: workouts,
                      periodStart: DateTime(2026, 11, 1),
                      periodEnd: DateTime(2026, 11, 20),
                      athleteName: 'Athlete',
                      playerId: 1,
                    ),
                    EupneaCurveBlock(
                      s: s,
                      athleteName: 'Athlete',
                      athleteColor: Colors.tealAccent,
                      workouts: workouts,
                      periodStart: DateTime(2026, 11, 1),
                      periodEnd: DateTime(2026, 11, 20),
                      mhr: 190,
                      effectiveRhr: 60,
                      isLoading: false,
                    ),
                    const WorkoutDecouplingCurve(
                      rawReadingsText: 'W200-HR140-T5, W205-HR142-T10, W210-HR145-T15, W215-HR148-T20',
                      durationMinutes: 20,
                      zoneKey: 'Z2',
                    ),
                  ],
                ),
              ));
              await tester.pump();
              expect(tester.takeException(), isNull);
            },
          );
        }
      }
    }
  });
}
