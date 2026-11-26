import 'dart:math';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'app_strings.dart';
import 'engine_rowing_ui.dart';
import 'heart_rate_zones.dart';
import 'progress_calcs.dart';
import 'progress_panel.dart';

/// ويدجت منحنى معامل الكفاءة الهوائية (EF Zone Curve)
/// - يعرض متوسط EF أسبوعي لكل منطقة تدريبية
/// - لاعب واحد: حتى سبعة خطوط ملونة حسب الزونات السبع
/// - عدة لاعبين: زون واحد يختاره المستخدم وخط لكل لاعب
/// - اختيار نوع تمرين واحد (الافتراضي: الأكثر تمريناً في الفترة)
/// - خط أساس منقط (step) بلون الزون أفتح
/// - زر "إظهار خط الأساس" / "Show baseline" إذا كان هناك أكثر من 3 خطوط زونات
class EfZoneCurveWidget extends StatefulWidget {
  final List<Map<String, Object?>> workouts;
  final DateTime periodStart;
  final DateTime periodEnd;
  final String athleteName;
  final int playerId;
  final Map<int, List<Map<String, Object?>>>? multiAthleteWorkouts; // للمقارنة بين اللاعبين
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

  @override
  State<EfZoneCurveWidget> createState() => _EfZoneCurveWidgetState();
}

class _EfZoneCurveWidgetState extends State<EfZoneCurveWidget> {
  late String _selectedKind;
  String _selectedZoneForMulti = 'Z2';
  bool _showBaseline = false;

  @override
  void initState() {
    super.initState();
    _selectedKind = _computeMostFrequentKind();
  }

