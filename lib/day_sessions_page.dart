import 'package:flutter/material.dart';
import 'app_strings.dart';
import 'engine_rowing_ui.dart';
import 'program_service.dart';
import 'session_workouts_page.dart';

const Color _navy = EngineRowingUI.bgNavy;
const Color _cardFill = EngineRowingUI.cardFill;
const Color _gold = EngineRowingUI.neonLime;
const Color _gridLine = EngineRowingUI.bgGridLine;

/// المستوى 3: صفحة الحصص التدريبية لهذا اليوم (Day Sessions Page)
/// تبدأ بحصة تدريبية واحدة مع زر (+) لإضافة حصة تدريبية جديدة،
/// ولكل حصة:
/// - وقت الحصة التدريبية
/// - 6 خانات زونات تحسب الثواني والدقائق والساعات للحصة مع تظليل الزونات الفارغة
/// - ملاحظة فنية (+) وملاحظة فسيولوجية (+)
/// - زر (دخول) للدخول لصفحة التمارين
class DaySessionsPage extends StatefulWidget {
  final int cycleId;
  final String cycleType;
  final int dayOfWeek;
  final String dayName;
  final VoidCallback onSaved;

  const DaySessionsPage({
    super.key,
    required this.cycleId,
    required this.cycleType,
    required this.dayOfWeek,
    required this.dayName,
    required this.onSaved,
  });

  @override
  State<DaySessionsPage> createState() => _DaySessionsPageState();
}

