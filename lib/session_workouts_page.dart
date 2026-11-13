import 'package:flutter/material.dart';
import 'app_strings.dart';
import 'engine_rowing_ui.dart';
import 'program_service.dart';

const Color _navy = EngineRowingUI.bgNavy;
const Color _cardFill = EngineRowingUI.cardFill;
const Color _gold = EngineRowingUI.neonLime;
const Color _gridLine = EngineRowingUI.bgGridLine;

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

      String nextTitle;
      if (last != null && last.details.trim().isNotEmpty) {
        nextTitle =
            ProgramService.incrementBoardTitle(last.details, prevItems.length);
      } else {
        final baseName = section == 'warmup'
            ? 'إحماء'
            : (section == 'main' ? 'رئيسي' : 'تهدئة');
        nextTitle = '$baseName ${prevItems.length + 1}';
      }

      _session.workouts.add(ProgramWorkoutItem(
        sessionId: _session.id ?? 0,
        section: section,
        itemIdx: prevItems.length,
        time: last?.time ?? _session.time,
        durationMinutes: last?.durationMinutes ?? (section == 'main' ? 30 : 10),
        durationSeconds: 0,
        hrPercent: last?.hrPercent ??
            (section == 'main' ? 80 : (section == 'warmup' ? 60 : 50)),
        hrRange: last?.hrRange ?? (section == 'main' ? '75%:85%' : '55%:65%'),
        distanceMeters:
            last?.distanceMeters ?? (section == 'main' ? 6000 : 1500),
        reps: last?.reps ?? 1,
        kind: last?.kind ??
            (section == 'warmup'
                ? 'Stretch'
                : (section == 'main' ? 'Erg' : 'Mob')),
        zone: last?.zone ??
            (section == 'main' ? 'zone3 = 75%:85%' : 'zone1 = 55%:65%'),
        details: nextTitle,
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
          colorScheme: const ColorScheme.dark(
            primary: _gold,
            onPrimary: _navy,
            surface: _cardFill,
            onSurface: EngineRowingUI.textWhite,
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
        backgroundColor: _cardFill,
        title: Row(
          children: [
            const Icon(Icons.comment_outlined, color: _gold),
            const SizedBox(width: 8),
            Text('${s.comment} - ${_session.name}',
                style: const TextStyle(color: EngineRowingUI.textWhite)),
          ],
        ),
        content: TextField(
          controller: ctrl,
          maxLines: 4,
          style: const TextStyle(color: EngineRowingUI.textWhite),
          decoration: const InputDecoration(
            hintText: 'اكتب ملاحظات وتعليمات المدرب لهذا التمرين...',
            hintStyle: TextStyle(color: EngineRowingUI.labelSlate),
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(s.cancel,
                style: const TextStyle(color: EngineRowingUI.labelSlate)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: _gold, foregroundColor: _navy),
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
      backgroundColor: _navy,
      appBar: AppBar(
        backgroundColor: _navy,
        foregroundColor: EngineRowingUI.textWhite,
        title: Text('${_session.name} - ${s.workoutsPageTitle}'),
        actions: [
          // زر إضافة تعليق
          IconButton(
            tooltip: s.comment,
            icon: Icon(
              _session.comment.isNotEmpty
                  ? Icons.comment_rounded
                  : Icons.mode_comment_outlined,
              color: _session.comment.isNotEmpty
                  ? _gold
                  : EngineRowingUI.labelSlate,
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
              color: _cardFill,
              border: Border(
                  bottom: BorderSide(color: _gold.withAlpha(120), width: 1.2)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: EngineRowingUI.equationCardFill,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _gridLine),
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
                            color: EngineRowingUI.textWhite),
                      ),
                      Directionality(
                        textDirection: TextDirection.ltr,
                        child: Text(
                          '${s.sessionTime}: ${RowingNumberFormatter.toEnglishDigits(_session.time)} • Warm-up, Main, Cool-down',
                          style: const TextStyle(
                              fontSize: 12, color: EngineRowingUI.labelSlate),
                        ),
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
                        color: _gold.withAlpha(35),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: _gold),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.comment, size: 14, color: _gold),
                          SizedBox(width: 4),
                          Text('يوجد تعليق',
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: _gold)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // قائمة الصفوف الثلاثة: 1. الإحماء 2. الرئيسي 3. التهدئة مع التكبير بالأصابع
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 850),
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    // ── 1. الصف الأول: الإحماء ──
                    _buildSectionCard(
                      title: s.warmupSection,
                      icon: Icons.directions_walk_rounded,
                      section: 'warmup',
                      items: _session.warmupItems,
                      badgeColor: const Color(0xFFFF9100),
                      onAdd: () => _addWorkoutRow('warmup'),
                    ),
                    const SizedBox(height: 18),

                    // ── 2. الصف الثاني: التمرين الرئيسي ──
                    _buildSectionCard(
                      title: s.mainWorkoutSection,
                      icon: Icons.fitness_center_rounded,
                      section: 'main',
                      items: _session.mainItems,
                      badgeColor: _gold,
                      onAdd: () => _addWorkoutRow('main'),
                    ),
                    const SizedBox(height: 18),

                    // ── 3. الصف الثالث: التهدئة ──
                    _buildSectionCard(
                      title: s.cooldownSection,
                      icon: Icons.self_improvement_rounded,
                      section: 'cooldown',
                      items: _session.cooldownItems,
                      badgeColor: const Color(0xFF2979FF),
                      onAdd: () => _addWorkoutRow('cooldown'),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ),

          // شريط الحفظ السفلي
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              color: _cardFill,
              border: Border(top: BorderSide(color: _gridLine)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black45,
                  blurRadius: 10,
                  offset: Offset(0, -3),
                ),
              ],
            ),
            child: Row(
              children: [
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: EngineRowingUI.labelSlate,
                    side: const BorderSide(color: _gridLine),
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
      decoration: EngineRowingUI.neonGlowBoxDecoration(
        backgroundColor: _cardFill,
        borderColor: _gold,
        borderRadius: 14,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // رأس الصف
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              color: EngineRowingUI.equationCardFill,
              borderRadius: BorderRadius.vertical(top: Radius.circular(13)),
              border: Border(bottom: BorderSide(color: _gridLine)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: badgeColor.withAlpha(35),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: badgeColor, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: EngineRowingUI.textWhite,
                    ),
                  ),
                ),
                const SizedBox(width: 8),

                // زرار (+) لإضافة خانة جديدة في رأس الصف
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _gold,
                    foregroundColor: _navy,
                    elevation: 0,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: Text(
                      'إضافة ${section == 'warmup' ? 'إحماء' : (section == 'main' ? 'تمرين' : 'تهدئة')} (+)',
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.bold)),
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
    final zoneColor = kZoneColors[normZone] ?? _gold;
    final defaultPrefix = widget.item.section == 'warmup'
        ? 'إحماء'
        : (widget.item.section == 'main' ? 'تمرين' : 'تهدئة');
    final boardTitle = widget.item.details.isNotEmpty
        ? widget.item.details
        : '$defaultPrefix ${widget.index + 1}';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: neonGlowBoxDecoration(
        fillColor: EngineRowingUI.equationCardFill,
        borderColor: zoneColor.withValues(alpha: 0.6),
        borderWidth: 1.2,
        borderRadius: 12,
        intensity: intensityNotifier.value,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── الشريط العلوي للخانة: رقم التمرين + اسم اللوحة + وقت التمرين + زر (+) بجوار الخانات + زر الحذف (متجاوب تماماً) ──
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            runSpacing: 8,
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircleAvatar(
                    radius: 12,
                    backgroundColor: _gold,
                    child: Text(
                      '${widget.index + 1}',
                      style: const TextStyle(
                          color: _navy,
                          fontSize: 11,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(width: 6),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 120),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: _gold.withAlpha(30),
                        borderRadius: BorderRadius.circular(6),
                        border:
                            Border.all(color: _gold.withAlpha(120), width: 1.0),
                      ),
                      child: Text(
                        boardTitle,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _gold,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              // 1. خانة وقت التمرين السريع
              InkWell(
                onTap: widget.onTimePick,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  decoration: BoxDecoration(
                    color: _cardFill,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _gridLine),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.access_time_rounded,
                          size: 15, color: _gold),
                      const SizedBox(width: 6),
                      Directionality(
                        textDirection: TextDirection.ltr,
                        child: Text(
                          'وقت: ${RowingNumberFormatter.toEnglishDigits(widget.item.time)}',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            fontFeatures: [FontFeature.tabularFigures()],
                            color: EngineRowingUI.textWhite,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // زر (+) بجوار الخانات لإضافة تمرين جديد بنفس المواصفات مع زيادة الرقم
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: _gold,
                  side: const BorderSide(color: _gold, width: 1.2),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                icon: const Icon(Icons.add_circle_outline_rounded,
                    size: 16, color: _gold),
                label: Text(
                  'إضافة $defaultPrefix (+)',
                  style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.bold,
                      color: _gold),
                ),
                onPressed: widget.onAddNext,
              ),

              // زر الحذف
              if (widget.canDelete)
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded,
                      size: 20, color: Colors.redAccent),
                  tooltip: 'حذف هذا التمرين',
                  onPressed: widget.onDelete,
                ),
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
                width: 115,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
                    side: const BorderSide(color: _gridLine),
                    backgroundColor: _cardFill,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: widget.onTimePick,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.schedule_rounded,
                          size: 16, color: _gold),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Directionality(
                          textDirection: TextDirection.ltr,
                          child: Text(
                            RowingNumberFormatter.toEnglishDigits(
                                widget.item.time),
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                fontFeatures: [FontFeature.tabularFigures()],
                                color: EngineRowingUI.textWhite),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // 2. خانة مدة زمن التمرين
              SizedBox(
                width: 115,
                child: Directionality(
                  textDirection: TextDirection.ltr,
                  child: TextFormField(
                    controller: _durationCtrl,
                    textAlign: TextAlign.left,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      RowingNumberFormatter.englishDigitsInputFormatter,
                    ],
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: EngineRowingUI.textWhite,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                    decoration: const InputDecoration(
                      labelText: 'مدة التمرين (د)',
                      labelStyle: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: EngineRowingUI.labelSlate),
                      filled: true,
                      fillColor: _cardFill,
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                      border: OutlineInputBorder(
                          borderSide: BorderSide(color: _gridLine)),
                      enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: _gridLine)),
                      focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: _gold)),
                      isDense: true,
                    ),
                    onChanged: (val) {
                      widget.item.durationMinutes = int.tryParse(val) ?? 0;
                      widget.onDataChanged();
                    },
                  ),
                ),
              ),

              // 3. خانة مسافة التمرين بالمتر
              SizedBox(
                width: 130,
                child: Directionality(
                  textDirection: TextDirection.ltr,
                  child: TextFormField(
                    controller: _distanceCtrl,
                    textAlign: TextAlign.left,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      RowingNumberFormatter.englishDigitsInputFormatter,
                    ],
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: EngineRowingUI.textWhite,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                    decoration: const InputDecoration(
                      labelText: 'المسافة (متر)',
                      labelStyle: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: EngineRowingUI.labelSlate),
                      filled: true,
                      fillColor: _cardFill,
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                      border: OutlineInputBorder(
                          borderSide: BorderSide(color: _gridLine)),
                      enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: _gridLine)),
                      focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: _gold)),
                      isDense: true,
                    ),
                    onChanged: (val) {
                      widget.item.distanceMeters = int.tryParse(val) ?? 0;
                      widget.onDataChanged();
                    },
                  ),
                ),
              ),

              // 4. خانة عدد تكرارات مدة زمن التمرين
              SizedBox(
                width: 100,
                child: Directionality(
                  textDirection: TextDirection.ltr,
                  child: TextFormField(
                    controller: _repsCtrl,
                    textAlign: TextAlign.left,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      RowingNumberFormatter.englishDigitsInputFormatter,
                    ],
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: EngineRowingUI.textWhite,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                    decoration: const InputDecoration(
                      labelText: 'التكرار',
                      labelStyle: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: EngineRowingUI.labelSlate),
                      filled: true,
                      fillColor: _cardFill,
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                      border: OutlineInputBorder(
                          borderSide: BorderSide(color: _gridLine)),
                      enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: _gridLine)),
                      focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: _gold)),
                      isDense: true,
                    ),
                    onChanged: (val) {
                      widget.item.reps = int.tryParse(val) ?? 1;
                      widget.onDataChanged();
                    },
                  ),
                ),
              ),

              // 5. خانة نوع التمرين (قائمة منسدلة: Stretch, Fitness, Mob, bike, Run, Erg, Row)
              SizedBox(
                width: 135,
                child: DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: kProgramWorkoutKinds.contains(widget.item.kind)
                      ? widget.item.kind
                      : kProgramWorkoutKinds.first,
                  dropdownColor: _cardFill,
                  isDense: true,
                  decoration: const InputDecoration(
                    labelText: 'نوع التمرين',
                    labelStyle: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: EngineRowingUI.labelSlate),
                    filled: true,
                    fillColor: _cardFill,
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                    border: OutlineInputBorder(
                        borderSide: BorderSide(color: _gridLine)),
                    enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: _gridLine)),
                    focusedBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: _gold)),
                  ),
                  items: kProgramWorkoutKinds.map((k) {
                    return DropdownMenuItem(
                      value: k,
                      child: Text(k,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: EngineRowingUI.textWhite)),
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
                width: 130,
                child: Directionality(
                  textDirection: TextDirection.ltr,
                  child: TextFormField(
                    controller: _hrCtrl,
                    textAlign: TextAlign.left,
                    inputFormatters: [
                      RowingNumberFormatter.englishDigitsInputFormatter,
                    ],
                    style: TextStyle(
                      fontSize: 15,
                      color: zoneColor,
                      fontWeight: FontWeight.bold,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                    decoration: InputDecoration(
                      labelText: 'نسبة النبض %',
                      labelStyle: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: EngineRowingUI.labelSlate),
                      hintText: '55%:65%',
                      hintStyle: const TextStyle(
                          fontSize: 12, color: EngineRowingUI.captionGrey),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 12),
                      border: OutlineInputBorder(
                          borderSide: BorderSide(color: zoneColor)),
                      enabledBorder: OutlineInputBorder(
                          borderSide:
                              BorderSide(color: zoneColor.withAlpha(120))),
                      focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: zoneColor, width: 2)),
                      isDense: true,
                      filled: true,
                      fillColor: zoneColor.withAlpha(25),
                    ),
                    onChanged: (val) {
                      widget.item.hrRange =
                          RowingNumberFormatter.toEnglishDigits(val);
                      widget.onDataChanged();
                    },
                  ),
                ),
              ),

              // 7. خانة zone التمرين الرئيسي (الزونات الـ 6 المحددة بالوصف)
              SizedBox(
                width: 230,
                child: DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: currentDetailedZone,
                  dropdownColor: _cardFill,
                  isDense: true,
                  decoration: InputDecoration(
                    labelText: 'Zone التمرين',
                    labelStyle: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: EngineRowingUI.labelSlate),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 10),
                    border: OutlineInputBorder(
                        borderSide: BorderSide(color: _gridLine)),
                    enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: _gridLine)),
                    focusedBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: _gold)),
                    filled: true,
                    fillColor: zoneColor.withAlpha(20),
                  ),
                  items: kProgramZonesDetailed.map((zd) {
                    final nKey = normalizeZoneKey(zd);
                    final c = kZoneColors[nKey] ?? _gold;
                    return DropdownMenuItem<String>(
                      value: zd,
                      child: Row(
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: c,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              zd,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: c,
                              ),
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
                  backgroundColor: _gold,
                  foregroundColor: _navy,
                  padding: const EdgeInsets.all(8),
                ),
                icon: const Icon(Icons.add, size: 20),
                tooltip: 'إضافة تمرين بنفس المواصفات',
                onPressed: widget.onAddNext,
              ),
            ],
          ),
          const SizedBox(height: 10),

          // 9. ملاحظات أو تفاصيل إضافية (تمتد بكامل العرض لاستغلال المساحة المتاحة دون هدر)
          TextFormField(
            controller: _detailsCtrl,
            style: const TextStyle(
                fontSize: 12.5, color: EngineRowingUI.textWhite),
            decoration: InputDecoration(
              labelText: s.workoutDetails,
              labelStyle: const TextStyle(
                  fontSize: 11, color: EngineRowingUI.labelSlate),
              hintText: 'ملاحظة أو تفاصيل التمرين...',
              hintStyle: const TextStyle(
                  fontSize: 10.5, color: EngineRowingUI.captionGrey),
              filled: true,
              fillColor: _cardFill,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: const OutlineInputBorder(
                  borderSide: BorderSide(color: _gridLine)),
              enabledBorder: const OutlineInputBorder(
                  borderSide: BorderSide(color: _gridLine)),
              focusedBorder: const OutlineInputBorder(
                  borderSide: BorderSide(color: _gold)),
              isDense: true,
            ),
            onChanged: (val) {
              widget.item.details = val;
              widget.onDataChanged();
            },
          ),
        ],
      ),
    );
  }
}
