import 'dart:math';
import 'heart_rate_zones.dart';

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
      final dateKey = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      final tss = (item['tss'] as num?)?.toDouble() ?? 0.0;
      dayTss[dateKey] = (dayTss[dateKey] ?? 0.0) + tss;
    }

    final sortedDates = dayTss.keys.toList()..sort();
    final firstDate = DateTime.parse(sortedDates.first);
    final lastDate = DateTime.parse(sortedDates.last);

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
      final key = '${cur.year}-${cur.month.toString().padLeft(2, '0')}-${cur.day.toString().padLeft(2, '0')}';
      final tss = dayTss[key] ?? 0.0;

      ctl = ctl + (tss - ctl) * kCtl;
      atl = atl + (tss - atl) * kAtl;
      final tsb = ctl - atl;

      ctlPoints.add(DateValuePoint(date: cur, value: double.parse(ctl.toStringAsFixed(1))));
      atlPoints.add(DateValuePoint(date: cur, value: double.parse(atl.toStringAsFixed(1))));
      tsbPoints.add(DateValuePoint(date: cur, value: double.parse(tsb.toStringAsFixed(1))));
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

  /// ── 5. قائمة المدخلات والمؤشرات الكاملة لكل منحنى ──
  /// تحدد المدخلات الفعلية التي تشارك في حساب كل مؤشر لإنشاء شارات الشاشة (Chips)
  static const Map<String, List<String>> curveInvolvedMetrics = {
    'hrv': ['hrv', 'rhr', 'time'],
    'rhr': ['rhr', 'time'],
    'sleep_weight': ['sleep', 'weight', 'time'],
    'eupnea': ['eupnea', 'rhr', 'time'],
    'watts': ['watts', 'split', 'time'],
    'decoupling': ['decoupling', 'watts', 'hr', 'time'],
    'ef': ['ef', 'watts', 'hr', 'time'],
    'pmc': ['ctl', 'atl', 'tsb', 'watts', 'time'],
  };
}
