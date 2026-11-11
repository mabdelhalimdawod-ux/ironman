import 'dart:convert';
import 'dart:math';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'app_strings.dart';
import 'auth_service.dart';
import 'db.dart';
import 'engine_rowing_ui.dart';
import 'heart_rate_zones.dart';
import 'power_calculations.dart';
import 'progress_calcs.dart';
import 'progress_curve_header.dart';
import 'progress_period_filter.dart';

/// أنواع الشاشات والمنحنيات السبعة داخل تبويب Progress
enum ProgressCurveType {
  matrixZone,
  efAndDecoupling,
  watts,
  pmcLoad,
  recovery,
  zoneHours,
  cpTests,
}

/// البيانات المحملة والمحسوبة للاعب واحد ضمن الفترة المختارة
class _AthleteCurveData {
  final int playerId;
  final String name;
  final int mhr;
  final int effectiveRhr;

  // نقاط المنحنيات الزمنية
  final List<DateValuePoint> hrvPoints;
  final List<DateValuePoint> rhrPoints;
  final List<DateValuePoint> sleepPoints;
  final List<DateValuePoint> weightPoints;
  final List<DateValuePoint> eupneaPoints;
  final List<DateValuePoint> efPoints;
  final List<DateValuePoint> decouplingPoints;
  final List<DateValuePoint> overallWattsPoints;
  final Map<String, List<DateValuePoint>> zoneWattsPoints;

  // نقاط Matrix Zone (% HRR, Watts)
  final List<({double hrrPct, double watts, String date})> matrixPoints;

  // ساعات الزونات
  final List<ZoneHoursEntry> zoneHours;

  // بيانات PMC (من جدول daily_load)
  final List<DailyLoadEntry> pmcEntries;
  final DailyLoadEntry? todayLoad;
  final int missingCpWorkoutsCount;
  final List<String> missingCpDates;

  // اختبارات CP
  final List<DateValuePoint> cpValuePoints;
  final List<Map<String, Object?>> cpTestRows;
  final double? latestCp;
  final double? latestWPrime;

  const _AthleteCurveData({
    required this.playerId,
    required this.name,
    required this.mhr,
    required this.effectiveRhr,
    required this.hrvPoints,
    required this.rhrPoints,
    required this.sleepPoints,
    required this.weightPoints,
    required this.eupneaPoints,
    required this.efPoints,
    required this.decouplingPoints,
    required this.overallWattsPoints,
    required this.zoneWattsPoints,
    required this.matrixPoints,
    required this.zoneHours,
    required this.pmcEntries,
    required this.todayLoad,
    required this.missingCpWorkoutsCount,
    required this.missingCpDates,
    required this.cpValuePoints,
    required this.cpTestRows,
    required this.latestCp,
    required this.latestWPrime,
  });
}

/// شاشة عرض ومقارنة منحنى (أو جدول) واحد للاعبي الفريق
/// - أعلى منطقة الرسم: شريط فلتر المدة المشترك وتحته قائمة كل لاعبي الفريق
/// - الضغط على لاعب يضيف/يزيل منحناه محلياً (setState) بدون استعلام غير ضروري لبقية اللاعبين
/// - المنحنيات المتتالية ملزوقة بدون أي فراغ (margin & padding = 0)
/// - Matrix Zone يعرض رسماً واحداً بمحورين مشتركين بدلاً من الرسم المتتالي
class ProgressCurvePage extends StatefulWidget {
  final ProgressCurveType curveType;
  final AppUser? user;
  final ProgressPeriodSelection? initialPeriod;

  const ProgressCurvePage({
    super.key,
    required this.curveType,
    this.user,
    this.initialPeriod,
  });

  @override
  State<ProgressCurvePage> createState() => _ProgressCurvePageState();
}

class _ProgressCurvePageState extends State<ProgressCurvePage> {
  /// ألوان ثابتة ومميزة لكل لاعب على مستوى الشاشة كلها
  static const List<Color> _athletePalette = [
    Color(0xFF9ED82E), // Neon Lime
    Color(0xFF00E5FF), // Cyan
    Color(0xFFFF9100), // Orange
    Color(0xFFB388FF), // Violet
    Color(0xFFFF4081), // Pink
    Color(0xFF69F0AE), // Mint
    Color(0xFF40C4FF), // Light Blue
    Color(0xFFFFD600), // Amber Yellow
    Color(0xFFFF5252), // Coral Red
    Color(0xFF1DE9B6), // Teal
    Color(0xFFFF6D00), // Deep Orange
    Color(0xFF7C4DFF), // Deep Purple
  ];

  bool _loadingRoster = true;
  List<Map<String, Object?>> _players = [];
  final Map<int, Color> _athleteColors = {};
  final List<int> _selectedPlayerIds = [];
  final Map<int, _AthleteCurveData> _athleteCache = {};
  final Set<int> _loadingPlayerIds = {};

  late ProgressPeriodSelection _period;
  String? _selectedWattsZone; // null = جميع الزونات

  @override
  void initState() {
    super.initState();
    _period = widget.initialPeriod ?? ProgressPeriodSelection.defaultWeek();
    _loadRosterAndInitial();
  }

  String _titleForType(AppStrings s) {
    switch (widget.curveType) {
      case ProgressCurveType.matrixZone:
        return s.matrixZoneTitle;
      case ProgressCurveType.efAndDecoupling:
        return s.efDecouplingTitle;
      case ProgressCurveType.watts:
        return s.wattsCurveTitle;
      case ProgressCurveType.pmcLoad:
        return s.pmcLoadTitle;
      case ProgressCurveType.recovery:
        return s.recoveryCurvesTitle;
      case ProgressCurveType.zoneHours:
        return s.zoneHoursTitle;
      case ProgressCurveType.cpTests:
        return s.cpTestsCurveTitle;
    }
  }

  Color _colorForAthlete(int playerId) {
    return _athleteColors[playerId] ??
        _athletePalette[playerId.abs() % _athletePalette.length];
  }

  Future<void> _loadRosterAndInitial() async {
    setState(() => _loadingRoster = true);
    try {
      await DB.db;
      final players = await DB.players();
      _players = players;

      // تعيين لون ثابت لكل لاعب بناءً على ترتيبه بالـ id لضمان عدم تغيّر اللون أبداً
      final byId = List<Map<String, Object?>>.from(players)
        ..sort((a, b) =>
            ((a['id'] as num?)?.toInt() ?? 0)
                .compareTo((b['id'] as num?)?.toInt() ?? 0));
      _athleteColors.clear();
      for (int i = 0; i < byId.length; i++) {
        final pid = (byId[i]['id'] as num?)?.toInt();
        if (pid != null) {
          _athleteColors[pid] = _athletePalette[i % _athletePalette.length];
        }
      }

      if (_selectedPlayerIds.isEmpty && _players.isNotEmpty) {
        final userId = widget.user?.id;
        final matchesUser = userId != null &&
            _players.any((p) => (p['id'] as num?)?.toInt() == userId);
        final firstId = matchesUser
            ? userId
            : (_players.first['id'] as num?)?.toInt();
        if (firstId != null) {
          _selectedPlayerIds.add(firstId);
        }
      }
    } catch (_) {}

    if (!mounted) return;
    setState(() => _loadingRoster = false);

    // جلب بيانات اللاعب المحدد مبدئياً فقط
    for (final pid in List<int>.from(_selectedPlayerIds)) {
      await _fetchSingleAthlete(pid);
    }
  }

