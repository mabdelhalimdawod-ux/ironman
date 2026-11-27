import 'dart:math';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'app_strings.dart';
import 'engine_rowing_ui.dart';
import 'progress_calcs.dart';
import 'progress_panel.dart';

/// ويدجت منحنى HRV مع المتوسط المتحرك وحزام التغير الأدنى ذي المعنى (SWC)
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
    if (isLoading) {
      return ProgressPanel(
        title: athleteName,
        child: SizedBox(
          height: 160,
          child: Center(
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: athleteColor,
            ),
          ),
        ),
      );
    }

    final validPoints = points.where((p) => p.value != null && p.value! > 0).toList();
    if (validPoints.length < 2) {
      return ProgressPanel(
        title: athleteName,
        child: SizedBox(
          height: 120,
          child: Center(
            child: Text(
              s.insufficientData,
              style: const TextStyle(color: Colors.white54, fontSize: 13),
            ),
          ),
        ),
      );
    }

    final maPoints = ProgressCalcs.movingAverage7(validPoints);

    // حساب حزام SWC لكل يوم به قيمة MA7
    final upperSwcSpots = <FlSpot>[];
    final lowerSwcSpots = <FlSpot>[];
    final dailySpots = <FlSpot>[];
    final maSpots = <FlSpot>[];

    double minY = double.infinity;
    double maxY = -double.infinity;

    for (int i = 0; i < validPoints.length; i++) {
      final p = validPoints[i];
      final x = i.toDouble();
      final y = p.value!;
      dailySpots.add(FlSpot(x, y));
      if (y < minY) minY = y;
      if (y > maxY) maxY = y;

      final ma = maPoints.firstWhere(
        (m) =>
            m.date.year == p.date.year &&
            m.date.month == p.date.month &&
            m.date.day == p.date.day,
        orElse: () => DateValuePoint(date: p.date, value: null),
      );

      if (ma.value != null && ma.value! > 0) {
        maSpots.add(FlSpot(x, ma.value!));
        if (ma.value! < minY) minY = ma.value!;
        if (ma.value! > maxY) maxY = ma.value!;

        final swc = ProgressCalcs.calcHrvSwcBand(
          targetDate: p.date,
          hrvPoints: validPoints,
          ma7Value: ma.value,
        );

        if (swc.upper != null && swc.lower != null) {
          upperSwcSpots.add(FlSpot(x, swc.upper!));
          lowerSwcSpots.add(FlSpot(x, swc.lower!));
          if (swc.upper! > maxY) maxY = swc.upper!;
          if (swc.lower! < minY) minY = swc.lower!;
        }
      }
    }

    if (minY == double.infinity) {
      minY = 0;
      maxY = 100;
    } else {
      final pad = max(5.0, (maxY - minY) * 0.15);
      minY = max(0.0, minY - pad);
      maxY = maxY + pad;
    }

    final lineBars = <LineChartBarData>[];

    // خطوط حزام SWC (Upper & Lower)
    int? upperIndex;
    int? lowerIndex;
    if (upperSwcSpots.length >= 2 && lowerSwcSpots.length >= 2) {
      upperIndex = lineBars.length;
      lineBars.add(LineChartBarData(
        spots: upperSwcSpots,
        isCurved: true,
        color: EngineRowingUI.neonLime.withValues(alpha: 0.5),
        barWidth: 1.2,
        dashArray: [4, 4],
        dotData: const FlDotData(show: false),
      ));

      lowerIndex = lineBars.length;
      lineBars.add(LineChartBarData(
        spots: lowerSwcSpots,
        isCurved: true,
        color: EngineRowingUI.neonLime.withValues(alpha: 0.5),
        barWidth: 1.2,
        dashArray: [4, 4],
        dotData: const FlDotData(show: false),
      ));
    }

    // خط المتوسط المتحرك 7 أيام
    if (maSpots.length >= 2) {
      lineBars.add(LineChartBarData(
        spots: maSpots,
        isCurved: true,
        color: Colors.white.withValues(alpha: 0.85),
        barWidth: 2.2,
        dotData: const FlDotData(show: false),
      ));
    }

    // خط القراءات اليومية
    lineBars.add(LineChartBarData(
      spots: dailySpots,
      isCurved: true,
      color: athleteColor,
      barWidth: 2.5,
      isStrokeCapRound: true,
      dotData: FlDotData(
        show: true,
        getDotPainter: (spot, percent, barData, index) =>
            FlDotCirclePainter(
          radius: 3.5,
          color: athleteColor,
          strokeWidth: 1.5,
          strokeColor: Colors.black,
        ),
      ),
      belowBarData: BarAreaData(
        show: true,
        color: athleteColor.withValues(alpha: 0.08),
      ),
    ));

    return ProgressPanel(
      title: athleteName,
      trailing: Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          _LegendChip(
            label: s.hrvTitle,
            color: athleteColor,
          ),
          _LegendChip(
            label: s.ma7Label,
            color: Colors.white70,
          ),
          if (upperIndex != null)
            _LegendChip(
              label: s.swcBandLegend,
              color: EngineRowingUI.neonLime,
              isDashed: true,
            ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          SizedBox(
            height: 180,
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: LineChart(
                LineChartData(
                  minY: minY,
                  maxY: maxY,
                  minX: 0,
                  maxX: max(1.0, (validPoints.length - 1).toDouble()),
                  betweenBarsData: (upperIndex != null && lowerIndex != null)
                      ? [
                          BetweenBarsData(
                            fromIndex: upperIndex,
                            toIndex: lowerIndex,
                            color: EngineRowingUI.neonLime.withValues(alpha: 0.10),
                          ),
                        ]
                      : const [],
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: max(5.0, (maxY - minY) / 4),
                    getDrawingHorizontalLine: (value) => FlLine(
                      color: Colors.white10,
                      strokeWidth: 1,
                    ),
                  ),
                  titlesData: FlTitlesData(
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 38,
                        getTitlesWidget: (val, meta) => Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: Text(
                            '${val.round()}',
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 10,
                            ),
                            textAlign: TextAlign.end,
                          ),
                        ),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 22,
                        interval: max(1.0, (validPoints.length / 5).floorToDouble()),
                        getTitlesWidget: (val, meta) {
                          final idx = val.toInt();
                          if (idx >= 0 && idx < validPoints.length) {
                            final d = validPoints[idx].date;
                            return Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                '${d.day}/${d.month}',
                                style: const TextStyle(
                                  color: Colors.white38,
                                  fontSize: 10,
                                ),
                              ),
                            );
                          }
                          return const SizedBox.shrink();
                        },
                      ),
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  lineBarsData: lineBars,
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Center(
            child: Text(
              s.estimationNotice,
              style: const TextStyle(color: Colors.white38, fontSize: 10),
            ),
          ),
        ],
      ),
    );
  }
}