class _DaySessionsPageState extends State<DaySessionsPage> {
  List<ProgramDaySession> _sessions = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadSessions();
  }

  Future<void> _loadSessions() async {
    setState(() => _loading = true);
    _sessions = await ProgramService.getDaySessionsDetailed(
      widget.cycleId,
      widget.cycleType,
      widget.dayOfWeek,
    );

    // إذا كانت القائمة فارغة، ننشئ حصة أولية تلقائياً كما طلب المستخدم
    if (_sessions.isEmpty) {
      final s = await ProgramService.addDaySessionDetailed(
        widget.cycleId,
        widget.cycleType,
        widget.dayOfWeek,
      );
      _sessions = [s];
    }

    if (mounted) setState(() => _loading = false);
  }

  Future<void> _addNewSession() async {
    try {
      await ProgramService.addDaySessionDetailed(
        widget.cycleId,
        widget.cycleType,
        widget.dayOfWeek,
      );
      await _loadSessions();
      widget.onSaved();
    } catch (_) {}
  }

  Future<void> _deleteSession(ProgramDaySession session) async {
    final s = AppStrings.of(context);
    if (_sessions.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يجب أن تحتوي الصفحة على حصة تدريبية واحدة على الأقل'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.removeSession),
        content: Text('${session.name}: ${s.removeSessionConfirm}'),
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

    if (confirmed == true && session.id != null) {
      await ProgramService.deleteDaySessionDetailed(session.id!);
      await _loadSessions();
      widget.onSaved();
    }
  }

  Future<void> _pickSessionTime(ProgramDaySession session) async {
    final parts = session.time.split(':');
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
      setState(() => session.time = '$hourStr:$minStr');
      await ProgramService.saveDaySessionDetailed(session);
      widget.onSaved();
    }
  }

  void _editNoteDialog(
      ProgramDaySession session, String title, bool isPhysio) {
    final ctrl = TextEditingController(
        text: isPhysio ? session.notesPhysio : session.notesTech);
    final s = AppStrings.of(context);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _cardFill,
        title: Row(
          children: [
            Icon(isPhysio ? Icons.health_and_safety_outlined : Icons.engineering_outlined,
                color: _gold),
            const SizedBox(width: 8),
            Text('$title - ${session.name}',
                style: const TextStyle(color: EngineRowingUI.textWhite)),
          ],
        ),
        content: TextField(
          controller: ctrl,
          maxLines: 4,
          style: const TextStyle(color: EngineRowingUI.textWhite),
          decoration: InputDecoration(
            hintText: 'اكتب تفاصيل $title...',
            hintStyle: const TextStyle(color: EngineRowingUI.labelSlate),
            border: const OutlineInputBorder(),
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
            onPressed: () async {
              if (isPhysio) {
                session.notesPhysio = ctrl.text.trim();
              } else {
                session.notesTech = ctrl.text.trim();
              }
              await ProgramService.saveDaySessionDetailed(session);
              if (mounted) setState(() {});
              widget.onSaved();
              Navigator.pop(ctx);
            },
            child: Text(s.save),
          ),
        ],
      ),
    );
  }

  void _openWorkouts(ProgramDaySession session) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SessionWorkoutsPage(
          session: session,
          onSaved: () {
            _loadSessions();
            widget.onSaved();
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);

    return Scaffold(
      backgroundColor: _navy,
      appBar: AppBar(
        backgroundColor: _navy,
        foregroundColor: EngineRowingUI.textWhite,
        title: Text('${widget.dayName} - ${s.daySessionsPageTitle}'),
        actions: [
          // زر إضافة حصة تدريبية جديدة في الهيدر
          IconButton(
            tooltip: s.addSession,
            icon: const Icon(Icons.add_circle, color: _gold, size: 26),
            onPressed: _addNewSession,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _gold))
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 850),
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  children: [
                    // هيدر توضيحي
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _cardFill,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: _gridLine),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline_rounded,
                              color: _gold, size: 22),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'الحصص التدريبية ليوم ${widget.dayName} • كل حصة تحتوي على خانة التوقيت، وحسابات الـ 6 زونات، وملاحظات وزر الدخول للتمارين.',
                              style: const TextStyle(
                                  fontSize: 12.5,
                                  color: EngineRowingUI.labelSlate,
                                  height: 1.4),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // ── قائمة لوحات الحصص التدريبية ──
                    ..._sessions.map((session) => _buildSessionPanel(s, session)),

                    const SizedBox(height: 20),

                    // زر إضافة حصة تدريبية أسفل القائمة
                    Center(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _gold,
                          foregroundColor: _navy,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 24, vertical: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          elevation: 2,
                        ),
                        icon: const Icon(Icons.add, size: 20),
                        label: Text(
                          s.addSession,
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.bold),
                        ),
                        onPressed: _addNewSession,
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
    );
  }

  /// لوحة الحصة التدريبية المجسمة بكامل المواصفات المطلوبة
  Widget _buildSessionPanel(AppStrings s, ProgramDaySession session) {
    final zoneDurations = session.zoneDurations;

    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      decoration: BoxDecoration(
        color: _cardFill,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _gridLine, width: 1.2),
        boxShadow: const [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── شريط رأس لوحة الحصة التدريبية ──
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              color: EngineRowingUI.equationCardFill,
              borderRadius:
                  BorderRadius.vertical(top: Radius.circular(13)),
              border: Border(bottom: BorderSide(color: _gridLine, width: 1.0)),
            ),
            child: Row(
              children: [
                const Icon(Icons.sports_score_rounded,
                    color: _gold, size: 24),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    session.name,
                    style: const TextStyle(
                      color: EngineRowingUI.textWhite,
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),

                // ── زرار دخول أعلى لوحة الحصة باللون الذهبي للدخول لصفحة التمارين ──
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _gold,
                    foregroundColor: _navy,
                    elevation: 1,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.login_rounded, size: 18),
                  label: Text(
                    s.enterCycle,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  onPressed: () => _openWorkouts(session),
                ),
                const SizedBox(width: 8),

                // زر حذف الحصة
                if (_sessions.length > 1)
                  IconButton(
                    icon: const Icon(Icons.delete_outline_rounded,
                        color: Colors.redAccent, size: 22),
                    tooltip: s.removeSession,
                    onPressed: () => _deleteSession(session),
                  ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── خانة وقت الحصة ──
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: EngineRowingUI.equationCardFill,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: _gridLine),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.access_time_filled_rounded,
                              size: 18, color: _gold),
                          const SizedBox(width: 8),
                          Directionality(
                            textDirection: TextDirection.ltr,
                            child: Text(
                              '${s.sessionTime}: ${RowingNumberFormatter.toEnglishDigits(session.time)}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13.5,
                                color: EngineRowingUI.textWhite,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          InkWell(
                            onTap: () => _pickSessionTime(session),
                            child: const Icon(Icons.edit_calendar,
                                size: 16, color: _gold),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '• عدد التمارين: ${session.workouts.length}',
                      style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: EngineRowingUI.labelSlate),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // ── الخانات الـ 6 المتجاورة أسفل لوحة الحصة (Z1 - Z5 + Threshold) ──
                // تبدأ من اليسار: zone1, zone2, zone3, zone4, Threshold, zone5
                const Text(
                  'أحمال الزونات لهذه الحصة (تحسب تلقائياً من التمارين):',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: EngineRowingUI.textWhite,
                  ),
                ),
                const SizedBox(height: 8),

                Directionality(
                  textDirection: TextDirection.ltr,
                  child: Row(
                    children: kProgramZones.map((z) {
                      final secs = zoneDurations[z] ?? 0;
                      final isZero = secs == 0;
                      final color = kZoneColors[z] ?? _navy;

                      return Expanded(
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 2.5),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 8),
                          decoration: BoxDecoration(
                            color: isZero
                                ? EngineRowingUI.equationCardFill.withAlpha(120)
                                : color.withAlpha(35),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isZero
                                  ? _gridLine
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
                                  color: isZero ? EngineRowingUI.captionGrey : color,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                isZero
                                    ? '-'
                                    : RowingNumberFormatter.toEnglishDigits(
                                        ProgramService.formatDurationDetailed(secs)),
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures()
                                  ],
                                  color: isZero
                                      ? EngineRowingUI.captionGrey
                                      : EngineRowingUI.textWhite,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 16),
                const Divider(height: 1, color: _gridLine),
                const SizedBox(height: 12),

                // ── الملاحظات الفسيولوجية والفنية ──
                Row(
                  children: [
                    // ملاحظة فسيولوجية (+)
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: EngineRowingUI.equationCardFill,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: _gridLine),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.health_and_safety_outlined,
                                size: 18, color: _gold),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                session.notesPhysio.isNotEmpty
                                    ? session.notesPhysio
                                    : s.physiologicalNote,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: session.notesPhysio.isNotEmpty
                                      ? EngineRowingUI.textWhite
                                      : EngineRowingUI.labelSlate,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.add_circle_outline,
                                  size: 18, color: _gold),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              onPressed: () => _editNoteDialog(
                                  session, s.physiologicalNote, true),
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
                          color: EngineRowingUI.equationCardFill,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: _gridLine),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.engineering_outlined,
                                size: 18, color: _gold),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                session.notesTech.isNotEmpty
                                    ? session.notesTech
                                    : s.technicalNote,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: session.notesTech.isNotEmpty
                                      ? EngineRowingUI.textWhite
                                      : EngineRowingUI.labelSlate,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.add_circle_outline,
                                  size: 18, color: _gold),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              onPressed: () => _editNoteDialog(
                                  session, s.technicalNote, false),
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
