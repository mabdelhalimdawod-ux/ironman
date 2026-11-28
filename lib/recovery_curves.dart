import 'dart:math';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'app_strings.dart';
import 'engine_rowing_ui.dart';
import 'progress_calcs.dart';
import 'progress_panel.dart';
import 'scrollable_chart_container.dart';

/// 1. منحنى تقلب نبض القلب (HRV) — نقطة واحدة لكل يوم مسجل بدون MA7 وبدون SWC
class HrvCurveBlock extends StatelessWidget {
  final AppStrings s;
  final String athleteName;
  final Color athleteColor;
  final List<DateValuePoint> points;
  final bool isLoading;

  const HrvCurveBlock({
    super.key,
    required this.s,
    required this.athleteName,
    required this.athleteColor,
    required this.points,
    required this.isLoading,
  });

  @override
  Widget build(BuildContext context) {
    return _DailyRecoveryChartBlock(
      s: s,
      athleteName: athleteName,
      athleteColor: athleteColor,
      metricLabel: s.hrvTitle,
      unit: 'ms',
      decimals: 0,
      minPadding: 5.0,
      points: points,
      isLoading: isLoading,
    );
  }
}

/// 2. منحنى نبض الراحة (RHR) — نقطة واحدة لكل يوم مسجل بدون MA7 وبدون تنبيه الارتفاع
class RhrCurveBlock extends StatelessWidget {
  final AppStrings s;
  final String athleteName;
  final Color athleteColor;
  final List<DateValuePoint> points;
  final bool isLoading;

  const RhrCurveBlock({
    super.key,
    required this.s,
    required this.athleteName,
    required this.athleteColor,
    required this.points,
    required this.isLoading,
  });

  @override
  Widget build(BuildContext context) {
    return _DailyRecoveryChartBlock(
      s: s,
      athleteName: athleteName,
      athleteColor: athleteColor,
      metricLabel: s.rhrTitle,
      unit: 'bpm',
      decimals: 0,
      minPadding: 4.0,
      points: points,
      isLoading: isLoading,
    );
  }
}

/// 3. منحنى ساعات النوم (Sleep) — نقطة واحدة لكل يوم مسجل بدون MA7
class SleepCurveBlock extends StatelessWidget {
  final AppStrings s;
  final String athleteName;
  final Color athleteColor;
  final List<DateValuePoint> points;
  final bool isLoading;

  const SleepCurveBlock({
    super.key,
    required this.s,
    required this.athleteName,
    required this.athleteColor,
    required this.points,
    required this.isLoading,
  });

  @override
  Widget build(BuildContext context) {
    return _DailyRecoveryChartBlock(
      s: s,
      athleteName: athleteName,
      athleteColor: athleteColor,
      metricLabel: s.chipSleep,
      unit: 'hrs',
      decimals: 1,
      minPadding: 1.0,
      fixedMinY: 0.0,
      fixedMinMaxFloor: 10.0,
      points: points,
      isLoading: isLoading,
    );
  }
}

/// 4. منحنى الوزن الصباحي (Weight) — نقطة واحدة لكل يوم مسجل بدون MA7
class WeightCurveBlock extends StatelessWidget {
  final AppStrings s;
  final String athleteName;
  final Color athleteColor;
  final List<DateValuePoint> points;
  final bool isLoading;

  const WeightCurveBlock({
    super.key,
    required this.s,
    required this.athleteName,
    required this.athleteColor,
    required this.points,
    required this.isLoading,
  });

  @override
  Widget build(BuildContext context) {
    return _DailyRecoveryChartBlock(
      s: s,
      athleteName: athleteName,
      athleteColor: athleteColor,
      metricLabel: s.chipWeight,
      unit: 'kg',
      decimals: 1,
      minPadding: 2.0,
      points: points,
      isLoading: isLoading,
    );
  }
}

/// مكوّن مشترك لمنحنيات الاستشفاء اليومية:
/// - نقطة واحدة لكل يوم فيه بيانات فعلية فقط (بدون أيام فراغ)
/// - بدون أي خط أو مسمى للمتوسط المتحرك MA7
/// - تمرير أفقي يبدأ من أحدث تاريخ، ومحور Y ثابت، ووسيلة إيضاح في سطر أفقي واحد وبخط >= 12
class _DailyRecoveryChartBlock extends StatelessWidget {
  final AppStrings s;
  final String athleteName;
  final Color athleteColor;
  final String metricLabel;
  final String unit;
  final int decimals;
  final double minPadding;
  final double? fixedMinY;
  final double? fixedMinMaxFloor;
  final List<DateValuePoint> points;
  final bool isLoading;

