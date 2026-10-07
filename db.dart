import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'dart:math';

const kinds = ['Erg', 'Water', 'Fitness', 'Running'];
const zones = {
  'Z1': [50, 60],
  'Z2': [60, 70],
  'Z3': [70, 80],
  'Z4 Threshold': [80, 90],
  'Z5 VO2 Max': [90, 100],
};

/// مناطق القدرة بناءً على الـ Critical Power
const cpPowerZones = {
  'Z1 استشفاء': [0, 55],
  'Z2 تحمل هوائي': [56, 75],
  'Z3 إيقاع': [76, 90],
  'Z4 عتبة (CP)': [91, 105],
  'Z5 VO2max': [106, 120],
  'Z6 لا هوائي': [121, 200],
};

/// أنواع اختبارات CP
const cpTestTypes = ['2000m', '5000m', '500m', '6min', '12min', '30min', 'مخصص'];

/// تسميات مستوى الإرهاق
const fatigueLabels = {1: 'ممتاز', 2: 'جيد', 3: 'مقبول', 4: 'متعب', 5: 'مرهق'};

/// تسميات مستوى الجاهزية
const readinessLabels = {1: 'مرهق', 2: 'غير جاهز', 3: 'متوسط', 4: 'جاهز', 5: 'جاهز تمامًا'};

