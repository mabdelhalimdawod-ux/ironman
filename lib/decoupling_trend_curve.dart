import 'dart:math';
import 'package:flutter/material.dart';
import 'app_strings.dart';
import 'decoupling_curve.dart';
import 'engine_rowing_ui.dart';
import 'heart_rate_zones.dart';
import 'progress_calcs.dart';
import 'workout_kinds.dart';
import 'workout_metric_curve_view.dart';

/// منحنى التفكك القلبي % لكل تمرينة — سياسة «كل تمرينة = نقطة»
/// - يعرض نسبة التفكك القلبي لكل تمرينة فعلية في الفترة المختارة (أفضل تمرينة في اليوم = أقل نسبة تفكك)
/// - عدة تمرينات في نفس اليوم ونفس المنطقة: يمر الخط بأقل نسبة تفكك وتظهر البقية باهتة بدون خط
/// - بدون أي متوسط متحرك (MA7) أو تجميع أسبوعي أو نصوص EF خاطئة
/// - الضغط على أي نقطة يعرض منحنى قراءات التمرينة المفصل بالأسفل عند توفر القراءات
class DecouplingTrendCurveWidget extends StatefulWidget {
  final List<Map<String, Object?>> workouts;
  final DateTime periodStart;
  final DateTime periodEnd;
  final String athleteName;
  final int playerId;
  final Map<int, List<Map<String, Object?>>>? multiAthleteWorkouts;
  final Map<int, String>? athleteNames;
  final Map<int, Color>? athleteColors;

  const DecouplingTrendCurveWidget({
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

  /// استخراج نسبة التفكك القلبي (%) للتمرينة سواء كانت مخزنة كرقم أو كنص قراءات
  static double? extractDecoupling(Map<String, Object?> w) {
    final pct = (w['decoupling_pct'] as num?)?.toDouble();
    if (pct != null && pct.isFinite) return pct;

    final raw = w['decoupling'];
    if (raw == null) return null;
    if (raw is num) return raw.toDouble();
    if (raw is String) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty) return null;
      final parsedNum = double.tryParse(trimmed);
      if (parsedNum != null) return parsedNum;

      final dur = (w['duration_minutes'] as num?)?.toDouble() ??
          (w['duration'] as num?)?.toDouble() ??
          (((w['duration_seconds'] as num?)?.toDouble() ?? 0.0) / 60.0);
      final calc = ProgressCalcs.calculateDecoupling(
        rawReadingsText: trimmed,
        durationMinutes: dur,
        zoneKey: w['zone'] as String?,
      );
      return calc.decouplingPercent;
    }
    return null;
  }

  @override
  State<DecouplingTrendCurveWidget> createState() =>
      _DecouplingTrendCurveWidgetState();
}

