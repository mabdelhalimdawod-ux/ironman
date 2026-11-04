import 'package:flutter/material.dart';
import 'app_strings.dart';
import 'db.dart';
import 'program_service.dart';
import 'cycle_weekly_cycles_page.dart';

const Color _navy = Color(0xFF0D3B66);
const Color _sky = Color(0xFFE8F4FC);
const Color _gold = Color(0xFFFFC93C);

/// المستوى 1: صفحة السيكلات لتاب Program (Cycles Page)
/// - مخصصة للمدربين
/// - تبدأ بسيكل واحدة (السيكل 1) مع زر (+) لإضافة سيكل جديد
/// - كارت السيكل مجسم عريض بعرض الشاشة مع:
///   1. تواريخ السيكل (من تاريخ - إلى تاريخ)
///   2. حساب عدد الدورات الأسبوعية تلقائياً
///   3. مكان أو منطقة التدريب
///   4. تاريخ الإنشاء وتاريخ آخر تعديل تلقائياً
///   5. الـ 6 خانات زونات المتجاورة (Z1, Z2, Z3, Z4, Threshold, Z5)
///   6. 4 خانات للتستات (500m, 750m, 1500m, 3000m) مع Checkbox
///   7. منحنى شريطي طولي رأسي لنسب مشاركة كل زون
///   8. زر (دخول) في المنتصف
///   9. ملاحظات فسيولوجية وفنية (+)
class ProgramTab extends StatefulWidget {
  const ProgramTab({super.key});

  @override
  State<ProgramTab> createState() => _ProgramTabState();
}

class _ProgramTabState extends State<ProgramTab> {
  List<ProgramCycle> _cycles = [];
  bool _loading = true;

  // كاش إجمالي ثواني الزونات لكل سيكل: cycleId -> map
  final Map<int, Map<String, int>> _cycleZoneTotals = {};

  @override
  void initState() {
    super.initState();
    _loadCycles();
  }

  Future<void> _loadCycles() async {
    setState(() => _loading = true);
    await ProgramService.ensureTables();
    _cycles = await ProgramService.getAllProgramCycles();

    _cycleZoneTotals.clear();
    for (final c in _cycles) {
      final totals = await ProgramService.calculateCycleTotalZoneSeconds(c);
      _cycleZoneTotals[c.id] = totals;
    }

    if (mounted) setState(() => _loading = false);
  }

