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

/// منحنى قياس استرداد النفس (Eupnea) بسياسة «كل تمرينة = نقطة»:
/// - عزل تام: نوع أداء واحد محدد (بدون All وبدون Stretch/Mob) + منطقة تدريب واحدة (بدون All) + فصل القياس 1 و2 و3
/// - أقل قيمة زمنية في اليوم = الأفضل (يمر بها الخط)، وباقي تمرينات نفس اليوم والمنطقة تظهر باهتة بدون خط
/// - خط أساس منقط متدرج منفصل لكل قياس عبر ProgressCalcs.computeBaseline
/// - محور X يعرض التواريخ الفعلية فقط، وتمرير أفقي يبدأ من أحدث تاريخ وبخط >= 12
class EupneaCurveBlock extends StatefulWidget {
  final AppStrings s;
  final String athleteName;
  final Color athleteColor;
  final List<Map<String, Object?>> workouts;
  final DateTime periodStart;
  final DateTime periodEnd;
  final int mhr;
  final int effectiveRhr;
  final bool isLoading;

  const EupneaCurveBlock({
    super.key,
    required this.s,
    required this.athleteName,
    required this.athleteColor,
    required this.workouts,
    required this.periodStart,
    required this.periodEnd,
    required this.mhr,
    required this.effectiveRhr,
    required this.isLoading,
  });

  @override
  State<EupneaCurveBlock> createState() => _EupneaCurveBlockState();
}

class _EupneaCurveBlockState extends State<EupneaCurveBlock> {
  late String _selectedKind;
  late String _selectedZone;

  bool _showReading1 = true;
  bool _showReading2 = true;
  bool _showReading3 = true;

  @override
  void initState() {
    super.initState();
    _selectedKind = WorkoutKinds.computeInitialPerformanceKind(widget.workouts);
    _selectedZone = _computeInitialZone();
  }

