import 'package:flutter/material.dart';
import 'app_strings.dart';
import 'auth_service.dart';
import 'db.dart';
import 'engine_rowing_ui.dart';
import 'program_service.dart';
import 'session_workouts_page.dart';
import 'user_avatar_widget.dart';

/// شاشة «تمرين اليوم» / "Today's Workout"
/// - للاعب: واجهة قراءة فقط تعرض تمارينه المخصصة أو الأصلية مع محدد نطاق تواريخ حتى 7 أيام شاملة كحد أقصى.
/// - للمدرب: عرض قائمة اللاعبين لتصفح تمارينهم للقراءة فقط، مع زر «تعديل» لتخصيص تمرين لاعب وتاريخ معين.
class TodayWorkoutPage extends StatefulWidget {
  final AppUser? user;
  final DateTime? initialDate;

  const TodayWorkoutPage({
    super.key,
    this.user,
    this.initialDate,
  });

  @override
  State<TodayWorkoutPage> createState() => _TodayWorkoutPageState();
}

class _TodayWorkoutPageState extends State<TodayWorkoutPage> {
  bool _loading = true;

  // للمدرب
  List<Map<String, Object?>> _athletes = [];

  // للاعب
  late DateTime _startDate;
  late DateTime _endDate;
  final Map<String, List<ProgramDaySession>> _sessionsByDate = {};

