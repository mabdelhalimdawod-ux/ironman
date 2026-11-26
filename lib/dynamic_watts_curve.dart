import 'dart:math';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'app_strings.dart';
import 'engine_rowing_ui.dart';
import 'heart_rate_zones.dart';
import 'progress_calcs.dart';
import 'progress_panel.dart';

/// ويدجت منحنى الواط الديناميكي (Dynamic Watt Curve)
/// - X: تواريخ التمارين في الفترة
/// - Y: متوسط الواط لكل تمرين
/// - كل نقطة بلون الزون الفعلي المحسوب من النبض وبجانبها رقمها
/// - خط متوسط متحرك ناعم 7 أيام (movingAverage7) بلون المنحنى بشفافية
/// - اختيار نوع تمرين واحد (الافتراضي: الأكثر تمريناً)
/// - فلتر اختياري للمنطقة التدريبية (الافتراضي "كل المناطق")
///   عند اختيار منطقة محددة: تظهر عتبة خط الأساس المنقط (step) لتلك المنطقة وتتعتم باقي النقاط
class DynamicWattsCurveWidget extends StatefulWidget {
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

  @override
  State<DynamicWattsCurveWidget> createState() =>
      _DynamicWattsCurveWidgetState();
}

class _DynamicWattsCurveWidgetState extends State<DynamicWattsCurveWidget> {
  late String _selectedKind;
  String? _selectedZone; // null يعني "كل المناطق"

  @override
  void initState() {
    super.initState();
    _selectedKind = _computeMostFrequentKind();
  }

  @override
  void didUpdateWidget(covariant DynamicWattsCurveWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    final available = _availableKinds;
    if (!available.contains(_selectedKind)) {
      _selectedKind = _computeMostFrequentKind();
    }
  }

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

  /// استخراج الواط الفعلي للتمرين:
  /// إذا كان avg_power موجوداً يُستخدم، وإذا كان ناقصاً وsplit_500 موجوداً:
  /// watts = 2.80 / (split / 500)^3
  double? _extractWatts(Map<String, Object?> w) {
    final p = (w['avg_power'] as num?)?.toDouble();
    if (p != null && p > 0) return p;

    final split = (w['split_500'] as num?)?.toDouble() ??
        (w['split'] as num?)?.toDouble();
    if (split != null && split > 0) {
      final pace = split / 500.0;
      if (pace > 0) {
        return 2.80 / (pace * pace * pace);
      }
    }
    return null;
  }

  List<({DateTime date, double watts, String zone, int index, Color color})>
      _getProcessedWorkoutPoints(List<Map<String, Object?>> source) {
    final filtered = source.where((w) {
      final k = (w['kind'] as String?)?.trim();
      return k == _selectedKind;
    }).toList();

    filtered.sort((a, b) {
      final da = (a['date'] as String?) ?? '';
      final db = (b['date'] as String?) ?? '';
      return da.compareTo(db);
    });

    final points = <({DateTime date, double watts, String zone, int index, Color color})>[];
    int idx = 1;

    for (final w in filtered) {
      final dateStr = (w['date'] as String?) ?? '';
      final d = DateTime.tryParse(dateStr);
      if (d == null) continue;

      final wVal = _extractWatts(w);
      if (wVal == null || wVal <= 0) continue;

      final rawZone = (w['zone'] as String?) ?? '';
      final zone = HeartRateZones.normalizeZoneKey(rawZone);
      final zColor = HeartRateZones.zoneColor(zone);

      points.add((
        date: d,
        watts: wVal,
        zone: zone,
        index: idx++,
        color: zColor,
      ));
    }

    return points;
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);

