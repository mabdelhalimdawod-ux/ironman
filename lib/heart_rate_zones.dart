import 'package:flutter/material.dart';
import 'db.dart';

/// فئة تمثل نطاق النبض المستهدف
class HeartRateZoneRange {
  final String zoneKey;
  final int minHR;
  final int maxHR;
  final int rhrUsed;
  final int hrr;
  final bool isKarvonen;

  const HeartRateZoneRange({
    required this.zoneKey,
    required this.minHR,
    required this.maxHR,
    required this.rhrUsed,
    required this.hrr,
    this.isKarvonen = true,
  });

  /// نص نطاق النبض المنسق (مثال: "135 - 152 bpm")
  String format([String unit = 'bpm']) => '$minHR - $maxHR $unit';

  @override
  String toString() => format();
}

/// محرك حساب نطاقات النبض بمعادلة كارفونين (Karvonen Heart Rate Zones)
///
/// معادلة كارفونين:
/// 1. احتياطي النبض (HRR) = الحد الأقصى للنبض (MHR) - نبض الراحة (RHR)
/// 2. النبض المستهدف = (احتياطي النبض × النسبة) + نبض الراحة
///
/// نسب المناطق المعتمدة في التطبيق كله (التعديل الثاني للـ ZONES):
/// - (zone1 - UT3): 55% - 65% (متوسط النبض المخزن 60%)
/// - (zone2 - UT2): 65% - 75% (متوسط النبض المخزن 70%)
/// - (zone3 - UT1): 75% - 85% (متوسط النبض المخزن 85%)
/// - (zone4 - AT): 85% - 90% (متوسط النبض المخزن 88%)
/// - (Threshold - AT): 90% - 95% (متوسط النبض المخزن 92%)
/// - (zone5 - TR): 95% - 98% (متوسط النبض المخزن 96%)
/// - (VO2 max - AN): 98% - 105% (متوسط النبض المخزن 103%)
class HeartRateZones {
  /// قائمة مفاتيح الزونات السبعة بالترتيب
  static const List<String> orderedZones = [
    'Z1',
    'Z2',
    'Z3',
    'Z4',
    'Threshold',
    'Z5',
    'VO2 max',
  ];

  /// نسب الزونات الأساسية
  static const Map<String, List<double>> zonePercentages = {
    'Z1': [0.55, 0.65],
    'Z2': [0.65, 0.75],
    'Z3': [0.75, 0.85],
    'Z4': [0.85, 0.90],
    'Threshold': [0.90, 0.95],
    'Z5': [0.95, 0.98],
    'VO2 max': [0.98, 1.05],
  };

  /// متوسطات نسب النبض المخزونة
  static const Map<String, double> zoneMidPercentages = {
    'Z1': 0.60,
    'Z2': 0.70,
    'Z3': 0.85,
    'Z4': 0.88,
    'Threshold': 0.92,
    'Z5': 0.96,
    'VO2 max': 1.03,
  };

  /// استخراج الزون الأساسي النظيف (Z1 إلى VO2 max)
  static String normalizeZoneKey(String zone) {
    final trimmed = zone.trim().toUpperCase();
    if (trimmed.contains('VO2') ||
        trimmed.contains('MAX') ||
        trimmed.contains('AN')) {
      return 'VO2 max';
    }
    if (trimmed.contains('THRESHOLD') || trimmed.contains('THR')) {
      return 'Threshold';
    }
    if (trimmed.startsWith('Z1') ||
        trimmed.contains('ZONE1') ||
        trimmed.contains('UT3')) {
      return 'Z1';
    }
    if (trimmed.startsWith('Z2') ||
        trimmed.contains('ZONE2') ||
        trimmed.contains('UT2')) {
      return 'Z2';
    }
    if (trimmed.startsWith('Z3') ||
        trimmed.contains('ZONE3') ||
        trimmed.contains('UT1')) {
      return 'Z3';
    }
    if (trimmed.startsWith('Z4') ||
        trimmed.contains('ZONE4') ||
        (trimmed.contains('AT') && !trimmed.contains('THRESHOLD'))) {
      return 'Z4';
    }
    if (trimmed.startsWith('Z5') ||
        trimmed.contains('ZONE5') ||
        trimmed.contains('TR')) {
      return 'Z5';
    }
    return 'Z2'; // القيمة الافتراضية
  }

  /// تحديد الزون تلقائياً بمعادلة كارفونين من نبض التمرين:
  /// HRR = MHR − RHR
  /// النسبة = (النبض − RHR) ÷ HRR
  static String? determineZone({
    required int? hr,
    required int? mhr,
    required int? rhr,
  }) {
    if (hr == null ||
        mhr == null ||
        rhr == null ||
        hr <= 0 ||
        mhr <= 0 ||
        rhr <= 0) {
      return null;
    }
    if (mhr <= rhr) {
      return 'Z1';
    }
    final hrr = mhr - rhr;
    if (hrr <= 0) return 'Z1';
    final pct = (hr - rhr) / hrr;
    if (pct < 0.65) return 'Z1';
    if (pct < 0.75) return 'Z2';
    if (pct < 0.85) return 'Z3';
    if (pct < 0.90) return 'Z4';
    if (pct < 0.95) return 'Threshold';
    if (pct < 0.98) return 'Z5';
    return 'VO2 max';
  }