  @override
  void didUpdateWidget(covariant EupneaCurveBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!WorkoutKinds.performanceKinds.contains(_selectedKind) ||
        (widget.workouts != oldWidget.workouts &&
            !_hasDataForKind(_selectedKind))) {
      _selectedKind =
          WorkoutKinds.computeInitialPerformanceKind(widget.workouts);
    }
    if (widget.workouts != oldWidget.workouts &&
        !_hasDataForKindAndZone(_selectedKind, _selectedZone)) {
      _selectedZone = _computeInitialZone();
    }
  }

  bool _hasEupneaValues(Map<String, Object?> w) {
    final e1 = (w['eupnea_1'] as num?)?.toDouble();
    final e2 = (w['eupnea_2'] as num?)?.toDouble();
    final e3 = (w['eupnea_3'] as num?)?.toDouble();
    return (e1 != null && e1 > 0) ||
        (e2 != null && e2 > 0) ||
        (e3 != null && e3 > 0);
  }

  bool _matchesKind(Map<String, Object?> w, String selectedKind) {
    final raw =
        ((w['kind'] as String?) ?? (w['session_kind'] as String?) ?? '').trim();
    if (raw.isEmpty) {
      return selectedKind == 'Erg';
    }
    return WorkoutKinds.isPerformanceKind(raw) &&
        WorkoutKinds.matchesKind(raw, selectedKind);
  }

  String _resolveZone(Map<String, Object?> w) {
    String? z = (w['zone'] as String?)?.trim();
    if (z == null || z.isEmpty) {
      final hr = (w['hr'] as num?)?.toInt() ?? (w['avg_hr'] as num?)?.toInt();
      if (hr != null && hr > 0 && widget.mhr > widget.effectiveRhr) {
        z = HeartRateZones.determineZone(
          hr: hr,
          mhr: widget.mhr,
          rhr: widget.effectiveRhr,
        );
      }
    }
    if (z == null || z.isEmpty) return 'Z2';
    return HeartRateZones.normalizeZoneKey(z);
  }

  bool _hasDataForKind(String kind) {
    return widget.workouts
        .any((w) => _matchesKind(w, kind) && _hasEupneaValues(w));
  }

  bool _hasDataForKindAndZone(String kind, String zoneKey) {
    final target = HeartRateZones.normalizeZoneKey(zoneKey);
    return widget.workouts.any((w) {
      if (!_matchesKind(w, kind)) return false;
      if (!_hasEupneaValues(w)) return false;
      return _resolveZone(w) == target;
    });
  }

  String _computeInitialZone() {
    for (final z in HeartRateZones.orderedZones) {
      if (_hasDataForKindAndZone(_selectedKind, z)) return z;
    }
    return 'Z2';
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isLoading) {
      return ProgressPanel(
        title: widget.athleteName,
        child: const SizedBox(
          height: 180,
          child: Center(
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: EngineRowingUI.neonLime,
            ),
          ),
        ),
      );
    }

    final targetZone = HeartRateZones.normalizeZoneKey(_selectedZone);
    final pStart = DateTime(widget.periodStart.year, widget.periodStart.month,
        widget.periodStart.day);
    final pEnd = DateTime(
        widget.periodEnd.year, widget.periodEnd.month, widget.periodEnd.day);

    // 1. عزل تام: نوع أداء واحد + منطقة تدريب واحدة (كل السجل لخط الأساس، وفترة الرسم للنقاط)
    final allIsolatedLogs = widget.workouts.where((w) {
      if (!_matchesKind(w, _selectedKind)) return false;
      if (!_hasEupneaValues(w)) return false;
      return _resolveZone(w) == targetZone;
    }).toList();

    final periodIsolatedLogs = allIsolatedLogs.where((w) {
      final d = ProgressCalcs.parseDate((w['date'] as String?) ?? '');
      if (d == null) return false;
      final dOnly = DateTime(d.year, d.month, d.day);
      return !dOnly.isBefore(pStart) && !dOnly.isAfter(pEnd);
    }).toList();

    // استخراج التواريخ الفعلية التي بها قياس لأي من القراءات المختارة
    final activeDateMap = <String, DateTime>{};
    for (final w in periodIsolatedLogs) {
      final d = ProgressCalcs.parseDate((w['date'] as String?) ?? '');
      if (d == null) continue;
      final dOnly = DateTime(d.year, d.month, d.day);
      final e1 = (w['eupnea_1'] as num?)?.toDouble();
      final e2 = (w['eupnea_2'] as num?)?.toDouble();
      final e3 = (w['eupnea_3'] as num?)?.toDouble();
      final hasVisible = (_showReading1 && e1 != null && e1 > 0) ||
          (_showReading2 && e2 != null && e2 > 0) ||
          (_showReading3 && e3 != null && e3 > 0);
      if (hasVisible) {
        activeDateMap[ProgressCalcs.formatDate(dOnly)] = dOnly;
      }
    }
    final activeDates = activeDateMap.values.toList()..sort();

    double? extractE(Map<String, Object?> row, String key) {
      final v = (row[key] as num?)?.toDouble();
      return (v != null && v > 0) ? v : null;
    }

    final series1 = ProgressCalcs.buildWorkoutDateSeries(
      workouts: periodIsolatedLogs,
      periodStart: pStart,
      periodEnd: pEnd,
      extractValue: (w) => extractE(w, 'eupnea_1'),
      higherIsBetter: false, // الأقل بالثواني هو الأفضل
      sharedActiveDates: activeDates,
      defaultKind: _selectedKind,
    );
    final series2 = ProgressCalcs.buildWorkoutDateSeries(
      workouts: periodIsolatedLogs,
      periodStart: pStart,
      periodEnd: pEnd,
      extractValue: (w) => extractE(w, 'eupnea_2'),
      higherIsBetter: false,
      sharedActiveDates: activeDates,
      defaultKind: _selectedKind,
    );
    final series3 = ProgressCalcs.buildWorkoutDateSeries(
      workouts: periodIsolatedLogs,
      periodStart: pStart,
      periodEnd: pEnd,
      extractValue: (w) => extractE(w, 'eupnea_3'),
      higherIsBetter: false,
      sharedActiveDates: activeDates,
      defaultKind: _selectedKind,
    );

    final baseline1 = ProgressCalcs.computeBaseline(
      workouts: allIsolatedLogs,
      metricKey: 'eupnea_1',
      periodStartDate: pStart,
    );
    final baseline2 = ProgressCalcs.computeBaseline(
      workouts: allIsolatedLogs,
      metricKey: 'eupnea_2',
      periodStartDate: pStart,
    );
    final baseline3 = ProgressCalcs.computeBaseline(
      workouts: allIsolatedLogs,
      metricKey: 'eupnea_3',
      periodStartDate: pStart,
    );

    const Color c1 = EngineRowingUI.electricCyan;
    const Color c2 = EngineRowingUI.neonLime;
    const Color c3 = EngineRowingUI.flameOrange;

    final allVals = <double>[];
    if (_showReading1) {
      for (final p in series1.allPoints) {
        allVals.add(p.value);
      }
      if (baseline1.currentBaseline != null && baseline1.currentBaseline! > 0) {
        allVals.add(baseline1.currentBaseline!);
      }
    }
    if (_showReading2) {
      for (final p in series2.allPoints) {
        allVals.add(p.value);
      }
      if (baseline2.currentBaseline != null && baseline2.currentBaseline! > 0) {
        allVals.add(baseline2.currentBaseline!);
      }
    }
    if (_showReading3) {
      for (final p in series3.allPoints) {
        allVals.add(p.value);
      }
      if (baseline3.currentBaseline != null && baseline3.currentBaseline! > 0) {
        allVals.add(baseline3.currentBaseline!);
      }
    }

    final hasData = activeDates.isNotEmpty &&
        ((_showReading1 && !series1.isEmpty) ||
            (_showReading2 && !series2.isEmpty) ||
            (_showReading3 && !series3.isEmpty));

    double minY = 0.0;
    double maxY = 60.0;
    if (allVals.isNotEmpty) {
      final dMin = allVals.reduce(min);
      final dMax = allVals.reduce(max);
      final spread = (dMax - dMin).abs() < 2.0 ? 5.0 : (dMax - dMin);
      minY = max(0.0, (dMin - spread * 0.15).floorToDouble());
      maxY = (dMax + spread * 0.15).ceilToDouble();
      if (maxY <= minY) maxY = minY + 10.0;
    }

    final lineBars = <LineChartBarData>[];
    final pointMatrix = <List<WorkoutPlotPoint?>>[];
    final readingLabelByBar = <int, String>{};
    bool hasAnyDimmed = false;

    void addReadingLayers({
      required bool enabled,
      required String label,
      required Color color,
      required WorkoutDateSeriesResult series,
      required BaselineResult baseline,
    }) {
      if (!enabled) return;

      // 1. نقاط نفس اليوم الأعلى (أسوأ) باهتة بدون خط
      if (series.dimmedPoints.isNotEmpty) {
        hasAnyDimmed = true;
        final barIdx = lineBars.length;
        lineBars.add(
          LineChartBarData(
            spots: series.dimmedPoints
                .map((p) => FlSpot(p.xSlotIndex.toDouble(), p.value))
                .toList(),
            isCurved: false,
            color: Colors.transparent,
            barWidth: 0,
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, p, b, i) => FlDotCirclePainter(
                radius: 4.5,
                color: color.withValues(alpha: 0.35),
                strokeWidth: 1.0,
                strokeColor: color.withValues(alpha: 0.55),
              ),
            ),
          ),
        );
        pointMatrix.add(series.dimmedPoints);
        readingLabelByBar[barIdx] = label;
      }

      // 2. الخط الأساسي يمر بأقل قيمة في اليوم (الأفضل)
      if (series.bestPoints.isNotEmpty) {
        final barIdx = lineBars.length;
        lineBars.add(
          LineChartBarData(
            spots: series.bestPoints
                .map((p) => FlSpot(p.xSlotIndex.toDouble(), p.value))
                .toList(),
            isCurved: false,
            color: color,
            barWidth: 2.6,
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, p, b, i) => FlDotCirclePainter(
                radius: 4.6,
                color: color,
                strokeWidth: 1.4,
                strokeColor: EngineRowingUI.cardFill,
              ),
            ),
          ),
        );
        pointMatrix.add(series.bestPoints);
        readingLabelByBar[barIdx] = label;
      }

      // 3. خط الأساس المنقط التدريجي (Stepped Baseline)
      if (baseline.hasEnoughData &&
          baseline.currentBaseline != null &&
          baseline.currentBaseline! > 0 &&
          activeDates.isNotEmpty) {
        var bSpots = <FlSpot>[];
        for (int idx = 0; idx < activeDates.length; idx++) {
          final d = activeDates[idx];
          double? val =
              baseline.startOfPeriodBaseline ?? baseline.currentBaseline;
          for (final hp in baseline.historyPoints) {
            final hd = DateTime(hp.date.year, hp.date.month, hp.date.day);
            if (!hd.isAfter(d)) {
              val = hp.value;
            }
          }
          if (val != null) {
            bSpots.add(FlSpot(idx.toDouble(), val));
          }
        }
        if (bSpots.length == 1) {
          bSpots = [
            FlSpot(-0.3, bSpots.first.y),
            FlSpot(0.3, bSpots.first.y),
          ];
        }
        if (bSpots.isNotEmpty) {
          lineBars.add(
            LineChartBarData(
              spots: bSpots,
              isCurved: false,
              isStepLineChart: true,
              color: color.withValues(alpha: 0.65),
              barWidth: 1.8,
              dashArray: const [6, 4],
              dotData: const FlDotData(show: false),
            ),
          );
          pointMatrix.add(List<WorkoutPlotPoint?>.filled(bSpots.length, null));
        }
      }
    }

    addReadingLayers(
      enabled: _showReading1,
      label: widget.s.reading1Label,
      color: c1,
      series: series1,
      baseline: baseline1,
    );
    addReadingLayers(
      enabled: _showReading2,
      label: widget.s.reading2Label,
      color: c2,
      series: series2,
      baseline: baseline2,
    );
    addReadingLayers(
      enabled: _showReading3,
      label: widget.s.reading3Label,
      color: c3,
      series: series3,
      baseline: baseline3,
    );

    final minX = -0.5;
    final maxX = max(0, activeDates.length - 1).toDouble() + 0.5;

    return ProgressPanel(
      title: widget.athleteName,
      glowBorderColor: widget.athleteColor.withValues(alpha: 0.45),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── ترويسة العنوان + شارة الأقل هو الأفضل ──
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.s.eupneaTitle,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: EngineRowingUI.textWhite,
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: EngineRowingUI.neonLime.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: EngineRowingUI.neonLime.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Text(
                    widget.s.eupneaLowerIsBetter,
                    maxLines: 1,
                    softWrap: false,
                    style: const TextStyle(
                      color: EngineRowingUI.neonLime,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // ── اختيار نوع الأداء (بدلاً من All وبدون Stretch/Mob) في سطر أفقي واحد ──
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (int i = 0;
                    i < WorkoutKinds.performanceKinds.length;
                    i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  _buildKindPill(WorkoutKinds.performanceKinds[i]),
                ],
              ],
            ),
          ),
          const SizedBox(height: 8),

          // ── اختيار منطقة تدريب واحدة (بدون All نهائياً) في سطر أفقي واحد ──
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (int i = 0;
                    i < HeartRateZones.orderedZones.length;
                    i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  _buildZonePill(HeartRateZones.orderedZones[i]),
                ],
              ],
            ),
          ),
          const SizedBox(height: 8),

          // ── أزرار تفعيل/إخفاء القياسات الثلاثة في سطر أفقي واحد ──
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildTogglePill(
                  label: widget.s.reading1Label,
                  color: c1,
                  active: _showReading1,
                  onTap: () => setState(() => _showReading1 = !_showReading1),
                ),
                const SizedBox(width: 8),
                _buildTogglePill(
                  label: widget.s.reading2Label,
                  color: c2,
                  active: _showReading2,
                  onTap: () => setState(() => _showReading2 = !_showReading2),
                ),
                const SizedBox(width: 8),
                _buildTogglePill(
                  label: widget.s.reading3Label,
                  color: c3,
                  active: _showReading3,
                  onTap: () => setState(() => _showReading3 = !_showReading3),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          if (!hasData)
            SizedBox(
              height: 160,
              child: Center(
                child: Text(
                  widget.s.insufficientData,
                  style: const TextStyle(color: Colors.white54, fontSize: 13),
                ),
              ),
            )
          else ...[
            ScrollableChartFrame(
              height: 245.0,
              slotsCount: activeDates.length,
              slotWidth: 68.0,
              minY: minY,
              maxY: maxY,
              yTicksCount: 5,
              yAxisUnitLabel: widget.s.isArabic ? 'الزمن (ث)' : 'Seconds (s)',
              formatYLabel: (v) => '${v.toStringAsFixed(0)}s',
              bottomReservedSize: 34.0,
              chartBuilder: (chartWidth, chartHeight) {
                return LineChart(
                  LineChartData(
                    minY: minY,
                    maxY: maxY,
                    minX: minX,
                    maxX: maxX,
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
                        color:
                            EngineRowingUI.bgGridLine.withValues(alpha: 0.45),
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
                            final pt =
                                pointMatrix[spot.barIndex][spot.spotIndex];
                            if (pt == null) return null;

                            final dateStr =
                                '${pt.date.day}/${pt.date.month}/${pt.date.year}';
                            final hrStr = pt.avgHr != null
                                ? '${pt.avgHr!.round()} bpm'
                                : '--';
                            final zoneStr = HeartRateZones.zoneDisplayName(
                              pt.zoneKey,
                              isArabic: widget.s.isArabic,
                            );
                            final kindStr =
                                WorkoutKinds.displayName(pt.kind, widget.s);
                            final rLabel =
                                readingLabelByBar[spot.barIndex] ?? '';
                            final text = [
                              if (rLabel.isNotEmpty) rLabel,
                              '$dateStr · ${widget.s.workoutNumberInDay} ${pt.dayOrder}',
                              '${pt.value.toStringAsFixed(1)} s',
                              '${widget.s.heartRateShort}: $hrStr · $zoneStr',
                              '${widget.s.typeShort}: $kindStr',
                            ].join('\n');

                            return LineTooltipItem(
                              text,
                              TextStyle(
                                color: spot.bar.color == Colors.transparent
                                    ? EngineRowingUI.labelSlate
                                    : (spot.bar.color ?? Colors.white),
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
                if (_showReading1)
                  SingleLineLegendItem(
                    color: c1,
                    label: widget.s.reading1Label,
                  ),
                if (_showReading2)
                  SingleLineLegendItem(
                    color: c2,
                    label: widget.s.reading2Label,
                  ),
                if (_showReading3)
                  SingleLineLegendItem(
                    color: c3,
                    label: widget.s.reading3Label,
                  ),
                if (hasAnyDimmed)
                  SingleLineLegendItem(
                    color: EngineRowingUI.labelSlate,
                    label: widget.s.sameDayDimmedLegend,
                    isCircle: true,
                    isDimmed: true,
                  ),
                if ((_showReading1 &&
                        baseline1.hasEnoughData &&
                        baseline1.currentBaseline != null) ||
                    (_showReading2 &&
                        baseline2.hasEnoughData &&
                        baseline2.currentBaseline != null) ||
                    (_showReading3 &&
                        baseline3.hasEnoughData &&
                        baseline3.currentBaseline != null))
                  SingleLineLegendItem(
                    color: Colors.white70,
                    label: widget.s.zoneBaselineLegend,
                    isDashed: true,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              widget.s.eupneaBelowBaselineNotice,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
          const SizedBox(height: 6),
          Text(
            widget.s.estimationNotice,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildKindPill(String k) {
    final isSelected = k == _selectedKind;
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () {
        if (_selectedKind == k) return;
        setState(() {
          _selectedKind = k;
          if (!_hasDataForKindAndZone(_selectedKind, _selectedZone)) {
            _selectedZone = _computeInitialZone();
          }
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? EngineRowingUI.neonLime.withValues(alpha: 0.22)
              : EngineRowingUI.equationCardFill,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isSelected
                ? EngineRowingUI.neonLime
                : EngineRowingUI.bgGridLine,
          ),
        ),
        child: Text(
          WorkoutKinds.displayName(k, widget.s),
          maxLines: 1,
          softWrap: false,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            color:
                isSelected ? EngineRowingUI.neonLime : EngineRowingUI.textWhite,
          ),
        ),
      ),
    );
  }

  Widget _buildZonePill(String z) {
    final cleanSelected = HeartRateZones.normalizeZoneKey(_selectedZone);
    final isSelected = cleanSelected == z;
    final zColor = HeartRateZones.zoneColor(z);
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => setState(() => _selectedZone = z),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? zColor.withValues(alpha: 0.22)
              : EngineRowingUI.equationCardFill,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isSelected ? zColor : zColor.withValues(alpha: 0.4),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: zColor, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text(
              HeartRateZones.zoneDisplayName(z, isArabic: widget.s.isArabic),
              maxLines: 1,
              softWrap: false,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected
                    ? EngineRowingUI.textWhite
                    : zColor.withValues(alpha: 0.92),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTogglePill({
    required String label,
    required Color color,
    required bool active,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active
              ? color.withValues(alpha: 0.18)
              : EngineRowingUI.equationCardFill,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: active ? color : Colors.white24,
            width: 1.2,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: active ? color : Colors.transparent,
                border: Border.all(color: color, width: 1.4),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              maxLines: 1,
              softWrap: false,
              style: TextStyle(
                color: active ? color : Colors.white54,
                fontSize: 12,
                fontWeight: active ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