    return ProgressPanel(
      title: s.dynamicWattsTitle,
      leading: const Icon(Icons.flash_on_rounded,
          color: EngineRowingUI.neonLime, size: 20),
      trailing: IconButton(
        icon: const Icon(Icons.info_outline_rounded,
            color: EngineRowingUI.neonLime, size: 18),
        onPressed: () => _showWattsInfoDialog(context, s),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── شريط الفلاتر: اختيار نوع التمرين واختيار المنطقة الاختياري ──
          _buildFiltersBar(context, s),
          const SizedBox(height: 14),

          // ── الرسم البياني لمنحنى الواط الديناميكي ──
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
                dropdownColor: EngineRowingUI.bgNavy,
                isDense: true,
                isExpanded: true,
                icon: const Icon(Icons.arrow_drop_down,
                    color: EngineRowingUI.neonLime),
                items: [
                  DropdownMenuItem<String?>(
                    value: null,
                    child: Text(
                      s.allZonesLabel,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: EngineRowingUI.textWhite,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
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

  Widget _buildChartArea(BuildContext context, AppStrings s) {
    final pts = _getProcessedWorkoutPoints(widget.workouts);

    if (pts.isEmpty) {
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

    final startMs = widget.periodStart.millisecondsSinceEpoch.toDouble();
    const dayMs = 86400000.0;

    final minX = pts.map((p) => (p.date.millisecondsSinceEpoch - startMs) / dayMs).reduce(min);
    final maxX = max(
      minX + 7,
      pts.map((p) => (p.date.millisecondsSinceEpoch - startMs) / dayMs).reduce(max),
    );
    final minY = max(0.0, pts.map((p) => p.watts).reduce(min) * 0.85);
    final maxY = pts.map((p) => p.watts).reduce(max) * 1.15;

    final bars = <LineChartBarData>[];

    // 1. خط المتوسط المتحرك الناعم 7 أيام فوق النقاط
    final dateValPoints = pts
        .map((p) => DateValuePoint(date: p.date, value: p.watts))
        .toList();
    final ma7Points = ProgressCalcs.movingAverage7(dateValPoints);

    if (ma7Points.isNotEmpty) {
      final maSpots = ma7Points.map((pt) {
        final x = (pt.date.millisecondsSinceEpoch - startMs) / dayMs;
        return FlSpot(x, pt.value ?? 0.0);
      }).toList();

      bars.add(
        LineChartBarData(
          spots: maSpots,
          isCurved: true,
          curveSmoothness: 0.35,
          color: EngineRowingUI.neonLime.withValues(alpha: 0.5),
          barWidth: 2.2,
          dotData: const FlDotData(show: false),
        ),
      );
    }

    // 2. خط الأساس للزون المختار (إذا اختير زون محدد)
    if (_selectedZone != null) {
      final cleanZone = HeartRateZones.normalizeZoneKey(_selectedZone!);
      final baselineResult = ProgressCalcs.computeBaseline(
        workouts: widget.workouts.where((w) {
          final rz = (w['zone'] as String?) ?? '';
          final rk = (w['kind'] as String?) ?? '';
          return HeartRateZones.normalizeZoneKey(rz) == cleanZone &&
              rk == _selectedKind;
        }).toList(),
        metricKey: 'watts',
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
            color: HeartRateZones.zoneColor(cleanZone).withValues(alpha: 0.8),
            barWidth: 1.8,
            dotData: const FlDotData(show: false),
          ),
        );
      }
    }

    // 3. نقاط التمارين الفعلية (مصفوفة بنقاط ملونة حسب الزون)
    final workoutSpots = pts.map((p) {
      final x = (p.date.millisecondsSinceEpoch - startMs) / dayMs;
      return FlSpot(x, p.watts);
    }).toList();

    bars.add(
      LineChartBarData(
        spots: workoutSpots,
        isCurved: false,
        barWidth: 0, // إظهار النقاط فقط بدون توصيل حاد بينها
        dotData: FlDotData(
          show: true,
          getDotPainter: (spot, percent, barData, index) {
            final p = pts[index];
            final isDimmed = _selectedZone != null &&
                HeartRateZones.normalizeZoneKey(p.zone) !=
                    HeartRateZones.normalizeZoneKey(_selectedZone!);
            final c = isDimmed ? p.color.withValues(alpha: 0.25) : p.color;

            return FlDotCirclePainter(
              radius: 4.5,
              color: c,
              strokeWidth: 1.5,
              strokeColor: isDimmed
                  ? EngineRowingUI.bgNavy.withValues(alpha: 0.3)
                  : EngineRowingUI.bgNavy,
            );
          },
        ),
      ),
    );

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
                  'Watts (W)',
                  style: TextStyle(
                      fontSize: 10, color: EngineRowingUI.labelSlate),
                ),
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 34,
                  interval: max(10.0, (maxY - minY) / 4),
                  getTitlesWidget: (val, _) => Text(
                    val.round().toString(),
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
                    final match = pts.firstWhere(
                      (p) {
                        final x = (p.date.millisecondsSinceEpoch - startMs) /
                            dayMs;
                        return (x - spot.x).abs() < 0.2;
                      },
                      orElse: () => (
                        date: widget.periodStart,
                        watts: spot.y,
                        zone: 'Z2',
                        index: 0,
                        color: EngineRowingUI.neonLime,
                      ),
                    );
                    final dStr =
                        '${match.date.day}/${match.date.month}/${match.date.year}';
                    return LineTooltipItem(
                      '#${match.index} • $dStr\n${match.watts.round()} W (${match.zone})',
                      TextStyle(
                        color: match.color,
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
    return Wrap(
      spacing: 12,
      runSpacing: 6,
      alignment: WrapAlignment.center,
      children: [
        // علامة المتوسط المتحرك 7 أيام
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 14,
              height: 2.5,
              color: EngineRowingUI.neonLime.withValues(alpha: 0.6),
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                s.movingAverage7Legend,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10,
                  color: EngineRowingUI.neonLime.withValues(alpha: 0.8),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),

        // علامات الزونات
        ...HeartRateZones.orderedZones.map((z) {
          final c = HeartRateZones.zoneColor(z);
          final isSelected = _selectedZone == null ||
              HeartRateZones.normalizeZoneKey(_selectedZone!) == z;
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isSelected ? c : c.withValues(alpha: 0.25),
                ),
              ),
              const SizedBox(width: 4),
              Text(
                HeartRateZones.zoneDisplayName(z, isArabic: s.isArabic),
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: isSelected ? c : c.withValues(alpha: 0.4),
                ),
              ),
            ],
          );
        }),
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

  void _showWattsInfoDialog(BuildContext context, AppStrings s) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: EngineRowingUI.cardFill,
        title: Row(
          children: [
            const Icon(Icons.info_outline_rounded,
                color: EngineRowingUI.neonLime),
            const SizedBox(width: 8),
            Text(s.wattsCurveTitle,
                style: const TextStyle(color: EngineRowingUI.textWhite)),
          ],
        ),
        content: Text(
          s.wattsCurveDesc,
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
