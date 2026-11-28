import 'dart:math';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'app_strings.dart';
import 'engine_rowing_ui.dart';
import 'heart_rate_zones.dart';
import 'progress_calcs.dart';
import 'progress_panel.dart';
import 'scrollable_chart_container.dart';

/// ويدجت مستقلة لعرض تحليل ومنحنى التفكك القلبي الهوائي (Decoupling) لتمرين محدد
/// تستقبل نص القراءات ومدة التمرين والمنطقة التدريبية
/// وتستخدم في تبويب Progress وشاشات التدريب لاحقاً
class WorkoutDecouplingCurve extends StatelessWidget {
  final String rawReadingsText;
  final double durationMinutes;
  final String? zoneKey;
  final String? workoutDate;
  final String? athleteName;

  const WorkoutDecouplingCurve({
    super.key,
    required this.rawReadingsText,
    required this.durationMinutes,
    this.zoneKey,
    this.workoutDate,
    this.athleteName,
  });

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final calc = ProgressCalcs.calculateDecoupling(
      rawReadingsText: rawReadingsText,
      durationMinutes: durationMinutes,
      zoneKey: zoneKey,
    );

    return ProgressPanel(
      title: s.actualEfForWorkoutTitle,
      leading: const Icon(Icons.show_chart_rounded,
          color: EngineRowingUI.neonLime, size: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── رأس المعلومات والبيانات الأساسية ──
          _buildHeaderMetrics(context, s, calc),
          const SizedBox(height: 12),

          // ── تحذيرات عدد القراءات وتجاهل المدخلات الخاطئة ──
          if (calc.ignoredCount > 0)
            _buildNoticeBanner(
              icon: Icons.info_outline_rounded,
              text: s.ignoredReadingsNotice(calc.ignoredCount),
              color: Colors.amber,
            ),
          if (calc.hasFewerReadingsThanRecommended && calc.hasEnoughReadings)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: _buildNoticeBanner(
                icon: Icons.warning_amber_rounded,
                text: s.fewerReadingsThanExpectedNotice,
                color: Colors.amber,
              ),
            ),

          const SizedBox(height: 12),

          // ── محتوى الرسم البياني أو رسالة عدم كفاية البيانات ──
          if (!calc.hasEnoughReadings)
            Container(
              height: 180,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: EngineRowingUI.bgNavy.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: EngineRowingUI.bgGridLine),
              ),
              child: Text(
                calc.errorMessage ?? s.notEnoughReadingsBothHalves,
                style: const TextStyle(
                  color: EngineRowingUI.labelSlate,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
            )
          else ...[
            _buildEfMinuteChart(context, s, calc),
            const SizedBox(height: 12),
            _buildLegend(context, s, calc),
          ],

          const SizedBox(height: 10),

          // ── نص منحنى تقديري فقط ──
          Center(
            child: Text(
              s.estimatedCurveNotice,
              style: const TextStyle(
                fontSize: 12,
                color: EngineRowingUI.captionGrey,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
          const SizedBox(height: 8),

          // ── صف شارات أسماء المدخلات ──
          _buildInputChipsRow(context, s),
        ],
      ),
    );
  }