  @override
  void initState() {
    super.initState();
    final today = widget.initialDate ?? DateTime.now();
    _startDate = DateTime(today.year, today.month, today.day);
    _endDate = _startDate;
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    final user = widget.user ?? AuthService.currentUser;

    if (user != null && user.isCoach) {
      try {
        final playersWithPhotos = await DB.q('''
          SELECT p.*, u.photo_path 
          FROM players p 
          LEFT JOIN users u ON u.player_id = p.id 
          WHERE p.active = 1 
          ORDER BY p.name ASC
        ''');
        _athletes = playersWithPhotos;
      } catch (_) {
        _athletes = await DB.players();
      }
    } else {
      await _loadAthleteSessions();
    }

    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadAthleteSessions() async {
    final user = widget.user ?? AuthService.currentUser;
    final playerId = user?.playerId ?? user?.id ?? 0;

    _sessionsByDate.clear();
    var cur = _startDate;
    while (!cur.isAfter(_endDate)) {
      final dateStr = dstr(cur);
      final sessions = await ProgramService.getSessionsForAthleteAndDate(
        playerId: playerId,
        date: cur,
      );
      _sessionsByDate[dateStr] = sessions;
      cur = cur.add(const Duration(days: 1));
    }
  }

  Future<void> _pickDate({required bool isStart}) async {
    final initial = isStart ? _startDate : _endDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: EngineRowingUI.neonLime,
            onPrimary: EngineRowingUI.bgNavy,
            surface: EngineRowingUI.cardFill,
            onSurface: EngineRowingUI.textWhite,
          ),
        ),
        child: child!,
      ),
    );

    if (picked == null) return;
    await updateDateSelection(picked, isStart: isStart);
  }

  @visibleForTesting
  Future<void> updateDateSelection(DateTime picked, {required bool isStart}) async {
    final s = AppStrings.of(context);
    final cleanPicked = DateTime(picked.year, picked.month, picked.day);

    DateTime nextStart = isStart ? cleanPicked : _startDate;
    DateTime nextEnd = isStart ? _endDate : cleanPicked;

    if (nextEnd.isBefore(nextStart)) {
      if (isStart) {
        nextEnd = nextStart;
      } else {
        nextStart = nextEnd;
      }
    }

    // فحص الحد الأقصى 7 أيام شاملة
    final daysDiff = nextEnd.difference(nextStart).inDays + 1;
    if (daysDiff > 7) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(s.maxSevenDaysNotice),
          backgroundColor: Colors.orange.shade800,
        ),
      );
      if (isStart) {
        nextEnd = nextStart.add(const Duration(days: 6));
      } else {
        nextStart = nextEnd.subtract(const Duration(days: 6));
      }
    }

    setState(() {
      _startDate = nextStart;
      _endDate = nextEnd;
    });

    await _loadAthleteSessions();
    if (mounted) setState(() {});
  }

  @visibleForTesting
  DateTime get startDate => _startDate;

  @visibleForTesting
  DateTime get endDate => _endDate;

  void _openSessionReadOnly(ProgramDaySession session) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SessionWorkoutsPage(
          session: session,
          isReadOnly: true,
        ),
      ),
    );
  }

  Future<void> _openCoachAthleteWorkout(Map<String, Object?> athlete) async {
    final playerId = (athlete['id'] as num?)?.toInt() ?? 0;
    final today = DateTime.now();
    final sessions = await ProgramService.getSessionsForAthleteAndDate(
      playerId: playerId,
      date: today,
    );

    if (!mounted) return;
    final s = AppStrings.of(context);

    if (sessions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(s.noWorkoutsToday),
          backgroundColor: EngineRowingUI.cardFill,
        ),
      );
      return;
    }

    if (sessions.length == 1) {
      _openSessionReadOnly(sessions.first);
    } else {
      showModalBottomSheet(
        context: context,
        backgroundColor: EngineRowingUI.cardFill,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: (ctx) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                '${athlete['name'] ?? ''} - ${s.todayWorkout}',
                style: const TextStyle(
                  color: EngineRowingUI.textWhite,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              ...sessions.map((sess) => ListTile(
                    tileColor: EngineRowingUI.equationCardFill,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    leading: const Icon(Icons.fitness_center_rounded,
                        color: EngineRowingUI.neonLime),
                    title: Text(sess.name,
                        style: const TextStyle(
                            color: EngineRowingUI.textWhite,
                            fontWeight: FontWeight.bold)),
                    subtitle: Text('${s.sessionTime}: ${sess.time}',
                        style: const TextStyle(
                            color: EngineRowingUI.labelSlate, fontSize: 12)),
                    onTap: () {
                      Navigator.pop(ctx);
                      _openSessionReadOnly(sess);
                    },
                  )),
            ],
          ),
        ),
      );
    }
  }

  Future<void> _openCoachCustomizeDialog() async {
    final s = AppStrings.of(context);
    int? selectedPlayerId =
        _athletes.isNotEmpty ? (_athletes.first['id'] as num?)?.toInt() : null;
    DateTime selectedDate = DateTime.now();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: EngineRowingUI.cardFill,
          title: Row(
            children: [
              const Icon(Icons.edit_note_rounded,
                  color: EngineRowingUI.neonLime),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  s.editWorkoutForAthlete,
                  style: const TextStyle(
                    color: EngineRowingUI.textWhite,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(s.selectAthlete,
                  style: const TextStyle(
                      color: EngineRowingUI.labelSlate, fontSize: 13)),
              const SizedBox(height: 6),
              DropdownButtonFormField<int>(
                dropdownColor: EngineRowingUI.cardFill,
                initialValue: selectedPlayerId,
                items: _athletes.map((a) {
                  final id = (a['id'] as num?)?.toInt() ?? 0;
                  final name = (a['name'] as String?) ?? '#$id';
                  return DropdownMenuItem<int>(
                    value: id,
                    child: Text(name,
                        style: const TextStyle(
                            color: EngineRowingUI.textWhite,
                            fontWeight: FontWeight.bold)),
                  );
                }).toList(),
                onChanged: (val) => setDialogState(() => selectedPlayerId = val),
                decoration: const InputDecoration(
                  filled: true,
                  fillColor: EngineRowingUI.equationCardFill,
                  border: OutlineInputBorder(),
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),
              const SizedBox(height: 16),
              Text(s.selectDate,
                  style: const TextStyle(
                      color: EngineRowingUI.labelSlate, fontSize: 13)),
              const SizedBox(height: 6),
              InkWell(
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: selectedDate,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2035),
                  );
                  if (picked != null) {
                    setDialogState(() => selectedDate = picked);
                  }
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  decoration: BoxDecoration(
                    color: EngineRowingUI.equationCardFill,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: EngineRowingUI.bgGridLine),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_today_rounded,
                          size: 16, color: EngineRowingUI.neonLime),
                      const SizedBox(width: 8),
                      Text(
                        dstr(selectedDate),
                        style: const TextStyle(
                          color: EngineRowingUI.textWhite,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(s.cancel,
                  style: const TextStyle(color: EngineRowingUI.labelSlate)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: EngineRowingUI.neonLime,
                foregroundColor: EngineRowingUI.bgNavy,
              ),
              onPressed: selectedPlayerId == null
                  ? null
                  : () => Navigator.pop(ctx, true),
              child: Text(s.edit,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true || selectedPlayerId == null) return;

    // جلب حصص اللاعب لهذا التاريخ (أو قالب اليوم إن لم تكن مخصصة)
    final dateStr = dstr(selectedDate);
    final sessions = await ProgramService.getSessionsForAthleteAndDate(
      playerId: selectedPlayerId!,
      date: selectedDate,
    );

    final sessionToEdit = sessions.isNotEmpty
        ? sessions.first
        : ProgramDaySession(
            cycleId: 0,
            cycleType: 'custom',
            dayOfWeek: ProgramService.getWeekdayIndex(selectedDate),
            sessionIdx: 0,
            name: 'الحصة 1',
            time: '07:00',
          );

    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SessionWorkoutsPage(
          session: sessionToEdit,
          isReadOnly: false,
          onSaved: () async {
            await ProgramService.saveAthleteCustomSession(
              playerId: selectedPlayerId!,
              date: dateStr,
              session: sessionToEdit,
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final user = widget.user ?? AuthService.currentUser;
    final isCoach = user?.isCoach == true;

    return Scaffold(
      backgroundColor: EngineRowingUI.bgNavy,
      appBar: AppBar(
        backgroundColor: EngineRowingUI.bgNavy,
        foregroundColor: EngineRowingUI.textWhite,
        title: Text(
          s.todayWorkout,
          style: const TextStyle(
            color: EngineRowingUI.textWhite,
            fontWeight: FontWeight.bold,
            fontSize: 17,
          ),
        ),
        actions: [
          if (isCoach)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 10),
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: EngineRowingUI.neonLime,
                  foregroundColor: EngineRowingUI.bgNavy,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                icon: const Icon(Icons.edit_note_rounded, size: 18),
                label: Text(s.edit,
                    style: const TextStyle(
                        fontSize: 12.5, fontWeight: FontWeight.bold)),
                onPressed: _openCoachCustomizeDialog,
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: RowingGridBackground(
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(
                    color: EngineRowingUI.neonLime,
                  ),
                )
              : (isCoach ? _buildCoachView(s) : _buildAthleteView(s)),
        ),
      ),
    );
  }

  // ── واجهة المدرب: قائمة اللاعبين لتصفح تمارينهم ──
  Widget _buildCoachView(AppStrings s) {
    if (_athletes.isEmpty) {
      return Center(
        child: Text(
          s.noActivePlayers,
          style: const TextStyle(
              color: EngineRowingUI.labelSlate, fontSize: 14),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      itemCount: _athletes.length,
      itemBuilder: (context, index) {
        final athlete = _athletes[index];
        final name = (athlete['name'] as String?) ?? '#${athlete['id']}';
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: EngineRowingUI.cardFill,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: EngineRowingUI.bgGridLine),
          ),
          child: Material(
            color: Colors.transparent,
            child: ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              leading: UserAvatarWidget(
                photoPath: athlete['photo_path'] as String?,
                radius: 20,
              ),
              title: Text(
                name,
                style: const TextStyle(
                  color: EngineRowingUI.textWhite,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
              subtitle: Text(
                s.tapPlayerToLog,
                style: const TextStyle(
                    color: EngineRowingUI.labelSlate, fontSize: 11.5),
              ),
              trailing: const Icon(Icons.chevron_left_rounded,
                  color: EngineRowingUI.labelSlate),
              onTap: () => _openCoachAthleteWorkout(athlete),
            ),
          ),
        );
      },
    );
  }

  // ── واجهة اللاعب: محدد نطاق التاريخ وتمارين الأيام ──
  Widget _buildAthleteView(AppStrings s) {
    final dates = _sessionsByDate.keys.toList()..sort();

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      children: [
        // محدد التاريخ ("من تاريخ" و "إلى تاريخ" بحد أقصى 7 أيام)
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: EngineRowingUI.cardFill,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: EngineRowingUI.bgGridLine),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.date_range_rounded,
                      color: EngineRowingUI.neonLime, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    '${s.fromDate} - ${s.toDate}',
                    style: const TextStyle(
                      color: EngineRowingUI.textWhite,
                      fontWeight: FontWeight.bold,
                      fontSize: 13.5,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: EngineRowingUI.textWhite,
                        side: const BorderSide(color: EngineRowingUI.bgGridLine),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: () => _pickDate(isStart: true),
                      child: Text(
                        '${s.fromDate}: ${dstr(_startDate)}',
                        style: const TextStyle(fontSize: 12),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: EngineRowingUI.textWhite,
                        side: const BorderSide(color: EngineRowingUI.bgGridLine),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: () => _pickDate(isStart: false),
                      child: Text(
                        '${s.toDate}: ${dstr(_endDate)}',
                        style: const TextStyle(fontSize: 12),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        if (dates.isEmpty ||
            dates.every((d) => _sessionsByDate[d]?.isEmpty ?? true))
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: EngineRowingUI.cardFill,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: EngineRowingUI.bgGridLine),
            ),
            child: Center(
              child: Text(
                s.noWorkoutsToday,
                style: const TextStyle(
                  color: EngineRowingUI.labelSlate,
                  fontSize: 13.5,
                ),
              ),
            ),
          )
        else
          ...dates.map((dateStr) {
            final sessions = _sessionsByDate[dateStr] ?? [];
            if (sessions.isEmpty) return const SizedBox.shrink();

            return Container(
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                color: EngineRowingUI.cardFill,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: EngineRowingUI.bgGridLine),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: const BoxDecoration(
                      color: EngineRowingUI.equationCardFill,
                      borderRadius:
                          BorderRadius.vertical(top: Radius.circular(13)),
                      border: Border(
                          bottom: BorderSide(color: EngineRowingUI.bgGridLine)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.event_note_rounded,
                            color: EngineRowingUI.neonLime, size: 16),
                        const SizedBox(width: 8),
                        Text(
                          dateStr,
                          style: const TextStyle(
                            color: EngineRowingUI.neonLime,
                            fontWeight: FontWeight.bold,
                            fontSize: 13.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  ...sessions.map((sess) {
                    final workoutsCount = sess.workouts.length;
                    return Material(
                      color: Colors.transparent,
                      child: ListTile(
                        title: Text(
                          sess.name,
                          style: const TextStyle(
                            color: EngineRowingUI.textWhite,
                            fontWeight: FontWeight.bold,
                            fontSize: 14.5,
                          ),
                        ),
                        subtitle: Text(
                          '${s.sessionTime}: ${sess.time} • $workoutsCount ${s.workout}',
                          style: const TextStyle(
                              color: EngineRowingUI.labelSlate, fontSize: 12),
                        ),
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: EngineRowingUI.neonLime.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                                color: EngineRowingUI.neonLime.withValues(alpha: 0.4)),
                          ),
                          child: Text(
                            s.readOnlyNotice,
                            style: const TextStyle(
                              color: EngineRowingUI.neonLime,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        onTap: () => _openSessionReadOnly(sess),
                      ),
                    );
                  }),
                ],
              ),
            );
          }),
      ],
    );
  }
}