/// ويدجت منحنى نبض الراحة RHR مع المتوسط المتحرك وتنبيه الارتفاع (+5 نبضات)
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
    if (isLoading) {
      return ProgressPanel(
        title: athleteName,
        child: SizedBox(
          height: 160,
          child: Center(
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: athleteColor,
            ),
          ),
        ),
      );
    }

    final validPoints = points.where((p) => p.value != null && p.value! > 0).toList();
    if (validPoints.length < 2) {
      return ProgressPanel(
        title: athleteName,
        child: SizedBox(
          height: 120,
          child: Center(
            child: Text(
              s.insufficientData,
              style: const TextStyle(color: Colors.white54, fontSize: 13),
            ),
          ),
        ),
      );
    }

    final maPoints = ProgressCalcs.movingAverage7(validPoints);

    // فحص تنبيه ارتفاع نبض الراحة لليوم (آخر قراءة متوفرة)
    final latestPoint = validPoints.last;
    final latestMa = maPoints.firstWhere(
      (m) =>
          m.date.year == latestPoint.date.year &&
          m.date.month == latestPoint.date.month &&
          m.date.day == latestPoint.date.day,
      orElse: () => DateValuePoint(date: latestPoint.date, value: null),
    );

    final isElevated = ProgressCalcs.isRhrElevated(
      todayRhr: latestPoint.value,
      ma7Rhr: latestMa.value,
    );

    final dailySpots = <FlSpot>[];
    final maSpots = <FlSpot>[];
    double minY = double.infinity;
    double maxY = -double.infinity;

    for (int i = 0; i < validPoints.length; i++) {
      final p = validPoints[i];
      final x = i.toDouble();
      final y = p.value!;
      dailySpots.add(FlSpot(x, y));
      if (y < minY) minY = y;
      if (y > maxY) maxY = y;

      final ma = maPoints.firstWhere(
        (m) =>
            m.date.year == p.date.year &&
            m.date.month == p.date.month &&
            m.date.day == p.date.day,
        orElse: () => DateValuePoint(date: p.date, value: null),
      );

      if (ma.value != null && ma.value! > 0) {
        maSpots.add(FlSpot(x, ma.value!));
        if (ma.value! < minY) minY = ma.value!;
        if (ma.value! > maxY) maxY = ma.value!;
      }
    }

    if (minY == double.infinity) {
      minY = 40;
      maxY = 100;
    } else {
      final pad = max(3.0, (maxY - minY) * 0.15);
      minY = max(30.0, minY - pad);
      maxY = maxY + pad;
    }

    final lineBars = <LineChartBarData>[];

    // خط المتوسط المتحرك 7 أيام
    if (maSpots.length >= 2) {
      lineBars.add(LineChartBarData(
        spots: maSpots,
        isCurved: true,
        color: Colors.white.withValues(alpha: 0.85),
        barWidth: 2.2,
        dotData: const FlDotData(show: false),
      ));
    }

    // خط النبض اليومي
    lineBars.add(LineChartBarData(
      spots: dailySpots,
      isCurved: true,
      color: athleteColor,
      barWidth: 2.5,
      isStrokeCapRound: true,
      dotData: FlDotData(
        show: true,
        getDotPainter: (spot, percent, barData, index) =>
            FlDotCirclePainter(
          radius: 3.5,
          color: athleteColor,
          strokeWidth: 1.5,
          strokeColor: Colors.black,
        ),
      ),
      belowBarData: BarAreaData(
        show: true,
        color: athleteColor.withValues(alpha: 0.08),
      ),
    ));

    return ProgressPanel(
      title: athleteName,
      trailing: Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          _LegendChip(
            label: s.rhrTitle,
            color: athleteColor,
          ),
          _LegendChip(
            label: s.ma7Label,
            color: Colors.white70,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (isElevated) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Colors.amber.withValues(alpha: 0.6),
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded,
                      color: Colors.amber, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      s.rhrElevatedAlert,
                      style: const TextStyle(
                        color: Colors.amber,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          SizedBox(
            height: 180,
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: LineChart(
                LineChartData(
                  minY: minY,
                  maxY: maxY,
                  minX: 0,
                  maxX: max(1.0, (validPoints.length - 1).toDouble()),
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: max(4.0, (maxY - minY) / 4),
                    getDrawingHorizontalLine: (value) => FlLine(
                      color: Colors.white10,
                      strokeWidth: 1,
                    ),
                  ),
                  titlesData: FlTitlesData(
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 34,
                        getTitlesWidget: (val, meta) => Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: Text(
                            '${val.round()}',
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 10,
                            ),
                            textAlign: TextAlign.end,
                          ),
                        ),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 22,
                        interval: max(1.0, (validPoints.length / 5).floorToDouble()),
                        getTitlesWidget: (val, meta) {
                          final idx = val.toInt();
                          if (idx >= 0 && idx < validPoints.length) {
                            final d = validPoints[idx].date;
                            return Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                '${d.day}/${d.month}',
                                style: const TextStyle(
                                  color: Colors.white38,
                                  fontSize: 10,
                                ),
                              ),
                            );
                          }
                          return const SizedBox.shrink();
                        },
                      ),
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  lineBarsData: lineBars,
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Center(
            child: Text(
              s.estimationNotice,
              style: const TextStyle(color: Colors.white38, fontSize: 10),
            ),
          ),
        ],
      ),
    );
  }
}

