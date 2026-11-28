import 'dart:math';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'app_strings.dart';
import 'engine_rowing_ui.dart';
import 'heart_rate_zones.dart';
import 'progress_calcs.dart';
import 'progress_panel.dart';
import 'scrollable_chart_container.dart';
import 'workout_kinds.dart';

/// المكون المشترك لمنحنيات الأداء (الواط، EF، Decoupling) بسياسة «كل تمرينة = نقطة»:
/// - التواريخ الفعلية التي بها بيانات فقط على محور X (بدون أيام فراغ)
/// - عدة تمرينات في نفس اليوم: يمر المنحنى بأفضل تمرينة في اليوم وتظهر البقية باهتة بدون خط
/// - بدون أي متوسط متحرك (MA7) أو تجميع أسبوعي أو نوع Stretch/Mob/All
/// - تمرير أفقي يبدأ من أحدث تاريخ، ومحور Y ثابت، وخط >= 12 دائماً
class WorkoutMetricCurveView extends StatefulWidget {
  final String title;
  final IconData icon;
  final VoidCallback onInfoTap;
  final List<Map<String, Object?>> workouts;
  final DateTime periodStart;
  final DateTime periodEnd;
  final String athleteName;
  final int playerId;
  final Map<int, List<Map<String, Object?>>>? multiAthleteWorkouts;
  final Map<int, String>? athleteNames;
  final Map<int, Color>? athleteColors;
  final double? Function(Map<String, Object?> row) extractValue;
  final bool higherIsBetter;
  final String baselineMetricKey;
  final String yUnitLabel;
  final String Function(double val) formatYValue;
  final String Function(double val) formatTooltipValue;
  final double? fixedMinY;
  final double Function(double dataMin, double dataMax)? computeMinY;
  final double Function(double dataMin, double dataMax)? computeMaxY;
  final List<String>? availableChipLabels;
  final void Function(WorkoutPlotPoint point)? onPointTap;
  final Widget? Function(
    BuildContext context,
    AppStrings s,
    String selectedKind,
    String? focusedZone,
  )? extraBottomBuilder;
  final void Function(String kind, String? zone)? onFilterChanged;

  const WorkoutMetricCurveView({
    super.key,
    required this.title,
    required this.icon,
    required this.onInfoTap,
    required this.workouts,
    required this.periodStart,
    required this.periodEnd,
    required this.athleteName,
    required this.playerId,
    this.multiAthleteWorkouts,
    this.athleteNames,
    this.athleteColors,
    required this.extractValue,
    required this.higherIsBetter,
    required this.baselineMetricKey,
    required this.yUnitLabel,
    required this.formatYValue,
    required this.formatTooltipValue,
    this.fixedMinY,
    this.computeMinY,
    this.computeMaxY,
    this.availableChipLabels,
    this.onPointTap,
    this.extraBottomBuilder,
    this.onFilterChanged,
  });

  @override
  State<WorkoutMetricCurveView> createState() => _WorkoutMetricCurveViewState();
}

class _WorkoutMetricCurveViewState extends State<WorkoutMetricCurveView> {
  late String _selectedKind;
  String? _focusedZone; // null في الفردي = عرض كل زون في خط ملون مستقل
  String _multiZone = 'Z2';

  bool get _isMultiAthlete =>
      widget.multiAthleteWorkouts != null &&
      widget.multiAthleteWorkouts!.length > 1;

  @override
  void initState() {
    super.initState();
    _selectedKind = WorkoutKinds.computeInitialPerformanceKind(
      widget.workouts,
      multiAthleteWorkouts: widget.multiAthleteWorkouts,
    );
    _multiZone = _computeInitialMultiZone();
  }

