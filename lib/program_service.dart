import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'db.dart';

// ============================================================================
// ثوابت ومناطق النبض والأنواع المعتمدة في تاب Program
// ============================================================================
const List<String> kProgramZones = [
  'Z1',
  'Z2',
  'Z3',
  'Z4',
  'Threshold',
  'Z5',
];

/// القائمة المنسدلة للزونات الـ 6 مع نسب النبض المحددة بالوصف
const List<String> kProgramZonesDetailed = [
  'zone1 = 55%:65%',
  'zone2 = 65%:75%',
  'zone3 = 75%:85%',
  'zone4 = 85%:90%',
  'Threshold = 90%:95%',
  'zone5 = 95%:100%',
];

/// خريطة مطابقة الزون إلى نسبة النبض
const Map<String, String> kZoneToHrPercentMap = {
  'zone1 = 55%:65%': '55%:65%',
  'zone2 = 65%:75%': '65%:75%',
  'zone3 = 75%:85%': '75%:85%',
  'zone4 = 85%:90%': '85%:90%',
  'Threshold = 90%:95%': '90%:95%',
  'zone5 = 95%:100%': '95%:100%',
  'zone1': '55%:65%',
  'zone2': '65%:75%',
  'zone3': '75%:85%',
  'zone4': '85%:90%',
  'Threshold': '90%:95%',
  'zone5': '95%:100%',
  'Z1': '55%:65%',
  'Z2': '65%:75%',
  'Z3': '75%:85%',
  'Z4': '85%:90%',
  'Z5': '95%:100%',
};

/// تحويل أي صيغة للزون إلى المفتاح الأساسي (Z1, Z2, Z3, Z4, Threshold, Z5)
String normalizeZoneKey(String rawZone) {
  if (rawZone.contains('zone1') || rawZone == 'Z1') return 'Z1';
  if (rawZone.contains('zone2') || rawZone == 'Z2') return 'Z2';
  if (rawZone.contains('zone3') || rawZone == 'Z3') return 'Z3';
  if (rawZone.contains('zone4') || rawZone == 'Z4') return 'Z4';
  if (rawZone.contains('Threshold')) return 'Threshold';
  if (rawZone.contains('zone5') || rawZone == 'Z5') return 'Z5';
  return 'Z2';
}

/// تحويل مفتاح الزون إلى النص الكامل المنسدل
String formatZoneToDetailed(String rawZone) {
  final norm = normalizeZoneKey(rawZone);
  switch (norm) {
    case 'Z1':
      return 'zone1 = 55%:65%';
    case 'Z2':
      return 'zone2 = 65%:75%';
    case 'Z3':
      return 'zone3 = 75%:85%';
    case 'Z4':
      return 'zone4 = 85%:90%';
    case 'Threshold':
      return 'Threshold = 90%:95%';
    case 'Z5':
      return 'zone5 = 95%:100%';
    default:
      return 'zone2 = 65%:75%';
  }
}

const List<String> kProgramWorkoutKinds = [
  'Stretch',
  'Fitness',
  'Mob',
  'bike',
  'Run',
  'Erg',
  'Row',
];

const List<String> kProgramTestTypes = [
  '500 m test',
  '750 m test',
  '1500 m test',
  '3000 m test',
];

const Map<String, Color> kZoneColors = {
  'Z1': Color(0xFFB8F229), // فسفوري خفيف
  'Z2': Color(0xFF2979FF), // أزرق متوسط
  'Z3': Color(0xFFFF9100), // برتقالي متوسط
  'Z4': Color(0xFFF4511E), // برتقالي غامق
  'Threshold': Color(0xFFE65100), // برتقالي غامق / عتبة
  'Z5': Color(0xFFFF5252), // أحمر خفيف
};

// ============================================================================
// نماذج البيانات (Data Models)
// ============================================================================

/// تمرين تفصيلي داخل حصة تدريبية (إحماء أو رئيسي أو تهدئة)
class ProgramWorkoutItem {
  final int? id;
  final int sessionId;
  final String section; // 'warmup' | 'main' | 'cooldown'
  final int itemIdx;
  String time;
  int durationMinutes;
  int durationSeconds;
  int hrPercent;
  String hrRange;
  int distanceMeters;
  int reps;
  String kind;
  String zone;
  String details;

  ProgramWorkoutItem({
    this.id,
    required this.sessionId,
    required this.section,
    required this.itemIdx,
    this.time = '07:00',
    this.durationMinutes = 10,
    this.durationSeconds = 0,
    this.hrPercent = 70,
    String? hrRange,
    this.distanceMeters = 2000,
    this.reps = 1,
    this.kind = 'Erg',
    this.zone = 'Z2',
    this.details = '',
  }) : hrRange = hrRange ?? (kZoneToHrPercentMap[zone] ?? '65%:75%');

  int get totalSeconds =>
      (durationMinutes * 60 + durationSeconds) * (reps > 0 ? reps : 1);

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'session_id': sessionId,
        'section': section,
        'item_idx': itemIdx,
        'time': time,
        'duration_minutes': durationMinutes,
        'duration_seconds': durationSeconds,
        'hr_percent': hrPercent,
        'hr_range': hrRange,
        'distance_meters': distanceMeters,
        'reps': reps,
        'kind': kind,
        'zone': zone,
        'details': details,
      };

  factory ProgramWorkoutItem.fromMap(Map<String, Object?> map) {
    final zoneStr = map['zone'] as String? ?? 'Z2';
    final savedHrRange = map['hr_range'] as String?;
    final hrRangeStr = (savedHrRange != null && savedHrRange.isNotEmpty)
        ? savedHrRange
        : (kZoneToHrPercentMap[zoneStr] ?? '65%:75%');

    return ProgramWorkoutItem(
      id: map['id'] as int?,
      sessionId: (map['session_id'] as num?)?.toInt() ?? 0,
      section: map['section'] as String? ?? 'main',
      itemIdx: (map['item_idx'] as num?)?.toInt() ?? 0,
      time: map['time'] as String? ?? '07:00',
      durationMinutes: (map['duration_minutes'] as num?)?.toInt() ?? 0,
      durationSeconds: (map['duration_seconds'] as num?)?.toInt() ?? 0,
      hrPercent: (map['hr_percent'] as num?)?.toInt() ?? 0,
      hrRange: hrRangeStr,
      distanceMeters: (map['distance_meters'] as num?)?.toInt() ?? 0,
      reps: (map['reps'] as num?)?.toInt() ?? 1,
      kind: map['kind'] as String? ?? 'Erg',
      zone: zoneStr,
      details: map['details'] as String? ?? '',
    );
  }
}

