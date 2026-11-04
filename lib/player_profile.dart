import 'dart:math';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'app_strings.dart';
import 'db.dart';
import 'engine_rowing_ui.dart';
import 'metrics_curve_page.dart';

/// صفحة ملف اللاعب التفصيلي مع التحليلات الفسيولوجية
class PlayerProfilePage extends StatefulWidget {
  final Map<String, Object?> player;
  const PlayerProfilePage({super.key, required this.player});
  @override
  State<PlayerProfilePage> createState() => _PlayerProfileState();
}

class _PlayerProfileState extends State<PlayerProfilePage> {
  Map<String, Object?> get p => widget.player;
  int get playerId => p['id'] as int;
  int get mhr => (p['mhr'] as int?) ?? 190;

  bool loading = true;
  List<Map<String, Object?>> logs = [];
  Map<String, double> baseline = {};
  Map<String, double> balance = {};
  List<String> alerts = [];
  Map<String, int> zonesDist = {};
  List<Map<String, dynamic>> recoveryData = [];

  @override
  void initState() {
    super.initState();
    loadAll();
  }

  Future<void> loadAll() async {
    logs = await DB.playerLogs(playerId);
    baseline = await DB.playerBaseline(playerId);
    balance = await DB.physiologicalBalance(playerId);
    alerts = await DB.overtrainingAlerts(playerId);
    zonesDist = await DB.playerZoneDistribution(playerId);
    recoveryData = await DB.playerRecoveryData(playerId);
    if (mounted) setState(() => loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);

    return Scaffold(
      backgroundColor: EngineRowingUI.bgNavy,
      appBar: AppBar(
        backgroundColor: EngineRowingUI.bgNavy,
        foregroundColor: EngineRowingUI.textWhite,
        elevation: 0,
        title: Text(
          '${p['name']} - ${s.athleteDetails}',
          style: const TextStyle(
            color: EngineRowingUI.textWhite,
            fontWeight: FontWeight.bold,
            fontSize: 17,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: EngineRowingUI.neonLime),
            onPressed: () {
              setState(() => loading = true);
              loadAll();
            },
          ),
        ],
      ),
      body: RowingGridBackground(
        child: loading
            ? const Center(child: CircularProgressIndicator(color: EngineRowingUI.neonLime))
            : logs.isEmpty
                ? _emptyState(s)
                : Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 850),
                      child: ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          _playerCard(s),
                          if (alerts.isNotEmpty) ...[
                            _sectionTitle(s.overtrainingAlerts),
                            _alertsCard(),
                          ],
                          _sectionTitle(s.readinessScore),
                          _readinessCard(s),
                          _sectionTitle(s.physiologicalBalance),
                          _balanceRadar(s),
                          _sectionTitle('${s.rhrLabel} - RHR'),
                          _rhrChart(),
                          _sectionTitle('${s.hrvLabel} - HRV'),
                          _hrvChart(),
                          _sectionTitle(s.recoveryAnalytics),
                          _recoveryChart(s),
                          _sectionTitle(s.weightLabel),
                          _weightChart(),
                          _sectionTitle('📊 ${s.isArabic ? 'توزيع مناطق التدريب' : 'Training Zones Distribution'}'),
                          _zonesChart(),
                          _sectionTitle(s.sessionsHistory),
                          _recentLogsTable(s),
                          const SizedBox(height: 32),
                        ],
                      ),
                    ),
                  ),
      ),
    );
  }

  Widget _emptyState(AppStrings s) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.insert_chart_outlined, size: 80, color: EngineRowingUI.labelSlate),
            const SizedBox(height: 16),
            Text(
              s.noLogsForPlayer,
              style: const TextStyle(fontSize: 18, color: EngineRowingUI.textWhite, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              s.tapPlayerToLog,
              style: const TextStyle(color: EngineRowingUI.labelSlate),
            ),
          ],
        ),
      );

  Widget _sectionTitle(String t) => Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 8),
      child: Text(
        t,
        style: const TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.bold,
          color: EngineRowingUI.textWhite,
        ),
      ));

  // ==================== بطاقة اللاعب ====================
  Widget _playerCard(AppStrings s) {
    final latest = logs.isNotEmpty ? logs.first : null;
    final sessionCount7 = logs.where((l) {
      final d = DateTime.tryParse(l['date'] as String? ?? '');
      return d != null && DateTime.now().difference(d).inDays <= 7;
    }).length;

    return Card(
      elevation: 0,
      color: EngineRowingUI.cardFill,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: EngineRowingUI.bgGridLine),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              CircleAvatar(
                radius: 30,
                backgroundColor: EngineRowingUI.equationCardFill,
                child: Text(
                  '${p['name'].toString().isNotEmpty ? p['name'].toString()[0] : 'A'}',
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: EngineRowingUI.neonLime,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${p['name']}',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: EngineRowingUI.textWhite,
                      ),
                    ),
                    Directionality(
                      textDirection: TextDirection.ltr,
                      child: Text(
                        '${s.maxHRLabel}: $mhr bpm • ${p['active'] == 1 ? s.playerStatusActive : s.playerStatusInactive}',
                        style: const TextStyle(fontSize: 13, color: EngineRowingUI.labelSlate),
                      ),
                    ),
                  ],
                ),
              ),
            ]),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
              decoration: BoxDecoration(
                color: EngineRowingUI.equationCardFill,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: EngineRowingUI.bgGridLine),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _statChip(s.isArabic ? 'حصص الأسبوع' : 'Weekly', '$sessionCount7'),
                  _statChip(s.isArabic ? 'إجمالي السجلات' : 'Total Logs', '${logs.length}'),
                  if (latest != null && latest['rhr'] != null)
                    _statChip(s.isArabic ? 'آخر RHR' : 'Latest RHR', '${latest['rhr']}'),
                  if (baseline.isNotEmpty && baseline['avg_rhr'] != null)
                    _statChip(s.isArabic ? 'متوسط RHR' : 'Avg RHR', '${baseline['avg_rhr']?.round()}'),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: EngineRowingUI.neonLime,
                  foregroundColor: EngineRowingUI.bgNavy,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => MetricsCurvePage(initialPlayer: widget.player),
                    ),
                  );
                },
                icon: const Icon(Icons.auto_graph_rounded, color: EngineRowingUI.bgNavy),
                label: Text(
                  s.isArabic ? 'منحنيات مؤشرات التدريب (خمسة منحنيات)' : 'View Metrics Curves (5 Curves)',
                  style: const TextStyle(fontWeight: FontWeight.bold, color: EngineRowingUI.bgNavy),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statChip(String label, String value) => Column(children: [
        Directionality(
          textDirection: TextDirection.ltr,
          child: Text(
            RowingNumberFormatter.toEnglishDigits(value),
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: EngineRowingUI.neonLime,
            ),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: EngineRowingUI.labelSlate),
        ),
      ]);

  // ==================== التنبيهات ====================
  Widget _alertsCard() => Card(
        elevation: 0,
        color: EngineRowingUI.cardFill,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: Colors.redAccent, width: 1.2),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final a in alerts)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          RowingNumberFormatter.toEnglishDigits(a),
                          style: const TextStyle(fontSize: 14, color: EngineRowingUI.textWhite),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      );

  // ==================== مؤشر الجاهزية ====================
  Widget _readinessCard(AppStrings s) {
    final latest = logs.isNotEmpty ? logs.first : null;
    double score = 75;
    if (latest != null && baseline.isNotEmpty) {
      score = calculateReadiness(
        rhr: latest['rhr'] as int?,
        rhrBaseline: baseline['avg_rhr'],
        hrv: latest['hrv'] as int?,
        hrvBaseline: baseline['avg_hrv'],
        fatigue: latest['fatigue'] as int?,
        sleepHours: latest['sleep_hours'] as double?,
      );
    }

    final color = score >= 80
        ? EngineRowingUI.neonLime
        : score >= 60
            ? const Color(0xFFFF9100)
            : const Color(0xFFFF5252);
    final text = readinessText(score);

    return Card(
      elevation: 0,
      color: EngineRowingUI.cardFill,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: EngineRowingUI.bgGridLine),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(children: [
          Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 120,
                height: 120,
                child: CircularProgressIndicator(
                  value: score / 100,
                  strokeWidth: 10,
                  backgroundColor: EngineRowingUI.equationCardFill,
                  valueColor: AlwaysStoppedAnimation(color),
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Directionality(
                    textDirection: TextDirection.ltr,
                    child: Text(
                      '${score.round()}%',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                    ),
                  ),
                  Text(text, style: TextStyle(fontSize: 14, color: color, fontWeight: FontWeight.w600)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (latest != null) ...[
            _readinessDetail(s.rhrLabel, '${latest['rhr'] ?? '-'}',
                '${s.isArabic ? 'المتوسط' : 'Avg'}: ${baseline['avg_rhr']?.round() ?? '-'}'),
            _readinessDetail(s.hrvLabel, '${latest['hrv'] ?? '-'}',
                '${s.isArabic ? 'المتوسط' : 'Avg'}: ${baseline['avg_hrv']?.round() ?? '-'}'),
            _readinessDetail(s.fatigueLabel,
                fatigueLabels[latest['fatigue'] as int?] ?? '-', ''),
            _readinessDetail(s.sleepLabel,
                '${latest['sleep_hours'] ?? '-'} ${s.hours}', ''),
          ],
        ]),
      ),
    );
  }

  Widget _readinessDetail(String label, String value, String sub) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Expanded(
          child: Text(label, style: const TextStyle(fontSize: 14, color: EngineRowingUI.labelSlate)),
        ),
        Directionality(
          textDirection: TextDirection.ltr,
          child: Text(
            RowingNumberFormatter.toEnglishDigits(value),
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: EngineRowingUI.textWhite,
            ),
          ),
        ),
        if (sub.isNotEmpty) ...[
          const SizedBox(width: 8),
          Directionality(
            textDirection: TextDirection.ltr,
            child: Text(
              RowingNumberFormatter.toEnglishDigits(sub),
              style: const TextStyle(fontSize: 12, color: EngineRowingUI.captionGrey),
            ),
          ),
        ],
      ]));

  // ==================== رادار التوازن الفسيولوجي ====================
  Widget _balanceRadar(AppStrings s) {
    if (balance.isEmpty) {
      return Card(
        elevation: 0,
        color: EngineRowingUI.cardFill,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: EngineRowingUI.bgGridLine),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            s.isArabic ? 'لا توجد بيانات كافية لعرض التوازن' : 'Not enough data for balance radar',
            style: const TextStyle(color: EngineRowingUI.labelSlate),
          ),
        ),
      );
    }

    final keys = balance.keys.toList();
    final values = balance.values.toList();
    final avgScore = values.reduce((a, b) => a + b) / values.length;

    return Card(
      elevation: 0,
      color: EngineRowingUI.cardFill,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: EngineRowingUI.bgGridLine),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          Directionality(
            textDirection: TextDirection.ltr,
            child: Text(
              '${s.isArabic ? 'المؤشر العام' : 'Overall Index'}: ${avgScore.round()}%',
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: EngineRowingUI.neonLime,
              ),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 260,
            child: RadarChart(
              RadarChartData(
                radarShape: RadarShape.polygon,
                radarBorderData: const BorderSide(color: Colors.transparent),
                gridBorderData: const BorderSide(color: EngineRowingUI.bgGridLine, width: 1),
                tickBorderData: const BorderSide(color: Colors.transparent),
                tickCount: 4,
                ticksTextStyle: const TextStyle(fontSize: 0),
                titleTextStyle: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: EngineRowingUI.labelSlate,
                ),
                getTitle: (i, _) => RadarChartTitle(text: keys[i]),
                dataSets: [
                  RadarDataSet(
                    dataEntries: [
                      for (final v in values) RadarEntry(value: v)
                    ],
                    fillColor: EngineRowingUI.neonLime.withValues(alpha: 0.15),
                    borderColor: EngineRowingUI.neonLime,
                    borderWidth: 2,
                    entryRadius: 3,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (int i = 0; i < keys.length; i++)
                Chip(
                  label: Directionality(
                    textDirection: TextDirection.ltr,
                    child: Text(
                      '${keys[i]}: ${values[i].round()}%',
                      style: const TextStyle(fontSize: 11, color: EngineRowingUI.textWhite),
                    ),
                  ),
                  backgroundColor: EngineRowingUI.equationCardFill,
                  side: const BorderSide(color: EngineRowingUI.bgGridLine),
                ),
            ],
          ),
        ]),
      ),
    );
  }

  // ==================== رسم بياني خطي عام ====================
  Widget _lineChartCard(
    List<FlSpot> spots,
    Color color, {
    double? refLine,
    String? refLabel,
  }) {
    if (spots.length < 2) {
      return Card(
        elevation: 0,
        color: EngineRowingUI.cardFill,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: EngineRowingUI.bgGridLine),
        ),
        child: const Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'بيانات غير كافية (مطلوب نقطتان على الأقل)',
            style: TextStyle(color: EngineRowingUI.labelSlate),
          ),
        ),
      );
    }

    final minY = spots.map((s) => s.y).reduce(min) - 5;
    final maxY = spots.map((s) => s.y).reduce(max) + 5;

    return Card(
      elevation: 0,
      color: EngineRowingUI.cardFill,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: EngineRowingUI.bgGridLine),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: SizedBox(
          height: 190,
          child: LineChart(
            LineChartData(
              minY: minY,
              maxY: maxY,
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: ((maxY - minY) / 4).clamp(1, 50),
                getDrawingHorizontalLine: (v) => const FlLine(
                  color: EngineRowingUI.bgGridLine,
                  strokeWidth: 1,
                ),
              ),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                bottomTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 40,
                    getTitlesWidget: (v, _) => Text(
                      '${v.round()}',
                      style: const TextStyle(fontSize: 11, color: EngineRowingUI.labelSlate),
                    ),
                  ),
                ),
              ),
              borderData: FlBorderData(show: false),
              extraLinesData: refLine != null
                  ? ExtraLinesData(horizontalLines: [
                      HorizontalLine(
                        y: refLine,
                        color: Colors.redAccent.withValues(alpha: 0.6),
                        strokeWidth: 1.5,
                        dashArray: [8, 4],
                        label: HorizontalLineLabel(
                          show: true,
                          labelResolver: (_) => refLabel ?? '',
                          style: const TextStyle(fontSize: 11, color: Colors.redAccent),
                        ),
                      ),
                    ])
                  : null,
              lineBarsData: [
                LineChartBarData(
                  spots: spots,
                  isCurved: true,
                  curveSmoothness: 0.25,
                  color: color,
                  barWidth: 3,
                  dotData: FlDotData(
                    show: spots.length <= 20,
                    getDotPainter: (_, __, ___, ____) =>
                        FlDotCirclePainter(radius: 3, color: color, strokeWidth: 0),
                  ),
                  belowBarData: BarAreaData(
                    show: true,
                    color: color.withValues(alpha: 0.12),
                  ),
                ),
              ],
              lineTouchData: LineTouchData(
                touchTooltipData: LineTouchTooltipData(
                  getTooltipItems: (spots) => spots
                      .map((s) => LineTooltipItem(
                            '${s.y.round()}',
                            TextStyle(
                              color: color,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ))
                      .toList(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ==================== نبض الراحة ====================
  Widget _rhrChart() {
    final rhrLogs = logs
        .where((l) => l['rhr'] != null)
        .toList()
        .reversed
        .toList();

    final spots = <FlSpot>[];
    for (int i = 0; i < rhrLogs.length; i++) {
      spots.add(FlSpot(i.toDouble(), (rhrLogs[i]['rhr'] as int).toDouble()));
    }

    return _lineChartCard(
      spots,
      Colors.redAccent,
      refLine: baseline['avg_rhr'],
      refLabel: 'Avg: ${baseline['avg_rhr']?.round() ?? ''}',
    );
  }

  // ==================== تغير النبض ====================
  Widget _hrvChart() {
    final hrvLogs = logs
        .where((l) => l['hrv'] != null)
        .toList()
        .reversed
        .toList();

    final spots = <FlSpot>[];
    for (int i = 0; i < hrvLogs.length; i++) {
      spots.add(FlSpot(i.toDouble(), (hrvLogs[i]['hrv'] as int).toDouble()));
    }

    return _lineChartCard(
      spots,
      const Color(0xFF2979FF),
      refLine: baseline['avg_hrv'],
      refLabel: 'Avg: ${baseline['avg_hrv']?.round() ?? ''}',
    );
  }

  // ==================== الاستشفاء ====================
  Widget _recoveryChart(AppStrings s) {
    if (recoveryData.isEmpty) {
      return Card(
        elevation: 0,
        color: EngineRowingUI.cardFill,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: EngineRowingUI.bgGridLine),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            s.isArabic ? 'لا توجد بيانات استشفاء مسجلة' : 'No recovery data recorded',
            style: const TextStyle(color: EngineRowingUI.labelSlate),
          ),
        ),
      );
    }

    final reversedData = recoveryData.reversed.toList();
    final spots = <FlSpot>[];
    for (int i = 0; i < reversedData.length; i++) {
      final rate = (reversedData[i]['recovery_rate_post'] as double?) ??
          (reversedData[i]['recovery_rate_1min'] as double?);
      if (rate != null) {
        spots.add(FlSpot(i.toDouble(), rate));
      }
    }

    return Column(children: [
      _lineChartCard(spots, EngineRowingUI.neonLime, refLine: 20, refLabel: 'Target: 20%+'),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Text(
          s.isArabic
              ? '💡 نسبة الاستشفاء = مدى انخفاض النبض بعد التمرين. أعلى من 20% = ممتاز'
              : '💡 Recovery Rate = Heart rate drop post-workout. >20% = Excellent',
          style: const TextStyle(fontSize: 12, color: EngineRowingUI.captionGrey),
        ),
      ),
    ]);
  }

  // ==================== الوزن ====================
  Widget _weightChart() {
    final wLogs = logs
        .where((l) => l['weight'] != null)
        .toList()
        .reversed
        .toList();

    final spots = <FlSpot>[];
    for (int i = 0; i < wLogs.length; i++) {
      spots.add(
          FlSpot(i.toDouble(), (wLogs[i]['weight'] as num).toDouble()));
    }

    return _lineChartCard(
      spots,
      const Color(0xFFFF9100),
      refLine: baseline['avg_weight'],
      refLabel: 'Avg: ${baseline['avg_weight']?.toStringAsFixed(1) ?? ''}',
    );
  }

  // ==================== توزيع المناطق ====================
  Widget _zonesChart() {
    if (zonesDist.isEmpty) {
      return const Card(
        elevation: 0,
        color: EngineRowingUI.cardFill,
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('لا توجد بيانات كافية', style: TextStyle(color: EngineRowingUI.labelSlate)),
        ),
      );
    }

    final colors = [
      EngineRowingUI.zone1Color,
      EngineRowingUI.zone2Color,
      EngineRowingUI.zone3Color,
      EngineRowingUI.thresholdColor,
      EngineRowingUI.zone5Color,
    ];

    final totalSessions = zonesDist.values.fold<int>(0, (a, b) => a + b);

    return Card(
      elevation: 0,
      color: EngineRowingUI.cardFill,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: EngineRowingUI.bgGridLine),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          SizedBox(
            height: 190,
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: (zonesDist.values.reduce(max) + 2).toDouble(),
                gridData: const FlGridData(show: false),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (v, _) {
                        final keys = zonesDist.keys.toList();
                        if (v.toInt() < keys.length) {
                          return Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              keys[v.toInt()],
                              style: const TextStyle(fontSize: 11, color: EngineRowingUI.textWhite),
                            ),
                          );
                        }
                        return const SizedBox();
                      },
                    ),
                  ),
                ),
                barGroups: [
                  for (int i = 0; i < zonesDist.length; i++)
                    BarChartGroupData(x: i, barRods: [
                      BarChartRodData(
                        toY: zonesDist.values.elementAt(i).toDouble(),
                        color: colors[i % colors.length],
                        width: 24,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                      ),
                    ]),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Directionality(
            textDirection: TextDirection.ltr,
            child: Text(
              'Total: $totalSessions sessions (last 30 days)',
              style: const TextStyle(color: EngineRowingUI.labelSlate, fontSize: 12),
            ),
          ),
        ]),
      ),
    );
  }

  // ==================== جدول آخر التسجيلات ====================
  Widget _recentLogsTable(AppStrings s) {
    final recentLogs = logs.take(15).toList();
    if (recentLogs.isEmpty) {
      return Card(
        elevation: 0,
        color: EngineRowingUI.cardFill,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(s.noData, style: const TextStyle(color: EngineRowingUI.labelSlate)),
        ),
      );
    }

    return Card(
      elevation: 0,
      color: EngineRowingUI.cardFill,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: EngineRowingUI.bgGridLine),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(EngineRowingUI.equationCardFill),
          columnSpacing: 14,
          columns: [
            DataColumn(
              label: Text(
                s.isArabic ? 'Date' : 'Date',
                style: const TextStyle(fontWeight: FontWeight.bold, color: EngineRowingUI.neonLime),
              ),
            ),
            DataColumn(
              label: Text(
                s.isArabic ? 'Kind' : 'Kind',
                style: const TextStyle(fontWeight: FontWeight.bold, color: EngineRowingUI.neonLime),
              ),
            ),
            const DataColumn(label: Text('RHR', style: TextStyle(fontWeight: FontWeight.bold, color: EngineRowingUI.neonLime))),
            const DataColumn(label: Text('HRV', style: TextStyle(fontWeight: FontWeight.bold, color: EngineRowingUI.neonLime))),
            DataColumn(label: Text(s.workoutHRLabel, style: const TextStyle(fontWeight: FontWeight.bold, color: EngineRowingUI.neonLime))),
            const DataColumn(label: Text('HR Max', style: TextStyle(fontWeight: FontWeight.bold, color: EngineRowingUI.neonLime))),
            DataColumn(label: Text(s.postHRLabel, style: const TextStyle(fontWeight: FontWeight.bold, color: EngineRowingUI.neonLime))),
            DataColumn(label: Text(s.hr1MinLabel, style: const TextStyle(fontWeight: FontWeight.bold, color: EngineRowingUI.neonLime))),
            DataColumn(label: Text(s.weightLabel, style: const TextStyle(fontWeight: FontWeight.bold, color: EngineRowingUI.neonLime))),
            DataColumn(label: Text(s.fatigueLabel, style: const TextStyle(fontWeight: FontWeight.bold, color: EngineRowingUI.neonLime))),
          ],
          rows: [
            for (final l in recentLogs)
              DataRow(cells: [
                DataCell(
                  Directionality(
                    textDirection: TextDirection.ltr,
                    child: Text(
                      RowingNumberFormatter.toEnglishDigits('${l['date'] ?? ''}'),
                      style: const TextStyle(fontSize: 13, color: EngineRowingUI.textWhite),
                    ),
                  ),
                ),
                DataCell(
                  Text(
                    '${l['kind'] ?? '-'}',
                    style: const TextStyle(fontSize: 13, color: EngineRowingUI.textWhite),
                  ),
                ),
                DataCell(_hrCell(l['rhr'] as int?)),
                DataCell(
                  Directionality(
                    textDirection: TextDirection.ltr,
                    child: Text(
                      RowingNumberFormatter.toEnglishDigits('${l['hrv'] ?? '-'}'),
                      style: const TextStyle(fontSize: 13, color: EngineRowingUI.textWhite),
                    ),
                  ),
                ),
                DataCell(_hrCell(l['hr'] as int?, zone: l['zone'] as String?)),
                DataCell(
                  Directionality(
                    textDirection: TextDirection.ltr,
                    child: Text(
                      RowingNumberFormatter.toEnglishDigits('${l['hr_max'] ?? '-'}'),
                      style: const TextStyle(fontSize: 13, color: EngineRowingUI.textWhite),
                    ),
                  ),
                ),
                DataCell(
                  Directionality(
                    textDirection: TextDirection.ltr,
                    child: Text(
                      RowingNumberFormatter.toEnglishDigits('${l['hr_post'] ?? '-'}'),
                      style: const TextStyle(fontSize: 13, color: EngineRowingUI.textWhite),
                    ),
                  ),
                ),
                DataCell(
                  Directionality(
                    textDirection: TextDirection.ltr,
                    child: Text(
                      RowingNumberFormatter.toEnglishDigits('${l['hr_1min'] ?? '-'}'),
                      style: const TextStyle(fontSize: 13, color: EngineRowingUI.textWhite),
                    ),
                  ),
                ),
                DataCell(
                  Directionality(
                    textDirection: TextDirection.ltr,
                    child: Text(
                      RowingNumberFormatter.toEnglishDigits(
                        l['weight'] != null ? (l['weight'] as num).toStringAsFixed(1) : '-',
                      ),
                      style: const TextStyle(fontSize: 13, color: EngineRowingUI.textWhite),
                    ),
                  ),
                ),
                DataCell(
                  Text(
                    fatigueLabels[l['fatigue'] as int?] ?? '-',
                    style: const TextStyle(fontSize: 13, color: EngineRowingUI.textWhite),
                  ),
                ),
              ]),
          ],
        ),
      ),
    );
  }

  /// خلية نبض ملونة حسب مقارنتها بالـ MHR والـ Zone
  Widget _hrCell(int? hr, {String? zone}) {
    if (hr == null) {
      return const Text('-', style: TextStyle(fontSize: 13, color: EngineRowingUI.labelSlate));
    }

    Color textColor = EngineRowingUI.textWhite;
    if (zone != null) {
      final z = zones[zone];
      if (z != null) {
        final lower = (mhr * z[0] / 100).round();
        final upper = (mhr * z[1] / 100).round();
        if (hr < lower - 5) {
          textColor = const Color(0xFF2979FF);
        } else if (hr > upper + 5) {
          textColor = const Color(0xFFFF5252);
        } else {
          textColor = EngineRowingUI.neonLime;
        }
      }
    }

    return Directionality(
      textDirection: TextDirection.ltr,
      child: Text(
        RowingNumberFormatter.toEnglishDigits('$hr'),
        style: TextStyle(fontSize: 13, color: textColor, fontWeight: FontWeight.bold),
      ),
    );
  }
}
