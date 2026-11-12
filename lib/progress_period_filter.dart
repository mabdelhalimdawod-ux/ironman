import 'package:flutter/material.dart';
import 'app_strings.dart';
import 'db.dart';
import 'engine_rowing_ui.dart';

/// أوضاع فلتر المدة المشترك في شاشات Progress
enum ProgressPeriodMode {
  week,
  cycle,
  custom,
}

/// ملخص سايكل من جداول Program لعرضه في فلتر السايكل
class ProgramCycleSummary {
  final int id;
  final String name;
  final DateTime start;
  final DateTime end;

  const ProgramCycleSummary({
    required this.id,
    required this.name,
    required this.start,
    required this.end,
  });
}

/// القيمة المختارة الحالية لفلتر المدة
class ProgressPeriodSelection {
  final ProgressPeriodMode mode;
  final DateTime start;
  final DateTime end;
  final int? cycleId;
  final String? cycleName;

  const ProgressPeriodSelection({
    required this.mode,
    required this.start,
    required this.end,
    this.cycleId,
    this.cycleName,
  });

  /// الافتراضي: آخر 7 أيام شاملة اليوم
  factory ProgressPeriodSelection.defaultWeek([DateTime? anchor]) {
    final now = anchor ?? DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return ProgressPeriodSelection(
      mode: ProgressPeriodMode.week,
      start: today.subtract(const Duration(days: 6)),
      end: today,
    );
  }
}

/// عنصر فلتر المدة الوحيد المشترك في تبويب Progress:
/// - أسبوع / Week (آخر 7 أيام افتراضياً + اختيار أي أسبوع آخر)
/// - سايكل / Cycle (مرتبط بجدول السايكلات في Program؛ بدون كراش لو لا توجد سايكلات)
/// - مدة مخصصة / Custom range (من التقويم)
class ProgressPeriodFilter extends StatefulWidget {
  final ProgressPeriodSelection selection;
  final ValueChanged<ProgressPeriodSelection> onChanged;
  final Future<List<ProgramCycleSummary>> Function()? cyclesLoader;

  const ProgressPeriodFilter({
    super.key,
    required this.selection,
    required this.onChanged,
    this.cyclesLoader,
  });

  /// جلب السايكلات المسجلة من جداول البرنامج (program_cycles ثم cycles) بأمان تام
  static Future<List<ProgramCycleSummary>> loadCyclesFromDb() async {
    final result = <ProgramCycleSummary>[];
    try {
      final rows = await DB.q(
        'SELECT id, name, start_date, end_date FROM program_cycles ORDER BY start_date DESC',
      );
      for (final r in rows) {
        final s = DateTime.tryParse((r['start_date'] as String? ?? '').trim());
        final e = DateTime.tryParse((r['end_date'] as String? ?? '').trim());
        if (s != null && e != null) {
          result.add(ProgramCycleSummary(
            id: (r['id'] as num?)?.toInt() ?? 0,
            name: (r['name'] as String?) ?? '',
            start: DateTime(s.year, s.month, s.day),
            end: DateTime(e.year, e.month, e.day),
          ));
        }
      }
    } catch (_) {}

    if (result.isEmpty) {
      try {
        final rows = await DB.q(
          'SELECT id, name, start, end FROM cycles ORDER BY start DESC',
        );
        for (final r in rows) {
          final s = DateTime.tryParse((r['start'] as String? ?? '').trim());
          final e = DateTime.tryParse((r['end'] as String? ?? '').trim());
          if (s != null && e != null) {
            result.add(ProgramCycleSummary(
              id: (r['id'] as num?)?.toInt() ?? 0,
              name: (r['name'] as String?) ?? '',
              start: DateTime(s.year, s.month, s.day),
              end: DateTime(e.year, e.month, e.day),
            ));
          }
        }
      } catch (_) {}
    }
    return result;
  }

  @override
  State<ProgressPeriodFilter> createState() => _ProgressPeriodFilterState();
}

class _ProgressPeriodFilterState extends State<ProgressPeriodFilter> {
  List<ProgramCycleSummary> _cycles = const [];
  bool _loadingCycles = false;
  bool _cyclesLoadedOnce = false;

  @override
  void initState() {
    super.initState();
    if (widget.selection.mode == ProgressPeriodMode.cycle) {
      _fetchCycles(autoSelectIfMissing: false);
    }
  }