  @override
  void didUpdateWidget(covariant EfZoneCurveWidget oldWidget) {
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
    final list = widget.workouts;
    for (final w in list) {
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

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);

    return ProgressPanel(
      title: s.weeklyAverageEfTitle,
      leading: const Icon(Icons.speed_rounded,
          color: EngineRowingUI.neonLime, size: 20),
      trailing: IconButton(
        icon: const Icon(Icons.info_outline_rounded,
            color: EngineRowingUI.neonLime, size: 18),
        onPressed: () => _showEfExplainerDialog(context, s),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── شريط الفلاتر: اختيار نوع التمرين والزون (في حالة عدة لاعبين) وزر خط الأساس ──
          _buildFiltersBar(context, s),
          const SizedBox(height: 14),

          // ── الرسم البياني لـ EF ──
          _buildChartArea(context, s),
          const SizedBox(height: 12),

          // ── مفتاح الألوان (Legend) ──
          _buildLegend(context, s),
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
    );
  }

  Widget _buildFiltersBar(BuildContext context, AppStrings s) {
    final kinds = _availableKinds;

    return Wrap(
      spacing: 12,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      alignment: WrapAlignment.spaceBetween,
      children: [
        // اختيار نوع التمرين (مفرد)
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 4,
          children: [
            Text(
              '${s.selectWorkoutTypePrompt}:',
              style: const TextStyle(
                fontSize: 12,
                color: EngineRowingUI.labelSlate,
                fontWeight: FontWeight.bold,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
              decoration: BoxDecoration(
                color: EngineRowingUI.equationCardFill,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: EngineRowingUI.bgGridLine),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: kinds.contains(_selectedKind) ? _selectedKind : kinds.first,
                  dropdownColor: EngineRowingUI.bgNavy,
                  isDense: true,
                  icon: const Icon(Icons.arrow_drop_down,
                      color: EngineRowingUI.neonLime),
                  items: kinds.map((k) {
                    return DropdownMenuItem<String>(
                      value: k,
                      child: Text(
                        k,
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
            ),
          ],
        ),

        // في حالة مقارنة عدة لاعبين: اختيار زون واحد فقط
        if (_isMultiAthlete)
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 4,
            children: [
              Text(
                '${s.selectZonePrompt}:',
                style: const TextStyle(
                  fontSize: 12,
                  color: EngineRowingUI.labelSlate,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                decoration: BoxDecoration(
                  color: EngineRowingUI.equationCardFill,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: EngineRowingUI.bgGridLine),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedZoneForMulti,
                    dropdownColor: EngineRowingUI.bgNavy,
                    isDense: true,
                    icon: const Icon(Icons.arrow_drop_down,
                        color: EngineRowingUI.neonLime),
                    items: HeartRateZones.orderedZones.map((z) {
                      return DropdownMenuItem<String>(
                        value: z,
                        child: Text(
                          HeartRateZones.zoneDisplayName(z, isArabic: s.isArabic),
                          style: TextStyle(
                            color: HeartRateZones.zoneColor(z),
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setState(() => _selectedZoneForMulti = val);
                      }
                    },
                  ),
                ),
              ),
            ],
          ),

        // زر إظهار / إخفاء خط الأساس
        InkWell(
          onTap: () => setState(() => _showBaseline = !_showBaseline),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: _showBaseline
                  ? EngineRowingUI.neonLime.withValues(alpha: 0.18)
                  : EngineRowingUI.equationCardFill,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: _showBaseline
                    ? EngineRowingUI.neonLime
                    : EngineRowingUI.bgGridLine,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _showBaseline
                      ? Icons.check_box_rounded
                      : Icons.check_box_outline_blank_rounded,
                  size: 15,
                  color: _showBaseline
                      ? EngineRowingUI.neonLime
                      : EngineRowingUI.labelSlate,
                ),
                const SizedBox(width: 6),
                Text(
                  _showBaseline ? s.hideBaselineAction : s.showBaselineAction,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.bold,
                    color: _showBaseline
                        ? EngineRowingUI.neonLime
                        : EngineRowingUI.textWhite,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// تجميع التمارين أسبوعياً وحساب متوسط EF لكل زون
  Map<String, List<({DateTime weekStart, double ef})>> _computeWeeklyZoneEf({
    required List<Map<String, Object?>> workouts,
  }) {
    final filtered = workouts.where((w) {
      final k = (w['kind'] as String?)?.trim();
      return k == _selectedKind;
    }).toList();

    // فرز حسب التاريخ
    filtered.sort((a, b) {
      final da = (a['date'] as String?) ?? '';
      final db = (b['date'] as String?) ?? '';
      return da.compareTo(db);
    });

    // تجميع بالزون ثم بالأسبوع
    // zone -> weekKey -> list of ef values
    final Map<String, Map<String, ({DateTime weekDate, List<double> values})>>
        zoneWeekMap = {};

    for (final z in HeartRateZones.orderedZones) {
      zoneWeekMap[z] = {};
    }

    for (final w in filtered) {
      final dateStr = (w['date'] as String?) ?? '';
      final d = DateTime.tryParse(dateStr);
      if (d == null) continue;

      final rawZone = (w['zone'] as String?) ?? '';
      final zone = HeartRateZones.normalizeZoneKey(rawZone);
      if (!zoneWeekMap.containsKey(zone)) continue;

      final efVal = (w['ef'] as num?)?.toDouble() ??
          (((w['avg_power'] as num?)?.toDouble() ?? 0.0) /
              (((w['hr'] as num?)?.toDouble() ?? 0.0) > 0
                  ? ((w['hr'] as num?)!.toDouble())
                  : 1.0));
      if (efVal <= 0) continue;

      // حساب بداية الأسبوع (السبت أو الاثنين: هنا نستخدم ترقيم الأسبوع)
      final weekStart = d.subtract(Duration(days: d.weekday % 7));
      final weekKey =
          '${weekStart.year}-${weekStart.month.toString().padLeft(2, '0')}-${weekStart.day.toString().padLeft(2, '0')}';

      final entry = zoneWeekMap[zone]!.putIfAbsent(
        weekKey,
        () => (weekDate: weekStart, values: []),
      );
      entry.values.add(efVal);
    }

    final result = <String, List<({DateTime weekStart, double ef})>>{};
    zoneWeekMap.forEach((zone, weeks) {
      final list = <({DateTime weekStart, double ef})>[];
      final sortedKeys = weeks.keys.toList()..sort();
      for (final k in sortedKeys) {
        final item = weeks[k]!;
        final avg = item.values.reduce((a, b) => a + b) / item.values.length;
        list.add((weekStart: item.weekDate, ef: avg));
      }
      result[zone] = list;
    });

    return result;
  }

  Widget _buildChartArea(BuildContext context, AppStrings s) {
    if (_isMultiAthlete) {
      return _buildMultiAthleteChart(context, s);
    }
    return _buildSingleAthleteChart(context, s);
  }

  /// رسم لاعب واحد: حتى 7 خطوط زونات
  Widget _buildSingleAthleteChart(BuildContext context, AppStrings s) {
    final weeklyMap = _computeWeeklyZoneEf(workouts: widget.workouts);

    // جمع كل النقاط لحساب الحدود
    final allSpots = <({String zone, double x, double y, DateTime date})>[];
    final activeZones = <String>[];

    // مرجع التواريخ: تحويل التاريخ إلى رقم أيام من بداية الفترة
    final startMs = widget.periodStart.millisecondsSinceEpoch.toDouble();
    const dayMs = 86400000.0;

    weeklyMap.forEach((zone, points) {
      if (points.isNotEmpty) {
        activeZones.add(zone);
        for (final pt in points) {
          final x = (pt.weekStart.millisecondsSinceEpoch - startMs) / dayMs;
          allSpots.add((zone: zone, x: x, y: pt.ef, date: pt.weekStart));
        }
      }
    });

    if (allSpots.isEmpty) {
      return Container(
        height: 220,
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
    final maxY = allSpots.map((e) => e.y).reduce(max) * 1.15;

    // خطوط الزونات
    final bars = <LineChartBarData>[];
    for (final zone in activeZones) {
      final pts = weeklyMap[zone]!;
      final spots = pts.map((pt) {
        final x = (pt.weekStart.millisecondsSinceEpoch - startMs) / dayMs;
        return FlSpot(x, pt.ef);
      }).toList();

      final zColor = HeartRateZones.zoneColor(zone);
      bars.add(
        LineChartBarData(
          spots: spots,
          isCurved: false, // كوتش: متوسط أسبوعي بدون تنعيم متحرك
          color: zColor,
          barWidth: 2.2,
          dotData: FlDotData(
            show: true,
            getDotPainter: (spot, percent, barData, index) {
              return FlDotCirclePainter(
                radius: 3.5,
                color: zColor,
                strokeWidth: 1.2,
                strokeColor: EngineRowingUI.bgNavy,
              );
            },
          ),
        ),
      );

      // خط الأساس المنقط لكل زون إذا كان مفعّلاً
      if (_showBaseline) {
        final baselineResult = ProgressCalcs.computeBaseline(
          workouts: widget.workouts.where((w) {
            final rz = (w['zone'] as String?) ?? '';
            final rk = (w['kind'] as String?) ?? '';
            return HeartRateZones.normalizeZoneKey(rz) == zone &&
                rk == _selectedKind;
          }).toList(),
          metricKey: 'ef',
          periodStartDate: widget.periodStart,
        );

        if (baselineResult.hasEnoughData && baselineResult.currentBaseline != null) {
          final baseSpots = [
            FlSpot(minX, baselineResult.currentBaseline!),
            FlSpot(maxX, baselineResult.currentBaseline!),
          ];
          bars.add(
            LineChartBarData(
              spots: baseSpots,
              isCurved: false,
              dashArray: [6, 4],
              color: zColor.withValues(alpha: 0.65),
              barWidth: 1.5,
              dotData: const FlDotData(show: false),
            ),
          );
        }
      }
    }

    return SizedBox(
      height: 240,
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
              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
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
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 34,
                  interval: max(0.1, (maxY - minY) / 4),
                  getTitlesWidget: (val, _) => Text(
                    val.toStringAsFixed(2),
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
                    final d = DateTime.fromMillisecondsSinceEpoch(
                        (startMs + spot.x * dayMs).round());
                    final dateStr = '${d.day}/${d.month}/${d.year}';
                    return LineTooltipItem(
                      '$dateStr\nEF: ${spot.y.toStringAsFixed(2)} W/bpm',
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

  /// رسم عدة لاعبين: زون واحد مختار، وخط لكل لاعب
  Widget _buildMultiAthleteChart(BuildContext context, AppStrings s) {
    final startMs = widget.periodStart.millisecondsSinceEpoch.toDouble();
    const dayMs = 86400000.0;
    final bars = <LineChartBarData>[];
    final allSpots = <({int pid, double x, double y})>[];

    final multi = widget.multiAthleteWorkouts ?? {};
    multi.forEach((pid, list) {
      final weeklyMap = _computeWeeklyZoneEf(workouts: list);
      final pts = weeklyMap[_selectedZoneForMulti] ?? [];
      if (pts.isNotEmpty) {
        final aColor = widget.athleteColors?[pid] ?? EngineRowingUI.neonLime;
        final spots = pts.map((pt) {
          final x = (pt.weekStart.millisecondsSinceEpoch - startMs) / dayMs;
          allSpots.add((pid: pid, x: x, y: pt.ef));
          return FlSpot(x, pt.ef);
        }).toList();

        bars.add(
          LineChartBarData(
            spots: spots,
            isCurved: false,
            color: aColor,
            barWidth: 2.2,
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, percent, barData, index) {
                return FlDotCirclePainter(
                  radius: 3.5,
                  color: aColor,
                  strokeWidth: 1.2,
                  strokeColor: EngineRowingUI.bgNavy,
                );
              },
            ),
          ),
        );
      }
    });

    if (allSpots.isEmpty) {
      return Container(
        height: 220,
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
    final maxY = allSpots.map((e) => e.y).reduce(max) * 1.15;

    return SizedBox(
      height: 240,
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
              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
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
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 34,
                  interval: max(0.1, (maxY - minY) / 4),
                  getTitlesWidget: (val, _) => Text(
                    val.toStringAsFixed(2),
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
                    final d = DateTime.fromMillisecondsSinceEpoch(
                        (startMs + spot.x * dayMs).round());
                    final dateStr = '${d.day}/${d.month}/${d.year}';
                    return LineTooltipItem(
                      '$dateStr\nEF: ${spot.y.toStringAsFixed(2)} W/bpm',
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

  Widget _buildLegend(BuildContext context, AppStrings s) {
    if (_isMultiAthlete) {
      final multi = widget.multiAthleteWorkouts ?? {};
      return Wrap(
        spacing: 12,
        runSpacing: 6,
        alignment: WrapAlignment.center,
        children: multi.keys.map((pid) {
          final name = widget.athleteNames?[pid] ?? '#$pid';
          final color = widget.athleteColors?[pid] ?? EngineRowingUI.neonLime;
          return _buildLegendChip(color, name);
        }).toList(),
      );
    }

    return Wrap(
      spacing: 10,
      runSpacing: 6,
      alignment: WrapAlignment.center,
      children: HeartRateZones.orderedZones.map((z) {
        final color = HeartRateZones.zoneColor(z);
        final name = HeartRateZones.zoneDisplayName(z, isArabic: s.isArabic);
        return _buildLegendChip(color, name);
      }).toList(),
    );
  }

  Widget _buildLegendChip(Color color, String name) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 3,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          name,
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
            color: color,
          ),
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
          _buildChip(s.chipWatts),
          const SizedBox(width: 6),
          _buildChip(s.chipHR),
          const SizedBox(width: 6),
          _buildChip(s.chipTime),
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

  void _showEfExplainerDialog(BuildContext context, AppStrings s) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: EngineRowingUI.cardFill,
        title: Row(
          children: [
            const Icon(Icons.info_outline_rounded,
                color: EngineRowingUI.neonLime),
            const SizedBox(width: 8),
            Text(s.efTitle,
                style: const TextStyle(color: EngineRowingUI.textWhite)),
          ],
        ),
        content: Text(
          s.efExplanation,
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
