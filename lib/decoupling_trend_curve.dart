import 'dart:math';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'app_strings.dart';
import 'engine_rowing_ui.dart';
import 'heart_rate_zones.dart';
import 'progress_calcs.dart';
import 'progress_panel.dart';
import 'decoupling_curve.dart';

/// ويدجت قسم ومنحنى التفكك القلبي الهوائي (Decoupling Trend Curve)
/// - اختيار نوع تمرين واحد + منطقة تدريبية واحدة (بدون افتراضي مخترع)
/// - منحنى خط ناعم (isCurved) لنسب التفكك عبر التاريخ
/// - خط أساس منقط (step) لـ Decoupling في تلك المنطقة
/// - قائمة التمارين المتاحة بالأسفل لمعاينة تفاصيل التمرين بـ WorkoutDecouplingCurve
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

  @override
  State<DecouplingTrendCurveWidget> createState() =>
      _DecouplingTrendCurveWidgetState();
}

class _DecouplingTrendCurveWidgetState extends State<DecouplingTrendCurveWidget> {
  late String _selectedKind;
  String? _selectedZone; // لا يوجد افتراضي مخترع
  Map<String, Object?>? _selectedWorkout;

  @override
  void initState() {
    super.initState();
    _selectedKind = _computeMostFrequentKind();
  }

  @override
  void didUpdateWidget(covariant DecouplingTrendCurveWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    final available = _availableKinds;
    if (!available.contains(_selectedKind)) {
      _selectedKind = _computeMostFrequentKind();
    }
  }

  bool get _isMultiAthlete =>
      widget.multiAthleteWorkouts != null &&
      widget.multiAthleteWorkouts!.length > 1;

  List<String> get _availableKinds {
    final kinds = <String>{};
    for (final w in widget.workouts) {
      final k = (w['kind'] as String?)?.trim();
      if (k != null && k.isNotEmpty) kinds.add(k);
    }
    if (widget.multiAthleteWorkouts != null) {
      for (final list in widget.multiAthleteWorkouts!.values) {
        for (final w in list) {
          final k = (w['kind'] as String?)?.trim();
          if (k != null && k.isNotEmpty) kinds.add(k);
        }
      }
    }
    if (kinds.isEmpty) kinds.add('Erg');
    final sorted = kinds.toList()..sort();
    return sorted;
  }

  String _computeMostFrequentKind() {
    final counts = <String, int>{};
    for (final w in widget.workouts) {
      final k = (w['kind'] as String?)?.trim();
      if (k != null && k.isNotEmpty) {
        counts[k] = (counts[k] ?? 0) + 1;
      }
    }
    if (counts.isEmpty) return 'Erg';
    var maxK = 'Erg';
    var maxC = -1;
    counts.forEach((k, c) {
      if (c > maxC) {
        maxC = c;
        maxK = k;
      }
    });
    return maxK;
  }

  /// استخراج قيمة Decoupling للتمرين سواء كانت مخزنة كرقم أو كنص قراءات
  double? _extractDecouplingValue(Map<String, Object?> w) {
    final raw = w['decoupling'];
    if (raw == null) return null;
    if (raw is num) return raw.toDouble();
    if (raw is String) {
      final parsedNum = double.tryParse(raw.trim());
      if (parsedNum != null) return parsedNum;
      // تحليل نص القراءات
      final dur = (w['duration_minutes'] as num?)?.toDouble() ??
          (w['duration'] as num?)?.toDouble() ??
          0.0;
      final calc = ProgressCalcs.calculateDecoupling(
        rawReadingsText: raw,
        durationMinutes: dur,
        zoneKey: (w['zone'] as String?),
      );
      return calc.decouplingPercent;
    }
    return null;
  }