  /// تبديل اختيار لاعب: عملية محلية على قائمة الـ IDs فقط عبر setState،
  /// ولا تستعلم من القاعدة عن باقي اللاعبين أبداً، وتعيد استخدام الكاش إن وُجد لنفس المدة.
  void _togglePlayer(int playerId) {
    if (_selectedPlayerIds.contains(playerId)) {
      setState(() {
        _selectedPlayerIds.remove(playerId);
      });
      return;
    }

    setState(() {
      _selectedPlayerIds.add(playerId);
    });

    if (!_athleteCache.containsKey(playerId) &&
        !_loadingPlayerIds.contains(playerId)) {
      _fetchSingleAthlete(playerId);
    }
  }

  Future<void> _onPeriodChanged(ProgressPeriodSelection nextPeriod) async {
    setState(() {
      _period = nextPeriod;
      _athleteCache.clear();
    });

    // إعادة جلب بيانات اللاعبين المختارين حالياً فقط على المدة الجديدة
    for (final pid in List<int>.from(_selectedPlayerIds)) {
      await _fetchSingleAthlete(pid);
    }
  }

  double? _extractDecoupling(Map<String, Object?> row) {
    final direct = (row['decoupling'] as num?)?.toDouble();
    if (direct != null) return direct;

    final notes = row['player_notes'] as String?;
    if (notes == null || notes.isEmpty) return null;

    if (notes.startsWith('{') && notes.endsWith('}')) {
      try {
        final decoded = jsonDecode(notes);
        if (decoded is Map<String, dynamic>) {
          final calc = (decoded['calculated_decoupling'] as num?)?.toDouble() ??
              (decoded['decoupling'] as num?)?.toDouble();
          if (calc != null) return calc;
        }
      } catch (_) {}
    }

    final match = RegExp(r'decoupling:\s*([0-9]+(?:\.[0-9]+)?)').firstMatch(notes);
    if (match != null) {
      return double.tryParse(match.group(1)!);
    }
    return null;
  }

  double? _extractEupnea(Map<String, Object?> row) {
    final direct = (row['eupnea'] as num?)?.toDouble();
    if (direct != null) return direct;

    final notes = row['player_notes'] as String?;
    if (notes == null || notes.isEmpty) return null;

    if (notes.startsWith('{') && notes.endsWith('}')) {
      try {
        final decoded = jsonDecode(notes);
        if (decoded is Map<String, dynamic>) {
          final val = (decoded['eupnea'] as num?)?.toDouble();
          if (val != null) return val;
        }
      } catch (_) {}
    }

    final match = RegExp(r'eupnea:\s*([0-9]+(?:\.[0-9]+)?)').firstMatch(notes);
    if (match != null) {
      return double.tryParse(match.group(1)!);
    }
    return null;
  }

  List<DateValuePoint> _toDailyAvgPoints(Map<String, List<double>> byDate) {
    final sortedKeys = byDate.keys.toList()..sort();
    return sortedKeys.map((k) {
      final vals = byDate[k]!;
      final avg = vals.reduce((a, b) => a + b) / vals.length;
      return DateValuePoint(
        date: DateTime.parse(k),
        value: double.parse(avg.toStringAsFixed(2)),
      );
    }).toList();
  }

