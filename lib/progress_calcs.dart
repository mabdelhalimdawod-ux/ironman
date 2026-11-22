import 'dart:math';
import 'app_strings.dart';
import 'db.dart';
import 'heart_rate_zones.dart';

/// الثوابت المعتمدة لحالات TSB من مكان واحد
class TsbThresholds {
  static const double excessRest = 25.0; // > +25 : راحة زيادة
  static const double raceReadyMin = 5.0; // +5 .. +25 : جاهز للسباق
  static const double neutralMin = -10.0; // -10 .. +5 : محايد
  static const double productiveBuildMin = -30.0; // -30 .. -10 : بناء منتج
  // < -30 : خطر إجهاد زيادة
}

/// تصنيفات حالة TSB الخمسة
enum TsbStatus {
  excessRest,
  raceReady,
  neutral,
  productiveBuild,
  overreachRisk,
}

/// حدود الزون بمعادلة كارفونين بدقة عشرية
class KarvonenZoneBound {
  final String zoneKey;
  final double minHR;
  final double maxHR;

  const KarvonenZoneBound({
    required this.zoneKey,
    required this.minHR,
    required this.maxHR,
  });
}

/// صف بيانات في جدول ساعات الزونات
class ZoneHoursEntry {
  final String zoneKey; // 'Z1', 'Z2', ..., 'VO2 max', 'NO_ZONE'
  final int totalSeconds;
  final double hours;
  final double percentage;

  const ZoneHoursEntry({
    required this.zoneKey,
    required this.totalSeconds,
    required this.hours,
    required this.percentage,
  });
}

/// سجل حمل يومي مخزن في جدول daily_load
class DailyLoadEntry {
  final int playerId;
  final String date;
  final double? tss;
  final double ctl;
  final double atl;
  final double tsb;

  const DailyLoadEntry({
    required this.playerId,
    required this.date,
    required this.tss,
    required this.ctl,
    required this.atl,
    required this.tsb,
  });

