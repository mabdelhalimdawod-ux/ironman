import 'dart:convert';
import 'dart:math';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'app_strings.dart';
import 'auth_service.dart';
import 'curve_privacy_service.dart';
import 'db.dart';
import 'engine_rowing_ui.dart';
import 'heart_rate_zones.dart';
import 'power_calculations.dart';
import 'program_service.dart';
import 'progress_calcs.dart';
import 'progress_curve_header.dart';
import 'progress_panel.dart';
import 'progress_period_filter.dart';
import 'ef_zone_curve.dart';
import 'decoupling_trend_curve.dart';
import 'dynamic_watts_curve.dart';
import 'recovery_curves.dart';
import 'eupnea_curve.dart';
import 'cp_bars_curve.dart';

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

  // نتيجة Matrix Zone ومنحنى القدرة وسجلات التمارين الخام
  final MatrixZoneAthleteResult? matrixZoneResult;
  final List<Map<String, Object?>> rawLogs;

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
    this.matrixZoneResult,
    this.rawLogs = const [],
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
  String _selectedMatrixKind = 'Erg';
  String _selectedZoneHoursKind = 'ALL';
  List<MatrixZoneIndicatorConfig> _matrixConfigs =
      ProgressCalcs.defaultMatrixIndicators;

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
      _matrixConfigs = await ProgressCalcs.loadMatrixZoneConfig();
      final players = await DB.players();
      _players = players;

      // تعيين لون ثابت لكل لاعب بناءً على ترتيبه بالـ id لضمان عدم تغيّر اللون أبداً
      final byId = List<Map<String, Object?>>.from(players)
        ..sort((a, b) => ((a['id'] as num?)?.toInt() ?? 0)
            .compareTo((b['id'] as num?)?.toInt() ?? 0));
      _athleteColors.clear();
      for (int i = 0; i < byId.length; i++) {
        final pid = (byId[i]['id'] as num?)?.toInt();
        if (pid != null) {
          _athleteColors[pid] = _athletePalette[i % _athletePalette.length];
        }
      }

      final isAthlete = widget.user?.isAthlete == true;
      final athletePlayerId = widget.user?.playerId ?? widget.user?.id;
      if (isAthlete && athletePlayerId != null) {
        // تبويب Progress مقفول على حساب اللاعب نفسه فقط
        _players = _players
            .where((p) => (p['id'] as num?)?.toInt() == athletePlayerId)
            .toList();
        if (_players.isEmpty) {
          _players = [
            {'id': athletePlayerId, 'name': widget.user!.name, 'mhr': 190}
          ];
        }
        _selectedPlayerIds.clear();
        _selectedPlayerIds.add(athletePlayerId);
      } else if (_selectedPlayerIds.isEmpty && _players.isNotEmpty) {
        final userId = widget.user?.id;
        final matchesUser = userId != null &&
            _players.any((p) => (p['id'] as num?)?.toInt() == userId);
        final firstId =
            matchesUser ? userId : (_players.first['id'] as num?)?.toInt();
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
      if (widget.user?.isAthlete == true && _selectedPlayerIds.length <= 1) {
        return; // الإبقاء على لاعب واحد على الأقل للمقارنة
      }
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

    final match =
        RegExp(r'decoupling:\s*([0-9]+(?:\.[0-9]+)?)').firstMatch(notes);
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
      if (widget.user != null) {
        final allowed = await CurvePrivacyService.canViewCurves(
          viewer: widget.user!,
          ownerPlayerId: playerId,
        );
        if (!allowed) {
          if (mounted) setState(() => _loadingPlayerIds.remove(playerId));
          return;
        }
      }

      final playerMap = _players.firstWhere(
        (p) => (p['id'] as num?)?.toInt() == playerId,
        orElse: () => {'id': playerId, 'name': '#$playerId', 'mhr': 190},
      );
      final name = (playerMap['name'] as String?) ?? '#$playerId';
      final mhr = (playerMap['mhr'] as num?)?.toInt() ?? 190;
      final effectiveRhr = await HeartRateZones.getEffectiveRHR(playerId);

      final startStr = dstr(_period.start);
      final endStr = dstr(_period.end);

      final isTeammate = widget.user?.isAthlete == true &&
          (widget.user?.playerId ?? widget.user?.id) != playerId;

      final List<Map<String, Object?>> allAthleteLogs;
      if (isTeammate) {
        allAthleteLogs = await DB.q('''
          SELECT c.*, p.mhr as player_mhr, '' as session_zone, '' as session_kind
          FROM shared_curve_cache c
          LEFT JOIN players p ON c.player_id = p.id
          WHERE c.player_id = ?
          ORDER BY c.date ASC, c.idx ASC
        ''', [playerId]);
      } else {
        allAthleteLogs = await DB.q('''
          SELECT l.*, p.mhr as player_mhr, s.zone as session_zone, s.kind as session_kind
          FROM logs l
          JOIN players p ON l.player_id = p.id
          LEFT JOIN sessions s ON l.date = s.date AND l.idx = s.idx
          WHERE l.player_id = ?
          ORDER BY l.date ASC, l.idx ASC
        ''', [playerId]);
      }

      final logRows = allAthleteLogs.where((l) {
        final dStr = (l['date'] as String?) ?? '';
        return dStr.compareTo(startStr) >= 0 && dStr.compareTo(endStr) <= 0;
      }).toList();

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
        final explicitZone = (row['zone'] as String?)?.trim();
        final zone = (explicitZone != null && explicitZone.isNotEmpty)
            ? explicitZone
            : (hrVal != null && hrVal > 0)
                ? HeartRateZones.determineZone(
                    hr: hrVal,
                    mhr: mhr,
                    rhr: rowRhr,
                  )
                : (row['session_zone'] as String?)?.trim();

        if (zone != null &&
            wattsVal != null &&
            wattsVal > 0 &&
            zoneWattsByDate.containsKey(zone)) {
          zoneWattsByDate[zone]!.putIfAbsent(dateStr, () => []).add(wattsVal);
        }

        if (hrVal != null && hrVal > 0) {
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

      // ساعات الزونات مع فلتر نوع التمرين (نوع محدد أو الكل)
      final zoneHoursLogs = logRows.where((l) {
        if (_selectedZoneHoursKind == 'ALL') return true;
        final k =
            (l['kind'] as String?) ?? (l['session_kind'] as String?) ?? '';
        return k.toLowerCase() == _selectedZoneHoursKind.toLowerCase();
      }).toList();
      final zoneHours = ProgressCalcs.computeZoneHours(
        zoneHoursLogs.map((r) => Map<String, dynamic>.from(r)).toList(),
        defaultMhr: mhr,
        defaultRhr: effectiveRhr,
      );

      // حسابات PMC والكاش مع فترة إحماء 42 يوماً على الأقل قبل الفترة المعروضة
      List<DailyLoadEntry> pmcEntries = const [];
      DailyLoadEntry? todayLoad;
      int missingCpCount = 0;
      List<String> missingCpDates = const [];
      if (widget.curveType == ProgressCurveType.pmcLoad) {
        final warmupDate = _period.start.subtract(const Duration(days: 42));
        final syncRes = await ProgressLoadCache.syncForPlayer(
          playerId,
          forceFromDate: dstr(warmupDate),
        );
        pmcEntries = syncRes.allEntries
            .where((e) =>
                e.date.compareTo(startStr) >= 0 &&
                e.date.compareTo(endStr) <= 0)
            .toList();
        final todayKey = dstr(DateTime.now());
        todayLoad = syncRes.allEntries
            .cast<DailyLoadEntry?>()
            .firstWhere((e) => e?.date == todayKey, orElse: () => null);
        todayLoad ??=
            syncRes.allEntries.isNotEmpty ? syncRes.allEntries.last : null;
        missingCpDates = syncRes.missingCpDates
            .where(
                (d) => d.compareTo(startStr) >= 0 && d.compareTo(endStr) <= 0)
            .toList()
          ..sort();
        missingCpCount = missingCpDates.length;
      }

      // حساب مقاييس Matrix Zone ومنحنى القدرة
      final matrixResult = ProgressCalcs.computeMatrixZoneForAthlete(
        playerId: playerId,
        athleteName: name,
        workoutKind: _selectedMatrixKind,
        allAthleteLogs: allAthleteLogs,
        periodStart: _period.start,
        periodEnd: _period.end,
        indicatorConfigs: _matrixConfigs,
      );

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
        matrixZoneResult: matrixResult,
        rawLogs: allAthleteLogs,
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

            // 3. أشرطة اختيار الأنواع والزونات المتخصصة حسب نوع المنحنى
            if (widget.curveType == ProgressCurveType.matrixZone)
              _buildMatrixZoneKindSelectorBar(s),
            if (widget.curveType == ProgressCurveType.zoneHours)
              _buildZoneHoursKindSelectorBar(s),
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
    if (widget.user?.isAthlete == true) {
      return const SizedBox.shrink();
    }
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
                            color:
                                isSelected ? color : EngineRowingUI.bgGridLine,
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
                            if (isSelected) ...[
                              const SizedBox(width: 4),
                              const RowingTrendIndicator(
                                direction: MetricTrendDirection.up,
                                size: 10,
                              ),
                            ],
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

  Widget _buildMatrixZoneKindSelectorBar(AppStrings s) {
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
            for (final kind in kProgramWorkoutKinds)
              _buildZoneChip(
                label: kind,
                color: EngineRowingUI.neonLime,
                selected:
                    _selectedMatrixKind.toLowerCase() == kind.toLowerCase(),
                onTap: () => _onMatrixKindChanged(kind),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildZoneHoursKindSelectorBar(AppStrings s) {
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
              label: s.allWorkoutsKind,
              color: EngineRowingUI.neonLime,
              selected: _selectedZoneHoursKind == 'ALL',
              onTap: () => _onZoneHoursKindChanged('ALL'),
            ),
            for (final kind in kProgramWorkoutKinds)
              _buildZoneChip(
                label: kind,
                color: EngineRowingUI.zone2Color,
                selected:
                    _selectedZoneHoursKind.toLowerCase() == kind.toLowerCase(),
                onTap: () => _onZoneHoursKindChanged(kind),
              ),
          ],
        ),
      ),
    );
  }

  void _onMatrixKindChanged(String kind) {
    if (_selectedMatrixKind.toLowerCase() == kind.toLowerCase()) return;
    setState(() {
      _selectedMatrixKind = kind;
      _athleteCache.clear();
    });
    for (final pid in _selectedPlayerIds) {
      _fetchSingleAthlete(pid);
    }
  }

  void _onZoneHoursKindChanged(String kind) {
    if (_selectedZoneHoursKind.toLowerCase() == kind.toLowerCase()) return;
    setState(() {
      _selectedZoneHoursKind = kind;
      _athleteCache.clear();
    });
    for (final pid in _selectedPlayerIds) {
      _fetchSingleAthlete(pid);
    }
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
              trailing: IconButton(
                icon: const Icon(Icons.info_outline_rounded,
                    color: EngineRowingUI.neonLime, size: 18),
                onPressed: () =>
                    _showInfoDialog(s.matrixZoneTitle, s.matrixZoneDesc),
              ),
            ),
            _buildMatrixZoneSharedChart(s),
          ],
        );

      case ProgressCurveType.efAndDecoupling:
        final primaryId =
            _selectedPlayerIds.isNotEmpty ? _selectedPlayerIds.first : 0;
        final primaryData = _athleteCache[primaryId];
        final multiWorkouts = {
          for (final pid in _selectedPlayerIds)
            pid: _athleteCache[pid]?.rawLogs ?? const <Map<String, Object?>>[],
        };
        final names = {
          for (final pid in _selectedPlayerIds)
            pid: _athleteCache[pid]?.name ?? _nameForId(pid),
        };
        final colors = {
          for (final pid in _selectedPlayerIds)
            pid: _athleteColors[pid] ?? Colors.cyan,
        };

        return ListView(
          padding: EdgeInsets.zero,
          children: [
            ProgressCurveHeader(
              curveName: s.efDecouplingTitle,
              period: _period,
              trailing: IconButton(
                icon: const Icon(Icons.info_outline_rounded,
                    color: EngineRowingUI.neonLime, size: 18),
                onPressed: () =>
                    _showInfoDialog(s.efDecouplingTitle, s.efDecouplingDesc),
              ),
            ),
            EfZoneCurveWidget(
              workouts: primaryData?.rawLogs ?? const [],
              periodStart: _period.start,
              periodEnd: _period.end,
              athleteName: primaryData?.name ?? _nameForId(primaryId),
              playerId: primaryId,
              multiAthleteWorkouts:
                  _selectedPlayerIds.length > 1 ? multiWorkouts : null,
              athleteNames: names,
              athleteColors: colors,
            ),
            const SizedBox(height: 14),
            DecouplingTrendCurveWidget(
              workouts: primaryData?.rawLogs ?? const [],
              periodStart: _period.start,
              periodEnd: _period.end,
              athleteName: primaryData?.name ?? _nameForId(primaryId),
              playerId: primaryId,
              multiAthleteWorkouts:
                  _selectedPlayerIds.length > 1 ? multiWorkouts : null,
              athleteNames: names,
              athleteColors: colors,
            ),
          ],
        );

      case ProgressCurveType.watts:
        final primaryId =
            _selectedPlayerIds.isNotEmpty ? _selectedPlayerIds.first : 0;
        final primaryData = _athleteCache[primaryId];
        final multiWorkouts = {
          for (final pid in _selectedPlayerIds)
            pid: _athleteCache[pid]?.rawLogs ?? const <Map<String, Object?>>[],
        };
        final names = {
          for (final pid in _selectedPlayerIds)
            pid: _athleteCache[pid]?.name ?? _nameForId(pid),
        };
        final colors = {
          for (final pid in _selectedPlayerIds)
            pid: _athleteColors[pid] ?? Colors.cyan,
        };

        return ListView(
          padding: EdgeInsets.zero,
          children: [
            ProgressCurveHeader(
              curveName: s.dynamicWattsTitle,
              period: _period,
              trailing: IconButton(
                icon: const Icon(Icons.info_outline_rounded,
                    color: EngineRowingUI.neonLime, size: 18),
                onPressed: () =>
                    _showInfoDialog(s.wattsCurveTitle, s.wattsCurveDesc),
              ),
            ),
            DynamicWattsCurveWidget(
              workouts: primaryData?.rawLogs ?? const [],
              periodStart: _period.start,
              periodEnd: _period.end,
              athleteName: primaryData?.name ?? _nameForId(primaryId),
              playerId: primaryId,
              multiAthleteWorkouts:
                  _selectedPlayerIds.length > 1 ? multiWorkouts : null,
              athleteNames: names,
              athleteColors: colors,
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
                onPressed: () => _showInfoDialog(s.pmcTitle, s.pmcExplanation),
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
                onPressed: () => _showInfoDialog(s.hrvTitle, s.hrvExplanation),
              ),
            ),
            ..._buildStackedAthleteBlocks(
              builder: (pid, data, color) => HrvCurveBlock(
                s: s,
                athleteName: data?.name ?? _nameForId(pid),
                athleteColor: color,
                points: data?.hrvPoints ?? const [],
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
                onPressed: () => _showInfoDialog(s.rhrTitle, s.rhrExplanation),
              ),
            ),
            ..._buildStackedAthleteBlocks(
              builder: (pid, data, color) => RhrCurveBlock(
                s: s,
                athleteName: data?.name ?? _nameForId(pid),
                athleteColor: color,
                points: data?.rhrPoints ?? const [],
                isLoading: data == null && _loadingPlayerIds.contains(pid),
              ),
            ),
            // 3. Sleep
            ProgressCurveHeader(
              curveName: s.chipSleep,
              period: _period,
              trailing: IconButton(
                icon: const Icon(Icons.info_outline_rounded,
                    color: EngineRowingUI.neonLime, size: 18),
                onPressed: () =>
                    _showInfoDialog(s.chipSleep, s.sleepWeightExplanation),
              ),
            ),
            ..._buildStackedAthleteBlocks(
              builder: (pid, data, color) => SleepCurveBlock(
                s: s,
                athleteName: data?.name ?? _nameForId(pid),
                athleteColor: color,
                points: data?.sleepPoints ?? const [],
                isLoading: data == null && _loadingPlayerIds.contains(pid),
              ),
            ),
            // 4. Weight
            ProgressCurveHeader(
              curveName: s.chipWeight,
              period: _period,
              trailing: IconButton(
                icon: const Icon(Icons.info_outline_rounded,
                    color: EngineRowingUI.neonLime, size: 18),
                onPressed: () =>
                    _showInfoDialog(s.chipWeight, s.sleepWeightExplanation),
              ),
            ),
            ..._buildStackedAthleteBlocks(
              builder: (pid, data, color) => WeightCurveBlock(
                s: s,
                athleteName: data?.name ?? _nameForId(pid),
                athleteColor: color,
                points: data?.weightPoints ?? const [],
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
              builder: (pid, data, color) => EupneaCurveBlock(
                s: s,
                athleteName: data?.name ?? _nameForId(pid),
                athleteColor: color,
                workouts: data?.rawLogs ?? const [],
                periodStart: _period.start,
                periodEnd: _period.end,
                mhr: data?.mhr ?? 190,
                effectiveRhr: data?.effectiveRhr ?? 60,
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
              trailing: IconButton(
                icon: const Icon(Icons.info_outline_rounded,
                    color: EngineRowingUI.neonLime, size: 18),
                onPressed: () =>
                    _showInfoDialog(s.zoneHoursTitle, s.zoneHoursDesc),
              ),
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
              trailing: IconButton(
                icon: const Icon(Icons.info_outline_rounded,
                    color: EngineRowingUI.neonLime, size: 18),
                onPressed: () =>
                    _showInfoDialog(s.cpTestsCurveTitle, s.cpTestsCurveDesc),
              ),
            ),
            ..._buildStackedAthleteBlocks(
              builder: (pid, data, color) => CpBarsCurveBlock(
                s: s,
                athleteName: data?.name ?? _nameForId(pid),
                athleteColor: color,
                playerId: pid,
                periodStart: _period.start,
                periodEnd: _period.end,
                cpTestRows: data?.cpTestRows ?? const [],
                cpValuePoints: data?.cpValuePoints ?? const [],
                isLoading: data == null && _loadingPlayerIds.contains(pid),
                onTestDataChanged: () => _fetchSingleAthlete(pid),
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
  // Matrix Zone: منحنى Matrix Zone مع المقارنة بين اللاعبين ومنحنى القدرة (Capacity Curve)
  // ════════════════════════════════════════════════════════════════
  Widget _buildMatrixZoneSharedChart(AppStrings s) {
    // التحقق من مجموع نسب المؤشرات
    final currentWeightSum = _matrixConfigs.fold<double>(
      0.0,
      (acc, c) => acc + c.weight,
    );
    final isWeightSumValid = (currentWeightSum - 100.0).abs() < 0.01;

    // استخراج أقصى واط عبر كل اللاعبين لتطبيع ارتفاع الشرايط
    double maxWattsAcrossAll = 350.0;
    for (final pid in _selectedPlayerIds) {
      final res = _athleteCache[pid]?.matrixZoneResult;
      if (res != null) {
        for (final d in res.detailsByZone.values) {
          if (d.bestWatts != null && d.bestWatts! > maxWattsAcrossAll) {
            maxWattsAcrossAll = d.bestWatts!;
          }
        }
      }
    }
    maxWattsAcrossAll = max(maxWattsAcrossAll + 30.0, 300.0);

    return ProgressPanel(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. ترويسة اللوحة المشتركة مع زر (i) لمنحنى القدرة
          Row(
            children: [
              Expanded(
                child: Text(
                  s.matrixZoneTitle,
                  style: const TextStyle(
                    color: EngineRowingUI.textWhite,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(
                  Icons.info_outline_rounded,
                  color: EngineRowingUI.neonLime,
                  size: 20,
                ),
                tooltip: s.capacityCurveTitle,
                onPressed: () => _showInfoDialog(
                  s.capacityCurveTitle,
                  s.capacityCurveExplanation,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),

          // شريط أسماء اللاعبين المختارين
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
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
          const SizedBox(height: 14),

          // تنبيه مجموع الأوزان إن لم يكن 100%
          if (!isWeightSumValid)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
                border:
                    Border.all(color: Colors.redAccent.withValues(alpha: 0.6)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded,
                      color: Colors.redAccent, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      s.weightsSumMustBe100(currentWeightSum.round()),
                      style: const TextStyle(
                        color: Colors.redAccent,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // لو حذف المدرب كل المؤشرات
          if (_matrixConfigs.isEmpty)
            Container(
              height: 160,
              alignment: Alignment.center,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    s.addIndicatorToShowCurve,
                    style: const TextStyle(
                      color: EngineRowingUI.captionGrey,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 10),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.add, size: 16),
                    label: Text(s.addIndicator),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: EngineRowingUI.neonLime,
                      foregroundColor: EngineRowingUI.bgNavy,
                    ),
                    onPressed: () => _showAddIndicatorDialog(s),
                  ),
                ],
              ),
            )
          else ...[
            // 2. رسم المقارنة: صفوف اللاعبين فوق بعض مع 7 شرايط ومنحنى القدرة لكل لاعب
            ..._selectedPlayerIds.map((pid) {
              final color = _colorForAthlete(pid);
              final athleteData = _athleteCache[pid];
              final athleteRes = athleteData?.matrixZoneResult;
              final athleteName = athleteData?.name ?? _nameForId(pid);

              return _buildMatrixZoneAthleteRow(
                s: s,
                playerId: pid,
                athleteName: athleteName,
                athleteColor: color,
                result: athleteRes,
                maxWatts: maxWattsAcrossAll,
              );
            }),
          ],

          const SizedBox(height: 16),

          // 3. لوحة إعداد المؤشرات وتوزيع النسب
          _buildMatrixZoneIndicatorsConfigPanel(s, currentWeightSum),

          const SizedBox(height: 16),

          // 4. قسم المدخلات المتاحة وجدول نبض الراحة ومصدره
          _buildAvailableInputsAndHeartRateTable(s),

          const SizedBox(height: 8),
          _buildCurveFooterChipsAndNotice(s, 'matrix'),
        ],
      ),
    );
  }

  /// صف لاعب واحد في Matrix Zone (الشرايط السبعة + منحنى القدرة)
  Widget _buildMatrixZoneAthleteRow({
    required AppStrings s,
    required int playerId,
    required String athleteName,
    required Color athleteColor,
    required MatrixZoneAthleteResult? result,
    required double maxWatts,
  }) {
    final orderedZones = HeartRateZones.orderedZones;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: EngineRowingUI.equationCardFill,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: athleteColor.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // عنوان اللاعب
          Row(
            children: [
              Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                      color: athleteColor, shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Text(
                athleteName,
                style: TextStyle(
                  color: athleteColor,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              if (result == null || !result.hasData)
                Text(
                  s.notEnoughData,
                  style: const TextStyle(
                      color: EngineRowingUI.captionGrey, fontSize: 11),
                ),
            ],
          ),
          const SizedBox(height: 10),

          // الشرايط السبعة للمناطق
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: orderedZones.map((z) {
                final detail = result?.detailsByZone[z];
                final zColor = HeartRateZones.zoneColor(z);
                final bestWatts = detail?.bestWatts;
                final barWidth = detail?.barWidth ?? 16.0;
                final baselineStart = detail?.startBaselineWatts;
                final baselineCurrent = detail?.currentBaselineWatts;

                // الارتفاع المنسوب للواط (أقصى ارتفاع 140px)
                final barHeight = bestWatts != null && bestWatts > 0
                    ? ((bestWatts / maxWatts) * 140.0).clamp(8.0, 140.0)
                    : 0.0;

                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // رقم الواط أو تنبيه لا توجد بيانات
                      Text(
                        bestWatts != null ? '${bestWatts.round()} W' : '--',
                        style: TextStyle(
                          color: bestWatts != null
                              ? EngineRowingUI.textWhite
                              : EngineRowingUI.captionGrey,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),

                      // الشريط الملون بعرض يطابق درجة التحسن
                      Stack(
                        alignment: Alignment.bottomCenter,
                        children: [
                          Container(
                            width: barWidth,
                            height: 140,
                            alignment: Alignment.bottomCenter,
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: bestWatts != null && bestWatts > 0
                                ? Container(
                                    width: barWidth,
                                    height: barHeight,
                                    decoration: BoxDecoration(
                                      color: zColor,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                  )
                                : Container(
                                    width: barWidth,
                                    height: 4,
                                    decoration: BoxDecoration(
                                      color: Colors.transparent,
                                      border: Border.all(
                                          color: Colors.grey.shade700,
                                          width: 1.0),
                                    ),
                                  ),
                          ),

                          // خط الأساس المرجعي المنقط على الشريط
                          if (baselineStart != null && baselineStart > 0)
                            Positioned(
                              bottom: ((baselineStart / maxWatts) * 140.0)
                                  .clamp(0.0, 140.0),
                              child: Tooltip(
                                message:
                                    '${s.baselineStartLabel}: ${baselineStart.round()} W, ${s.currentBaselineLabel}: ${baselineCurrent?.round() ?? baselineStart.round()} W',
                                child: Container(
                                  width: barWidth + 8,
                                  height: 2.5,
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    boxShadow: [
                                      BoxShadow(
                                          color: Colors.black
                                              .withValues(alpha: 0.5),
                                          blurRadius: 2),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),

                      // اسم المنطقة
                      SizedBox(
                        width: max(barWidth + 10, 48),
                        child: Text(
                          HeartRateZones.zoneDisplayName(z, isArabic: false),
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: zColor,
                            fontSize: 9.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 12),

          // منحنى القدرة (Capacity Curve) مع علامات LT1 و LT2
          if (result != null && result.hasData)
            _buildCapacityCurveChart(
              s: s,
              athleteColor: athleteColor,
              result: result,
            ),
        ],
      ),
    );
  }

  /// رسم منحنى القدرة (Capacity Curve) للاعب
  Widget _buildCapacityCurveChart({
    required AppStrings s,
    required Color athleteColor,
    required MatrixZoneAthleteResult result,
  }) {
    final spots = <FlSpot>[];
    final orderedZones = HeartRateZones.orderedZones;

    for (int i = 0; i < orderedZones.length; i++) {
      final z = orderedZones[i];
      final val = result.detailsByZone[z]?.capacityCurveValue;
      if (val != null) {
        spots.add(FlSpot(i.toDouble(), val));
      }
    }

    if (spots.length < 2) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              s.capacityCurveTitle,
              style: TextStyle(
                color: athleteColor,
                fontSize: 11.5,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(width: 8),
            // شارة LT1
            if (result.lt1Point != null)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                decoration: BoxDecoration(
                  color: EngineRowingUI.bgNavy,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                      color: HeartRateZones.zoneColor('Z2'), width: 1.0),
                ),
                child: const Text(
                  'LT1 (تقديري)',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.bold),
                ),
              ),
            const SizedBox(width: 6),
            // شارة LT2
            if (result.lt2Point != null)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                decoration: BoxDecoration(
                  color: EngineRowingUI.bgNavy,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                      color: HeartRateZones.zoneColor('Threshold'), width: 1.0),
                ),
                child: const Text(
                  'LT2 (تقديري)',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.bold),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 100,
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: LineChart(
              LineChartData(
                minX: 0,
                maxX: 6,
                minY: 60,
                maxY: 420,
                gridData: const FlGridData(show: false),
                titlesData: const FlTitlesData(show: false),
                borderData: FlBorderData(show: false),
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    curveSmoothness: 0.35,
                    color: athleteColor,
                    barWidth: 2.4,
                    dotData: FlDotData(
                      show: true,
                      getDotPainter: (spot, percent, bar, index) =>
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
        ),
      ],
    );
  }

  /// لوحة إعداد المؤشرات الأربعة وإضافة أو حذف مؤشرات
  Widget _buildMatrixZoneIndicatorsConfigPanel(
      AppStrings s, double currentSum) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: EngineRowingUI.equationCardFill,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: EngineRowingUI.bgGridLine),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.tune_rounded,
                  color: EngineRowingUI.neonLime, size: 18),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  s.isArabic
                      ? 'إعداد نسب المؤشرات (لكل اللاعبين)'
                      : 'Indicator Weights (Global)',
                  style: const TextStyle(
                    color: EngineRowingUI.textWhite,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '${s.isArabic ? 'المجموع' : 'Total'}: ${currentSum.round()}%',
                style: TextStyle(
                  color: (currentSum - 100.0).abs() < 0.01
                      ? EngineRowingUI.neonLime
                      : Colors.redAccent,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(Icons.add_circle_outline,
                    color: EngineRowingUI.neonLime, size: 20),
                tooltip: s.addIndicator,
                onPressed: () => _showAddIndicatorDialog(s),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // قائمة المؤشرات الحالية
          ..._matrixConfigs.map((cfg) {
            final name = ProgressCalcs.metricChipName(s, cfg.key);
            return Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: EngineRowingUI.cardFill,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      name,
                      style: const TextStyle(
                          color: EngineRowingUI.textWhite, fontSize: 12),
                    ),
                  ),
                  SizedBox(
                    width: 70,
                    child: TextFormField(
                      initialValue: cfg.weight.round().toString(),
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: EngineRowingUI.neonLime,
                          fontSize: 13,
                          fontWeight: FontWeight.bold),
                      decoration: const InputDecoration(
                        isDense: true,
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                        suffixText: '%',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (val) {
                        final parsed = double.tryParse(val);
                        if (parsed != null && parsed >= 0) {
                          _updateIndicatorWeight(cfg.key, parsed);
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(Icons.delete_outline,
                        color: Colors.redAccent, size: 18),
                    tooltip: s.isArabic ? 'حذف' : 'Delete',
                    onPressed: () => _confirmDeleteIndicator(s, cfg.key),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  void _updateIndicatorWeight(String key, double newWeight) async {
    final idx = _matrixConfigs.indexWhere((c) => c.key == key);
    if (idx < 0) return;

    final updated = List<MatrixZoneIndicatorConfig>.from(_matrixConfigs);
    updated[idx] = MatrixZoneIndicatorConfig(
      key: key,
      weight: newWeight,
      direction: updated[idx].direction,
      sortOrder: updated[idx].sortOrder,
    );

    setState(() {
      _matrixConfigs = updated;
    });

    final sum = updated.fold<double>(0.0, (acc, c) => acc + c.weight);
    if ((sum - 100.0).abs() < 0.01) {
      await ProgressCalcs.saveMatrixZoneConfig(updated);
      _athleteCache.clear();
      for (final pid in List<int>.from(_selectedPlayerIds)) {
        _fetchSingleAthlete(pid);
      }
    }
  }

  void _confirmDeleteIndicator(AppStrings s, String key) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: EngineRowingUI.cardFill,
        title: Text(
          s.confirmDeleteIndicator,
          style: const TextStyle(color: EngineRowingUI.textWhite, fontSize: 15),
        ),
        actions: [
          TextButton(
            child: Text(s.cancel,
                style: const TextStyle(color: EngineRowingUI.captionGrey)),
            onPressed: () => Navigator.of(ctx).pop(),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: Text(s.isArabic ? 'تأكيد الحذف' : 'Confirm Delete',
                style: const TextStyle(color: Colors.white)),
            onPressed: () async {
              Navigator.of(ctx).pop();
              final updated =
                  _matrixConfigs.where((c) => c.key != key).toList();
              setState(() {
                _matrixConfigs = updated;
              });
              final sum = updated.fold<double>(0.0, (acc, c) => acc + c.weight);
              if ((sum - 100.0).abs() < 0.01) {
                await ProgressCalcs.saveMatrixZoneConfig(updated);
                _athleteCache.clear();
                for (final pid in List<int>.from(_selectedPlayerIds)) {
                  _fetchSingleAthlete(pid);
                }
              }
            },
          ),
        ],
      ),
    );
  }

  void _showAddIndicatorDialog(AppStrings s) {
    String selectedField = 'hr';
    String selectedDir = 'up';
    double weight = 10.0;

    final availableFields = [
      'hr',
      'hr_max',
      'hr_post',
      'hr_1min',
      'rhr',
      'hrv',
      'weight',
      'fatigue',
      'sleep_hours',
      'avg_power',
      'distance',
      'split_500',
      'ef',
      'decoupling',
      'eupnea_1',
      'player_notes',
    ];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) {
          final isTextField = selectedField == 'player_notes';
          return AlertDialog(
            backgroundColor: EngineRowingUI.cardFill,
            title: Text(
              s.addIndicator,
              style: const TextStyle(
                  color: EngineRowingUI.textWhite, fontSize: 16),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: selectedField,
                  dropdownColor: EngineRowingUI.cardFill,
                  decoration: InputDecoration(
                    labelText: s.isArabic ? 'الحقل' : 'Field',
                    border: const OutlineInputBorder(),
                  ),
                  items: availableFields.map((f) {
                    return DropdownMenuItem<String>(
                      value: f,
                      child: Text(
                        f,
                        style: const TextStyle(color: EngineRowingUI.textWhite),
                      ),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setDlgState(() => selectedField = val);
                    }
                  },
                ),
                if (isTextField) ...[
                  const SizedBox(height: 8),
                  Text(
                    s.textFieldNotCalculatedWarning,
                    style: const TextStyle(color: Colors.amber, fontSize: 11),
                  ),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: selectedDir,
                        dropdownColor: EngineRowingUI.cardFill,
                        decoration: InputDecoration(
                          labelText: s.isArabic ? 'اتجاه التحسن' : 'Direction',
                          border: const OutlineInputBorder(),
                        ),
                        items: [
                          DropdownMenuItem(
                            value: 'up',
                            child: Text(
                                s.isArabic ? 'الأعلى أفضل' : 'Higher is better',
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 12)),
                          ),
                          DropdownMenuItem(
                            value: 'down',
                            child: Text(
                                s.isArabic ? 'الأقل أفضل' : 'Lower is better',
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 12)),
                          ),
                        ],
                        onChanged: (val) {
                          if (val != null) setDlgState(() => selectedDir = val);
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 80,
                      child: TextFormField(
                        initialValue: weight.round().toString(),
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: s.isArabic ? 'النسبة' : 'Weight',
                          suffixText: '%',
                          border: const OutlineInputBorder(),
                        ),
                        style: const TextStyle(color: Colors.white),
                        onChanged: (val) {
                          final p = double.tryParse(val);
                          if (p != null) weight = p;
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
            actions: [
              TextButton(
                child: Text(s.cancel,
                    style: const TextStyle(color: EngineRowingUI.captionGrey)),
                onPressed: () => Navigator.of(ctx).pop(),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: EngineRowingUI.neonLime),
                child: Text(s.isArabic ? 'إضافة' : 'Add',
                    style: const TextStyle(color: EngineRowingUI.bgNavy)),
                onPressed: () async {
                  Navigator.of(ctx).pop();
                  final updated =
                      List<MatrixZoneIndicatorConfig>.from(_matrixConfigs);
                  updated.add(MatrixZoneIndicatorConfig(
                    key: selectedField,
                    weight: weight,
                    direction: selectedDir,
                    sortOrder: updated.length,
                  ));
                  setState(() => _matrixConfigs = updated);
                  final sum =
                      updated.fold<double>(0.0, (acc, c) => acc + c.weight);
                  if ((sum - 100.0).abs() < 0.01) {
                    await ProgressCalcs.saveMatrixZoneConfig(updated);
                    _athleteCache.clear();
                    for (final pid in List<int>.from(_selectedPlayerIds)) {
                      _fetchSingleAthlete(pid);
                    }
                  }
                },
              ),
            ],
          );
        },
      ),
    );
  }

  /// قسم المدخلات المتاحة وجدول نبض الراحة الأقصى ومصدرهما
  Widget _buildAvailableInputsAndHeartRateTable(AppStrings s) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: EngineRowingUI.equationCardFill,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: EngineRowingUI.bgGridLine),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            s.maxHrRhrSourceTitle,
            style: const TextStyle(
              color: EngineRowingUI.textWhite,
              fontSize: 12.5,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          ..._selectedPlayerIds.map((pid) {
            final data = _athleteCache[pid];
            final name = data?.name ?? _nameForId(pid);
            final mhr = data?.mhr ?? 190;
            final rhr = data?.effectiveRhr ?? 0;
            final rhrText = rhr > 0 ? '$rhr bpm' : s.logMorningRhrPrompt;

            return Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: EngineRowingUI.cardFill,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 4,
                children: [
                  Text(
                    name,
                    style: TextStyle(
                      color: _colorForAthlete(pid),
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    'Max HR: $mhr bpm (${s.isArabic ? 'البروفايل' : 'Profile'})',
                    style: const TextStyle(
                        color: EngineRowingUI.captionGrey, fontSize: 10.5),
                  ),
                  Text(
                    'RHR: $rhrText',
                    style: TextStyle(
                      color: rhr > 0 ? EngineRowingUI.neonLime : Colors.amber,
                      fontSize: 10.5,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════
  // صف شارات المدخلات المشاركة فعلياً في الحساب + النص الثابت "منحنى تقديري فقط"
  // ════════════════════════════════════════════════════════════════
  Widget _buildCurveFooterChipsAndNotice(AppStrings s, String metricKey) {
    final metrics = ProgressCalcs.curveInvolvedMetrics[metricKey] ?? const [];
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (metrics.isNotEmpty)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: metrics.map((m) {
                  final label = ProgressCalcs.metricChipName(s, m);
                  return Container(
                    margin: const EdgeInsetsDirectional.only(end: 6),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: EngineRowingUI.equationCardFill,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: EngineRowingUI.neonLime.withValues(alpha: 0.35),
                        width: 0.8,
                      ),
                    ),
                    child: Text(
                      label,
                      style: const TextStyle(
                        color: EngineRowingUI.neonLime,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          const SizedBox(height: 5),
          Directionality(
            textDirection: s.isArabic ? TextDirection.rtl : TextDirection.ltr,
            child: Text(
              s.estimatedCurveNotice,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: EngineRowingUI.captionGrey,
                fontSize: 10,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════
  // ويدجت منحنى لاعب مفرد ملزوق مباشرة بدون فراغ خارجي (margin & padding = 0)
  // ════════════════════════════════════════════════════════════════
  // ignore: unused_element
  Widget _buildAthleteLineBlock({
    required AppStrings s,
    required String athleteName,
    required Color athleteColor,
    required List<DateValuePoint> points,
    required String unit,
    required bool enableMA7,
    required bool isLoading,
    required String metricKey,
  }) {
    final maPoints = enableMA7
        ? ProgressCalcs.movingAverage7(points)
        : const <DateValuePoint>[];

    double? minY;
    double? maxY;
    final nonNullVals =
        points.where((p) => p.value != null).map((p) => p.value!).toList();
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
          bottom:
              const BorderSide(color: EngineRowingUI.bgGridLine, width: 1.0),
        ),
        boxShadow: [
          BoxShadow(
            color: EngineRowingUI.neonLime.withValues(alpha: 0.10),
            blurRadius: 6.0,
            spreadRadius: 0.0,
          ),
        ],
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
                  fontSize: 16,
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
                          getDotPainter: (spot, percent, bar, index) {
                            final isLast = index == points.length - 1;
                            return FlDotCirclePainter(
                              radius: isLast
                                  ? 4.6
                                  : (points.length == 1 ? 4.2 : 2.6),
                              color: isLast
                                  ? const Color(0xFFB8F229)
                                  : athleteColor,
                              strokeColor: Colors.white,
                              strokeWidth: isLast ? 1.4 : 0.9,
                            );
                          },
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
          if (enableMA7 && maPoints.any((p) => p.value != null)) ...[
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Container(
                  width: 14,
                  height: 2,
                  decoration: BoxDecoration(
                    color: athleteColor.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  s.movingAverage7Legend,
                  style: TextStyle(
                    color: athleteColor.withValues(alpha: 0.85),
                    fontSize: 9.5,
                  ),
                ),
              ],
            ),
          ],
          _buildCurveFooterChipsAndNotice(s, metricKey),
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
          bottom:
              const BorderSide(color: EngineRowingUI.bgGridLine, width: 1.0),
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
              fontSize: 16,
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
                              fontSize: 13,
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
                              fontSize: 13,
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
                              fontSize: 13,
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
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  for (final entry in rows) _buildZoneHoursRow(s, entry),
                ],
              ),
            ),
          _buildCurveFooterChipsAndNotice(s, 'zone_hours'),
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
    final hasCp = (data != null && data.latestCp != null && data.latestCp! > 0);
    final entries = hasCp ? data.pmcEntries : const <DailyLoadEntry>[];
    final today = hasCp ? data.todayLoad : null;
    final ctlToday = today?.ctl;
    final atlToday = today?.atl;
    final tsbToday = today?.tsb;
    final (tsbLabel, tsbColor) = (hasCp && tsbToday != null)
        ? _tsbVisualFromTheme(context, s, tsbToday)
        : ('--', EngineRowingUI.labelSlate);

    return Container(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: EngineRowingUI.cardFill,
        border: Border(
          left: BorderSide(color: athleteColor, width: 3.0),
          bottom:
              const BorderSide(color: EngineRowingUI.bgGridLine, width: 1.0),
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
                  fontSize: 16,
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
                  value: ctlToday != null ? ctlToday.toStringAsFixed(1) : '--',
                  color: EngineRowingUI.zone2Color,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _buildPmcTodayCard(
                  label: '${s.atlLineLabel} (${s.todayLabel})',
                  value: atlToday != null ? atlToday.toStringAsFixed(1) : '--',
                  color: EngineRowingUI.zone3Color,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _buildPmcTodayCard(
                  label: '${s.tsbBarLabel} (${s.todayLabel})',
                  value: tsbToday != null ? tsbToday.toStringAsFixed(1) : '--',
                  color: tsbColor,
                ),
              ),
            ],
          ),

          if (!hasCp) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: EngineRowingUI.equationCardFill,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.amber.shade700, width: 1.2),
              ),
              child: Row(
                children: [
                  Icon(Icons.speed_rounded,
                      color: Colors.amber.shade400, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      s.recordCpTestNotice,
                      style: const TextStyle(
                        color: EngineRowingUI.textWhite,
                        fontWeight: FontWeight.bold,
                        fontSize: 12.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ] else if (data.missingCpWorkoutsCount > 0) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: EngineRowingUI.equationCardFill,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                    color: Theme.of(context)
                        .colorScheme
                        .error
                        .withValues(alpha: 0.5)),
              ),
              child: Text(
                '${s.missingCpNotice} (${data.missingCpDates.join(', ')})',
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
          else if (!hasCp)
            const SizedBox.shrink()
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
          _buildCurveFooterChipsAndNotice(s, 'pmc'),
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
              fontSize: 12.5,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Directionality(
            textDirection: TextDirection.ltr,
            child: Text(
              RowingNumberFormatter.toEnglishDigits(value),
              style: TextStyle(
                color: color,
                fontSize: 20,
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
  // ignore: unused_element
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
          bottom:
              const BorderSide(color: EngineRowingUI.bgGridLine, width: 1.0),
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
                  fontSize: 16,
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
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
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
          _buildCurveFooterChipsAndNotice(s, 'cp_tests'),
        ],
      ),
    );
  }
}
