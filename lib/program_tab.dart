import 'package:flutter/material.dart';
import 'app_strings.dart';
import 'db.dart';
import 'program_service.dart';
import 'cycle_template_page.dart';

const Color _navy = Color(0xFF0D3B66);
const Color _sky = Color(0xFFE8F4FC);
const Color _gold = Color(0xFFFFC93C);

/// تاب "البرنامج" (Program Tab):
/// يعرض سيكلات مرقمة من 1 إلى 12، كل سيكل بتاريخ بداية ونهاية مرن من أسبوعين لستة أسابيع،
/// وعلامة واضحة على السيكل الشغال حالياً.
/// بالضغط على سيكل معين يتم الدخول لصفحته الفرعية (CycleTemplatePage)
class ProgramTab extends StatefulWidget {
  const ProgramTab({super.key});

  @override
  State<ProgramTab> createState() => _ProgramTabState();
}

class _ProgramTabState extends State<ProgramTab> {
  List<Map<String, Object?>> _cycles = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadCycles();
  }

  Future<void> _loadCycles() async {
    setState(() => _loading = true);
    await ProgramService.ensureTables();
    _cycles = await ProgramService.getAllCycles();
    if (mounted) setState(() => _loading = false);
  }

  /// حوار تعديل تواريخ السيكل بمرونة من 2 إلى 6 أسابيع
  Future<void> _editCycleDates(Map<String, Object?> cycle) async {
    final s = AppStrings.of(context);
    final cycleId = (cycle['id'] as num).toInt();
    final startStr = cycle['start'] as String? ?? dstr(DateTime.now());
    final endStr = cycle['end'] as String? ?? dstr(DateTime.now().add(const Duration(days: 27)));

    DateTime selectedStart = DateTime.tryParse(startStr) ?? DateTime.now();
    DateTime selectedEnd = DateTime.tryParse(endStr) ?? DateTime.now().add(const Duration(days: 27));

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final days = selectedEnd.difference(selectedStart).inDays + 1;
          final weeks = (days / 7).toStringAsFixed(1);
          final isValid = days >= 14 && days <= 42;

          return AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.edit_calendar, color: _navy),
                const SizedBox(width: 8),
                Text('${cycle['name']} - ${s.editCycleDates}'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.cycleDateConstraint,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),

                // تاريخ البداية
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.play_circle_outline, color: _navy),
                  title: Text(s.startDate),
                  subtitle: Text(dstr(selectedStart), style: const TextStyle(fontWeight: FontWeight.bold)),
                  trailing: const Icon(Icons.calendar_today, size: 20),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: selectedStart,
                      firstDate: DateTime(2024),
                      lastDate: DateTime(2035),
                    );
                    if (picked != null) {
                      setDialogState(() {
                        selectedStart = picked;
                        // إذا أصبحت النهاية قبل البداية أو خارج النطاق نعدلها
                        if (selectedEnd.isBefore(selectedStart)) {
                          selectedEnd = selectedStart.add(const Duration(days: 27));
                        }
                      });
                    }
                  },
                ),
                const Divider(),

                // تاريخ النهاية
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.stop_circle_outlined, color: _navy),
                  title: Text(s.endDate),
                  subtitle: Text(dstr(selectedEnd), style: const TextStyle(fontWeight: FontWeight.bold)),
                  trailing: const Icon(Icons.calendar_today, size: 20),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: selectedEnd,
                      firstDate: selectedStart.add(const Duration(days: 13)), // حد أدنى 14 يوم
                      lastDate: selectedStart.add(const Duration(days: 41)),  // حد أقصى 42 يوم
                    );
                    if (picked != null) {
                      setDialogState(() {
                        selectedEnd = picked;
                      });
                    }
                  },
                ),
                const SizedBox(height: 8),

                // مدة السيكل وحالة الصلاحية
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isValid ? Colors.green.shade50 : Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: isValid ? Colors.green.shade300 : Colors.red.shade300),
                  ),
                  child: Row(
                    children: [
                      Icon(isValid ? Icons.check_circle : Icons.warning_amber,
                          size: 18, color: isValid ? Colors.green.shade800 : Colors.red.shade800),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          isValid
                              ? 'المدة: $days يوم ($weeks أسبوع) ✔ صالحة'
                              : 'المدة: $days يوم ($weeks أسبوع) ❌ يجب أن تكون بين 2 و 6 أسابيع',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: isValid ? Colors.green.shade800 : Colors.red.shade800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(s.cancel),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: _navy, foregroundColor: Colors.white),
                onPressed: isValid
                    ? () async {
                        final ok = await ProgramService.updateCycleDates(
                          cycleId: cycleId,
                          start: selectedStart,
                          end: selectedEnd,
                        );
                        if (ok) {
                          Navigator.pop(ctx);
                          _loadCycles();
                        }
                      }
                    : null,
                child: Text(s.save),
              ),
            ],
          );
        },
      ),
    );
  }

  void _openCycleTemplate(Map<String, Object?> cycle) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CycleTemplatePage(
          cycle: cycle,
          onSaved: _loadCycles,
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

    final today = DateTime.now();

    return RefreshIndicator(
      onRefresh: _loadCycles,
      color: _navy,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        children: [
          // رأس الصفحة التعريفي
          _buildHeader(s),
          const SizedBox(height: 16),

          // قائمة السيكلات الـ 12
          ..._cycles.map((c) => _buildCycleCard(s, c, today)),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildHeader(AppStrings s) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: _navy,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.event_repeat, color: _gold, size: 28),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                s.trainingCycles,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: _navy,
                ),
              ),
              Text(
                s.cyclesSubtitle,
                style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCycleCard(AppStrings s, Map<String, Object?> cycle, DateTime today) {
    final cycleId = (cycle['id'] as num?)?.toInt() ?? 1;
    final name = cycle['name'] as String? ?? 'السيكل $cycleId';
    final startStr = cycle['start'] as String? ?? '';
    final endStr = cycle['end'] as String? ?? '';
    final isActive = ProgramService.isCycleActive(cycle, today);

    final start = DateTime.tryParse(startStr) ?? today;
    final end = DateTime.tryParse(endStr) ?? today;
    final totalDays = (end.difference(start).inDays + 1).clamp(1, 100);
    final weeks = (totalDays / 7).toStringAsFixed(1);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: isActive ? 3 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isActive ? _gold : Colors.grey.shade200,
          width: isActive ? 2 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _openCycleTemplate(cycle),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // دائرة رقم السيكل
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: isActive ? _navy : Colors.grey.shade200,
                    child: Text(
                      '$cycleId',
                      style: TextStyle(
                        color: isActive ? _gold : Colors.grey.shade800,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),

                  // اسم السيكل
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: _navy,
                          ),
                        ),
                        Text(
                          '$startStr ➔ $endStr ($weeks أسبوع / $totalDays يوم)',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ),

                  // علامة واضحة على السيكل الشغال حالياً
                  if (isActive)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: _gold.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: _gold, width: 1.2),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.bolt, color: Colors.deepOrange, size: 16),
                          const SizedBox(width: 4),
                          Text(
                            s.activeCycleBadge,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: _navy,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),

              // شريط تقدم السيكل إن كان نشطاً
              if (isActive) ...[
                Builder(
                  builder: (_) {
                    final elapsed = today.difference(start).inDays.clamp(0, totalDays);
                    final progress = (elapsed / totalDays).clamp(0.0, 1.0);
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: LinearProgressIndicator(
                            value: progress,
                            minHeight: 6,
                            backgroundColor: Colors.grey.shade200,
                            valueColor: const AlwaysStoppedAnimation<Color>(_navy),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'مضى $elapsed من $totalDays يوم',
                              style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                            ),
                            Text(
                              'متبقي ${totalDays - elapsed} يوم',
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _navy),
                            ),
                          ],
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 8),
              ],

              // أزرار العمليات (تعديل التواريخ والدخول للقالب)
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    style: TextButton.styleFrom(foregroundColor: Colors.grey.shade800),
                    icon: const Icon(Icons.edit_calendar, size: 16),
                    label: Text(s.editCycleDates, style: const TextStyle(fontSize: 13)),
                    onPressed: () => _editCycleDates(cycle),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isActive ? _navy : Colors.grey.shade100,
                      foregroundColor: isActive ? Colors.white : _navy,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    icon: const Icon(Icons.tune, size: 16),
                    label: Text(s.weeklyTemplateTitle, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                    onPressed: () => _openCycleTemplate(cycle),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
