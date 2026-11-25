import 'dart:math';

/// محرك الحسابات المتقدمة للقدرة (Normalized Power) و Decoupling
class PowerCalculations {
  /// تحويل نص مفصول بفواصل إلى قائمة أرقام
  static List<double> parseSeries(String text) {
    if (text.trim().isEmpty) return [];
    final items = text.split(RegExp(r'[,،\s]+'));
    final result = <double>[];
    for (final item in items) {
      final clean = item.trim();
      if (clean.isNotEmpty) {
        final val = double.tryParse(clean);
        if (val != null && val > 0) {
          result.add(val);
        }
      }
    }
    return result;
  }

  /// حساب الـ Normalized Power (NP) وفق خوارزمية Coggan القياسية:
  /// 1. حساب المتوسط المتحرك (30-second moving average أو النوافذ المتتالية)
  /// 2. رفع القيم للأس 4 (Power to the 4th)
  /// 3. حساب متوسط القيم المرفوعة للأس 4
  /// 4. أخذ الجذر الرابع للناتج (4th root)
  static double? calculateNormalizedPower(List<double> rawPowers, {int windowSize = 3}) {
    if (rawPowers.isEmpty) return null;
    if (rawPowers.length == 1) return rawPowers.first;

    // 1. حساب المتوسط المتحرك
    final smoothed = <double>[];
    for (int i = 0; i < rawPowers.length; i++) {
      final start = max(0, i - windowSize + 1);
      final window = rawPowers.sublist(start, i + 1);
      final avg = window.reduce((a, b) => a + b) / window.length;
      smoothed.add(avg);
    }

    // 2 & 3. رفع للأس 4 وحساب المتوسط
    double sumPow4 = 0;
    for (final p in smoothed) {
      sumPow4 += pow(p, 4).toDouble();
    }
    final avgPow4 = sumPow4 / smoothed.length;

    // 4. أخذ الجذر الرابع
    if (avgPow4 <= 0) return 0;
    final np = pow(avgPow4, 0.25).toDouble();
    return double.parse(np.toStringAsFixed(1));
  }

  /// حساب معدل الكفاءة Efficiency Factor (EF = Watts / HR)
  static double? calculateEF(double? power, int? hr) {
    if (power == null || hr == null || hr <= 0 || power <= 0) return null;
    final ef = power / hr;
    return double.parse(ef.toStringAsFixed(2));
  }

  /// حساب الـ Decoupling (Pw:HR Drift) بين النصف الأول والنصف الثاني
  /// النسبة = ((EF1 - EF2) / EF1) * 100
  static double? calculateDecoupling(List<double> powers, List<double> hrs) {
    final count = min(powers.length, hrs.length);
    if (count < 4) return null;

    final mid = count ~/ 2;
    
    // النصف الأول
    final p1 = powers.sublist(0, mid);
    final hr1 = hrs.sublist(0, mid);
    final avgP1 = p1.reduce((a, b) => a + b) / p1.length;
    final avgHr1 = hr1.reduce((a, b) => a + b) / hr1.length;
    final ef1 = avgP1 / avgHr1;

    // النصف الثاني
    final p2 = powers.sublist(mid, count);
    final hr2 = hrs.sublist(mid, count);
    final avgP2 = p2.reduce((a, b) => a + b) / p2.length;
    final avgHr2 = hr2.reduce((a, b) => a + b) / hr2.length;
    final ef2 = avgP2 / avgHr2;

    if (ef1 <= 0) return null;
    final decoupling = ((ef1 - ef2) / ef1) * 100;
    return double.parse(decoupling.toStringAsFixed(1));
  }
}