  factory DailyLoadEntry.fromMap(Map<String, Object?> map) {
    return DailyLoadEntry(
      playerId: (map['player_id'] as num).toInt(),
      date: map['date'] as String,
      tss: (map['tss'] as num?)?.toDouble(),
      ctl: (map['ctl'] as num?)?.toDouble() ?? 0.0,
      atl: (map['atl'] as num?)?.toDouble() ?? 0.0,
      tsb: (map['tsb'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

/// نقطة زمنية ذات تاريخ وقيمة لحسابات المنحنيات
class DateValuePoint {
  final DateTime date;
  final double? value;

  const DateValuePoint({required this.date, this.value});
}

/// ملخص أداء اللاعب في زون معين لمقارنة خط الأساس (Personal Best Baseline)
class ZoneBaseline {
  final String zone;
  final double? bestWatts; // أعلى واط
  final double? bestSplitSeconds; // أقل زمن سبليت (الأسرع)
  final double? bestDecoupling; // أقل تفكك قلبي (الأفضل)

  const ZoneBaseline({
    required this.zone,
    this.bestWatts,
    this.bestSplitSeconds,
    this.bestDecoupling,
  });
}

/// اتجاه المؤشر المثلث
enum ProgressTrend {
  up, // تحسن (فسفوري)
  down, // تراجع (أحمر)
  neutral, // مستقر
}

/// محرك الحسابات النقي لتاب Progress
class ProgressCalcs {
  /// ── 1. حساب المتوسط المتحرك الناعم لـ 7 أيام (movingAverage7) ──
  /// الشرط: لكل يوم يتم حساب متوسط قراءات آخر 7 أيام شاملة اليوم.
  /// يظهر فقط إذا كان هناك 4 قراءات على الأقل في نافذة الـ 7 أيام، وإلا يرجع null لهذا اليوم.
  static List<DateValuePoint> movingAverage7(List<DateValuePoint> points) {
    if (points.isEmpty) return [];

    // ترتيب النقاط تصاعدياً باليوم
    final sorted = List<DateValuePoint>.from(points)
      ..sort((a, b) => a.date.compareTo(b.date));

    final result = <DateValuePoint>[];

    for (int i = 0; i < sorted.length; i++) {
      final curDate = sorted[i].date;
      final startWindow = DateTime(curDate.year, curDate.month, curDate.day)
          .subtract(const Duration(days: 6)); // نافذة 7 أيام شاملة اليوم

      // جمع كل القراءات الواقعة داخل النافذة حتى هذا اليوم
      final windowValues = <double>[];
      for (int j = 0; j <= i; j++) {
        final d = sorted[j].date;
        final dMidnight = DateTime(d.year, d.month, d.day);
        if (!dMidnight.isBefore(startWindow) && !dMidnight.isAfter(curDate)) {
          if (sorted[j].value != null) {
            windowValues.add(sorted[j].value!);
          }
        }
      }

      // شرط الـ 4 قراءات على الأقل
      if (windowValues.length >= 4) {
        final avg = windowValues.reduce((a, b) => a + b) / windowValues.length;
        result.add(DateValuePoint(
          date: curDate,
          value: double.parse(avg.toStringAsFixed(2)),
        ));
      } else {
        result.add(DateValuePoint(
          date: curDate,
          value: null,
        ));
      }
    }

    return result;
  }

  /// ── 2. حساب النبض المستهدف بمعادلة كارفونين للزونات السبعة ──
  /// Target HR = RHR + ((MHR - RHR) * Percentage)
  static int karvonenTargetHR({
    required int mhr,
    required int rhr,
    double? percentage,
    double? hrPercent,
  }) {
    final pct = percentage ?? hrPercent ?? 0.60;
    if (rhr <= 0 || mhr <= rhr) return (mhr * pct).round();
    final hrr = mhr - rhr;
    return (rhr + (hrr * pct)).round();
  }

  /// تحديد الزون بمعادلة كارفونين ونسب كوتش المعتمدة
  static String determineZone({
    required int hr,
    required int mhr,
    required int rhr,
  }) {
    return HeartRateZones.determineZone(hr: hr, mhr: mhr, rhr: rhr) ?? 'Z2';
  }

  /// ── 3. حساب خط الأساس (Personal Best) لكل زون على حدة ──
  /// يستخلص أفضل واط، أسرع سبليت، وأقل decoupling حققها اللاعب في هذا الزون بعينه
  static Map<String, ZoneBaseline> computeZoneBaselines(
      List<Map<String, dynamic>> logs) {
    final Map<String, double> maxWatts = {};
    final Map<String, double> minSplit = {};
    final Map<String, double> minDecoupling = {};

    for (final row in logs) {
      final rawZone = row['zone'] as String? ?? row['session_zone'] as String?;
      if (rawZone == null || rawZone.isEmpty) continue;
      final zone = HeartRateZones.normalizeZoneKey(rawZone);

      final watts = (row['watts'] as num?)?.toDouble() ??
          (row['avg_power'] as num?)?.toDouble();
      final split = (row['split_500'] as num?)?.toDouble();
      final decoupling = (row['decoupling'] as num?)?.toDouble();

      if (watts != null && watts > 0) {
        if (!maxWatts.containsKey(zone) || watts > maxWatts[zone]!) {
          maxWatts[zone] = watts;
        }
      }

      if (split != null && split > 0) {
        if (!minSplit.containsKey(zone) || split < minSplit[zone]!) {
          minSplit[zone] = split;
        }
      }

      if (decoupling != null && decoupling > 0) {
        if (!minDecoupling.containsKey(zone) ||
            decoupling < minDecoupling[zone]!) {
          minDecoupling[zone] = decoupling;
        }
      }
    }

    final baselines = <String, ZoneBaseline>{};
    for (final z in HeartRateZones.orderedZones) {
      baselines[z] = ZoneBaseline(
        zone: z,
        bestWatts: maxWatts[z],
        bestSplitSeconds: minSplit[z],
        bestDecoupling: minDecoupling[z],
      );
    }
    return baselines;
  }

  /// تقييم اتجاه الواط للزون: هل تحسن (>= خط الأساس) أم تراجع؟
  static ProgressTrend evalWattsTrend({
    required double currentWatts,
    required double? baselineWatts,
  }) {
    if (baselineWatts == null || baselineWatts <= 0) {
      return ProgressTrend.neutral;
    }
    if (currentWatts >= baselineWatts) return ProgressTrend.up;
    if (currentWatts >= baselineWatts * 0.95) return ProgressTrend.neutral;
    return ProgressTrend.down;
  }

  /// تقييم اتجاه السبليت للزون: الأسرع (أقل ثوانٍ) يعتبر تحسن
  static ProgressTrend evalSplitTrend({
    required double currentSplit,
    required double? baselineSplit,
  }) {
    if (baselineSplit == null || baselineSplit <= 0) {
      return ProgressTrend.neutral;
    }
    if (currentSplit <= baselineSplit) return ProgressTrend.up;
    if (currentSplit <= baselineSplit * 1.03) return ProgressTrend.neutral;
    return ProgressTrend.down;
  }

  /// تقييم اتجاه التفكك القلبي Decoupling: الأقل يعتبر تحسن
  static ProgressTrend evalDecouplingTrend({
    required double currentDecoupling,
    required double? baselineDecoupling,
  }) {
    if (baselineDecoupling == null || baselineDecoupling <= 0) {
      return ProgressTrend.neutral;
    }
    if (currentDecoupling <= baselineDecoupling) return ProgressTrend.up;
    if (currentDecoupling <= baselineDecoupling * 1.05) {
      return ProgressTrend.neutral;
    }
    return ProgressTrend.down;
  }

  /// ── 4. حسابات الـ PMC (Performance Management Chart: CTL, ATL, TSB) ──
  static Map<String, dynamic> calculatePMC({
    required List<Map<String, dynamic>> dailyTssList, // [{date: DateTime, tss: double}]
    DateTime? endDate,
    double initialCtl = 0,
    double initialAtl = 0,
  }) {
    if (dailyTssList.isEmpty) {
      return {
        'ctlPoints': <DateValuePoint>[],
        'atlPoints': <DateValuePoint>[],
        'tsbPoints': <DateValuePoint>[],
        'currentCTL': 0.0,
        'currentATL': 0.0,
        'currentTSB': 0.0,
      };
    }

    // تجميع الـ TSS حسب اليوم
    final Map<String, double> dayTss = {};
    for (final item in dailyTssList) {
      final d = item['date'] as DateTime;
      final dateKey = formatDateKey(d);
      final tss = (item['tss'] as num?)?.toDouble() ?? 0.0;
      dayTss[dateKey] = (dayTss[dateKey] ?? 0.0) + tss;
    }

    final sortedDates = dayTss.keys.toList()..sort();
    final firstDate = DateTime.parse(sortedDates.first);
    final rawLastDate = DateTime.parse(sortedDates.last);
    final normEnd = endDate != null
        ? DateTime(endDate.year, endDate.month, endDate.day)
        : rawLastDate;
    final lastDate = normEnd.isAfter(rawLastDate) ? normEnd : rawLastDate;

    final ctlPoints = <DateValuePoint>[];
    final atlPoints = <DateValuePoint>[];
    final tsbPoints = <DateValuePoint>[];

    double ctl = initialCtl;
    double atl = initialAtl;

    final kCtl = 1.0 - exp(-1.0 / 42.0);
    final kAtl = 1.0 - exp(-1.0 / 7.0);

    for (var cur = firstDate;
        !cur.isAfter(lastDate);
        cur = cur.add(const Duration(days: 1))) {
      final key = formatDateKey(cur);
      final tss = dayTss[key] ?? 0.0;

      // TSB_today = CTL_yesterday - ATL_yesterday
      final tsb = ctl - atl;
      ctl = ctl + (tss - ctl) * kCtl;
      atl = atl + (tss - atl) * kAtl;

      ctlPoints.add(DateValuePoint(
          date: cur, value: double.parse(ctl.toStringAsFixed(2))));
      atlPoints.add(DateValuePoint(
          date: cur, value: double.parse(atl.toStringAsFixed(2))));
      tsbPoints.add(DateValuePoint(
          date: cur, value: double.parse(tsb.toStringAsFixed(2))));
    }

    return {
      'ctlPoints': ctlPoints,
      'atlPoints': atlPoints,
      'tsbPoints': tsbPoints,
      'currentCTL': ctlPoints.isNotEmpty ? ctlPoints.last.value : 0.0,
      'currentATL': atlPoints.isNotEmpty ? atlPoints.last.value : 0.0,
      'currentTSB': tsbPoints.isNotEmpty ? tsbPoints.last.value : 0.0,
    };
  }

  /// تنسيق التاريخ كـ YYYY-MM-DD من DateTime أو String
  static String formatDateKey(Object date) {
    if (date is DateTime) {
      return dstr(date);
    }
    final raw = date.toString().trim();
    if (raw.length >= 10 && RegExp(r'^\d{4}-\d{2}-\d{2}').hasMatch(raw)) {
      return raw.substring(0, 10);
    }
    final parsed = DateTime.tryParse(raw);
    if (parsed != null) return dstr(parsed);
    return raw;
  }

  /// حدود زون واحد بمعادلة كارفونين بدقة عشرية من نفس ثوابت HeartRateZones
  static KarvonenZoneBound karvonenZoneBounds({
    required int mhr,
    required int rhr,
    required String zone,
  }) {
    final clean = HeartRateZones.normalizeZoneKey(zone);
    final pct = HeartRateZones.zonePercentages[clean] ?? const [0.55, 0.65];
    if (rhr <= 0 || mhr <= rhr) {
      return KarvonenZoneBound(
        zoneKey: clean,
        minHR: double.parse((mhr * pct[0]).toStringAsFixed(4)),
        maxHR: double.parse((mhr * pct[1]).toStringAsFixed(4)),
      );
    }
    final hrr = mhr - rhr;
    return KarvonenZoneBound(
      zoneKey: clean,
      minHR: double.parse((rhr + hrr * pct[0]).toStringAsFixed(4)),
      maxHR: double.parse((rhr + hrr * pct[1]).toStringAsFixed(4)),
    );
  }

  /// حدود الزونات السبعة جميعها بمعادلة كارفونين بدقة عشرية
  static Map<String, KarvonenZoneBound> karvonenAllZoneBounds({
    required int mhr,
    required int rhr,
  }) {
    return {
      for (final z in HeartRateZones.orderedZones)
        z: karvonenZoneBounds(mhr: mhr, rhr: rhr, zone: z),
    };
  }

  /// حساب جدول ساعات الزونات السبعة + "بدون زون" من سجلات اللاعب (logs)
  /// يعتمد على النبض الفعلي والحدود المعتمدة بمعادلة كارفونين وعلى duration_seconds للزمن
  static List<ZoneHoursEntry> computeZoneHours(
    List<Map<String, dynamic>> logs, {
    int? defaultMhr,
    int? defaultRhr,
  }) {
    const orderedKeys = [...HeartRateZones.orderedZones, 'NO_ZONE'];
    final secondsByZone = <String, int>{for (final k in orderedKeys) k: 0};

    for (final row in logs) {
      final dur = (row['duration_seconds'] as num?)?.toInt() ?? 0;
      if (dur <= 0) continue;

      final hr = (row['hr'] as num?)?.toInt();
      if (hr == null || hr <= 0) {
        secondsByZone['NO_ZONE'] = (secondsByZone['NO_ZONE'] ?? 0) + dur;
        continue;
      }

      final pMhr = (row['player_mhr'] as num?)?.toInt() ?? 0;
      final rMhr = (row['mhr'] as num?)?.toInt() ?? 0;
      final hMhr = (row['hr_max'] as num?)?.toInt() ?? 0;
      final effMhr =
          pMhr > 0 ? pMhr : (rMhr > 0 ? rMhr : (hMhr > 0 ? hMhr : (defaultMhr ?? 0)));

      final rowRhr = (row['rhr'] as num?)?.toInt() ?? 0;
      final effRhr = rowRhr > 0 ? rowRhr : (defaultRhr ?? 60);

      String? zone;
      if (row['zone'] != null && row['zone'].toString().trim().isNotEmpty) {
        zone = HeartRateZones.normalizeZoneKey(row['zone'].toString());
      } else if (effMhr > 0 && hr > 0) {
        zone = HeartRateZones.determineZone(hr: hr, mhr: effMhr, rhr: effRhr);
      }
      zone ??= row['session_zone'] != null
          ? HeartRateZones.normalizeZoneKey(row['session_zone'].toString())
          : null;

      if (zone == null) {
        secondsByZone['NO_ZONE'] = (secondsByZone['NO_ZONE'] ?? 0) + dur;
      } else {
        secondsByZone[zone] = (secondsByZone[zone] ?? 0) + dur;
      }
    }

    final totalSeconds = secondsByZone.values.fold<int>(0, (a, b) => a + b);
    return orderedKeys.map((key) {
      final secs = secondsByZone[key] ?? 0;
      return ZoneHoursEntry(
        zoneKey: key,
        totalSeconds: secs,
        hours: secs / 3600.0,
        percentage: totalSeconds > 0 ? (secs / totalSeconds) * 100.0 : 0.0,
      );
    }).toList();
  }

  /// حساب TSS لتمرين واحد بالمعادلة الثابتة:
  /// TSS = (t_sec × P × IF) / (CP × 3600) × 100 ، حيث IF = P / CP
  /// يرجع null (يعرض "--") إذا لم تتوفر قيمة CP صالحة أو كانت المدخلات ناقصة
  static double? calculateWorkoutTSS({
    required double? avgPower,
    required int? durationSeconds,
    required double? cp,
  }) {
    if (avgPower == null ||
        avgPower <= 0 ||
        durationSeconds == null ||
        durationSeconds <= 0 ||
        cp == null ||
        cp <= 0) {
      return null;
    }
    final intensityFactor = avgPower / cp;
    return (durationSeconds * avgPower * intensityFactor) / (cp * 3600.0) * 100.0;
  }

  /// تصنيف حالة TSB طبقاً للحدود المسماة الموحدة في TsbThresholds
  static TsbStatus classifyTsb(double tsb) {
    if (tsb > TsbThresholds.excessRest) return TsbStatus.excessRest;
    if (tsb >= TsbThresholds.raceReadyMin) return TsbStatus.raceReady;
    if (tsb >= TsbThresholds.neutralMin) return TsbStatus.neutral;
    if (tsb >= TsbThresholds.productiveBuildMin) return TsbStatus.productiveBuild;
    return TsbStatus.overreachRisk;
  }

  /// جلب قيمة CP المعتمدة لتاريخ محدد:
  /// 1) آخر اختبار/قيمة رسمية في cp_values أو calculateCP من cp_tests قبل/في تاريخ التمرين
  /// 2) وإلا التقدير الموجود في db.dart (estimateCPFromSingle أو estimated في cp_values)
  /// 3) وإلا null (يعني TSS = "--" والتمرين لا يدخل في CTL/ATL)
  static Future<double?> getCpForDate(int playerId, Object date) async {
    final dateStr = formatDateKey(date);

    List<Map<String, Object?>> officialRows = const [];
    try {
      officialRows = await DB.q('''
        SELECT date, cp FROM cp_values
        WHERE player_id = ? AND date <= ? AND cp IS NOT NULL AND cp > 0
          AND (method IS NULL OR method != 'estimated')
        ORDER BY date DESC LIMIT 1
      ''', [playerId, dateStr]);
    } catch (_) {}

    List<Map<String, Object?>> testRows = const [];
    try {
      testRows = await DB.q('''
        SELECT date, duration_seconds, avg_power
        FROM cp_tests
        WHERE player_id = ? AND date <= ?
          AND duration_seconds IS NOT NULL AND duration_seconds > 0
          AND avg_power IS NOT NULL AND avg_power > 0
        ORDER BY date DESC, id DESC
      ''', [playerId, dateStr]);
    } catch (_) {}

    double? multiTestCp;
    String? latestTestDate;
    if (testRows.isNotEmpty) {
      latestTestDate = testRows.first['date'] as String?;
      final byDuration = <int, Map<String, dynamic>>{};
      for (final t in testRows) {
        final dur = (t['duration_seconds'] as num).toInt();
        if (!byDuration.containsKey(dur)) {
          byDuration[dur] = {
            'duration_seconds': dur,
            'avg_power': (t['avg_power'] as num).toDouble(),
          };
        }
      }
      if (byDuration.length >= 2) {
        final calc = calculateCP(byDuration.values.toList());
        final cp = calc['cp'];
        if (cp != null && cp > 0) {
          multiTestCp = cp;
        }
      }
    }

    if (officialRows.isNotEmpty) {
      final officialDate = officialRows.first['date'] as String? ?? '';
      final officialCp = (officialRows.first['cp'] as num).toDouble();
      if (multiTestCp == null ||
          latestTestDate == null ||
          officialDate.compareTo(latestTestDate) >= 0) {
        return officialCp;
      }
    }

    if (multiTestCp != null) {
      return multiTestCp;
    }

    // تقدير محفوظ في cp_values (method = 'estimated')
    try {
      final estRows = await DB.q('''
        SELECT cp FROM cp_values
        WHERE player_id = ? AND date <= ? AND cp IS NOT NULL AND cp > 0
        ORDER BY date DESC LIMIT 1
      ''', [playerId, dateStr]);
      if (estRows.isNotEmpty) {
        return (estRows.first['cp'] as num).toDouble();
      }
    } catch (_) {}

    // تقدير من اختبار واحد باستخدام estimateCPFromSingle من db.dart
    if (testRows.isNotEmpty) {
      final latest = testRows.first;
      final dur = (latest['duration_seconds'] as num).toInt();
      final avgP = (latest['avg_power'] as num).toDouble();
      final est = estimateCPFromSingle(avgP, dur);
      if (est > 0) return est;
    }

    return null;
  }

  /// جلب قيمة CP المعتمدة لتاريخ محدد (آخر CP تاريخ اختباره <= تاريخ التمرين من cp_tests)
  static Future<double?> playerCpAt(int playerId, Object date) =>
      getCpForDate(playerId, date);

  /// ── 5. قائمة المدخلات والمؤشرات الكاملة لكل منحنى ──
  /// تحدد المدخلات الفعلية التي تشارك في حساب كل مؤشر لإنشاء شارات الشاشة (Chips)
  static const Map<String, List<String>> curveInvolvedMetrics = {
    'hrv': ['hrv', 'rhr', 'time'],
    'rhr': ['rhr', 'time'],
    'sleep_weight': ['sleep', 'weight', 'time'],
    'sleep': ['sleep', 'time'],
    'weight': ['weight', 'time'],
    'eupnea': ['eupnea', 'rhr', 'time'],
    'watts': ['watts', 'split', 'time'],
    'decoupling': ['decoupling', 'watts', 'hr', 'time'],
    'ef': ['ef', 'watts', 'hr', 'time'],
    'pmc': ['ctl', 'atl', 'tsb', 'watts', 'time'],
    'matrix': ['watts', 'hr', 'zone', 'time'],
    'zone_hours': ['time', 'hr', 'zone'],
    'cp_tests': ['watts', 'time', 'split'],
  };

  /// استرجاع الاسم الكامل غير المختصر لشارة المدخل من AppStrings
  static String metricChipName(AppStrings s, String metricKey) {
    switch (metricKey) {
      case 'watts':
        return s.chipWatts;
      case 'hr':
        return s.chipHR;
      case 'decoupling':
        return s.chipDecoupling;
      case 'time':
        return s.chipTime;
      case 'ef':
        return s.chipEF;
      case 'hrv':
        return s.chipHRV;
      case 'rhr':
        return s.chipRHR;
      case 'sleep':
        return s.chipSleep;
      case 'weight':
        return s.chipWeight;
      case 'eupnea':
        return s.chipEupnea;
      case 'ctl':
        return s.chipCTL;
      case 'atl':
        return s.chipATL;
      case 'tsb':
        return s.chipTSB;
      case 'split':
        return s.chipSplit;
      case 'zone':
        return s.chipZone;
      default:
        return metricKey;
    }
  }
  // ════════════════════════════════════════════════════════════════
  // ── 7. محرك حسابات خط الأساس (Baseline) لـ Matrix Zone والتطور ──
  // ════════════════════════════════════════════════════════════════
  /// حساب خط الأساس لتراكم تمرينات اللاعب في زون ونوع تمرين محدد
  /// وفق قرارات كوتش (12 نوفمبر):
  /// - أقل عدد تمرينات 3، أقصى نافذة 5
  /// - نسبة التقارب 3%، حد التحرك 1%
  /// - يبدأ بعد 3 تمرينات متقاربة
  /// - يتحرك صعوداً أو هبوطاً إذا تقاربت آخر 3-5 تمرينات واختلف متوسطها >= 1%
  static BaselineResult computeBaseline({
    required List<Map<String, Object?>> workouts,
    required String metricKey,
    DateTime? periodStartDate,
    double convergenceRatio = 0.03,
    double movementThreshold = 0.01,
    int minWorkouts = 3,
    int maxWindow = 5,
  }) {
    // 1. استخراج وفرز التمرينات التي تحتوي على القيمة المطلوبة
    final parsed = <_WorkoutMetricPoint>[];
    for (final w in workouts) {
      final dateStr = (w['date'] as String?) ?? '';
      final d = DateTime.tryParse(dateStr);
      if (d == null) continue;

      double? val;
      if (metricKey == 'watts' || metricKey == 'avg_power') {
        val = (w['avg_power'] as num?)?.toDouble();
      } else if (metricKey == 'ef') {
        val = (w['ef'] as num?)?.toDouble();
      } else if (metricKey == 'decoupling') {
        val = (w['decoupling'] as num?)?.toDouble();
      } else if (metricKey.startsWith('eupnea')) {
        val = (w[metricKey] as num?)?.toDouble() ?? (w['eupnea'] as num?)?.toDouble();
      } else {
        val = (w[metricKey] as num?)?.toDouble();
      }

      if (val != null && val > 0) {
        parsed.add(_WorkoutMetricPoint(date: d, value: val));
      }
    }

    parsed.sort((a, b) => a.date.compareTo(b.date));

    if (parsed.length < minWorkouts) {
      return const BaselineResult(
        currentBaseline: null,
        startOfPeriodBaseline: null,
        hasEnoughData: false,
        historyPoints: [],
      );
    }

    // 2. تتبع تطور خط الأساس عبر الزمن
    double? runningBaseline;
    final history = <DateValuePoint>[];
    double? startOfPeriodVal;

    for (int i = 0; i < parsed.length; i++) {
      final curDate = parsed[i].date;

      if (periodStartDate != null &&
          curDate.isBefore(periodStartDate) &&
          runningBaseline != null) {
        startOfPeriodVal = runningBaseline;
      }

      if (i + 1 < minWorkouts) {
        continue;
      }

      if (runningBaseline == null) {
        // فحص تقارب أول 3 تمرينات (أو توسيع النافذة حتى 5)
        bool found = false;
        for (int w = minWorkouts; w <= min(maxWindow, i + 1); w++) {
          final windowValues = parsed.sublist(i - w + 1, i + 1).map((e) => e.value).toList();
          final minV = windowValues.reduce(min);
          final maxV = windowValues.reduce(max);
          final avgV = windowValues.reduce((a, b) => a + b) / w;

          if (avgV > 0 && (maxV - minV) <= avgV * convergenceRatio) {
            runningBaseline = avgV;
            found = true;
            break;
          }
        }
        if (found && runningBaseline != null) {
          history.add(DateValuePoint(date: curDate, value: runningBaseline));
        }
      } else {
        // خط الأساس موجود: هل آخر 3-5 تمرينات متقاربة وتختلف عن الحالي بنسبة >= حد التحرك؟
        for (int w = minWorkouts; w <= min(maxWindow, i + 1); w++) {
          final windowValues = parsed.sublist(i - w + 1, i + 1).map((e) => e.value).toList();
          final minV = windowValues.reduce(min);
          final maxV = windowValues.reduce(max);
          final avgV = windowValues.reduce((a, b) => a + b) / w;

          if (avgV > 0 && (maxV - minV) <= avgV * convergenceRatio) {
            final currentBase = runningBaseline!;
            final diffRatio = (avgV - currentBase).abs() / currentBase;
            if (diffRatio >= movementThreshold) {
              runningBaseline = avgV;
              history.add(DateValuePoint(date: curDate, value: runningBaseline));
              break;
            }
          }
        }
      }

      if (periodStartDate != null &&
          (curDate.isBefore(periodStartDate) || curDate.isAtSameMomentAs(periodStartDate)) &&
          runningBaseline != null) {
        startOfPeriodVal = runningBaseline;
      }
    }

    if (periodStartDate == null) {
      startOfPeriodVal = runningBaseline;
    }

    return BaselineResult(
      currentBaseline: runningBaseline,
      startOfPeriodBaseline: startOfPeriodVal,
      hasEnoughData: runningBaseline != null,
      historyPoints: history,
    );
  }

  // ════════════════════════════════════════════════════════════════
  // ── 8. محرك حسابات Matrix Zone ومنحنى القدرة (Capacity Curve) ──
  // ════════════════════════════════════════════════════════════════
  static const double kMaxZoneScore = 15.0;
  static const double kMinBarWidth = 14.0;
  static const double kMaxBarWidth = 32.0;
  static const double kCapacityScoreFactor = 2.5;

  static const List<MatrixZoneIndicatorConfig> defaultMatrixIndicators = [
    MatrixZoneIndicatorConfig(key: 'watts', weight: 40.0, direction: 'up', sortOrder: 0),
    MatrixZoneIndicatorConfig(key: 'ef', weight: 25.0, direction: 'up', sortOrder: 1),
    MatrixZoneIndicatorConfig(key: 'time', weight: 20.0, direction: 'up', sortOrder: 2),
    MatrixZoneIndicatorConfig(key: 'decoupling', weight: 15.0, direction: 'down', sortOrder: 3),
  ];

  /// حساب مقاييس Matrix Zone لكل الزونات للاعب معين في فترة ونوع تمرين محددين
  static MatrixZoneAthleteResult computeMatrixZoneForAthlete({
    required int playerId,
    required String athleteName,
    required String workoutKind,
    required List<Map<String, Object?>> allAthleteLogs,
    required DateTime periodStart,
    required DateTime periodEnd,
    List<MatrixZoneIndicatorConfig> indicatorConfigs = defaultMatrixIndicators,
  }) {
    final periodDurationDays = periodEnd.difference(periodStart).inDays + 1;
    final prevPeriodStart = periodStart.subtract(Duration(days: periodDurationDays));
    final prevPeriodEnd = periodStart.subtract(const Duration(days: 1));

    // تصفية تمرينات نوع التمرين المحدد (قاعدة عدم التداخل)
    final kindLogs = allAthleteLogs.where((l) {
      final k = (l['kind'] as String?)?.trim();
      return k == null || k.isEmpty || k.toLowerCase() == workoutKind.toLowerCase();
    }).toList();

    // تقسيم التمرينات حسب الزون
    final details = <String, MatrixZoneDetail>{};
    final orderedZones = HeartRateZones.orderedZones; // Z1..VO2 max

    // الأساس التصاعدي لمنحنى القدرة عبر المناطق
    final baseCapacityValues = {
      'Z1': 100.0,
      'Z2': 145.0,
      'Z3': 195.0,
      'Z4': 245.0,
      'Threshold': 295.0,
      'Z5': 345.0,
      'VO2 max': 395.0,
    };

    for (int zi = 0; zi < orderedZones.length; zi++) {
      final zoneKey = orderedZones[zi];
      final zoneLogs = kindLogs.where((l) {
        final z = (l['zone'] as String?) ?? '';
        return HeartRateZones.normalizeZoneKey(z) == zoneKey;
      }).toList();

      final currentPeriodLogs = zoneLogs.where((l) {
        final dStr = (l['date'] as String?) ?? '';
        final d = DateTime.tryParse(dStr);
        if (d == null) return false;
        return (d.isAfter(periodStart) || d.isAtSameMomentAs(periodStart)) &&
            (d.isBefore(periodEnd) || d.isAtSameMomentAs(periodEnd));
      }).toList();

      final prevPeriodLogs = zoneLogs.where((l) {
        final dStr = (l['date'] as String?) ?? '';
        final d = DateTime.tryParse(dStr);
        if (d == null) return false;
        return (d.isAfter(prevPeriodStart) || d.isAtSameMomentAs(prevPeriodStart)) &&
            (d.isBefore(prevPeriodEnd) || d.isAtSameMomentAs(prevPeriodEnd));
      }).toList();

      // 1. طول الشريط = أفضل متوسط واط حققه اللاعب في الزون ده خلال الفترة
      double? bestWatts;
      final wattsList = currentPeriodLogs
          .map((l) => (l['avg_power'] as num?)?.toDouble())
          .whereType<double>()
          .where((w) => w > 0)
          .toList();
      if (wattsList.isNotEmpty) {
        bestWatts = wattsList.reduce(max);
      }

      // 2. حساب خطوط الأساس
      final wattsBaseline = computeBaseline(
        workouts: zoneLogs,
        metricKey: 'watts',
        periodStartDate: periodStart,
      );
      final efBaseline = computeBaseline(
        workouts: zoneLogs,
        metricKey: 'ef',
        periodStartDate: periodStart,
      );
      final decouplingBaseline = computeBaseline(
        workouts: zoneLogs,
        metricKey: 'decoupling',
        periodStartDate: periodStart,
      );

      // 3. حساب درجات المؤشرات الأربعة
      final scoresMap = <String, MatrixZoneMetricScore>{};
      double weightedScoreSum = 0.0;
      double availableWeightSum = 0.0;

      for (final cfg in indicatorConfigs) {
        double? metricScore;
        double rawVal = 0.0;
        double? baseVal;
        bool hasData = false;

        if (cfg.key == 'watts') {
          baseVal = wattsBaseline.startOfPeriodBaseline;
          if (wattsList.isNotEmpty && baseVal != null && baseVal > 0) {
            rawVal = wattsList.reduce((a, b) => a + b) / wattsList.length;
            metricScore = ((rawVal / baseVal) - 1.0) * 100.0;
            hasData = true;
          }
        } else if (cfg.key == 'ef') {
          baseVal = efBaseline.startOfPeriodBaseline;
          final efList = currentPeriodLogs
              .map((l) => (l['ef'] as num?)?.toDouble())
              .whereType<double>()
              .where((v) => v > 0)
              .toList();
          if (efList.isNotEmpty && baseVal != null && baseVal > 0) {
            rawVal = efList.reduce((a, b) => a + b) / efList.length;
            metricScore = ((rawVal / baseVal) - 1.0) * 100.0;
            hasData = true;
          }
        } else if (cfg.key == 'time') {
          // الزمن (الساعات المتراكمة) يتقارن بالفترة السابقة بنفس الطول
          final curSeconds = currentPeriodLogs.fold<int>(
            0,
            (sum, l) => sum + ((l['duration_seconds'] as num?)?.toInt() ?? 0),
          );
          final prevSeconds = prevPeriodLogs.fold<int>(
            0,
            (sum, l) => sum + ((l['duration_seconds'] as num?)?.toInt() ?? 0),
          );
          final curHours = curSeconds / 3600.0;
          final prevHours = prevSeconds / 3600.0;
          rawVal = curHours;
          baseVal = prevHours;

          if (curHours > 0 || prevHours > 0) {
            hasData = true;
            if (prevHours > 0) {
              metricScore = ((curHours / prevHours) - 1.0) * 100.0;
            } else {
              metricScore = kMaxZoneScore;
            }
          }
        } else if (cfg.key == 'decoupling') {
          // Decoupling: الأقل أحسن (أساس البداية - متوسط الفترة)
          baseVal = decouplingBaseline.startOfPeriodBaseline;
          final decList = currentPeriodLogs
              .map((l) => (l['decoupling'] as num?)?.toDouble())
              .whereType<double>()
              .toList();
          if (decList.isNotEmpty && baseVal != null) {
            rawVal = decList.reduce((a, b) => a + b) / decList.length;
            metricScore = (baseVal - rawVal); // كلما نزل الـ Decoupling زادت الدرجة
            hasData = true;
          }
        } else {
          // مؤشر مخصص
          final customList = currentPeriodLogs
              .map((l) => (l[cfg.key] as num?)?.toDouble())
              .whereType<double>()
              .toList();
          final prevCustomList = prevPeriodLogs
              .map((l) => (l[cfg.key] as num?)?.toDouble())
              .whereType<double>()
              .toList();
          if (customList.isNotEmpty) {
            rawVal = customList.reduce((a, b) => a + b) / customList.length;
            hasData = true;
            if (prevCustomList.isNotEmpty) {
              baseVal = prevCustomList.reduce((a, b) => a + b) / prevCustomList.length;
              if (baseVal > 0) {
                final ratio = ((rawVal / baseVal) - 1.0) * 100.0;
                metricScore = cfg.isHigherBetter ? ratio : -ratio;
              }
            }
          }
        }

        if (metricScore != null) {
          metricScore = metricScore.clamp(-kMaxZoneScore, kMaxZoneScore);
          weightedScoreSum += (cfg.weight * metricScore);
          availableWeightSum += cfg.weight;
        }

        scoresMap[cfg.key] = MatrixZoneMetricScore(
          indicatorKey: cfg.key,
          rawValue: rawVal,
          baselineValue: baseVal,
          score: metricScore,
          hasData: hasData,
        );
      }

      final hasEnoughData = availableWeightSum > 0 && bestWatts != null;
      double? zoneScore;
      if (availableWeightSum > 0) {
        zoneScore = (weightedScoreSum / availableWeightSum).clamp(-kMaxZoneScore, kMaxZoneScore);
      }

      // عرض الشريط: دالة متزايدة من درجة الزون (14.0 إلى 32.0)
      final barWidth = zoneScore != null
          ? (23.0 + (zoneScore / kMaxZoneScore) * 9.0).clamp(kMinBarWidth, kMaxBarWidth)
          : kMinBarWidth;

      // ارتفاع منحنى القدرة عند الزون: دالة متناقصة من درجة الزون (أوطى = قدرة أحسن)
      double? capacityCurveVal;
      if (zoneScore != null) {
        final baseVal = baseCapacityValues[zoneKey] ?? 200.0;
        capacityCurveVal = baseVal - (zoneScore * kCapacityScoreFactor);
      }

      details[zoneKey] = MatrixZoneDetail(
        zoneKey: zoneKey,
        bestWatts: bestWatts,
        zoneScore: zoneScore,
        barWidth: barWidth,
        capacityCurveValue: capacityCurveVal,
        startBaselineWatts: wattsBaseline.startOfPeriodBaseline,
        currentBaselineWatts: wattsBaseline.currentBaseline,
        metricScores: scoresMap,
        hasEnoughData: hasEnoughData,
      );
    }

    // حساب موقع علامات LT1 و LT2
    final z2Detail = details['Z2'];
    final thrDetail = details['Threshold'];

    Point<double>? lt1;
    if (z2Detail?.capacityCurveValue != null) {
      final z2Score = z2Detail?.zoneScore ?? 0.0;
      lt1 = Point<double>(1.5 + (z2Score / kMaxZoneScore) * 0.3, z2Detail!.capacityCurveValue!);
    }

    Point<double>? lt2;
    if (thrDetail?.capacityCurveValue != null) {
      final thrScore = thrDetail?.zoneScore ?? 0.0;
      lt2 = Point<double>(4.0 + (thrScore / kMaxZoneScore) * 0.3, thrDetail!.capacityCurveValue!);
    }

    return MatrixZoneAthleteResult(
      playerId: playerId,
      athleteName: athleteName,
      workoutKind: workoutKind,
      detailsByZone: details,
      lt1Point: lt1,
      lt2Point: lt2,
      hasData: details.values.any((d) => d.hasEnoughData),
    );
  }

  /// تحميل إعدادات المؤشرات من جدول matrix_zone_config
  static Future<List<MatrixZoneIndicatorConfig>> loadMatrixZoneConfig() async {
    try {
      final database = await DB.db;
      final rows = await database.rawQuery(
        'SELECT * FROM matrix_zone_config ORDER BY sort_order ASC',
      );
      if (rows.isNotEmpty) {
        return rows.map((r) {
          return MatrixZoneIndicatorConfig(
            key: r['indicator_key'] as String,
            weight: (r['weight'] as num).toDouble(),
            direction: (r['direction'] as String?) ?? 'up',
            sortOrder: (r['sort_order'] as num?)?.toInt() ?? 0,
          );
        }).toList();
      }
    } catch (_) {}
    return defaultMatrixIndicators;
  }

  /// حفظ إعدادات المؤشرات في جدول matrix_zone_config
  static Future<void> saveMatrixZoneConfig(List<MatrixZoneIndicatorConfig> configs) async {
    final database = await DB.db;
    await database.transaction((txn) async {
      await txn.delete('matrix_zone_config');
      for (int i = 0; i < configs.length; i++) {
        final c = configs[i];
        await txn.insert('matrix_zone_config', {
          'indicator_key': c.key,
          'weight': c.weight,
          'direction': c.direction,
          'sort_order': i,
        });
      }
    });
  }

}



/// نتيجة مزامنة جدول الكاش daily_load للاعب
class DailyLoadSyncResult {
  final List<DailyLoadEntry> allEntries;
  final Set<String> missingCpDates;
  final int missingCpWorkoutsCount;
  final String? recomputedFromDate;

  const DailyLoadSyncResult({
    required this.allEntries,
    required this.missingCpDates,
    required this.missingCpWorkoutsCount,
    this.recomputedFromDate,
  });
}

/// إدارة الكاش المرحلي للأحمال اليومية (daily_load) وإعادة الحساب من أقدم تاريخ معدل لقدام
class ProgressLoadCache {
  static Future<void> ensureTable() async {
    final database = await DB.db;
    await database.execute('''
      CREATE TABLE IF NOT EXISTS daily_load(
        player_id INTEGER NOT NULL,
        date TEXT NOT NULL,
        tss REAL,
        ctl REAL NOT NULL,
        atl REAL NOT NULL,
        tsb REAL NOT NULL,
        PRIMARY KEY(player_id, date)
      )
    ''');
  }

  /// مسح الكاش للاعب (أو من تاريخ معين) لفرض إعادة الحساب عند التعديل
  static Future<void> invalidateFrom(int playerId, {String? fromDate}) async {
    await ensureTable();
    final database = await DB.db;
    if (fromDate == null) {
      await database.delete('daily_load', where: 'player_id = ?', whereArgs: [playerId]);
    } else {
      await database.delete(
        'daily_load',
        where: 'player_id = ? AND date >= ?',
        whereArgs: [playerId, fromDate],
      );
    }
  }

  /// مزامنة جدول daily_load للاعب من أقدم تاريخ تغيّر فيه الـ TSS (أو CP) للأمام فقط
  static Future<DailyLoadSyncResult> syncForPlayer(
    int playerId, {
    String? forceFromDate,
    DateTime? upToDate,
  }) async {
    await ensureTable();
    final database = await DB.db;

    final logRows = await database.rawQuery('''
      SELECT date, avg_power, duration_seconds
      FROM logs
      WHERE player_id = ? AND avg_power IS NOT NULL AND avg_power > 0
        AND duration_seconds IS NOT NULL AND duration_seconds > 0
      ORDER BY date ASC, idx ASC
    ''', [playerId]);

    final validDailyTss = <String, double>{};
    final missingCpDates = <String>{};
    int missingCpCount = 0;

    // كاش محلي لقيمة CP لكل تاريخ تمرين
    final cpByDateCache = <String, double?>{};
    for (final row in logRows) {
      final dateStr = ProgressCalcs.formatDateKey(row['date'] ?? '');
      if (dateStr.isEmpty) continue;

      final double? cp;
      if (cpByDateCache.containsKey(dateStr)) {
        cp = cpByDateCache[dateStr];
      } else {
        cp = await ProgressCalcs.getCpForDate(playerId, dateStr);
        cpByDateCache[dateStr] = cp;
      }

      if (cp == null || cp <= 0) {
        missingCpDates.add(dateStr);
        missingCpCount++;
        continue;
      }

      final watts = (row['avg_power'] as num).toDouble();
      final dur = (row['duration_seconds'] as num).toInt();
      final tss = ProgressCalcs.calculateWorkoutTSS(
        avgPower: watts,
        durationSeconds: dur,
        cp: cp,
      );
      if (tss != null) {
        validDailyTss[dateStr] = (validDailyTss[dateStr] ?? 0.0) + tss;
      }
    }

    if (validDailyTss.isEmpty) {
      await database.delete(
        'daily_load',
        where: 'player_id = ?',
        whereArgs: [playerId],
      );
      return DailyLoadSyncResult(
        allEntries: const [],
        missingCpDates: missingCpDates,
        missingCpWorkoutsCount: missingCpCount,
      );
    }

    final sortedDates = validDailyTss.keys.toList()..sort();
    final firstDate = DateTime.parse(sortedDates.first);
    final lastLogDate = DateTime.parse(sortedDates.last);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final targetEnd = upToDate != null
        ? DateTime(upToDate.year, upToDate.month, upToDate.day)
        : today;
    final endDate = targetEnd.isAfter(lastLogDate) ? targetEnd : lastLogDate;

    final existingRows = await database.rawQuery(
      'SELECT * FROM daily_load WHERE player_id = ? ORDER BY date ASC',
      [playerId],
    );
    final existingByDate = <String, DailyLoadEntry>{
      for (final r in existingRows)
        (r['date'] as String): DailyLoadEntry.fromMap(r),
    };

    String? dirtyStartDate;
    final firstDateStr = dstr(firstDate);

    // إذا كان هناك تواريخ في الكاش أقدم من أول تمرين صالح حالياً، نحذفها ونعيد من البداية
    if (existingRows.isNotEmpty) {
      final cachedFirstDate = existingRows.first['date'] as String;
      if (cachedFirstDate.compareTo(firstDateStr) < 0) {
        await database.delete(
          'daily_load',
          where: 'player_id = ? AND date < ?',
          whereArgs: [playerId, firstDateStr],
        );
        dirtyStartDate = firstDateStr;
      }
    }

    if (dirtyStartDate == null) {
      for (var cur = firstDate;
          !cur.isAfter(endDate);
          cur = cur.add(const Duration(days: 1))) {
        final key = dstr(cur);
        final expectedTss = validDailyTss[key] ?? 0.0;
        final cached = existingByDate[key];
        if (cached == null ||
            cached.tss == null ||
            (cached.tss! - expectedTss).abs() > 1e-4) {
          dirtyStartDate = key;
          break;
        }
      }
    }

    if (forceFromDate != null) {
      final normForce = ProgressCalcs.formatDateKey(forceFromDate);
      final clampedForce =
          normForce.compareTo(firstDateStr) < 0 ? firstDateStr : normForce;
      if (dirtyStartDate == null ||
          clampedForce.compareTo(dirtyStartDate) < 0) {
        dirtyStartDate = clampedForce;
      }
    }

    if (dirtyStartDate != null) {
      final prevRows = await database.rawQuery('''
        SELECT ctl, atl FROM daily_load
        WHERE player_id = ? AND date < ?
        ORDER BY date DESC LIMIT 1
      ''', [playerId, dirtyStartDate]);

      double ctlPrev = prevRows.isNotEmpty
          ? ((prevRows.first['ctl'] as num?)?.toDouble() ?? 0.0)
          : 0.0;
      double atlPrev = prevRows.isNotEmpty
          ? ((prevRows.first['atl'] as num?)?.toDouble() ?? 0.0)
          : 0.0;

      final kCtl = 1.0 - exp(-1.0 / 42.0);
      final kAtl = 1.0 - exp(-1.0 / 7.0);
      final startLoop = DateTime.parse(dirtyStartDate);

      await database.transaction((txn) async {
        await txn.delete(
          'daily_load',
          where: 'player_id = ? AND date >= ?',
          whereArgs: [playerId, dirtyStartDate],
        );

        for (var cur = startLoop;
            !cur.isAfter(endDate);
            cur = cur.add(const Duration(days: 1))) {
          final key = dstr(cur);
          final tssToday = validDailyTss[key] ?? 0.0;
          final tsbToday = ctlPrev - atlPrev;
          final ctlToday = ctlPrev + (tssToday - ctlPrev) * kCtl;
          final atlToday = atlPrev + (tssToday - atlPrev) * kAtl;

          await txn.insert('daily_load', {
            'player_id': playerId,
            'date': key,
            'tss': tssToday,
            'ctl': ctlToday,
            'atl': atlToday,
            'tsb': tsbToday,
          });

          ctlPrev = ctlToday;
          atlPrev = atlToday;
        }
      });
    }

    final finalRows = await database.rawQuery(
      'SELECT * FROM daily_load WHERE player_id = ? ORDER BY date ASC',
      [playerId],
    );

    return DailyLoadSyncResult(
      allEntries: finalRows.map(DailyLoadEntry.fromMap).toList(),
      missingCpDates: missingCpDates,
      missingCpWorkoutsCount: missingCpCount,
      recomputedFromDate: dirtyStartDate,
    );
  }


}

class _WorkoutMetricPoint {
  final DateTime date;
  final double value;

  const _WorkoutMetricPoint({required this.date, required this.value});
}

/// نتيجة حساب خط الأساس (Baseline)
class BaselineResult {
  final double? currentBaseline;
  final double? startOfPeriodBaseline;
  final bool hasEnoughData;
  final List<DateValuePoint> historyPoints;

  const BaselineResult({
    this.currentBaseline,
    this.startOfPeriodBaseline,
    required this.hasEnoughData,
    this.historyPoints = const [],
  });
}

/// تهيئة إعداد المؤشر لـ Matrix Zone
class MatrixZoneIndicatorConfig {
  final String key;
  final double weight;
  final String direction;
  final int sortOrder;

  const MatrixZoneIndicatorConfig({
    required this.key,
    required this.weight,
    this.direction = 'up',
    this.sortOrder = 0,
  });

  bool get isHigherBetter => direction == 'up';
}

/// درجة مؤشر واحد في زون معين
class MatrixZoneMetricScore {
  final String indicatorKey;
  final double rawValue;
  final double? baselineValue;
  final double? score;
  final bool hasData;

  const MatrixZoneMetricScore({
    required this.indicatorKey,
    required this.rawValue,
    this.baselineValue,
    this.score,
    required this.hasData,
  });
}

/// تفاصيل منطقة تدريبية واحدة للاعب في Matrix Zone
class MatrixZoneDetail {
  final String zoneKey;
  final double? bestWatts;
  final double? zoneScore;
  final double barWidth;
  final double? capacityCurveValue;
  final double? startBaselineWatts;
  final double? currentBaselineWatts;
  final Map<String, MatrixZoneMetricScore> metricScores;
  final bool hasEnoughData;

  const MatrixZoneDetail({
    required this.zoneKey,
    this.bestWatts,
    this.zoneScore,
    required this.barWidth,
    this.capacityCurveValue,
    this.startBaselineWatts,
    this.currentBaselineWatts,
    this.metricScores = const {},
    required this.hasEnoughData,
  });
}

/// نتيجة حساب Matrix Zone الكاملة للاعب
class MatrixZoneAthleteResult {
  final int playerId;
  final String athleteName;
  final String workoutKind;
  final Map<String, MatrixZoneDetail> detailsByZone;
  final Point<double>? lt1Point;
  final Point<double>? lt2Point;
  final bool hasData;

  const MatrixZoneAthleteResult({
    required this.playerId,
    required this.athleteName,
    required this.workoutKind,
    required this.detailsByZone,
    this.lt1Point,
    this.lt2Point,
    required this.hasData,
  });
}