  Future<void> _fetchSingleAthlete(int playerId) async {
    if (!mounted) return;
    setState(() => _loadingPlayerIds.add(playerId));

    try {
      final playerMap = _players.firstWhere(
        (p) => (p['id'] as num?)?.toInt() == playerId,
        orElse: () => {'id': playerId, 'name': '#$playerId', 'mhr': 190},
      );
      final name = (playerMap['name'] as String?) ?? '#$playerId';
      final mhr = (playerMap['mhr'] as num?)?.toInt() ?? 190;
      final effectiveRhr = await HeartRateZones.getEffectiveRHR(playerId);

      final startStr = dstr(_period.start);
      final endStr = dstr(_period.end);

      final logRows = await DB.q('''
        SELECT l.*, p.mhr as player_mhr
        FROM logs l
        JOIN players p ON l.player_id = p.id
        WHERE l.player_id = ? AND l.date >= ? AND l.date <= ?
        ORDER BY l.date ASC, l.idx ASC
      ''', [playerId, startStr, endStr]);

      final hrvByDate = <String, List<double>>{};
      final rhrByDate = <String, List<double>>{};
      final sleepByDate = <String, List<double>>{};
      final weightByDate = <String, List<double>>{};
      final eupneaByDate = <String, List<double>>{};
      final efByDate = <String, List<double>>{};
      final decouplingByDate = <String, List<double>>{};
      final overallWattsByDate = <String, List<double>>{};
      final zoneWattsByDate = <String, Map<String, List<double>>>{
        for (final z in HeartRateZones.orderedZones) z: {},
      };
      final matrixPoints = <({double hrrPct, double watts, String date})>[];

      for (final row in logRows) {
        final dateStr = ProgressCalcs.formatDateKey(row['date'] ?? '');
        if (dateStr.isEmpty) continue;

        final rhrVal = (row['rhr'] as num?)?.toDouble();
        final hrvVal = (row['hrv'] as num?)?.toDouble();
        final sleepVal = (row['sleep_hours'] as num?)?.toDouble();
        final weightVal = (row['weight'] as num?)?.toDouble();
        final eupneaVal = _extractEupnea(row);
        final decouplingVal = _extractDecoupling(row);
        final wattsVal = (row['avg_power'] as num?)?.toDouble();
        final hrVal = (row['hr'] as num?)?.toInt();

        double? efVal = (row['ef'] as num?)?.toDouble();
        if ((efVal == null || efVal <= 0) &&
            wattsVal != null &&
            wattsVal > 0 &&
            hrVal != null &&
            hrVal > 0) {
          efVal = PowerCalculations.calculateEF(wattsVal, hrVal);
        }

        if (rhrVal != null && rhrVal > 0) {
          rhrByDate.putIfAbsent(dateStr, () => []).add(rhrVal);
        }
        if (hrvVal != null && hrvVal > 0) {
          hrvByDate.putIfAbsent(dateStr, () => []).add(hrvVal);
        }
        if (sleepVal != null && sleepVal > 0) {
          sleepByDate.putIfAbsent(dateStr, () => []).add(sleepVal);
        }
        if (weightVal != null && weightVal > 0) {
          weightByDate.putIfAbsent(dateStr, () => []).add(weightVal);
        }
        if (eupneaVal != null && eupneaVal > 0) {
          eupneaByDate.putIfAbsent(dateStr, () => []).add(eupneaVal);
        }
        if (efVal != null && efVal > 0) {
          efByDate.putIfAbsent(dateStr, () => []).add(efVal);
        }
        if (decouplingVal != null) {
          decouplingByDate.putIfAbsent(dateStr, () => []).add(decouplingVal);
        }
        if (wattsVal != null && wattsVal > 0) {
          overallWattsByDate.putIfAbsent(dateStr, () => []).add(wattsVal);
        }

        final rowRhr =
            (rhrVal != null && rhrVal > 0) ? rhrVal.round() : effectiveRhr;
        if (hrVal != null && hrVal > 0) {
          final zone = HeartRateZones.determineZone(
            hr: hrVal,
            mhr: mhr,
            rhr: rowRhr,
          );
          if (zone != null &&
              wattsVal != null &&
              wattsVal > 0 &&
              zoneWattsByDate.containsKey(zone)) {
            zoneWattsByDate[zone]!.putIfAbsent(dateStr, () => []).add(wattsVal);
          }

          if (wattsVal != null && wattsVal > 0 && mhr > rowRhr) {
            final hrrPct = ((hrVal - rowRhr) / (mhr - rowRhr)) * 100.0;
            matrixPoints.add((
              hrrPct: double.parse(hrrPct.toStringAsFixed(1)),
              watts: wattsVal,
              date: dateStr,
            ));
          }
        }
      }

      // ساعات الزونات
      final zoneHours = ProgressCalcs.computeZoneHours(
        logRows.map((r) => Map<String, dynamic>.from(r)).toList(),
        defaultMhr: mhr,
        defaultRhr: effectiveRhr,
      );

      // حسابات PMC والكاش
      List<DailyLoadEntry> pmcEntries = const [];
      DailyLoadEntry? todayLoad;
      int missingCpCount = 0;
      List<String> missingCpDates = const [];
      if (widget.curveType == ProgressCurveType.pmcLoad) {
        final syncRes = await ProgressLoadCache.syncForPlayer(playerId);
        pmcEntries = syncRes.allEntries
            .where((e) =>
                e.date.compareTo(startStr) >= 0 && e.date.compareTo(endStr) <= 0)
            .toList();
        final todayKey = dstr(DateTime.now());
        todayLoad = syncRes.allEntries
            .cast<DailyLoadEntry?>()
            .firstWhere((e) => e?.date == todayKey, orElse: () => null);
        todayLoad ??=
            syncRes.allEntries.isNotEmpty ? syncRes.allEntries.last : null;
        missingCpDates = syncRes.missingCpDates
            .where((d) => d.compareTo(startStr) >= 0 && d.compareTo(endStr) <= 0)
            .toList()
          ..sort();
        missingCpCount = missingCpDates.length;
      }

      // اختبارات CP
      List<DateValuePoint> cpValuePoints = const [];
      List<Map<String, Object?>> cpTestRows = const [];
      double? latestCp;
      double? latestWPrime;
      if (widget.curveType == ProgressCurveType.cpTests) {
        try {
          final cpVals = await DB.q('''
            SELECT date, cp, w_prime FROM cp_values
            WHERE player_id = ? AND date >= ? AND date <= ?
            ORDER BY date ASC
          ''', [playerId, startStr, endStr]);
          cpValuePoints = cpVals
              .where((r) => (r['cp'] as num?) != null && r['date'] != null)
              .map((r) => DateValuePoint(
                    date: DateTime.parse(r['date'] as String),
                    value: (r['cp'] as num).toDouble(),
                  ))
              .toList();

          cpTestRows = await DB.q('''
            SELECT * FROM cp_tests
            WHERE player_id = ? AND date >= ? AND date <= ?
            ORDER BY date DESC, id DESC
          ''', [playerId, startStr, endStr]);

          final latestUpToEnd = await DB.q('''
            SELECT cp, w_prime FROM cp_values
            WHERE player_id = ? AND date <= ?
            ORDER BY date DESC LIMIT 1
          ''', [playerId, endStr]);
          if (latestUpToEnd.isNotEmpty) {
            latestCp = (latestUpToEnd.first['cp'] as num?)?.toDouble();
            latestWPrime = (latestUpToEnd.first['w_prime'] as num?)?.toDouble();
          } else {
            latestCp = await ProgressCalcs.getCpForDate(playerId, endStr);
          }
        } catch (_) {}
      }

      final data = _AthleteCurveData(
        playerId: playerId,
        name: name,
        mhr: mhr,
        effectiveRhr: effectiveRhr,
        hrvPoints: _toDailyAvgPoints(hrvByDate),
        rhrPoints: _toDailyAvgPoints(rhrByDate),
        sleepPoints: _toDailyAvgPoints(sleepByDate),
        weightPoints: _toDailyAvgPoints(weightByDate),
        eupneaPoints: _toDailyAvgPoints(eupneaByDate),
        efPoints: _toDailyAvgPoints(efByDate),
        decouplingPoints: _toDailyAvgPoints(decouplingByDate),
        overallWattsPoints: _toDailyAvgPoints(overallWattsByDate),
        zoneWattsPoints: {
          for (final z in HeartRateZones.orderedZones)
            z: _toDailyAvgPoints(zoneWattsByDate[z]!),
        },
        matrixPoints: matrixPoints,
        zoneHours: zoneHours,
        pmcEntries: pmcEntries,
        todayLoad: todayLoad,
        missingCpWorkoutsCount: missingCpCount,
        missingCpDates: missingCpDates,
        cpValuePoints: cpValuePoints,
        cpTestRows: cpTestRows,
        latestCp: latestCp,
        latestWPrime: latestWPrime,
      );

      if (mounted) {
        setState(() {
          _athleteCache[playerId] = data;
        });
      }
    } catch (_) {
      // حماية ضد غياب جدول أو بيانات ناقصة
    } finally {
      if (mounted) {
        setState(() => _loadingPlayerIds.remove(playerId));
      }
    }
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
        title: Text(
          title,
          style: const TextStyle(
            color: EngineRowingUI.textWhite,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
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
            onPressed: () => Navigator.pop(ctx),
            child: Text(AppStrings.of(context).close),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final pageTitle = _titleForType(s);

    return Scaffold(
      backgroundColor: EngineRowingUI.bgNavy,
      appBar: AppBar(
        backgroundColor: EngineRowingUI.bgNavy,
        foregroundColor: EngineRowingUI.textWhite,
        elevation: 0,
        title: Text(
          pageTitle,
          style: const TextStyle(
            color: EngineRowingUI.textWhite,
            fontSize: 17,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: RowingGridBackground(
        maxContentWidth: 920,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. شريط فلتر المدة المشترك فوق منطقة الرسم
            ProgressPeriodFilter(
              selection: _period,
              onChanged: _onPeriodChanged,
            ),

            // 2. قائمة أسماء كل لاعبي الفريق تحت الفلتر مباشرة
            _buildTeamRosterBar(s),

            // 3. شريط اختيار الزون الفرعي لشاشة الواط فقط
            if (widget.curveType == ProgressCurveType.watts)
              _buildWattsZoneSelectorBar(s),

            // 4. منطقة الرسم الرأسية القابلة للتمرير لأي عدد لاعبين
            Expanded(
              child: _loadingRoster
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: EngineRowingUI.neonLime,
                      ),
                    )
                  : _buildCurvesBody(s),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTeamRosterBar(AppStrings s) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: const BoxDecoration(
        color: EngineRowingUI.bgNavy,
        border: Border(
          bottom: BorderSide(color: EngineRowingUI.bgGridLine, width: 1.0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            s.teamAthletesPrompt,
            style: const TextStyle(
              color: EngineRowingUI.captionGrey,
              fontSize: 10.5,
            ),
          ),
          const SizedBox(height: 6),
          if (_players.isEmpty)
            Text(
              s.noActivePlayers,
              style: const TextStyle(
                color: EngineRowingUI.labelSlate,
                fontSize: 12,
              ),
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _players.map((p) {
                  final pid = (p['id'] as num?)?.toInt();
                  if (pid == null) return const SizedBox.shrink();
                  final name = (p['name'] as String?) ?? '#$pid';
                  final isSelected = _selectedPlayerIds.contains(pid);
                  final color = _colorForAthlete(pid);

                  return Padding(
                    padding: const EdgeInsetsDirectional.only(end: 6),
                    child: InkWell(
                      onTap: () => _togglePlayer(pid),
                      borderRadius: BorderRadius.circular(18),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? color.withValues(alpha: 0.22)
                              : EngineRowingUI.equationCardFill,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: isSelected ? color : EngineRowingUI.bgGridLine,
                            width: isSelected ? 1.5 : 1.0,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: color,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              name,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.w500,
                                color: isSelected
                                    ? color
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
            ),
        ],
      ),
    );
  }

  Widget _buildWattsZoneSelectorBar(AppStrings s) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: const BoxDecoration(
        color: EngineRowingUI.equationCardFill,
        border: Border(
          bottom: BorderSide(color: EngineRowingUI.bgGridLine, width: 1.0),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _buildZoneChip(
              label: s.all,
              color: EngineRowingUI.neonLime,
              selected: _selectedWattsZone == null,
              onTap: () => setState(() => _selectedWattsZone = null),
            ),
            for (final z in HeartRateZones.orderedZones)
              _buildZoneChip(
                label: z,
                color: HeartRateZones.zoneColor(z),
                selected: _selectedWattsZone == z,
                onTap: () => setState(() => _selectedWattsZone = z),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildZoneChip({
    required String label,
    required Color color,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(
            color: selected
                ? color.withValues(alpha: 0.25)
                : EngineRowingUI.cardFill,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: selected ? color : EngineRowingUI.bgGridLine,
              width: 1.0,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: selected ? FontWeight.bold : FontWeight.w500,
              color: selected ? color : EngineRowingUI.labelSlate,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCurvesBody(AppStrings s) {
    if (_selectedPlayerIds.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ProgressCurveHeader(
            curveName: _titleForType(s),
            period: _period,
          ),
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  s.selectAtLeastOneAthlete,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: EngineRowingUI.labelSlate,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }

    switch (widget.curveType) {
      case ProgressCurveType.matrixZone:
        return ListView(
          padding: EdgeInsets.zero,
          children: [
            ProgressCurveHeader(
              curveName: s.matrixZoneTitle,
              period: _period,
            ),
            _buildMatrixZoneSharedChart(s),
          ],
        );

      case ProgressCurveType.efAndDecoupling:
        return ListView(
          padding: EdgeInsets.zero,
          children: [
            ProgressCurveHeader(
              curveName: s.efTitle,
              period: _period,
              trailing: IconButton(
                icon: const Icon(Icons.info_outline_rounded,
                    color: EngineRowingUI.neonLime, size: 18),
                onPressed: () => _showInfoDialog(s.efTitle, s.efExplanation),
              ),
            ),
            ..._buildStackedAthleteBlocks(
              builder: (pid, data, color) => _buildAthleteLineBlock(
                s: s,
                athleteName: data?.name ?? _nameForId(pid),
                athleteColor: color,
                points: data?.efPoints ?? const [],
                unit: 'W/bpm',
                enableMA7: false,
                isLoading: data == null && _loadingPlayerIds.contains(pid),
              ),
            ),
            ProgressCurveHeader(
              curveName: s.decouplingTitle,
              period: _period,
              trailing: IconButton(
                icon: const Icon(Icons.info_outline_rounded,
                    color: EngineRowingUI.neonLime, size: 18),
                onPressed: () => _showInfoDialog(
                    s.decouplingTitle, s.decouplingExplanation),
              ),
            ),
            ..._buildStackedAthleteBlocks(
              builder: (pid, data, color) => _buildAthleteLineBlock(
                s: s,
                athleteName: data?.name ?? _nameForId(pid),
                athleteColor: color,
                points: data?.decouplingPoints ?? const [],
                unit: '%',
                enableMA7: true,
                isLoading: data == null && _loadingPlayerIds.contains(pid),
              ),
            ),
          ],
        );

      case ProgressCurveType.watts:
        final wattsHeaderTitle = _selectedWattsZone == null
            ? s.wattsCurveTitle
            : '${s.wattsCurveTitle} - ${HeartRateZones.zoneDisplayName(_selectedWattsZone!, isArabic: s.isArabic)}';
        return ListView(
          padding: EdgeInsets.zero,
          children: [
            ProgressCurveHeader(
              curveName: wattsHeaderTitle,
              period: _period,
              accentColor: _selectedWattsZone != null
                  ? HeartRateZones.zoneColor(_selectedWattsZone!)
                  : EngineRowingUI.neonLime,
            ),
            ..._buildStackedAthleteBlocks(
              builder: (pid, data, color) {
                final pts = data == null
                    ? const <DateValuePoint>[]
                    : (_selectedWattsZone == null
                        ? data.overallWattsPoints
                        : (data.zoneWattsPoints[_selectedWattsZone!] ??
                            const []));
                return _buildAthleteLineBlock(
                  s: s,
                  athleteName: data?.name ?? _nameForId(pid),
                  athleteColor: color,
                  points: pts,
                  unit: 'W',
                  enableMA7: true,
                  isLoading: data == null && _loadingPlayerIds.contains(pid),
                );
              },
            ),
          ],
        );

      case ProgressCurveType.pmcLoad:
        return ListView(
          padding: EdgeInsets.zero,
          children: [
            ProgressCurveHeader(
              curveName: s.pmcTitle,
              period: _period,
              trailing: IconButton(
                icon: const Icon(Icons.info_outline_rounded,
                    color: EngineRowingUI.neonLime, size: 18),
                onPressed: () =>
                    _showInfoDialog(s.pmcTitle, s.pmcExplanation),
              ),
            ),
            ..._buildStackedAthleteBlocks(
              builder: (pid, data, color) => _buildAthletePmcBlock(
                s: s,
                athleteName: data?.name ?? _nameForId(pid),
                athleteColor: color,
                data: data,
                isLoading: data == null && _loadingPlayerIds.contains(pid),
              ),
            ),
          ],
        );

      case ProgressCurveType.recovery:
        return ListView(
          padding: EdgeInsets.zero,
          children: [
            // 1. HRV
            ProgressCurveHeader(
              curveName: s.hrvTitle,
              period: _period,
              trailing: IconButton(
                icon: const Icon(Icons.info_outline_rounded,
                    color: EngineRowingUI.neonLime, size: 18),
                onPressed: () =>
                    _showInfoDialog(s.hrvTitle, s.hrvExplanation),
              ),
            ),
            ..._buildStackedAthleteBlocks(
              builder: (pid, data, color) => _buildAthleteLineBlock(
                s: s,
                athleteName: data?.name ?? _nameForId(pid),
                athleteColor: color,
                points: data?.hrvPoints ?? const [],
                unit: 'ms',
                enableMA7: true,
                isLoading: data == null && _loadingPlayerIds.contains(pid),
              ),
            ),
            // 2. RHR
            ProgressCurveHeader(
              curveName: s.rhrTitle,
              period: _period,
              trailing: IconButton(
                icon: const Icon(Icons.info_outline_rounded,
                    color: EngineRowingUI.neonLime, size: 18),
                onPressed: () =>
                    _showInfoDialog(s.rhrTitle, s.rhrExplanation),
              ),
            ),
            ..._buildStackedAthleteBlocks(
              builder: (pid, data, color) => _buildAthleteLineBlock(
                s: s,
                athleteName: data?.name ?? _nameForId(pid),
                athleteColor: color,
                points: data?.rhrPoints ?? const [],
                unit: 'bpm',
                enableMA7: true,
                isLoading: data == null && _loadingPlayerIds.contains(pid),
              ),
            ),
            // 3. Sleep
            ProgressCurveHeader(
              curveName: s.chipSleep,
              period: _period,
            ),
            ..._buildStackedAthleteBlocks(
              builder: (pid, data, color) => _buildAthleteLineBlock(
                s: s,
                athleteName: data?.name ?? _nameForId(pid),
                athleteColor: color,
                points: data?.sleepPoints ?? const [],
                unit: 'hrs',
                enableMA7: true,
                isLoading: data == null && _loadingPlayerIds.contains(pid),
              ),
            ),
            // 4. Weight
            ProgressCurveHeader(
              curveName: s.chipWeight,
              period: _period,
            ),
            ..._buildStackedAthleteBlocks(
              builder: (pid, data, color) => _buildAthleteLineBlock(
                s: s,
                athleteName: data?.name ?? _nameForId(pid),
                athleteColor: color,
                points: data?.weightPoints ?? const [],
                unit: 'kg',
                enableMA7: true,
                isLoading: data == null && _loadingPlayerIds.contains(pid),
              ),
            ),
            // 5. + Eupnea
            ProgressCurveHeader(
              curveName: s.eupneaTitle,
              period: _period,
              trailing: IconButton(
                icon: const Icon(Icons.info_outline_rounded,
                    color: EngineRowingUI.neonLime, size: 18),
                onPressed: () =>
                    _showInfoDialog(s.eupneaTitle, s.eupneaExplanation),
              ),
            ),
            ..._buildStackedAthleteBlocks(
              builder: (pid, data, color) => _buildAthleteLineBlock(
                s: s,
                athleteName: data?.name ?? _nameForId(pid),
                athleteColor: color,
                points: data?.eupneaPoints ?? const [],
                unit: 'br/min',
                enableMA7: true,
                isLoading: data == null && _loadingPlayerIds.contains(pid),
              ),
            ),
          ],
        );

      case ProgressCurveType.zoneHours:
        return ListView(
          padding: EdgeInsets.zero,
          children: [
            ProgressCurveHeader(
              curveName: s.zoneHoursTitle,
              period: _period,
            ),
            ..._buildStackedAthleteBlocks(
              builder: (pid, data, color) => _buildAthleteZoneHoursBlock(
                s: s,
                athleteName: data?.name ?? _nameForId(pid),
                athleteColor: color,
                data: data,
                isLoading: data == null && _loadingPlayerIds.contains(pid),
              ),
            ),
          ],
        );

      case ProgressCurveType.cpTests:
        return ListView(
          padding: EdgeInsets.zero,
          children: [
            ProgressCurveHeader(
              curveName: s.cpTestsCurveTitle,
              period: _period,
            ),
            ..._buildStackedAthleteBlocks(
              builder: (pid, data, color) => _buildAthleteCpTestsBlock(
                s: s,
                athleteName: data?.name ?? _nameForId(pid),
                athleteColor: color,
                data: data,
                isLoading: data == null && _loadingPlayerIds.contains(pid),
              ),
            ),
          ],
        );
    }
  }

  String _nameForId(int playerId) {
    final found = _players.cast<Map<String, Object?>?>().firstWhere(
          (p) => (p?['id'] as num?)?.toInt() == playerId,
          orElse: () => null,
        );
    return (found?['name'] as String?) ?? '#$playerId';
  }

  List<Widget> _buildStackedAthleteBlocks({
    required Widget Function(
            int playerId, _AthleteCurveData? data, Color athleteColor)
        builder,
  }) {
    return _selectedPlayerIds.map((pid) {
      return builder(pid, _athleteCache[pid], _colorForAthlete(pid));
    }).toList();
  }

  // ════════════════════════════════════════════════════════════════
  // Matrix Zone: عرض خاص مشترك — رسم واحد بمحورين مشتركين لكل اللاعبين المختارين
  // ════════════════════════════════════════════════════════════════
  Widget _buildMatrixZoneSharedChart(AppStrings s) {
    final series = <LineChartBarData>[];
    double minX = 50.0, maxX = 110.0;
    double minY = 50.0, maxY = 400.0;
    bool hasAnyPoints = false;

    final allPts = <({double hrrPct, double watts})>[];
    for (final pid in _selectedPlayerIds) {
      final data = _athleteCache[pid];
      if (data == null || data.matrixPoints.isEmpty) continue;
      hasAnyPoints = true;
      final color = _colorForAthlete(pid);
      final sorted = List.of(data.matrixPoints)
        ..sort((a, b) => a.hrrPct.compareTo(b.hrrPct));
      allPts.addAll(sorted.map((e) => (hrrPct: e.hrrPct, watts: e.watts)));

      series.add(
        LineChartBarData(
          spots: sorted.map((p) => FlSpot(p.hrrPct, p.watts)).toList(),
          isCurved: false,
          color: color,
          barWidth: 2.2,
          dotData: FlDotData(
            show: true,
            getDotPainter: (spot, percent, bar, idx) => FlDotCirclePainter(
              radius: 4.0,
              color: color,
              strokeColor: Colors.white,
              strokeWidth: 1.0,
            ),
          ),
        ),
      );
    }

    if (hasAnyPoints) {
      minX = (allPts.map((e) => e.hrrPct).reduce(min) - 5).clamp(0.0, 100.0);
      maxX = max(allPts.map((e) => e.hrrPct).reduce(max) + 5, minX + 10);
      minY = max(0.0, allPts.map((e) => e.watts).reduce(min) - 20);
      maxY = max(allPts.map((e) => e.watts).reduce(max) + 20, minY + 30);
    }

    return Container(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.all(12),
      decoration: const BoxDecoration(
        color: EngineRowingUI.cardFill,
        border: Border(
          bottom: BorderSide(color: EngineRowingUI.bgGridLine, width: 1.0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 6,
            children: _selectedPlayerIds.map((pid) {
              final color = _colorForAthlete(pid);
              final name = _athleteCache[pid]?.name ?? _nameForId(pid);
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration:
                        BoxDecoration(color: color, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    name,
                    style: TextStyle(
                      color: color,
                      fontSize: 11.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
          const SizedBox(height: 8),
          if (!hasAnyPoints)
            Container(
              height: 180,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: EngineRowingUI.equationCardFill,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: EngineRowingUI.bgGridLine),
              ),
              child: Text(
                s.notEnoughData,
                style: const TextStyle(
                  color: EngineRowingUI.captionGrey,
                  fontSize: 13,
                ),
              ),
            )
          else
            SizedBox(
              height: 230,
              child: Directionality(
                textDirection: TextDirection.ltr,
                child: LineChart(
                  LineChartData(
                    minX: minX,
                    maxX: maxX,
                    minY: minY,
                    maxY: maxY,
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
                      leftTitles: AxisTitles(
                        axisNameWidget: Text(
                          s.chipWatts,
                          style: const TextStyle(
                            color: EngineRowingUI.labelSlate,
                            fontSize: 10,
                          ),
                        ),
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 38,
                          getTitlesWidget: (v, _) => Text(
                            v.toInt().toString(),
                            style: const TextStyle(
                              color: EngineRowingUI.captionGrey,
                              fontSize: 10,
                            ),
                          ),
                        ),
                      ),
                      bottomTitles: AxisTitles(
                        axisNameWidget: const Text(
                          '% HRR',
                          style: TextStyle(
                            color: EngineRowingUI.labelSlate,
                            fontSize: 10,
                          ),
                        ),
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 22,
                          getTitlesWidget: (v, _) => Text(
                            '${v.toInt()}%',
                            style: const TextStyle(
                              color: EngineRowingUI.captionGrey,
                              fontSize: 10,
                            ),
                          ),
                        ),
                      ),
                      rightTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false)),
                      topTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false)),
                    ),
                    borderData: FlBorderData(
                      show: true,
                      border: Border.all(color: EngineRowingUI.bgGridLine),
                    ),
                    lineBarsData: series,
                  ),
                ),
              ),
            ),
          const SizedBox(height: 8),
          Text(
            s.matrixZoneComparisonNote,
            style: const TextStyle(
              color: EngineRowingUI.captionGrey,
              fontSize: 10.5,
            ),
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════
  // ويدجت منحنى لاعب مفرد ملزوق مباشرة بدون فراغ خارجي (margin & padding = 0)
  // ════════════════════════════════════════════════════════════════
  Widget _buildAthleteLineBlock({
    required AppStrings s,
    required String athleteName,
    required Color athleteColor,
    required List<DateValuePoint> points,
    required String unit,
    required bool enableMA7,
    required bool isLoading,
  }) {
    final maPoints = enableMA7
        ? ProgressCalcs.movingAverage7(points)
        : const <DateValuePoint>[];

    double? minY;
    double? maxY;
    final nonNullVals = points
        .where((p) => p.value != null)
        .map((p) => p.value!)
        .toList();
    if (nonNullVals.isNotEmpty) {
      final low = nonNullVals.reduce(min);
      final high = nonNullVals.reduce(max);
      if ((high - low).abs() < 1e-6) {
        minY = low - max(1.0, low.abs() * 0.1);
        maxY = high + max(1.0, high.abs() * 0.1);
      }
    }

    return Container(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
      decoration: BoxDecoration(
        color: EngineRowingUI.cardFill,
        border: Border(
          left: BorderSide(color: athleteColor, width: 3.0),
          bottom: const BorderSide(color: EngineRowingUI.bgGridLine, width: 1.0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // اسم اللاعب الصغير فوق المنحنى مباشرة بنفس لون المنحنى
          Row(
            children: [
              Text(
                athleteName,
                style: TextStyle(
                  color: athleteColor,
                  fontSize: 11.5,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              if (points.isNotEmpty && points.last.value != null)
                Directionality(
                  textDirection: TextDirection.ltr,
                  child: Text(
                    RowingNumberFormatter.toEnglishDigits(
                        '${points.last.value!.toStringAsFixed(1)} $unit'),
                    style: TextStyle(
                      color: athleteColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          if (isLoading)
            const SizedBox(
              height: 90,
              child: Center(
                child: CircularProgressIndicator(
                  color: EngineRowingUI.neonLime,
                  strokeWidth: 2.0,
                ),
              ),
            )
          else if (points.isEmpty)
            SizedBox(
              height: 64,
              child: Center(
                child: Text(
                  s.notEnoughData,
                  style: const TextStyle(
                    color: EngineRowingUI.captionGrey,
                    fontSize: 12,
                  ),
                ),
              ),
            )
          else
            SizedBox(
              height: 145,
              child: Directionality(
                textDirection: TextDirection.ltr,
                child: LineChart(
                  LineChartData(
                    minX: points.length == 1 ? -0.5 : 0.0,
                    maxX: points.length == 1
                        ? 0.5
                        : (points.length - 1).toDouble(),
                    minY: minY,
                    maxY: maxY,
                    gridData: FlGridData(
                      show: true,
                      drawVerticalLine: false,
                      getDrawingHorizontalLine: (_) => const FlLine(
                        color: EngineRowingUI.bgGridLine,
                        strokeWidth: 0.8,
                      ),
                    ),
                    titlesData: FlTitlesData(
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 34,
                          getTitlesWidget: (val, _) => Text(
                            val.toStringAsFixed(val.abs() < 10 ? 1 : 0),
                            style: const TextStyle(
                              color: EngineRowingUI.captionGrey,
                              fontSize: 9.5,
                            ),
                          ),
                        ),
                      ),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 20,
                          getTitlesWidget: (val, _) {
                            final idx = val.round();
                            if (val == idx.toDouble() &&
                                idx >= 0 &&
                                idx < points.length &&
                                idx % max(1, (points.length ~/ 4)) == 0) {
                              final d = points[idx].date;
                              return Text(
                                '${d.day}/${d.month}',
                                style: const TextStyle(
                                  color: EngineRowingUI.captionGrey,
                                  fontSize: 9.5,
                                ),
                              );
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
                      LineChartBarData(
                        spots: List.generate(
                          points.length,
                          (i) => FlSpot(i.toDouble(), points[i].value ?? 0.0),
                        ),
                        isCurved: false,
                        color: athleteColor,
                        barWidth: 2.2,
                        dotData: FlDotData(
                          show: true,
                          getDotPainter: (spot, percent, bar, index) =>
                              FlDotCirclePainter(
                            radius: points.length == 1 ? 4.2 : 2.6,
                            color: athleteColor,
                            strokeColor: Colors.white,
                            strokeWidth: 0.9,
                          ),
                        ),
                      ),
                      if (maPoints.any((p) => p.value != null))
                        LineChartBarData(
                          spots: [
                            for (int i = 0; i < maPoints.length; i++)
                              if (maPoints[i].value != null)
                                FlSpot(i.toDouble(), maPoints[i].value!),
                          ],
                          isCurved: true,
                          color: athleteColor.withValues(alpha: 0.6),
                          barWidth: 1.5,
                          dashArray: [5, 4],
                          dotData: const FlDotData(show: false),
                        ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════
  // شاشة ساعات الزونات: جدول الـ 7 زونات + "بدون زون"
  // ════════════════════════════════════════════════════════════════
  String _zoneTableTitle(AppStrings s, String zoneKey) {
    switch (zoneKey) {
      case 'Z1':
        return 'Zone 1 - UT3';
      case 'Z2':
        return 'Zone 2 - UT2';
      case 'Z3':
        return 'Zone 3 - UT1';
      case 'Z4':
        return 'Zone 4 - AT';
      case 'Threshold':
        return 'Threshold - AT';
      case 'Z5':
        return 'Zone 5 - TR';
      case 'VO2 max':
        return 'VO2 max - AN';
      default:
        return s.noZoneName;
    }
  }

  String _zoneTableDesc(AppStrings s, String zoneKey) {
    if (zoneKey == 'NO_ZONE') return s.noZoneDesc;
    final pct = HeartRateZones.zonePercentages[zoneKey];
    final pctLabel = pct != null
        ? '${(pct[0] * 100).round()}%–${(pct[1] * 100).round()}%'
        : '';
    if (s.isArabic) {
      switch (zoneKey) {
        case 'Z1':
          return 'استشفاء / هوائي خفيف ($pctLabel)';
        case 'Z2':
          return 'تحمل هوائي أساسي ($pctLabel)';
        case 'Z3':
          return 'تحمل هوائي مكثف ($pctLabel)';
        case 'Z4':
          return 'قرب العتبة ($pctLabel)';
        case 'Threshold':
          return 'العتبة اللاهوائية ($pctLabel)';
        case 'Z5':
          return 'تطوير اللاهوائي ($pctLabel)';
        case 'VO2 max':
          return 'أقصى استهلاك أكسجين ($pctLabel)';
        default:
          return s.noZoneDesc;
      }
    } else {
      switch (zoneKey) {
        case 'Z1':
          return 'Light Recovery ($pctLabel)';
        case 'Z2':
          return 'Base Aerobic ($pctLabel)';
        case 'Z3':
          return 'Intensive Aerobic ($pctLabel)';
        case 'Z4':
          return 'Sub-Threshold ($pctLabel)';
        case 'Threshold':
          return 'Anaerobic Threshold ($pctLabel)';
        case 'Z5':
          return 'TR Power ($pctLabel)';
        case 'VO2 max':
          return 'Max Oxygen Uptake ($pctLabel)';
        default:
          return s.noZoneDesc;
      }
    }
  }

  Widget _buildAthleteZoneHoursBlock({
    required AppStrings s,
    required String athleteName,
    required Color athleteColor,
    required _AthleteCurveData? data,
    required bool isLoading,
  }) {
    final rows = data?.zoneHours ?? const <ZoneHoursEntry>[];

    return Container(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: EngineRowingUI.cardFill,
        border: Border(
          left: BorderSide(color: athleteColor, width: 3.0),
          bottom: const BorderSide(color: EngineRowingUI.bgGridLine, width: 1.0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            athleteName,
            style: TextStyle(
              color: athleteColor,
              fontSize: 11.5,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          if (isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: CircularProgressIndicator(
                  color: EngineRowingUI.neonLime,
                  strokeWidth: 2.0,
                ),
              ),
            )
          else
            Container(
              decoration: BoxDecoration(
                color: EngineRowingUI.equationCardFill,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: EngineRowingUI.bgGridLine),
              ),
              child: Column(
                children: [
                  // رأس الجدول
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                    decoration: const BoxDecoration(
                      color: EngineRowingUI.bgNavy,
                      borderRadius:
                          BorderRadius.vertical(top: Radius.circular(7)),
                      border: Border(
                        bottom: BorderSide(
                            color: EngineRowingUI.bgGridLine, width: 1.0),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: Text(
                            s.zoneColHeader,
                            style: const TextStyle(
                              color: EngineRowingUI.neonLime,
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 4,
                          child: Text(
                            s.zoneDescColHeader,
                            style: const TextStyle(
                              color: EngineRowingUI.neonLime,
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            s.totalHoursColHeader,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: EngineRowingUI.neonLime,
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            s.percentageColHeader,
                            textAlign: TextAlign.end,
                            style: const TextStyle(
                              color: EngineRowingUI.neonLime,
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  for (final entry in rows)
                    _buildZoneHoursRow(s, entry),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildZoneHoursRow(AppStrings s, ZoneHoursEntry entry) {
    final isNoZone = entry.zoneKey == 'NO_ZONE';
    final zColor = isNoZone
        ? EngineRowingUI.captionGrey
        : HeartRateZones.zoneColor(entry.zoneKey);
    final hoursStr =
        RowingNumberFormatter.toEnglishDigits(entry.hours.toStringAsFixed(2));
    final pctStr = RowingNumberFormatter.toEnglishDigits(
        '${entry.percentage.toStringAsFixed(1)}%');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: EngineRowingUI.bgGridLine, width: 0.7),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration:
                      BoxDecoration(color: zColor, shape: BoxShape.circle),
                ),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    _zoneTableTitle(s, entry.zoneKey),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isNoZone
                          ? EngineRowingUI.labelSlate
                          : EngineRowingUI.textWhite,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 4,
            child: Text(
              _zoneTableDesc(s, entry.zoneKey),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: EngineRowingUI.labelSlate,
                fontSize: 10,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: Text(
                hoursStr,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: EngineRowingUI.textWhite,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: Text(
                pctStr,
                textAlign: TextAlign.end,
                style: TextStyle(
                  color: zColor,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════
  // شاشة PMC (الحمل): كروت اليوم + خطوط CTL/ATL + أعمدة TSB الملونة بالثيم
  // ════════════════════════════════════════════════════════════════
  (String label, Color color) _tsbVisualFromTheme(
      BuildContext context, AppStrings s, double tsb) {
    final colorScheme = Theme.of(context).colorScheme;
    final status = ProgressCalcs.classifyTsb(tsb);
    switch (status) {
      case TsbStatus.excessRest:
        return (s.tsbExcessRest, EngineRowingUI.zone2Color);
      case TsbStatus.raceReady:
        return (s.tsbRaceReady, colorScheme.primary);
      case TsbStatus.neutral:
        return (s.tsbNeutral, EngineRowingUI.labelSlate);
      case TsbStatus.productiveBuild:
        return (s.tsbProductiveBuild, EngineRowingUI.zone3Color);
      case TsbStatus.overreachRisk:
        return (s.tsbOverreachRisk, colorScheme.error);
    }
  }

  Widget _buildAthletePmcBlock({
    required AppStrings s,
    required String athleteName,
    required Color athleteColor,
    required _AthleteCurveData? data,
    required bool isLoading,
  }) {
    final entries = data?.pmcEntries ?? const <DailyLoadEntry>[];
    final today = data?.todayLoad;
    final ctlToday = today?.ctl ?? 0.0;
    final atlToday = today?.atl ?? 0.0;
    final tsbToday = today?.tsb ?? 0.0;
    final (tsbLabel, tsbColor) = _tsbVisualFromTheme(context, s, tsbToday);

    return Container(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: EngineRowingUI.cardFill,
        border: Border(
          left: BorderSide(color: athleteColor, width: 3.0),
          bottom: const BorderSide(color: EngineRowingUI.bgGridLine, width: 1.0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // اسم اللاعب فوق الرسم بنفس لونه
          Row(
            children: [
              Text(
                athleteName,
                style: TextStyle(
                  color: athleteColor,
                  fontSize: 11.5,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: tsbColor.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: tsbColor.withValues(alpha: 0.7)),
                ),
                child: Text(
                  tsbLabel,
                  style: TextStyle(
                    color: tsbColor,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),

          // كروت CTL و ATL و TSB النهارده فوق الرسم
          Row(
            children: [
              Expanded(
                child: _buildPmcTodayCard(
                  label: '${s.ctlLineLabel} (${s.todayLabel})',
                  value: ctlToday.toStringAsFixed(1),
                  color: EngineRowingUI.zone2Color,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _buildPmcTodayCard(
                  label: '${s.atlLineLabel} (${s.todayLabel})',
                  value: atlToday.toStringAsFixed(1),
                  color: EngineRowingUI.zone3Color,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _buildPmcTodayCard(
                  label: '${s.tsbBarLabel} (${s.todayLabel})',
                  value: tsbToday.toStringAsFixed(1),
                  color: tsbColor,
                ),
              ),
            ],
          ),

          if ((data?.missingCpWorkoutsCount ?? 0) > 0) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: EngineRowingUI.equationCardFill,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                    color: Theme.of(context).colorScheme.error.withValues(alpha: 0.5)),
              ),
              child: Text(
                '${s.missingCpNotice} (${data!.missingCpDates.join(', ')})',
                style: const TextStyle(
                  color: EngineRowingUI.labelSlate,
                  fontSize: 10.5,
                ),
              ),
            ),
          ],

          const SizedBox(height: 8),

          if (isLoading)
            const SizedBox(
              height: 120,
              child: Center(
                child: CircularProgressIndicator(
                  color: EngineRowingUI.neonLime,
                  strokeWidth: 2.0,
                ),
              ),
            )
          else if (entries.isEmpty)
            SizedBox(
              height: 80,
              child: Center(
                child: Text(
                  s.notEnoughData,
                  style: const TextStyle(
                    color: EngineRowingUI.captionGrey,
                    fontSize: 12,
                  ),
                ),
              ),
            )
          else ...[
            // خطوط CTL و ATL
            Builder(
              builder: (context) {
                final allLoadVals = [
                  for (final e in entries) ...[e.ctl, e.atl],
                ];
                final rawMin = allLoadVals.reduce(min);
                final rawMax = allLoadVals.reduce(max);
                final loadMinY = max(0.0, rawMin - 5).floorToDouble();
                final loadMaxY = (rawMax == rawMin ? rawMax + 10 : rawMax + 5)
                    .ceilToDouble();

                final tsbVals = entries.map((e) => e.tsb).toList();
                final rawTsbMin = min(0.0, tsbVals.reduce(min));
                final rawTsbMax = max(0.0, tsbVals.reduce(max));
                final tsbMinY = (rawTsbMin - 5).floorToDouble();
                final tsbMaxY = (rawTsbMax + 5).ceilToDouble();

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      height: 150,
                      child: Directionality(
                        textDirection: TextDirection.ltr,
                        child: LineChart(
                          LineChartData(
                            minX: entries.length == 1 ? -0.5 : 0.0,
                            maxX: entries.length == 1
                                ? 0.5
                                : (entries.length - 1).toDouble(),
                            minY: loadMinY,
                            maxY: loadMaxY,
                            gridData: FlGridData(
                              show: true,
                              drawVerticalLine: false,
                              getDrawingHorizontalLine: (_) => const FlLine(
                                color: EngineRowingUI.bgGridLine,
                                strokeWidth: 0.8,
                              ),
                            ),
                            titlesData: FlTitlesData(
                              leftTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  reservedSize: 34,
                                  getTitlesWidget: (v, _) => Text(
                                    v.toInt().toString(),
                                    style: const TextStyle(
                                      color: EngineRowingUI.captionGrey,
                                      fontSize: 9.5,
                                    ),
                                  ),
                                ),
                              ),
                              bottomTitles: const AxisTitles(
                                  sideTitles: SideTitles(showTitles: false)),
                              rightTitles: const AxisTitles(
                                  sideTitles: SideTitles(showTitles: false)),
                              topTitles: const AxisTitles(
                                  sideTitles: SideTitles(showTitles: false)),
                            ),
                            borderData: FlBorderData(show: false),
                            lineBarsData: [
                              LineChartBarData(
                                spots: List.generate(
                                  entries.length,
                                  (i) => FlSpot(i.toDouble(), entries[i].ctl),
                                ),
                                isCurved: true,
                                color: EngineRowingUI.zone2Color,
                                barWidth: 2.2,
                                dotData: const FlDotData(show: false),
                              ),
                              LineChartBarData(
                                spots: List.generate(
                                  entries.length,
                                  (i) => FlSpot(i.toDouble(), entries[i].atl),
                                ),
                                isCurved: true,
                                color: EngineRowingUI.zone3Color,
                                barWidth: 2.0,
                                dotData: const FlDotData(show: false),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    // أعمدة TSB الملونة حسب الحالة تحت خطوط CTL/ATL
                    SizedBox(
                      height: 95,
                      child: Directionality(
                        textDirection: TextDirection.ltr,
                        child: BarChart(
                          BarChartData(
                            minY: tsbMinY,
                            maxY: tsbMaxY,
                            alignment: BarChartAlignment.spaceBetween,
                            gridData: FlGridData(
                              show: true,
                              drawVerticalLine: false,
                              getDrawingHorizontalLine: (v) => FlLine(
                                color: v.abs() < 0.01
                                    ? EngineRowingUI.labelSlate
                                        .withValues(alpha: 0.6)
                                    : EngineRowingUI.bgGridLine,
                                strokeWidth: v.abs() < 0.01 ? 1.2 : 0.6,
                              ),
                            ),
                            titlesData: FlTitlesData(
                              leftTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  reservedSize: 34,
                                  getTitlesWidget: (v, _) => Text(
                                    v.toInt().toString(),
                                    style: const TextStyle(
                                      color: EngineRowingUI.captionGrey,
                                      fontSize: 9.5,
                                    ),
                                  ),
                                ),
                              ),
                              bottomTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  reservedSize: 20,
                                  getTitlesWidget: (val, _) {
                                    final idx = val.round();
                                    if (idx >= 0 &&
                                        idx < entries.length &&
                                        idx % max(1, (entries.length ~/ 4)) ==
                                            0) {
                                      final d =
                                          DateTime.tryParse(entries[idx].date);
                                      if (d != null) {
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
                            barGroups: List.generate(entries.length, (i) {
                              final tsbVal = entries[i].tsb;
                              final (_, barColor) =
                                  _tsbVisualFromTheme(context, s, tsbVal);
                              return BarChartGroupData(
                                x: i,
                                barRods: [
                                  BarChartRodData(
                                    fromY: 0,
                                    toY: tsbVal,
                                    width: entries.length > 20 ? 5 : 10,
                                    color: barColor,
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ],
                              );
                            }),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPmcTodayCard({
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: EngineRowingUI.equationCardFill,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: EngineRowingUI.captionGrey,
              fontSize: 9.5,
            ),
          ),
          const SizedBox(height: 3),
          Directionality(
            textDirection: TextDirection.ltr,
            child: Text(
              RowingNumberFormatter.toEnglishDigits(value),
              style: TextStyle(
                color: color,
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════
  // شاشة اختبارات CP
  // ════════════════════════════════════════════════════════════════
  Widget _buildAthleteCpTestsBlock({
    required AppStrings s,
    required String athleteName,
    required Color athleteColor,
    required _AthleteCurveData? data,
    required bool isLoading,
  }) {
    final pts = data?.cpValuePoints ?? const <DateValuePoint>[];
    final tests = data?.cpTestRows ?? const <Map<String, Object?>>[];

    return Container(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: EngineRowingUI.cardFill,
        border: Border(
          left: BorderSide(color: athleteColor, width: 3.0),
          bottom: const BorderSide(color: EngineRowingUI.bgGridLine, width: 1.0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text(
                athleteName,
                style: TextStyle(
                  color: athleteColor,
                  fontSize: 11.5,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              Directionality(
                textDirection: TextDirection.ltr,
                child: Text(
                  RowingNumberFormatter.toEnglishDigits(
                    data?.latestCp != null
                        ? 'CP: ${data!.latestCp!.toStringAsFixed(0)} W'
                        : 'CP: --',
                  ),
                  style: TextStyle(
                    color: athleteColor,
                    fontSize: 11.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (pts.isNotEmpty)
            Builder(
              builder: (context) {
                final cpVals = pts.map((p) => p.value ?? 0.0).toList();
                final low = cpVals.reduce(min);
                final high = cpVals.reduce(max);
                final minY = (high - low).abs() < 1e-6
                    ? max(0.0, low - 15).floorToDouble()
                    : null;
                final maxY = (high - low).abs() < 1e-6
                    ? (high + 15).ceilToDouble()
                    : null;

                return SizedBox(
                  height: 130,
                  child: Directionality(
                    textDirection: TextDirection.ltr,
                    child: LineChart(
                      LineChartData(
                        minX: pts.length == 1 ? -0.5 : 0.0,
                        maxX:
                            pts.length == 1 ? 0.5 : (pts.length - 1).toDouble(),
                        minY: minY,
                        maxY: maxY,
                        gridData: FlGridData(
                          show: true,
                          drawVerticalLine: false,
                          getDrawingHorizontalLine: (_) => const FlLine(
                            color: EngineRowingUI.bgGridLine,
                            strokeWidth: 0.8,
                          ),
                        ),
                        titlesData: FlTitlesData(
                          leftTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 34,
                              getTitlesWidget: (v, _) => Text(
                                v.toInt().toString(),
                                style: const TextStyle(
                                  color: EngineRowingUI.captionGrey,
                                  fontSize: 9.5,
                                ),
                              ),
                            ),
                          ),
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 20,
                              getTitlesWidget: (v, _) {
                                final idx = v.round();
                                if (v == idx.toDouble() &&
                                    idx >= 0 &&
                                    idx < pts.length) {
                                  final d = pts[idx].date;
                                  return Text(
                                    '${d.day}/${d.month}',
                                    style: const TextStyle(
                                      color: EngineRowingUI.captionGrey,
                                      fontSize: 9.5,
                                    ),
                                  );
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
                          LineChartBarData(
                            spots: List.generate(
                              pts.length,
                              (i) => FlSpot(i.toDouble(), pts[i].value ?? 0.0),
                            ),
                            isCurved: false,
                            color: athleteColor,
                            barWidth: 2.2,
                            dotData: FlDotData(
                              show: true,
                              getDotPainter: (_, __, ___, ____) =>
                                  FlDotCirclePainter(
                                radius: 3.5,
                                color: athleteColor,
                                strokeColor: Colors.white,
                                strokeWidth: 1.0,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          if (isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: CircularProgressIndicator(
                  color: EngineRowingUI.neonLime,
                  strokeWidth: 2.0,
                ),
              ),
            )
          else if (tests.isEmpty && pts.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: Text(
                  s.notEnoughData,
                  style: const TextStyle(
                    color: EngineRowingUI.captionGrey,
                    fontSize: 12,
                  ),
                ),
              ),
            )
          else if (tests.isNotEmpty) ...[
            const SizedBox(height: 6),
            for (final t in tests)
              Container(
                margin: const EdgeInsets.only(bottom: 4),
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: EngineRowingUI.equationCardFill,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: EngineRowingUI.bgGridLine),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${t['date']} • ${t['test_type'] ?? ''}',
                        style: const TextStyle(
                          color: EngineRowingUI.textWhite,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Directionality(
                      textDirection: TextDirection.ltr,
                      child: Text(
                        RowingNumberFormatter.toEnglishDigits(
                          '${((t['avg_power'] as num?)?.toDouble() ?? 0).toStringAsFixed(0)} W (${formatDuration((t['duration_seconds'] as num?)?.toInt() ?? 0)})',
                        ),
                        style: TextStyle(
                          color: athleteColor,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}
