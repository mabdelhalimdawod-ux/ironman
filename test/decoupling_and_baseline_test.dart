import 'package:flutter_test/flutter_test.dart';
import 'package:rowing_app/progress_calcs.dart';

void main() {
  group('Decoupling Readings Parsing & Calculation Tests', () {
    test('1. parseDecouplingReadings parses valid W-HR-T format case-insensitively', () {
      const raw = 'W200-HR140-T5, w205-hr142-t10, W210-HR145-T15';
      final res = ProgressCalcs.parseDecouplingReadings(raw);

      expect(res.ignoredCount, 0);
      expect(res.readings.length, 3);

      expect(res.readings[0].watts, 200.0);
      expect(res.readings[0].hr, 140.0);
      expect(res.readings[0].timeMinutes, 5.0);
      expect(res.readings[0].ef, closeTo(200.0 / 140.0, 0.001));

      expect(res.readings[1].watts, 205.0);
      expect(res.readings[1].hr, 142.0);
      expect(res.readings[1].timeMinutes, 10.0);

      expect(res.readings[2].watts, 210.0);
      expect(res.readings[2].hr, 145.0);
      expect(res.readings[2].timeMinutes, 15.0);
    });

    test('2. parseDecouplingReadings ignores invalid or incomplete readings and counts them', () {
      const raw = 'W200-HR140-T5, W200-HR140, HR150-T10, W200-T15, random_text, W210-HR145-T20';
      final res = ProgressCalcs.parseDecouplingReadings(raw);

      expect(res.readings.length, 2);
      expect(res.ignoredCount, 4);
      expect(res.readings[0].timeMinutes, 5.0);
      expect(res.readings[1].timeMinutes, 20.0);
    });

    test('3. calculateDecoupling splits by actual time T <= D/2 and T > D/2', () {
      // 60 minutes workout, D/2 = 30
      // Half 1: T=10, T=20 -> avgW=200, avgHr=140 -> EF1 = 200/140 = 1.42857
      // Half 2: T=40, T=50 -> avgW=200, avgHr=147 -> EF2 = 200/147 = 1.36054
      // Decoupling = ((1.42857 - 1.36054) / 1.42857) * 100 = 4.76% (Excellent, < 5%)
      const raw = 'W200-HR140-T10, W200-HR140-T20, W200-HR147-T40, W200-HR147-T50';
      final result = ProgressCalcs.calculateDecoupling(
        rawReadingsText: raw,
        durationMinutes: 60.0,
        zoneKey: 'Z2',
      );

      expect(result.hasEnoughReadings, isTrue);
      expect(result.half1Readings.length, 2);
      expect(result.half2Readings.length, 2);
      expect(result.efHalf1, closeTo(1.42857, 0.001));
      expect(result.efHalf2, closeTo(1.36054, 0.001));
      expect(result.decouplingPercent, closeTo(4.76, 0.05));
      expect(result.isEligibleForInterpretation, isTrue);
      expect(result.controlLevel, DecouplingControlLevel.excellent);
    });

    test('4. calculateDecoupling handles edge cases: empty half, not enough readings', () {
      // Only readings in first half
      const rawOnlyHalf1 = 'W200-HR140-T5, W200-HR140-T10';
      final res1 = ProgressCalcs.calculateDecoupling(
        rawReadingsText: rawOnlyHalf1,
        durationMinutes: 60.0,
        zoneKey: 'Z2',
      );

      expect(res1.hasEnoughReadings, isFalse);
      expect(res1.decouplingPercent, isNull);
      expect(res1.errorMessage, isNotNull);

      // Empty string
      final resEmpty = ProgressCalcs.calculateDecoupling(
        rawReadingsText: '',
        durationMinutes: 60.0,
        zoneKey: 'Z2',
      );
      expect(resEmpty.hasEnoughReadings, isFalse);
      expect(resEmpty.decouplingPercent, isNull);
    });

    test('5. calculateDecoupling interpretation rules: moderate (5-10%), high (>10%), not eligible', () {
      // Moderate decoupling (7%)
      // EF1 = 200/140 = 1.42857
      // EF2 = 200/150.54 = 1.32857 -> (1.42857 - 1.32857)/1.42857 * 100 = 7.0%
      const rawModerate = 'W200-HR140-T10, W200-HR150.54-T50';
      final resMod = ProgressCalcs.calculateDecoupling(
        rawReadingsText: rawModerate,
        durationMinutes: 60.0,
        zoneKey: 'Z2',
      );
      expect(resMod.hasEnoughReadings, isTrue);
      expect(resMod.controlLevel, DecouplingControlLevel.moderate);

      // High decoupling (>10%)
      const rawHigh = 'W200-HR130-T10, W200-HR160-T50';
      final resHigh = ProgressCalcs.calculateDecoupling(
        rawReadingsText: rawHigh,
        durationMinutes: 60.0,
        zoneKey: 'Z1',
      );
      expect(resHigh.hasEnoughReadings, isTrue);
      expect(resHigh.controlLevel, DecouplingControlLevel.high);

      // Not eligible: Zone 4 (not Z1 or Z2)
      final resZ4 = ProgressCalcs.calculateDecoupling(
        rawReadingsText: rawModerate,
        durationMinutes: 60.0,
        zoneKey: 'Z4',
      );
      expect(resZ4.isEligibleForInterpretation, isFalse);
      expect(resZ4.controlLevel, DecouplingControlLevel.notEligible);

      // Not eligible: Duration < 60 min (e.g. 40 min)
      final resShort = ProgressCalcs.calculateDecoupling(
        rawReadingsText: 'W200-HR140-T10, W200-HR145-T30',
        durationMinutes: 40.0,
        zoneKey: 'Z2',
      );
      expect(resShort.isEligibleForInterpretation, isFalse);
      expect(resShort.controlLevel, DecouplingControlLevel.notEligible);
    });
  });

  group('computeBaseline Unit Tests (Coach Rules)', () {
    test('1. Fewer than 3 workouts yields no baseline', () {
      final workouts = [
        {'date': '2026-11-01', 'avg_power': 200.0},
        {'date': '2026-11-03', 'avg_power': 202.0},
      ];

      final res = ProgressCalcs.computeBaseline(
        workouts: workouts,
        metricKey: 'watts',
      );

      expect(res.hasEnoughData, isFalse);
      expect(res.currentBaseline, isNull);
      expect(res.startOfPeriodBaseline, isNull);
    });

    test('2. Three close workouts (spread <= 3%) creates first baseline', () {
      final workouts = [
        {'date': '2026-11-01', 'avg_power': 200.0},
        {'date': '2026-11-03', 'avg_power': 202.0},
        {'date': '2026-11-05', 'avg_power': 201.0},
      ];

      final res = ProgressCalcs.computeBaseline(
        workouts: workouts,
        metricKey: 'watts',
      );

      expect(res.hasEnoughData, isTrue);
      expect(res.currentBaseline, closeTo(201.0, 0.01));
      expect(res.historyPoints.length, 1);
    });

    test('3. Three divergent workouts expand window up to 5 to find convergence', () {
      // 1: 180, 2: 220, 3: 200 -> not close (220 - 180 = 40 > 200*0.03 = 6)
      // 4: 201, 5: 200 -> workouts [200, 201, 200] in window of 3 are close!
      final workouts = [
        {'date': '2026-11-01', 'avg_power': 180.0},
        {'date': '2026-11-03', 'avg_power': 220.0},
        {'date': '2026-11-05', 'avg_power': 200.0},
        {'date': '2026-11-07', 'avg_power': 201.0},
        {'date': '2026-11-09', 'avg_power': 200.0},
      ];

      final res = ProgressCalcs.computeBaseline(
        workouts: workouts,
        metricKey: 'watts',
      );

      expect(res.hasEnoughData, isTrue);
      expect(res.currentBaseline, closeTo(200.33, 0.5));
    });

    test('4. Steady rise moves baseline UP; steady fall moves baseline DOWN', () {
      // Initial baseline ~ 200
      final workouts = [
        {'date': '2026-11-01', 'avg_power': 200.0},
        {'date': '2026-11-03', 'avg_power': 201.0},
        {'date': '2026-11-05', 'avg_power': 200.0},
        // Step up to ~215 (diff > 1%)
        {'date': '2026-11-10', 'avg_power': 214.0},
        {'date': '2026-11-12', 'avg_power': 215.0},
        {'date': '2026-11-14', 'avg_power': 216.0},
      ];

      final res = ProgressCalcs.computeBaseline(
        workouts: workouts,
        metricKey: 'watts',
      );

      expect(res.hasEnoughData, isTrue);
      expect(res.currentBaseline, closeTo(215.0, 0.5));
      expect(res.historyPoints.length, 2); // original + step up
    });

    test('5. Single outlier does NOT move the baseline', () {
      final workouts = [
        {'date': '2026-11-01', 'avg_power': 200.0},
        {'date': '2026-11-03', 'avg_power': 201.0},
        {'date': '2026-11-05', 'avg_power': 200.0},
        // Single anomalous spike
        {'date': '2026-11-10', 'avg_power': 260.0},
        // Back to normal
        {'date': '2026-11-12', 'avg_power': 201.0},
        {'date': '2026-11-14', 'avg_power': 200.0},
      ];

      final res = ProgressCalcs.computeBaseline(
        workouts: workouts,
        metricKey: 'watts',
      );

      // Baseline should remain around 200
      expect(res.currentBaseline, closeTo(200.5, 1.0));
      // Outlier did not cause a step change
      expect(res.currentBaseline, isNot(closeTo(260.0, 10.0)));
    });

    test('6. Comparison with start of period baseline uses workouts strictly before period', () {
      final workouts = [
        // Before period (period starts 2026-11-15)
        {'date': '2026-11-01', 'avg_power': 200.0},
        {'date': '2026-11-03', 'avg_power': 201.0},
        {'date': '2026-11-05', 'avg_power': 200.0},
        // Inside period
        {'date': '2026-11-16', 'avg_power': 215.0},
        {'date': '2026-11-18', 'avg_power': 216.0},
        {'date': '2026-11-20', 'avg_power': 215.0},
      ];

      final res = ProgressCalcs.computeBaseline(
        workouts: workouts,
        metricKey: 'watts',
        periodStartDate: DateTime(2026, 11, 15),
      );

      expect(res.hasEnoughData, isTrue);
      // Start of period baseline was established before Nov 15 ~ 200.33
      expect(res.startOfPeriodBaseline, closeTo(200.33, 0.5));
      // Current baseline inside period moved up to ~ 215.33
      expect(res.currentBaseline, closeTo(215.33, 0.5));
    });
  });
}
