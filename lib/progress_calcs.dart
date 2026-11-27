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

/// قراءة واحدة من قراءات التفكك القلبي W-HR-T
class DecouplingReading {
  final double watts;
  final double hr;
  final double timeMinutes;

  const DecouplingReading({
    required this.watts,
    required this.hr,
    required this.timeMinutes,
  });

  /// حساب EF اللحظي لهذه القراءة = واط ÷ نبض
  double get ef => hr > 0 ? (watts / hr) : 0.0;

  @override
  String toString() =>
      'W${watts.round()}-HR${hr.round()}-T${timeMinutes.toStringAsFixed(1)}';
}

/// نتيجة تحليل نص قراءات Decoupling
class DecouplingParseResult {
  final List<DecouplingReading> readings;
  final int ignoredCount;

  const DecouplingParseResult({
    required this.readings,
    required this.ignoredCount,
  });
}

/// مستوى سيطرة التفكك القلبي
enum DecouplingControlLevel {
  excellent, // < 5% سيطرة ممتازة
  moderate, // 5% - 10% متوسط
  high, // > 10% انحراف مرتفع
  notEligible, // غير مؤهل للتفسير (ليست Z1/Z2 أو أقل من 60 دقيقة)
}

/// نتيجة حساب Decoupling الكامل للتمرين
class DecouplingCalculationResult {
  final double? decouplingPercent;
  final double? efHalf1;
  final double? efHalf2;
  final List<DecouplingReading> half1Readings;
  final List<DecouplingReading> half2Readings;
  final List<DecouplingReading> allReadings;
  final int ignoredCount;
  final bool hasEnoughReadings;
  final String? errorMessage;
  final bool isEligibleForInterpretation;
  final DecouplingControlLevel controlLevel;
  final bool hasFewerReadingsThanRecommended;

