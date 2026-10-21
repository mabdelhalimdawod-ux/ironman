import 'package:flutter/material.dart';
import 'app_strings.dart';
import 'program_service.dart';

const Color _navy = Color(0xFF0D3B66);
const Color _sky = Color(0xFFE8F4FC);
const Color _gold = Color(0xFFFFC93C);

/// الصفحة الفرعية للقالب الأسبوعي المتكرر لسيكل معين
class CycleTemplatePage extends StatefulWidget {
  final Map<String, Object?> cycle;
  final VoidCallback onSaved;

  const CycleTemplatePage({
    super.key,
    required this.cycle,
    required this.onSaved,
  });

  @override
  State<CycleTemplatePage> createState() => _CycleTemplatePageState();
}

class _CycleTemplatePageState extends State<CycleTemplatePage> {
  int _selectedDayIndex = 0; // 0: السبت ... 6: الجمعة
  bool _loading = true;
  bool _isSaving = false;

  // القالب لجميع أيام الأسبوع: dayIndex -> list of slots
  final Map<int, List<WorkoutSlot>> _weekSlots = {};

  int get _cycleId => (widget.cycle['id'] as num?)?.toInt() ?? 1;
  String get _cycleName => widget.cycle['name'] as String? ?? 'السيكل $_cycleId';

  @override
  void initState() {
    super.initState();
    _loadAllDays();
  }

  Future<void> _loadAllDays() async {
    setState(() => _loading = true);
    for (int day = 0; day < 7; day++) {
      final slots = await ProgramService.getTemplateSlots(_cycleId, day);
      _weekSlots[day] = List.from(slots);
    }
    if (mounted) setState(() => _loading = false);
  }

  List<WorkoutSlot> get _currentDaySlots => _weekSlots[_selectedDayIndex] ?? [];