  Future<void> _fetchCycles({required bool autoSelectIfMissing}) async {
    if (!mounted) return;
    setState(() => _loadingCycles = true);
    List<ProgramCycleSummary> fetched = const [];
    try {
      final loader = widget.cyclesLoader ?? ProgressPeriodFilter.loadCyclesFromDb;
      fetched = await loader();
    } catch (_) {
      fetched = const [];
    }
    if (!mounted) return;
    setState(() {
      _cycles = fetched;
      _loadingCycles = false;
      _cyclesLoadedOnce = true;
    });

    if (autoSelectIfMissing && fetched.isNotEmpty) {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final active = fetched.cast<ProgramCycleSummary?>().firstWhere(
            (c) =>
                c != null &&
                !today.isBefore(c.start) &&
                !today.isAfter(c.end),
            orElse: () => fetched.first,
          )!;
      widget.onChanged(ProgressPeriodSelection(
        mode: ProgressPeriodMode.cycle,
        start: active.start,
        end: active.end,
        cycleId: active.id,
        cycleName: active.name,
      ));
    }
  }

  Future<void> _onModeTapped(ProgressPeriodMode mode) async {
    if (mode == ProgressPeriodMode.week) {
      widget.onChanged(ProgressPeriodSelection.defaultWeek());
      return;
    }

    if (mode == ProgressPeriodMode.cycle) {
      if (!_cyclesLoadedOnce) {
        // التبديل لوضع السايكل وإظهار النتيجة فوراً سواء وجدت سايكلات أو رسالة "لسه مفيش سايكلات متسجلة"
        widget.onChanged(ProgressPeriodSelection(
          mode: ProgressPeriodMode.cycle,
          start: widget.selection.start,
          end: widget.selection.end,
          cycleId: widget.selection.cycleId,
          cycleName: widget.selection.cycleName,
        ));
        await _fetchCycles(autoSelectIfMissing: true);
      } else if (_cycles.isNotEmpty) {
        final selected = _cycles.cast<ProgramCycleSummary?>().firstWhere(
              (c) => c?.id == widget.selection.cycleId,
              orElse: () => _cycles.first,
            )!;
        widget.onChanged(ProgressPeriodSelection(
          mode: ProgressPeriodMode.cycle,
          start: selected.start,
          end: selected.end,
          cycleId: selected.id,
          cycleName: selected.name,
        ));
      } else {
        widget.onChanged(ProgressPeriodSelection(
          mode: ProgressPeriodMode.cycle,
          start: widget.selection.start,
          end: widget.selection.end,
        ));
      }
      return;
    }

    if (mode == ProgressPeriodMode.custom) {
      await _pickCustomRange();
    }
  }

  Future<void> _pickAnyWeek() async {
    final s = AppStrings.of(context);
    final picked = await showDatePicker(
      context: context,
      initialDate: widget.selection.start,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
      helpText: s.pickWeekTooltip,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: EngineRowingUI.neonLime,
              onPrimary: EngineRowingUI.bgNavy,
              surface: EngineRowingUI.cardFill,
              onSurface: EngineRowingUI.textWhite,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && mounted) {
      final startDay = DateTime(picked.year, picked.month, picked.day);
      final endDay = startDay.add(const Duration(days: 6));
      widget.onChanged(ProgressPeriodSelection(
        mode: ProgressPeriodMode.week,
        start: startDay,
        end: endDay,
      ));
    }
  }

  void _shiftWeek(int deltaDays) {
    final newStart = widget.selection.start.add(Duration(days: deltaDays));
    final newEnd = widget.selection.end.add(Duration(days: deltaDays));
    widget.onChanged(ProgressPeriodSelection(
      mode: ProgressPeriodMode.week,
      start: DateTime(newStart.year, newStart.month, newStart.day),
      end: DateTime(newEnd.year, newEnd.month, newEnd.day),
    ));
  }

