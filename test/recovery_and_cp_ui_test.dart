import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rowing_app/app_strings.dart';
import 'package:rowing_app/cp_bars_curve.dart';
import 'package:rowing_app/eupnea_curve.dart';
import 'package:rowing_app/progress_calcs.dart';
import 'package:rowing_app/recovery_curves.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget buildTestApp({
    required Widget child,
    bool isArabic = true,
    double textScale = 1.0,
    Size size = const Size(360, 800),
  }) {
    return MediaQuery(
      data: MediaQueryData(
        size: size,
        textScaler: TextScaler.linear(textScale),
      ),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark(),
        home: Directionality(
          textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
          child: Scaffold(
            body: SingleChildScrollView(
              child: child,
            ),
          ),
        ),
      ),
    );
  }

  group('Recovery Curves UI Tests (Progress Batch 4)', () {
    final now = DateTime(2026, 11, 27);
    final hrvPoints = List.generate(
      14,
      (i) => DateValuePoint(
        date: now.subtract(Duration(days: 13 - i)),
        value: 60.0 + (i % 5) * 4.0,
      ),
    );

    testWidgets('HrvCurveBlock renders line chart and legend chips', (tester) async {
      final s = AppStrings(true);
      await tester.pumpWidget(
        buildTestApp(
          child: HrvCurveBlock(
            s: s,
            athleteName: 'أحمد علي',
            athleteColor: Colors.blueAccent,
            points: hrvPoints,
            isLoading: false,
          ),
        ),
      );

      expect(find.text('أحمد علي'), findsOneWidget);
      expect(find.text(s.hrvTitle), findsOneWidget);
      expect(find.text(s.ma7Label), findsOneWidget);
      expect(find.text(s.estimationNotice), findsOneWidget);
    });

    testWidgets('HrvCurveBlock shows insufficient data when points < 2', (tester) async {
      final s = AppStrings(true);
      await tester.pumpWidget(
        buildTestApp(
          child: HrvCurveBlock(
            s: s,
            athleteName: 'أحمد علي',
            athleteColor: Colors.blueAccent,
            points: [DateValuePoint(date: now, value: 65.0)],
            isLoading: false,
          ),
        ),
      );

      expect(find.text(s.insufficientData), findsOneWidget);
    });

    testWidgets('RhrCurveBlock shows alert banner when RHR is elevated (+5 bpm)', (tester) async {
      final s = AppStrings(true);
      // نقاط سابقة حول 55-60، واليوم قفز إلى 72 (أعلى من MA7 + 5)
      final rhrPoints = [
        for (int i = 0; i < 7; i++)
          DateValuePoint(date: now.subtract(Duration(days: 7 - i)), value: 58.0),
        DateValuePoint(date: now, value: 72.0),
      ];

      await tester.pumpWidget(
        buildTestApp(
          child: RhrCurveBlock(
            s: s,
            athleteName: 'محمد سامي',
            athleteColor: Colors.redAccent,
            points: rhrPoints,
            isLoading: false,
          ),
        ),
      );

      expect(find.text('محمد سامي'), findsOneWidget);
      expect(find.text(s.rhrElevatedAlert), findsOneWidget);
    });

    testWidgets('RhrCurveBlock does not show alert when RHR is normal', (tester) async {
      final s = AppStrings(true);
      final rhrPoints = [
        for (int i = 0; i < 7; i++)
          DateValuePoint(date: now.subtract(Duration(days: 7 - i)), value: 58.0),
        DateValuePoint(date: now, value: 59.0),
      ];

      await tester.pumpWidget(
        buildTestApp(
          child: RhrCurveBlock(
            s: s,
            athleteName: 'محمد سامي',
            athleteColor: Colors.redAccent,
            points: rhrPoints,
            isLoading: false,
          ),
        ),
      );

      expect(find.text(s.rhrElevatedAlert), findsNothing);
    });

    testWidgets('SleepCurveBlock & WeightCurveBlock render without errors', (tester) async {
      final s = AppStrings(true);
      final sleepPoints = [
        for (int i = 0; i < 7; i++)
          DateValuePoint(date: now.subtract(Duration(days: 7 - i)), value: 7.5),
      ];
      final weightPoints = [
        for (int i = 0; i < 7; i++)
          DateValuePoint(date: now.subtract(Duration(days: 7 - i)), value: 78.0),
      ];

      await tester.pumpWidget(
        buildTestApp(
          child: Column(
            children: [
              SleepCurveBlock(
                s: s,
                athleteName: 'كابتن محمود',
                athleteColor: Colors.greenAccent,
                points: sleepPoints,
                isLoading: false,
              ),
              WeightCurveBlock(
                s: s,
                athleteName: 'كابتن محمود',
                athleteColor: Colors.amberAccent,
                points: weightPoints,
                isLoading: false,
              ),
            ],
          ),
        ),
      );

      expect(find.text('كابتن محمود'), findsNWidgets(2));
      expect(find.text('${s.chipSleep} (hrs)'), findsOneWidget);
      expect(find.text('${s.chipWeight} (kg)'), findsOneWidget);
    });
  });

  group('Eupnea Curve UI Tests (Progress Batch 4)', () {
    final workouts = [
      {
        'date': '2026-11-20',
        'kind': 'Rowing',
        'zone': 'Z2',
        'eupnea_1': 45.0,
        'eupnea_2': 50.0,
        'eupnea_3': 55.0,
      },
      {
        'date': '2026-11-22',
        'kind': 'Rowing',
        'zone': 'Z2',
        'eupnea_1': 42.0,
        'eupnea_2': 48.0,
        'eupnea_3': 52.0,
      },
      {
        'date': '2026-11-25',
        'kind': 'Rowing',
        'zone': 'Z2',
        'eupnea_1': 39.0,
        'eupnea_2': 44.0,
        'eupnea_3': 49.0,
      },
    ];

    testWidgets('EupneaCurveBlock renders 3 series toggles and lower-is-better banner', (tester) async {
      final s = AppStrings(true);
      await tester.pumpWidget(
        buildTestApp(
          child: EupneaCurveBlock(
            s: s,
            athleteName: 'خالد إبراهيم',
            athleteColor: Colors.cyanAccent,
            workouts: workouts,
            periodStart: DateTime(2026, 11, 1),
            periodEnd: DateTime(2026, 11, 30),
            mhr: 190,
            effectiveRhr: 60,
            isLoading: false,
          ),
        ),
      );

      expect(find.text('خالد إبراهيم'), findsOneWidget);
      expect(find.text(s.reading1Label), findsOneWidget);
      expect(find.text(s.reading2Label), findsOneWidget);
      expect(find.text(s.reading3Label), findsOneWidget);
      expect(find.text(s.eupneaLowerIsBetter), findsOneWidget);
      expect(find.text(s.eupneaBelowBaselineNotice), findsOneWidget);

      // اختبار النقر على فلتر إخفاء القراءة 1
      await tester.tap(find.text(s.reading1Label));
      await tester.pumpAndSettle();
      expect(find.text('خالد إبراهيم'), findsOneWidget);
    });
  });

  group('Critical Power Bars UI Tests (Progress Batch 4)', () {
    testWidgets('CpBarsCurveBlock renders bars and interactive test calculator with live Watts', (tester) async {
      final s = AppStrings(true);
      final cpTestRows = [
        {
          'date': '2026-11-15',
          'cp': 250.0,
          'w_prime': 15000.0,
        },
        {
          'date': '2026-11-25',
          'cp': 260.0,
          'w_prime': 16000.0,
        },
      ];

      await tester.pumpWidget(
        buildTestApp(
          child: CpBarsCurveBlock(
            s: s,
            athleteName: 'عمر طارق',
            athleteColor: Colors.orangeAccent,
            playerId: 1,
            periodStart: DateTime(2026, 11, 1),
            periodEnd: DateTime(2026, 11, 30),
            cpTestRows: cpTestRows,
            cpValuePoints: const [],
            isLoading: false,
          ),
        ),
      );

      expect(find.text('عمر طارق'), findsOneWidget);
      expect(find.text(s.chipCP), findsWidgets);
      expect(find.text(s.chipWPrime), findsWidgets);
      expect(find.text(s.chipBalanceIndex), findsWidgets);

      // إدخال زمن للمسافة الأولى 500م (حقل الزمن index 1 في الصف الأول)
      final textFields = find.byType(TextField);
      expect(textFields, findsAtLeastNWidgets(2));

      await tester.enterText(textFields.at(1), '100');
      await tester.pumpAndSettle();

      // التحقق من حساب الواط تلقائياً (350 W)
      expect(find.text('350 W'), findsOneWidget);
    });
  });

  group('Responsive Overflow Tests (Progress Batch 4)', () {
    final sizes = [
      const Size(320, 640), // شاشة صغيرة
      const Size(360, 800), // شاشة قياسية
      const Size(411, 891), // شاشة كبيرة
    ];
    final scales = [1.0, 1.3]; // مقياس خط عادي ومكبر
    final locales = [true, false]; // عربي وإنجليزي

    for (final size in sizes) {
      for (final scale in scales) {
        for (final isAr in locales) {
          testWidgets('No overflow on ${size.width}x${size.height} scale $scale ${isAr ? "AR" : "EN"}', (tester) async {
            final s = AppStrings(isAr);
            final hrvPoints = [
              DateValuePoint(date: DateTime(2026, 11, 20), value: 65.0),
              DateValuePoint(date: DateTime(2026, 11, 21), value: 70.0),
              DateValuePoint(date: DateTime(2026, 11, 22), value: 68.0),
            ];

            await tester.pumpWidget(
              buildTestApp(
                isArabic: isAr,
                textScale: scale,
                size: size,
                child: Column(
                  children: [
                    HrvCurveBlock(
                      s: s,
                      athleteName: isAr ? 'لاعب تجربة' : 'Test Athlete',
                      athleteColor: Colors.blueAccent,
                      points: hrvPoints,
                      isLoading: false,
                    ),
                    RhrCurveBlock(
                      s: s,
                      athleteName: isAr ? 'لاعب تجربة' : 'Test Athlete',
                      athleteColor: Colors.redAccent,
                      points: hrvPoints,
                      isLoading: false,
                    ),
                  ],
                ),
              ),
            );

            expect(tester.takeException(), isNull);
          });
        }
      }
    }
  });
}