/// حصة تدريبية في يوم محدد
class ProgramDaySession {
  final int? id;
  final int cycleId;
  final String cycleType; // 'basic' | 'secondary'
  final int dayOfWeek; // 0: السبت ... 6: الجمعة
  final int sessionIdx;
  String name;
  String time;
  String notesPhysio;
  String notesTech;
  String comment;
  List<ProgramWorkoutItem> workouts;

  ProgramDaySession({
    this.id,
    required this.cycleId,
    required this.cycleType,
    required this.dayOfWeek,
    required this.sessionIdx,
    this.name = 'الحصة 1',
    this.time = '07:00',
    this.notesPhysio = '',
    this.notesTech = '',
    this.comment = '',
    List<ProgramWorkoutItem>? workouts,
  }) : workouts = workouts ?? [];

  List<ProgramWorkoutItem> get warmupItems =>
      workouts.where((w) => w.section == 'warmup').toList();
  List<ProgramWorkoutItem> get mainItems =>
      workouts.where((w) => w.section == 'main').toList();
  List<ProgramWorkoutItem> get cooldownItems =>
      workouts.where((w) => w.section == 'cooldown').toList();

  Map<String, int> get zoneDurations {
    final map = <String, int>{for (var z in kProgramZones) z: 0};
    for (final w in workouts) {
      final z = normalizeZoneKey(w.zone);
      map[z] = (map[z] ?? 0) + w.totalSeconds;
    }
    return map;
  }

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'cycle_id': cycleId,
        'cycle_type': cycleType,
        'day_of_week': dayOfWeek,
        'session_idx': sessionIdx,
        'name': name,
        'time': time,
        'notes_physio': notesPhysio,
        'notes_tech': notesTech,
        'comment': comment,
      };

  factory ProgramDaySession.fromMap(
          Map<String, Object?> map, List<ProgramWorkoutItem> workouts) =>
      ProgramDaySession(
        id: map['id'] as int?,
        cycleId: (map['cycle_id'] as num?)?.toInt() ?? 1,
        cycleType: map['cycle_type'] as String? ?? 'basic',
        dayOfWeek: (map['day_of_week'] as num?)?.toInt() ?? 0,
        sessionIdx: (map['session_idx'] as num?)?.toInt() ?? 0,
        name: map['name'] as String? ?? 'الحصة 1',
        time: map['time'] as String? ?? '07:00',
        notesPhysio: map['notes_physio'] as String? ?? '',
        notesTech: map['notes_tech'] as String? ?? '',
        comment: map['comment'] as String? ?? '',
        workouts: workouts,
      );
}

/// بيانات اختبارات السيكل الأربعة
class ProgramCycleTest {
  final int cycleId;
  final String testType;
  String testDate;
  String targetValue;
  bool isCompleted;

  ProgramCycleTest({
    required this.cycleId,
    required this.testType,
    this.testDate = '',
    this.targetValue = '',
    this.isCompleted = false,
  });

  Map<String, Object?> toMap() => {
        'cycle_id': cycleId,
        'test_type': testType,
        'test_date': testDate,
        'target_value': targetValue,
        'is_completed': isCompleted ? 1 : 0,
      };

  factory ProgramCycleTest.fromMap(Map<String, Object?> map) => ProgramCycleTest(
        cycleId: (map['cycle_id'] as num?)?.toInt() ?? 1,
        testType: map['test_type'] as String? ?? '500 m test',
        testDate: map['test_date'] as String? ?? '',
        targetValue: map['target_value'] as String? ?? '',
        isCompleted: (map['is_completed'] as int? ?? 0) == 1,
      );
}

/// بيانات تكوين اليوم التدريبي (المكان ومواعيد الإرسال)
class ProgramDayConfig {
  final int cycleId;
  final String cycleType;
  final int dayOfWeek;
  String location;
  String dispatchDate;
  String dispatchTime;
  String comment;

  ProgramDayConfig({
    required this.cycleId,
    required this.cycleType,
    required this.dayOfWeek,
    this.location = '',
    this.dispatchDate = '',
    this.dispatchTime = '06:00',
    this.comment = '',
  });

  Map<String, Object?> toMap() => {
        'cycle_id': cycleId,
        'cycle_type': cycleType,
        'day_of_week': dayOfWeek,
        'location': location,
        'dispatch_date': dispatchDate,
        'dispatch_time': dispatchTime,
        'comment': comment,
      };

  factory ProgramDayConfig.fromMap(Map<String, Object?> map) => ProgramDayConfig(
        cycleId: (map['cycle_id'] as num?)?.toInt() ?? 1,
        cycleType: map['cycle_type'] as String? ?? 'basic',
        dayOfWeek: (map['day_of_week'] as num?)?.toInt() ?? 0,
        location: map['location'] as String? ?? '',
        dispatchDate: map['dispatch_date'] as String? ?? '',
        dispatchTime: map['dispatch_time'] as String? ?? '06:00',
        comment: map['comment'] as String? ?? '',
      );
}

/// نموذج السيكل الكامل بالمستوى الأول
class ProgramCycle {
  final int id;
  String name;
  String startDate;
  String endDate;
  String location;
  String createdAt;
  String updatedAt;
  int basicReps;
  int secondaryReps;
  String notesPhysio;
  String notesTech;
  String comment;
  List<ProgramCycleTest> tests;

