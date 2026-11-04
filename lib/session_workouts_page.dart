import 'package:flutter/material.dart';
import 'app_strings.dart';
import 'program_service.dart';

const Color _navy = Color(0xFF0D3B66);
const Color _sky = Color(0xFFE8F4FC);
const Color _gold = Color(0xFFFFC93C);

/// المستوى 4: صفحة تفاصيل تمارين الحصة التدريبية (Workouts Page)
/// تشمل 3 صفوف رئيسية متتالية:
/// 1. الإحماء (Warm-up)
/// 2. التمرين الرئيسي (Main Workout)
/// 3. التهدئة (Cool-down)
class SessionWorkoutsPage extends StatefulWidget {
  final ProgramDaySession session;
  final VoidCallback onSaved;

  const SessionWorkoutsPage({
    super.key,
    required this.session,
    required this.onSaved,
  });

  @override
  State<SessionWorkoutsPage> createState() => _SessionWorkoutsPageState();
}

class _SessionWorkoutsPageState extends State<SessionWorkoutsPage> {
  late ProgramDaySession _session;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _session = widget.session;
    // التأكد من وجود عنصر واحد على الأقل في كل قسم كبداية
    if (_session.warmupItems.isEmpty) {
      _addWorkoutRow('warmup');
    }
    if (_session.mainItems.isEmpty) {
      _addWorkoutRow('main');
    }
    if (_session.cooldownItems.isEmpty) {
      _addWorkoutRow('cooldown');
    }
  }

  void _addWorkoutRow(String section, [ProgramWorkoutItem? template]) {
    setState(() {
      final prevItems =
          _session.workouts.where((w) => w.section == section).toList();
      final last = template ?? (prevItems.isNotEmpty ? prevItems.last : null);

      _session.workouts.add(ProgramWorkoutItem(
        sessionId: _session.id ?? 0,
        section: section,
        itemIdx: prevItems.length,
        time: last?.time ?? _session.time,
        durationMinutes: last?.durationMinutes ?? (section == 'main' ? 30 : 10),
        durationSeconds: 0,
        hrPercent: last?.hrPercent ??
            (section == 'main' ? 80 : (section == 'warmup' ? 60 : 50)),
        hrRange: last?.hrRange ??
            (section == 'main' ? '75%:85%' : '55%:65%'),
        distanceMeters:
            last?.distanceMeters ?? (section == 'main' ? 6000 : 1500),
        reps: last?.reps ?? 1,
        kind: last?.kind ??
            (section == 'warmup'
                ? 'Stretch'
                : (section == 'main' ? 'Erg' : 'Mob')),
        zone: last?.zone ??
            (section == 'main'
                ? 'zone3 = 75%:85%'
                : 'zone1 = 55%:65%'),
        details: '',
      ));
    });
  }

  void _removeWorkoutRow(ProgramWorkoutItem item) {
    setState(() {
      _session.workouts.remove(item);
    });
  }

  Future<void> _pickTime(ProgramWorkoutItem item) async {
    final parts = item.time.split(':');
    final initial = TimeOfDay(
      hour: int.tryParse(parts[0]) ?? 7,
      minute: parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0,
    );

    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
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
      final hourStr = picked.hour.toString().padLeft(2, '0');
      final minStr = picked.minute.toString().padLeft(2, '0');
      setState(() {
        item.time = '$hourStr:$minStr';
      });
    }
  }

  void _showCommentDialog() {
    final ctrl = TextEditingController(text: _session.comment);
    final s = AppStrings.of(context);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.comment_outlined, color: _navy),
            const SizedBox(width: 8),
            Text('${s.comment} - ${_session.name}'),
          ],
        ),
        content: TextField(
          controller: ctrl,
          maxLines: 4,
          decoration: const InputDecoration(
            hintText: 'اكتب ملاحظات وتعليمات المدرب لهذا التمرين...',
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
              setState(() => _session.comment = ctrl.text.trim());
              Navigator.pop(ctx);
            },
            child: Text(s.save),
          ),
        ],
      ),
    );
  }

  Future<void> _saveAndExit() async {
    setState(() => _isSaving = true);
    final s = AppStrings.of(context);

    try {
      await ProgramService.saveDaySessionDetailed(_session);
      widget.onSaved();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 8),
                Text(s.savedSuccessfully),
              ],
            ),
            backgroundColor: Colors.green.shade700,
          ),
        );
        Navigator.pop(context);
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text('${_session.name} - ${s.workoutsPageTitle}'),
        actions: [
          // زر إضافة تعليق
          IconButton(
            tooltip: s.comment,
            icon: Icon(
              _session.comment.isNotEmpty
                  ? Icons.comment_rounded
                  : Icons.mode_comment_outlined,
              color: _session.comment.isNotEmpty ? _gold : Colors.white,
            ),
            onPressed: _showCommentDialog,
          ),
        ],
      ),
      body: Column(
        children: [
          // شريط معلومات الحصة التدريبية العلوي
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: _sky.withValues(alpha: 0.5),
              border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _navy,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.access_time_filled_rounded,
                      color: _gold, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _session.name,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: _navy),
                      ),
                      Text(
                        '${s.sessionTime}: ${_session.time} • تفاصيل الإحماء والتمرين الرئيسي والتهدئة',
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey.shade700),
                      ),
                    ],
                  ),
                ),
                if (_session.comment.isNotEmpty)
                  Tooltip(
                    message: _session.comment,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: _gold.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: _gold),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.comment, size: 14, color: _navy),
                          SizedBox(width: 4),
                          Text('يوجد تعليق',
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: _navy)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // قائمة الصفوف الثلاثة: 1. الإحماء 2. الرئيسي 3. التهدئة
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // ── 1. الصف الأول: الإحماء ──
                _buildSectionCard(
                  title: s.warmupSection,
                  icon: Icons.directions_walk_rounded,
                  section: 'warmup',
                  items: _session.warmupItems,
                  badgeColor: Colors.amber.shade700,
                  onAdd: () => _addWorkoutRow('warmup'),
                ),
                const SizedBox(height: 18),

                // ── 2. الصف الثاني: التمرين الرئيسي ──
                _buildSectionCard(
                  title: s.mainWorkoutSection,
                  icon: Icons.fitness_center_rounded,
                  section: 'main',
                  items: _session.mainItems,
                  badgeColor: Colors.deepOrange,
                  onAdd: () => _addWorkoutRow('main'),
                ),
                const SizedBox(height: 18),

                // ── 3. الصف الثالث: التهدئة ──
                _buildSectionCard(
                  title: s.cooldownSection,
                  icon: Icons.self_improvement_rounded,
                  section: 'cooldown',
                  items: _session.cooldownItems,
                  badgeColor: Colors.teal,
                  onAdd: () => _addWorkoutRow('cooldown'),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),

          // شريط الحفظ السفلي
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 10,
                  offset: const Offset(0, -3),
                ),
              ],
            ),
            child: Row(
              children: [
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _navy,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () => Navigator.pop(context),
                  child: Text(s.cancel),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _gold,
                      foregroundColor: _navy,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      elevation: 1,
                    ),
                    icon: _isSaving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: _navy),
                          )
                        : const Icon(Icons.check_circle_rounded, size: 20),
                    label: Text(
                      _isSaving ? s.loading : s.save,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                    onPressed: _isSaving ? null : _saveAndExit,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// كارت القسم (مجسم بحواف مظللة دائرية)
  Widget _buildSectionCard({
    required String title,
    required IconData icon,
    required String section,
    required List<ProgramWorkoutItem> items,
    required Color badgeColor,
    required VoidCallback onAdd,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade300, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // رأس الصف
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: _navy.withValues(alpha: 0.04),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(17)),
              border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: badgeColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: badgeColor, size: 20),
                ),
                const SizedBox(width: 10),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: _navy,
                  ),
                ),
                const Spacer(),

                // زرار (+) لإضافة خانة جديدة في رأس الصف
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _navy,
                    foregroundColor: _gold,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('إضافة تمرين',
                      style:
                          TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  onPressed: onAdd,
                ),
              ],
            ),
          ),

          // قائمة الخانات المدخلة في هذا الصف
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: items.asMap().entries.map((entry) {
                final idx = entry.key;
                final item = entry.value;
                return _WorkoutRowWidget(
                  key: ValueKey(item.hashCode),
                  item: item,
                  index: idx,
                  canDelete: items.length > 1,
                  onTimePick: () => _pickTime(item),
                  onAddNext: () => _addWorkoutRow(section, item),
                  onDelete: () => _removeWorkoutRow(item),
                  onDataChanged: () => setState(() {}),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

/// خانة تمرين تفصيلية داخل الصف تحتوي على الحقول السبعة المحددة بدقة
/// مع الإسقاط التلقائي لنسبة النبض بمجرد اختيار الزون، وزر (+) لإضافة تمرين بنفس المواصفات
class _WorkoutRowWidget extends StatefulWidget {
  final ProgramWorkoutItem item;
  final int index;
  final bool canDelete;
  final VoidCallback onTimePick;
  final VoidCallback onAddNext;
  final VoidCallback onDelete;
  final VoidCallback onDataChanged;

  const _WorkoutRowWidget({
    super.key,
    required this.item,
    required this.index,
    required this.canDelete,
    required this.onTimePick,
    required this.onAddNext,
    required this.onDelete,
    required this.onDataChanged,
  });

  @override
  State<_WorkoutRowWidget> createState() => _WorkoutRowWidgetState();
}

class _WorkoutRowWidgetState extends State<_WorkoutRowWidget> {
  late TextEditingController _durationCtrl;
  late TextEditingController _distanceCtrl;
  late TextEditingController _repsCtrl;
  late TextEditingController _hrCtrl;
  late TextEditingController _detailsCtrl;

  @override
  void initState() {
    super.initState();
    _durationCtrl =
        TextEditingController(text: '${widget.item.durationMinutes}');
    _distanceCtrl =
        TextEditingController(text: '${widget.item.distanceMeters}');
    _repsCtrl = TextEditingController(text: '${widget.item.reps}');
    _hrCtrl = TextEditingController(
        text: widget.item.hrRange.isNotEmpty
            ? widget.item.hrRange
            : (kZoneToHrPercentMap[widget.item.zone] ?? '75%:85%'));
    _detailsCtrl = TextEditingController(text: widget.item.details);
  }

  @override
  void didUpdateWidget(covariant _WorkoutRowWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item != widget.item) {
      _durationCtrl.text = '${widget.item.durationMinutes}';
      _distanceCtrl.text = '${widget.item.distanceMeters}';
      _repsCtrl.text = '${widget.item.reps}';
      _hrCtrl.text = widget.item.hrRange.isNotEmpty
          ? widget.item.hrRange
          : (kZoneToHrPercentMap[widget.item.zone] ?? '75%:85%');
      _detailsCtrl.text = widget.item.details;
    }
  }

  @override
  void dispose() {
    _durationCtrl.dispose();
    _distanceCtrl.dispose();
    _repsCtrl.dispose();
    _hrCtrl.dispose();
    _detailsCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final currentDetailedZone = formatZoneToDetailed(widget.item.zone);
    final normZone = normalizeZoneKey(currentDetailedZone);
    final zoneColor = kZoneColors[normZone] ?? _navy;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFBFDFE),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── الشريط العلوي للخانة: رقم التمرين + وقت التمرين + زر (+) بجوار الخانات + زر الحذف ──
          Row(
            children: [
              CircleAvatar(
                radius: 12,
                backgroundColor: _navy,
                child: Text(
                  '${widget.index + 1}',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 8),

              // 1. خانة وقت التمرين السريع
              InkWell(
                onTap: widget.onTimePick,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: _sky,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _navy.withValues(alpha: 0.25)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.access_time_rounded,
                          size: 15, color: _navy),
                      const SizedBox(width: 6),
                      Text(
                        'وقت: ${widget.item.time}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: _navy,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Spacer(),

              // زر (+) بجوار الخانات لإضافة تمرين جديد بنفس المواصفات
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: _navy,
                  side: const BorderSide(color: _navy, width: 1.2),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                icon: const Icon(Icons.add_circle_outline_rounded,
                    size: 16, color: _navy),
                label: const Text(
                  'إضافة تمرين (+)',
                  style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.bold,
                      color: _navy),
                ),
                onPressed: widget.onAddNext,
              ),

              // زر الحذف
              if (widget.canDelete) ...[
                const SizedBox(width: 6),
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded,
                      size: 20, color: Colors.redAccent),
                  tooltip: 'حذف هذا التمرين',
                  onPressed: widget.onDelete,
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),

          // ── الخانات المرتبة من جهة يمين المستخدم ──
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              // 1. زر ضبط وقت التمرين
              SizedBox(
                width: 95,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 12),
                    side: BorderSide(color: Colors.grey.shade400),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: widget.onTimePick,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.schedule_rounded,
                          size: 15, color: _navy),
                      const SizedBox(width: 4),
                      Text(
                        widget.item.time,
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: _navy),
                      ),
                    ],
                  ),
                ),
              ),

              // 2. خانة مدة زمن التمرين
              SizedBox(
                width: 105,
                child: TextFormField(
                  controller: _durationCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'مدة التمرين (د)',
                    labelStyle: TextStyle(fontSize: 11),
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (val) {
                    widget.item.durationMinutes = int.tryParse(val) ?? 0;
                    widget.onDataChanged();
                  },
                ),
              ),

              // 3. خانة مسافة التمرين بالمتر
              SizedBox(
                width: 120,
                child: TextFormField(
                  controller: _distanceCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'المسافة (متر)',
                    labelStyle: TextStyle(fontSize: 11),
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (val) {
                    widget.item.distanceMeters = int.tryParse(val) ?? 0;
                    widget.onDataChanged();
                  },
                ),
              ),

              // 4. خانة عدد تكرارات مدة زمن التمرين
              SizedBox(
                width: 90,
                child: TextFormField(
                  controller: _repsCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'التكرار',
                    labelStyle: TextStyle(fontSize: 11),
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (val) {
                    widget.item.reps = int.tryParse(val) ?? 1;
                    widget.onDataChanged();
                  },
                ),
              ),

              // 5. خانة نوع التمرين (قائمة منسدلة: Stretch, Fitness, Mob, bike, Run, Erg, Row)
              SizedBox(
                width: 125,
                child: DropdownButtonFormField<String>(
                  value: kProgramWorkoutKinds.contains(widget.item.kind)
                      ? widget.item.kind
                      : kProgramWorkoutKinds.first,
                  isDense: true,
                  decoration: const InputDecoration(
                    labelText: 'نوع التمرين',
                    labelStyle: TextStyle(fontSize: 11),
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    border: OutlineInputBorder(),
                  ),
                  items: kProgramWorkoutKinds.map((k) {
                    return DropdownMenuItem(
                      value: k,
                      child: Text(k,
                          style: const TextStyle(
                              fontSize: 12.5, fontWeight: FontWeight.w600)),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setState(() => widget.item.kind = val);
                      widget.onDataChanged();
                    }
                  },
                ),
              ),

              // 6. خانة نسبة النبض للتمرين الرئيسي (تسقط تلقائياً فور اختيار الزون)
              SizedBox(
                width: 120,
                child: TextFormField(
                  controller: _hrCtrl,
                  decoration: InputDecoration(
                    labelText: 'نسبة النبض %',
                    labelStyle: const TextStyle(fontSize: 11),
                    hintText: '55%:65%',
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    border: const OutlineInputBorder(),
                    isDense: true,
                    filled: true,
                    fillColor: zoneColor.withValues(alpha: 0.08),
                  ),
                  onChanged: (val) {
                    widget.item.hrRange = val;
                    widget.onDataChanged();
                  },
                ),
              ),

              // 7. خانة zone التمرين الرئيسي (الزونات الـ 6 المحددة بالوصف)
              SizedBox(
                width: 215,
                child: DropdownButtonFormField<String>(
                  value: currentDetailedZone,
                  isDense: true,
                  decoration: InputDecoration(
                    labelText: 'Zone التمرين',
                    labelStyle: const TextStyle(fontSize: 11),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    border: const OutlineInputBorder(),
                    filled: true,
                    fillColor: zoneColor.withValues(alpha: 0.05),
                  ),
                  items: kProgramZonesDetailed.map((zd) {
                    final nKey = normalizeZoneKey(zd);
                    final c = kZoneColors[nKey] ?? _navy;
                    return DropdownMenuItem<String>(
                      value: zd,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 9,
                            height: 9,
                            decoration: BoxDecoration(
                              color: c,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            zd,
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.bold,
                              color: c,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setState(() {
                        widget.item.zone = val;
                        // إسقاط نسبة النبض المحددة فوراً في خانة نسبة النبض
                        final autoHr = kZoneToHrPercentMap[val] ?? '';
                        widget.item.hrRange = autoHr;
                        _hrCtrl.text = autoHr;

                        final norm = normalizeZoneKey(val);
                        widget.item.hrPercent = norm == 'Z1'
                            ? 60
                            : (norm == 'Z2'
                                ? 70
                                : (norm == 'Z3'
                                    ? 80
                                    : (norm == 'Z4'
                                        ? 88
                                        : (norm == 'Threshold' ? 92 : 98))));
                      });
                      widget.onDataChanged();
                    }
                  },
                ),
              ),

              // 8. زر (+) مباشر بجوار الخانات
              IconButton(
                style: IconButton.styleFrom(
                  backgroundColor: _navy,
                  foregroundColor: _gold,
                  padding: const EdgeInsets.all(8),
                ),
                icon: const Icon(Icons.add, size: 20),
                tooltip: 'إضافة تمرين بنفس المواصفات',
                onPressed: widget.onAddNext,
              ),

              // 9. ملاحظات أو تفاصيل إضافية
              SizedBox(
                width: 140,
                child: TextFormField(
                  controller: _detailsCtrl,
                  decoration: InputDecoration(
                    labelText: s.workoutDetails,
                    labelStyle: const TextStyle(fontSize: 11),
                    hintText: 'ملاحظة...',
                    hintStyle: const TextStyle(fontSize: 10),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (val) {
                    widget.item.details = val;
                    widget.onDataChanged();
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