  List<Map<String, Object?>> _getFilteredWorkouts(
      List<Map<String, Object?>> source) {
    if (_selectedZone == null) return [];
    final cleanZone = HeartRateZones.normalizeZoneKey(_selectedZone!);

    return source.where((w) {
      final k = (w['kind'] as String?)?.trim();
      if (k != _selectedKind) return false;

      final rawZone = (w['zone'] as String?) ?? '';
      final z = HeartRateZones.normalizeZoneKey(rawZone);
      if (z != cleanZone) return false;

      final val = _extractDecouplingValue(w);
      return val != null;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ProgressPanel(
          title: s.workoutDecouplingTrendTitle,
          leading: const Icon(Icons.trending_down_rounded,
              color: EngineRowingUI.neonLime, size: 20),
          trailing: IconButton(
            icon: const Icon(Icons.info_outline_rounded,
                color: EngineRowingUI.neonLime, size: 18),
            onPressed: () => _showDecouplingInfoDialog(context, s),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── شريط الاختيار: نوع التمرين + المنطقة التدريبية ──
              _buildSelectorsBar(context, s),
              const SizedBox(height: 14),

              // ── رسم المنحنى أو رسالة المطالبة بالاختيار ──
              if (_selectedZone == null)
                _buildPromptSelectZone(context, s)
              else
                _buildTrendChart(context, s),

              const SizedBox(height: 10),

              // ── نص منحنى تقديري فقط ──
              Center(
                child: Text(
                  s.estimatedCurveNotice,
                  style: const TextStyle(
                    fontSize: 11,
                    color: EngineRowingUI.captionGrey,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
              const SizedBox(height: 8),

              // ── صف أسماء المدخلات ──
              _buildInputChipsRow(context, s),
            ],
          ),
        ),

        // ── قسم تفاصيل تمرين محدد من القائمة ──
        if (_selectedZone != null) _buildSpecificWorkoutSection(context, s),
      ],
    );
  }

  Widget _buildSelectorsBar(BuildContext context, AppStrings s) {
    final kinds = _availableKinds;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 340;

        Widget buildKindDropdown() {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
            decoration: BoxDecoration(
              color: EngineRowingUI.equationCardFill,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: EngineRowingUI.bgGridLine),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value:
                    kinds.contains(_selectedKind) ? _selectedKind : kinds.first,
                dropdownColor: EngineRowingUI.bgNavy,
                isDense: true,
                isExpanded: true,
                icon: const Icon(Icons.arrow_drop_down,
                    color: EngineRowingUI.neonLime),
                items: kinds.map((k) {
                  return DropdownMenuItem<String>(
                    value: k,
                    child: Text(
                      k,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: EngineRowingUI.textWhite,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  );
                }).toList(),
                onChanged: (val) {
                  if (val != null) setState(() => _selectedKind = val);
                },
              ),
            ),
          );
        }

        Widget buildZoneDropdown() {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
            decoration: BoxDecoration(
              color: EngineRowingUI.equationCardFill,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: _selectedZone != null
                    ? HeartRateZones.zoneColor(_selectedZone!)
                    : EngineRowingUI.bgGridLine,
              ),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String?>(
                value: _selectedZone,
                hint: Text(
                  s.selectZonePrompt,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: EngineRowingUI.captionGrey,
                    fontSize: 12,
                  ),
                ),
                dropdownColor: EngineRowingUI.bgNavy,
                isDense: true,
                isExpanded: true,
                icon: const Icon(Icons.arrow_drop_down,
                    color: EngineRowingUI.neonLime),
                items: [
                  ...HeartRateZones.orderedZones.map((z) {
                    return DropdownMenuItem<String?>(
                      value: z,
                      child: Text(
                        HeartRateZones.zoneDisplayName(z, isArabic: s.isArabic),
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: HeartRateZones.zoneColor(z),
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    );
                  }),
                ],
                onChanged: (val) {
                  setState(() => _selectedZone = val);
                },
              ),
            ),
          );
        }

        if (isCompact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '${s.selectWorkoutTypePrompt}:',
                style: const TextStyle(
                  fontSize: 12,
                  color: EngineRowingUI.labelSlate,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              buildKindDropdown(),
              const SizedBox(height: 10),
              Text(
                '${s.selectZonePrompt}:',
                style: const TextStyle(
                  fontSize: 12,
                  color: EngineRowingUI.labelSlate,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              buildZoneDropdown(),
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  '${s.selectWorkoutTypePrompt}:',
                  style: const TextStyle(
                    fontSize: 12,
                    color: EngineRowingUI.labelSlate,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(child: buildKindDropdown()),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  '${s.selectZonePrompt}:',
                  style: const TextStyle(
                    fontSize: 12,
                    color: EngineRowingUI.labelSlate,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(child: buildZoneDropdown()),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _buildPromptSelectZone(BuildContext context, AppStrings s) {
    return Container(
      height: 180,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: EngineRowingUI.bgNavy.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: EngineRowingUI.bgGridLine),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.touch_app_rounded,
              color: EngineRowingUI.neonLime, size: 28),
          const SizedBox(height: 8),
          Text(
            s.selectZonePrompt,
            style: const TextStyle(
              color: EngineRowingUI.textWhite,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTrendChart(BuildContext context, AppStrings s) {
    final filtered = _getFilteredWorkouts(widget.workouts);
    final zoneColor = HeartRateZones.zoneColor(_selectedZone!);

    if (filtered.isEmpty && !_isMultiAthlete) {
      return Container(
        height: 200,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: EngineRowingUI.bgNavy.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: EngineRowingUI.bgGridLine),
        ),
        child: Text(
          s.notEnoughData,
          style: const TextStyle(
            color: EngineRowingUI.labelSlate,
            fontSize: 13,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
    }

    final startMs = widget.periodStart.millisecondsSinceEpoch.toDouble();
    const dayMs = 86400000.0;
    final bars = <LineChartBarData>[];
    final allSpots = <({double x, double y, String date, double duration})>[];

    if (_isMultiAthlete) {
      final multi = widget.multiAthleteWorkouts ?? {};
      multi.forEach((pid, list) {
        final aFiltered = _getFilteredWorkouts(list);
        if (aFiltered.isNotEmpty) {
          final aColor = widget.athleteColors?[pid] ?? EngineRowingUI.neonLime;
          final spots = aFiltered.map((w) {
            final dStr = (w['date'] as String?) ?? '';
            final d = DateTime.tryParse(dStr) ?? widget.periodStart;
            final x = (d.millisecondsSinceEpoch - startMs) / dayMs;
            final y = _extractDecouplingValue(w) ?? 0.0;
            final dur = (w['duration_minutes'] as num?)?.toDouble() ?? 0.0;
            allSpots.add((x: x, y: y, date: dStr, duration: dur));
            return FlSpot(x, y);
          }).toList();

          bars.add(
            LineChartBarData(
              spots: spots,
              isCurved: true,
              curveSmoothness: 0.35,
              color: aColor,
              barWidth: 2.2,
              dotData: FlDotData(
                show: true,
                getDotPainter: (spot, percent, barData, index) {
                  return FlDotCirclePainter(
                    radius: 4.0,
                    color: aColor,
                    strokeWidth: 1.5,
                    strokeColor: EngineRowingUI.bgNavy,
                  );
                },
              ),
            ),
          );
        }
      });
    } else {
      final spots = filtered.map((w) {
        final dStr = (w['date'] as String?) ?? '';
        final d = DateTime.tryParse(dStr) ?? widget.periodStart;
        final x = (d.millisecondsSinceEpoch - startMs) / dayMs;
        final y = _extractDecouplingValue(w) ?? 0.0;
        final dur = (w['duration_minutes'] as num?)?.toDouble() ?? 0.0;
        allSpots.add((x: x, y: y, date: dStr, duration: dur));
        return FlSpot(x, y);
      }).toList();

      bars.add(
        LineChartBarData(
          spots: spots,
          isCurved: true,
          curveSmoothness: 0.35,
          color: zoneColor,
          barWidth: 2.5,
          dotData: FlDotData(
            show: true,
            getDotPainter: (spot, percent, barData, index) {
              return FlDotCirclePainter(
                radius: 4.0,
                color: zoneColor,
                strokeWidth: 1.5,
                strokeColor: EngineRowingUI.bgNavy,
              );
            },
          ),
        ),
      );

      // خط أساس Decoupling المنقط (step)
      final baselineResult = ProgressCalcs.computeBaseline(
        workouts: widget.workouts.where((w) {
          final rz = (w['zone'] as String?) ?? '';
          final rk = (w['kind'] as String?) ?? '';
          return HeartRateZones.normalizeZoneKey(rz) ==
                  HeartRateZones.normalizeZoneKey(_selectedZone!) &&
              rk == _selectedKind;
        }).toList(),
        metricKey: 'decoupling',
        periodStartDate: widget.periodStart,
      );

      if (baselineResult.hasEnoughData &&
          baselineResult.currentBaseline != null &&
          allSpots.isNotEmpty) {
        final minX = allSpots.map((e) => e.x).reduce(min);
        final maxX = max(minX + 7, allSpots.map((e) => e.x).reduce(max));
        final baseSpots = [
          FlSpot(minX, baselineResult.currentBaseline!),
          FlSpot(maxX, baselineResult.currentBaseline!),
        ];
        bars.add(
          LineChartBarData(
            spots: baseSpots,
            isCurved: false,
            dashArray: [6, 4],
            color: zoneColor.withValues(alpha: 0.7),
            barWidth: 1.6,
            dotData: const FlDotData(show: false),
          ),
        );
      }
    }

    if (allSpots.isEmpty) {
      return Container(
        height: 200,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: EngineRowingUI.bgNavy.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: EngineRowingUI.bgGridLine),
        ),
        child: Text(
          s.notEnoughData,
          style: const TextStyle(
            color: EngineRowingUI.labelSlate,
            fontSize: 13,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
    }

    final minX = allSpots.map((e) => e.x).reduce(min);
    final maxX = max(minX + 7, allSpots.map((e) => e.x).reduce(max));
    final minY = max(0.0, allSpots.map((e) => e.y).reduce(min) * 0.85);
    final maxY = max(10.0, allSpots.map((e) => e.y).reduce(max) * 1.15);

    return SizedBox(
      height: 230,
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: LineChart(
          LineChartData(
            gridData: FlGridData(
              show: true,
              drawVerticalLine: true,
              getDrawingHorizontalLine: (_) => const FlLine(
                color: EngineRowingUI.bgGridLine,
                strokeWidth: 0.8,
              ),
              getDrawingVerticalLine: (_) => const FlLine(
                color: EngineRowingUI.bgGridLine,
                strokeWidth: 0.8,
              ),
            ),
            titlesData: FlTitlesData(
              topTitles:
                  const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles:
                  const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 22,
                  interval: max(7.0, (maxX - minX) / 5),
                  getTitlesWidget: (val, _) {
                    final d = DateTime.fromMillisecondsSinceEpoch(
                        (startMs + val * dayMs).round());
                    return Text(
                      '${d.day}/${d.month}',
                      style: const TextStyle(
                        fontSize: 10,
                        color: EngineRowingUI.captionGrey,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    );
                  },
                ),
              ),
              leftTitles: AxisTitles(
                axisNameWidget: const Text(
                  'Decoupling %',
                  style: TextStyle(
                      fontSize: 10, color: EngineRowingUI.labelSlate),
                ),
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 32,
                  interval: max(2.0, (maxY - minY) / 4),
                  getTitlesWidget: (val, _) => Text(
                    '${val.round()}%',
                    style: const TextStyle(
                      fontSize: 10,
                      color: EngineRowingUI.captionGrey,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ),
            ),
            borderData: FlBorderData(
              show: true,
              border: Border.all(color: EngineRowingUI.bgGridLine),
            ),
            minX: minX,
            maxX: maxX,
            minY: minY,
            maxY: maxY,
            lineTouchData: LineTouchData(
              enabled: true,
              touchTooltipData: LineTouchTooltipData(
                getTooltipColor: (_) => EngineRowingUI.bgNavy,
                getTooltipItems: (touchedSpots) {
                  return touchedSpots.map((spot) {
                    final match = allSpots.firstWhere(
                      (pt) => (pt.x - spot.x).abs() < 0.2,
                      orElse: () => (
                        x: spot.x,
                        y: spot.y,
                        date: '',
                        duration: 0.0,
                      ),
                    );
                    final durStr = match.duration > 0
                        ? '\n${s.durationMinutesLabel}: ${match.duration.round()}m'
                        : '';
                    return LineTooltipItem(
                      '${match.date}\nDecoupling: ${spot.y.toStringAsFixed(1)}%$durStr',
                      TextStyle(
                        color: spot.bar.color ?? Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    );
                  }).toList();
                },
              ),
            ),
            lineBarsData: bars,
          ),
        ),
      ),
    );
  }

  /// قسم اختيار تمرين معين لعرض تحليل قراءات الـ Decoupling الخاصة به
  Widget _buildSpecificWorkoutSection(BuildContext context, AppStrings s) {
    final filtered = _getFilteredWorkouts(widget.workouts);
    final workoutsWithReadings = filtered.where((w) {
      final dec = w['decoupling'];
      return dec != null && (dec is String && dec.contains('-'));
    }).toList();

    if (workoutsWithReadings.isEmpty) {
      return const SizedBox.shrink();
    }

    final currentWorkout = _selectedWorkout ?? workoutsWithReadings.first;
    final readingsText = (currentWorkout['decoupling'] as String?) ?? '';
    final dur = (currentWorkout['duration_minutes'] as num?)?.toDouble() ??
        (currentWorkout['duration'] as num?)?.toDouble() ??
        60.0;
    final wDate = (currentWorkout['date'] as String?) ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: EngineRowingUI.cardFill,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: EngineRowingUI.bgGridLine),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 360;
              final dropdown = DropdownButtonHideUnderline(
                child: DropdownButton<Map<String, Object?>>(
                  value: currentWorkout,
                  dropdownColor: EngineRowingUI.bgNavy,
                  isDense: true,
                  isExpanded: true,
                  icon: const Icon(Icons.arrow_drop_down,
                      color: EngineRowingUI.neonLime),
                  items: workoutsWithReadings.map((w) {
                    final date = (w['date'] as String?) ?? '';
                    final idx = (w['idx'] as num?)?.toInt() ?? 0;
                    return DropdownMenuItem(
                      value: w,
                      child: Text(
                        '$date - #$idx (${w['kind']})',
                        style: const TextStyle(
                          fontSize: 12,
                          color: EngineRowingUI.textWhite,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) setState(() => _selectedWorkout = val);
                  },
                ),
              );

              if (isNarrow) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.sports_score_rounded,
                            color: EngineRowingUI.neonLime, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${s.selectWorkoutPrompt}:',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: EngineRowingUI.textWhite,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    dropdown,
                  ],
                );
              }

              return Row(
                children: [
                  const Icon(Icons.sports_score_rounded,
                      color: EngineRowingUI.neonLime, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    '${s.selectWorkoutPrompt}:',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: EngineRowingUI.textWhite,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: dropdown),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        WorkoutDecouplingCurve(
          rawReadingsText: readingsText,
          durationMinutes: dur,
          zoneKey: _selectedZone,
          workoutDate: wDate,
          athleteName: widget.athleteName,
        ),
      ],
    );
  }

  Widget _buildInputChipsRow(BuildContext context, AppStrings s) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildChip(s.chipTime),
          const SizedBox(width: 6),
          _buildChip(s.chipDecoupling),
          const SizedBox(width: 6),
          _buildChip(s.chipWatts),
          const SizedBox(width: 6),
          _buildChip(s.chipHR),
          const SizedBox(width: 6),
          _buildChip(s.chipEF),
          const SizedBox(width: 6),
          _buildChip(s.chipZone),
        ],
      ),
    );
  }

  Widget _buildChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: EngineRowingUI.equationCardFill,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: EngineRowingUI.neonLime.withValues(alpha: 0.4),
        ),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          color: EngineRowingUI.textWhite,
          fontWeight: FontWeight.w600,
        ),
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
            const Icon(Icons.info_outline_rounded,
                color: EngineRowingUI.neonLime),
            const SizedBox(width: 8),
            Text(s.decouplingTitle,
                style: const TextStyle(color: EngineRowingUI.textWhite)),
          ],
        ),
        content: Text(
          s.decouplingExplanation,
          style: const TextStyle(color: EngineRowingUI.labelSlate, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(s.save,
                style: const TextStyle(color: EngineRowingUI.neonLime)),
          ),
        ],
      ),
    );
  }
}
