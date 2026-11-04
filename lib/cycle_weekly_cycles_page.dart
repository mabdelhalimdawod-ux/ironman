import 'package:flutter/material.dart';
import 'app_strings.dart';
import 'db.dart';
import 'day_sessions_page.dart';
import 'program_service.dart';

const Color _navy = Color(0xFF0D3B66);
const Color _sky = Color(0xFFE8F4FC);
const Color _gold = Color(0xFFFFC93C);

/// المستوى 2: صفحة الدورات التدريبية الأسبوعية (Basic & Secondary Weekly Cycles)
/// تنقسم إلى:
/// 1. الدورة التدريبية الأسبوعية الأساسية (تكراراتها، أيامها من السبت للجمعة، وتواريخ كل يوم مع تحول المنقضي للرمادي)
/// 2. الدورة التدريبية الأسبوعية الفرعية (تكراراتها، موعد الإرسال الأسبوعي، وأيامها)
/// 3. فحص ومطابقة إجمالي التكرارات مع أسابيع السيكل المحسوبة
class CycleWeeklyCyclesPage extends StatefulWidget {
  final ProgramCycle cycle;
  final VoidCallback onSaved;

  const CycleWeeklyCyclesPage({
    super.key,
    required this.cycle,
    required this.onSaved,
  });

  @override
  State<CycleWeeklyCyclesPage> createState() => _CycleWeeklyCyclesPageState();
}

class _CycleWeeklyCyclesPageState extends State<CycleWeeklyCyclesPage> {
  late ProgramCycle _cycle;
  bool _loading = true;

  // خريطة لتخزين زونات كل يوم: cycleType_dayOfWeek -> zoneSecondsMap
  final Map<String, Map<String, int>> _dayZoneCache = {};
  // خريطة لتخزين عدد الحصص التدريبية لكل يوم: cycleType_dayOfWeek -> count
  final Map<String, int> _daySessionCounts = {};

  @override
  void initState() {
    super.initState();
    _cycle = widget.cycle;
    _loadAllDayStats();
  }

  Future<void> _loadAllDayStats() async {
    setState(() => _loading = true);

    for (final cycleType in ['basic', 'secondary']) {
      for (int day = 0; day < 7; day++) {
        final key = '${cycleType}_$day';
        final sessions = await ProgramService.getDaySessionsDetailed(
            _cycle.id, cycleType, day);
        _daySessionCounts[key] = sessions.length;

        final zoneMap = await ProgramService.calculateDayZoneSeconds(
            _cycle.id, cycleType, day);
        _dayZoneCache[key] = zoneMap;
      }
    }

    if (mounted) setState(() => _loading = false);
  }

  Future<void> _updateCycleData() async {
    await ProgramService.updateProgramCycle(_cycle);
    widget.onSaved();
    if (mounted) setState(() {});
  }

