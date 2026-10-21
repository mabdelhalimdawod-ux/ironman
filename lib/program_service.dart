import 'package:sqflite/sqflite.dart';
import 'db.dart';

/// نموذج بيانات خانة التمرين في القالب الأسبوعي
class WorkoutSlot {
  final int slotIdx;
  final String kind; // 'إرج', 'ماء', 'جري', 'مرونة', 'قوة', 'لياقة'
  final String time; // ميعاد التمرين بالساعة مثل '06:00'
  final String zone; // 'Z1', 'Z2', 'Z3', 'Z4', 'Z5'

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

/// خدمة إدارة السيكلات والقالب الأسبوعي وتغذية جدول التمارين
class ProgramService {
  static bool _initialized = false;

  /// أنواع التمارين المعتمدة في المرحلة الثانية
  static const List<String> workoutKinds = [
    'إرج',
    'ماء',
    'جري',
    'مرونة',
    'قوة',
    'لياقة',
  ];

  /// مناطق النبض المستهدفة المعتمدة في القالب
  static const List<String> targetZones = ['Z1', 'Z2', 'Z3', 'Z4', 'Z5'];

  /// أيام الأسبوع بالترتيب (0: السبت، 1: الأحد، 2: الإثنين، 3: الثلاثاء، 4: الأربعاء، 5: الخميس، 6: الجمعة)
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

  /// تهيئة الجداول وحقول قاعدة البيانات إن لم تكن موجودة
  static Future<void> ensureTables() async {
    if (_initialized) return;
    final database = await DB.db;

    // 1. إضافة عمود time لجدول sessions إن لم يكن موجوداً
    try {
      await database.execute('ALTER TABLE sessions ADD COLUMN time TEXT');
    } catch (_) {}

    // 2. إنشاء جدول القوالب الأسبوعية للسيكلات
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

    // 3. التحقق من وجود 12 سيكل وتوليدها إن كانت فارغة
    await _ensure12Cycles();

    _initialized = true;
  }

  /// التحقق من تهيئة السيكلات من 1 إلى 12
  static Future<void> _ensure12Cycles() async {
    final existing = await DB.q('SELECT * FROM cycles ORDER BY id ASC');
    if (existing.length < 12) {
      final now = DateTime.now();
      // نبدأ بالسيكل الأول قبل أسبوعين بحيث يكون اليوم واقعاً داخل السيكل النشط حالياً
      DateTime curStart = now.subtract(const Duration(days: 10));

      for (int i = 1; i <= 12; i++) {
        final cycleName = 'السيكل $i';
        // مدة السيكل 4 أسابيع (28 يوم) كافتراضي مرن بين أسبوعين وستة أسابيع
        final curEnd = curStart.add(const Duration(days: 27));

        final already = existing.where((c) => (c['id'] == i || c['name'] == cycleName)).toList();
        if (already.isEmpty) {
          await DB.put('cycles', {
            'id': i,
            'name': cycleName,
            'start': dstr(curStart),
            'end': dstr(curEnd),
          });

          // ننشئ قالباً تدريبياً متكرراً افتراضياً لهذا السيكل
          await _seedDefaultTemplateForCycle(i);
        }

        curStart = curEnd.add(const Duration(days: 1));
      }
    }
  }

