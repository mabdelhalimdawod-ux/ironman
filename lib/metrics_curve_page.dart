import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fl_chart/fl_chart.dart';
import 'db.dart';
import 'app_strings.dart';
import 'heart_rate_zones.dart';
import 'power_calculations.dart';

// ==================== ألوان التصميم الفاخرة (الهوية الجديدة المعتمدة) ====================
const Color _navyDeep = Color(0xFF0A1633);
const Color _navy = Color(0xFF15264F);
const Color _navyLight = Color(0xFF1B4D7E);
const Color _cardSurface = Color(0xFF15264F);
const Color _cardBorder = Color(0xFF11224A);
const Color _gold = Color(0xFFB8F229);
const Color _cyan = Color(0xFF2979FF);
const Color _emerald = Color(0xFFB8F229);
const Color _purple = Color(0xFFE65100);
const Color _coral = Color(0xFFFF5252);

/// الألوان المعتمدة للزونات الخمسة
const Map<String, Color> _zoneColors = {
  'Z1': Color(0xFFB8F229), // فسفوري خفيف
  'Z2': Color(0xFF2979FF), // أزرق متوسط
  'Z3': Color(0xFFFF9100), // برتقالي متوسط
  'Z4': Color(0xFFE65100), // برتقالي غامق
  'Z5': Color(0xFFFF5252), // أحمر خفيف
};

/// المسميات المعتمدة للزونات
const Map<String, String> _zoneLabelsEn = {
  'Z1': 'Z1 Recovery',
  'Z2': 'Z2 UT2',
  'Z3': 'Z3 UT1',
  'Z4': 'Z4 AT',
  'Z5': 'Z5 TR / Max',
};

const Map<String, String> _zoneLabelsAr = {
  'Z1': 'Z1 استشفاء (Recovery)',
  'Z2': 'Z2 هوائي أساسي (UT2)',
  'Z3': 'Z3 هوائي مكثف (UT1)',
  'Z4': 'Z4 عتبة لاهوائية (AT)',
  'Z5': 'Z5 أقصى جهد (TR / Max)',
};

/// الفترات الزمنية المتاحة
enum MetricsPeriod {
  days7,
  days30,
  days90,
  allTime,
  custom,
}

/// صفحة منحنيات مؤشرات التدريب المتطورة (Training Metrics Curves)
/// تشمل المنحنيات الخمسة:
/// 1. EF Curve (معامل الكفاءة)
/// 2. Watts Curve (الواط)
/// 3. Decoupling Curve (التفكك القلبي)
/// 4. Heart Rate Curve (النبض)
/// 5. Zone Curve (زون كيرف مع مربعات الاختيار وتصدير Excel)
class MetricsCurvePage extends StatefulWidget {
  final Map<String, Object?>? initialPlayer;

  const MetricsCurvePage({
    super.key,
    this.initialPlayer,
  });

  @override
  State<MetricsCurvePage> createState() => _MetricsCurvePageState();
}

