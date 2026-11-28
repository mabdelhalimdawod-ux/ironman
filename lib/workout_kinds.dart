import 'app_strings.dart';

/// القائمة المركزية الوحيدة لأنواع التمرين في التطبيق كله:
/// مستخلصة من القائمة المنسدلة الأصلية في فورم التمرينة والبرنامج:
/// Erg, Row, Run, bike, Fitness, Stretch, Mob
///
/// أنواع تدريب الأداء فقط (تظهر في منحنيات الواط، EF، Decoupling، Eupnea):
/// Erg, Row, Run, bike, Fitness
///
/// أنواع غير تدريب أداء (تظهر في الفورم والبرنامج وساعات المناطق فقط):
/// Stretch, Mob (بالإضافة لأي إحماء/تهدئة)
class WorkoutKinds {
  /// القائمة الكاملة لأنواع التمرين (للفورم والبرنامج وساعات المناطق)
  static const List<String> all = [
    'Erg',
    'Row',
    'Run',
    'bike',
    'Fitness',
    'Stretch',
    'Mob',
  ];

  /// أنواع تدريب الأداء فقط (ممنوع ظهور Stretch/Mob/إحماء/تهدئة في منحنيات الأداء)
  static const List<String> performanceKinds = [
    'Erg',
    'Row',
    'Run',
    'bike',
    'Fitness',
  ];

  /// خريطة المطابقة للحفاظ على التوافق مع البيانات القديمة في السجلات
  static const Map<String, String> _legacyAliases = {
    'erg': 'Erg',
    'ergometer': 'Erg',
    'إرج': 'Erg',
    'ارج': 'Erg',
    'إرجوميتر': 'Erg',
    'row': 'Row',
    'water': 'Row',
    'rowing': 'Row',
    'ماء': 'Row',
    'تجديف': 'Row',
    'تجديف مائي': 'Row',
    'run': 'Run',
    'running': 'Run',
    'جري': 'Run',
    'bike': 'bike',
    'cycling': 'bike',
    'دراجة': 'bike',
    'دراجه': 'bike',
    'fitness': 'Fitness',
    'لياقة': 'Fitness',
    'لياقه': 'Fitness',
    'stretch': 'Stretch',
    'stretching': 'Stretch',
    'flexibility': 'Stretch',
    'إطالة': 'Stretch',
    'اطالة': 'Stretch',
    'إطالات': 'Stretch',
    'اطالات': 'Stretch',
    'مرونة': 'Stretch',
    'mob': 'Mob',
    'mobility': 'Mob',
    'مرونة حركية': 'Mob',
  };

  static const Set<String> _nonPerformanceWords = {
    'stretch',
    'stretching',
    'flexibility',
    'mob',
    'mobility',
    'warmup',
    'warm-up',
    'warm up',
    'cooldown',
    'cool-down',
    'cool down',
    'إحماء',
    'احماء',
    'تهدئة',
    'تهدئه',
    'إطالة',
    'إطالات',
    'مرونة',
    'مرونة حركية',
  };

  /// توحيد نوع التمرين من القيمة المخزنة في السجلات إلى أحد المفاتيح المركزية السبعة.
  /// يرجع null إذا لم تتطابق القيمة مع أي نوع معروف في القائمة المركزية.
  static String? normalizeKind(String? rawKind) {
    if (rawKind == null) return null;
    final clean = rawKind.trim().toLowerCase();
    if (clean.isEmpty) return null;
    return _legacyAliases[clean];
  }

  /// هل نوع التمرين المخزن ينتمي لأنواع تدريب الأداء؟
  static bool isPerformanceKind(String? rawKind) {
    if (rawKind == null) return false;
    final clean = rawKind.trim().toLowerCase();
    if (clean.isEmpty || _nonPerformanceWords.contains(clean)) {
      return false;
    }
    final normalized = normalizeKind(rawKind);
    return normalized != null && performanceKinds.contains(normalized);
  }

  /// هل يطابق نوع التمرين المسجل النوع المختار في الفلتر (مع دعم الصيغ القديمة)؟
  static bool matchesKind(String? rawKind, String selectedKind) {
    final normSelected = normalizeKind(selectedKind) ?? selectedKind.trim();
    final normRaw = normalizeKind(rawKind);
    if (normRaw != null) {
      return normRaw.toLowerCase() == normSelected.toLowerCase();
    }
    if (rawKind == null) return false;
    return rawKind.trim().toLowerCase() == normSelected.toLowerCase();
  }

  /// الاسم المترجم لنوع التمرين للعرض في القوائم والمنحنيات
  static String displayName(String rawKind, AppStrings s) {
    final norm = normalizeKind(rawKind) ?? rawKind.trim();
    switch (norm) {
      case 'Erg':
        return s.typeErg;
      case 'Row':
        return s.typeWaterRowing;
      case 'Run':
        return s.typeRun;
      case 'bike':
        return s.typeBike;
      case 'Fitness':
        return s.typeFitness;
      case 'Stretch':
        return s.typeStretch;
      case 'Mob':
        return s.typeMobility;
      default:
        return rawKind;
    }
  }

  /// استخراج الأنواع الافتراضية المتكررة من بيانات التمارين ضمن أنواع الأداء فقط
  static String computeInitialPerformanceKind(
    List<Map<String, Object?>> workouts, {
    Map<int, List<Map<String, Object?>>>? multiAthleteWorkouts,
  }) {
    final counts = <String, int>{};

    void countList(List<Map<String, Object?>> list) {
      for (final w in list) {
        final raw =
            (w['kind'] as String?) ?? (w['session_kind'] as String?) ?? '';
        final norm = normalizeKind(raw);
        if (norm != null && performanceKinds.contains(norm)) {
          counts[norm] = (counts[norm] ?? 0) + 1;
        }
      }
    }

    countList(workouts);
    if (multiAthleteWorkouts != null) {
      for (final list in multiAthleteWorkouts.values) {
        countList(list);
      }
    }

    if (counts.isEmpty) return performanceKinds.first; // 'Erg'
    var bestKind = performanceKinds.first;
    var bestCount = -1;
    for (final k in performanceKinds) {
      final c = counts[k] ?? 0;
      if (c > bestCount) {
        bestCount = c;
        bestKind = k;
      }
    }
    return bestKind;
  }

  /// رصد أي قيم `kind` قديمة في السجلات لم تتطابق مع القائمة المركزية السبعة
  static List<String> findUnmatchedKinds(List<Map<String, Object?>> rows) {
    final unmatched = <String>{};
    for (final row in rows) {
      final raw =
          (row['kind'] as String?) ?? (row['session_kind'] as String?) ?? '';
      final trimmed = raw.trim();
      if (trimmed.isEmpty) continue;
      if (normalizeKind(trimmed) == null &&
          !_nonPerformanceWords.contains(trimmed.toLowerCase())) {
        unmatched.add(trimmed);
      }
    }
    return unmatched.toList()..sort();
  }
}