  /// قالب أسبوعي تجديفي نموذجي لكل سيكل (منوع بين إرج، ماء، جري، مرونة، قوة، لياقة)
  static Future<void> _seedDefaultTemplateForCycle(int cycleId) async {
    final defaultSchedule = <int, List<WorkoutSlot>>{
      0: [ // السبت: ماء صباحاً + قوة عصراً
        const WorkoutSlot(slotIdx: 0, kind: 'ماء', time: '07:00', zone: 'Z2'),
        const WorkoutSlot(slotIdx: 1, kind: 'قوة', time: '16:00', zone: 'Z3'),
      ],
      1: [ // الأحد: إرج صباحاً + مرونة
        const WorkoutSlot(slotIdx: 0, kind: 'إرج', time: '06:30', zone: 'Z2'),
        const WorkoutSlot(slotIdx: 1, kind: 'مرونة', time: '18:00', zone: 'Z1'),
      ],
      2: [ // الإثنين: ماء + لياقة
        const WorkoutSlot(slotIdx: 0, kind: 'ماء', time: '07:00', zone: 'Z3'),
        const WorkoutSlot(slotIdx: 1, kind: 'لياقة', time: '17:00', zone: 'Z4'),
      ],
      3: [ // الثلاثاء: جري صباحاً + إرج
        const WorkoutSlot(slotIdx: 0, kind: 'جري', time: '06:00', zone: 'Z2'),
        const WorkoutSlot(slotIdx: 1, kind: 'إرج', time: '16:30', zone: 'Z4'),
      ],
      4: [ // الأربعاء: ماء + قوة
        const WorkoutSlot(slotIdx: 0, kind: 'ماء', time: '07:00', zone: 'Z3'),
        const WorkoutSlot(slotIdx: 1, kind: 'قوة', time: '16:00', zone: 'Z3'),
      ],
      5: [ // الخميس: اختبار إرج Z5 + مرونة
        const WorkoutSlot(slotIdx: 0, kind: 'إرج', time: '07:00', zone: 'Z5'),
        const WorkoutSlot(slotIdx: 1, kind: 'مرونة', time: '17:00', zone: 'Z1'),
      ],
      6: [ // الجمعة: راحة أو تمرين خفيف Z1
        const WorkoutSlot(slotIdx: 0, kind: 'مرونة', time: '09:00', zone: 'Z1'),
      ],
    };

    final database = await DB.db;
    for (final entry in defaultSchedule.entries) {
      final day = entry.key;
      for (final slot in entry.value) {
        await database.insert(
          'cycle_templates',
          slot.toMap(cycleId, day),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    }
  }

  /// جلب جميع السيكلات الـ 12
  static Future<List<Map<String, Object?>>> getAllCycles() async {
    await ensureTables();
    return DB.q('SELECT * FROM cycles ORDER BY id ASC');
  }

  /// التحقق مما إذا كان السيكل نشطاً اليوم
  static bool isCycleActive(Map<String, Object?> cycle, [DateTime? targetDate]) {
    final now = targetDate ?? DateTime.now();
    final todayStr = dstr(now);
    final start = cycle['start'] as String? ?? '';
    final end = cycle['end'] as String? ?? '';
    return start.compareTo(todayStr) <= 0 && end.compareTo(todayStr) >= 0;
  }

  /// جلب السيكل النشط حالياً
  static Future<Map<String, Object?>?> getActiveCycle([DateTime? targetDate]) async {
    await ensureTables();
    final cycles = await getAllCycles();
    final now = targetDate ?? DateTime.now();
    for (final c in cycles) {
      if (isCycleActive(c, now)) return c;
    }
    return cycles.isNotEmpty ? cycles.first : null;
  }

  /// تحديث تواريخ سيكل معين (مع التحقق من شرط 2 إلى 6 أسابيع)
  static Future<bool> updateCycleDates({
    required int cycleId,
    required DateTime start,
    required DateTime end,
  }) async {
    await ensureTables();
    final days = end.difference(start).inDays + 1;
    // التحقق من مدة أسبوعين (14 يوم) إلى ستة أسابيع (42 يوم)
    if (days < 14 || days > 42) {
      return false;
    }

    await (await DB.db).update(
      'cycles',
      {'start': dstr(start), 'end': dstr(end)},
      where: 'id = ?',
      whereArgs: [cycleId],
    );
    return true;
  }

  /// تحويل تاريخ DateTime إلى رقم اليوم في الأسبوع الخاص بنا (0: السبت ... 6: الجمعة)
  static int getWeekdayIndex(DateTime date) {
    // في Dart: Monday = 1 ... Saturday = 6, Sunday = 7
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

  /// جلب خانات القالب الأسبوعي لسيكل ويوم محدد
  static Future<List<WorkoutSlot>> getTemplateSlots(int cycleId, int dayOfWeek) async {
    await ensureTables();
    final res = await DB.q(
      'SELECT * FROM cycle_templates WHERE cycle_id = ? AND day_of_week = ? ORDER BY slot_idx ASC',
      [cycleId, dayOfWeek],
    );
    return res.map((r) => WorkoutSlot.fromMap(r)).toList();
  }

  /// حفظ خانات القالب ليوم معين في سيكل (حتى 6 خانات كحد أقصى)
  static Future<void> saveTemplateSlots(
    int cycleId,
    int dayOfWeek,
    List<WorkoutSlot> slots,
  ) async {
    await ensureTables();
    final database = await DB.db;

    // حذف الخانات السابقة لهذا اليوم في هذا السيكل
    await database.delete(
      'cycle_templates',
      where: 'cycle_id = ? AND day_of_week = ?',
      whereArgs: [cycleId, dayOfWeek],
    );

    // إدراج الخانات بحد أقصى 6
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

    // مزامنة تلقائية لجدول التمارين لليوم إن كان السيكل نشطاً
    final active = await getActiveCycle();
    if (active != null && active['id'] == cycleId) {
      await syncSessionsForDate(DateTime.now());
    }
  }

  /// تغذية جدول sessions بالحصص التدريبية لليوم من قالب السيكل النشط تلقائياً
  static Future<List<Map<String, Object?>>> syncSessionsForDate(DateTime date) async {
    await ensureTables();
    final dateStr = dstr(date);
    final active = await getActiveCycle(date);
    if (active == null) {
      return DB.sessions(dateStr);
    }

    final cycleId = active['id'] as int;
    final dayIndex = getWeekdayIndex(date);
    final templateSlots = await getTemplateSlots(cycleId, dayIndex);

    // إذا وُجدت خانات في القالب، نضمن تواجدها في جدول sessions
    final currentSessions = await DB.sessions(dateStr);

    if (templateSlots.isNotEmpty) {
      // نتحقق إذا كانت الحصص الحالية مطابقة أو غير منشأة بعد
      if (currentSessions.isEmpty || currentSessions.length != templateSlots.length) {
        // حذف الحصص القديمة لهذا التاريخ وإعادة إنشائها من القالب
        final database = await DB.db;
        await database.delete('sessions', where: 'date = ?', whereArgs: [dateStr]);

        for (int i = 0; i < templateSlots.length; i++) {
          final slot = templateSlots[i];
          await database.insert('sessions', {
            'date': dateStr,
            'idx': i,
            'kind': slot.kind,
            'zone': slot.zone,
            'time': slot.time,
          });
        }
      }
    }

    return DB.sessions(dateStr);
  }

  /// جلب حصص اليوم بمواعيدها ونوعها وزونها
  static Future<List<Map<String, Object?>>> getTodayWorkouts([DateTime? date]) async {
    final target = date ?? DateTime.now();
    return syncSessionsForDate(target);
  }
}