class _DecouplingTrendCurveWidgetState
    extends State<DecouplingTrendCurveWidget> {
  Map<String, Object?>? _selectedWorkout;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    return WorkoutMetricCurveView(
      title: s.decouplingPerWorkoutTitle,
      icon: Icons.trending_down_rounded,
      onInfoTap: () => _showDecouplingInfoDialog(context, s),
      workouts: widget.workouts,
      periodStart: widget.periodStart,
      periodEnd: widget.periodEnd,
      athleteName: widget.athleteName,
      playerId: widget.playerId,
      multiAthleteWorkouts: widget.multiAthleteWorkouts,
      athleteNames: widget.athleteNames,
      athleteColors: widget.athleteColors,
      extractValue: DecouplingTrendCurveWidget.extractDecoupling,
      higherIsBetter: false, // الأقل تفككاً هو الأفضل
      baselineMetricKey: 'decoupling',
      yUnitLabel: '${s.decouplingPerWorkoutTitle} (%)',
      formatYValue: (v) => '${v.toStringAsFixed(1)}%',
      formatTooltipValue: (v) => '${v.toStringAsFixed(1)}%',
      computeMinY: (dMin, dMax) => min(0.0, (dMin - 2.0).floorToDouble()),
      computeMaxY: (dMin, dMax) => max(10.0, (dMax + 2.0).ceilToDouble()),
      availableChipLabels: [s.chipDecoupling, s.chipWatts, s.chipHR, s.chipTime],
      onPointTap: (pt) {
        setState(() {
          _selectedWorkout = pt.rawRow;
        });
      },
      onFilterChanged: (kind, zone) {
        if (_selectedWorkout != null) {
          setState(() => _selectedWorkout = null);
        }
      },
      extraBottomBuilder: (ctx, strings, selectedKind, focusedZone) =>
          _buildSpecificWorkoutSection(ctx, strings, selectedKind, focusedZone),
    );
  }

  Widget? _buildSpecificWorkoutSection(
    BuildContext context,
    AppStrings s,
    String selectedKind,
    String? focusedZone,
  ) {
    final pStart = DateTime(
        widget.periodStart.year, widget.periodStart.month, widget.periodStart.day);
    final pEnd = DateTime(
        widget.periodEnd.year, widget.periodEnd.month, widget.periodEnd.day);
    final normFocus =
        focusedZone != null ? HeartRateZones.normalizeZoneKey(focusedZone) : null;

    final workoutsWithReadings = widget.workouts.where((w) {
      final rawKind =
          ((w['kind'] as String?) ?? (w['session_kind'] as String?) ?? '')
              .trim();
      final matchesKind = rawKind.isEmpty
          ? selectedKind == 'Erg'
          : (WorkoutKinds.isPerformanceKind(rawKind) &&
              WorkoutKinds.matchesKind(rawKind, selectedKind));
      if (!matchesKind) return false;

      final d = ProgressCalcs.parseDate((w['date'] as String?) ?? '');
      if (d == null) return false;
      final dOnly = DateTime(d.year, d.month, d.day);
      if (dOnly.isBefore(pStart) || dOnly.isAfter(pEnd)) return false;

      if (normFocus != null) {
        final wz = HeartRateZones.normalizeZoneKey((w['zone'] as String?) ?? '');
        if (wz != normFocus) return false;
      }

      final dec = w['decoupling'];
      return dec is String && dec.contains('-');
    }).toList();

    if (workoutsWithReadings.isEmpty) {
      return null;
    }

    final currentWorkout = workoutsWithReadings.contains(_selectedWorkout)
        ? _selectedWorkout!
        : workoutsWithReadings.last;
    final readingsText = (currentWorkout['decoupling'] as String?) ?? '';
    final dur = (currentWorkout['duration_minutes'] as num?)?.toDouble() ??
        (currentWorkout['duration'] as num?)?.toDouble() ??
        60.0;
    final wDate = (currentWorkout['date'] as String?) ?? '';
    final wZone = (currentWorkout['zone'] as String?) ?? focusedZone;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: EngineRowingUI.equationCardFill,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: EngineRowingUI.bgGridLine),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<Map<String, Object?>>(
                    value: currentWorkout,
                    isExpanded: true,
                    dropdownColor: EngineRowingUI.cardFill,
                    style: const TextStyle(
                      color: EngineRowingUI.textWhite,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                    items: workoutsWithReadings.map((w) {
                      final dStr = (w['date'] as String?) ?? '';
                      final zStr = HeartRateZones.zoneDisplayName(
                        (w['zone'] as String?) ?? '',
                        isArabic: s.isArabic,
                      );
                      return DropdownMenuItem<Map<String, Object?>>(
                        value: w,
                        child: Text(
                          '$dStr · $zStr',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12),
                        ),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setState(() => _selectedWorkout = val);
                      }
                    },
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          WorkoutDecouplingCurve(
            rawReadingsText: readingsText,
            durationMinutes: dur,
            zoneKey: wZone,
            workoutDate: wDate,
            athleteName: widget.athleteName,
          ),
        ],
      ),
    );
  }

  void _showDecouplingInfoDialog(BuildContext context, AppStrings s) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: EngineRowingUI.cardFill,
        title: Row(
          children: [
            const Icon(Icons.trending_down_rounded,
                color: EngineRowingUI.neonLime),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                s.decouplingPerWorkoutTitle,
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
          s.decouplingExplanation,
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