  /// اسم الزون المعروض
  static String zoneDisplayName(String zone, {bool isArabic = true}) {
    final clean = normalizeZoneKey(zone);
    switch (clean) {
      case 'Z1':
        return '(zone1 - UT3) = 55%:65%';
      case 'Z2':
        return '(zone2 - UT2) = 65%:75%';
      case 'Z3':
        return '(zone3 - UT1) = 75%:85%';
      case 'Z4':
        return '(zone4 - AT) = 85%:90%';
      case 'Threshold':
        return '(Threshold - AT) = 90%:95%';
      case 'Z5':
        return '(zone5 - TR) = 95%:98%';
      case 'VO2 max':
        return '(VO2 max - AN) = 98%:105%';
      default:
        return zone;
    }
  }

  /// لون الشارة للزون المعتمد في الهوية المحدثة من الـ Theme
  /// Z1 أزرق، Z2 أخضر، Z3 أصفر، Z4 برتقالي، Threshold برتقالي غامق، Z5 أحمر، VO2 max أحمر داكن
  static Color zoneColor(String zone) {
    final clean = normalizeZoneKey(zone);
    switch (clean) {
      case 'Z1':
        return const Color(0xFF2979FF); // أزرق
      case 'Z2':
        return const Color(0xFF00E676); // أخضر
      case 'Z3':
        return const Color(0xFFFFD600); // أصفر
      case 'Z4':
        return const Color(0xFFFF9100); // برتقالي
      case 'Threshold':
        return const Color(0xFFE65100); // برتقالي داكن / Threshold
      case 'Z5':
        return const Color(0xFFFF5252); // أحمر
      case 'VO2 max':
        return const Color(0xFF8B0000); // أحمر داكن (Dark Red)
      default:
        return const Color(0xFF2979FF);
    }
  }

  /// حساب نطاق النبض المستهدف بمعادلة كارفونين بشكل مباشر
  static HeartRateZoneRange calculate({
    required int mhr,
    required int rhr,
    required String zone,
  }) {
    final cleanZone = normalizeZoneKey(zone);
    final pct = zonePercentages[cleanZone] ?? const [0.60, 0.70];

    // لو نبض الراحة غير منطقي أو يساوي صفر، نرجع للحساب البسيط من MHR
    if (rhr <= 0 || rhr >= mhr) {
      final min = (mhr * pct[0]).round();
      final max = (mhr * pct[1]).round();
      return HeartRateZoneRange(
        zoneKey: cleanZone,
        minHR: min,
        maxHR: max,
        rhrUsed: rhr,
        hrr: mhr,
        isKarvonen: false,
      );
    }

    final hrr = mhr - rhr;
    final min = (rhr + (hrr * pct[0])).round();
    final max = (rhr + (hrr * pct[1])).round();

    return HeartRateZoneRange(
      zoneKey: cleanZone,
      minHR: min,
      maxHR: max,
      rhrUsed: rhr,
      hrr: hrr,
      isKarvonen: true,
    );
  }

  /// جلب نبض الراحة الفعّال للاعب:
  /// - متوسط آخر 7 أيام إذا توفرت بيانات
  /// - إذا لم تتوفر بيانات خلال آخر 7 أيام، نأخذ آخر قيمة مسجلة
  /// - إذا لم يسجل أي نبض راحة على الإطلاق، نرجع قيمة افتراضية تقديرية (60)
  static Future<int> getEffectiveRHR(int playerId) async {
    try {
      final cutoffDate = dstr(DateTime.now().subtract(const Duration(days: 7)));

      // 1. فحص متوسط آخر 7 أيام
      final weekRes = await DB.q('''
        SELECT AVG(rhr) as avg_rhr, COUNT(*) as cnt 
        FROM logs 
        WHERE player_id = ? AND date >= ? AND rhr IS NOT NULL AND rhr > 0
      ''', [playerId, cutoffDate]);

      if (weekRes.isNotEmpty) {
        final cnt = (weekRes.first['cnt'] as num?)?.toInt() ?? 0;
        final avg = (weekRes.first['avg_rhr'] as num?)?.toDouble();
        if (cnt > 0 && avg != null && avg > 0) {
          return avg.round();
        }
      }

      // 2. إذا لم تتوفر بيانات في آخر 7 أيام: آخر قيمة مسجلة للاعب
      final latestRes = await DB.q('''
        SELECT rhr FROM logs 
        WHERE player_id = ? AND rhr IS NOT NULL AND rhr > 0 
        ORDER BY date DESC, idx DESC 
        LIMIT 1
      ''', [playerId]);

      if (latestRes.isNotEmpty) {
        final lastRhr = latestRes.first['rhr'] as int?;
        if (lastRhr != null && lastRhr > 0) {
          return lastRhr;
        }
      }
    } catch (_) {}

    // قيمة افتراضية احتياطية إن لم تكن هناك أي قراءة مسجلة
    return 60;
  }

  /// حساب النطاق المستهدف للاعب بناءً على هويته وقاعدة البيانات والزون
  static Future<HeartRateZoneRange> calculateForPlayer({
    required int playerId,
    required int mhr,
    required String zone,
  }) async {
    final effectiveRHR = await getEffectiveRHR(playerId);
    return calculate(mhr: mhr, rhr: effectiveRHR, zone: zone);
  }
}