  @override
  void didUpdateWidget(covariant WorkoutMetricCurveView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!WorkoutKinds.performanceKinds.contains(_selectedKind) ||
        (widget.workouts != oldWidget.workouts &&
            !_hasDataForKind(_selectedKind))) {
      _selectedKind = WorkoutKinds.computeInitialPerformanceKind(
        widget.workouts,
        multiAthleteWorkouts: widget.multiAthleteWorkouts,
      );
    }
    if (widget.multiAthleteWorkouts != oldWidget.multiAthleteWorkouts ||
        widget.workouts != oldWidget.workouts) {
      if (!_hasDataForKindAndZone(_selectedKind, _multiZone)) {
        _multiZone = _computeInitialMultiZone();
      }
    }
  }

  bool _matchesKind(Map<String, Object?> row, String selectedKind) {
    final raw =
        ((row['kind'] as String?) ?? (row['session_kind'] as String?) ?? '')
            .trim();
    if (raw.isEmpty) {
      return selectedKind == 'Erg';
    }
    return WorkoutKinds.isPerformanceKind(raw) &&
        WorkoutKinds.matchesKind(raw, selectedKind);
  }

  bool _hasDataForKind(String kind) {
    for (final w in widget.workouts) {
      if (_matchesKind(w, kind) && widget.extractValue(w) != null) return true;
    }
    if (widget.multiAthleteWorkouts != null) {
      for (final list in widget.multiAthleteWorkouts!.values) {
        for (final w in list) {
          if (_matchesKind(w, kind) && widget.extractValue(w) != null) {
            return true;
          }
        }
      }
    }
    return false;
  }

  bool _hasDataForKindAndZone(String kind, String zoneKey) {
    final targetZone = HeartRateZones.normalizeZoneKey(zoneKey);
    bool scan(List<Map<String, Object?>> list) {
      for (final w in list) {
        if (!_matchesKind(w, kind)) continue;
        final z = HeartRateZones.normalizeZoneKey((w['zone'] as String?) ?? '');
        if (z == targetZone && widget.extractValue(w) != null) return true;
      }
      return false;
    }

    if (scan(widget.workouts)) return true;
    if (widget.multiAthleteWorkouts != null) {
      for (final list in widget.multiAthleteWorkouts!.values) {
        if (scan(list)) return true;
      }
    }
    return false;
  }

  String _computeInitialMultiZone() {
    for (final z in HeartRateZones.orderedZones) {
      if (_hasDataForKindAndZone(_selectedKind, z)) return z;
    }
    return 'Z2';
  }

  List<Map<String, Object?>> _filterWorkouts(
    List<Map<String, Object?>> source, {
    String? zoneKey,
  }) {
    final pStart = DateTime(
        widget.periodStart.year, widget.periodStart.month, widget.periodStart.day);
    final pEnd = DateTime(
        widget.periodEnd.year, widget.periodEnd.month, widget.periodEnd.day);
    final normZone =
        zoneKey != null ? HeartRateZones.normalizeZoneKey(zoneKey) : null;

    return source.where((w) {
      if (!_matchesKind(w, _selectedKind)) return false;
      final d = ProgressCalcs.parseDate((w['date'] as String?) ?? '');
      if (d == null) return false;
      final dOnly = DateTime(d.year, d.month, d.day);
      if (dOnly.isBefore(pStart) || dOnly.isAfter(pEnd)) return false;
      if (normZone != null) {
        final wz =
            HeartRateZones.normalizeZoneKey((w['zone'] as String?) ?? '');
        if (wz != normZone) return false;
      }
      return widget.extractValue(w) != null;
    }).toList();
  }

  List<DateTime> _collectSortedUniqueDates(
    List<List<Map<String, Object?>>> buckets,
  ) {
    final map = <String, DateTime>{};
    for (final list in buckets) {
      for (final w in list) {
        final d = ProgressCalcs.parseDate((w['date'] as String?) ?? '');
        if (d == null) continue;
        final dOnly = DateTime(d.year, d.month, d.day);
        map[ProgressCalcs.formatDate(dOnly)] = dOnly;
      }
    }
    final dates = map.values.toList()..sort();
    return dates;
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final activeZoneFilter = _isMultiAthlete ? _multiZone : _focusedZone;

    return ProgressPanel(
      title: widget.title,
      leading: Icon(widget.icon, color: EngineRowingUI.neonLime, size: 20),
      trailing: IconButton(
        icon: const Icon(
          Icons.info_outline_rounded,
          color: EngineRowingUI.neonLime,
          size: 20,
        ),
        tooltip: widget.title,
        onPressed: widget.onInfoTap,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildKindFilterRow(s),
          const SizedBox(height: 8),
          _buildZoneFilterRow(s),
          const SizedBox(height: 12),
          _buildChartSection(context, s),
          if (widget.availableChipLabels != null &&
              widget.availableChipLabels!.isNotEmpty) ...[
            const SizedBox(height: 10),
            SingleLineChipsRow(labels: widget.availableChipLabels!),
          ],
          if (widget.extraBottomBuilder != null) ...[
            const SizedBox(height: 10),
            widget.extraBottomBuilder!(
                    context, s, _selectedKind, activeZoneFilter) ??
                const SizedBox.shrink(),
          ],
          const SizedBox(height: 10),
          Text(
            s.estimatedCurveNotice,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12,
              color: EngineRowingUI.labelSlate,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKindFilterRow(AppStrings s) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (int i = 0; i < WorkoutKinds.performanceKinds.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Builder(
              builder: (context) {
                final k = WorkoutKinds.performanceKinds[i];
                final isSelected = k == _selectedKind;
                return InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: () {
                    if (_selectedKind == k) return;
                    setState(() {
                      _selectedKind = k;
                      if (_isMultiAthlete &&
                          !_hasDataForKindAndZone(_selectedKind, _multiZone)) {
                        _multiZone = _computeInitialMultiZone();
                      }
                    });
                    widget.onFilterChanged?.call(
                      _selectedKind,
                      _isMultiAthlete ? _multiZone : _focusedZone,
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? EngineRowingUI.neonLime.withValues(alpha: 0.22)
                          : EngineRowingUI.equationCardFill,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: isSelected
                            ? EngineRowingUI.neonLime
                            : EngineRowingUI.bgGridLine,
                        width: isSelected ? 1.4 : 1.0,
                      ),
                    ),
                    child: Text(
                      WorkoutKinds.displayName(k, s),
                      maxLines: 1,
                      softWrap: false,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight:
                            isSelected ? FontWeight.bold : FontWeight.w500,
                        color: isSelected
                            ? EngineRowingUI.neonLime
                            : EngineRowingUI.textWhite,
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildZoneFilterRow(AppStrings s) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (int i = 0; i < HeartRateZones.orderedZones.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Builder(
              builder: (context) {
                final z = HeartRateZones.orderedZones[i];
                final zColor = HeartRateZones.zoneColor(z);
                final isSelected = _isMultiAthlete
                    ? _multiZone == z
                    : _focusedZone == z;
                return InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: () {
                    setState(() {
                      if (_isMultiAthlete) {
                        _multiZone = z;
                      } else {
                        _focusedZone = (_focusedZone == z) ? null : z;
                      }
                    });
                    widget.onFilterChanged?.call(
                      _selectedKind,
                      _isMultiAthlete ? _multiZone : _focusedZone,
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? zColor.withValues(alpha: 0.22)
                          : EngineRowingUI.equationCardFill,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: isSelected ? zColor : zColor.withValues(alpha: 0.4),
                        width: isSelected ? 1.5 : 1.0,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: zColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          HeartRateZones.zoneDisplayName(z, isArabic: s.isArabic),
                          maxLines: 1,
                          softWrap: false,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.w500,
                            color: isSelected
                                ? EngineRowingUI.textWhite
                                : zColor.withValues(alpha: 0.92),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildChartSection(BuildContext context, AppStrings s) {
    final seriesList = <_SeriesRenderSpec>[];

    if (_isMultiAthlete) {
      final multiMap = widget.multiAthleteWorkouts!;
      final rawBuckets = <int, List<Map<String, Object?>>>{};
      for (final entry in multiMap.entries) {
        final filtered = _filterWorkouts(entry.value, zoneKey: _multiZone);
        if (filtered.isNotEmpty) {
          rawBuckets[entry.key] = filtered;
        }
      }
      if (rawBuckets.isEmpty) {
        return _buildNoDataCard(s.notEnoughData);
      }
      final activeDates = _collectSortedUniqueDates(rawBuckets.values.toList());
      for (final entry in rawBuckets.entries) {
        final pid = entry.key;
        final color =
            widget.athleteColors?[pid] ?? EngineRowingUI.electricCyan;
        final name = widget.athleteNames?[pid] ?? '#$pid';
        final series = ProgressCalcs.buildWorkoutDateSeries(
          workouts: entry.value,
          periodStart: widget.periodStart,
          periodEnd: widget.periodEnd,
          extractValue: widget.extractValue,
          higherIsBetter: widget.higherIsBetter,
          sharedActiveDates: activeDates,
          defaultKind: _selectedKind,
        );
        if (!series.isEmpty) {
          seriesList.add(_SeriesRenderSpec(
            label: name,
            color: color,
            series: series,
            zoneKey: _multiZone,
          ));
        }
      }
      return _renderChartAndLegend(context, s, activeDates, seriesList,
          baselineZone: null);
    }

    // الوضع الفردي: كل منطقة تدريب بخط مستقل بلونها، أو التركيز على منطقة واحدة + خط الأساس
    final targetZones = _focusedZone != null
        ? [_focusedZone!]
        : HeartRateZones.orderedZones;
    final zoneBuckets = <String, List<Map<String, Object?>>>{};
    for (final z in targetZones) {
      final filtered = _filterWorkouts(widget.workouts, zoneKey: z);
      if (filtered.isNotEmpty) {
        zoneBuckets[z] = filtered;
      }
    }

    if (zoneBuckets.isEmpty) {
      return _buildNoDataCard(s.notEnoughData);
    }

    final activeDates = _collectSortedUniqueDates(zoneBuckets.values.toList());
    for (final z in targetZones) {
      final bucket = zoneBuckets[z];
      if (bucket == null || bucket.isEmpty) continue;
      final series = ProgressCalcs.buildWorkoutDateSeries(
        workouts: bucket,
        periodStart: widget.periodStart,
        periodEnd: widget.periodEnd,
        extractValue: widget.extractValue,
        higherIsBetter: widget.higherIsBetter,
        sharedActiveDates: activeDates,
        defaultKind: _selectedKind,
      );
      if (!series.isEmpty) {
        seriesList.add(_SeriesRenderSpec(
          label: HeartRateZones.zoneDisplayName(z, isArabic: s.isArabic),
          color: HeartRateZones.zoneColor(z),
          series: series,
          zoneKey: z,
        ));
      }
    }

    return _renderChartAndLegend(
      context,
      s,
      activeDates,
      seriesList,
      baselineZone: _focusedZone,
    );
  }

  Widget _buildNoDataCard(String message) {
    return SizedBox(
      height: 160,
      child: Center(
        child: Text(
          message,
          style: const TextStyle(
            fontSize: 13,
            color: EngineRowingUI.labelSlate,
          ),
        ),
      ),
    );
  }

  Widget _renderChartAndLegend(
    BuildContext context,
    AppStrings s,
    List<DateTime> activeDates,
    List<_SeriesRenderSpec> seriesList, {
    required String? baselineZone,
  }) {
    if (seriesList.isEmpty || activeDates.isEmpty) {
      return _buildNoDataCard(s.notEnoughData);
    }

    final allValues = <double>[];
    bool hasAnyDimmed = false;
    for (final spec in seriesList) {
      for (final p in spec.series.allPoints) {
        allValues.add(p.value);
      }
      if (spec.series.dimmedPoints.isNotEmpty) {
        hasAnyDimmed = true;
      }
    }

    // حساب خط الأساس التدريجي عند التركيز على منطقة واحدة
    BaselineResult? baselineResult;
    List<FlSpot> baselineSpots = [];
    if (baselineZone != null && !_isMultiAthlete) {
      final cleanZone = HeartRateZones.normalizeZoneKey(baselineZone);
      final rawForBaseline = widget.workouts.where((w) {
        if (!_matchesKind(w, _selectedKind)) return false;
        final wz = HeartRateZones.normalizeZoneKey((w['zone'] as String?) ?? '');
        return wz == cleanZone;
      }).toList();
      baselineResult = ProgressCalcs.computeBaseline(
        workouts: rawForBaseline,
        metricKey: widget.baselineMetricKey,
        periodStartDate: widget.periodStart,
      );
      if (baselineResult.hasEnoughData &&
          baselineResult.currentBaseline != null) {
        final history = baselineResult.historyPoints;
        for (int idx = 0; idx < activeDates.length; idx++) {
          final d = activeDates[idx];
          double? bVal = baselineResult.startOfPeriodBaseline ??
              baselineResult.currentBaseline;
          for (final hp in history) {
            final hd = DateTime(hp.date.year, hp.date.month, hp.date.day);
            if (!hd.isAfter(d)) {
              bVal = hp.value;
            }
          }
          if (bVal != null) {
            baselineSpots.add(FlSpot(idx.toDouble(), bVal));
            allValues.add(bVal);
          }
        }
      }
    }

    final rawMin = allValues.reduce(min);
    final rawMax = allValues.reduce(max);
    final spread = (rawMax - rawMin).abs() < 1e-6 ? max(1.0, rawMax * 0.2) : (rawMax - rawMin);
    final double minY = widget.fixedMinY ??
        (widget.computeMinY != null
            ? widget.computeMinY!(rawMin, rawMax)
            : max(0.0, rawMin - spread * 0.15));
    final double maxY = widget.computeMaxY != null
        ? widget.computeMaxY!(rawMin, rawMax)
        : (rawMax + spread * 0.15);
    final double safeMaxY = maxY <= minY ? minY + 1.0 : maxY;

    // بناء خطوط الرسم البياني مع خريطة النقاط المطابقة لكل (barIndex, spotIndex)
    final lineBars = <LineChartBarData>[];
    final pointMatrix = <List<WorkoutPlotPoint?>>[];
    final seriesLabelByBar = <int, String>{};

    for (final spec in seriesList) {
      // 1. نقاط نفس اليوم غير الأفضل: باهتة بدون خط توصيل
      if (spec.series.dimmedPoints.isNotEmpty) {
        final dimmedSpots = spec.series.dimmedPoints
            .map((pt) => FlSpot(pt.xSlotIndex.toDouble(), pt.value))
            .toList();
        final barIdx = lineBars.length;
        lineBars.add(
          LineChartBarData(
            spots: dimmedSpots,
            isCurved: false,
            color: Colors.transparent,
            barWidth: 0,
            isStrokeCapRound: true,
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, percent, bar, idx) => FlDotCirclePainter(
                radius: 4.5,
                color: spec.color.withValues(alpha: 0.35),
                strokeWidth: 1.0,
                strokeColor: spec.color.withValues(alpha: 0.55),
              ),
            ),
          ),
        );
        pointMatrix.add(spec.series.dimmedPoints);
        seriesLabelByBar[barIdx] = spec.label;
      }

      // 2. الخط الأساسي يمر فقط بأفضل تمرينة في كل يوم
      final bestSpots = spec.series.bestPoints
          .map((pt) => FlSpot(pt.xSlotIndex.toDouble(), pt.value))
          .toList();
      if (bestSpots.isNotEmpty) {
        final barIdx = lineBars.length;
        lineBars.add(
          LineChartBarData(
            spots: bestSpots,
            isCurved: false,
            color: spec.color,
            barWidth: 2.8,
            isStrokeCapRound: true,
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, percent, bar, idx) => FlDotCirclePainter(
                radius: 4.8,
                color: spec.color,
                strokeWidth: 1.5,
                strokeColor: EngineRowingUI.cardFill,
              ),
            ),
            belowBarData: BarAreaData(
              show: seriesList.length == 1,
              color: spec.color.withValues(alpha: 0.08),
            ),
          ),
        );
        pointMatrix.add(spec.series.bestPoints);
        seriesLabelByBar[barIdx] = spec.label;
      }
    }

    // 3. خط الأساس المنقط التدريجي (عند التركيز على منطقة واحدة)
    if (baselineSpots.isNotEmpty && baselineZone != null) {
      final baseColor = HeartRateZones.zoneColor(baselineZone);
      if (baselineSpots.length == 1) {
        baselineSpots = [
          FlSpot(-0.3, baselineSpots.first.y),
          FlSpot(0.3, baselineSpots.first.y),
        ];
      }
      lineBars.add(
        LineChartBarData(
          spots: baselineSpots,
          isCurved: false,
          isStepLineChart: true,
          color: baseColor.withValues(alpha: 0.8),
          barWidth: 2.0,
          dashArray: const [6, 4],
          dotData: const FlDotData(show: false),
        ),
      );
      pointMatrix.add(List<WorkoutPlotPoint?>.filled(baselineSpots.length, null));
    }

    final double minX = -0.5;
    final double maxX = (activeDates.length - 1).toDouble() + 0.5;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ScrollableChartFrame(
          height: 250.0,
          slotsCount: activeDates.length,
          slotWidth: 68.0,
          minY: minY,
          maxY: safeMaxY,
          yTicksCount: 5,
          yAxisUnitLabel: widget.yUnitLabel,
          formatYLabel: widget.formatYValue,
          bottomReservedSize: 34.0,
          chartBuilder: (chartWidth, chartHeight) {
            return LineChart(
              LineChartData(
                minX: minX,
                maxX: maxX,
                minY: minY,
                maxY: safeMaxY,
                clipData: const FlClipData.none(),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: true,
                  verticalInterval: 1.0,
                  getDrawingHorizontalLine: (_) => const FlLine(
                    color: EngineRowingUI.bgGridLine,
                    strokeWidth: 0.8,
                  ),
                  getDrawingVerticalLine: (_) => FlLine(
                    color: EngineRowingUI.bgGridLine.withValues(alpha: 0.45),
                    strokeWidth: 0.6,
                  ),
                ),
                borderData: FlBorderData(
                  show: true,
                  border: const Border(
                    bottom: BorderSide(
                        color: EngineRowingUI.bgGridLine, width: 1.0),
                    left: BorderSide(
                        color: EngineRowingUI.bgGridLine, width: 1.0),
                  ),
                ),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  leftTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 34.0,
                      interval: 1.0,
                      getTitlesWidget: (val, meta) {
                        if ((val - val.roundToDouble()).abs() > 0.05) {
                          return const SizedBox.shrink();
                        }
                        final idx = val.round();
                        if (idx < 0 || idx >= activeDates.length) {
                          return const SizedBox.shrink();
                        }
                        final d = activeDates[idx];
                        return SideTitleWidget(
                          meta: meta,
                          space: 8,
                          child: Text(
                            '${d.day}/${d.month}',
                            maxLines: 1,
                            softWrap: false,
                            style: const TextStyle(
                              fontSize: 12,
                              color: EngineRowingUI.labelSlate,
                              fontWeight: FontWeight.w500,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                lineTouchData: LineTouchData(
                  enabled: true,
                  handleBuiltInTouches: true,
                  touchCallback: (event, response) {
                    if (widget.onPointTap != null &&
                        event is FlTapUpEvent &&
                        response?.lineBarSpots != null) {
                      for (final spot in response!.lineBarSpots!) {
                        if (spot.barIndex < pointMatrix.length &&
                            spot.spotIndex <
                                pointMatrix[spot.barIndex].length) {
                          final pt = pointMatrix[spot.barIndex][spot.spotIndex];
                          if (pt != null) {
                            widget.onPointTap!(pt);
                            break;
                          }
                        }
                      }
                    }
                  },
                  touchTooltipData: LineTouchTooltipData(
                    fitInsideHorizontally: true,
                    fitInsideVertically: true,
                    getTooltipColor: (_) =>
                        EngineRowingUI.bgNavy.withValues(alpha: 0.95),
                    tooltipBorder: const BorderSide(
                      color: EngineRowingUI.neonLime,
                      width: 0.8,
                    ),
                    getTooltipItems: (touchedSpots) {
                      return touchedSpots.map((spot) {
                        if (spot.barIndex >= pointMatrix.length ||
                            spot.spotIndex >=
                                pointMatrix[spot.barIndex].length) {
                          return null;
                        }
                        final pt = pointMatrix[spot.barIndex][spot.spotIndex];
                        if (pt == null) return null;

                        final dateStr =
                            '${pt.date.day}/${pt.date.month}/${pt.date.year}';
                        final hrStr = pt.avgHr != null
                            ? '${pt.avgHr!.round()} bpm'
                            : '--';
                        final zoneStr = HeartRateZones.zoneDisplayName(
                          pt.zoneKey,
                          isArabic: s.isArabic,
                        );
                        final kindStr = WorkoutKinds.displayName(pt.kind, s);
                        final seriesTitle =
                            seriesLabelByBar[spot.barIndex] ?? '';
                        final text = [
                          if (seriesTitle.isNotEmpty) seriesTitle,
                          '$dateStr · ${s.workoutNumberInDay} ${pt.dayOrder}',
                          widget.formatTooltipValue(pt.value),
                          '${s.heartRateShort}: $hrStr · $zoneStr',
                          '${s.typeShort}: $kindStr',
                        ].join('\n');

                        return LineTooltipItem(
                          text,
                          TextStyle(
                            color: spot.bar.color == Colors.transparent
                                ? EngineRowingUI.labelSlate
                                : (spot.bar.color ?? EngineRowingUI.textWhite),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        );
                      }).toList();
                    },
                  ),
                ),
                lineBarsData: lineBars,
              ),
            );
          },
        ),
        const SizedBox(height: 10),
        SingleLineLegend(
          items: [
            for (final spec in seriesList)
              SingleLineLegendItem(
                color: spec.color,
                label: spec.label,
              ),
            if (hasAnyDimmed)
              SingleLineLegendItem(
                color: EngineRowingUI.labelSlate,
                label: s.sameDayDimmedLegend,
                isCircle: true,
                isDimmed: true,
              ),
            if (baselineSpots.isNotEmpty && baselineZone != null)
              SingleLineLegendItem(
                color: HeartRateZones.zoneColor(baselineZone),
                label: s.zoneBaselineLegend,
                isDashed: true,
              ),
          ],
        ),
      ],
    );
  }
}

class _SeriesRenderSpec {
  final String label;
  final Color color;
  final WorkoutDateSeriesResult series;
  final String zoneKey;

  const _SeriesRenderSpec({
    required this.label,
    required this.color,
    required this.series,
    required this.zoneKey,
  });
}