  Future<void> _addNewCycle() async {
    final s = AppStrings.of(context);
    try {
      final newCycle = await ProgramService.addProgramCycle();
      await _loadCycles();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 8),
                Text('${s.cycleAddedSuccess}: ${newCycle.name}'),
              ],
            ),
            backgroundColor: Colors.green.shade700,
          ),
        );
      }
    } catch (_) {}
  }

  Future<void> _deleteCycle(ProgramCycle cycle) async {
    final s = AppStrings.of(context);
    if (_cycles.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(s.cannotDeleteLastCycle),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.deleteCycle),
        content: Text('${cycle.name}: ${s.deleteCycleConfirm}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(s.cancel),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(s.delete),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ProgramService.deleteProgramCycle(cycle.id);
      await _loadCycles();
    }
  }

  Future<void> _pickCycleDates(ProgramCycle cycle) async {
    DateTime selectedStart = DateTime.tryParse(cycle.startDate) ?? DateTime.now();
    DateTime selectedEnd =
        DateTime.tryParse(cycle.endDate) ?? selectedStart.add(const Duration(days: 27));

    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: DateTimeRange(start: selectedStart, end: selectedEnd),
      firstDate: DateTime(2024),
      lastDate: DateTime(2035),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(
            primary: _navy,
            secondary: _gold,
          ),
        ),
        child: child!,
      ),
    );

    if (picked != null) {
      final days = picked.end.difference(picked.start).inDays + 1;
      if (days < 14 || days > 84) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('مدة السيكل يجب ألا تقل عن أسبوعين (14 يوم)'),
            backgroundColor: Colors.redAccent,
          ),
        );
        return;
      }

      setState(() {
        cycle.startDate = dstr(picked.start);
        cycle.endDate = dstr(picked.end);
      });
      await ProgramService.updateProgramCycle(cycle);
      await _loadCycles();
    }
  }

  void _showCommentDialog(ProgramCycle cycle) {
    final ctrl = TextEditingController(text: cycle.comment);
    final s = AppStrings.of(context);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.comment_outlined, color: _navy),
            const SizedBox(width: 8),
            Text('${s.comment} - ${cycle.name}'),
          ],
        ),
        content: TextField(
          controller: ctrl,
          maxLines: 4,
          decoration: const InputDecoration(
            hintText: 'اكتب تعليق أو ملاحظات عامة حول هذا السيكل...',
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
            onPressed: () async {
              setState(() => cycle.comment = ctrl.text.trim());
              await ProgramService.updateProgramCycle(cycle);
              Navigator.pop(ctx);
            },
            child: Text(s.save),
          ),
        ],
      ),
    );
  }

  void _showNoteDialog(ProgramCycle cycle, bool isPhysio) {
    final s = AppStrings.of(context);
    final title = isPhysio ? s.physiologicalNote : s.technicalNote;
    final ctrl = TextEditingController(
        text: isPhysio ? cycle.notesPhysio : cycle.notesTech);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(isPhysio ? Icons.health_and_safety_outlined : Icons.engineering_outlined,
                color: _navy),
            const SizedBox(width: 8),
            Text('$title - ${cycle.name}'),
          ],
        ),
        content: TextField(
          controller: ctrl,
          maxLines: 4,
          decoration: InputDecoration(
            hintText: 'اكتب تفاصيل $title...',
            border: const OutlineInputBorder(),
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
            onPressed: () async {
              if (isPhysio) {
                cycle.notesPhysio = ctrl.text.trim();
              } else {
                cycle.notesTech = ctrl.text.trim();
              }
              await ProgramService.updateProgramCycle(cycle);
              if (mounted) setState(() {});
              Navigator.pop(ctx);
            },
            child: Text(s.save),
          ),
        ],
      ),
    );
  }

  void _openCycleWeeklyCycles(ProgramCycle cycle) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CycleWeeklyCyclesPage(
          cycle: cycle,
          onSaved: () => _loadCycles(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);

    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: _navy));
    }

    return RefreshIndicator(
      onRefresh: _loadCycles,
      color: _navy,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        children: [
          // ── شريط رأس تاب Program مع زرار (+) لإضافة سيكل جديد ──
          _buildHeaderBar(s),
          const SizedBox(height: 18),

          // ── كروت السيكلات المجسمة ──
          ..._cycles.map((c) => _buildCyclePanel(s, c)),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  /// رأس الصفحة التعريفي لتاب Program مع الصورة والزرار (+)
  Widget _buildHeaderBar(AppStrings s) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade300, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          // أيقونة / صورة تاب Program
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: _navy,
              borderRadius: BorderRadius.circular(14),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.asset(
                'assets/images/program_tab_icon.png',
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const Icon(
                  Icons.event_repeat_rounded,
                  color: _gold,
                  size: 28,
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      s.trainingCycles,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: _navy,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: _navy.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'لوحة المدربين',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: _navy),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  'تخطيط السيكلات والدورات التدريبية وحسابات الزونات الستة والتستات',
                  style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),

          // ── زرار علامة (+) لإضافة تاب سيكل كامل جديد ──
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: _navy,
              foregroundColor: _gold,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              elevation: 2,
            ),
            icon: const Icon(Icons.add_circle, color: _gold, size: 20),
            label: Text(
              s.addCycle,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
            ),
            onPressed: _addNewCycle,
          ),
        ],
      ),
    );
  }

  /// كارت لوحة السيكل المجسمة بعرض الشاشة بكامل مواصفات الوصف
  Widget _buildCyclePanel(AppStrings s, ProgramCycle cycle) {
    final zoneTotals = _cycleZoneTotals[cycle.id] ??
        {for (var z in kProgramZones) z: 0};
    final totalAllSecs =
        zoneTotals.values.fold<int>(0, (a, b) => a + b);

    final createdDateStr = cycle.createdAt.length >= 10
        ? cycle.createdAt.substring(0, 10)
        : cycle.createdAt;
    final updatedDateStr = cycle.updatedAt.length >= 10
        ? cycle.updatedAt.substring(0, 10)
        : cycle.updatedAt;

    return Container(
      margin: const EdgeInsets.only(bottom: 22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _navy.withValues(alpha: 0.25), width: 1.4),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── رأس لوحة السيكل (العنوان + زر الحذف + أيقونة الكومنت) ──
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: const BoxDecoration(
              color: _navy,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: _gold,
                  child: Text(
                    '${cycle.id}',
                    style: const TextStyle(
                        color: _navy, fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    cycle.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),

                // زر الكومنت
                IconButton(
                  tooltip: s.comment,
                  icon: Icon(
                    cycle.comment.isNotEmpty
                        ? Icons.comment_rounded
                        : Icons.mode_comment_outlined,
                    color: cycle.comment.isNotEmpty ? _gold : Colors.white70,
                    size: 22,
                  ),
                  onPressed: () => _showCommentDialog(cycle),
                ),
                const SizedBox(width: 6),

                // زر حذف السيكل
                if (_cycles.length > 1)
                  IconButton(
                    tooltip: s.deleteCycle,
                    icon: const Icon(Icons.delete_outline_rounded,
                        color: Colors.white70, size: 22),
                    onPressed: () => _deleteCycle(cycle),
                  ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── 1. مجموعة مدخلات الصدر: التواريخ + الأسابيع تلقائياً + مكان التدريب + تواريخ الإنشاء ──
                Wrap(
                  spacing: 12,
                  runSpacing: 10,
                  children: [
                    // خانة تاريخ السيكل (من تاريخ - إلى تاريخ)
                    InkWell(
                      onTap: () => _pickCycleDates(cycle),
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: _sky,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: _navy.withValues(alpha: 0.25)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.date_range_rounded,
                                size: 18, color: _navy),
                            const SizedBox(width: 8),
                            Text(
                              '${cycle.startDate} ➔ ${cycle.endDate}',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12.5,
                                  color: _navy),
                            ),
                            const SizedBox(width: 6),
                            const Icon(Icons.edit, size: 14, color: _navy),
                          ],
                        ),
                      ),
                    ),

                    // خانة حساب عدد الدورات الأسبوعية تلقائياً (لا يسمح فيها بالتسجيل اليدوي)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.green.shade300),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.auto_awesome_rounded,
                              size: 16, color: Colors.green.shade800),
                          const SizedBox(width: 6),
                          Text(
                            '${s.weeksCountCalculated}: ${cycle.totalWeeks} أسابيع (تلقائي)',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.green.shade900,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // خانة مكان أو منطقة التدريب (تضاف وتعدل يدوياً من المدرب)
                    Container(
                      width: 240,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.place_outlined,
                              size: 18, color: _navy),
                          const SizedBox(width: 6),
                          Expanded(
                            child: TextFormField(
                              initialValue: cycle.location,
                              style: const TextStyle(
                                  fontSize: 12, fontWeight: FontWeight.w600),
                              decoration: InputDecoration(
                                labelText: s.trainingLocation,
                                labelStyle: const TextStyle(fontSize: 11),
                                border: InputBorder.none,
                                isDense: true,
                              ),
                              onChanged: (val) {
                                cycle.location = val.trim();
                                ProgramService.updateProgramCycle(cycle);
                              },
                            ),
                          ),
                        ],
                      ),
                    ),

                    // خانات تاريخ الإنشاء وآخر تعديل (تلقائية)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'أنشئ: $createdDateStr • عُدل: $updatedDateStr',
                        style: TextStyle(
                            fontSize: 11, color: Colors.grey.shade700),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(height: 1),
                const SizedBox(height: 14),

                // ── 2. أربع خانات التستات الأربعة (500m, 750m, 1500m, 3000m) مع Checkbox ──
                Text(
                  s.testDatesTitle,
                  style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.bold,
                      color: _navy),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  children: kProgramTestTypes.map((testType) {
                    final testItem = cycle.tests.firstWhere(
                      (t) => t.testType == testType,
                      orElse: () => ProgramCycleTest(
                        cycleId: cycle.id,
                        testType: testType,
                        testDate: cycle.endDate,
                        targetValue: '',
                        isCompleted: false,
                      ),
                    );

                    return Container(
                      width: 175,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 6),
                      decoration: BoxDecoration(
                        color: testItem.isCompleted
                            ? Colors.green.shade50
                            : const Color(0xFFFBFDFE),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: testItem.isCompleted
                              ? Colors.green.shade400
                              : Colors.grey.shade300,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              SizedBox(
                                width: 20,
                                height: 20,
                                child: Checkbox(
                                  value: testItem.isCompleted,
                                  activeColor: Colors.green.shade700,
                                  onChanged: (val) {
                                    setState(() {
                                      testItem.isCompleted = val ?? false;
                                    });
                                    ProgramService.updateProgramCycle(cycle);
                                  },
                                ),
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  testType,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 11.5,
                                    color: testItem.isCompleted
                                        ? Colors.green.shade900
                                        : _navy,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          // إدخال قيمة التست المستهدفة
                          TextFormField(
                            initialValue: testItem.targetValue,
                            style: const TextStyle(fontSize: 11),
                            decoration: const InputDecoration(
                              hintText: 'الزمن أو الواط المستهدف...',
                              hintStyle: TextStyle(fontSize: 10),
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 4),
                              border: OutlineInputBorder(),
                            ),
                            onChanged: (val) {
                              testItem.targetValue = val.trim();
                              ProgramService.updateProgramCycle(cycle);
                            },
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 18),

                // ── 3. الـ 6 خانات للزونات + المنحنى الشريطي الرأسي لنسب المشاركة ──
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    // الـ 6 خانات متجاورة تبدأ من اليسار (Z1, Z2, Z3, Z4, Threshold, Z5)
                    Expanded(
                      flex: 4,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'إجمالي أحمال الزونات بالسيكل (أساسي × تكرارات + فرعي):',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 8),

                          Directionality(
                            textDirection: TextDirection.ltr,
                            child: Row(
                              children: kProgramZones.map((z) {
                                final secs = zoneTotals[z] ?? 0;
                                final color = kZoneColors[z] ?? _navy;
                                final isZero = secs == 0;

                                return Expanded(
                                  child: Container(
                                    margin: const EdgeInsets.symmetric(
                                        horizontal: 2.5),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 4, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: isZero
                                          ? Colors.grey.shade100
                                          : color.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: isZero
                                            ? Colors.grey.shade300
                                            : color,
                                        width: isZero ? 1 : 1.5,
                                      ),
                                    ),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          z,
                                          style: TextStyle(
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.bold,
                                            color: isZero
                                                ? Colors.grey.shade400
                                                : color,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          isZero
                                              ? '-'
                                              : ProgramService
                                                  .formatDurationDetailed(secs),
                                          style: TextStyle(
                                            fontSize: 10,
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
                    const SizedBox(width: 14),

                    // ── المنحنى الرسومي الشريطي الرأسي الملون لكل زون (على الجانب الأيسر) ──
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(
                          s.zoneParticipationTitle,
                          style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey.shade700),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          width: 120,
                          height: 64,
                          padding: const EdgeInsets.all(5),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: kProgramZones.map((z) {
                              final secs = zoneTotals[z] ?? 0;
                              final fraction = totalAllSecs > 0
                                  ? (secs / totalAllSecs).clamp(0.08, 1.0)
                                  : 0.08;
                              final color = kZoneColors[z] ?? _navy;

                              return Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 1.5),
                                  child: Tooltip(
                                    message:
                                        '$z: ${totalAllSecs > 0 ? ((secs / totalAllSecs) * 100).toStringAsFixed(1) : 0}%',
                                    child: Container(
                                      height: 52 * fraction,
                                      decoration: BoxDecoration(
                                        color: secs > 0
                                            ? color
                                            : Colors.grey.shade300,
                                        borderRadius:
                                            const BorderRadius.vertical(
                                                top: Radius.circular(3)),
                                      ),
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
                const SizedBox(height: 18),

                // ── 4. زر (دخول) في منتصف التاب للدخول إلى صفحة الدورات التدريبية ──
                Center(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _navy,
                      foregroundColor: _gold,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 36, vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      elevation: 2,
                    ),
                    icon: const Icon(Icons.meeting_room_rounded,
                        color: _gold, size: 20),
                    label: Text(
                      '${s.enterCycle} (${cycle.name})',
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                    onPressed: () => _openCycleWeeklyCycles(cycle),
                  ),
                ),
                const SizedBox(height: 16),
                const Divider(height: 1),
                const SizedBox(height: 12),

                // ── 5. أسفل تاب السيكل: ملاحظة فسيولوجية (+) وملاحظة فنية (+) ──
                Row(
                  children: [
                    // ملاحظة فسيولوجية (+)
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF9FBFC),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.health_and_safety_outlined,
                                size: 18, color: Colors.teal),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                cycle.notesPhysio.isNotEmpty
                                    ? cycle.notesPhysio
                                    : s.physiologicalNote,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: cycle.notesPhysio.isNotEmpty
                                      ? Colors.black87
                                      : Colors.grey.shade500,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.add_circle_outline,
                                  size: 18, color: _navy),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              onPressed: () => _showNoteDialog(cycle, true),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),

                    // ملاحظة فنية (+)
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF9FBFC),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.engineering_outlined,
                                size: 18, color: Colors.blueGrey),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                cycle.notesTech.isNotEmpty
                                    ? cycle.notesTech
                                    : s.technicalNote,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: cycle.notesTech.isNotEmpty
                                      ? Colors.black87
                                      : Colors.grey.shade500,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.add_circle_outline,
                                  size: 18, color: _navy),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              onPressed: () => _showNoteDialog(cycle, false),
                            ),
                          ],
                        ),
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