String dstr(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// نطاق النبض المستهدف للاعب حسب الـ MHR والـ Zone
String hrRange(int mhr, String zone) {
  final z = zones[zone] ?? [60, 70];
  return '${(mhr * z[0] / 100).round()} - ${(mhr * z[1] / 100).round()}';
}

/// نطاق القدرة المستهدف للاعب بناءً على CP ومنطقة القدرة
String cpRange(double cp, String powerZone) {
  final z = cpPowerZones[powerZone] ?? [56, 75];
  return '${(cp * z[0] / 100).round()} - ${(cp * z[1] / 100).round()} W';
}

/// تحديد منطقة القدرة من الواط الفعلي والـ CP
String powerZoneFromWatts(double watts, double cp) {
  if (cp <= 0) return '-';
  final pct = (watts / cp * 100).round();
  for (final e in cpPowerZones.entries) {
    if (pct >= e.value[0] && pct <= e.value[1]) return e.key;
  }
  return pct > 200 ? 'Z6 لا هوائي' : 'Z1 استشفاء';
}

// ==================== حسابات الأرقو (Concept2) ====================

/// تحويل زمن 500م (بالثواني) إلى واط
double splitToWatts(double splitSeconds) {
  if (splitSeconds <= 0) return 0;
  final pace = splitSeconds / 500; // ثانية لكل متر
  return 2.80 / (pace * pace * pace);
}

/// تحويل الواط إلى زمن 500م (بالثواني)
double wattsToSplit(double watts) {
  if (watts <= 0) return 0;
  final pace = pow(2.80 / watts, 1.0 / 3.0); // ثانية لكل متر
  return (pace * 500).toDouble();
}

/// تنسيق زمن السبليت: 105.3 ثانية → "1:45.3"
String formatSplit(double seconds) {
  if (seconds <= 0) return '-';
  final mins = (seconds / 60).floor();
  final secs = seconds - mins * 60;
  return '$mins:${secs.toStringAsFixed(1).padLeft(4, '0')}';
}

/// تنسيق الوقت بالدقائق والثواني: 480 ثانية → "8:00"
String formatDuration(int seconds) {
  final mins = seconds ~/ 60;
  final secs = seconds % 60;
  return '$mins:${secs.toString().padLeft(2, '0')}';
}

// ==================== حساب الـ Critical Power ====================

/// حساب CP و W' من مجموعة اختبارات
/// tests: قائمة {duration_seconds, avg_power}
/// يتطلب اختبارين على الأقل بمدد مختلفة
Map<String, double> calculateCP(List<Map<String, dynamic>> tests) {
  if (tests.length < 2) return {};

  // ترتيب حسب المدة
  tests.sort((a, b) =>
      (a['duration_seconds'] as int).compareTo(b['duration_seconds'] as int));

  if (tests.length == 2) {
    // الطريقة الخطية بنقطتين
    final t1 = (tests[0]['duration_seconds'] as int).toDouble();
    final t2 = (tests[1]['duration_seconds'] as int).toDouble();
    final p1 = (tests[0]['avg_power'] as num).toDouble();
    final p2 = (tests[1]['avg_power'] as num).toDouble();

    if (t1 == t2) return {};

    final w1 = p1 * t1; // الشغل الكلي - اختبار 1
    final w2 = p2 * t2; // الشغل الكلي - اختبار 2

    final cp = (w2 - w1) / (t2 - t1);
    final wPrime = w1 - cp * t1;

    if (cp <= 0) return {};
    return {'cp': cp, 'w_prime': wPrime.abs()};
  }

  // طريقة الانحدار الخطي (3+ نقاط)
  // W (الشغل الكلي) = CP × t + W'
  // المنحدر = CP, التقاطع = W'
  final n = tests.length.toDouble();
  double sumT = 0, sumW = 0, sumTW = 0, sumT2 = 0;
  for (final test in tests) {
    final t = (test['duration_seconds'] as int).toDouble();
    final w = (test['avg_power'] as num).toDouble() * t;
    sumT += t;
    sumW += w;
    sumTW += t * w;
    sumT2 += t * t;
  }

  final denom = n * sumT2 - sumT * sumT;
  if (denom == 0) return {};

  final cp = (n * sumTW - sumT * sumW) / denom;
  final wPrime = (sumW - cp * sumT) / n;

  if (cp <= 0) return {};
  return {'cp': cp, 'w_prime': wPrime.abs()};
}

/// تقدير CP من اختبار واحد (أقل دقة)
/// يستخدم عامل تقريبي حسب مدة الاختبار
double estimateCPFromSingle(double avgPower, int durationSeconds) {
  // كلما زادت المدة كلما اقترب المتوسط من CP
  if (durationSeconds >= 1800) return avgPower * 0.97; // 30+ دقيقة
  if (durationSeconds >= 1200) return avgPower * 0.93; // 20 دقيقة
  if (durationSeconds >= 720) return avgPower * 0.90;  // 12 دقيقة
  if (durationSeconds >= 360) return avgPower * 0.85;  // 6 دقائق
  if (durationSeconds >= 120) return avgPower * 0.78;  // 2 دقيقة
  return avgPower * 0.70; // أقل من دقيقتين
}

// ==================== حساب حمل التدريب (TSS) ====================

/// حساب Training Stress Score
/// TSS = (t × P²) / (CP² × 3600) × 100
double calculateTSS({
  required double avgPower,
  required int durationSeconds,
  required double cp,
}) {
  if (cp <= 0 || durationSeconds <= 0 || avgPower <= 0) return 0;
  final intensityFactor = avgPower / cp;
  return (durationSeconds * avgPower * intensityFactor) / (cp * 3600) * 100;
}

/// حساب Intensity Factor
double intensityFactor(double avgPower, double cp) {
  if (cp <= 0) return 0;
  return avgPower / cp;
}

// ==================== حساب التوازن والجاهزية ====================

/// حساب نسبة الاستشفاء
double? recoveryRate(int? hrDuring, int? hrPost) {
  if (hrDuring == null || hrPost == null || hrDuring == 0) return null;
  return ((hrDuring - hrPost) / hrDuring) * 100;
}

/// حساب مؤشر الجاهزية الشامل (مبني على CP + الفسيولوجيا)
double calculateReadiness({
  int? rhr,
  double? rhrBaseline,
  int? hrv,
  double? hrvBaseline,
  int? fatigue,
  double? sleepHours,
  double? tsb, // Training Stress Balance - المؤشر الرئيسي
}) {
  double score = 70;

  // ═══ TSB هو المقياس الرئيسي (الأهم - مبني على CP) ═══
  if (tsb != null) {
    if (tsb > 20) {
      score += 20; // جاهز جدًا
    } else if (tsb > 5) {
      score += 12; // جاهز
    } else if (tsb > -10) {
      score += 0; // متوازن
    } else if (tsb > -25) {
      score -= 12; // إجهاد تدريبي
    } else {
      score -= 25; // إفراط تدريبي
    }
  }

  // RHR مقارنة بالخط الأساسي
  if (rhr != null && rhrBaseline != null && rhrBaseline > 0) {
    final diff = rhr - rhrBaseline;
    if (diff > 8) {
      score -= 15;
    } else if (diff > 5) {
      score -= 8;
    } else if (diff > 3) {
      score -= 4;
    } else if (diff < -2) {
      score += 3;
    }
  }

  // HRV مقارنة بالخط الأساسي
  if (hrv != null && hrvBaseline != null && hrvBaseline > 0) {
    final ratio = hrv / hrvBaseline;
    if (ratio < 0.7) {
      score -= 15;
    } else if (ratio < 0.85) {
      score -= 7;
    } else if (ratio > 1.1) {
      score += 5;
    }
  }

  // الإرهاق المحسوس
  if (fatigue != null) {
    score += (fatigue - 3) * -5.0;
  }

  // النوم
  if (sleepHours != null) {
    if (sleepHours < 5) {
      score -= 12;
    } else if (sleepHours < 6) {
      score -= 7;
    } else if (sleepHours >= 8) {
      score += 3;
    }
  }

  return score.clamp(0, 100);
}

/// لون مؤشر الجاهزية
int readinessColor(double score) {
  if (score >= 80) return 0xFF4CAF50;
  if (score >= 60) return 0xFFFFC107;
  if (score >= 40) return 0xFFFF9800;
  return 0xFFF44336;
}

/// نص مؤشر الجاهزية
String readinessText(double score) {
  if (score >= 80) return 'ممتاز';
  if (score >= 60) return 'جيد';
  if (score >= 40) return 'انتبه';
  return 'خطر';
}

/// نص وصف TSB
String tsbDescription(double tsb) {
  if (tsb > 25) return 'جاهز تمامًا - يمكن المنافسة';
  if (tsb > 10) return 'مستريح - مناسب لتمرين قوي';
  if (tsb > -5) return 'متوازن - تدريب مثالي';
  if (tsb > -15) return 'إجهاد خفيف - بناء لياقة';
  if (tsb > -30) return 'إجهاد - يحتاج مراقبة';
  return 'إفراط تدريبي - يحتاج راحة!';
}

int tsbColor(double tsb) {
  if (tsb > 15) return 0xFF2196F3;   // أزرق - جاهز/مستريح
  if (tsb > 0) return 0xFF4CAF50;    // أخضر - متوازن
  if (tsb > -15) return 0xFFFFC107;  // أصفر - إجهاد بنّاء
  if (tsb > -30) return 0xFFFF9800;  // برتقالي - إجهاد
  return 0xFFF44336;                  // أحمر - إفراط
}

// ==================== قاعدة البيانات ====================

class DB {
  static Database? _db;
  static Future<Database> get db async => _db ??= await _open();

  static Future<Database> _open() async {
    final path = join(await getDatabasesPath(), 'rowing.db');
    return openDatabase(path, version: 3,
        onCreate: (d, v) async {
          await d.execute(
              'CREATE TABLE players(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, mhr INTEGER, active INTEGER DEFAULT 1)');
          await d.execute(
              'CREATE TABLE cycles(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, start TEXT, end TEXT)');
          await d.execute(
              'CREATE TABLE sessions(date TEXT, idx INTEGER, kind TEXT, zone TEXT, PRIMARY KEY(date, idx))');
          await d.execute(
              'CREATE TABLE notes(date TEXT PRIMARY KEY, general TEXT, tech TEXT)');
          await d.execute('''
            CREATE TABLE logs(
              player_id INTEGER,
              date TEXT,
              idx INTEGER,
              rhr INTEGER,
              hrv INTEGER,
              hr INTEGER,
              hr_max INTEGER,
              hr_post INTEGER,
              hr_1min INTEGER,
              weight REAL,
              fatigue INTEGER,
              sleep_hours REAL,
              readiness INTEGER,
              player_notes TEXT,
              avg_power REAL,
              max_power REAL,
              duration_seconds INTEGER,
              distance INTEGER,
              PRIMARY KEY(player_id, date, idx)
            )
          ''');
          await d.execute('''
            CREATE TABLE cp_tests(
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              player_id INTEGER,
              date TEXT,
              test_type TEXT,
              duration_seconds INTEGER,
              avg_power REAL,
              max_power REAL,
              distance INTEGER,
              avg_hr INTEGER,
              max_hr INTEGER,
              split_500 REAL,
              notes TEXT
            )
          ''');
          await d.execute('''
            CREATE TABLE cp_values(
              player_id INTEGER,
              date TEXT,
              cp REAL,
              w_prime REAL,
              method TEXT,
              PRIMARY KEY(player_id, date)
            )
          ''');
        },
        onUpgrade: (d, oldVersion, newVersion) async {
          if (oldVersion < 2) {
            await d.execute('ALTER TABLE logs ADD COLUMN hr_max INTEGER');
            await d.execute('ALTER TABLE logs ADD COLUMN hr_post INTEGER');
            await d.execute('ALTER TABLE logs ADD COLUMN hr_1min INTEGER');
            await d.execute('ALTER TABLE logs ADD COLUMN fatigue INTEGER');
            await d.execute('ALTER TABLE logs ADD COLUMN sleep_hours REAL');
            await d.execute('ALTER TABLE logs ADD COLUMN readiness INTEGER');
            await d.execute('ALTER TABLE logs ADD COLUMN player_notes TEXT');
          }
          if (oldVersion < 3) {
            await d.execute('ALTER TABLE logs ADD COLUMN avg_power REAL');
            await d.execute('ALTER TABLE logs ADD COLUMN max_power REAL');
            await d.execute('ALTER TABLE logs ADD COLUMN duration_seconds INTEGER');
            await d.execute('ALTER TABLE logs ADD COLUMN distance INTEGER');
            await d.execute('''
              CREATE TABLE IF NOT EXISTS cp_tests(
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                player_id INTEGER,
                date TEXT,
                test_type TEXT,
                duration_seconds INTEGER,
                avg_power REAL,
                max_power REAL,
                distance INTEGER,
                avg_hr INTEGER,
                max_hr INTEGER,
                split_500 REAL,
                notes TEXT
              )
            ''');
            await d.execute('''
              CREATE TABLE IF NOT EXISTS cp_values(
                player_id INTEGER,
                date TEXT,
                cp REAL,
                w_prime REAL,
                method TEXT,
                PRIMARY KEY(player_id, date)
              )
            ''');
          }
        });
  }

  static Future<List<Map<String, Object?>>> q(String sql, [List<Object?>? a]) async =>
      (await db).rawQuery(sql, a);

  static Future<void> put(String table, Map<String, Object?> v) async =>
      (await db).insert(table, v, conflictAlgorithm: ConflictAlgorithm.replace);

  static Future<void> del(String table, String where, List<Object?> a) async =>
      (await db).delete(table, where: where, whereArgs: a);

  static Future<List<Map<String, Object?>>> sessions(String date) =>
      q('SELECT * FROM sessions WHERE date=? ORDER BY idx', [date]);

  // ==================== اختبارات CP ====================

  /// جلب جميع اختبارات CP للاعب
  static Future<List<Map<String, Object?>>> cpTests(int playerId) =>
      q('SELECT * FROM cp_tests WHERE player_id=? ORDER BY date DESC', [playerId]);

  /// إضافة اختبار CP
  static Future<void> addCPTest(Map<String, Object?> test) async {
    await (await db).insert('cp_tests', test);
  }

  /// حذف اختبار CP
  static Future<void> deleteCPTest(int testId) =>
      del('cp_tests', 'id=?', [testId]);

  /// جلب آخر قيمة CP محسوبة للاعب
  static Future<double?> playerCP(int playerId) async {
    final r = await q(
        'SELECT cp FROM cp_values WHERE player_id=? ORDER BY date DESC LIMIT 1',
        [playerId]);
    if (r.isEmpty) return null;
    return (r.first['cp'] as num?)?.toDouble();
  }

  /// جلب آخر قيمة W' للاعب
  static Future<double?> playerWPrime(int playerId) async {
    final r = await q(
        'SELECT w_prime FROM cp_values WHERE player_id=? ORDER BY date DESC LIMIT 1',
        [playerId]);
    if (r.isEmpty) return null;
    return (r.first['w_prime'] as num?)?.toDouble();
  }

  /// جلب سجل CP عبر الزمن للاعب
  static Future<List<Map<String, Object?>>> cpHistory(int playerId) =>
      q('SELECT * FROM cp_values WHERE player_id=? ORDER BY date', [playerId]);

  /// حساب وحفظ CP من الاختبارات المتاحة
  static Future<Map<String, double>> computeAndSaveCP(int playerId) async {
    final tests = await cpTests(playerId);
    if (tests.isEmpty) return {};

    // تجميع أحدث اختبار لكل مدة مختلفة
    final byDuration = <int, Map<String, Object?>>{};
    for (final t in tests) {
      final dur = t['duration_seconds'] as int;
      if (!byDuration.containsKey(dur)) {
        byDuration[dur] = t;
      }
    }

    final testList = byDuration.values
        .map((t) => {
              'duration_seconds': t['duration_seconds'] as int,
              'avg_power': (t['avg_power'] as num).toDouble(),
            })
        .toList();

    Map<String, double> result;
    String method;

    if (testList.length >= 2) {
      result = calculateCP(testList);
      method = testList.length >= 3 ? 'regression' : 'two_point';
    } else {
      // تقدير من اختبار واحد
      final t = testList.first;
      final estimated = estimateCPFromSingle(
          t['avg_power']!, t['duration_seconds'] as int);
      result = {'cp': estimated, 'w_prime': 0};
      method = 'estimated';
    }

    if (result.isNotEmpty && (result['cp'] ?? 0) > 0) {
      await put('cp_values', {
        'player_id': playerId,
        'date': dstr(DateTime.now()),
        'cp': result['cp'],
        'w_prime': result['w_prime'],
        'method': method,
      });
    }

    return result;
  }

  // ==================== تحليلات التمرين ====================

  /// جلب جميع سجلات لاعب مرتبة بالتاريخ
  static Future<List<Map<String, Object?>>> playerLogs(int playerId, {int limit = 90}) =>
      q('SELECT l.*, s.kind, s.zone FROM logs l LEFT JOIN sessions s ON l.date=s.date AND l.idx=s.idx WHERE l.player_id=? ORDER BY l.date DESC, l.idx DESC LIMIT ?',
          [playerId, limit]);

  /// جلب آخر سجل للاعب
  static Future<Map<String, Object?>?> latestLog(int playerId) async {
    final r = await q(
        'SELECT * FROM logs WHERE player_id=? ORDER BY date DESC, idx DESC LIMIT 1',
        [playerId]);
    return r.isEmpty ? null : r.first;
  }

  /// خط الأساس (متوسط آخر n يوم)
  static Future<Map<String, double>> playerBaseline(int playerId, {int days = 14}) async {
    final cutoff = dstr(DateTime.now().subtract(Duration(days: days)));
    final r = await q('''
      SELECT 
        AVG(rhr) as avg_rhr,
        AVG(hrv) as avg_hrv,
        AVG(hr) as avg_hr,
        AVG(weight) as avg_weight,
        AVG(fatigue) as avg_fatigue,
        AVG(sleep_hours) as avg_sleep,
        AVG(avg_power) as avg_power,
        MIN(rhr) as min_rhr,
        MAX(hrv) as max_hrv,
        COUNT(*) as count
      FROM logs 
      WHERE player_id=? AND date>=? AND rhr IS NOT NULL
    ''', [playerId, cutoff]);

    if (r.isEmpty || r.first['count'] == 0) return {};

    final row = r.first;
    return {
      'avg_rhr': (row['avg_rhr'] as num?)?.toDouble() ?? 0,
      'avg_hrv': (row['avg_hrv'] as num?)?.toDouble() ?? 0,
      'avg_hr': (row['avg_hr'] as num?)?.toDouble() ?? 0,
      'avg_weight': (row['avg_weight'] as num?)?.toDouble() ?? 0,
      'avg_fatigue': (row['avg_fatigue'] as num?)?.toDouble() ?? 0,
      'avg_sleep': (row['avg_sleep'] as num?)?.toDouble() ?? 0,
      'avg_power': (row['avg_power'] as num?)?.toDouble() ?? 0,
      'min_rhr': (row['min_rhr'] as num?)?.toDouble() ?? 0,
      'max_hrv': (row['max_hrv'] as num?)?.toDouble() ?? 0,
      'count': (row['count'] as num?)?.toDouble() ?? 0,
    };
  }

  /// بيانات الاستشفاء
  static Future<List<Map<String, dynamic>>> playerRecoveryData(int playerId, {int limit = 30}) async {
    final logs = await q('''
      SELECT date, hr, hr_post, hr_1min 
      FROM logs 
      WHERE player_id=? AND hr IS NOT NULL AND (hr_post IS NOT NULL OR hr_1min IS NOT NULL)
      ORDER BY date DESC 
      LIMIT ?
    ''', [playerId, limit]);

    return logs.map((l) {
      final hr = l['hr'] as int;
      final hrPost = l['hr_post'] as int?;
      final hr1min = l['hr_1min'] as int?;
      return {
        'date': l['date'],
        'hr': hr,
        'hr_post': hrPost,
        'hr_1min': hr1min,
        'recovery_rate_post': recoveryRate(hr, hrPost),
        'recovery_rate_1min': recoveryRate(hr, hr1min),
      };
    }).toList();
  }

  /// عدد الحصص
  static Future<int> playerSessionCount(int playerId, {int days = 7}) async {
    final cutoff = dstr(DateTime.now().subtract(Duration(days: days)));
    final r = await q(
        'SELECT COUNT(*) as c FROM logs WHERE player_id=? AND date>=?',
        [playerId, cutoff]);
    return (r.first['c'] as int?) ?? 0;
  }

  /// توزيع مناطق التدريب
  static Future<Map<String, int>> playerZoneDistribution(int playerId, {int days = 30}) async {
    final cutoff = dstr(DateTime.now().subtract(Duration(days: days)));
    final r = await q('''
      SELECT s.zone, COUNT(*) as c 
      FROM logs l 
      JOIN sessions s ON l.date=s.date AND l.idx=s.idx 
      WHERE l.player_id=? AND l.date>=?
      GROUP BY s.zone
    ''', [playerId, cutoff]);

    final dist = <String, int>{};
    for (final row in r) {
      dist[row['zone'] as String? ?? 'غير محدد'] = (row['c'] as int?) ?? 0;
    }
    return dist;
  }

  // ==================== PMC - Performance Management Chart ====================

  /// حساب مخطط إدارة الأداء (CTL, ATL, TSB) بناءً على CP
  /// هذا هو مقياس التوازن الرئيسي
  static Future<List<Map<String, dynamic>>> playerPMC(int playerId, {int days = 90}) async {
    final cp = await playerCP(playerId);
    if (cp == null || cp <= 0) return [];

    final startDate = DateTime.now().subtract(Duration(days: days));

    // جلب TSS اليومي من سجلات القدرة
    final logs = await q('''
      SELECT date, avg_power, duration_seconds
      FROM logs
      WHERE player_id=? AND date>=? AND avg_power IS NOT NULL AND duration_seconds IS NOT NULL
      ORDER BY date
    ''', [playerId, dstr(startDate)]);

    // تجميع TSS يومي
    final dailyTSS = <String, double>{};
    for (final l in logs) {
      final date = l['date'] as String;
      final power = (l['avg_power'] as num).toDouble();
      final duration = l['duration_seconds'] as int;
      final tss = calculateTSS(avgPower: power, durationSeconds: duration, cp: cp);
      dailyTSS[date] = (dailyTSS[date] ?? 0) + tss;
    }

    // حساب CTL و ATL و TSB
    double ctl = 0, atl = 0;
    final results = <Map<String, dynamic>>[];

    for (int d = 0; d <= days; d++) {
      final date = dstr(startDate.add(Duration(days: d)));
      final tss = dailyTSS[date] ?? 0;

      ctl = ctl + (tss - ctl) / 42; // الحمل المزمن (لياقة) - 42 يوم
      atl = atl + (tss - atl) / 7;  // الحمل الحاد (إجهاد) - 7 أيام
      final tsb = ctl - atl;         // توازن الضغط التدريبي

      results.add({
        'date': date,
        'tss': tss,
        'ctl': ctl,
        'atl': atl,
        'tsb': tsb,
      });
    }

    return results;
  }

  /// جلب آخر قيمة TSB (التوازن التدريبي) للاعب
  static Future<double?> playerTSB(int playerId) async {
    final pmc = await playerPMC(playerId, days: 50);
    if (pmc.isEmpty) return null;
    return pmc.last['tsb'] as double;
  }

  // ==================== التوازن الفسيولوجي (مبني على CP) ====================

  /// حساب مؤشرات التوازن - المحور الرئيسي هو CP
  static Future<Map<String, double>> physiologicalBalance(int playerId) async {
    final baseline = await playerBaseline(playerId, days: 28);
    final recent = await playerBaseline(playerId, days: 3);
    final recovery = await playerRecoveryData(playerId, limit: 10);
    final cp = await playerCP(playerId);
    final tsb = await playerTSB(playerId);

    final scores = <String, double>{
      'القدرة الحرجة CP': 50,     // المحور الرئيسي
      'التوازن التدريبي': 50,      // TSB
      'القلب والأوعية': 50,
      'التوازن العصبي': 50,
      'الاستشفاء': 50,
    };

    if (baseline.isEmpty || (baseline['count'] ?? 0) < 3) return scores;

    // ═══ 1. القدرة الحرجة - المحور الرئيسي ═══
    if (cp != null && cp > 0) {
      // تقييم بناءً على وجود CP وتطوره
      final cpHist = await cpHistory(playerId);
      if (cpHist.length >= 2) {
        final oldCP = (cpHist[cpHist.length - 2]['cp'] as num).toDouble();
        final currentCP = (cpHist.last['cp'] as num).toDouble();
        final improvement = ((currentCP - oldCP) / oldCP) * 100;
        // تحسن = درجة أعلى
        scores['القدرة الحرجة CP'] = (70 + improvement * 3).clamp(20, 100);
      } else {
        scores['القدرة الحرجة CP'] = 65; // يوجد CP لكن لا يوجد تاريخ للمقارنة
      }
    }

    // ═══ 2. التوازن التدريبي (TSB) - ثاني أهم محور ═══
    if (tsb != null) {
      // TSB المثالي للتدريب: -5 إلى 15
      // TSB المثالي للمنافسة: 10 إلى 25
      if (tsb > 25) {
        scores['التوازن التدريبي'] = 70; // مستريح أكثر من اللازم
      } else if (tsb > 5) {
        scores['التوازن التدريبي'] = 90; // مثالي
      } else if (tsb > -10) {
        scores['التوازن التدريبي'] = 75; // إجهاد بنّاء
      } else if (tsb > -25) {
        scores['التوازن التدريبي'] = 50; // إجهاد
      } else {
        scores['التوازن التدريبي'] = 25; // إفراط
      }
    }

    // ═══ 3. القلب والأوعية (RHR) ═══
    final rhrBase = baseline['avg_rhr'] ?? 0;
    final rhrRecent = recent.isNotEmpty ? (recent['avg_rhr'] ?? rhrBase) : rhrBase;
    if (rhrBase > 0) {
      final diff = rhrRecent - rhrBase;
      scores['القلب والأوعية'] = (85 - diff * 4).clamp(0, 100);
    }

    // ═══ 4. التوازن العصبي (HRV) ═══
    final hrvBase = baseline['avg_hrv'] ?? 0;
    final hrvRecent = recent.isNotEmpty ? (recent['avg_hrv'] ?? hrvBase) : hrvBase;
    if (hrvBase > 0) {
      final ratio = hrvRecent / hrvBase;
      scores['التوازن العصبي'] = (ratio * 80).clamp(0, 100);
    }

    // ═══ 5. الاستشفاء ═══
    if (recovery.isNotEmpty) {
      double totalRate = 0;
      int count = 0;
      for (final r in recovery) {
        final rate = (r['recovery_rate_post'] as double?) ??
            (r['recovery_rate_1min'] as double?);
        if (rate != null) {
          totalRate += rate;
          count++;
        }
      }
      if (count > 0) {
        scores['الاستشفاء'] = (totalRate / count * 4).clamp(0, 100);
      }
    }

    return scores;
  }

  // ==================== تنبيهات (محسّنة مع CP) ====================

  /// كشف مؤشرات الإفراط التدريبي - مع تحليل CP
  static Future<List<String>> overtrainingAlerts(int playerId) async {
    final alerts = <String>[];
    final baseline = await playerBaseline(playerId);
    if (baseline.isEmpty || (baseline['count'] ?? 0) < 3) return alerts;

    final recent = await playerBaseline(playerId, days: 3);
    if (recent.isEmpty || (recent['count'] ?? 0) < 1) return alerts;

    // 1. تحليل TSB (المقياس الرئيسي)
    final tsb = await playerTSB(playerId);
    if (tsb != null) {
      if (tsb < -30) {
        alerts.add('🔴 إفراط تدريبي! TSB = ${tsb.round()} — يحتاج راحة فورية');
      } else if (tsb < -15) {
        alerts.add('🟠 إجهاد تدريبي مرتفع (TSB = ${tsb.round()}) — خفف الحمل');
      } else if (tsb > 30) {
        alerts.add('🔵 فقدان لياقة محتمل (TSB = ${tsb.round()}) — ارفع الحمل');
      }
    }

    // 2. تراجع CP
    final cpHist = await cpHistory(playerId);
    if (cpHist.length >= 2) {
      final oldCP = (cpHist[cpHist.length - 2]['cp'] as num).toDouble();
      final currentCP = (cpHist.last['cp'] as num).toDouble();
      if (currentCP < oldCP * 0.95) {
        alerts.add('⚠️ تراجع في القدرة الحرجة (${oldCP.round()}W → ${currentCP.round()}W)');
      }
    }

    // 3. ارتفاع نبض الراحة
    final rhrDiff = (recent['avg_rhr'] ?? 0) - (baseline['avg_rhr'] ?? 0);
    if (rhrDiff > 5) {
      alerts.add('⚠️ نبض الراحة مرتفع +${rhrDiff.round()} عن المعتاد');
    }

    // 4. انخفاض HRV
    final hrvBase = baseline['avg_hrv'] ?? 0;
    final hrvRecent = recent['avg_hrv'] ?? 0;
    if (hrvBase > 0 && hrvRecent > 0 && hrvRecent / hrvBase < 0.7) {
      alerts.add('⚠️ HRV منخفض بشكل ملحوظ — علامة إجهاد');
    }

    // 5. إرهاق مزمن
    if ((recent['avg_fatigue'] ?? 0) >= 4) {
      alerts.add('⚠️ مستوى الإرهاق مرتفع باستمرار');
    }

    // 6. قلة نوم
    if ((recent['avg_sleep'] ?? 8) < 6) {
      alerts.add('⚠️ ساعات النوم أقل من 6');
    }

    return alerts;
  }

  // ==================== الصفحة الرئيسية ====================

  /// جاهزية جميع اللاعبين (مع TSB)
  static Future<List<Map<String, dynamic>>> allPlayersReadiness() async {
    final players = await q('SELECT * FROM players WHERE active=1 ORDER BY name');
    final results = <Map<String, dynamic>>[];

    for (final p in players) {
      final id = p['id'] as int;
      final latest = await latestLog(id);
      final baseline = await playerBaseline(id);
      final tsb = await playerTSB(id);
      final cp = await playerCP(id);

      double score = 70;
      if (latest != null || tsb != null) {
        score = calculateReadiness(
          rhr: latest?['rhr'] as int?,
          rhrBaseline: baseline.isNotEmpty ? baseline['avg_rhr'] : null,
          hrv: latest?['hrv'] as int?,
          hrvBaseline: baseline.isNotEmpty ? baseline['avg_hrv'] : null,
          fatigue: latest?['fatigue'] as int?,
          sleepHours: latest?['sleep_hours'] as double?,
          tsb: tsb,
        );
      }

      results.add({
        'player': p,
        'readiness': score,
        'latest': latest,
        'baseline': baseline,
        'tsb': tsb,
        'cp': cp,
        'has_data': latest != null,
      });
    }

    return results;
  }
}
