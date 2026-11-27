import 'dart:math';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'app_strings.dart';
import 'engine_rowing_ui.dart';
import 'heart_rate_zones.dart';
import 'progress_calcs.dart';
import 'progress_panel.dart';

/// ويدجت منحنى نَفَس الراحة (Eupnea Curve):
/// - 3 سلاسل مستقلة غير متداخلة (قراءة 1، قراءة 2، قراءة 3) بالثواني
/// - الأقل أحسن (استشفاء أسرع)
/// - فلترة بنوع تمرين واحد + زون واحد (عبر كارفونين)
/// - خط أساس متدرج منقط (stepped dashed baseline) لكل سلسلة عبر computeBaseline
/// - أزرار إظهار/إخفاء للثلاث خطوط
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
    _selectedKind = _computeInitialKind();
    _selectedZone = _computeInitialZone();
  }

  @override
  void didUpdateWidget(covariant EupneaCurveBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    final kinds = _availableKinds;
    if (!kinds.contains(_selectedKind)) {
      _selectedKind = _computeInitialKind();
    }
  }

  String _computeInitialKind() {
    final kinds = _availableKinds;
    return kinds.isNotEmpty ? kinds.first : 'ALL';
  }

  String _computeInitialZone() {
    return 'Z2';
  }

  List<String> get _availableKinds {
    final set = <String>{};
    for (final w in widget.workouts) {
      final k = (w['kind'] as String?) ?? (w['session_kind'] as String?) ?? '';
      if (k.trim().isNotEmpty) set.add(k.trim());
    }
    final list = set.toList()..sort();
    return list.isNotEmpty ? list : ['Rowing'];
  }

  static const List<String> _availableZones = [
    'ALL',
    'Z1',
    'Z2',
    'Z3',
    'Z4',
    'Z5',
    'VO2 max',
  ];

  String _zoneForWorkout(Map<String, Object?> row) {
    final explicit = (row['zone'] as String?)?.trim();
    if (explicit != null && explicit.isNotEmpty) return explicit;
    final sessionZone = (row['session_zone'] as String?)?.trim();
    if (sessionZone != null && sessionZone.isNotEmpty) return sessionZone;

    final hrVal = (row['hr'] as num?)?.toInt();
    if (hrVal != null && hrVal > 0 && widget.mhr > widget.effectiveRhr) {
      final z = HeartRateZones.determineZone(
        hr: hrVal,
        mhr: widget.mhr,
        rhr: widget.effectiveRhr,
      );
      if (z != null) return z;
    }
    return 'NO_ZONE';
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isLoading) {
      return ProgressPanel(
        title: widget.athleteName,
        child: SizedBox(
          height: 180,
          child: Center(
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: widget.athleteColor,
            ),
          ),
        ),
      );
    }

    final startStr = ProgressCalcs.formatDateKey(widget.periodStart);
    final endStr = ProgressCalcs.formatDateKey(widget.periodEnd);

    // تصفية التمارين بنوع التمرين والزون والفترة
    final filtered = widget.workouts.where((w) {
      final dStr = ProgressCalcs.formatDateKey(w['date'] ?? '');
      if (dStr.isEmpty || dStr.compareTo(startStr) < 0 || dStr.compareTo(endStr) > 0) {
        return false;
      }
      final k = (w['kind'] as String?) ?? (w['session_kind'] as String?) ?? '';
      if (_selectedKind != 'ALL' && k.trim().toLowerCase() != _selectedKind.toLowerCase()) {
        return false;
      }
      if (_selectedZone != 'ALL') {
        final z = _zoneForWorkout(w);
        if (z.toLowerCase() != _selectedZone.toLowerCase()) {
          return false;
        }
      }
      return true;
    }).toList();

    // استخراج القراءات الثلاث كـ DateValuePoint
    final points1 = <DateValuePoint>[];
    final points2 = <DateValuePoint>[];
    final points3 = <DateValuePoint>[];

    // لتوحيد المحور السيني X عبر التواريخ المشتركة
    final dateSet = <String>{};

    for (final w in filtered) {
      final dStr = ProgressCalcs.formatDateKey(w['date'] ?? '');
      if (dStr.isEmpty) continue;
      final date = DateTime.parse(dStr);

      final e1 = (w['eupnea_1'] as num?)?.toDouble();
      final e2 = (w['eupnea_2'] as num?)?.toDouble();
      final e3 = (w['eupnea_3'] as num?)?.toDouble();

      if (e1 != null && e1 > 0) {
        points1.add(DateValuePoint(date: date, value: e1));
        dateSet.add(dStr);
      }
      if (e2 != null && e2 > 0) {
        points2.add(DateValuePoint(date: date, value: e2));
        dateSet.add(dStr);
      }
      if (e3 != null && e3 > 0) {
        points3.add(DateValuePoint(date: date, value: e3));
        dateSet.add(dStr);
      }
    }

    final sortedDates = dateSet.toList()..sort();

    // حساب خطوط الأساس لكل سلسلة (الأقل أحسن -> isHigherBetter = false)
    final baseline1 = ProgressCalcs.computeBaseline(
      workouts: filtered,
      metricKey: 'eupnea_1',
      periodStartDate: widget.periodStart,
    );

    final baseline2 = ProgressCalcs.computeBaseline(
      workouts: filtered,
      metricKey: 'eupnea_2',
      periodStartDate: widget.periodStart,
    );

    final baseline3 = ProgressCalcs.computeBaseline(
      workouts: filtered,
      metricKey: 'eupnea_3',
      periodStartDate: widget.periodStart,
    );

    // تجهيز نقاط الرسم fl_chart
    final spots1 = <FlSpot>[];
    final spots2 = <FlSpot>[];
    final spots3 = <FlSpot>[];

    double minY = double.infinity;
    double maxY = -double.infinity;

    for (int i = 0; i < sortedDates.length; i++) {
      final dStr = sortedDates[i];
      final x = i.toDouble();

      if (_showReading1) {
        final pt1 = points1.firstWhere(
          (p) => ProgressCalcs.formatDateKey(p.date) == dStr,
          orElse: () => DateValuePoint(date: DateTime.now(), value: null),
        );
        if (pt1.value != null && pt1.value! > 0) {
          spots1.add(FlSpot(x, pt1.value!));
          if (pt1.value! < minY) minY = pt1.value!;
          if (pt1.value! > maxY) maxY = pt1.value!;
        }
      }

      if (_showReading2) {
        final pt2 = points2.firstWhere(
          (p) => ProgressCalcs.formatDateKey(p.date) == dStr,
          orElse: () => DateValuePoint(date: DateTime.now(), value: null),
        );
        if (pt2.value != null && pt2.value! > 0) {
          spots2.add(FlSpot(x, pt2.value!));
          if (pt2.value! < minY) minY = pt2.value!;
          if (pt2.value! > maxY) maxY = pt2.value!;
        }
      }

      if (_showReading3) {
        final pt3 = points3.firstWhere(
          (p) => ProgressCalcs.formatDateKey(p.date) == dStr,
          orElse: () => DateValuePoint(date: DateTime.now(), value: null),
        );
        if (pt3.value != null && pt3.value! > 0) {
          spots3.add(FlSpot(x, pt3.value!));
          if (pt3.value! < minY) minY = pt3.value!;
          if (pt3.value! > maxY) maxY = pt3.value!;
        }
      }
    }

    // تضمين قيم خطوط الأساس في المدى العمودي Y
    void checkBaselineY(BaselineResult? b) {
      if (b != null && b.currentBaseline != null && b.currentBaseline! > 0) {
        if (b.currentBaseline! < minY) minY = b.currentBaseline!;
        if (b.currentBaseline! > maxY) maxY = b.currentBaseline!;
      }
    }

    if (_showReading1) checkBaselineY(baseline1);
    if (_showReading2) checkBaselineY(baseline2);
    if (_showReading3) checkBaselineY(baseline3);

    if (minY == double.infinity) {
      minY = 0;
      maxY = 120;
    } else {
      final pad = max(5.0, (maxY - minY) * 0.15);
      minY = max(0.0, minY - pad);
      maxY = maxY + pad;
    }

    final c1 = EngineRowingUI.electricCyan;
    final c2 = EngineRowingUI.flameOrange;
    final c3 = const Color(0xFFD946EF); // Fuchsia / Magenta

    final lineBars = <LineChartBarData>[];

    // خطوط الأساس المتدرجة المنقطة (Stepped dashed baselines)
    LineChartBarData buildBaselineBar(double baselineVal, Color col) {
      final pts = [
        FlSpot(0, baselineVal),
        FlSpot(max(1.0, (sortedDates.length - 1).toDouble()), baselineVal),
      ];
      return LineChartBarData(
        spots: pts,
        isCurved: false,
        color: col.withValues(alpha: 0.55),
        barWidth: 1.5,
        dashArray: [5, 4],
        dotData: const FlDotData(show: false),
      );
    }

    if (_showReading1 && baseline1.currentBaseline != null && baseline1.currentBaseline! > 0) {
      lineBars.add(buildBaselineBar(baseline1.currentBaseline!, c1));
    }
    if (_showReading2 && baseline2.currentBaseline != null && baseline2.currentBaseline! > 0) {
      lineBars.add(buildBaselineBar(baseline2.currentBaseline!, c2));
    }
    if (_showReading3 && baseline3.currentBaseline != null && baseline3.currentBaseline! > 0) {
      lineBars.add(buildBaselineBar(baseline3.currentBaseline!, c3));
    }

    // خطوط القراءات الثلاث
    if (_showReading1 && spots1.isNotEmpty) {
      lineBars.add(LineChartBarData(
        spots: spots1,
        isCurved: true,
        color: c1,
        barWidth: 2.2,
        dotData: FlDotData(
          show: true,
          getDotPainter: (spot, p, bar, idx) => FlDotCirclePainter(
            radius: 3.5,
            color: c1,
            strokeWidth: 1.5,
            strokeColor: Colors.black,
          ),
        ),
      ));
    }

    if (_showReading2 && spots2.isNotEmpty) {
      lineBars.add(LineChartBarData(
        spots: spots2,
        isCurved: true,
        color: c2,
        barWidth: 2.2,
        dotData: FlDotData(
          show: true,
          getDotPainter: (spot, p, bar, idx) => FlDotCirclePainter(
            radius: 3.5,
            color: c2,
            strokeWidth: 1.5,
            strokeColor: Colors.black,
          ),
        ),
      ));
    }

    if (_showReading3 && spots3.isNotEmpty) {
      lineBars.add(LineChartBarData(
        spots: spots3,
        isCurved: true,
        color: c3,
        barWidth: 2.2,
        dotData: FlDotData(
          show: true,
          getDotPainter: (spot, p, bar, idx) => FlDotCirclePainter(
            radius: 3.5,
            color: c3,
            strokeWidth: 1.5,
            strokeColor: Colors.black,
          ),
        ),
      ));
    }

    return ProgressPanel(
      title: widget.athleteName,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // شريط الفلاتر: نوع التمرين + الزون
          Row(
            children: [
              // اختيار نوع التمرين
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _availableKinds.contains(_selectedKind)
                          ? _selectedKind
                          : _availableKinds.first,
                      isDense: true,
                      isExpanded: true,
                      dropdownColor: EngineRowingUI.cardFill,
                      icon: const Icon(Icons.arrow_drop_down, color: Colors.white70),
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                      items: _availableKinds.map((k) {
                        return DropdownMenuItem<String>(
                          value: k,
                          child: Text(k),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) setState(() => _selectedKind = val);
                      },
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // اختيار الزون
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _selectedZone,
                      isDense: true,
                      isExpanded: true,
                      dropdownColor: EngineRowingUI.cardFill,
                      icon: const Icon(Icons.arrow_drop_down, color: Colors.white70),
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                      items: _availableZones.map((z) {
                        return DropdownMenuItem<String>(
                          value: z,
                          child: Text(z == 'ALL' ? (widget.s.isArabic ? 'كل المناطق' : 'All Zones') : z),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) setState(() => _selectedZone = val);
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // شريط أزرار إظهار / إخفاء القراءات الثلاث
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilterChip(
                label: Text(
                  widget.s.reading1Label,
                  style: TextStyle(
                    color: _showReading1 ? Colors.white : Colors.white54,
                    fontSize: 11,
                    fontWeight: _showReading1 ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
                selected: _showReading1,
                selectedColor: c1.withValues(alpha: 0.35),
                backgroundColor: Colors.white.withValues(alpha: 0.06),
                side: BorderSide(
                  color: _showReading1 ? c1 : Colors.white12,
                  width: 1,
                ),
                checkmarkColor: c1,
                onSelected: (val) => setState(() => _showReading1 = val),
              ),
              FilterChip(
                label: Text(
                  widget.s.reading2Label,
                  style: TextStyle(
                    color: _showReading2 ? Colors.white : Colors.white54,
                    fontSize: 11,
                    fontWeight: _showReading2 ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
                selected: _showReading2,
                selectedColor: c2.withValues(alpha: 0.35),
                backgroundColor: Colors.white.withValues(alpha: 0.06),
                side: BorderSide(
                  color: _showReading2 ? c2 : Colors.white12,
                  width: 1,
                ),
                checkmarkColor: c2,
                onSelected: (val) => setState(() => _showReading2 = val),
              ),
              FilterChip(
                label: Text(
                  widget.s.reading3Label,
                  style: TextStyle(
                    color: _showReading3 ? Colors.white : Colors.white54,
                    fontSize: 11,
                    fontWeight: _showReading3 ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
                selected: _showReading3,
                selectedColor: c3.withValues(alpha: 0.35),
                backgroundColor: Colors.white.withValues(alpha: 0.06),
                side: BorderSide(
                  color: _showReading3 ? c3 : Colors.white12,
                  width: 1,
                ),
                checkmarkColor: c3,
                onSelected: (val) => setState(() => _showReading3 = val),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // شارة "الأقل أحسن (استشفاء أسرع)"
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: EngineRowingUI.neonLime.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: EngineRowingUI.neonLime.withValues(alpha: 0.35),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.arrow_downward_rounded,
                  color: EngineRowingUI.neonLime,
                  size: 14,
                ),
                const SizedBox(width: 4),
                Text(
                  widget.s.eupneaLowerIsBetter,
                  style: const TextStyle(
                    color: EngineRowingUI.neonLime,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // الرسم البياني
          if (sortedDates.isEmpty || lineBars.isEmpty) ...[
            SizedBox(
              height: 120,
              child: Center(
                child: Text(
                  widget.s.insufficientData,
                  style: const TextStyle(color: Colors.white54, fontSize: 13),
                ),
              ),
            ),
          ] else ...[
            SizedBox(
              height: 180,
              child: Directionality(
                textDirection: TextDirection.ltr,
                child: LineChart(
                  LineChartData(
                    minY: minY,
                    maxY: maxY,
                    minX: 0,
                    maxX: max(1.0, (sortedDates.length - 1).toDouble()),
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
                          reservedSize: 34,
                          getTitlesWidget: (val, meta) => Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: Text(
                              '${val.round()}s',
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
                          interval: max(1.0, (sortedDates.length / 5).floorToDouble()),
                          getTitlesWidget: (val, meta) {
                            final idx = val.toInt();
                            if (idx >= 0 && idx < sortedDates.length) {
                              final d = DateTime.parse(sortedDates[idx]);
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
                widget.s.eupneaBelowBaselineNotice,
                style: const TextStyle(color: Colors.white54, fontSize: 10),
              ),
            ),
          ],

          const SizedBox(height: 6),
          Center(
            child: Text(
              widget.s.estimationNotice,
              style: const TextStyle(color: Colors.white38, fontSize: 10),
            ),
          ),
        ],
      ),
    );
  }
}