/// ويدجت منحنى ساعات النوم مع المتوسط المتحرك 7 أيام
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
    if (isLoading) {
      return ProgressPanel(
        title: athleteName,
        child: SizedBox(
          height: 160,
          child: Center(
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: athleteColor,
            ),
          ),
        ),
      );
    }

    final validPoints = points.where((p) => p.value != null && p.value! > 0).toList();
    if (validPoints.length < 2) {
      return ProgressPanel(
        title: athleteName,
        child: SizedBox(
          height: 120,
          child: Center(
            child: Text(
              s.insufficientData,
              style: const TextStyle(color: Colors.white54, fontSize: 13),
            ),
          ),
        ),
      );
    }

    final maPoints = ProgressCalcs.movingAverage7(validPoints);
    final dailySpots = <FlSpot>[];
    final maSpots = <FlSpot>[];
    double minY = double.infinity;
    double maxY = -double.infinity;

    for (int i = 0; i < validPoints.length; i++) {
      final p = validPoints[i];
      final x = i.toDouble();
      final y = p.value!;
      dailySpots.add(FlSpot(x, y));
      if (y < minY) minY = y;
      if (y > maxY) maxY = y;

      final ma = maPoints.firstWhere(
        (m) =>
            m.date.year == p.date.year &&
            m.date.month == p.date.month &&
            m.date.day == p.date.day,
        orElse: () => DateValuePoint(date: p.date, value: null),
      );

      if (ma.value != null && ma.value! > 0) {
        maSpots.add(FlSpot(x, ma.value!));
        if (ma.value! < minY) minY = ma.value!;
        if (ma.value! > maxY) maxY = ma.value!;
      }
    }

    if (minY == double.infinity) {
      minY = 0;
      maxY = 12;
    } else {
      final pad = max(1.0, (maxY - minY) * 0.15);
      minY = max(0.0, minY - pad);
      maxY = maxY + pad;
    }

    final lineBars = <LineChartBarData>[];

    if (maSpots.length >= 2) {
      lineBars.add(LineChartBarData(
        spots: maSpots,
        isCurved: true,
        color: Colors.white.withValues(alpha: 0.85),
        barWidth: 2.2,
        dotData: const FlDotData(show: false),
      ));
    }

    lineBars.add(LineChartBarData(
      spots: dailySpots,
      isCurved: true,
      color: athleteColor,
      barWidth: 2.5,
      isStrokeCapRound: true,
      dotData: FlDotData(
        show: true,
        getDotPainter: (spot, percent, barData, index) =>
            FlDotCirclePainter(
          radius: 3.5,
          color: athleteColor,
          strokeWidth: 1.5,
          strokeColor: Colors.black,
        ),
      ),
      belowBarData: BarAreaData(
        show: true,
        color: athleteColor.withValues(alpha: 0.08),
      ),
    ));

    return ProgressPanel(
      title: athleteName,
      trailing: Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          _LegendChip(
            label: '${s.chipSleep} (hrs)',
            color: athleteColor,
          ),
          _LegendChip(
            label: s.ma7Label,
            color: Colors.white70,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          SizedBox(
            height: 180,
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: LineChart(
                LineChartData(
                  minY: minY,
                  maxY: maxY,
                  minX: 0,
                  maxX: max(1.0, (validPoints.length - 1).toDouble()),
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: max(1.0, (maxY - minY) / 4),
                    getDrawingHorizontalLine: (value) => FlLine(
                      color: Colors.white10,
                      strokeWidth: 1,
                    ),
                  ),
                  titlesData: FlTitlesData(
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 32,
                        getTitlesWidget: (val, meta) => Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: Text(
                            val.toStringAsFixed(1),
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 10,
                            ),
                            textAlign: TextAlign.end,
                          ),
                        ),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 22,
                        interval: max(1.0, (validPoints.length / 5).floorToDouble()),
                        getTitlesWidget: (val, meta) {
                          final idx = val.toInt();
                          if (idx >= 0 && idx < validPoints.length) {
                            final d = validPoints[idx].date;
                            return Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                '${d.day}/${d.month}',
                                style: const TextStyle(
                                  color: Colors.white38,
                                  fontSize: 10,
                                ),
                              ),
                            );
                          }
                          return const SizedBox.shrink();
                        },
                      ),
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  lineBarsData: lineBars,
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Center(
            child: Text(
              s.estimationNotice,
              style: const TextStyle(color: Colors.white38, fontSize: 10),
            ),
          ),
        ],
      ),
    );
  }
}