  const _DailyRecoveryChartBlock({
    required this.s,
    required this.athleteName,
    required this.athleteColor,
    required this.metricLabel,
    required this.unit,
    required this.decimals,
    required this.minPadding,
    this.fixedMinY,
    this.fixedMinMaxFloor,
    required this.points,
    required this.isLoading,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return ProgressPanel(
        title: athleteName,
        glowBorderColor: athleteColor.withValues(alpha: 0.45),
        child: const SizedBox(
          height: 160,
          child: Center(
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: EngineRowingUI.neonLime,
            ),
          ),
        ),
      );
    }

    final validPoints = points
        .where((p) => p.value != null && p.value! > 0 && p.value!.isFinite)
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));

    if (validPoints.length < 2) {
      return ProgressPanel(
        title: athleteName,
        glowBorderColor: athleteColor.withValues(alpha: 0.45),
        child: SizedBox(
          height: 130,
          child: Center(
            child: Text(
              s.insufficientData,
              style: const TextStyle(color: Colors.white54, fontSize: 13),
            ),
          ),
        ),
      );
    }

    final dailySpots = <FlSpot>[];
    double dataMin = double.infinity;
    double dataMax = -double.infinity;

    for (int i = 0; i < validPoints.length; i++) {
      final y = validPoints[i].value!;
      dailySpots.add(FlSpot(i.toDouble(), y));
      if (y < dataMin) dataMin = y;
      if (y > dataMax) dataMax = y;
    }

    final pad = max(minPadding, (dataMax - dataMin) * 0.15);
    final double minY = fixedMinY ?? max(0.0, dataMin - pad);
    double maxY = dataMax + pad;
    if (fixedMinMaxFloor != null) {
      maxY = max(fixedMinMaxFloor!, maxY);
    }
    if (maxY <= minY) {
      maxY = minY + minPadding;
    }

    return ProgressPanel(
      title: athleteName,
      glowBorderColor: athleteColor.withValues(alpha: 0.45),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ScrollableChartFrame(
            height: 220.0,
            slotsCount: validPoints.length,
            slotWidth: 64.0,
            minY: minY,
            maxY: maxY,
            yTicksCount: 5,
            yAxisUnitLabel: '$metricLabel ($unit)',
            formatYLabel: (v) => v.toStringAsFixed(decimals),
            bottomReservedSize: 34.0,
            chartBuilder: (chartWidth, chartHeight) {
              return LineChart(
                LineChartData(
                  minY: minY,
                  maxY: maxY,
                  minX: -0.5,
                  maxX: (validPoints.length - 1).toDouble() + 0.5,
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
                      color: EngineRowingUI.bgGridLine.withValues(alpha: 0.4),
                      strokeWidth: 0.6,
                    ),
                  ),
                  borderData: FlBorderData(
                    show: true,
                    border: const Border(
                      left: BorderSide(
                          color: EngineRowingUI.bgGridLine, width: 1.0),
                      bottom: BorderSide(
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
                          if (idx < 0 || idx >= validPoints.length) {
                            return const SizedBox.shrink();
                          }
                          final d = validPoints[idx].date;
                          return SideTitleWidget(
                            meta: meta,
                            space: 8,
                            child: Text(
                              '${d.day}/${d.month}',
                              maxLines: 1,
                              softWrap: false,
                              style: const TextStyle(
                                color: EngineRowingUI.labelSlate,
                                fontSize: 12,
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
                      tooltipBorder:
                          BorderSide(color: athleteColor, width: 0.8),
                      getTooltipItems: (touchedSpots) {
                        return touchedSpots.map((spot) {
                          final idx = spot.x.round();
                          if (idx < 0 || idx >= validPoints.length) return null;
                          final p = validPoints[idx];
                          final dStr =
                              '${p.date.day}/${p.date.month}/${p.date.year}';
                          return LineTooltipItem(
                            '$metricLabel\n$dStr\n${p.value!.toStringAsFixed(decimals)} $unit',
                            TextStyle(
                              color: athleteColor,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          );
                        }).toList();
                      },
                    ),
                  ),
                  lineBarsData: [
                    LineChartBarData(
                      spots: dailySpots,
                      isCurved: false,
                      color: athleteColor,
                      barWidth: 2.6,
                      dotData: FlDotData(
                        show: true,
                        getDotPainter: (spot, percent, bar, index) =>
                            FlDotCirclePainter(
                          radius: 4.5,
                          color: athleteColor,
                          strokeWidth: 1.4,
                          strokeColor: EngineRowingUI.cardFill,
                        ),
                      ),
                      belowBarData: BarAreaData(
                        show: true,
                        color: athleteColor.withValues(alpha: 0.08),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 10),
          SingleLineLegend(
            items: [
              SingleLineLegendItem(
                color: athleteColor,
                label: metricLabel,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            s.estimationNotice,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: EngineRowingUI.labelSlate,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