  const DecouplingCalculationResult({
    this.decouplingPercent,
    this.efHalf1,
    this.efHalf2,
    this.half1Readings = const [],
    this.half2Readings = const [],
    this.allReadings = const [],
    this.ignoredCount = 0,
    required this.hasEnoughReadings,
    this.errorMessage,
    required this.isEligibleForInterpretation,
    required this.controlLevel,
    this.hasFewerReadingsThanRecommended = false,
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

  /// ── 3.5 تحليل وحساب قراءات التفكك القلبي الهوائي (Decoupling) ──
  ///
  /// تحليل نص القراءات بصيغة: W200-HR180-T5, W205-HR183-T10
  /// مفصولة بفواصل، غير حساسة لحالة الأحرف (case-insensitive)
  /// كل قراءة يجب أن تشتمل على القيم الثلاث: W (واط)، HR (نبض)، T (الزمن بالدقائق)
  /// أي قراءة ناقصة أو بتنسيق خاطئ يتم تجاهلها وزيادة ignoredCount
  static DecouplingParseResult parseDecouplingReadings(String rawText) {
    if (rawText.trim().isEmpty) {
      return const DecouplingParseResult(readings: [], ignoredCount: 0);
    }

    final chunks = rawText.split(RegExp(r'[,;\n]'));
    final readings = <DecouplingReading>[];
    int ignoredCount = 0;

    final wReg = RegExp(r'W\s*(\d+(?:\.\d+)?)', caseSensitive: false);
    final hrReg = RegExp(r'HR\s*(\d+(?:\.\d+)?)', caseSensitive: false);
    final tReg = RegExp(r'T\s*(\d+(?:\.\d+)?)', caseSensitive: false);

    for (final rawChunk in chunks) {
      final chunk = rawChunk.trim();
      if (chunk.isEmpty) continue;

      final wMatch = wReg.firstMatch(chunk);
      final hrMatch = hrReg.firstMatch(chunk);
      final tMatch = tReg.firstMatch(chunk);

      if (wMatch != null && hrMatch != null && tMatch != null) {
        final w = double.tryParse(wMatch.group(1)!);
        final hr = double.tryParse(hrMatch.group(1)!);
        final t = double.tryParse(tMatch.group(1)!);

        if (w != null && hr != null && t != null && w > 0 && hr > 0 && t >= 0) {
          readings.add(DecouplingReading(watts: w, hr: hr, timeMinutes: t));
        } else {
          ignoredCount++;
        }
      } else {
        ignoredCount++;
      }
    }

    readings.sort((a, b) => a.timeMinutes.compareTo(b.timeMinutes));

    return DecouplingParseResult(
      readings: readings,
      ignoredCount: ignoredCount,
    );
  }

  /// حساب Decoupling % وفق مواصفات كوتش:
  /// - تقسيم التمرين لنصفين بالزمن الفعلي (T <= D/2 و T > D/2)
  /// - EF لكل نصف = متوسط الواط ÷ متوسط النبض
  /// - Decoupling % = ((EF1 - EF2) / EF1) * 100
  /// - شرط قراءة واحدة على الأقل في كل نصف
  /// - التفسير: < 5% سيطرة ممتازة، 5-10% متوسط، > 10% انحراف مرتفع
  /// - غير مؤهل للتفسير إذا لم يكن Z1/Z2 أو المدة < 60 دقيقة
  static DecouplingCalculationResult calculateDecoupling({
    required String rawReadingsText,
    required double durationMinutes,
    String? zoneKey,
  }) {
    final parseResult = parseDecouplingReadings(rawReadingsText);
    final readings = parseResult.readings;
    final ignored = parseResult.ignoredCount;

    if (readings.isEmpty) {
      return DecouplingCalculationResult(
        hasEnoughReadings: false,
        errorMessage: 'مفيش قراءات كفاية في النصفين',
        ignoredCount: ignored,
        isEligibleForInterpretation: false,
        controlLevel: DecouplingControlLevel.notEligible,
      );
    }

    final effectiveD = durationMinutes > 0
        ? durationMinutes
        : readings.map((r) => r.timeMinutes).reduce(max);

    final halfTime = effectiveD / 2.0;
    final half1 = readings.where((r) => r.timeMinutes <= halfTime).toList();
    final half2 = readings.where((r) => r.timeMinutes > halfTime).toList();

    if (half1.isEmpty || half2.isEmpty) {
      return DecouplingCalculationResult(
        hasEnoughReadings: false,
        errorMessage: 'مفيش قراءات كفاية في النصفين',
        half1Readings: half1,
        half2Readings: half2,
        allReadings: readings,
        ignoredCount: ignored,
        isEligibleForInterpretation: false,
        controlLevel: DecouplingControlLevel.notEligible,
      );
    }

    final avgW1 =
        half1.map((r) => r.watts).reduce((a, b) => a + b) / half1.length;
    final avgHr1 =
        half1.map((r) => r.hr).reduce((a, b) => a + b) / half1.length;
    final ef1 = avgHr1 > 0 ? (avgW1 / avgHr1) : 0.0;

    final avgW2 =
        half2.map((r) => r.watts).reduce((a, b) => a + b) / half2.length;
    final avgHr2 =
        half2.map((r) => r.hr).reduce((a, b) => a + b) / half2.length;
    final ef2 = avgHr2 > 0 ? (avgW2 / avgHr2) : 0.0;

    double decouplingPct = 0.0;
    if (ef1 > 0) {
      decouplingPct = ((ef1 - ef2) / ef1) * 100.0;
    }

    final cleanZone =
        zoneKey != null ? HeartRateZones.normalizeZoneKey(zoneKey) : null;
    final isEligible =
        (effectiveD >= 60.0) && (cleanZone == 'Z1' || cleanZone == 'Z2');

    final DecouplingControlLevel controlLevel;
    if (!isEligible) {
      controlLevel = DecouplingControlLevel.notEligible;
    } else if (decouplingPct < 5.0) {
      controlLevel = DecouplingControlLevel.excellent;
    } else if (decouplingPct <= 10.0) {
      controlLevel = DecouplingControlLevel.moderate;
    } else {
      controlLevel = DecouplingControlLevel.high;
    }

    final double expectedIntervalMinutes =
        effectiveD < 10 ? 1.0 : (effectiveD <= 40 ? 2.0 : 5.0);
    final expectedCount = (effectiveD / expectedIntervalMinutes).floor();
    final hasFewer = readings.length < (expectedCount * 0.7);

    return DecouplingCalculationResult(
      decouplingPercent: decouplingPct,
      efHalf1: ef1,
      efHalf2: ef2,
      half1Readings: half1,
      half2Readings: half2,
      allReadings: readings,
      ignoredCount: ignored,
      hasEnoughReadings: true,
      isEligibleForInterpretation: isEligible,
      controlLevel: controlLevel,
      hasFewerReadingsThanRecommended: hasFewer,
    );
  }

  /// ── 4. حسابات الـ PMC (Performance Management Chart: CTL, ATL, TSB) ──
  static Map<String, dynamic> calculatePMC({
    required List<Map<String, dynamic>>
        dailyTssList, // [{date: DateTime, tss: double}]
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
      final effMhr = pMhr > 0
          ? pMhr
          : (rMhr > 0 ? rMhr : (hMhr > 0 ? hMhr : (defaultMhr ?? 0)));

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
    return (durationSeconds * avgPower * intensityFactor) /
        (cp * 3600.0) *
        100.0;
  }

  /// تصنيف حالة TSB طبقاً للحدود المسماة الموحدة في TsbThresholds
  static TsbStatus classifyTsb(double tsb) {
    if (tsb > TsbThresholds.excessRest) return TsbStatus.excessRest;
    if (tsb >= TsbThresholds.raceReadyMin) return TsbStatus.raceReady;
    if (tsb >= TsbThresholds.neutralMin) return TsbStatus.neutral;
    if (tsb >= TsbThresholds.productiveBuildMin)
      return TsbStatus.productiveBuild;
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
    'cp_tests': ['cp', 'w_prime', 'bi', 'time', 'watts'],
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
      case 'cp':
        return s.chipCP;
      case 'w_prime':
        return s.chipWPrime;
      case 'bi':
        return s.chipBalanceIndex;
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
        val = (w[metricKey] as num?)?.toDouble() ??
            (w['eupnea'] as num?)?.toDouble();
      } else {
        val = (w[metricKey] as num?)?.toDouble();
      }

      if (val != null && (metricKey == 'decoupling' ? val >= 0 : val > 0)) {
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
          final windowValues =
              parsed.sublist(i - w + 1, i + 1).map((e) => e.value).toList();
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
          final windowValues =
              parsed.sublist(i - w + 1, i + 1).map((e) => e.value).toList();
          final minV = windowValues.reduce(min);
          final maxV = windowValues.reduce(max);
          final avgV = windowValues.reduce((a, b) => a + b) / w;

          if (avgV > 0 && (maxV - minV) <= avgV * convergenceRatio) {
            final currentBase = runningBaseline!;
            final diffRatio = (avgV - currentBase).abs() / currentBase;
            if (diffRatio >= movementThreshold) {
              runningBaseline = avgV;
              history
                  .add(DateValuePoint(date: curDate, value: runningBaseline));
              break;
            }
          }
        }
      }

      if (periodStartDate != null &&
          curDate.isBefore(periodStartDate) &&
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

  /// جلب إعدادات خط الأساس من جدول progress_baseline_config مع القيم الافتراضية
  static Future<Map<String, double>> loadBaselineConfig() async {
    const defaults = {
      'min_workouts': 3.0,
      'max_window': 5.0,
      'convergence_ratio': 0.03,
      'movement_threshold': 0.01,
    };
    try {
      final rows =
          await DB.q('SELECT key, value FROM progress_baseline_config');
      final result = Map<String, double>.from(defaults);
      for (final r in rows) {
        final k = r['key'] as String?;
        final v = (r['value'] as num?)?.toDouble();
        if (k != null && v != null) {
          result[k] = v;
        }
      }
      return result;
    } catch (_) {
      return defaults;
    }
  }

  // ════════════════════════════════════════════════════════════════
  // ── 8. محرك حسابات Matrix Zone ومنحنى القدرة (Capacity Curve) ──
  // ════════════════════════════════════════════════════════════════
  static const double kMaxZoneScore = 15.0;
  static const double kMinBarWidth = 14.0;
  static const double kMaxBarWidth = 32.0;
  static const double kCapacityScoreFactor = 2.5;

  static const List<MatrixZoneIndicatorConfig> defaultMatrixIndicators = [
    MatrixZoneIndicatorConfig(
        key: 'watts', weight: 40.0, direction: 'up', sortOrder: 0),
    MatrixZoneIndicatorConfig(
        key: 'ef', weight: 25.0, direction: 'up', sortOrder: 1),
    MatrixZoneIndicatorConfig(
        key: 'time', weight: 20.0, direction: 'up', sortOrder: 2),
    MatrixZoneIndicatorConfig(
        key: 'decoupling', weight: 15.0, direction: 'down', sortOrder: 3),
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
    final prevPeriodStart =
        periodStart.subtract(Duration(days: periodDurationDays));
    final prevPeriodEnd = periodStart.subtract(const Duration(days: 1));

    // تصفية تمرينات نوع التمرين المحدد (قاعدة عدم التداخل)
    final kindLogs = allAthleteLogs.where((l) {
      final k = (l['kind'] as String?)?.trim();
      return k == null ||
          k.isEmpty ||
          k.toLowerCase() == workoutKind.toLowerCase();
    }).toList();

    // تقسيم التمرينات حسب الزون
    final details = <String, MatrixZoneDetail>{};
    final orderedZones = HeartRateZones.orderedZones; // Z1..VO2 max

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
        return (d.isAfter(prevPeriodStart) ||
                d.isAtSameMomentAs(prevPeriodStart)) &&
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
            metricScore =
                (baseVal - rawVal); // كلما نزل الـ Decoupling زادت الدرجة
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
              baseVal = prevCustomList.reduce((a, b) => a + b) /
                  prevCustomList.length;
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
        zoneScore = (weightedScoreSum / availableWeightSum)
            .clamp(-kMaxZoneScore, kMaxZoneScore);
      }

      // عرض الشريط: دالة متزايدة من درجة الزون (14.0 إلى 32.0)
      final barWidth = zoneScore != null
          ? (23.0 + (zoneScore / kMaxZoneScore) * 9.0)
              .clamp(kMinBarWidth, kMaxBarWidth)
          : kMinBarWidth;

      // ارتفاع منحنى القدرة عند الزون: دالة متناقصة من درجة الزون مبنية على خط أساس الواط الفعلي للاعب
      // capacityCurveVal = playerBaselineWatts * (1.0 - (zoneScore / 100.0))
      // المنطقة التي لا تمتلك خط أساس = لا توجد نقطة (null)
      double? capacityCurveVal;
      final playerBaselineWatts =
          wattsBaseline.startOfPeriodBaseline ?? wattsBaseline.currentBaseline;
      if (zoneScore != null &&
          playerBaselineWatts != null &&
          playerBaselineWatts > 0) {
        capacityCurveVal = playerBaselineWatts * (1.0 - (zoneScore / 100.0));
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
      lt1 = Point<double>(
          1.5 + (z2Score / kMaxZoneScore) * 0.3, z2Detail!.capacityCurveValue!);
    }

    Point<double>? lt2;
    if (thrDetail?.capacityCurveValue != null) {
      final thrScore = thrDetail?.zoneScore ?? 0.0;
      lt2 = Point<double>(4.0 + (thrScore / kMaxZoneScore) * 0.3,
          thrDetail!.capacityCurveValue!);
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
  static Future<void> saveMatrixZoneConfig(
      List<MatrixZoneIndicatorConfig> configs) async {
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

  // ════════════════════════════════════════════════════════════════
  // ── 10. حسابات الاستشفاء (Recovery Calculations: SWC & RHR Alert) ──
  // ════════════════════════════════════════════════════════════════
  /// الثابت المعتمد لتنبيه ارتفاع نبض الراحة (5 نبضات عن المتوسط المتحرك)
  static const double elevatedRhrThresholdBpm = 5.0;

  /// فحص تنبيه ارتفاع نبض الراحة الصباحي:
  /// إذا كان RHR لليوم أعلى من المتوسط المتحرك بـ 5 نبضات أو أكثر
  static bool isRhrElevated({
    required double? todayRhr,
    required double? ma7Rhr,
    double thresholdBpm = elevatedRhrThresholdBpm,
  }) {
    if (todayRhr == null || ma7Rhr == null) return false;
    return todayRhr >= (ma7Rhr + thresholdBpm);
  }

  /// حساب حزام التغير الأدنى ذي المعنى (SWC) لـ HRV:
  /// SWC = المتوسط المتحرك ± (0.5 × الانحراف المعياري لآخر 28 يوماً، أو آخر 7 أيام لو أقل)
  static ({double? upper, double? lower, double? stdDev}) calcHrvSwcBand({
    required DateTime targetDate,
    required List<DateValuePoint> hrvPoints,
    required double? ma7Value,
    int maxWindowDays = 28,
    int minWindowDays = 7,
  }) {
    if (ma7Value == null) {
      return (upper: null, lower: null, stdDev: null);
    }

    final targetMidnight =
        DateTime(targetDate.year, targetDate.month, targetDate.day);
    final start28 = targetMidnight.subtract(Duration(days: maxWindowDays - 1));
    final start7 = targetMidnight.subtract(Duration(days: minWindowDays - 1));

    final values28 = <double>[];
    final values7 = <double>[];

    for (final pt in hrvPoints) {
      if (pt.value == null || pt.value! <= 0) continue;
      final d = DateTime(pt.date.year, pt.date.month, pt.date.day);
      if (!d.isAfter(targetMidnight)) {
        if (!d.isBefore(start28)) {
          values28.add(pt.value!);
        }
        if (!d.isBefore(start7)) {
          values7.add(pt.value!);
        }
      }
    }

    // شرط القراءات الكافية (3 قراءات على الأقل في نافذة 28 أو 7 أيام)
    final window = values28.length >= 3
        ? values28
        : (values7.length >= 3 ? values7 : const <double>[]);

    if (window.length < 3) {
      return (upper: null, lower: null, stdDev: null);
    }

    final mean = window.reduce((a, b) => a + b) / window.length;
    double sumSqDiff = 0.0;
    for (final v in window) {
      final diff = v - mean;
      sumSqDiff += diff * diff;
    }
    final sampleVariance = sumSqDiff / (window.length - 1);
    final stdDev = sqrt(sampleVariance);

    final halfStdDev = 0.5 * stdDev;
    final upper = double.parse((ma7Value + halfStdDev).toStringAsFixed(1));
    final lower =
        double.parse(max(0.0, ma7Value - halfStdDev).toStringAsFixed(1));

    return (
      upper: upper,
      lower: lower,
      stdDev: double.parse(stdDev.toStringAsFixed(1)),
    );
  }

  // ════════════════════════════════════════════════════════════════
  // ── 11. حسابات القدرة الحرجة (Critical Power: CP, W', Balance Index) ──
  // ════════════════════════════════════════════════════════════════
  /// المسافات الافتراضية الأربعة المعتمدة من كوتش
  static const List<double> defaultCpDistances = [
    500.0,
    750.0,
    1500.0,
    3500.0,
  ];

  /// حساب الواط من المسافة بالمتر والزمن بالثواني:
  /// watts = 2.80 ÷ (timeSec ÷ distanceM)^3
  static double wattsFromTime(double distanceM, double timeSec) {
    if (distanceM <= 0 || timeSec <= 0) return 0.0;
    final pace = timeSec / distanceM; // ثانية لكل متر
    if (pace <= 0) return 0.0;
    final w = 2.80 / (pace * pace * pace);
    return double.parse(w.toStringAsFixed(1));
  }

  /// حساب الشغل الكلي بالجول = الواط × الزمن بالثواني
  static double workJoules(double watts, double timeSec) => watts * timeSec;

  /// حساب مؤشر التوازن Balance Index (BI) المعتمد من كوتش:
  /// BI = W' بالجول ÷ CP بالواط (الناتج بالثواني المتاحة للعمل فوق الـ CP)
  static double balanceIndex(double wPrimeJoules, double cpWatts) {
    if (cpWatts <= 0) return 0.0;
    final bi = wPrimeJoules / cpWatts;
    return double.parse(bi.toStringAsFixed(1));
  }

  /// تصنيف ميل مؤشر التوازن (BI) بمقارنة اختبار اللاعب بمتوسط اختباراته في الفترة
  /// إذا كان أعلى من المتوسط = مايل للانفجارية، أقل = مايل للتحمل، متقارب (ضمن 2%) = متوازن
  static BalanceIndexLeaning classifyBalanceIndex({
    required double bi,
    required double? avgBi,
    double thresholdRatio = 0.02,
  }) {
    if (avgBi == null || avgBi <= 0) return BalanceIndexLeaning.unclassified;
    final diff = (bi - avgBi) / avgBi;
    if (diff > thresholdRatio) return BalanceIndexLeaning.explosive;
    if (diff < -thresholdRatio) return BalanceIndexLeaning.endurance;
    return BalanceIndexLeaning.balanced;
  }

  /// حساب CP و W' و BI من قائمة مسافات وأزمنة
  /// يشترط 3 مسافات صالحة على الأقل، ويرجع null إذا كانت أقل من 3 أو النتائج غير متسقة
  static CpCalculationResult? calcCpAndWPrime(
    List<({double distanceM, double timeSec})> testDistances,
  ) {
    // تصفية المدخلات الصالحة (المسافة > 0 والزمن > 0)
    final valid =
        testDistances.where((t) => t.distanceM > 0 && t.timeSec > 0).toList();

    if (valid.length < 3) {
      return null;
    }

    // حساب النقاط (الزمن t والشغل w بالجول)
    final points = valid.map((t) {
      final w = wattsFromTime(t.distanceM, t.timeSec);
      final work = w * t.timeSec;
      return (t: t.timeSec, work: work, watts: w, distance: t.distanceM);
    }).toList();

    // انحدار خطي بالمربعات الصغرى: Work = CP * t + W'
    // Y = Work, X = t
    final n = points.length.toDouble();
    double sumT = 0.0;
    double sumWork = 0.0;
    double sumTWork = 0.0;
    double sumT2 = 0.0;

    for (final p in points) {
      sumT += p.t;
      sumWork += p.work;
      sumTWork += p.t * p.work;
      sumT2 += p.t * p.t;
    }

    final denom = n * sumT2 - (sumT * sumT);
    if (denom <= 0) return null;

    final cp = (n * sumTWork - sumT * sumWork) / denom;
    final wPrime = (sumWork - cp * sumT) / n;

    // اشتراط CP > 0 و W' > 0
    if (cp <= 0 || wPrime <= 0) {
      return null;
    }

    final bi = balanceIndex(wPrime, cp);

    return CpCalculationResult(
      cpWatts: double.parse(cp.toStringAsFixed(1)),
      wPrimeJoules: double.parse(wPrime.toStringAsFixed(1)),
      wPrimeKiloJoules: double.parse((wPrime / 1000.0).toStringAsFixed(2)),
      balanceIndexSeconds: bi,
      validPointsCount: valid.length,
    );
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
      await database
          .delete('daily_load', where: 'player_id = ?', whereArgs: [playerId]);
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

/// تصنيف ميل مؤشر التوازن
enum BalanceIndexLeaning {
  explosive,
  endurance,
  balanced,
  unclassified,
}

/// نتيجة حساب CP و W' و BI
class CpCalculationResult {
  final double cpWatts;
  final double wPrimeJoules;
  final double wPrimeKiloJoules;
  final double balanceIndexSeconds;
  final int validPointsCount;

  const CpCalculationResult({
    required this.cpWatts,
    required this.wPrimeJoules,
    required this.wPrimeKiloJoules,
    required this.balanceIndexSeconds,
    required this.validPointsCount,
  });
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