  void _openDaySessions(String cycleType, int dayOfWeek, String dayName) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DaySessionsPage(
          cycleId: _cycle.id,
          cycleType: cycleType,
          dayOfWeek: dayOfWeek,
          dayName: '$dayName (${cycleType == 'basic' ? 'الدورة الأساسية' : 'الدورة الفرعية'})',
          onSaved: () {
            _loadAllDayStats();
            widget.onSaved();
          },
        ),
      ),
    );
  }

  void _showCommentDialog(String title, String initialText, ValueChanged<String> onSave) {
    final ctrl = TextEditingController(text: initialText);
    final s = AppStrings.of(context);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.comment_outlined, color: _navy),
            const SizedBox(width: 8),
            Text(title),
          ],
        ),
        content: TextField(
          controller: ctrl,
          maxLines: 4,
          decoration: const InputDecoration(
            hintText: 'اكتب التعليق هنا...',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(s.cancel),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: _navy, foregroundColor: Colors.white),
            onPressed: () {
              onSave(ctrl.text.trim());
              Navigator.pop(ctx);
            },
            child: Text(s.save),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final totalWeeks = _cycle.totalWeeks;
    final isRepsValid = _cycle.isRepsCountValid;

    return Scaffold(
      appBar: AppBar(
        title: Text('${_cycle.name} - ${s.trainingCycles}'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _navy))
          : ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              children: [
                // ── شريط التنبيه والتحقق من مجموع تكرارات الدورتين ──
                if (!isRepsValid)
                  Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.red.shade300, width: 1.2),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.warning_amber_rounded,
                            color: Colors.redAccent, size: 24),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '${s.repsMismatchWarning}\n(مجموع التكرارات الحالي: ${_cycle.sumConfiguredReps} • المطلوب: $totalWeeks أسابيع بناءً على تواريخ السيكل)',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: Colors.red.shade900,
                              fontWeight: FontWeight.bold,
                              height: 1.3,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                // ════════════════════════════════════════════════════════════
                // القسم الأول: الدورة التدريبية الأسبوعية الأساسية
                // ════════════════════════════════════════════════════════════
                _buildCycleSectionHeader(
                  title: s.basicWeeklyCycleTitle,
                  cycleType: 'basic',
                  repsValue: _cycle.basicReps,
                  onRepsChanged: (val) {
                    setState(() => _cycle.basicReps = val);
                    _updateCycleData();
                  },
                ),
                const SizedBox(height: 12),

                // لوحات أيام الأسبوع السبعة للدورة الأساسية
                ...List.generate(7, (day) {
                  return _buildDayPanel(
                    dayOfWeek: day,
                    cycleType: 'basic',
                    repsMultiplier: _cycle.basicReps,
                  );
                }),

                const SizedBox(height: 24),
                const Divider(thickness: 2),
                const SizedBox(height: 16),

                // ════════════════════════════════════════════════════════════
                // القسم الثاني: الدورة التدريبية الأسبوعية الفرعية
                // ════════════════════════════════════════════════════════════
                _buildCycleSectionHeader(
                  title: s.secondaryWeeklyCycleTitle,
                  cycleType: 'secondary',
                  repsValue: _cycle.secondaryReps,
                  onRepsChanged: (val) {
                    setState(() => _cycle.secondaryReps = val);
                    _updateCycleData();
                  },
                ),
                const SizedBox(height: 12),

                // لوحات أيام الأسبوع السبعة للدورة الفرعية
                ...List.generate(7, (day) {
                  return _buildDayPanel(
                    dayOfWeek: day,
                    cycleType: 'secondary',
                    repsMultiplier: _cycle.secondaryReps,
                  );
                }),
                const SizedBox(height: 30),
              ],
            ),
    );
  }

  /// رأس قسم الدورة الأسبوعية (الأساسية أو الفرعية)
  Widget _buildCycleSectionHeader({
    required String title,
    required String cycleType,
    required int repsValue,
    required ValueChanged<int> onRepsChanged,
  }) {
    final s = AppStrings.of(context);
    final isBasic = cycleType == 'basic';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isBasic ? _navy : const Color(0xFF164B7A),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _gold.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  isBasic ? Icons.repeat_rounded : Icons.flag_circle_rounded,
                  color: _gold,
                  size: 22,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // الحقول العلوية الخاصة بعدد التكرارات ومكان التدريب
          Wrap(
            spacing: 12,
            runSpacing: 10,
            children: [
              // خانة عدد التكرارات
              Container(
                width: 190,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Text(
                      'التكرارات:',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey.shade800),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<int>(
                          value: repsValue.clamp(1, 12),
                          isDense: true,
                          items: List.generate(12, (i) => i + 1).map((val) {
                            return DropdownMenuItem(
                              value: val,
                              child: Text('$val دورات',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold, fontSize: 13)),
                            );
                          }).toList(),
                          onChanged: (val) {
                            if (val != null) onRepsChanged(val);
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // خانة مكان التدريب
              Container(
                width: 250,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.place_outlined, size: 18, color: _navy),
                    const SizedBox(width: 6),
                    Expanded(
                      child: TextFormField(
                        initialValue: _cycle.location,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                        decoration: InputDecoration(
                          hintText: s.trainingLocationHint,
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                        onChanged: (val) {
                          _cycle.location = val.trim();
                          _updateCycleData();
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// لوحة اليوم التدريبي المجسمة بعرض الشاشة (السبت إلى الجمعة)
  Widget _buildDayPanel({
    required int dayOfWeek,
    required String cycleType,
    required int repsMultiplier,
  }) {
    final s = AppStrings.of(context);
    final dayName = s.isArabic
        ? ProgramService.weekDayNamesAr[dayOfWeek]
        : ProgramService.weekDayNamesEn[dayOfWeek];

    final key = '${cycleType}_$dayOfWeek';
    final sessionCount = _daySessionCounts[key] ?? 0;
    final dayZoneSeconds = _dayZoneCache[key] ?? {for (var z in kProgramZones) z: 0};

    // تواريخ هذا اليوم داخل السيكل
    final dates = ProgramService.getCycleDatesForDayOfWeek(
      _cycle.startDate,
      _cycle.endDate,
      dayOfWeek,
    );

    final today = DateTime.now();

    // إجمالي ثواني اليوم لحساب نسب المنحنى الشريطي
    final totalSecs = dayZoneSeconds.values.fold<int>(0, (a, b) => a + b);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade300, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.07),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── شريط رأس لوحة اليوم + زر (دخول) ──
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF0F3254),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(17)),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: _gold,
                  child: Text(
                    '${dayOfWeek + 1}',
                    style: const TextStyle(
                        color: _navy, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Row(
                    children: [
                      Text(
                        dayName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '$sessionCount ${sessionCount == 1 ? (s.isArabic ? "حصة" : "session") : (s.isArabic ? "حصص" : "sessions")}',
                          style: const TextStyle(
                              color: _gold,
                              fontSize: 11.5,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ),

                // ── زرار دخول أعلى لوحة كل يوم ──
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _gold,
                    foregroundColor: _navy,
                    elevation: 1,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: const Icon(Icons.login_rounded, size: 16),
                  label: Text(
                    s.enterCycle,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 13.5),
                  ),
                  onPressed: () => _openDaySessions(cycleType, dayOfWeek, dayName),
                ),
                const SizedBox(width: 6),

                // أيقونة التعليق
                IconButton(
                  icon: const Icon(Icons.comment_outlined,
                      color: Colors.white70, size: 20),
                  onPressed: () => _showCommentDialog(
                    'تعليق $dayName ($cycleType)',
                    '',
                    (val) {},
                  ),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── تواريخ هذا اليوم داخل السيكل مع تقادم المنقضي للرمادي ──
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        '${s.dayDatesInCycle} (${dates.length}):',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: dates.map((date) {
                          final isPast = date.isBefore(
                              DateTime(today.year, today.month, today.day));
                          final isToday = date.year == today.year &&
                              date.month == today.month &&
                              date.day == today.day;

                          return Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: isPast
                                  ? Colors.grey.shade200
                                  : (isToday ? _gold.withValues(alpha: 0.3) : _sky),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: isPast
                                    ? Colors.grey.shade400
                                    : (isToday ? _navy : _navy.withValues(alpha: 0.3)),
                                width: isToday ? 1.5 : 1,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  dstr(date),
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: isToday
                                        ? FontWeight.bold
                                        : FontWeight.w600,
                                    color: isPast
                                        ? Colors.grey.shade600
                                        : _navy,
                                    decoration: isPast
                                        ? TextDecoration.lineThrough
                                        : null,
                                  ),
                                ),
                                if (isPast) ...[
                                  const SizedBox(width: 4),
                                  Text(
                                    '(منقضي)',
                                    style: TextStyle(
                                        fontSize: 9.5,
                                        color: Colors.grey.shade600),
                                  ),
                                ],
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // ── الخانات الـ 6 المتجاورة لتوزيع الأحمال في الأسبوع الواحد ──
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    // الخانات الـ 6
                    Expanded(
                      flex: 4,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'أحمال الأسبوع الواحد (ثواني، دقائق، ساعات):',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Directionality(
                            textDirection: TextDirection.ltr,
                            child: Row(
                              children: kProgramZones.map((z) {
                                final secs = dayZoneSeconds[z] ?? 0;
                                final color = kZoneColors[z] ?? _navy;
                                final isZero = secs == 0;

                                return Expanded(
                                  child: Container(
                                    margin: const EdgeInsets.symmetric(
                                        horizontal: 2),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 3, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: isZero
                                          ? Colors.grey.shade100
                                          : color.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                        color: isZero
                                            ? Colors.grey.shade300
                                            : color.withValues(alpha: 0.7),
                                      ),
                                    ),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          z,
                                          style: TextStyle(
                                            fontSize: 9.5,
                                            fontWeight: FontWeight.bold,
                                            color: isZero
                                                ? Colors.grey.shade400
                                                : color,
                                          ),
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          isZero
                                              ? '-'
                                              : ProgramService
                                                  .formatDurationDetailed(secs),
                                          style: TextStyle(
                                            fontSize: 9.5,
                                            fontWeight: FontWeight.bold,
                                            color: isZero
                                                ? Colors.grey.shade400
                                                : Colors.black87,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),

                    // ── منحنى شريطي رأسي ملون لنسب الزونات ──
                    Container(
                      width: 100,
                      height: 52,
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: kProgramZones.map((z) {
                          final secs = dayZoneSeconds[z] ?? 0;
                          final fraction = totalSecs > 0
                              ? (secs / totalSecs).clamp(0.08, 1.0)
                              : 0.08;
                          final color = kZoneColors[z] ?? _navy;

                          return Expanded(
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 1.5),
                              child: Container(
                                height: 44 * fraction,
                                decoration: BoxDecoration(
                                  color: secs > 0
                                      ? color
                                      : Colors.grey.shade300,
                                  borderRadius: const BorderRadius.vertical(
                                      top: Radius.circular(3)),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