class _MetricsCurvePageState extends State<MetricsCurvePage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _loading = true;

  // اللاعبون والقائمة
  List<Map<String, Object?>> _players = [];
  Map<String, Object?>? _selectedPlayer; // null يعني متوسط الفريق بالكامل

  // الفترة الزمنية المحددة
  MetricsPeriod _selectedPeriod = MetricsPeriod.days30;
  DateTimeRange? _customDateRange;

  // سجلات التمارين المحملة والمفلترة
  List<Map<String, dynamic>> _rawLogs = [];

  // بيانات منحنى الزون Z1 - Z5
  // Map<zoneKey, Map<dateString, averageWatts>>
  final Map<String, Map<String, double>> _zoneDailyWatts = {
    'Z1': {},
    'Z2': {},
    'Z3': {},
    'Z4': {},
    'Z5': {},
  };

  // حالة مربعات اختيار الزونات (افتراضياً كلها معلّمة كما طلب المستخدم)
  final Set<String> _selectedZones = {'Z1', 'Z2', 'Z3', 'Z4', 'Z5'};

  // نبض الراحة الفعّال للاعب
  int _effectiveRHR = 60;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
        length: 5, vsync: this, initialIndex: 4); // فتح Zone Curve افتراضياً
    _selectedPlayer = widget.initialPlayer;
    _loadInitialData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    setState(() => _loading = true);
    try {
      _players = await DB
          .q('SELECT * FROM players WHERE active = 1 ORDER BY name ASC');
      if (_selectedPlayer == null && _players.isNotEmpty) {
        _selectedPlayer = _players.first;
      }
      await _fetchMetricsData();
    } catch (e) {
      debugPrint('Error loading initial metrics data: $e');
    }
    if (mounted) setState(() => _loading = false);
  }

  DateTimeRange _getDateRange() {
    final now = DateTime.now();
    switch (_selectedPeriod) {
      case MetricsPeriod.days7:
        return DateTimeRange(
          start: now.subtract(const Duration(days: 7)),
          end: now,
        );
      case MetricsPeriod.days30:
        return DateTimeRange(
          start: now.subtract(const Duration(days: 30)),
          end: now,
        );
      case MetricsPeriod.days90:
        return DateTimeRange(
          start: now.subtract(const Duration(days: 90)),
          end: now,
        );
      case MetricsPeriod.allTime:
        return DateTimeRange(
          start: DateTime(2023, 1, 1),
          end: now,
        );
      case MetricsPeriod.custom:
        return _customDateRange ??
            DateTimeRange(
              start: now.subtract(const Duration(days: 30)),
              end: now,
            );
    }
  }

  Future<void> _fetchMetricsData() async {
    final range = _getDateRange();
    final startStr = dstr(range.start);
    final endStr = dstr(range.end);

    int? playerId =
        _selectedPlayer != null ? (_selectedPlayer!['id'] as int?) : null;
    int mhr = _selectedPlayer != null
        ? ((_selectedPlayer!['mhr'] as int?) ?? 190)
        : 190;

    if (playerId != null) {
      _effectiveRHR = await HeartRateZones.getEffectiveRHR(playerId);
    } else {
      _effectiveRHR = 60;
    }

    String query;
    List<Object?> args;

    if (playerId != null) {
      query = '''
        SELECT l.*, s.kind, s.zone as session_zone, p.mhr as player_mhr, p.name as player_name
        FROM logs l
        LEFT JOIN sessions s ON l.date = s.date AND l.idx = s.idx
        JOIN players p ON l.player_id = p.id
        WHERE l.player_id = ? AND l.date >= ? AND l.date <= ?
        ORDER BY l.date ASC, l.idx ASC
      ''';
      args = [playerId, startStr, endStr];
    } else {
      query = '''
        SELECT l.*, s.kind, s.zone as session_zone, p.mhr as player_mhr, p.name as player_name
        FROM logs l
        LEFT JOIN sessions s ON l.date = s.date AND l.idx = s.idx
        JOIN players p ON l.player_id = p.id
        WHERE l.date >= ? AND l.date <= ?
        ORDER BY l.date ASC, l.idx ASC
      ''';
      args = [startStr, endStr];
    }

    final rows = await DB.q(query, args);

    // تصفير بيانات الزونات
    for (final z in ['Z1', 'Z2', 'Z3', 'Z4', 'Z5']) {
      _zoneDailyWatts[z] = {};
    }

    // خريطة مساعدة لتجميع الواط اليومي لكل زون لحساب المتوسط:
    // zone -> date -> List<watts>
    final Map<String, Map<String, List<double>>> zoneAccumulator = {
      'Z1': {},
      'Z2': {},
      'Z3': {},
      'Z4': {},
      'Z5': {},
    };

    final parsedLogs = <Map<String, dynamic>>[];

    for (final row in rows) {
      final date = row['date'] as String? ?? '';
      final watts = (row['avg_power'] as num?)?.toDouble();
      final hr = (row['hr'] as num?)?.toInt();
      final rowMhr = (row['hr_max'] as num?)?.toInt() ??
          (row['player_mhr'] as num?)?.toInt() ??
          mhr;
      final rowRhr = (row['rhr'] as num?)?.toInt() ?? _effectiveRHR;

      // حساب كفاءة الأداء EF
      double? ef = (row['ef'] as num?)?.toDouble();
      if (ef == null && watts != null && hr != null && hr > 0 && watts > 0) {
        ef = PowerCalculations.calculateEF(watts, hr);
      }

      // حساب Decoupling إن وجد
      double? decoupling;
      if (row['player_notes'] != null &&
          row['player_notes'].toString().contains('decoupling:')) {
        final match = RegExp(r'decoupling:\s*([0-9.]+)')
            .firstMatch(row['player_notes'].toString());
        if (match != null) {
          decoupling = double.tryParse(match.group(1)!);
        }
      }

      // ── قراءة الزون المعتمد للتمرين بدقة متناهية ──
      // التركيز الأساسي على خانة الزون المحددة والمثبتة للتمرين (في جدول logs أو sessions)
      // وإذا لم تكن محددة يرجع لحساب كارفونين التلقائي
      final String? assignedZone = (row['zone'] as String?)?.isNotEmpty == true
          ? row['zone'] as String
          : (row['session_zone'] as String?)?.isNotEmpty == true
              ? row['session_zone'] as String
              : (hr != null && hr > 0 && rowMhr > 0)
                  ? HeartRateZones.determineZone(
                      hr: hr, mhr: rowMhr, rhr: rowRhr)
                  : null;

      final item = <String, dynamic>{
        'date': date,
        'idx': row['idx'],
        'watts': watts,
        'hr': hr,
        'rhr': rowRhr,
        'mhr': rowMhr,
        'ef': ef,
        'decoupling': decoupling,
        'zone': assignedZone,
        'photo_path': row['photo_path'],
        'player_name': row['player_name'],
      };
      parsedLogs.add(item);

      // تجميع النقاط لمنحنى الزون: فقط للتمارين التي تم تحديدها بهذا الزون بالذات
      if (assignedZone != null && watts != null && watts > 0) {
        final cleanZone = HeartRateZones.normalizeZoneKey(assignedZone);
        if (zoneAccumulator.containsKey(cleanZone)) {
          zoneAccumulator[cleanZone]!.putIfAbsent(date, () => []).add(watts);
        }
      }
    }

    // حساب متوسط الواط لليوم الواحد لكل زون
    for (final zone in ['Z1', 'Z2', 'Z3', 'Z4', 'Z5']) {
      final daysMap = zoneAccumulator[zone]!;
      for (final entry in daysMap.entries) {
        final date = entry.key;
        final wattsList = entry.value;
        if (wattsList.isNotEmpty) {
          final avg = wattsList.reduce((a, b) => a + b) / wattsList.length;
          _zoneDailyWatts[zone]![date] = double.parse(avg.toStringAsFixed(1));
        }
      }
    }

    _rawLogs = parsedLogs;
  }

  void _onPeriodChanged(MetricsPeriod period) async {
    if (period == MetricsPeriod.custom) {
      final picked = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2023),
        lastDate: DateTime(2030),
        initialDateRange: _customDateRange ??
            DateTimeRange(
              start: DateTime.now().subtract(const Duration(days: 30)),
              end: DateTime.now(),
            ),
      );
      if (picked != null) {
        setState(() {
          _selectedPeriod = MetricsPeriod.custom;
          _customDateRange = picked;
          _loading = true;
        });
        await _fetchMetricsData();
        if (mounted) setState(() => _loading = false);
      }
      return;
    }

    setState(() {
      _selectedPeriod = period;
      _loading = true;
    });
    await _fetchMetricsData();
    if (mounted) setState(() => _loading = false);
  }

  void _onPlayerChanged(Map<String, Object?>? player) async {
    setState(() {
      _selectedPlayer = player;
      _loading = true;
    });
    await _fetchMetricsData();
    if (mounted) setState(() => _loading = false);
  }

  // ==================== تصدير Excel للزونات المعلّمة ====================
  void _exportCheckedZonesToExcel() {
    final s = AppStrings.of(context);

    if (_selectedZones.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(s.selectAtLeastOneZone),
          backgroundColor: Colors.orange.shade800,
        ),
      );
      return;
    }

    // بناء محتوى ملف الـ CSV مع UTF-8 BOM لدعم فتح العربي في Excel فوراً
    final buffer = StringBuffer();
    buffer.write('\uFEFF'); // UTF-8 BOM
    buffer.writeln(s.isArabic
        ? 'التاريخ,الزون,متوسط الواط (W)'
        : 'Date,Zone,Average Watts (W)');

    // جمع التواريخ المتاحة للزونات المحددة وترتيبها
    final allDates = <String>{};
    for (final zone in _selectedZones) {
      final data = _zoneDailyWatts[zone] ?? {};
      allDates.addAll(data.keys);
    }
    final sortedDates = allDates.toList()..sort();

    int totalRows = 0;
    for (final date in sortedDates) {
      for (final zone in ['Z1', 'Z2', 'Z3', 'Z4', 'Z5']) {
        if (_selectedZones.contains(zone)) {
          final watts = _zoneDailyWatts[zone]?[date];
          if (watts != null) {
            final zoneName = s.isArabic
                ? (_zoneLabelsAr[zone] ?? zone)
                : (_zoneLabelsEn[zone] ?? zone);
            buffer.writeln('$date,"$zoneName",$watts');
            totalRows++;
          }
        }
      }
    }

    final csvString = buffer.toString();
    _showExportSuccessModal(csvString, totalRows);
  }

  void _showExportSuccessModal(String csvContent, int rowCount) {
    final s = AppStrings.of(context);
    final playerName = _selectedPlayer != null
        ? _selectedPlayer!['name']
        : (s.isArabic ? 'فريق_التجديف' : 'Team');
    final filename = 'Zone_Curve_${playerName}_${dstr(DateTime.now())}.csv';

    // حفظ تلقائي على القرص إن أمكن
    String savedPath = '';
    try {
      final file = File(filename);
      file.writeAsStringSync(csvContent, encoding: utf8);
      savedPath = file.absolute.path;
    } catch (_) {}

    showModalBottomSheet(
      context: context,
      backgroundColor: _navyDeep,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _emerald.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.table_chart_rounded,
                      color: _emerald, size: 28),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.exportExcelDone,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        s.isArabic
                            ? 'تم تجهيز $rowCount سجل للزونات المعلّمة فقط'
                            : '$rowCount records prepared for checked zones only',
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.7),
                            fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _cardSurface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _cardBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.isArabic ? '📄 اسم الملف المُصدّر:' : '📄 Exported File:',
                    style: const TextStyle(
                        color: _gold,
                        fontSize: 12,
                        fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    savedPath.isNotEmpty ? savedPath : filename,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: _cardBorder),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: csvContent));
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(s.isArabic
                              ? 'تم نسخ بيانات CSV للحافظة بنجاح ✔'
                              : 'CSV copied to clipboard ✔'),
                          backgroundColor: _emerald,
                        ),
                      );
                    },
                    icon: const Icon(Icons.copy_rounded, size: 18),
                    label: Text(s.isArabic ? 'نسخ البيانات CSV' : 'Copy CSV'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: _emerald,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () => Navigator.pop(ctx),
                    icon: const Icon(Icons.check_rounded, size: 18),
                    label: Text(s.close),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);

    return Scaffold(
      backgroundColor: _navyDeep,
      appBar: AppBar(
        backgroundColor: _navyDeep,
        elevation: 0,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                gradient:
                    const LinearGradient(colors: [_navyLight, _cardSurface]),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _gold.withValues(alpha: 0.3)),
              ),
              child:
                  const Icon(Icons.auto_graph_rounded, color: _gold, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.metricsCurvesTitle,
                    style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white),
                  ),
                  Text(
                    s.metricsCurvesSubtitle,
                    style: TextStyle(
                        fontSize: 11,
                        color: Colors.white.withValues(alpha: 0.7)),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
            tooltip: s.loading,
            onPressed: () async {
              setState(() => _loading = true);
              await _fetchMetricsData();
              if (mounted) setState(() => _loading = false);
            },
          ),
          const SizedBox(width: 8),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: _cardSurface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _cardBorder),
            ),
            child: TabBar(
              controller: _tabController,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              indicatorSize: TabBarIndicatorSize.tab,
              dividerColor: Colors.transparent,
              indicator: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [_navyLight, _navy],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 2)),
                ],
              ),
              labelColor: _gold,
              unselectedLabelColor: Colors.white70,
              labelStyle:
                  const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              unselectedLabelStyle: const TextStyle(
                  fontWeight: FontWeight.normal, fontSize: 12.5),
              tabs: [
                Tab(
                    icon: const Icon(Icons.speed_rounded, size: 18),
                    text: s.curveEF),
                Tab(
                    icon: const Icon(Icons.bolt_rounded, size: 18),
                    text: s.curveWatts),
                Tab(
                    icon: const Icon(Icons.trending_down_rounded, size: 18),
                    text: s.curveDecoupling),
                Tab(
                    icon: const Icon(Icons.favorite_rounded, size: 18),
                    text: s.curveHR),
                Tab(
                    icon:
                        const Icon(Icons.stacked_line_chart_rounded, size: 18),
                    text: s.curveZone),
              ],
            ),
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _gold))
          : Column(
              children: [
                // ── شريط التصفية العلوي (اختيار اللاعب والفترة) ──
                _buildTopFilterBar(s),

                // ── محتوى المنحنيات الخمسة ──
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildEFCurveTab(s),
                      _buildWattsCurveTab(s),
                      _buildDecouplingCurveTab(s),
                      _buildHRCurveTab(s),
                      _buildZoneCurveTab(s), // المنحنى الخامس المطلوب
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  // ── شريط التصفية العلوي ──
  Widget _buildTopFilterBar(AppStrings s) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: _cardSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _cardBorder),
      ),
      child: Row(
        children: [
          // اختيار اللاعب
          Expanded(
            flex: 3,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: _navyDeep,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _cardBorder),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<int?>(
                  value: _selectedPlayer != null
                      ? (_selectedPlayer!['id'] as int?)
                      : null,
                  dropdownColor: _navyDeep,
                  isExpanded: true,
                  icon: const Icon(Icons.arrow_drop_down, color: _gold),
                  items: [
                    ..._players.map((p) => DropdownMenuItem<int?>(
                          value: p['id'] as int?,
                          child: Text(
                            p['name'] as String? ?? '',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w600),
                            overflow: TextOverflow.ellipsis,
                          ),
                        )),
                  ],
                  onChanged: (id) {
                    final selected = _players.firstWhere(
                      (p) => p['id'] == id,
                      orElse: () => _players.isNotEmpty ? _players.first : {},
                    );
                    _onPlayerChanged(selected);
                  },
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),

          // اختيار الفترة الزمنية
          Expanded(
            flex: 4,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _periodChip(s.periodLast7Days, MetricsPeriod.days7),
                  const SizedBox(width: 6),
                  _periodChip(s.periodLast30Days, MetricsPeriod.days30),
                  const SizedBox(width: 6),
                  _periodChip(s.periodLast90Days, MetricsPeriod.days90),
                  const SizedBox(width: 6),
                  _periodChip(s.periodAllTime, MetricsPeriod.allTime),
                  const SizedBox(width: 6),
                  _periodChip(s.periodCustomRange, MetricsPeriod.custom),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _periodChip(String label, MetricsPeriod period) {
    final isSelected = _selectedPeriod == period;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => _onPeriodChanged(period),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? _gold : _navyDeep,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? _gold : _cardBorder,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? _navyDeep : Colors.white70,
            fontSize: 11.5,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  // =========================================================================
  // 5. منحنى الزون (Zone Curve / زون كيرف) - المنحنى الخامس الأساسي المطلوب
  // =========================================================================
  Widget _buildZoneCurveTab(AppStrings s) {
    // جمع كل التواريخ المتاحة عبر كافة الزونات وترتيبها زمنياً
    final allDatesSet = <String>{};
    for (final zone in ['Z1', 'Z2', 'Z3', 'Z4', 'Z5']) {
      allDatesSet.addAll(_zoneDailyWatts[zone]!.keys);
    }
    final sortedDates = allDatesSet.toList()..sort();

    // بناء خطوط المنحنى لكل زون متعلّم
    final List<LineChartBarData> lineBars = [];
    double minWatts = 500;
    double maxWatts = 0;

    for (final zone in ['Z1', 'Z2', 'Z3', 'Z4', 'Z5']) {
      // يظهر الخط فقط إذا كان الزون معلّم
      if (_selectedZones.contains(zone)) {
        final data = _zoneDailyWatts[zone]!;
        final spots = <FlSpot>[];

        for (int i = 0; i < sortedDates.length; i++) {
          final date = sortedDates[i];
          if (data.containsKey(date)) {
            final w = data[date]!;
            spots.add(FlSpot(i.toDouble(), w));
            if (w < minWatts) minWatts = w;
            if (w > maxWatts) maxWatts = w;
          }
        }

        if (spots.isNotEmpty) {
          final color = _zoneColors[zone]!;
          lineBars.add(
            LineChartBarData(
              spots: spots,
              isCurved: true,
              curveSmoothness: 0.35,
              color: color,
              barWidth: 3.5,
              isStrokeCapRound: true,
              dotData: FlDotData(
                show: spots.length <= 30,
                getDotPainter: (spot, percent, barData, index) =>
                    FlDotCirclePainter(
                  radius: 4.5,
                  color: color,
                  strokeWidth: 2,
                  strokeColor: Colors.white,
                ),
              ),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  colors: [
                    color.withValues(alpha: 0.25),
                    color.withValues(alpha: 0.02),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
          );
        }
      }
    }

    if (maxWatts == 0) {
      maxWatts = 300;
      minWatts = 100;
    } else {
      minWatts = (minWatts - 20).clamp(0, 1000);
      maxWatts = maxWatts + 30;
    }

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      children: [
        // ── بطاقة شرح الغرض والمعادلة ──
        _buildInfoBanner(
          icon: Icons.stacked_line_chart_rounded,
          accentColor: _gold,
          title: s.curveZone,
          description: s.zoneCurvePurpose,
          extraTag: 'Z1 - Z5 Watts',
        ),
        const SizedBox(height: 14),

        // ── فوق المنحنى: 5 مربعات اختيار (Checkboxes) لزونات Z1 إلى Z5 ──
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _cardSurface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _cardBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.checklist_rounded,
                          color: _gold, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        s.selectZonesPrompt,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  // زر تصدير Excel
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: _emerald,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: _exportCheckedZonesToExcel,
                    icon: const Icon(Icons.file_download_outlined, size: 18),
                    label: Text(
                      s.exportExcel,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // صف المربعات الخمسة
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: ['Z1', 'Z2', 'Z3', 'Z4', 'Z5'].map((zoneKey) {
                  final hasData = _zoneDailyWatts[zoneKey] != null &&
                      _zoneDailyWatts[zoneKey]!.isNotEmpty;
                  final isChecked = _selectedZones.contains(zoneKey);
                  final color = _zoneColors[zoneKey]!;
                  final label = s.isArabic
                      ? (_zoneLabelsAr[zoneKey] ?? zoneKey)
                      : (_zoneLabelsEn[zoneKey] ?? zoneKey);

                  return _buildZoneCheckboxChip(
                    zoneKey: zoneKey,
                    label: label,
                    color: color,
                    hasData: hasData,
                    isChecked: isChecked,
                    noDataText: s.zoneNoData,
                    onToggle: hasData
                        ? () {
                            setState(() {
                              if (isChecked) {
                                _selectedZones.remove(zoneKey);
                              } else {
                                _selectedZones.add(zoneKey);
                              }
                            });
                          }
                        : null,
                  );
                }).toList(),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // ── بطاقة الرسم البياني لمنحنى الزون ──
        Container(
          padding: const EdgeInsets.fromLTRB(14, 20, 16, 16),
          decoration: BoxDecoration(
            color: _cardSurface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _cardBorder),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 4,
                        height: 18,
                        decoration: BoxDecoration(
                          color: _gold,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        s.isArabic
                            ? 'تطور الواط للتمارين المحددة لكل زون'
                            : 'Watts Progression Across Zone Workouts',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    s.isArabic
                        ? 'المحور الرأسي: الواط (W)'
                        : 'Y-Axis: Watts (W)',
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.6),
                        fontSize: 11),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // حالة عدم تعليم أي زون
              if (_selectedZones.isEmpty)
                Container(
                  height: 260,
                  alignment: Alignment.center,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.touch_app_rounded,
                          size: 48, color: Colors.white.withValues(alpha: 0.3)),
                      const SizedBox(height: 12),
                      Text(
                        s.selectAtLeastOneZone,
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.7),
                            fontSize: 14),
                      ),
                    ],
                  ),
                )
              else if (lineBars.isEmpty)
                Container(
                  height: 260,
                  alignment: Alignment.center,
                  child: Text(
                    s.noData,
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.6),
                        fontSize: 14),
                  ),
                )
              else
                Container(
                  height: 310,
                  padding: const EdgeInsets.only(
                      top: 16, right: 14, left: 6, bottom: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.15),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: LineChart(
                    LineChartData(
                      minX: 0,
                      maxX: (sortedDates.length - 1)
                          .toDouble()
                          .clamp(1.0, 1000.0),
                      minY: minWatts,
                      maxY: maxWatts,
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: false,
                        getDrawingHorizontalLine: (value) => const FlLine(
                          color: Color(0xFFE2E8F0),
                          strokeWidth: 1,
                          dashArray: [4, 4],
                        ),
                      ),
                      titlesData: FlTitlesData(
                        rightTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                        topTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 48,
                            getTitlesWidget: (v, _) => Padding(
                              padding: const EdgeInsets.only(left: 4),
                              child: Text(
                                '${v.round()} W',
                                style: const TextStyle(
                                  color: Color(0xFF334155),
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 32,
                            interval:
                                (sortedDates.length / 5).clamp(1.0, 100.0),
                            getTitlesWidget: (v, _) {
                              final idx = v.toInt();
                              if (idx >= 0 && idx < sortedDates.length) {
                                final d = sortedDates[idx];
                                final parts = d.split('-');
                                final label = parts.length >= 3
                                    ? '${parts[1]}/${parts[2]}'
                                    : d;
                                return Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Text(
                                    label,
                                    style: const TextStyle(
                                      color: Color(0xFF334155),
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w600,
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
                      lineTouchData: LineTouchData(
                        enabled: true,
                        touchTooltipData: LineTouchTooltipData(
                          getTooltipItems: (touchedSpots) {
                            return touchedSpots.map((spot) {
                              final idx = spot.x.toInt();
                              final date =
                                  (idx >= 0 && idx < sortedDates.length)
                                      ? sortedDates[idx]
                                      : '';
                              return LineTooltipItem(
                                '$date\n${spot.y.round()} W',
                                TextStyle(
                                  color: spot.bar.color ?? Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              );
                            }).toList();
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 16),

              // ── الدليل البياني (Legend) أسفل المنحنى يعرض الزونات المعلّمة فقط ──
              if (_selectedZones.isNotEmpty) ...[
                const Divider(color: _cardBorder, height: 24),
                Wrap(
                  spacing: 16,
                  runSpacing: 8,
                  children: _selectedZones.map((zKey) {
                    final color = _zoneColors[zKey]!;
                    final label = s.isArabic
                        ? (_zoneLabelsAr[zKey] ?? zKey)
                        : (_zoneLabelsEn[zKey] ?? zKey);
                    final count = _zoneDailyWatts[zKey]?.length ?? 0;
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 1.5),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '$label ($count ${s.isArabic ? 'يوم' : 'days'})',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  /// مربع اختيار الزون فوق المنحنى مع معالجة غياب البيانات
  Widget _buildZoneCheckboxChip({
    required String zoneKey,
    required String label,
    required Color color,
    required bool hasData,
    required bool isChecked,
    required String noDataText,
    required VoidCallback? onToggle,
  }) {
    if (!hasData) {
      // زون مفيهوش بيانات: مربعه يتعطل من غير خط ولا أصفار
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: _navyDeep.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_box_outline_blank,
                color: Colors.white.withValues(alpha: 0.2), size: 18),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.3), fontSize: 12),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                noDataText,
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.4), fontSize: 10),
              ),
            ),
          ],
        ),
      );
    }

    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onToggle,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: isChecked ? color.withValues(alpha: 0.2) : _navyDeep,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isChecked ? color : _cardBorder,
            width: isChecked ? 1.5 : 1.0,
          ),
          boxShadow: isChecked
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isChecked
                  ? Icons.check_box_rounded
                  : Icons.check_box_outline_blank_rounded,
              color: isChecked ? color : Colors.white60,
              size: 20,
            ),
            const SizedBox(width: 6),
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: isChecked ? Colors.white : Colors.white70,
                fontSize: 12,
                fontWeight: isChecked ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // =========================================================================
  // 1. منحنى معامل الكفاءة (Efficiency Factor Curve / EF Curve)
  // =========================================================================
  Widget _buildEFCurveTab(AppStrings s) {
    final validLogs = _rawLogs
        .where((l) => l['ef'] != null && (l['ef'] as double) > 0)
        .toList();
    final spots = <FlSpot>[];
    double totalEf = 0;
    double maxEf = 0;

    for (int i = 0; i < validLogs.length; i++) {
      final ef = validLogs[i]['ef'] as double;
      spots.add(FlSpot(i.toDouble(), ef));
      totalEf += ef;
      if (ef > maxEf) maxEf = ef;
    }
    final avgEf = spots.isNotEmpty ? totalEf / spots.length : 0.0;

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      children: [
        _buildInfoBanner(
          icon: Icons.speed_rounded,
          accentColor: _cyan,
          title: s.curveEF,
          description: s.efMetricDesc,
          extraTag: 'EF = Watts / HR',
        ),
        const SizedBox(height: 14),
        _buildStatsSummaryRow(
          items: [
            _StatCardItem(
                label: s.currentAvgEF,
                value: avgEf > 0 ? avgEf.toStringAsFixed(2) : '-',
                color: _cyan),
            _StatCardItem(
                label: s.isArabic ? 'أعلى EF' : 'Peak EF',
                value: maxEf > 0 ? maxEf.toStringAsFixed(2) : '-',
                color: _emerald),
            _StatCardItem(
                label: s.isArabic ? 'عدد التمارين' : 'Workouts',
                value: spots.length.toString(),
                color: _gold),
          ],
        ),
        const SizedBox(height: 16),
        _buildStandardChartCard(
          title: s.efTrendTitle,
          unit: 'W/bpm',
          spots: spots,
          primaryColor: _cyan,
          refLine: avgEf > 0 ? avgEf : null,
          refLineLabel: '${s.baselineEF}: ${avgEf.toStringAsFixed(2)}',
          dates: validLogs.map((l) => l['date'] as String).toList(),
        ),
      ],
    );
  }

  // =========================================================================
  // 2. منحنى القدرة (Watts Curve / منحنى الواط)
  // =========================================================================
  Widget _buildWattsCurveTab(AppStrings s) {
    final validLogs = _rawLogs
        .where((l) => l['watts'] != null && (l['watts'] as double) > 0)
        .toList();
    final spots = <FlSpot>[];
    double totalWatts = 0;
    double maxWatts = 0;

    for (int i = 0; i < validLogs.length; i++) {
      final w = validLogs[i]['watts'] as double;
      spots.add(FlSpot(i.toDouble(), w));
      totalWatts += w;
      if (w > maxWatts) maxWatts = w;
    }
    final avgWatts = spots.isNotEmpty ? totalWatts / spots.length : 0.0;

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      children: [
        _buildInfoBanner(
          icon: Icons.bolt_rounded,
          accentColor: _gold,
          title: s.curveWatts,
          description: s.isArabic
              ? 'متابعة تطور القوة والواط الميكانيكي المستمر عبر التمارين والأزمنة'
              : 'Monitor mechanical power output and sustained wattage across workouts',
          extraTag: 'Watts & Pace 500m',
        ),
        const SizedBox(height: 14),
        _buildStatsSummaryRow(
          items: [
            _StatCardItem(
                label: s.avgWattsLabel,
                value: avgWatts > 0 ? '${avgWatts.round()} W' : '-',
                color: _gold),
            _StatCardItem(
                label: s.maxWattsLabel,
                value: maxWatts > 0 ? '${maxWatts.round()} W' : '-',
                color: _coral),
            _StatCardItem(
              label: s.isArabic ? 'معادل Split' : 'Equiv Split',
              value: avgWatts > 0 ? formatSplit(wattsToSplit(avgWatts)) : '-',
              color: _cyan,
            ),
          ],
        ),
        const SizedBox(height: 16),
        _buildStandardChartCard(
          title: s.isArabic ? 'منحنى متوسط الواط' : 'Average Watts Curve',
          unit: 'W',
          spots: spots,
          primaryColor: _gold,
          refLine: avgWatts > 0 ? avgWatts : null,
          refLineLabel: 'المتوسط: ${avgWatts.round()} W',
          dates: validLogs.map((l) => l['date'] as String).toList(),
        ),
      ],
    );
  }

  // =========================================================================
  // 3. منحنى التفكك القلبي (Decoupling Curve)
  // =========================================================================
  Widget _buildDecouplingCurveTab(AppStrings s) {
    final validLogs = _rawLogs.where((l) => l['decoupling'] != null).toList();
    final spots = <FlSpot>[];
    for (int i = 0; i < validLogs.length; i++) {
      final d = validLogs[i]['decoupling'] as double;
      spots.add(FlSpot(i.toDouble(), d));
    }

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      children: [
        _buildInfoBanner(
          icon: Icons.trending_down_rounded,
          accentColor: _purple,
          title: s.curveDecoupling,
          description: s.isArabic
              ? 'مقياس الانجراف القلبي (Pw:HR Drift). القيم الأقل من 5% تدل على ثبات هوائي ممتاز.'
              : 'Aerobic decoupling (Pw:HR Drift). Values below 5% indicate elite aerobic stamina.',
          extraTag: 'Target: < 5.0%',
        ),
        const SizedBox(height: 14),
        _buildStandardChartCard(
          title: s.isArabic
              ? 'منحنى التفكك والانجراف القلبي'
              : 'Cardiac Decoupling Drift Curve',
          unit: '%',
          spots: spots,
          primaryColor: _purple,
          refLine: 5.0,
          refLineLabel: s.isArabic ? 'عتبة 5% (حد الاستقرار)' : 'Threshold 5%',
          dates: validLogs.map((l) => l['date'] as String).toList(),
        ),
      ],
    );
  }

  // =========================================================================
  // 4. منحنى النبض (Heart Rate Curve)
  // =========================================================================
  Widget _buildHRCurveTab(AppStrings s) {
    final validLogs =
        _rawLogs.where((l) => l['hr'] != null && (l['hr'] as int) > 0).toList();
    final spots = <FlSpot>[];
    double totalHr = 0;
    int maxHr = 0;

    for (int i = 0; i < validLogs.length; i++) {
      final hr = validLogs[i]['hr'] as int;
      spots.add(FlSpot(i.toDouble(), hr.toDouble()));
      totalHr += hr;
      if (hr > maxHr) maxHr = hr;
    }
    final avgHr = spots.isNotEmpty ? totalHr / spots.length : 0.0;

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      children: [
        _buildInfoBanner(
          icon: Icons.favorite_rounded,
          accentColor: _coral,
          title: s.curveHR,
          description: s.isArabic
              ? 'تتبع استجابة النبض في التمارين مقارنة بنبض الراحة والحد الأقصى'
              : 'Heart rate response tracking during sessions relative to resting & max HR',
          extraTag: 'BPM Tracking',
        ),
        const SizedBox(height: 14),
        _buildStatsSummaryRow(
          items: [
            _StatCardItem(
                label: s.isArabic ? 'متوسط النبض' : 'Avg HR',
                value: avgHr > 0 ? '${avgHr.round()} bpm' : '-',
                color: _coral),
            _StatCardItem(
                label: s.maxHRLabel,
                value: maxHr > 0 ? '$maxHr bpm' : '-',
                color: _gold),
            _StatCardItem(
                label: s.rhrLabel, value: '$_effectiveRHR bpm', color: _cyan),
          ],
        ),
        const SizedBox(height: 16),
        _buildStandardChartCard(
          title: s.isArabic ? 'منحنى نبض التمارين' : 'Workout Heart Rate Curve',
          unit: 'bpm',
          spots: spots,
          primaryColor: _coral,
          refLine: avgHr > 0 ? avgHr : null,
          refLineLabel: 'المتوسط: ${avgHr.round()} bpm',
          dates: validLogs.map((l) => l['date'] as String).toList(),
        ),
      ],
    );
  }

  // ==================== بطاقة الرسم البياني الموحدة ====================
  Widget _buildStandardChartCard({
    required String title,
    required String unit,
    required List<FlSpot> spots,
    required Color primaryColor,
    required List<String> dates,
    double? refLine,
    String? refLineLabel,
  }) {
    if (spots.isEmpty) {
      return Container(
        height: 250,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: _cardSurface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _cardBorder),
        ),
        child: Text(
          'لا توجد بيانات مسجلة في هذه الفترة',
          style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6), fontSize: 14),
        ),
      );
    }

    double minY = spots.map((s) => s.y).reduce((a, b) => a < b ? a : b);
    double maxY = spots.map((s) => s.y).reduce((a, b) => a > b ? a : b);
    minY = (minY * 0.9).clamp(0, 1000);
    maxY = maxY * 1.1;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 20, 16, 16),
      decoration: BoxDecoration(
        color: _cardSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _cardBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14.5,
                    fontWeight: FontWeight.bold),
              ),
              Text(
                unit,
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6), fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Container(
            height: 290,
            padding:
                const EdgeInsets.only(top: 16, right: 14, left: 6, bottom: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: LineChart(
              LineChartData(
                minX: 0,
                maxX: (spots.length - 1).toDouble().clamp(1.0, 1000.0),
                minY: minY,
                maxY: maxY,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (value) => const FlLine(
                    color: Color(0xFFE2E8F0),
                    strokeWidth: 1,
                    dashArray: [4, 4],
                  ),
                ),
                titlesData: FlTitlesData(
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 48,
                      getTitlesWidget: (v, _) => Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: Text(
                          v.toStringAsFixed(
                              unit == 'W/bpm' || unit == '%' ? 1 : 0),
                          style: const TextStyle(
                            color: Color(0xFF334155),
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 32,
                      interval: (spots.length / 5).clamp(1.0, 100.0),
                      getTitlesWidget: (v, _) {
                        final idx = v.toInt();
                        if (idx >= 0 && idx < dates.length) {
                          final d = dates[idx];
                          final parts = d.split('-');
                          final label =
                              parts.length >= 3 ? '${parts[1]}/${parts[2]}' : d;
                          return Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              label,
                              style: const TextStyle(
                                color: Color(0xFF334155),
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
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
                extraLinesData: refLine != null
                    ? ExtraLinesData(horizontalLines: [
                        HorizontalLine(
                          y: refLine,
                          color: _gold.withValues(alpha: 0.6),
                          strokeWidth: 1.5,
                          dashArray: [6, 4],
                          label: HorizontalLineLabel(
                            show: true,
                            alignment: Alignment.topRight,
                            labelResolver: (_) => refLineLabel ?? '',
                            style: const TextStyle(
                                color: _gold,
                                fontSize: 10,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                      ])
                    : null,
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    curveSmoothness: 0.35,
                    color: primaryColor,
                    barWidth: 3.5,
                    isStrokeCapRound: true,
                    dotData: FlDotData(
                      show: spots.length <= 30,
                      getDotPainter: (spot, percent, barData, index) =>
                          FlDotCirclePainter(
                        radius: 4,
                        color: primaryColor,
                        strokeWidth: 2,
                        strokeColor: Colors.white,
                      ),
                    ),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        colors: [
                          primaryColor.withValues(alpha: 0.25),
                          primaryColor.withValues(alpha: 0.02),
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),
                ],
                lineTouchData: LineTouchData(
                  enabled: true,
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipItems: (touchedSpots) {
                      return touchedSpots.map((spot) {
                        final idx = spot.x.toInt();
                        final date =
                            (idx >= 0 && idx < dates.length) ? dates[idx] : '';
                        return LineTooltipItem(
                          '$date\n${spot.y.toStringAsFixed(1)} $unit',
                          TextStyle(
                            color: primaryColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        );
                      }).toList();
                    },
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── لافتة الشرح التعريفية لكل كيرف ──
  Widget _buildInfoBanner({
    required IconData icon,
    required Color accentColor,
    required String title,
    required String description,
    required String extraTag,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            accentColor.withValues(alpha: 0.12),
            _cardSurface,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accentColor.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: accentColor, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: accentColor.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        extraTag,
                        style: TextStyle(
                          color: accentColor,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  description,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.8),
                    fontSize: 12.5,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── صف البطاقات الإحصائية ──
  Widget _buildStatsSummaryRow({required List<_StatCardItem> items}) {
    return Row(
      children: items
          .map((item) => Expanded(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  padding:
                      const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
                  decoration: BoxDecoration(
                    color: _cardSurface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: _cardBorder),
                  ),
                  child: Column(
                    children: [
                      Text(
                        item.label,
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.65),
                            fontSize: 11.5),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        item.value,
                        style: TextStyle(
                          color: item.color,
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ))
          .toList(),
    );
  }
}

class _StatCardItem {
  final String label;
  final String value;
  final Color color;

  const _StatCardItem({
    required this.label,
    required this.value,
    required this.color,
  });
}
