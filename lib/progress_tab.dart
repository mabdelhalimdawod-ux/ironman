import 'dart:math';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'app_strings.dart';
import 'auth_service.dart';
import 'db.dart';
import 'engine_rowing_ui.dart';
import 'heart_rate_zones.dart';
import 'progress_calcs.dart';
import 'progress_panel.dart';

/// تبويب التقدم والتحليلات (Progress Tab)
/// يعرض مؤشرات الأداء الفسيولوجي، مخطط إدارة الأداء (PMC)،
/// خط الأساس ومراقبة الزونات السبعة، ومنحنيات التطور الزمني.
class ProgressTab extends StatefulWidget {
  final AppUser? user;

  const ProgressTab({super.key, this.user});

  @override
  State<ProgressTab> createState() => _ProgressTabState();
}

class _ProgressTabState extends State<ProgressTab> {
  bool _loading = true;
  List<Map<String, Object?>> _players = [];
  int? _selectedPlayerId;
  String _selectedFilter = '30D'; // '7D', '30D', '90D', 'All'

  // ── نقاط المنحنيات ──
  List<DateValuePoint> _ctlPoints = [];
  List<DateValuePoint> _atlPoints = [];
  List<DateValuePoint> _tsbPoints = [];
  double _currentCTL = 0.0;
  double _currentATL = 0.0;
  double _currentTSB = 0.0;

  Map<String, ZoneBaseline> _zoneBaselines = {};
  final Map<String, List<DateValuePoint>> _zoneWattsPoints = {};
  final Map<String, List<DateValuePoint>> _zoneSplitPoints = {};
  final Map<String, List<DateValuePoint>> _zoneDecouplingPoints = {};

  List<DateValuePoint> _hrvPoints = [];
  List<DateValuePoint> _rhrPoints = [];
  List<DateValuePoint> _sleepPoints = [];
  List<DateValuePoint> _weightPoints = [];
  List<DateValuePoint> _eupneaPoints = [];
  List<DateValuePoint> _decouplingPoints = [];
  List<DateValuePoint> _efPoints = [];