/// ويدجت منحنى الوزن مع المتوسط المتحرك 7 أيام (عرض فقط)
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
    if (isLoading) {
      return ProgressPanel(
        title: athleteName,
        child: SizedBox(
          height: 160,
          child: Center(
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: athleteColor,
            ),
          ),
        ),
      );
    }

    final validPoints = points.where((p) => p.value != null && p.value! > 0).toList();
    if (validPoints.length < 2) {
      return ProgressPanel(
        title: athleteName,
        child: SizedBox(
          height: 120,
          child: Center(
            child: Text(
              s.insufficientData,
              style: const TextStyle(color: Colors.white54, fontSize: 13),
            ),
          ),
        ),
      );
    }

    final maPoints = ProgressCalcs.movingAverage7(validPoints);
    final dailySpots = <FlSpot>[];
    final maSpots = <FlSpot>[];
    double minY = double.infinity;
    double maxY = -double.infinity;

    for (int i = 0; i < validPoints.length; i++) {
      final p = validPoints[i];
      final x = i.toDouble();
      final y = p.value!;
      dailySpots.add(FlSpot(x, y));
      if (y < minY) minY = y;
      if (y > maxY) maxY = y;

      final ma = maPoints.firstWhere(
        (m) =>
            m.date.year == p.date.year &&
            m.date.month == p.date.month &&
            m.date.day == p.date.day,
        orElse: () => DateValuePoint(date: p.date, value: null),
      );

      if (ma.value != null && ma.value! > 0) {
        maSpots.add(FlSpot(x, ma.value!));
        if (ma.value! < minY) minY = ma.value!;
        if (ma.value! > maxY) maxY = ma.value!;
      }
    }

    if (minY == double.infinity) {
      minY = 50;
      maxY = 100;
    } else {
      final pad = max(1.0, (maxY - minY) * 0.15);
      minY = max(30.0, minY - pad);
      maxY = maxY + pad;
    }

    final lineBars = <LineChartBarData>[];

    if (maSpots.length >= 2) {
      lineBars.add(LineChartBarData(
        spots: maSpots,
        isCurved: true,
        color: Colors.white.withValues(alpha: 0.85),
        barWidth: 2.2,
        dotData: const FlDotData(show: false),
      ));
    }

    lineBars.add(LineChartBarData(
      spots: dailySpots,
      isCurved: true,
      color: athleteColor,
      barWidth: 2.5,
      isStrokeCapRound: true,
      dotData: FlDotData(
        show: true,
        getDotPainter: (spot, percent, barData, index) =>
            FlDotCirclePainter(
          radius: 3.5,
          color: athleteColor,
          strokeWidth: 1.5,
          strokeColor: Colors.black,
        ),
      ),
      belowBarData: BarAreaData(
        show: true,
        color: athleteColor.withValues(alpha: 0.08),
      ),
    ));

    return ProgressPanel(
      title: athleteName,
      trailing: Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          _LegendChip(
            label: '${s.chipWeight} (kg)',
            color: athleteColor,
          ),
          _LegendChip(
            label: s.ma7Label,
            color: Colors.white70,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          SizedBox(
            height: 180,
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: LineChart(
                LineChartData(
                  minY: minY,
                  maxY: maxY,
                  minX: 0,
                  maxX: max(1.0, (validPoints.length - 1).toDouble()),
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: max(1.0, (maxY - minY) / 4),
                    getDrawingHorizontalLine: (value) => FlLine(
                      color: Colors.white10,
                      strokeWidth: 1,
                    ),
                  ),
                  titlesData: FlTitlesData(
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 34,
                        getTitlesWidget: (val, meta) => Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: Text(
                            val.toStringAsFixed(1),
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 10,
                            ),
                            textAlign: TextAlign.end,
                          ),
                        ),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 22,
                        interval: max(1.0, (validPoints.length / 5).floorToDouble()),
                        getTitlesWidget: (val, meta) {
                          final idx = val.toInt();
                          if (idx >= 0 && idx < validPoints.length) {
                            final d = validPoints[idx].date;
                            return Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                '${d.day}/${d.month}',
                                style: const TextStyle(
                                  color: Colors.white38,
                                  fontSize: 10,
                                ),
                              ),
                            );
                          }
                          return const SizedBox.shrink();
                        },
                      ),
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  lineBarsData: lineBars,
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Center(
            child: Text(
              s.estimationNotice,
              style: const TextStyle(color: Colors.white38, fontSize: 10),
            ),
          ),
        ],
      ),
    );
  }
}

class _LegendChip extends StatelessWidget {
  final String label;
  final Color color;
  final bool isDashed;

  const _LegendChip({
    required this.label,
    required this.color,
    this.isDashed = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 3,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(1.5),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            color: color.withValues(alpha: 0.9),
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