  ProgramCycle({
    required this.id,
    required this.name,
    required this.startDate,
    required this.endDate,
    this.location = 'مجرى التجديف الدولي',
    required this.createdAt,
    required this.updatedAt,
    this.basicReps = 3,
    this.secondaryReps = 1,
    this.notesPhysio = '',
    this.notesTech = '',
    this.comment = '',
    List<ProgramCycleTest>? tests,
  }) : tests = tests ?? [];

  /// حساب عدد الدورات الأسبوعية الكلية بالسيكل تلقائياً من التواريخ
  int get totalWeeks {
    final s = DateTime.tryParse(startDate) ?? DateTime.now();
    final e = DateTime.tryParse(endDate) ?? s.add(const Duration(days: 27));
    final days = e.difference(s).inDays + 1;
    return (days / 7).round().clamp(2, 12);
  }

  /// مجموع تكرارات الدورتين الأساسية والفرعية
  int get sumConfiguredReps => basicReps + secondaryReps;

  /// التحقق من مطابقة تكرارات المدرب مع إجمالي أسابيع السيكل
  bool get isRepsCountValid => sumConfiguredReps == totalWeeks;

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'start_date': startDate,
        'end_date': endDate,
        'location': location,
        'created_at': createdAt,
        'updated_at': updatedAt,
        'basic_reps': basicReps,
        'secondary_reps': secondaryReps,
        'notes_physio': notesPhysio,
        'notes_tech': notesTech,
        'comment': comment,
      };

  factory ProgramCycle.fromMap(
          Map<String, Object?> map, List<ProgramCycleTest> tests) =>
      ProgramCycle(
        id: map['id'] as int,
        name: map['name'] as String? ?? 'الدورة المرحلية 1',
        startDate: map['start_date'] as String? ?? dstr(DateTime.now()),
        endDate: map['end_date'] as String? ??
            dstr(DateTime.now().add(const Duration(days: 27))),
        location: map['location'] as String? ?? 'مجرى التجديف الدولي',
        createdAt: map['created_at'] as String? ?? DateTime.now().toIso8601String(),
        updatedAt: map['updated_at'] as String? ?? DateTime.now().toIso8601String(),
        basicReps: (map['basic_reps'] as num?)?.toInt() ?? 3,
        secondaryReps: (map['secondary_reps'] as num?)?.toInt() ?? 1,
        notesPhysio: map['notes_physio'] as String? ?? '',
        notesTech: map['notes_tech'] as String? ?? '',
        comment: map['comment'] as String? ?? '',
        tests: tests,
      );
}

// ============================================================================
// خدمة ProgramService المركزية
// ============================================================================
class ProgramService {
  static bool _initialized = false;

  static const List<String> workoutKinds = kProgramWorkoutKinds;
  static const List<String> targetZones = kProgramZones;

  static const List<String> weekDayNamesAr = [
    'السبت',
    'الأحد',
    'الإثنين',
    'الثلاثاء',
    'الأربعاء',
    'الخميس',
    'الجمعة',
  ];

  static const List<String> weekDayNamesEn = [
    'Saturday',
    'Sunday',
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
  ];

  /// تنسيق الثواني إلى ساعات ودقائق وثواني (مثال: 01:25:30 أو 45د 10ث)
  static String formatDurationDetailed(int totalSeconds) {
    if (totalSeconds <= 0) return '0ث';
    final hrs = totalSeconds ~/ 3600;
    final mins = (totalSeconds % 3600) ~/ 60;
    final secs = totalSeconds % 60;

    final parts = <String>[];
    if (hrs > 0) parts.add('${hrs}س');
    if (mins > 0) parts.add('${mins}د');
    if (secs > 0 || parts.isEmpty) parts.add('${secs}ث');
    return parts.join(' ');
  }

  /// إنشاء وتحديث الجداول في SQLite
  static Future<void> ensureTables() async {
    if (_initialized) return;
    final database = await DB.db;

    // 1. جدول السيكلات الموسع
    await database.execute('''
      CREATE TABLE IF NOT EXISTS program_cycles (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        start_date TEXT NOT NULL,
        end_date TEXT NOT NULL,
        location TEXT DEFAULT '',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        basic_reps INTEGER DEFAULT 3,
        secondary_reps INTEGER DEFAULT 1,
        notes_physio TEXT DEFAULT '',
        notes_tech TEXT DEFAULT '',
        comment TEXT DEFAULT ''
      )
    ''');

    // 2. جدول تستات السيكل
    await database.execute('''
      CREATE TABLE IF NOT EXISTS program_cycle_tests (
        cycle_id INTEGER NOT NULL,
        test_type TEXT NOT NULL,
        test_date TEXT DEFAULT '',
        target_value TEXT DEFAULT '',
        is_completed INTEGER DEFAULT 0,
        PRIMARY KEY (cycle_id, test_type)
      )
    ''');

    // 3. جدول إعدادات أيام الأسبوع (مكان وموعد الإرسال)
    await database.execute('''
      CREATE TABLE IF NOT EXISTS program_day_config (
        cycle_id INTEGER NOT NULL,
        cycle_type TEXT NOT NULL,
        day_of_week INTEGER NOT NULL,
        location TEXT DEFAULT '',
        dispatch_date TEXT DEFAULT '',
        dispatch_time TEXT DEFAULT '',
        comment TEXT DEFAULT '',
        PRIMARY KEY (cycle_id, cycle_type, day_of_week)
      )
    ''');

    // 4. جدول الحصص التدريبية
    await database.execute('''
      CREATE TABLE IF NOT EXISTS program_sessions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        cycle_id INTEGER NOT NULL,
        cycle_type TEXT NOT NULL,
        day_of_week INTEGER NOT NULL,
        session_idx INTEGER NOT NULL,
        name TEXT NOT NULL,
        time TEXT NOT NULL,
        notes_physio TEXT DEFAULT '',
        notes_tech TEXT DEFAULT '',
        comment TEXT DEFAULT ''
      )
    ''');

    // 5. جدول تفاصيل التمارين (إحماء، رئيسي، تهدئة)
    await database.execute('''
      CREATE TABLE IF NOT EXISTS program_workout_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id INTEGER NOT NULL,
        section TEXT NOT NULL,
        item_idx INTEGER NOT NULL,
        time TEXT DEFAULT '',
        duration_minutes INTEGER DEFAULT 0,
        duration_seconds INTEGER DEFAULT 0,
        hr_percent INTEGER DEFAULT 0,
        distance_meters INTEGER DEFAULT 0,
        reps INTEGER DEFAULT 1,
        kind TEXT DEFAULT 'Erg',
        zone TEXT DEFAULT 'Z2',
        details TEXT DEFAULT ''
      )
    ''');

    try {
      await database.execute('ALTER TABLE program_workout_items ADD COLUMN hr_range TEXT DEFAULT ""');
    } catch (_) {}

    // جدول sessions القديم للتوافق العكسي
    try {
      await database.execute('ALTER TABLE sessions ADD COLUMN time TEXT');
    } catch (_) {}

    // التأكد من تهيئة السيكل الأول
    await _ensureInitialCycleData();

    _initialized = true;
  }