  void _addSlot() {
    final current = _currentDaySlots;
    if (current.length >= 6) {
      final s = AppStrings.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.maxSlotsReached), backgroundColor: Colors.red.shade700),
      );
      return;
    }

    // وقت افتراضي حسب عدد الخانات
    final defaultTimes = ['06:30', '08:30', '16:00', '17:30', '19:00', '20:30'];
    final time = defaultTimes[current.length.clamp(0, defaultTimes.length - 1)];

    setState(() {
      current.add(WorkoutSlot(
        slotIdx: current.length,
        kind: 'إرج',
        time: time,
        zone: 'Z2',
      ));
    });
  }

  void _removeSlot(int index) {
    setState(() {
      _currentDaySlots.removeAt(index);
    });
  }

  void _updateSlotKind(int index, String newKind) {
    final old = _currentDaySlots[index];
    setState(() {
      _currentDaySlots[index] = WorkoutSlot(
        slotIdx: old.slotIdx,
        kind: newKind,
        time: old.time,
        zone: old.zone,
      );
    });
  }

  void _updateSlotZone(int index, String newZone) {
    final old = _currentDaySlots[index];
    setState(() {
      _currentDaySlots[index] = WorkoutSlot(
        slotIdx: old.slotIdx,
        kind: old.kind,
        time: old.time,
        zone: newZone,
      );
    });
  }

  Future<void> _pickTime(int index) async {
    final old = _currentDaySlots[index];
    final parts = old.time.split(':');
    final initialTime = TimeOfDay(
      hour: int.tryParse(parts[0]) ?? 7,
      minute: parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0,
    );

    final picked = await showTimePicker(
      context: context,
      initialTime: initialTime,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: _navy,
              onPrimary: Colors.white,
              secondary: _gold,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      final hourStr = picked.hour.toString().padLeft(2, '0');
      final minStr = picked.minute.toString().padLeft(2, '0');
      final formatted = '$hourStr:$minStr';

      setState(() {
        _currentDaySlots[index] = WorkoutSlot(
          slotIdx: old.slotIdx,
          kind: old.kind,
          time: formatted,
          zone: old.zone,
        );
      });
    }
  }

  Future<void> _saveCurrentTemplate() async {
    setState(() => _isSaving = true);
    final s = AppStrings.of(context);

    try {
      for (int day = 0; day < 7; day++) {
        await ProgramService.saveTemplateSlots(
          _cycleId,
          day,
          _weekSlots[day] ?? [],
        );
      }

      widget.onSaved();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 8),
                Text(s.templateSaved),
              ],
            ),
            backgroundColor: Colors.green.shade700,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _copyToOtherDays() {
    final s = AppStrings.of(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.copyTemplateToDay),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(7, (i) {
            if (i == _selectedDayIndex) return const SizedBox.shrink();
            final dayName = s.isArabic
                ? ProgramService.weekDayNamesAr[i]
                : ProgramService.weekDayNamesEn[i];
            return ListTile(
              title: Text(dayName),
              trailing: const Icon(Icons.copy, size: 20),
              onTap: () {
                setState(() {
                  _weekSlots[i] = _currentDaySlots.map((slot) => WorkoutSlot(
                    slotIdx: slot.slotIdx,
                    kind: slot.kind,
                    time: slot.time,
                    zone: slot.zone,
                  )).toList();
                });
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('تم نسخ القالب إلى $dayName بنجاح')),
                );
              },
            );
          }),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(s.close),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final currentDaySlots = _currentDaySlots;

    return Scaffold(
      appBar: AppBar(
        title: Text('$_cycleName - ${s.weeklyTemplateTitle}'),
        actions: [
          IconButton(
            tooltip: s.copyTemplateToDay,
            icon: const Icon(Icons.copy_all_rounded),
            onPressed: _copyToOtherDays,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _navy))
          : Column(
              children: [
                // رأس تعريفي بالسيكل
                _buildCycleSummaryHeader(s),

                // شريط اختيار أيام الأسبوع (السبت - الجمعة)
                _buildDaySelector(s),

                // قائمة خانات التمرين لهذا اليوم (حتى 6 خانات)
                Expanded(
                  child: currentDaySlots.isEmpty
                      ? _buildEmptyDayState(s)
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          itemCount: currentDaySlots.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 12),
                          itemBuilder: (ctx, idx) => _buildSlotCard(s, idx, currentDaySlots[idx]),
                        ),
                ),

                // شريط الإجراءات السفلي (إضافة خانة + حفظ)
                _buildBottomActionBar(s, currentDaySlots.length),
              ],
            ),
    );
  }

  Widget _buildCycleSummaryHeader(AppStrings s) {
    final start = widget.cycle['start'] as String? ?? '';
    final end = widget.cycle['end'] as String? ?? '';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: _sky.withOpacity(0.5),
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
            child: const Icon(Icons.calendar_month, color: _gold, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _cycleName,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: _navy),
                ),
                Text(
                  '$start ➔ $end • ${s.weeklyTemplateSubtitle}',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDaySelector(AppStrings s) {
    return Container(
      height: 52,
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: 7,
        itemBuilder: (context, index) {
          final isSelected = index == _selectedDayIndex;
          final dayName = s.isArabic
              ? ProgramService.weekDayNamesAr[index]
              : ProgramService.weekDayNamesEn[index];
          final count = (_weekSlots[index] ?? []).length;

          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: ChoiceChip(
              label: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(dayName),
                  if (count > 0) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: isSelected ? _gold : Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '$count',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: isSelected ? _navy : Colors.black87,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              selected: isSelected,
              selectedColor: _navy,
              backgroundColor: Colors.white,
              labelStyle: TextStyle(
                color: isSelected ? Colors.white : _navy,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
              onSelected: (val) {
                if (val) setState(() => _selectedDayIndex = index);
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildEmptyDayState(AppStrings s) {
    final dayName = s.isArabic
        ? ProgramService.weekDayNamesAr[_selectedDayIndex]
        : ProgramService.weekDayNamesEn[_selectedDayIndex];

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.event_available_outlined, size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          Text(
            'لا توجد تمارين مجدولة ليوم $dayName (يوم راحة)',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey.shade700),
          ),
          const SizedBox(height: 6),
          Text(
            'يمكنك إضافة حتى 6 خانات تمرين لهذا اليوم',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: _navy, foregroundColor: Colors.white),
            icon: const Icon(Icons.add),
            label: Text(s.addSlot),
            onPressed: _addSlot,
          ),
        ],
      ),
    );
  }

  Widget _buildSlotCard(AppStrings s, int index, WorkoutSlot slot) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // العنوان ورقم الخانة وزر الحذف
            Row(
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: _navy,
                  child: Text(
                    '${index + 1}',
                    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  s.slotTitle(index),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: _navy),
                ),
                const Spacer(),
                IconButton(
                  tooltip: s.removeSlot,
                  icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 22),
                  onPressed: () => _removeSlot(index),
                ),
              ],
            ),
            const Divider(height: 16),

            // الحقول الثلاثة الإلزامية: نوع التمرين، ميعاد التمرين بالساعة، والزون المستهدف
            Row(
              children: [
                // 1. نوع التمرين (إرج، ماء، جري، مرونة، قوة، لياقة)
                Expanded(
                  flex: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.workoutType, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black54)),
                      const SizedBox(height: 4),
                      DropdownButtonFormField<String>(
                        value: ProgramService.workoutKinds.contains(slot.kind) ? slot.kind : 'إرج',
                        decoration: InputDecoration(
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        items: ProgramService.workoutKinds.map((k) {
                          return DropdownMenuItem(value: k, child: Text(k, style: const TextStyle(fontSize: 14)));
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) _updateSlotKind(index, val);
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),

                // 2. ميعاد التمرين بالساعة
                Expanded(
                  flex: 2,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.workoutTime, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black54)),
                      const SizedBox(height: 4),
                      InkWell(
                        onTap: () => _pickTime(index),
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey.shade400),
                            borderRadius: BorderRadius.circular(8),
                            color: Colors.grey.shade50,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                slot.time,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: _navy),
                              ),
                              const Icon(Icons.access_time, size: 18, color: _navy),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),

                // 3. الزون المستهدف (Z1 إلى Z5)
                Expanded(
                  flex: 2,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.selectZone, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black54)),
                      const SizedBox(height: 4),
                      DropdownButtonFormField<String>(
                        value: ProgramService.targetZones.contains(slot.zone) ? slot.zone : 'Z2',
                        decoration: InputDecoration(
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        items: ProgramService.targetZones.map((z) {
                          return DropdownMenuItem(
                            value: z,
                            child: Text(z, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) _updateSlotZone(index, val);
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomActionBar(AppStrings s, int currentCount) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            offset: const Offset(0, -2),
            blurRadius: 8,
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              flex: 2,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 48),
                  side: const BorderSide(color: _navy),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: const Icon(Icons.add, color: _navy),
                label: Text(s.addSlot, style: const TextStyle(color: _navy, fontWeight: FontWeight.bold)),
                onPressed: currentCount < 6 ? _addSlot : null,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 3,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(0, 48),
                  backgroundColor: _navy,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: _isSaving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.save),
                label: Text(s.save, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                onPressed: _isSaving ? null : _saveCurrentTemplate,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
