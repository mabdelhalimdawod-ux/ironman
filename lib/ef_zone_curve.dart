import 'dart:math';
import 'package:flutter/material.dart';
import 'app_strings.dart';
import 'engine_rowing_ui.dart';
import 'workout_metric_curve_view.dart';

/// منحنى معامل الكفاءة (EF) لكل تمرينة — سياسة «كل تمرينة = نقطة»
/// - يعرض قيمة EF لكل تمرينة فعلية في الفترة المختارة (بدون متوسط أسبوعي أو MA7)
/// - عدة تمرينات في نفس اليوم: يمر الخط بأعلى EF في اليوم وتظهر البقية باهتة بدون خط
/// - يفصل كل منطقة تدريب بخط مستقل بلونها أو يركّز على منطقة واحدة مع خط الأساس
class EfZoneCurveWidget extends StatelessWidget {
  final List<Map<String, Object?>> workouts;
  final DateTime periodStart;
  final DateTime periodEnd;
  final String athleteName;
  final int playerId;
  final Map<int, List<Map<String, Object?>>>? multiAthleteWorkouts;
  final Map<int, String>? athleteNames;
  final Map<int, Color>? athleteColors;

  const EfZoneCurveWidget({
    super.key,
    required this.workouts,
    required this.periodStart,
    required this.periodEnd,
    required this.athleteName,
    required this.playerId,
    this.multiAthleteWorkouts,
    this.athleteNames,
    this.athleteColors,
  });

  /// استخراج معامل الكفاءة (EF = avg_power / hr) للتمرينة الواحدة
  static double? extractEf(Map<String, Object?> w) {
    final storedEf = (w['ef'] as num?)?.toDouble();
    if (storedEf != null && storedEf > 0) return storedEf;

    final p = (w['avg_power'] as num?)?.toDouble();
    final hr =
        (w['hr'] as num?)?.toDouble() ?? (w['avg_hr'] as num?)?.toDouble();
    if (p != null && p > 0 && hr != null && hr > 0) {
      return p / hr;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    return WorkoutMetricCurveView(
      title: s.efPerWorkoutTitle,
      icon: Icons.bolt_rounded,
      onInfoTap: () => _showEfInfoDialog(context, s),
      workouts: workouts,
      periodStart: periodStart,
      periodEnd: periodEnd,
      athleteName: athleteName,
      playerId: playerId,
      multiAthleteWorkouts: multiAthleteWorkouts,
      athleteNames: athleteNames,
      athleteColors: athleteColors,
      extractValue: extractEf,
      higherIsBetter: true,
      baselineMetricKey: 'ef',
      yUnitLabel: 'EF (W/bpm)',
      formatYValue: (v) => v.toStringAsFixed(2),
      formatTooltipValue: (v) => 'EF: ${v.toStringAsFixed(2)}',
      computeMinY: (dMin, dMax) => max(0.0, dMin - 0.15),
      computeMaxY: (dMin, dMax) => dMax + 0.15,
      availableChipLabels: [s.chipEF, s.chipWatts, s.chipHR, s.chipZone],
    );
  }

  void _showEfInfoDialog(BuildContext context, AppStrings s) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: EngineRowingUI.cardFill,
        title: Row(
          children: [
            const Icon(Icons.bolt_rounded, color: EngineRowingUI.neonLime),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                s.efTitle,
                style: const TextStyle(
                  color: EngineRowingUI.textWhite,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        content: Text(
          s.efExplanation,
          style: const TextStyle(
            color: EngineRowingUI.labelSlate,
            fontSize: 13,
            height: 1.45,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              s.close,
              style: const TextStyle(
                color: EngineRowingUI.neonLime,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
