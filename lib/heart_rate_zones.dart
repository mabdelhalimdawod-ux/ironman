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
/// نسب المناطق من احتياطي النبض:
/// - Z1: 50% - 60%
/// - Z2: 60% - 70%
/// - Z3: 70% - 80%
/// - Z4: 80% - 90%
/// - Z5: 90% - 100%
class HeartRateZones {
  /// نسب الزونات الأساسية
  static const Map<String, List<double>> zonePercentages = {
    'Z1': [0.50, 0.60],
    'Z2': [0.60, 0.70],
    'Z3': [0.70, 0.80],
    'Z4': [0.80, 0.90],
    'Z5': [0.90, 1.00],
  };

  /// استخراج الزون الأساسي النظيف (Z1 إلى Z5) حتى لو كان النص يحتوي مسميات مثل "Z4 Threshold"
  static String normalizeZoneKey(String zone) {
    final trimmed = zone.trim().toUpperCase();
    if (trimmed.startsWith('Z1')) return 'Z1';
    if (trimmed.startsWith('Z2')) return 'Z2';
    if (trimmed.startsWith('Z3')) return 'Z3';
    if (trimmed.startsWith('Z4')) return 'Z4';
    if (trimmed.startsWith('Z5')) return 'Z5';
    return 'Z2'; // القيمة الافتراضية
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
