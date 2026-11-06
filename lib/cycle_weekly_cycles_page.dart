import 'package:flutter/material.dart';
import 'app_strings.dart';
import 'db.dart';
import 'day_sessions_page.dart';
import 'engine_rowing_ui.dart';
import 'program_service.dart';

const Color _navy = EngineRowingUI.bgNavy;
const Color _cardFill = EngineRowingUI.cardFill;
const Color _gold = EngineRowingUI.neonLime;
const Color _gridLine = EngineRowingUI.bgGridLine;

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
        backgroundColor: _cardFill,
        title: Row(
          children: [
            const Icon(Icons.comment_outlined, color: _gold),
            const SizedBox(width: 8),
            Text(title, style: const TextStyle(color: EngineRowingUI.textWhite)),
          ],
        ),
        content: TextField(
          controller: ctrl,
          maxLines: 4,
          style: const TextStyle(color: EngineRowingUI.textWhite),
          decoration: const InputDecoration(
            hintText: 'اكتب التعليق هنا...',
            hintStyle: TextStyle(color: EngineRowingUI.labelSlate),
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(s.cancel, style: const TextStyle(color: EngineRowingUI.labelSlate)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: _gold, foregroundColor: _navy),
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
      backgroundColor: _navy,
      appBar: AppBar(
        backgroundColor: _navy,
        foregroundColor: EngineRowingUI.textWhite,
        title: Text('${_cycle.name} - ${s.trainingCycles}'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _gold))
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 850),
                child: PinchZoomArea(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    children: [
                    // ── شريط التنبيه والتحقق من مجموع تكرارات الدورتين ──
                    if (!isRepsValid)
                      Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF280B14),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFFF5252), width: 1.2),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.warning_amber_rounded,
                                color: Color(0xFFFF5252), size: 24),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                '${s.repsMismatchWarning}\n(${s.isArabic ? "مجموع التكرارات الحالي:" : "Current configured reps:"} ${_cycle.sumConfiguredReps} • ${s.isArabic ? "المطلوب:" : "Required:"} $totalWeeks ${s.isArabic ? "أسابيع بناءً على تواريخ الدورة المرحلية" : "weeks based on phase cycle dates"})',
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  color: EngineRowingUI.textWhite,
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
                    const Divider(thickness: 1.5, color: _gridLine),
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
              ),
            ),
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
        color: _cardFill,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _gridLine, width: 1.2),
        boxShadow: const [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 10,
            offset: Offset(0, 4),
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
                  color: _gold.withAlpha(35),
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
                    color: EngineRowingUI.textWhite,
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
                  color: EngineRowingUI.equationCardFill,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _gridLine),
                ),
                child: Row(
                  children: [
                    const Text(
                      'التكرارات:',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: EngineRowingUI.labelSlate),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<int>(
                          value: repsValue.clamp(1, 12),
                          dropdownColor: _cardFill,
                          isDense: true,
                          items: List.generate(12, (i) => i + 1).map((val) {
                            return DropdownMenuItem(
                              value: val,
                              child: Directionality(
                                textDirection: TextDirection.ltr,
                                child: Text(
                                  '${RowingNumberFormatter.toEnglishDigits(val.toString())} cycles',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                      color: EngineRowingUI.textWhite),
                                ),
                              ),
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
                  color: EngineRowingUI.equationCardFill,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _gridLine),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.place_outlined, size: 18, color: _gold),
                    const SizedBox(width: 6),
                    Expanded(
                      child: TextFormField(
                        initialValue: _cycle.location,
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: EngineRowingUI.textWhite),
                        decoration: InputDecoration(
                          hintText: s.trainingLocationHint,
                          hintStyle: const TextStyle(
                              fontSize: 12, color: EngineRowingUI.captionGrey),
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

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: EngineRowingUI.neonGlowBoxDecoration(
        backgroundColor: _cardFill,
        borderColor: _gridLine,
        borderRadius: 14,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── شريط رأس لوحة اليوم + زر (دخول) ──
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              color: EngineRowingUI.equationCardFill,
              borderRadius: BorderRadius.vertical(top: Radius.circular(13)),
              border: Border(bottom: BorderSide(color: _gridLine, width: 1.0)),
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
                          color: EngineRowingUI.textWhite,
                          fontSize: 16.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: _navy,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: _gridLine),
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
                      color: EngineRowingUI.labelSlate, size: 20),
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
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: EngineRowingUI.labelSlate,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Directionality(
                        textDirection: TextDirection.ltr,
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
                                    ? EngineRowingUI.equationCardFill.withAlpha(90)
                                    : (isToday
                                        ? _gold.withAlpha(35)
                                        : EngineRowingUI.equationCardFill),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: isPast
                                      ? _gridLine
                                      : (isToday ? _gold : _gridLine),
                                  width: isToday ? 1.5 : 1,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    RowingNumberFormatter.toEnglishDigits(dstr(date)),
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: isToday
                                          ? FontWeight.bold
                                          : FontWeight.w600,
                                      color: isPast
                                          ? EngineRowingUI.captionGrey
                                          : (isToday
                                              ? _gold
                                              : EngineRowingUI.textWhite),
                                      decoration: isPast
                                          ? TextDecoration.lineThrough
                                          : null,
                                    ),
                                  ),
                                  if (isPast) ...[
                                    const SizedBox(width: 4),
                                    const Text(
                                      '(Past)',
                                      style: TextStyle(
                                          fontSize: 9.5,
                                          color: EngineRowingUI.captionGrey),
                                    ),
                                  ],
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // ── الخانات الـ 6 المتجاورة لتوزيع الأحمال في الأسبوع الواحد ──
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    // ── لوحة الزونات والكيرف المتجاوبة بالكامل لجميع الشاشات والموبايل مع الخلفية البيضاء للكيرف ──
                    RowingAdaptiveZoneBoxes(
                      zoneTotals: dayZoneSeconds,
                      title: s.isArabic
                          ? 'أحمال الأسبوع الواحد (ثواني، دقائق، ساعات):'
                          : 'Weekly Microcycle Zone Loads:',
                      curveTitle: s.zoneParticipationTitle,
                      formatDuration: (secs) =>
                          ProgramService.formatDurationDetailed(secs),
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
