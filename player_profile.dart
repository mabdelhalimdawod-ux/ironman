import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'db.dart';
import 'dart:math';

// ==================== ألوان التصميم ====================
const _navy = Color(0xFF0D3B66);
const _sky = Color(0xFFD6EEFB);
const _yellow = Color(0xFFFFC93C);
const _green = Color(0xFF4CAF50);
const _orange = Color(0xFFFF9800);
const _red = Color(0xFFF44336);

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
  int get mhr => p['mhr'] as int;

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
    return Scaffold(
      appBar: AppBar(
        title: Text('${p['name']}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              setState(() => loading = true);
              loadAll();
            },
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : logs.isEmpty
              ? _emptyState()
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _playerCard(),
                    if (alerts.isNotEmpty) ...[
                      _sectionTitle('🚨 تنبيهات'),
                      _alertsCard(),
                    ],
                    _sectionTitle('🎯 مؤشر الجاهزية'),
                    _readinessCard(),
                    _sectionTitle('⚖️ التوازن الفسيولوجي'),
                    _balanceRadar(),
                    _sectionTitle('❤️ اتجاه نبض الراحة (RHR)'),
                    _rhrChart(),
                    _sectionTitle('💓 اتجاه تغير النبض (HRV)'),
                    _hrvChart(),
                    _sectionTitle('🔄 الاستشفاء'),
                    _recoveryChart(),
                    _sectionTitle('⚖️ الوزن'),
                    _weightChart(),
                    _sectionTitle('📊 توزيع مناطق التدريب'),
                    _zonesChart(),
                    _sectionTitle('📋 آخر التسجيلات'),
                    _recentLogsTable(),
                    const SizedBox(height: 32),
                  ],
                ),
    );
  }

  Widget _emptyState() => const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.insert_chart_outlined, size: 80, color: Colors.grey),
            SizedBox(height: 16),
            Text('لا توجد بيانات مسجلة بعد',
                style: TextStyle(fontSize: 20, color: Colors.grey)),
            SizedBox(height: 8),
            Text('سجّل بيانات اللاعب من صفحة "تسجيل"',
                style: TextStyle(color: Colors.grey)),
          ],
        ),
      );

  Widget _sectionTitle(String t) => Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 8),
      child: Text(t,
          style: const TextStyle(
              fontSize: 20, fontWeight: FontWeight.bold, color: _navy)));

  // ==================== بطاقة اللاعب ====================
  Widget _playerCard() {
    final latest = logs.isNotEmpty ? logs.first : null;
    final sessionCount7 = logs.where((l) {
      final d = DateTime.tryParse(l['date'] as String? ?? '');
      return d != null && DateTime.now().difference(d).inDays <= 7;
    }).length;

    return Card(
      color: _navy,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              CircleAvatar(
                radius: 30,
                backgroundColor: _yellow,
                child: Text('${p['name'].toString()[0]}',
                    style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: _navy)),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${p['name']}',
                        style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.white)),
                    Text('MHR: $mhr  •  الحالة: ${p['active'] == 1 ? 'نشط' : 'غير نشط'}',
                        style: TextStyle(
                            fontSize: 16, color: Colors.white.withOpacity(0.8))),
                  ],
                ),
              ),
            ]),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _statChip('حصص الأسبوع', '$sessionCount7'),
                _statChip('إجمالي السجلات', '${logs.length}'),
                if (latest != null && latest['rhr'] != null)
                  _statChip('آخر RHR', '${latest['rhr']}'),
                if (baseline.isNotEmpty && baseline['avg_rhr'] != null)
                  _statChip('متوسط RHR', '${baseline['avg_rhr']?.round()}'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _statChip(String label, String value) => Column(children: [
        Text(value,
            style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: _yellow)),
        Text(label,
            style: TextStyle(
                fontSize: 12, color: Colors.white.withOpacity(0.7))),
      ]);

  // ==================== التنبيهات ====================
  Widget _alertsCard() => Card(
        color: const Color(0xFFFFF3E0),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final a in alerts)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(a, style: const TextStyle(fontSize: 16)),
                ),
            ],
          ),
        ),
      );

  // ==================== مؤشر الجاهزية ====================
  Widget _readinessCard() {
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

    final color = Color(readinessColor(score));
    final text = readinessText(score);

    return Card(
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
                  strokeWidth: 12,
                  backgroundColor: Colors.grey.shade200,
                  valueColor: AlwaysStoppedAnimation(color),
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('${score.round()}%',
                      style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: color)),
                  Text(text,
                      style: TextStyle(fontSize: 16, color: color)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (latest != null) ...[
            _readinessDetail('نبض الراحة', '${latest['rhr'] ?? '-'}',
                'المتوسط: ${baseline['avg_rhr']?.round() ?? '-'}'),
            _readinessDetail('تغير النبض', '${latest['hrv'] ?? '-'}',
                'المتوسط: ${baseline['avg_hrv']?.round() ?? '-'}'),
            _readinessDetail('الإرهاق',
                fatigueLabels[latest['fatigue'] as int?] ?? '-', ''),
            _readinessDetail('النوم',
                '${latest['sleep_hours'] ?? '-'} ساعات', ''),
          ],
        ]),
      ),
    );
  }

  Widget _readinessDetail(String label, String value, String sub) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Expanded(
            child: Text(label,
                style: const TextStyle(fontSize: 16, color: Colors.grey))),
        Text(value,
            style:
                const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        if (sub.isNotEmpty) ...[
          const SizedBox(width: 8),
          Text(sub,
              style: const TextStyle(fontSize: 13, color: Colors.grey)),
        ],
      ]));

  // ==================== رادار التوازن الفسيولوجي ====================
  Widget _balanceRadar() {
    if (balance.isEmpty) {
      return const Card(
          child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('لا توجد بيانات كافية لعرض التوازن')));
    }

    final keys = balance.keys.toList();
    final values = balance.values.toList();
    final avgScore = values.reduce((a, b) => a + b) / values.length;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          Text('المؤشر العام: ${avgScore.round()}%',
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(readinessColor(avgScore)))),
          const SizedBox(height: 16),
          SizedBox(
            height: 280,
            child: RadarChart(
              RadarChartData(
                radarShape: RadarShape.polygon,
                radarBorderData:
                    const BorderSide(color: Colors.transparent),
                gridBorderData:
                    BorderSide(color: Colors.grey.shade300, width: 1),
                tickBorderData:
                    const BorderSide(color: Colors.transparent),
                tickCount: 4,
                ticksTextStyle: const TextStyle(fontSize: 0),
                titleTextStyle: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: _navy),
                getTitle: (i, _) =>
                    RadarChartTitle(text: keys[i]),
                dataSets: [
                  RadarDataSet(
                    dataEntries: [
                      for (final v in values) RadarEntry(value: v)
                    ],
                    fillColor: _navy.withOpacity(0.15),
                    borderColor: _navy,
                    borderWidth: 2.5,
                    entryRadius: 4,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          // شرح المحاور
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (int i = 0; i < keys.length; i++)
                Chip(
                  label: Text('${keys[i]}: ${values[i].round()}%',
                      style: const TextStyle(fontSize: 12)),
                  backgroundColor: Color(readinessColor(values[i]))
                      .withOpacity(0.2),
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
    String? yLabel,
    double? refLine,
    String? refLabel,
  }) {
    if (spots.length < 2) {
      return const Card(
          child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('بيانات غير كافية (مطلوب نقطتان على الأقل)')));
    }

    final minY = spots.map((s) => s.y).reduce(min) - 5;
    final maxY = spots.map((s) => s.y).reduce(max) + 5;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: SizedBox(
          height: 200,
          child: LineChart(
            LineChartData(
              minY: minY,
              maxY: maxY,
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: ((maxY - minY) / 4).clamp(1, 50),
                getDrawingHorizontalLine: (v) => FlLine(
                    color: Colors.grey.shade200, strokeWidth: 1),
              ),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false)),
                bottomTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false)),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 40,
                    getTitlesWidget: (v, _) => Text('${v.round()}',
                        style: const TextStyle(
                            fontSize: 11, color: Colors.grey)),
                  ),
                ),
              ),
              borderData: FlBorderData(show: false),
              extraLinesData: refLine != null
                  ? ExtraLinesData(horizontalLines: [
                      HorizontalLine(
                        y: refLine,
                        color: Colors.red.withOpacity(0.5),
                        strokeWidth: 1.5,
                        dashArray: [8, 4],
                        label: HorizontalLineLabel(
                          show: true,
                          labelResolver: (_) => refLabel ?? '',
                          style: const TextStyle(
                              fontSize: 11, color: Colors.red),
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
                        FlDotCirclePainter(
                            radius: 3,
                            color: color,
                            strokeWidth: 0),
                  ),
                  belowBarData: BarAreaData(
                    show: true,
                    color: color.withOpacity(0.1),
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
                                fontSize: 14),
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
      Colors.red.shade400,
      refLine: baseline['avg_rhr'],
      refLabel: 'المتوسط: ${baseline['avg_rhr']?.round() ?? ''}',
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
      Colors.blue.shade400,
      refLine: baseline['avg_hrv'],
      refLabel: 'المتوسط: ${baseline['avg_hrv']?.round() ?? ''}',
    );
  }

  // ==================== الاستشفاء ====================
  Widget _recoveryChart() {
    if (recoveryData.isEmpty) {
      return const Card(
          child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('لا توجد بيانات استشفاء (سجّل النبض بعد التمرين)')));
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
      _lineChartCard(spots, _green, refLine: 20, refLabel: 'هدف: 20%+'),
      const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16),
        child: Text(
          '💡 نسبة الاستشفاء = مدى انخفاض النبض بعد التمرين. أعلى من 20% = ممتاز',
          style: TextStyle(fontSize: 13, color: Colors.grey),
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
      _orange,
      refLine: baseline['avg_weight'],
      refLabel: 'المتوسط: ${baseline['avg_weight']?.toStringAsFixed(1) ?? ''}',
    );
  }

  // ==================== توزيع المناطق ====================
  Widget _zonesChart() {
    if (zonesDist.isEmpty) {
      return const Card(
          child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('لا توجد بيانات كافية')));
    }

    final colors = [
      Colors.green.shade300,
      Colors.blue.shade300,
      Colors.orange.shade300,
      Colors.red.shade300,
      Colors.purple.shade300,
    ];

    final totalSessions =
        zonesDist.values.fold<int>(0, (a, b) => a + b);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          SizedBox(
            height: 200,
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: (zonesDist.values.reduce(max) + 2).toDouble(),
                gridData: const FlGridData(show: false),
                borderData: FlBorderData(show: false),
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
                      getTitlesWidget: (v, _) {
                        final keys = zonesDist.keys.toList();
                        if (v.toInt() < keys.length) {
                          return Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(keys[v.toInt()],
                                style: const TextStyle(fontSize: 11)),
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
                        width: 28,
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(6)),
                      ),
                    ]),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text('إجمالي: $totalSessions حصة في آخر 30 يوم',
              style: const TextStyle(color: Colors.grey)),
        ]),
      ),
    );
  }

  // ==================== جدول آخر التسجيلات ====================
  Widget _recentLogsTable() {
    final recentLogs = logs.take(15).toList();
    if (recentLogs.isEmpty) {
      return const Card(
          child: Padding(
              padding: EdgeInsets.all(16), child: Text('لا توجد سجلات')));
    }

    return Card(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(_sky),
          columnSpacing: 14,
          columns: const [
            DataColumn(label: Text('التاريخ', style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(label: Text('النوع', style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(label: Text('RHR', style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(label: Text('HRV', style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(label: Text('النبض', style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(label: Text('أقصى', style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(label: Text('بعد', style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(label: Text('دقيقة', style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(label: Text('الوزن', style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(label: Text('إرهاق', style: TextStyle(fontWeight: FontWeight.bold))),
          ],
          rows: [
            for (final l in recentLogs)
              DataRow(cells: [
                DataCell(Text('${l['date'] ?? ''}', style: const TextStyle(fontSize: 13))),
                DataCell(Text('${l['kind'] ?? '-'}', style: const TextStyle(fontSize: 13))),
                DataCell(_hrCell(l['rhr'] as int?)),
                DataCell(Text('${l['hrv'] ?? '-'}', style: const TextStyle(fontSize: 13))),
                DataCell(_hrCell(l['hr'] as int?, zone: l['zone'] as String?)),
                DataCell(Text('${l['hr_max'] ?? '-'}', style: const TextStyle(fontSize: 13))),
                DataCell(Text('${l['hr_post'] ?? '-'}', style: const TextStyle(fontSize: 13))),
                DataCell(Text('${l['hr_1min'] ?? '-'}', style: const TextStyle(fontSize: 13))),
                DataCell(Text(
                    l['weight'] != null
                        ? (l['weight'] as num).toStringAsFixed(1)
                        : '-',
                    style: const TextStyle(fontSize: 13))),
                DataCell(Text(
                    fatigueLabels[l['fatigue'] as int?] ?? '-',
                    style: const TextStyle(fontSize: 13))),
              ]),
          ],
        ),
      ),
    );
  }

  /// خلية نبض ملونة حسب مقارنتها بالـ MHR والـ Zone
  Widget _hrCell(int? hr, {String? zone}) {
    if (hr == null) return const Text('-', style: TextStyle(fontSize: 13));

    Color textColor = Colors.black;
    if (zone != null) {
      final z = zones[zone];
      if (z != null) {
        final lower = (mhr * z[0] / 100).round();
        final upper = (mhr * z[1] / 100).round();
        if (hr < lower - 5) {
          textColor = Colors.blue; // أقل من المطلوب
        } else if (hr > upper + 5) {
          textColor = Colors.red; // أعلى من المطلوب
        } else {
          textColor = _green; // في النطاق
        }
      }
    }

    return Text('$hr',
        style: TextStyle(
            fontSize: 13, color: textColor, fontWeight: FontWeight.bold));
  }
}