  /// التأكد من وجود سيكل واحد فقط كبداية
  static Future<void> _ensureInitialCycleData() async {
    final database = await DB.db;
    final rows = await database.rawQuery('SELECT * FROM program_cycles ORDER BY id ASC');

    if (rows.isEmpty) {
      final now = DateTime.now();
      final start = now.subtract(const Duration(days: 7));
      final end = start.add(const Duration(days: 27)); // 4 أسابيع

      final id = await database.insert('program_cycles', {
        'name': 'الدورة المرحلية 1',
        'start_date': dstr(start),
        'end_date': dstr(end),
        'location': 'مجرى التجديف الدولي',
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
        'basic_reps': 3,
        'secondary_reps': 1,
        'notes_physio': 'ملاحظة فسيولوجية: التركيز على تحسين قاعدة التحمل الهوائي العام.',
        'notes_tech': 'ملاحظة فنية: تثبيت زاوية مسكة المجداف وديناميكية الدفع بالقدمين.',
        'comment': '',
      });

      // زراعة التستات الأربعة
      for (final t in kProgramTestTypes) {
        await database.insert('program_cycle_tests', {
          'cycle_id': id,
          'test_type': t,
          'test_date': dstr(end.subtract(const Duration(days: 3))),
          'target_value': t == '500 m test'
              ? '1:28.0'
              : (t == '750 m test'
                  ? '2:15.0'
                  : (t == '1500 m test' ? '4:45.0' : '9:50.0')),
          'is_completed': 0,
        });
      }

      // زراعة أيام تجريبية في الدورة الأساسية والفرعية
      await _seedDefaultCycleData(id);
    }
  }

