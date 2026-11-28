import 'dart:math';
import 'package:flutter/material.dart';
import 'app_strings.dart';
import 'engine_rowing_ui.dart';
import 'progress_calcs.dart';
import 'workout_metric_curve_view.dart';

/// منحنى الواط الديناميكي (Dynamic Watt Curve) — سياسة «كل تمرينة = نقطة»
/// - يعرض نقطة واحدة لكل تمرينة في الفترة المختارة على التواريخ الفعلية فقط
/// - في حال تكرار تمرينات نفس اليوم ونفس المنطقة: يمر الخط بأعلى واط في اليوم وتظهر البقية باهتة
/// - بدون أي متوسط متحرك (MA7) أو تجميع أسبوعي
class DynamicWattsCurveWidget extends StatelessWidget {
  final List<Map<String, Object?>> workouts;
  final DateTime periodStart;
  final DateTime periodEnd;
  final String athleteName;
  final int playerId;
  final Map<int, List<Map<String, Object?>>>? multiAthleteWorkouts;
  final Map<int, String>? athleteNames;
  final Map<int, Color>? athleteColors;

  const DynamicWattsCurveWidget({
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

  /// استخراج قيمة الواط من avg_power أو حسابها من split_500 عند غيابه
  static double? extractWatts(Map<String, Object?> w) {
    final p = (w['avg_power'] as num?)?.toDouble();
    if (p != null && p > 0) return p;

    final split =
        (w['split_500'] as num?)?.toDouble() ?? (w['split'] as num?)?.toDouble();
    if (split != null && split > 0) {
      return ProgressCalcs.wattsFromSplit(split);
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    return WorkoutMetricCurveView(
      title: s.dynamicWattsTitle,
      icon: Icons.flash_on_rounded,
      onInfoTap: () => _showWattsInfoDialog(context, s),
      workouts: workouts,
      periodStart: periodStart,
      periodEnd: periodEnd,
      athleteName: athleteName,
      playerId: playerId,
      multiAthleteWorkouts: multiAthleteWorkouts,
      athleteNames: athleteNames,
      athleteColors: athleteColors,
      extractValue: extractWatts,
      higherIsBetter: true,
      baselineMetricKey: 'watts',
      yUnitLabel: s.chipWatts,
      formatYValue: (v) => '${v.round()} W',
      formatTooltipValue: (v) => '${v.toStringAsFixed(0)} W',
      computeMinY: (dMin, dMax) => max(0.0, (dMin - 20).floorToDouble()),
      computeMaxY: (dMin, dMax) => (dMax + 25).ceilToDouble(),
      availableChipLabels: [s.chipWatts, s.chipSplit, s.chipHR, s.chipZone],
    );
  }

  void _showWattsInfoDialog(BuildContext context, AppStrings s) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: EngineRowingUI.cardFill,
        title: Row(
          children: [
            const Icon(Icons.flash_on_rounded, color: EngineRowingUI.neonLime),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                s.dynamicWattsTitle,
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
          s.wattsCurveDesc,
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