  /// كروت المؤشرات العلوية: Decoupling % وشارة التفسير ومتوسطات النصفين
  Widget _buildHeaderMetrics(
      BuildContext context, AppStrings s, DecouplingCalculationResult calc) {
    final zoneColor = zoneKey != null
        ? HeartRateZones.zoneColor(zoneKey!)
        : EngineRowingUI.neonLime;

    return Wrap(
      spacing: 10,
      runSpacing: 8,
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        // كارت Decoupling % الرئيسي
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 6,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: EngineRowingUI.equationCardFill,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: zoneColor.withValues(alpha: 0.6)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    s.chipDecoupling,
                    style: const TextStyle(
                      fontSize: 12,
                      color: EngineRowingUI.labelSlate,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    calc.decouplingPercent != null
                        ? '${calc.decouplingPercent!.toStringAsFixed(1)}%'
                        : '--',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: zoneColor,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
            _buildControlLevelBadge(context, s, calc),
          ],
        ),

        // متوسطات النصف الأول والثاني
        if (calc.hasEnoughReadings)
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _buildHalfStatCard(
                s.firstHalfLabel,
                calc.efHalf1?.toStringAsFixed(2) ?? '--',
                const Color(0xFF2979FF),
              ),
              _buildHalfStatCard(
                s.secondHalfLabel,
                calc.efHalf2?.toStringAsFixed(2) ?? '--',
                const Color(0xFFFF9100),
              ),
            ],
          ),
      ],
    );
  }

  Widget _buildControlLevelBadge(
      BuildContext context, AppStrings s, DecouplingCalculationResult calc) {
    final String label;
    final Color badgeColor;

    switch (calc.controlLevel) {
      case DecouplingControlLevel.excellent:
        label = s.decouplingExcellent;
        badgeColor = const Color(0xFF00E676);
        break;
      case DecouplingControlLevel.moderate:
        label = s.decouplingModerate;
        badgeColor = const Color(0xFFFFD600);
        break;
      case DecouplingControlLevel.high:
        label = s.decouplingHigh;
        badgeColor = const Color(0xFFFF5252);
        break;
      case DecouplingControlLevel.notEligible:
        label = s.notEligibleBadge;
        badgeColor = EngineRowingUI.captionGrey;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: badgeColor.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: badgeColor.withValues(alpha: 0.6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.shield_outlined, size: 14, color: badgeColor),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: badgeColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHalfStatCard(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: EngineRowingUI.equationCardFill,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 12, color: color),
          ),
          const SizedBox(height: 1),
          Text(
            '$value W/bpm',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: EngineRowingUI.textWhite,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoticeBanner({
    required IconData icon,
    required String text,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12,
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// الرسم البياني لمنحنى EF اللحظي لكل دقيقة
  Widget _buildEfMinuteChart(
      BuildContext context, AppStrings s, DecouplingCalculationResult calc) {
    final readings = calc.allReadings;
    if (readings.isEmpty) return const SizedBox.shrink();

    final spots = readings.map((r) => FlSpot(r.timeMinutes, r.ef)).toList();
    final minX = readings.first.timeMinutes;
    final maxX = max(readings.last.timeMinutes, durationMinutes);

    final allEf = readings.map((r) => r.ef).toList();
    final minEf = allEf.reduce(min);
    final maxEf = allEf.reduce(max);
    final minY = max(0.0, (minEf * 0.9));
    final maxY = maxEf * 1.1;

    final ef1 = calc.efHalf1 ?? 0.0;
    final ef2 = calc.efHalf2 ?? 0.0;
    final effectiveD = durationMinutes > 0 ? durationMinutes : maxX;
    final halfTime = effectiveD / 2.0;

    return ScrollableChartFrame(
      height: 240.0,
      slotsCount: max(1, readings.length),
      slotWidth: 64.0,
      minY: minY,
      maxY: maxY,
      yTicksCount: 5,
      yAxisUnitLabel: 'EF (W/bpm)',
      formatYLabel: (v) => v.toStringAsFixed(2),
      bottomReservedSize: 30.0,
      chartBuilder: (chartWidth, chartHeight) {
        return LineChart(
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
              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              bottomTitles: AxisTitles(
                axisNameWidget: const Text(
                  'Minutes (T)',
                  style: TextStyle(fontSize: 12, color: EngineRowingUI.labelSlate),
                ),
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 30,
                  interval: max(5.0, (maxX - minX) / 6),
                  getTitlesWidget: (val, _) => Text(
                    val.round().toString(),
                    style: const TextStyle(
                      fontSize: 12,
                      color: EngineRowingUI.captionGrey,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ),
              leftTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
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
            // ── خطوط متوسط EF للنصف الأول والثاني والفاصل الزمني ──
            extraLinesData: ExtraLinesData(
              verticalLines: [
                VerticalLine(
                  x: halfTime,
                  color: Colors.white38,
                  strokeWidth: 1.2,
                  dashArray: [4, 4],
                  label: VerticalLineLabel(
                    show: true,
                    alignment: Alignment.topRight,
                    padding: const EdgeInsets.only(left: 4),
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.white70,
                      fontWeight: FontWeight.bold,
                    ),
                    labelResolver: (_) => 'D/2 (${halfTime.round()}m)',
                  ),
                ),
              ],
              horizontalLines: [
                if (ef1 > 0)
                  HorizontalLine(
                    y: ef1,
                    color: const Color(0xFF2979FF),
                    strokeWidth: 1.4,
                    dashArray: [6, 4],
                    label: HorizontalLineLabel(
                      show: true,
                      alignment: Alignment.topRight,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF2979FF),
                        fontWeight: FontWeight.bold,
                      ),
                      labelResolver: (_) => 'H1: ${ef1.toStringAsFixed(2)}',
                    ),
                  ),
                if (ef2 > 0)
                  HorizontalLine(
                    y: ef2,
                    color: const Color(0xFFFF9100),
                    strokeWidth: 1.4,
                    dashArray: [6, 4],
                    label: HorizontalLineLabel(
                      show: true,
                      alignment: Alignment.bottomRight,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFFFF9100),
                        fontWeight: FontWeight.bold,
                      ),
                      labelResolver: (_) => 'H2: ${ef2.toStringAsFixed(2)}',
                    ),
                  ),
              ],
            ),
            lineTouchData: LineTouchData(
              enabled: true,
              touchTooltipData: LineTouchTooltipData(
                getTooltipColor: (_) => EngineRowingUI.bgNavy,
                getTooltipItems: (touchedSpots) {
                  return touchedSpots.map((spot) {
                    final r = readings.firstWhere(
                      (item) => (item.timeMinutes - spot.x).abs() < 0.1,
                      orElse: () => DecouplingReading(
                        watts: 0,
                        hr: 0,
                        timeMinutes: spot.x,
                      ),
                    );
                    return LineTooltipItem(
                      'T: ${spot.x.round()}m\nEF: ${spot.y.toStringAsFixed(2)}\nW: ${r.watts.round()} | HR: ${r.hr.round()}',
                      const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    );
                  }).toList();
                },
              ),
            ),
            lineBarsData: [
              // المنحنى الرئيسي الموجي لـ EF
              LineChartBarData(
                spots: spots,
                isCurved: true,
                curveSmoothness: 0.35,
                color: EngineRowingUI.neonLime,
                barWidth: 2.2,
                isStrokeCapRound: true,
                dotData: FlDotData(
                  show: true,
                  getDotPainter: (spot, percent, barData, index) {
                    return FlDotCirclePainter(
                      radius: 3.5,
                      color: EngineRowingUI.neonLime,
                      strokeWidth: 1.2,
                      strokeColor: EngineRowingUI.bgNavy,
                    );
                  },
                ),
                belowBarData: BarAreaData(
                  show: true,
                  color: EngineRowingUI.neonLime.withValues(alpha: 0.10),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLegend(
      BuildContext context, AppStrings s, DecouplingCalculationResult calc) {
    return SingleLineLegend(
      items: [
        SingleLineLegendItem(color: EngineRowingUI.neonLime, label: s.chipEF),
        SingleLineLegendItem(
            color: const Color(0xFF2979FF),
            label: s.firstHalfLabel,
            isDashed: true),
        SingleLineLegendItem(
            color: const Color(0xFFFF9100),
            label: s.secondHalfLabel,
            isDashed: true),
        const SingleLineLegendItem(
            color: Colors.white54, label: 'D/2', isDashed: true),
      ],
    );
  }

  /// صف أسماء المدخلات المشاركة فعلاً في حساب Decoupling
  Widget _buildInputChipsRow(BuildContext context, AppStrings s) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildChip(s.chipWatts),
          const SizedBox(width: 6),
          _buildChip(s.chipHR),
          const SizedBox(width: 6),
          _buildChip(s.chipTime),
          const SizedBox(width: 6),
          _buildChip(s.chipEF),
          const SizedBox(width: 6),
          _buildChip(s.chipDecoupling),
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
          fontSize: 12,
          color: EngineRowingUI.textWhite,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