  Future<void> _pickCustomRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
      initialDateRange: DateTimeRange(
        start: widget.selection.start,
        end: widget.selection.end,
      ),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: EngineRowingUI.neonLime,
              onPrimary: EngineRowingUI.bgNavy,
              surface: EngineRowingUI.cardFill,
              onSurface: EngineRowingUI.textWhite,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && mounted) {
      widget.onChanged(ProgressPeriodSelection(
        mode: ProgressPeriodMode.custom,
        start: DateTime(
            picked.start.year, picked.start.month, picked.start.day),
        end: DateTime(picked.end.year, picked.end.month, picked.end.day),
      ));
    }
  }

  String _shortRange(DateTime a, DateTime b) => RowingNumberFormatter.toEnglishDigits(
      '${a.day}/${a.month}/${a.year} - ${b.day}/${b.month}/${b.year}');

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final currentMode = widget.selection.mode;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: EngineRowingUI.cardFill,
        border: const Border(
          bottom: BorderSide(color: EngineRowingUI.bgGridLine, width: 1.0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              _buildModeChip(
                label: s.periodFilterWeek,
                icon: Icons.view_week_rounded,
                selected: currentMode == ProgressPeriodMode.week,
                onTap: () => _onModeTapped(ProgressPeriodMode.week),
              ),
              const SizedBox(width: 6),
              _buildModeChip(
                label: s.periodFilterCycle,
                icon: Icons.event_repeat_rounded,
                selected: currentMode == ProgressPeriodMode.cycle,
                onTap: () => _onModeTapped(ProgressPeriodMode.cycle),
              ),
              const SizedBox(width: 6),
              _buildModeChip(
                label: s.periodFilterCustom,
                icon: Icons.date_range_rounded,
                selected: currentMode == ProgressPeriodMode.custom,
                onTap: () => _onModeTapped(ProgressPeriodMode.custom),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (currentMode == ProgressPeriodMode.week)
            _buildWeekControls(s)
          else if (currentMode == ProgressPeriodMode.cycle)
            _buildCycleControls(s)
          else
            _buildCustomControls(s),
        ],
      ),
    );
  }

  Widget _buildModeChip({
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          decoration: BoxDecoration(
            color: selected
                ? EngineRowingUI.neonLime
                : EngineRowingUI.equationCardFill,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected
                  ? EngineRowingUI.neonLime
                  : EngineRowingUI.bgGridLine,
              width: 1.0,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 14,
                color: selected
                    ? EngineRowingUI.bgNavy
                    : EngineRowingUI.labelSlate,
              ),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.bold,
                    color: selected
                        ? EngineRowingUI.bgNavy
                        : EngineRowingUI.textWhite,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWeekControls(AppStrings s) {
    return Row(
      children: [
        Tooltip(
          message: s.prevWeek,
          child: InkWell(
            onTap: () => _shiftWeek(-7),
            borderRadius: BorderRadius.circular(6),
            child: const Padding(
              padding: EdgeInsets.all(5),
              child: Icon(Icons.chevron_left_rounded,
                  color: EngineRowingUI.neonLime, size: 20),
            ),
          ),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: InkWell(
            onTap: _pickAnyWeek,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: EngineRowingUI.equationCardFill,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: EngineRowingUI.bgGridLine),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.calendar_month_rounded,
                      color: EngineRowingUI.neonLime, size: 15),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Directionality(
                      textDirection: TextDirection.ltr,
                      child: Text(
                        _shortRange(
                            widget.selection.start, widget.selection.end),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: EngineRowingUI.textWhite,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 4),
        Tooltip(
          message: s.nextWeek,
          child: InkWell(
            onTap: () => _shiftWeek(7),
            borderRadius: BorderRadius.circular(6),
            child: const Padding(
              padding: EdgeInsets.all(5),
              child: Icon(Icons.chevron_right_rounded,
                  color: EngineRowingUI.neonLime, size: 20),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCycleControls(AppStrings s) {
    if (_loadingCycles) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 6),
        child: LinearProgressIndicator(
          color: EngineRowingUI.neonLime,
          backgroundColor: EngineRowingUI.equationCardFill,
          minHeight: 2,
        ),
      );
    }

    if (_cycles.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: EngineRowingUI.equationCardFill,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: EngineRowingUI.bgGridLine),
        ),
        child: Row(
          children: [
            const Icon(Icons.info_outline_rounded,
                color: EngineRowingUI.labelSlate, size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                s.noCyclesRecorded,
                style: const TextStyle(
                  color: EngineRowingUI.labelSlate,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final currentId = _cycles.any((c) => c.id == widget.selection.cycleId)
        ? widget.selection.cycleId
        : _cycles.first.id;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: EngineRowingUI.equationCardFill,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: EngineRowingUI.neonLime.withValues(alpha: 0.4)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: currentId,
          isExpanded: true,
          dropdownColor: EngineRowingUI.cardFill,
          icon: const Icon(Icons.arrow_drop_down,
              color: EngineRowingUI.neonLime),
          style: const TextStyle(
            color: EngineRowingUI.textWhite,
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
          ),
          items: _cycles.map((c) {
            return DropdownMenuItem<int>(
              value: c.id,
              child: Text(
                '${c.name} (${_shortRange(c.start, c.end)})',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            );
          }).toList(),
          onChanged: (id) {
            if (id == null) return;
            final chosen = _cycles.firstWhere((c) => c.id == id);
            widget.onChanged(ProgressPeriodSelection(
              mode: ProgressPeriodMode.cycle,
              start: chosen.start,
              end: chosen.end,
              cycleId: chosen.id,
              cycleName: chosen.name,
            ));
          },
        ),
      ),
    );
  }

  Widget _buildCustomControls(AppStrings s) {
    return InkWell(
      onTap: _pickCustomRange,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: EngineRowingUI.equationCardFill,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: EngineRowingUI.neonLime.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.date_range_rounded,
                color: EngineRowingUI.neonLime, size: 15),
            const SizedBox(width: 6),
            Flexible(
              child: Directionality(
                textDirection: TextDirection.ltr,
                child: Text(
                  _shortRange(widget.selection.start, widget.selection.end),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: EngineRowingUI.textWhite,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.edit_calendar_rounded,
                color: EngineRowingUI.labelSlate, size: 14),
          ],
        ),
      ),
    );
  }
}