  bool _hasIncompleteInputs = true;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    setState(() => _loading = true);
    try {
      await DB.db;
      final players = await DB.players();
      _players = players;

      if (widget.user != null && widget.user!.isAthlete) {
        _selectedPlayerId = widget.user!.id;
      } else if (_players.isNotEmpty && _selectedPlayerId == null) {
        _selectedPlayerId = _players.first['id'] as int?;
      }

      await _fetchDataForSelection();
    } catch (_) {
      // تجاهل أخطاء التهيئة العابرة
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  int _getFilterDays() {
    switch (_selectedFilter) {
      case '7D':
        return 7;
      case '30D':
        return 30;
      case '90D':
        return 90;
      case 'All':
      default:
        return 365;
    }
  }

  Future<void> _fetchDataForSelection() async {
    if (_selectedPlayerId == null) {
      _hasIncompleteInputs = true;
      return;
    }

    final limitDays = _getFilterDays();
    final logs = await DB.playerLogs(_selectedPlayerId!, limit: limitDays);

    _hasIncompleteInputs = logs.isEmpty ||
        logs.any((l) =>
            l['rhr'] == null || l['hrv'] == null || l['avg_power'] == null);

    // 1. حساب خط الأساس لكل زون
    _zoneBaselines = ProgressCalcs.computeZoneBaselines(logs);

    // 2. إعداد نقاط المنحنيات الفسيولوجية
    final Map<String, List<double>> hrvByDate = {};
    final Map<String, List<double>> rhrByDate = {};
    final Map<String, List<double>> sleepByDate = {};
    final Map<String, List<double>> weightByDate = {};
    final Map<String, List<double>> eupneaByDate = {};
    final Map<String, List<double>> decouplingByDate = {};
    final Map<String, List<double>> efByDate = {};

    final Map<String, Map<String, List<double>>> zoneWattsByDate = {
      for (final z in HeartRateZones.orderedZones) z: {},
    };
    final Map<String, Map<String, List<double>>> zoneSplitByDate = {
      for (final z in HeartRateZones.orderedZones) z: {},
    };
    final Map<String, Map<String, List<double>>> zoneDecouplingByDate = {
      for (final z in HeartRateZones.orderedZones) z: {},
    };

    final List<Map<String, dynamic>> dailyTssInput = [];

    for (final r in logs) {
      final dateStr = r['date'] as String?;
      if (dateStr == null) continue;

      final date = DateTime.tryParse(dateStr);
      if (date == null) continue;

      final rhr = (r['rhr'] as num?)?.toDouble();
      final hrv = (r['hrv'] as num?)?.toDouble();
      final sleep = (r['sleep_hours'] as num?)?.toDouble();
      final weight = (r['weight'] as num?)?.toDouble();
      final eupnea = (r['eupnea'] as num?)?.toDouble();
      final decoupling = (r['decoupling'] as num?)?.toDouble();
      final ef = (r['ef'] as num?)?.toDouble();
      final watts = (r['avg_power'] as num?)?.toDouble();
      final split = (r['split_500'] as num?)?.toDouble();
      final dur = (r['duration_seconds'] as num?)?.toInt() ?? 0;
      final actualZone = r['zone'] as String?;

      if (rhr != null && rhr > 0) rhrByDate.putIfAbsent(dateStr, () => []).add(rhr);
      if (hrv != null && hrv > 0) hrvByDate.putIfAbsent(dateStr, () => []).add(hrv);
      if (sleep != null && sleep > 0) sleepByDate.putIfAbsent(dateStr, () => []).add(sleep);
      if (weight != null && weight > 0) weightByDate.putIfAbsent(dateStr, () => []).add(weight);
      if (eupnea != null && eupnea > 0) eupneaByDate.putIfAbsent(dateStr, () => []).add(eupnea);
      if (decoupling != null && decoupling > 0) decouplingByDate.putIfAbsent(dateStr, () => []).add(decoupling);
      if (ef != null && ef > 0) efByDate.putIfAbsent(dateStr, () => []).add(ef);

      if (actualZone != null) {
        final normZone = HeartRateZones.normalizeZoneKey(actualZone);
        if (watts != null && watts > 0 && zoneWattsByDate.containsKey(normZone)) {
          zoneWattsByDate[normZone]!.putIfAbsent(dateStr, () => []).add(watts);
        }
        if (split != null && split > 0 && zoneSplitByDate.containsKey(normZone)) {
          zoneSplitByDate[normZone]!.putIfAbsent(dateStr, () => []).add(split);
        }
        if (decoupling != null && decoupling > 0 && zoneDecouplingByDate.containsKey(normZone)) {
          zoneDecouplingByDate[normZone]!.putIfAbsent(dateStr, () => []).add(decoupling);
        }
      }

      // TSS
      if (watts != null && watts > 0 && dur > 0) {
        final cp = await DB.playerCP(_selectedPlayerId!) ?? 250.0;
        final tss = calculateTSS(avgPower: watts, durationSeconds: dur, cp: cp);
        dailyTssInput.add({'date': date, 'tss': tss});
      }
    }

    List<DateValuePoint> mapToPoints(Map<String, List<double>> data) {
      final sortedKeys = data.keys.toList()..sort();
      return sortedKeys.map((k) {
        final vals = data[k]!;
        final avg = vals.reduce((a, b) => a + b) / vals.length;
        return DateValuePoint(
          date: DateTime.parse(k),
          value: double.parse(avg.toStringAsFixed(1)),
        );
      }).toList();
    }

    _hrvPoints = mapToPoints(hrvByDate);
    _rhrPoints = mapToPoints(rhrByDate);
    _sleepPoints = mapToPoints(sleepByDate);
    _weightPoints = mapToPoints(weightByDate);
    _eupneaPoints = mapToPoints(eupneaByDate);
    _decouplingPoints = mapToPoints(decouplingByDate);
    _efPoints = mapToPoints(efByDate);

    _zoneWattsPoints.clear();
    _zoneSplitPoints.clear();
    _zoneDecouplingPoints.clear();
    for (final z in HeartRateZones.orderedZones) {
      _zoneWattsPoints[z] = mapToPoints(zoneWattsByDate[z] ?? {});
      _zoneSplitPoints[z] = mapToPoints(zoneSplitByDate[z] ?? {});
      _zoneDecouplingPoints[z] = mapToPoints(zoneDecouplingByDate[z] ?? {});
    }

    // 3. حسابات PMC
    final pmcResult = ProgressCalcs.calculatePMC(dailyTssList: dailyTssInput);
    _ctlPoints = (pmcResult['ctlPoints'] as List<dynamic>?)?.cast<DateValuePoint>() ?? [];
    _atlPoints = (pmcResult['atlPoints'] as List<dynamic>?)?.cast<DateValuePoint>() ?? [];
    _tsbPoints = (pmcResult['tsbPoints'] as List<dynamic>?)?.cast<DateValuePoint>() ?? [];
    _currentCTL = (pmcResult['currentCTL'] as num?)?.toDouble() ?? 0.0;
    _currentATL = (pmcResult['currentATL'] as num?)?.toDouble() ?? 0.0;
    _currentTSB = (pmcResult['currentTSB'] as num?)?.toDouble() ?? 0.0;
  }

  void _showInfoDialog(String title, String explanation) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: EngineRowingUI.cardFill,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: EngineRowingUI.neonLime, width: 1.0),
        ),
        title: Row(
          children: [
            const Icon(Icons.info_outline_rounded,
                color: EngineRowingUI.neonLime, size: 22),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
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
          explanation,
          style: const TextStyle(
            color: EngineRowingUI.labelSlate,
            fontSize: 14,
            height: 1.5,
          ),
        ),
        actions: [
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: EngineRowingUI.neonLime,
              foregroundColor: EngineRowingUI.bgNavy,
            ),
            onPressed: () => Navigator.pop(ctx),
            child: Text(AppStrings.of(context).close),
          ),
        ],
      ),
    );
  }

  String _formatSplit(double seconds) {
    if (seconds <= 0) return '--';
    final mins = (seconds / 60).floor();
    final secs = seconds - mins * 60;
    return '$mins:${secs.toStringAsFixed(1).padLeft(4, '0')}';
  }

  MetricTrendDirection _toDir(ProgressTrend t) {
    switch (t) {
      case ProgressTrend.up:
        return MetricTrendDirection.up;
      case ProgressTrend.down:
        return MetricTrendDirection.down;
      case ProgressTrend.neutral:
        return MetricTrendDirection.neutral;
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);

    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: EngineRowingUI.neonLime),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── 1. رأس الصفحة (العنوان + اختيار اللاعب والفلتر) ──
          _buildHeaderSection(s),
          const SizedBox(height: 12),

          // ── 2. شريط تحذير استكمال المدخلات ──
          if (_hasIncompleteInputs) ...[
            _buildWarningBanner(s),
            const SizedBox(height: 12),
          ],

          // ── 3. قسم مخطط إدارة الأداء PMC ──
          _buildPmcSection(s),
          const SizedBox(height: 14),

          // ── 4. قسم خط الأساس ومراقبة الزونات السبعة ──
          _buildZoneBaselinesSection(s),
          const SizedBox(height: 14),

          // ── 5. قسم المنحنيات الفسيولوجية ومنحنيات الزونات ──
          _buildCurvesSection(s),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════
  // 1. قسم الرأس والفلترة واختيار اللاعب
  // ════════════════════════════════════════════════════════════════
  Widget _buildHeaderSection(AppStrings s) {
    final isAthlete = widget.user != null && widget.user!.isAthlete;

    return ProgressPanel(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_graph_rounded,
                  color: EngineRowingUI.neonLime, size: 24),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  s.progressTitle,
                  style: const TextStyle(
                    color: EngineRowingUI.textWhite,
                    fontSize: 16.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            s.progressSubtitle,
            style: const TextStyle(
              color: EngineRowingUI.captionGrey,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 12),

          // اختيار اللاعب + فلاتر المدة
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            alignment: WrapAlignment.spaceBetween,
            children: [
              // اختيار اللاعب
              if (isAthlete)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.person,
                        color: EngineRowingUI.neonLime, size: 18),
                    const SizedBox(width: 6),
                    Text(
                      widget.user!.name,
                      style: const TextStyle(
                        color: EngineRowingUI.textWhite,
                        fontSize: 13.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                )
              else
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: EngineRowingUI.equationCardFill,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: EngineRowingUI.neonLime.withValues(alpha: 0.4),
                      width: 1.0,
                    ),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<int>(
                      value: _selectedPlayerId,
                      dropdownColor: EngineRowingUI.cardFill,
                      icon: const Icon(Icons.arrow_drop_down,
                          color: EngineRowingUI.neonLime),
                      style: const TextStyle(
                        color: EngineRowingUI.textWhite,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                      onChanged: (newId) async {
                        if (newId != null) {
                          setState(() {
                            _selectedPlayerId = newId;
                            _loading = true;
                          });
                          await _fetchDataForSelection();
                          if (mounted) setState(() => _loading = false);
                        }
                      },
                      items: _players.map((p) {
                        return DropdownMenuItem<int>(
                          value: p['id'] as int,
                          child: Text(p['name'] as String? ?? '--'),
                        );
                      }).toList(),
                    ),
                  ),
                ),

              // فلاتر المدة الزمنية: 7D, 30D, 90D, All
              Row(
                mainAxisSize: MainAxisSize.min,
                children: ['7D', '30D', '90D', 'All'].map((filter) {
                  final isSelected = _selectedFilter == filter;
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: InkWell(
                      onTap: () async {
                        if (_selectedFilter != filter) {
                          setState(() {
                            _selectedFilter = filter;
                            _loading = true;
                          });
                          await _fetchDataForSelection();
                          if (mounted) setState(() => _loading = false);
                        }
                      },
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? EngineRowingUI.neonLime
                              : EngineRowingUI.equationCardFill,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: isSelected
                                ? EngineRowingUI.neonLime
                                : EngineRowingUI.bgGridLine,
                            width: 1.0,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (isSelected) ...[
                              const RowingTrendIndicator(
                                direction: MetricTrendDirection.up,
                                size: 10,
                              ),
                              const SizedBox(width: 4),
                            ],
                            Text(
                              filter,
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.bold,
                                color: isSelected
                                    ? EngineRowingUI.bgNavy
                                    : EngineRowingUI.labelSlate,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════
  // 2. شريط تحذير استكمال المدخلات
  // ════════════════════════════════════════════════════════════════
  Widget _buildWarningBanner(AppStrings s) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF2E1A04),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: const Color(0xFFFF9100).withValues(alpha: 0.7),
          width: 1.0,
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded,
              color: Color(0xFFFF9100), size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              s.completeInputsWarning,
              style: const TextStyle(
                color: Color(0xFFFFCC80),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════
  // 3. قسم PMC (Performance Management Chart)
  // ════════════════════════════════════════════════════════════════
  Widget _buildPmcSection(AppStrings s) {
    return ProgressPanel(
      title: s.pmcTitle,
      leading: const Icon(Icons.analytics_rounded,
          color: EngineRowingUI.neonLime, size: 20),
      trailing: IconButton(
        icon: const Icon(Icons.info_outline_rounded,
            color: EngineRowingUI.neonLime, size: 18),
        tooltip: s.pmcTitle,
        onPressed: () => _showInfoDialog(s.pmcTitle, s.pmcExplanation),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // كروت إحصائيات سريعة CTL, ATL, TSB
          Row(
            children: [
              Expanded(
                child: _buildPmcStatCard(
                  label: s.ctlLabel,
                  value: _currentCTL,
                  color: const Color(0xFF2979FF),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildPmcStatCard(
                  label: s.atlLabel,
                  value: _currentATL,
                  color: const Color(0xFFFF9100),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildPmcStatCard(
                  label: s.tsbLabel,
                  value: _currentTSB,
                  color: EngineRowingUI.neonLime,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // رسم بياني للـ PMC
          if (_ctlPoints.isEmpty)
            _buildEmptyDataNotice(s)
          else
            SizedBox(
              height: 190,
              child: Directionality(
                textDirection: TextDirection.ltr,
                child: LineChart(
                  LineChartData(
                    gridData: FlGridData(
                      show: true,
                      drawVerticalLine: false,
                      getDrawingHorizontalLine: (_) => const FlLine(
                        color: Color(0xFF1B2F5C),
                        strokeWidth: 0.8,
                      ),
                    ),
                    titlesData: FlTitlesData(
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 36,
                          getTitlesWidget: (val, _) => Text(
                            val.toInt().toString(),
                            style: const TextStyle(
                              color: EngineRowingUI.captionGrey,
                              fontSize: 10,
                            ),
                          ),
                        ),
                      ),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 22,
                          getTitlesWidget: (val, _) {
                            final idx = val.toInt();
                            if (idx >= 0 && idx < _ctlPoints.length) {
                              if (idx % max(1, (_ctlPoints.length ~/ 4)) == 0) {
                                final d = _ctlPoints[idx].date;
                                return Text(
                                  '${d.day}/${d.month}',
                                  style: const TextStyle(
                                    color: EngineRowingUI.captionGrey,
                                    fontSize: 9.5,
                                  ),
                                );
                              }
                            }
                            return const SizedBox.shrink();
                          },
                        ),
                      ),
                      rightTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false)),
                      topTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false)),
                    ),
                    borderData: FlBorderData(show: false),
                    lineBarsData: [
                      // خط CTL (أزرق)
                      LineChartBarData(
                        spots: List.generate(
                          _ctlPoints.length,
                          (i) => FlSpot(i.toDouble(), _ctlPoints[i].value ?? 0.0),
                        ),
                        isCurved: true,
                        color: const Color(0xFF2979FF),
                        barWidth: 2.2,
                        dotData: const FlDotData(show: false),
                      ),
                      // خط ATL (برتقالي)
                      LineChartBarData(
                        spots: List.generate(
                          _atlPoints.length,
                          (i) => FlSpot(i.toDouble(), _atlPoints[i].value ?? 0.0),
                        ),
                        isCurved: true,
                        color: const Color(0xFFFF9100),
                        barWidth: 2.0,
                        dotData: const FlDotData(show: false),
                      ),
                      // خط TSB (فسفوري / أخضر)
                      LineChartBarData(
                        spots: List.generate(
                          _tsbPoints.length,
                          (i) => FlSpot(i.toDouble(), _tsbPoints[i].value ?? 0.0),
                        ),
                        isCurved: true,
                        color: EngineRowingUI.neonLime,
                        barWidth: 2.0,
                        dotData: const FlDotData(show: false),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          const SizedBox(height: 6),

          // النص الثابت الإلزامي تحت المنحنى
          _buildEstimatedCurveNotice(s),
          const SizedBox(height: 8),

          // صف أسماء المدخلات الكاملة (Chips)
          _buildChipsRow([
            s.chipCTL,
            s.chipATL,
            s.chipTSB,
            s.chipWatts,
            s.chipTime,
          ]),
        ],
      ),
    );
  }

  Widget _buildPmcStatCard({
    required String label,
    required double value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: EngineRowingUI.equationCardFill,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 1.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 10.5,
              color: EngineRowingUI.captionGrey,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            RowingNumberFormatter.toEnglishDigits(value.toStringAsFixed(1)),
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════
  // 4. قسم خط الأساس ومراقبة الزونات السبعة
  // ════════════════════════════════════════════════════════════════
  Widget _buildZoneBaselinesSection(AppStrings s) {
    return ProgressPanel(
      title: s.zoneBaselinesTitle,
      leading: const Icon(Icons.speed_rounded,
          color: EngineRowingUI.neonLime, size: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth > 550;
              final itemWidth = isWide
                  ? (constraints.maxWidth - 16) / 2
                  : constraints.maxWidth;

              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: HeartRateZones.orderedZones.map((zone) {
                  final baseline = _zoneBaselines[zone];
                  final wPoints = _zoneWattsPoints[zone] ?? [];
                  final curWatts = wPoints.isNotEmpty ? wPoints.last.value : null;

                  final sPoints = _zoneSplitPoints[zone] ?? [];
                  final curSplit = sPoints.isNotEmpty ? sPoints.last.value : null;

                  final dPoints = _zoneDecouplingPoints[zone] ?? [];
                  final curDec = dPoints.isNotEmpty ? dPoints.last.value : null;

                  return SizedBox(
                    width: itemWidth,
                    child: _buildSingleZoneCard(
                      s: s,
                      zone: zone,
                      baseline: baseline,
                      currentWatts: curWatts,
                      currentSplit: curSplit,
                      currentDecoupling: curDec,
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSingleZoneCard({
    required AppStrings s,
    required String zone,
    required ZoneBaseline? baseline,
    required double? currentWatts,
    required double? currentSplit,
    required double? currentDecoupling,
  }) {
    final color = HeartRateZones.zoneColor(zone);
    final displayName =
        HeartRateZones.zoneDisplayName(zone, isArabic: s.isArabic);

    final wattsTrend = currentWatts != null && baseline?.bestWatts != null
        ? ProgressCalcs.evalWattsTrend(
            currentWatts: currentWatts,
            baselineWatts: baseline!.bestWatts,
          )
        : ProgressTrend.neutral;

    final splitTrend = currentSplit != null && baseline?.bestSplitSeconds != null
        ? ProgressCalcs.evalSplitTrend(
            currentSplit: currentSplit,
            baselineSplit: baseline!.bestSplitSeconds,
          )
        : ProgressTrend.neutral;

    final decTrend =
        currentDecoupling != null && baseline?.bestDecoupling != null
            ? ProgressCalcs.evalDecouplingTrend(
                currentDecoupling: currentDecoupling,
                baselineDecoupling: baseline!.bestDecoupling,
              )
            : ProgressTrend.neutral;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: EngineRowingUI.equationCardFill,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.7), width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // شريط اسم الزون
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ),
              RowingTrendIndicator(
                direction: _toDir(wattsTrend),
                size: 14,
              ),
            ],
          ),
          const SizedBox(height: 8),

          // 1. صف الواط
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${s.chipWatts}:',
                style: const TextStyle(
                  fontSize: 11,
                  color: EngineRowingUI.labelSlate,
                ),
              ),
              Row(
                children: [
                  Text(
                    currentWatts != null
                        ? '${RowingNumberFormatter.toEnglishDigits(currentWatts.toStringAsFixed(0))} W'
                        : '--',
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.bold,
                      color: EngineRowingUI.textWhite,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    baseline?.bestWatts != null
                        ? '(${RowingNumberFormatter.toEnglishDigits(baseline!.bestWatts!.toStringAsFixed(0))})'
                        : '(--)',
                    style: TextStyle(
                      fontSize: 10,
                      color: color.withValues(alpha: 0.8),
                    ),
                  ),
                  const SizedBox(width: 4),
                  RowingTrendIndicator(
                    direction: _toDir(wattsTrend),
                    size: 13,
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 4),

          // 2. صف أفضل سبليت
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${s.chipSplit}:',
                style: const TextStyle(
                  fontSize: 10.5,
                  color: EngineRowingUI.labelSlate,
                ),
              ),
              Row(
                children: [
                  Text(
                    currentSplit != null ? _formatSplit(currentSplit) : '--',
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.bold,
                      color: EngineRowingUI.textWhite,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    baseline?.bestSplitSeconds != null
                        ? '(${_formatSplit(baseline!.bestSplitSeconds!)})'
                        : '(--)',
                    style: TextStyle(
                      fontSize: 10,
                      color: color.withValues(alpha: 0.8),
                    ),
                  ),
                  const SizedBox(width: 4),
                  RowingTrendIndicator(
                    direction: _toDir(splitTrend),
                    size: 13,
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 4),

          // 3. صف التفكك القلبي Decoupling
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${s.chipDecoupling}:',
                style: const TextStyle(
                  fontSize: 10.5,
                  color: EngineRowingUI.labelSlate,
                ),
              ),
              Row(
                children: [
                  Text(
                    currentDecoupling != null
                        ? '${RowingNumberFormatter.toEnglishDigits(currentDecoupling.toStringAsFixed(1))}%'
                        : '--',
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.bold,
                      color: EngineRowingUI.textWhite,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    baseline?.bestDecoupling != null
                        ? '(${RowingNumberFormatter.toEnglishDigits(baseline!.bestDecoupling!.toStringAsFixed(1))}%)'
                        : '(--)',
                    style: TextStyle(
                      fontSize: 10,
                      color: color.withValues(alpha: 0.8),
                    ),
                  ),
                  const SizedBox(width: 4),
                  RowingTrendIndicator(
                    direction: _toDir(decTrend),
                    size: 13,
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════
  // 5. قسم المنحنيات الفسيولوجية والزونات
  // ════════════════════════════════════════════════════════════════
  Widget _buildCurvesSection(AppStrings s) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // منحنى HRV
        _buildSingleCurvePanel(
          s: s,
          title: s.hrvTitle,
          explanation: s.hrvExplanation,
          points: _hrvPoints,
          lineColor: const Color(0xFF00E5FF),
          unit: 'ms',
          chipKeys: [s.chipHRV, s.chipRHR, s.chipTime],
          enableMovingAverage: true,
        ),
        const SizedBox(height: 12),

        // منحنى RHR
        _buildSingleCurvePanel(
          s: s,
          title: s.rhrTitle,
          explanation: s.rhrExplanation,
          points: _rhrPoints,
          lineColor: const Color(0xFFFF5252),
          unit: 'bpm',
          chipKeys: [s.chipRHR, s.chipHRV, s.chipTime],
          enableMovingAverage: true,
        ),
        const SizedBox(height: 12),

        // منحنى النوم والوزن
        _buildSingleCurvePanel(
          s: s,
          title: s.sleepWeightTitle,
          explanation: s.sleepWeightExplanation,
          points: _sleepPoints,
          lineColor: const Color(0xFF7C4DFF),
          unit: 'hrs',
          chipKeys: [s.chipSleep, s.chipWeight, s.chipTime],
          enableMovingAverage: true,
        ),
        if (_weightPoints.isNotEmpty) ...[
          const SizedBox(height: 12),
          _buildSingleCurvePanel(
            s: s,
            title: s.chipWeight,
            explanation: s.sleepWeightExplanation,
            points: _weightPoints,
            lineColor: const Color(0xFFB388FF),
            unit: 'kg',
            chipKeys: [s.chipWeight, s.chipTime],
            enableMovingAverage: true,
          ),
        ],
        const SizedBox(height: 12),

        // منحنى التنفس (Eupnea)
        _buildSingleCurvePanel(
          s: s,
          title: s.eupneaTitle,
          explanation: s.eupneaExplanation,
          points: _eupneaPoints,
          lineColor: const Color(0xFF69F0AE),
          unit: 'br/min',
          chipKeys: [s.chipEupnea, s.chipHR, s.chipTime],
          enableMovingAverage: true,
        ),
        const SizedBox(height: 12),

        // منحنى Decoupling
        _buildSingleCurvePanel(
          s: s,
          title: s.decouplingTitle,
          explanation: s.decouplingExplanation,
          points: _decouplingPoints,
          lineColor: const Color(0xFFFFAB00),
          unit: '%',
          chipKeys: [s.chipDecoupling, s.chipWatts, s.chipHR, s.chipTime],
          enableMovingAverage: true,
        ),
        const SizedBox(height: 12),

        // منحنى EF
        _buildSingleCurvePanel(
          s: s,
          title: s.efTitle,
          explanation: s.efExplanation,
          points: _efPoints,
          lineColor: EngineRowingUI.neonLime,
          unit: 'W/bpm',
          chipKeys: [s.chipEF, s.chipWatts, s.chipHR, s.chipTime],
          enableMovingAverage: false, // مستثنى لأنه متوسط أسبوعي
        ),

        // ── منحنيات الواط لكل زون من الزونات السبعة ──
        for (final zone in HeartRateZones.orderedZones) ...[
          const SizedBox(height: 12),
          _buildSingleCurvePanel(
            s: s,
            title:
                '${s.chipWatts} - ${HeartRateZones.zoneDisplayName(zone, isArabic: s.isArabic)}',
            explanation:
                '${HeartRateZones.zoneDisplayName(zone, isArabic: s.isArabic)}\n${s.zoneCurvePurpose}',
            points: _zoneWattsPoints[zone] ?? [],
            lineColor: HeartRateZones.zoneColor(zone),
            unit: 'W',
            chipKeys: [
              s.chipWatts,
              s.chipSplit,
              s.chipHR,
              s.chipZone,
              s.chipTime,
            ],
            enableMovingAverage: true,
          ),
        ],
      ],
    );
  }

  Widget _buildSingleCurvePanel({
    required AppStrings s,
    required String title,
    required String explanation,
    required List<DateValuePoint> points,
    required Color lineColor,
    required String unit,
    required List<String> chipKeys,
    required bool enableMovingAverage,
  }) {
    final maPoints = enableMovingAverage
        ? ProgressCalcs.movingAverage7(points)
        : <DateValuePoint>[];

    MetricTrendDirection? curveTrend;
    if (points.length >= 2) {
      final lastVal = points.last.value;
      final prevVal = points[points.length - 2].value;
      if (lastVal != null && prevVal != null) {
        if (lastVal > prevVal) {
          curveTrend = MetricTrendDirection.up;
        } else if (lastVal < prevVal) {
          curveTrend = MetricTrendDirection.down;
        } else {
          curveTrend = MetricTrendDirection.neutral;
        }
      }
    }

    return ProgressPanel(
      title: title,
      leading: Icon(Icons.show_chart_rounded, color: lineColor, size: 20),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (curveTrend != null) ...[
            RowingTrendIndicator(direction: curveTrend, size: 16),
            const SizedBox(width: 8),
          ],
          IconButton(
            icon: const Icon(Icons.info_outline_rounded,
                color: EngineRowingUI.neonLime, size: 18),
            tooltip: title,
            onPressed: () => _showInfoDialog(title, explanation),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (points.isEmpty)
            _buildEmptyDataNotice(s)
          else ...[
            SizedBox(
              height: 170,
              child: Directionality(
                textDirection: TextDirection.ltr,
                child: LineChart(
                  LineChartData(
                    gridData: FlGridData(
                      show: true,
                      drawVerticalLine: false,
                      getDrawingHorizontalLine: (_) => const FlLine(
                        color: Color(0xFF1B2F5C),
                        strokeWidth: 0.8,
                      ),
                    ),
                    titlesData: FlTitlesData(
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 34,
                          getTitlesWidget: (val, _) => Text(
                            val.toInt().toString(),
                            style: const TextStyle(
                              color: EngineRowingUI.captionGrey,
                              fontSize: 10,
                            ),
                          ),
                        ),
                      ),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 22,
                          getTitlesWidget: (val, _) {
                            final idx = val.toInt();
                            if (idx >= 0 && idx < points.length) {
                              if (idx % max(1, (points.length ~/ 4)) == 0) {
                                final d = points[idx].date;
                                return Text(
                                  '${d.day}/${d.month}',
                                  style: const TextStyle(
                                    color: EngineRowingUI.captionGrey,
                                    fontSize: 9.5,
                                  ),
                                );
                              }
                            }
                            return const SizedBox.shrink();
                          },
                        ),
                      ),
                      rightTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false)),
                      topTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false)),
                    ),
                    borderData: FlBorderData(show: false),
                    lineBarsData: [
                      // الخط الفعلي للنقاط
                      LineChartBarData(
                        spots: List.generate(
                          points.length,
                          (i) => FlSpot(i.toDouble(), points[i].value ?? 0.0),
                        ),
                        isCurved: false,
                        color: lineColor,
                        barWidth: 2.2,
                        dotData: FlDotData(
                          show: true,
                          getDotPainter: (spot, percent, barData, index) {
                            final isLast = index == points.length - 1;
                            final dotColor = isLast
                                ? (curveTrend == MetricTrendDirection.down
                                    ? const Color(0xFFFF4D4D)
                                    : EngineRowingUI.neonLime)
                                : lineColor;
                            return FlDotCirclePainter(
                              radius: isLast ? 4.8 : 2.5,
                              color: dotColor,
                              strokeColor: Colors.white,
                              strokeWidth: isLast ? 1.5 : 0.8,
                            );
                          },
                        ),
                      ),

                      // خط المتوسط المتحرك لـ 7 أيام
                      if (maPoints.isNotEmpty)
                        LineChartBarData(
                          spots: [
                            for (int i = 0; i < maPoints.length; i++)
                              if (maPoints[i].value != null)
                                FlSpot(i.toDouble(), maPoints[i].value!),
                          ],
                          isCurved: true,
                          color: lineColor.withValues(alpha: 0.65),
                          barWidth: 1.6,
                          dashArray: [5, 4],
                          dotData: const FlDotData(show: false),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
          ],

          // النص الثابت الإلزامي تحت المنحنى
          _buildEstimatedCurveNotice(s),
          const SizedBox(height: 8),

          // صف شارات المدخلات الكاملة
          _buildChipsRow(chipKeys),
        ],
      ),
    );
  }

  Widget _buildEmptyDataNotice(AppStrings s) {
    return Container(
      height: 100,
      alignment: Alignment.center,
      child: Text(
        s.notEnoughData,
        style: const TextStyle(
          color: EngineRowingUI.captionGrey,
          fontSize: 13,
        ),
      ),
    );
  }

  Widget _buildEstimatedCurveNotice(AppStrings s) {
    return Center(
      child: Text(
        s.estimatedCurveOnly,
        style: const TextStyle(
          color: EngineRowingUI.captionGrey,
          fontSize: 10.5,
          fontStyle: FontStyle.italic,
        ),
      ),
    );
  }

  Widget _buildChipsRow(List<String> chipNames) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: chipNames.map((name) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: EngineRowingUI.equationCardFill,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: EngineRowingUI.bgGridLine,
              width: 0.8,
            ),
          ),
          child: Text(
            name,
            style: const TextStyle(
              fontSize: 10,
              color: EngineRowingUI.labelSlate,
              fontWeight: FontWeight.w500,
            ),
          ),
        );
      }).toList(),
    );
  }
}
