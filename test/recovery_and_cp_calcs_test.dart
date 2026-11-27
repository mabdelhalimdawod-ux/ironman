import 'package:flutter_test/flutter_test.dart';
import 'package:rowing_app/progress_calcs.dart';

void main() {
  group('Critical Power Math Tests (Progress Batch 4)', () {
    test('wattsFromTime calculates exact Concept2 Watts', () {
      // 500m in 100.0s -> pace = 0.20 s/m -> 2.80 / (0.20^3) = 350.0 W
      final w500 = ProgressCalcs.wattsFromTime(500.0, 100.0);
      expect(w500, equals(350.0));

      // 1000m in 200.0s -> pace = 0.20 s/m -> 350.0 W
      final w1000 = ProgressCalcs.wattsFromTime(1000.0, 200.0);
      expect(w1000, equals(350.0));

      // Invalid inputs return 0.0
      expect(ProgressCalcs.wattsFromTime(0.0, 100.0), equals(0.0));
      expect(ProgressCalcs.wattsFromTime(500.0, 0.0), equals(0.0));
      expect(ProgressCalcs.wattsFromTime(-500.0, 100.0), equals(0.0));
    });

    test('balanceIndex calculates W\' (Joules) / CP (Watts)', () {
      // 15,000 Joules and 200 Watts -> 75.0 seconds
      final bi = ProgressCalcs.balanceIndex(15000.0, 200.0);
      expect(bi, equals(75.0));

      // CP <= 0 returns 0.0
      expect(ProgressCalcs.balanceIndex(15000.0, 0.0), equals(0.0));
      expect(ProgressCalcs.balanceIndex(15000.0, -200.0), equals(0.0));
    });

    test('calcCpAndWPrime calculates exact CP, W\', and BI from 3 known points', () {
      // Work = 200.0 * t + 15000.0
      // Point 1: t=100, W=350.0 -> distance=500.0
      // Point 2: t=200, W=275.0 -> pace=0.216743 -> distance=922.75
      // Point 3: t=400, W=237.5 -> pace=0.227589 -> distance=1757.55
      final tests = [
        (distanceM: 500.0, timeSec: 100.0),
        (distanceM: 922.75, timeSec: 200.0),
        (distanceM: 1757.55, timeSec: 400.0),
      ];

      final res = ProgressCalcs.calcCpAndWPrime(tests);
      expect(res, isNotNull);
      expect(res!.cpWatts, closeTo(200.0, 0.5));
      expect(res.wPrimeJoules, closeTo(15000.0, 50.0));
      expect(res.wPrimeKiloJoules, closeTo(15.0, 0.1));
      expect(res.balanceIndexSeconds, closeTo(75.0, 0.5));
      expect(res.validPointsCount, equals(3));
    });

    test('calcCpAndWPrime works accurately with 4 default distances (500, 750, 1500, 3500)', () {
      // 500m in 92s (450W), 750m in 148s (369W), 1500m in 320s (290W), 3500m in 820s (221W)
      final tests = [
        (distanceM: 500.0, timeSec: 92.0),
        (distanceM: 750.0, timeSec: 148.0),
        (distanceM: 1500.0, timeSec: 320.0),
        (distanceM: 3500.0, timeSec: 820.0),
      ];

      final res = ProgressCalcs.calcCpAndWPrime(tests);
      expect(res, isNotNull);
      expect(res!.cpWatts, greaterThan(150.0));
      expect(res.wPrimeJoules, greaterThan(1000.0));
      expect(res.balanceIndexSeconds, greaterThan(10.0));
      expect(res.validPointsCount, equals(4));
    });

    test('calcCpAndWPrime requires at least 3 valid distances', () {
      // Only 2 points
      final twoPoints = [
        (distanceM: 500.0, timeSec: 100.0),
        (distanceM: 750.0, timeSec: 160.0),
      ];
      expect(ProgressCalcs.calcCpAndWPrime(twoPoints), isNull);

      // 3 points but one has time=0
      final withZeroTime = [
        (distanceM: 500.0, timeSec: 100.0),
        (distanceM: 750.0, timeSec: 0.0),
        (distanceM: 1500.0, timeSec: 320.0),
      ];
      expect(ProgressCalcs.calcCpAndWPrime(withZeroTime), isNull);

      // Empty list
      expect(ProgressCalcs.calcCpAndWPrime([]), isNull);
    });

    test('classifyBalanceIndex correctly identifies endurance vs explosive leaning', () {
      const avgBi = 60.0;

      // Higher than average by > 2% -> explosive
      expect(
        ProgressCalcs.classifyBalanceIndex(bi: 75.0, avgBi: avgBi),
        equals(BalanceIndexLeaning.explosive),
      );

      // Lower than average by > 2% -> endurance
      expect(
        ProgressCalcs.classifyBalanceIndex(bi: 45.0, avgBi: avgBi),
        equals(BalanceIndexLeaning.endurance),
      );

      // Within 2% -> balanced
      expect(
        ProgressCalcs.classifyBalanceIndex(bi: 60.5, avgBi: avgBi),
        equals(BalanceIndexLeaning.balanced),
      );

      // Null or <= 0 avgBi -> unclassified (single test)
      expect(
        ProgressCalcs.classifyBalanceIndex(bi: 60.0, avgBi: null),
        equals(BalanceIndexLeaning.unclassified),
      );
      expect(
        ProgressCalcs.classifyBalanceIndex(bi: 60.0, avgBi: 0.0),
        equals(BalanceIndexLeaning.unclassified),
      );
    });
  });

  group('Recovery Math Tests (Progress Batch 4)', () {
    test('isRhrElevated alerts when today RHR is 5+ bpm above MA7', () {
      // Exactly 5 bpm higher
      expect(
        ProgressCalcs.isRhrElevated(todayRhr: 65.0, ma7Rhr: 60.0),
        isTrue,
      );

      // 6 bpm higher
      expect(
        ProgressCalcs.isRhrElevated(todayRhr: 66.0, ma7Rhr: 60.0),
        isTrue,
      );

      // 4 bpm higher -> not elevated
      expect(
        ProgressCalcs.isRhrElevated(todayRhr: 64.0, ma7Rhr: 60.0),
        isFalse,
      );

      // Lower or equal -> not elevated
      expect(
        ProgressCalcs.isRhrElevated(todayRhr: 58.0, ma7Rhr: 60.0),
        isFalse,
      );

      // Null values return false
      expect(
        ProgressCalcs.isRhrElevated(todayRhr: null, ma7Rhr: 60.0),
        isFalse,
      );
      expect(
        ProgressCalcs.isRhrElevated(todayRhr: 65.0, ma7Rhr: null),
        isFalse,
      );
    });

    test('calcHrvSwcBand calculates MA7 +- 0.5 * stdDev', () {
      final baseDate = DateTime(2026, 11, 20);
      final points = [
        DateValuePoint(date: DateTime(2026, 11, 15), value: 60.0),
        DateValuePoint(date: DateTime(2026, 11, 16), value: 70.0),
        DateValuePoint(date: DateTime(2026, 11, 17), value: 80.0),
        DateValuePoint(date: DateTime(2026, 11, 18), value: 70.0),
      ];
      // Values: [60, 70, 80, 70], mean = 70.0, sample std dev = sqrt(((100 + 0 + 100 + 0) / 3)) = sqrt(66.67) = 8.165
      // 0.5 * stdDev = 4.08
      // If MA7 = 72.0: upper = 72.0 + 4.08 = 76.1, lower = 72.0 - 4.08 = 67.9

      final swc = ProgressCalcs.calcHrvSwcBand(
        targetDate: baseDate,
        hrvPoints: points,
        ma7Value: 72.0,
      );

      expect(swc.upper, isNotNull);
      expect(swc.lower, isNotNull);
      expect(swc.stdDev, closeTo(8.2, 0.2));
      expect(swc.upper!, closeTo(76.1, 0.3));
      expect(swc.lower!, closeTo(67.9, 0.3));
    });

    test('calcHrvSwcBand returns null when MA7 is null or points < 3', () {
      final baseDate = DateTime(2026, 11, 20);
      final twoPoints = [
        DateValuePoint(date: DateTime(2026, 11, 15), value: 60.0),
        DateValuePoint(date: DateTime(2026, 11, 16), value: 70.0),
      ];

      expect(
        ProgressCalcs.calcHrvSwcBand(
          targetDate: baseDate,
          hrvPoints: twoPoints,
          ma7Value: 65.0,
        ).upper,
        isNull,
      );

      expect(
        ProgressCalcs.calcHrvSwcBand(
          targetDate: baseDate,
          hrvPoints: twoPoints,
          ma7Value: null,
        ).upper,
        isNull,
      );
    });
  });

  group('Eupnea Baseline Tests (Progress Batch 4)', () {
    test('computeBaseline for eupnea series with lower is better', () {
      final workouts = [
        {'date': '2026-11-01', 'eupnea_1': 45.0},
        {'date': '2026-11-03', 'eupnea_1': 44.5},
        {'date': '2026-11-05', 'eupnea_1': 45.2},
      ];

      final baseline = ProgressCalcs.computeBaseline(
        workouts: workouts,
        metricKey: 'eupnea_1',
      );

      expect(baseline.hasEnoughData, isTrue);
      expect(baseline.currentBaseline, isNotNull);
      expect(baseline.currentBaseline!, closeTo(44.9, 0.2));
    });
  });
}