  /// زراعة حصص تدريبية وتمارين افتراضية لسيكل جديد
  static Future<void> _seedDefaultCycleData(int cycleId) async {
    final database = await DB.db;

    // تهيئة الدورة التدريبية الأساسية
    for (int day = 0; day < 7; day++) {
      // إعدادات اليوم
      await database.insert(
        'program_day_config',
        {
          'cycle_id': cycleId,
          'cycle_type': 'basic',
          'day_of_week': day,
          'location': 'مجرى التجديف الدولي',
          'dispatch_date': '',
          'dispatch_time': '06:00',
          'comment': '',
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      // حصة 1 صباحية
      final s1Id = await database.insert('program_sessions', {
        'cycle_id': cycleId,
        'cycle_type': 'basic',
        'day_of_week': day,
        'session_idx': 0,
        'name': 'الحصة الصباحية',
        'time': '07:00',
        'notes_physio': 'مراقبة نبض الاستشفاء بعد التمرين',
        'notes_tech': 'إتقان سحب المقبض في خط مستقيم',
        'comment': '',
      });

      // إحماء
      await database.insert('program_workout_items', {
        'session_id': s1Id,
        'section': 'warmup',
        'item_idx': 0,
        'time': '07:00',
        'duration_minutes': 12,
        'duration_seconds': 0,
        'hr_percent': 60,
        'distance_meters': 2500,
        'reps': 1,
        'kind': 'Stretch',
        'zone': 'Z1',
        'details': 'إطالات ديناميكية وإحماء مفاصل',
      });

      // تمرين رئيسي
      await database.insert('program_workout_items', {
        'session_id': s1Id,
        'section': 'main',
        'item_idx': 0,
        'time': '07:20',
        'duration_minutes': 45,
        'duration_seconds': 0,
        'hr_percent': 75,
        'distance_meters': 10000,
        'reps': 1,
        'kind': 'Row',
        'zone': 'Z2',
        'details': 'تجديف مائي متواصل بسرعة ثابتة 18-20 spm',
      });

      // تهدئة
      await database.insert('program_workout_items', {
        'session_id': s1Id,
        'section': 'cooldown',
        'item_idx': 0,
        'time': '08:10',
        'duration_minutes': 10,
        'duration_seconds': 0,
        'hr_percent': 55,
        'distance_meters': 1500,
        'reps': 1,
        'kind': 'Mob',
        'zone': 'Z1',
        'details': 'تهدئة تدريجية وإطالات استشفائية',
      });

      // حصة 2 مسائية لبعض الأيام (السبت، الإثنين، الأربعاء)
      if (day == 0 || day == 2 || day == 4) {
        final s2Id = await database.insert('program_sessions', {
          'cycle_id': cycleId,
          'cycle_type': 'basic',
          'day_of_week': day,
          'session_idx': 1,
          'name': 'الحصة المسائية',
          'time': '16:30',
          'notes_physio': 'تركيز على الزون 3 وتحمل القوة',
          'notes_tech': 'تزامن عضلات الجذع مع الدفع',
          'comment': '',
        });

        await database.insert('program_workout_items', {
          'session_id': s2Id,
          'section': 'warmup',
          'item_idx': 0,
          'time': '16:30',
          'duration_minutes': 10,
          'duration_seconds': 0,
          'hr_percent': 65,
          'distance_meters': 2000,
          'reps': 1,
          'kind': 'bike',
          'zone': 'Z1',
          'details': 'دراجة إحماء هوائي خفيف',
        });

        await database.insert('program_workout_items', {
          'session_id': s2Id,
          'section': 'main',
          'item_idx': 0,
          'time': '16:45',
          'duration_minutes': 30,
          'duration_seconds': 0,
          'hr_percent': 85,
          'distance_meters': 6000,
          'reps': 3,
          'kind': 'Erg',
          'zone': 'Threshold',
          'details': 'فترات عتبة لاهوائية 3 × 10 دقائق',
        });

        await database.insert('program_workout_items', {
          'session_id': s2Id,
          'section': 'cooldown',
          'item_idx': 0,
          'time': '17:30',
          'duration_minutes': 8,
          'duration_seconds': 0,
          'hr_percent': 55,
          'distance_meters': 1000,
          'reps': 1,
          'kind': 'Stretch',
          'zone': 'Z1',
          'details': 'إطالات وإرخاء عضلات الظهر والأكتاف',
        });
      }
    }

    // تهيئة الدورة التدريبية الفرعية (تستات وتهدئة)
    for (int day = 0; day < 7; day++) {
      await database.insert(
        'program_day_config',
        {
          'cycle_id': cycleId,
          'cycle_type': 'secondary',
          'day_of_week': day,
          'location': 'مجرى التجديف الدولي',
          'dispatch_date': '',
          'dispatch_time': '06:00',
          'comment': '',
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      final sId = await database.insert('program_sessions', {
        'cycle_id': cycleId,
        'cycle_type': 'secondary',
        'day_of_week': day,
        'session_idx': 0,
        'name': 'حصة الاختبار والتهدئة',
        'time': '07:30',
        'notes_physio': 'أقصى طاقة هوائية ولاكتات',
        'notes_tech': 'سرعة انطلاقة وثبات سرعة التجديف',
        'comment': '',
      });

      await database.insert('program_workout_items', {
        'session_id': sId,
        'section': 'warmup',
        'item_idx': 0,
        'time': '07:30',
        'duration_minutes': 15,
        'duration_seconds': 0,
        'hr_percent': 65,
        'distance_meters': 3000,
        'reps': 1,
        'kind': 'Erg',
        'zone': 'Z2',
        'details': 'إحماء تدريجي مع سبيرنتات قصيرة',
      });

      await database.insert('program_workout_items', {
        'session_id': sId,
        'section': 'main',
        'item_idx': 0,
        'time': '07:50',
        'duration_minutes': 10,
        'duration_seconds': 0,
        'hr_percent': 95,
        'distance_meters': 2000,
        'reps': 1,
        'kind': 'Erg',
        'zone': 'Z5',
        'details': 'اختبار قدرة قصوى 2000م أقصى أداء',
      });

      await database.insert('program_workout_items', {
        'session_id': sId,
        'section': 'cooldown',
        'item_idx': 0,
        'time': '08:05',
        'duration_minutes': 15,
        'duration_seconds': 0,
        'hr_percent': 50,
        'distance_meters': 2000,
        'reps': 1,
        'kind': 'Stretch',
        'zone': 'Z1',
        'details': 'تهدئة هوائية واستشفاء مفاصل كامل',
      });
    }
  }

  // ============================================================================
  // دوال المستوى 1: إدارة السيكلات (Cycles)
  // ============================================================================

  /// جلب جميع السيكلات المسجلة
  static Future<List<ProgramCycle>> getAllProgramCycles() async {
    await ensureTables();
    final database = await DB.db;

    final rows =
        await database.rawQuery('SELECT * FROM program_cycles ORDER BY id ASC');

    final cycles = <ProgramCycle>[];
    for (final row in rows) {
      final id = row['id'] as int;
      final testRows = await database.rawQuery(
        'SELECT * FROM program_cycle_tests WHERE cycle_id = ? ORDER BY test_type ASC',
        [id],
      );
      final tests = testRows.map((t) => ProgramCycleTest.fromMap(t)).toList();
      cycles.add(ProgramCycle.fromMap(row, tests));
    }
    return cycles;
  }

  /// إضافة سيكل جديد بالكامل
  static Future<ProgramCycle> addProgramCycle() async {
    await ensureTables();
    final database = await DB.db;
    final existing = await getAllProgramCycles();

    int nextNum = 1;
    DateTime nextStart = DateTime.now();

    if (existing.isNotEmpty) {
      nextNum = existing.length + 1;
      final lastEnd = DateTime.tryParse(existing.last.endDate);
      if (lastEnd != null) {
        nextStart = lastEnd.add(const Duration(days: 1));
      }
    }
    final nextEnd = nextStart.add(const Duration(days: 27)); // 4 أسابيع

    final id = await database.insert('program_cycles', {
      'name': 'الدورة المرحلية $nextNum',
      'start_date': dstr(nextStart),
      'end_date': dstr(nextEnd),
      'location': existing.isNotEmpty ? existing.last.location : 'مجرى التجديف الدولي',
      'created_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
      'basic_reps': 3,
      'secondary_reps': 1,
      'notes_physio': '',
      'notes_tech': '',
      'comment': '',
    });

    for (final t in kProgramTestTypes) {
      await database.insert('program_cycle_tests', {
        'cycle_id': id,
        'test_type': t,
        'test_date': dstr(nextEnd.subtract(const Duration(days: 2))),
        'target_value': '',
        'is_completed': 0,
      });
    }

    await _seedDefaultCycleData(id);
    final all = await getAllProgramCycles();
    return all.firstWhere((c) => c.id == id);
  }

  /// تحديث بيانات سيكل
  static Future<void> updateProgramCycle(ProgramCycle cycle) async {
    await ensureTables();
    final database = await DB.db;

    await database.update(
      'program_cycles',
      {
        'name': cycle.name,
        'start_date': cycle.startDate,
        'end_date': cycle.endDate,
        'location': cycle.location,
        'updated_at': DateTime.now().toIso8601String(),
        'basic_reps': cycle.basicReps,
        'secondary_reps': cycle.secondaryReps,
        'notes_physio': cycle.notesPhysio,
        'notes_tech': cycle.notesTech,
        'comment': cycle.comment,
      },
      where: 'id = ?',
      whereArgs: [cycle.id],
    );

    // تحديث التستات
    for (final t in cycle.tests) {
      await database.insert(
        'program_cycle_tests',
        t.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  /// حذف سيكل
  static Future<bool> deleteProgramCycle(int cycleId) async {
    await ensureTables();
    final database = await DB.db;
    final cycles = await getAllProgramCycles();
    if (cycles.length <= 1) return false;

    await database.delete('program_cycles', where: 'id = ?', whereArgs: [cycleId]);
    await database.delete('program_cycle_tests', where: 'cycle_id = ?', whereArgs: [cycleId]);
    await database.delete('program_day_config', where: 'cycle_id = ?', whereArgs: [cycleId]);

    final sessionRows = await database.rawQuery(
      'SELECT id FROM program_sessions WHERE cycle_id = ?',
      [cycleId],
    );
    for (final s in sessionRows) {
      final sId = s['id'] as int;
      await database.delete('program_workout_items', where: 'session_id = ?', whereArgs: [sId]);
    }
    await database.delete('program_sessions', where: 'cycle_id = ?', whereArgs: [cycleId]);

    return true;
  }

  // ============================================================================
  // حسابات إجمالي الزونات في السيكل كاملاً (المستوى 1)
  // ============================================================================

  /// حساب ثواني كل زون في السيكل كاملاً:
  /// (زونات أسبوع الدورة الأساسية × عدد تكراراتها) + (زونات أسبوع الدورة الفرعية × عدد تكراراتها)
  static Future<Map<String, int>> calculateCycleTotalZoneSeconds(
      ProgramCycle cycle) async {
    await ensureTables();

    // 1. حساب زونات الأسبوع للدورة الأساسية
    final basicWeekZones = await calculateWeeklyCycleZoneSeconds(cycle.id, 'basic');

    // 2. حساب زونات الأسبوع للدورة الفرعية
    final secondaryWeekZones =
        await calculateWeeklyCycleZoneSeconds(cycle.id, 'secondary');

    final total = <String, int>{for (var z in kProgramZones) z: 0};

    for (final z in kProgramZones) {
      final b = (basicWeekZones[z] ?? 0) * cycle.basicReps;
      final s = (secondaryWeekZones[z] ?? 0) * cycle.secondaryReps;
      total[z] = b + s;
    }

    return total;
  }

  // ============================================================================
  // دوال المستوى 2: إدارة الدورات الأسبوعية الأساسية والفرعية والأيام
  // ============================================================================

  /// جلب إعدادات يوم معين
  static Future<ProgramDayConfig> getDayConfig(
      int cycleId, String cycleType, int dayOfWeek, String defaultLocation) async {
    await ensureTables();
    final database = await DB.db;

    final rows = await database.rawQuery(
      'SELECT * FROM program_day_config WHERE cycle_id = ? AND cycle_type = ? AND day_of_week = ?',
      [cycleId, cycleType, dayOfWeek],
    );

    if (rows.isNotEmpty) {
      return ProgramDayConfig.fromMap(rows.first);
    }

    return ProgramDayConfig(
      cycleId: cycleId,
      cycleType: cycleType,
      dayOfWeek: dayOfWeek,
      location: defaultLocation,
    );
  }

  /// حفظ إعدادات اليوم
  static Future<void> saveDayConfig(ProgramDayConfig config) async {
    await ensureTables();
    final database = await DB.db;

    await database.insert(
      'program_day_config',
      config.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// توليد قائمة تواريخ يوم معين في الأسبوع التي تقع داخل السيكل
  static List<DateTime> getCycleDatesForDayOfWeek(
      String startStr, String endStr, int dayOfWeek) {
    final start = DateTime.tryParse(startStr) ?? DateTime.now();
    final end = DateTime.tryParse(endStr) ?? start.add(const Duration(days: 27));

    final dates = <DateTime>[];
    DateTime cur = start;

    while (cur.isBefore(end) || cur.isAtSameMomentAs(end)) {
      if (getWeekdayIndex(cur) == dayOfWeek) {
        dates.add(cur);
      }
      cur = cur.add(const Duration(days: 1));
    }

    return dates;
  }

  /// حساب مجموع ثواني الزونات لأسبوع كامل في دورة معينة (أساسية أو فرعية)
  static Future<Map<String, int>> calculateWeeklyCycleZoneSeconds(
      int cycleId, String cycleType) async {
    await ensureTables();
    final total = <String, int>{for (var z in kProgramZones) z: 0};

    for (int day = 0; day < 7; day++) {
      final dayZones = await calculateDayZoneSeconds(cycleId, cycleType, day);
      for (final z in kProgramZones) {
        total[z] = (total[z] ?? 0) + (dayZones[z] ?? 0);
      }
    }

    return total;
  }

  /// حساب مجموع ثواني الزونات ليوم واحد فقط
  static Future<Map<String, int>> calculateDayZoneSeconds(
      int cycleId, String cycleType, int dayOfWeek) async {
    final sessions = await getDaySessionsDetailed(cycleId, cycleType, dayOfWeek);
    final dayMap = <String, int>{for (var z in kProgramZones) z: 0};

    for (final s in sessions) {
      final sMap = s.zoneDurations;
      for (final z in kProgramZones) {
        dayMap[z] = (dayMap[z] ?? 0) + (sMap[z] ?? 0);
      }
    }

    return dayMap;
  }

  // ============================================================================
  // دوال المستوى 3 & 4: الحصص التدريبية والتمارين التفصيلية
  // ============================================================================

  /// جلب الحصص التدريبية ليوم معين مع كامل التمارين
  static Future<List<ProgramDaySession>> getDaySessionsDetailed(
      int cycleId, String cycleType, int dayOfWeek) async {
    await ensureTables();
    final database = await DB.db;

    final sessionRows = await database.rawQuery(
      'SELECT * FROM program_sessions WHERE cycle_id = ? AND cycle_type = ? AND day_of_week = ? ORDER BY session_idx ASC',
      [cycleId, cycleType, dayOfWeek],
    );

    final sessions = <ProgramDaySession>[];
    for (final sRow in sessionRows) {
      final sId = sRow['id'] as int;
      final workoutRows = await database.rawQuery(
        'SELECT * FROM program_workout_items WHERE session_id = ? ORDER BY item_idx ASC',
        [sId],
      );
      final workouts =
          workoutRows.map((w) => ProgramWorkoutItem.fromMap(w)).toList();
      sessions.add(ProgramDaySession.fromMap(sRow, workouts));
    }

    return sessions;
  }

  /// تكرار اسم اللوحة السابقة مع زيادة رقمها التسلسلي (مثال: إحماء 1 -> إحماء 2 أو الحصة 1 -> الحصة 2)
  static String incrementBoardTitle(String? prevTitle, String defaultPrefix, int targetIndex) {
    if (prevTitle == null || prevTitle.trim().isEmpty) {
      return '$defaultPrefix $targetIndex';
    }
    final trimmed = prevTitle.trim();
    final regex = RegExp(r'^(.*?)\s*(\d+)$');
    final match = regex.firstMatch(trimmed);
    if (match != null) {
      final prefix = match.group(1)!.trim();
      final number = int.tryParse(match.group(2)!) ?? (targetIndex - 1);
      return '$prefix ${number + 1}';
    }
    return '$trimmed $targetIndex';
  }

  /// إضافة حصة تدريبية جديدة لليوم مع تكرار اسم الحصة السابقة وزيادة رقمها
  static Future<ProgramDaySession> addDaySessionDetailed(
      int cycleId, String cycleType, int dayOfWeek) async {
    await ensureTables();
    final database = await DB.db;
    final current = await getDaySessionsDetailed(cycleId, cycleType, dayOfWeek);

    final newIdx = current.length;
    final defaultTimes = ['07:00', '16:30', '11:00', '19:00'];
    final time = defaultTimes[newIdx.clamp(0, defaultTimes.length - 1)];
    final String name;
    if (current.isNotEmpty) {
      name = incrementBoardTitle(current.last.name, 'الحصة', newIdx + 1);
    } else {
      name = newIdx == 0
          ? 'الحصة الصباحية'
          : (newIdx == 1 ? 'الحصة المسائية' : 'الحصة ${newIdx + 1}');
    }

    final sId = await database.insert('program_sessions', {
      'cycle_id': cycleId,
      'cycle_type': cycleType,
      'day_of_week': dayOfWeek,
      'session_idx': newIdx,
      'name': name,
      'time': time,
      'notes_physio': '',
      'notes_tech': '',
      'comment': '',
    });

    // إضافة تمرين إحماء وتمرين رئيسي تلقائياً
    await database.insert('program_workout_items', {
      'session_id': sId,
      'section': 'warmup',
      'item_idx': 0,
      'time': time,
      'duration_minutes': 10,
      'duration_seconds': 0,
      'hr_percent': 60,
      'distance_meters': 2000,
      'reps': 1,
      'kind': 'Stretch',
      'zone': 'Z1',
      'details': '',
    });

    await database.insert('program_workout_items', {
      'session_id': sId,
      'section': 'main',
      'item_idx': 0,
      'time': time,
      'duration_minutes': 40,
      'duration_seconds': 0,
      'hr_percent': 75,
      'distance_meters': 8000,
      'reps': 1,
      'kind': 'Erg',
      'zone': 'Z2',
      'details': '',
    });

    final updated = await getDaySessionsDetailed(cycleId, cycleType, dayOfWeek);
    return updated.firstWhere((s) => s.id == sId);
  }

  /// حذف حصة تدريبية بالكامل
  static Future<void> deleteDaySessionDetailed(int sessionId) async {
    await ensureTables();
    final database = await DB.db;

    await database
        .delete('program_workout_items', where: 'session_id = ?', whereArgs: [sessionId]);
    await database
        .delete('program_sessions', where: 'id = ?', whereArgs: [sessionId]);
  }

  /// حفظ حصة تدريبية وتحديث تمارينها
  static Future<void> saveDaySessionDetailed(ProgramDaySession session) async {
    await ensureTables();
    final database = await DB.db;

    if (session.id != null) {
      await database.update(
        'program_sessions',
        {
          'name': session.name,
          'time': session.time,
          'notes_physio': session.notesPhysio,
          'notes_tech': session.notesTech,
          'comment': session.comment,
        },
        where: 'id = ?',
        whereArgs: [session.id],
      );

      // إعادة كتابة التمارين
      await database.delete('program_workout_items',
          where: 'session_id = ?', whereArgs: [session.id]);

      for (int i = 0; i < session.workouts.length; i++) {
        final w = session.workouts[i];
        await database.insert('program_workout_items', {
          'session_id': session.id,
          'section': w.section,
          'item_idx': i,
          'time': w.time,
          'duration_minutes': w.durationMinutes,
          'duration_seconds': w.durationSeconds,
          'hr_percent': w.hrPercent,
          'distance_meters': w.distanceMeters,
          'reps': w.reps,
          'kind': w.kind,
          'zone': w.zone,
          'details': w.details,
        });
      }
    }
  }

  // ============================================================================
  // دوال التوافق العكسي وتغذية جدول تمارين اليوم للرياضيين
  // ============================================================================

  static int getWeekdayIndex(DateTime date) {
    switch (date.weekday) {
      case DateTime.saturday:
        return 0;
      case DateTime.sunday:
        return 1;
      case DateTime.monday:
        return 2;
      case DateTime.tuesday:
        return 3;
      case DateTime.wednesday:
        return 4;
      case DateTime.thursday:
        return 5;
      case DateTime.friday:
        return 6;
      default:
        return 0;
    }
  }

  /// مزامنة تمارين اليوم لجدول sessions التابع لشاشة اللاعبين
  static Future<List<Map<String, Object?>>> syncSessionsForDate(DateTime date) async {
    await ensureTables();
    final dateStr = dstr(date);
    final cycles = await getAllProgramCycles();

    ProgramCycle? activeCycle;
    for (final c in cycles) {
      if (c.startDate.compareTo(dateStr) <= 0 && c.endDate.compareTo(dateStr) >= 0) {
        activeCycle = c;
        break;
      }
    }

    if (activeCycle == null) {
      return DB.sessions(dateStr);
    }

    final dayIndex = getWeekdayIndex(date);
    // نقرأ من الدورة الأساسية افتراضياً
    final daySessions =
        await getDaySessionsDetailed(activeCycle.id, 'basic', dayIndex);

    final currentSessions = await DB.sessions(dateStr);

    if (daySessions.isNotEmpty) {
      final flattenedWorkouts = <Map<String, Object?>>[];
      for (final s in daySessions) {
        for (final w in s.workouts) {
          flattenedWorkouts.add({
            'kind': w.kind,
            'zone': w.zone,
            'time': w.time.isNotEmpty ? w.time : s.time,
          });
        }
      }

      if (currentSessions.isEmpty || currentSessions.length != flattenedWorkouts.length) {
        final database = await DB.db;
        await database.delete('sessions', where: 'date = ?', whereArgs: [dateStr]);

        for (int i = 0; i < flattenedWorkouts.length; i++) {
          final item = flattenedWorkouts[i];
          await database.insert('sessions', {
            'date': dateStr,
            'idx': i,
            'kind': item['kind'],
            'zone': item['zone'],
            'time': item['time'],
          });
        }
      }
    }

    return DB.sessions(dateStr);
  }

  static Future<List<Map<String, Object?>>> getTodayWorkouts([DateTime? date]) async {
    return syncSessionsForDate(date ?? DateTime.now());
  }

  static Future<List<Map<String, Object?>>> getAllCycles() async {
    final cycles = await getAllProgramCycles();
    return cycles
        .map((c) => {
              'id': c.id,
              'name': c.name,
              'start': c.startDate,
              'end': c.endDate,
            })
        .toList();
  }

  static bool isCycleActive(Map<String, Object?> cycle, [DateTime? targetDate]) {
    final now = targetDate ?? DateTime.now();
    final todayStr = dstr(now);
    final start = cycle['start'] as String? ?? '';
    final end = cycle['end'] as String? ?? '';
    if (start.isEmpty || end.isEmpty) return false;
    return start.compareTo(todayStr) <= 0 && end.compareTo(todayStr) >= 0;
  }

  // --------------------------------------------------------------------------
  // دوال التوافق العكسي مع القوالب القديمة (WorkoutSlot & cycle_template_page)
  // --------------------------------------------------------------------------
  static Future<Map<String, Object?>?> getActiveCycle([DateTime? date]) async {
    final cycles = await getAllCycles();
    final now = date ?? DateTime.now();
    for (final c in cycles) {
      if (isCycleActive(c, now)) return c;
    }
    return cycles.isNotEmpty ? cycles.first : null;
  }

  static Future<List<WorkoutSlot>> getTemplateSlots(
      int cycleId, int dayOfWeek) async {
    await ensureTables();
    final database = await DB.db;
    try {
      final res = await database.rawQuery(
        'SELECT * FROM cycle_templates WHERE cycle_id = ? AND day_of_week = ? ORDER BY slot_idx ASC',
        [cycleId, dayOfWeek],
      );
      return res.map((r) => WorkoutSlot.fromMap(r)).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveTemplateSlots(
    int cycleId,
    int dayOfWeek,
    List<WorkoutSlot> slots,
  ) async {
    await ensureTables();
    final database = await DB.db;

    try {
      await database.execute('''
        CREATE TABLE IF NOT EXISTS cycle_templates (
          cycle_id INTEGER,
          day_of_week INTEGER,
          slot_idx INTEGER,
          kind TEXT,
          time TEXT,
          zone TEXT,
          PRIMARY KEY (cycle_id, day_of_week, slot_idx)
        )
      ''');

      await database.delete(
        'cycle_templates',
        where: 'cycle_id = ? AND day_of_week = ?',
        whereArgs: [cycleId, dayOfWeek],
      );

      final limited = slots.take(6).toList();
      for (int i = 0; i < limited.length; i++) {
        final s = WorkoutSlot(
          slotIdx: i,
          kind: limited[i].kind,
          time: limited[i].time,
          zone: limited[i].zone,
        );
        await database.insert('cycle_templates', s.toMap(cycleId, dayOfWeek));
      }
    } catch (_) {}

    final active = await getActiveCycle();
    if (active != null && active['id'] == cycleId) {
      await syncSessionsForDate(DateTime.now());
    }
  }
}

/// نموذج بيانات خانة التمرين للتوافق العكسي
class WorkoutSlot {
  final int slotIdx;
  final String kind;
  final String time;
  final String zone;

  const WorkoutSlot({
    required this.slotIdx,
    required this.kind,
    required this.time,
    required this.zone,
  });

  Map<String, Object?> toMap(int cycleId, int dayOfWeek) => {
        'cycle_id': cycleId,
        'day_of_week': dayOfWeek,
        'slot_idx': slotIdx,
        'kind': kind,
        'time': time,
        'zone': zone,
      };

  factory WorkoutSlot.fromMap(Map<String, Object?> map) => WorkoutSlot(
        slotIdx: (map['slot_idx'] as num?)?.toInt() ?? 0,
        kind: map['kind'] as String? ?? 'Erg',
        time: map['time'] as String? ?? '07:00',
        zone: map['zone'] as String? ?? 'Z2',
      );
}
