import 'package:flutter/material.dart';
import 'db.dart';
import 'app_strings.dart';
import 'auth_service.dart';
import 'engine_rowing_ui.dart';
import 'program_service.dart';
import 'athlete_day_entry_page.dart';
import 'metrics_curve_page.dart';
import 'session_lock_service.dart';
import 'user_avatar_widget.dart';

const Color _navy = EngineRowingUI.bgNavy;
const Color _cardFill = EngineRowingUI.cardFill;
const Color _gold = EngineRowingUI.neonLime;
const Color _gridLine = EngineRowingUI.bgGridLine;

/// تاب "التمارين" (Workouts Tab):
/// - للمدرب: هيدر علوي يعرض كل تمارين اليوم وقائمة بكل اللاعبين لتسجيل ومتابعة حصصهم بصلاحية كاملة.
/// - للاعب: شاشة مخصصة لتمارين اللاعب نفسه فقط مفلترة على رقم حسابه بدون قائمة لاعبين ومع تطبيق قواعد قفل التعديل.
class WorkoutsTab extends StatefulWidget {
  final AppUser? user;

  const WorkoutsTab({super.key, this.user});

  @override
  State<WorkoutsTab> createState() => _WorkoutsTabState();
}

class _WorkoutsTabState extends State<WorkoutsTab> {
  DateTime _selectedDate = DateTime.now();
  List<Map<String, Object?>> _todayWorkouts = [];
  List<Map<String, Object?>> _players = [];
  List<ScheduledSessionInfo> _allScheduledSessions = [];
  List<Map<String, Object?>> _athleteTodayLogs = [];

  // خريطة لتتبع عدد التمارين المسجلة لكل لاعب اليوم: playerId -> count of logged sessions
  final Map<int, int> _playerCompletedCounts = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    final dateStr = dstr(_selectedDate);

    // 1. جلب تمارين اليوم الجاية من تاب البرنامج وقالب السيكل النشط بمواعيدها
    _todayWorkouts = await ProgramService.getTodayWorkouts(_selectedDate);

    // 2. جلب جميع حصص البرنامج لحساب حالة القفل
    final sessionRows = await DB.q(
        'SELECT date, idx, kind, zone, time FROM sessions ORDER BY date ASC, idx ASC');
    _allScheduledSessions = sessionRows
        .map((r) => ScheduledSessionInfo(
              date: r['date'] as String? ?? dateStr,
              idx: (r['idx'] as num?)?.toInt() ?? 0,
              time: (r['time'] as String?) ?? '07:00',
              kind: (r['kind'] as String?) ?? 'Erg',
              zone: (r['zone'] as String?) ?? 'Z2',
            ))
        .toList();

    final isAthlete = widget.user?.isAthlete == true;

    if (isAthlete) {
      // ── وضع اللاعب: جلب بيانات اللاعب نفسه فقط وتصفية الاستعلام لمنع أي تسريب لبيانات لاعب آخر ──
      _players = [];
      final pid = widget.user?.playerId;
      if (pid != null) {
        try {
          _players = await DB.q('''
            SELECT p.*, u.photo_path 
            FROM players p 
            LEFT JOIN users u ON u.player_id = p.id 
            WHERE p.id = ?
          ''', [pid]);
        } catch (_) {
          _players = await DB.q('SELECT * FROM players WHERE id = ?', [pid]);
        }
      }
      if (_players.isEmpty && widget.user != null) {
        try {
          _players = await DB.q('''
            SELECT p.*, u.photo_path 
            FROM players p 
            LEFT JOIN users u ON u.player_id = p.id 
            WHERE p.name = ? LIMIT 1
          ''', [widget.user!.name]);
        } catch (_) {
          _players = await DB.q('SELECT * FROM players WHERE name = ? LIMIT 1',
              [widget.user!.name]);
        }
      }

      final activePlayerId =
          _players.isNotEmpty ? (_players.first['id'] as int) : -1;
      _athleteTodayLogs = await DB.q(
        'SELECT * FROM logs WHERE player_id = ?',
        [activePlayerId],
      );

      _playerCompletedCounts.clear();
      final todayCount =
          _athleteTodayLogs.where((l) => l['date'] == dateStr).length;
      if (activePlayerId > 0) {
        _playerCompletedCounts[activePlayerId] = todayCount;
      }
    } else {
      // ── وضع المدرب: جلب كل اللاعبين النشطين ──
      try {
        _players = await DB.q('''
          SELECT p.*, u.photo_path 
          FROM players p 
          LEFT JOIN users u ON u.player_id = p.id 
          WHERE p.active = 1 
          ORDER BY p.name ASC
        ''');
      } catch (_) {
        _players =
            await DB.q('SELECT * FROM players WHERE active=1 ORDER BY name');
      }

      _playerCompletedCounts.clear();
      final todayLogs = await DB.q(
        'SELECT player_id, COUNT(DISTINCT idx) as cnt FROM logs WHERE date = ? GROUP BY player_id',
        [dateStr],
      );

      for (final row in todayLogs) {
        final pid = row['player_id'] as int;
        final cnt = (row['cnt'] as num?)?.toInt() ?? 0;
        _playerCompletedCounts[pid] = cnt;
      }
    }

    if (mounted) setState(() => _loading = false);
  }

  Future<void> _pickDate() async {
    final isAthlete = widget.user?.isAthlete == true;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final minDate =
        isAthlete ? today.subtract(const Duration(days: 7)) : DateTime(2024);
    final maxDate =
        isAthlete ? today.add(const Duration(days: 7)) : DateTime(2035);

    DateTime initial = _selectedDate;
    if (initial.isBefore(minDate)) initial = minDate;
    if (initial.isAfter(maxDate)) initial = maxDate;

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: minDate,
      lastDate: maxDate,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: _gold,
              onPrimary: _navy,
              surface: _cardFill,
              onSurface: EngineRowingUI.textWhite,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() => _selectedDate = picked);
      _loadAll();
    }
  }

  void _openAthleteEntry(Map<String, Object?> player) async {
    final dateStr = dstr(_selectedDate);
    final isAthlete = widget.user?.isAthlete == true;
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AthleteDayEntryPage(
          player: player,
          date: dateStr,
          sessions: _todayWorkouts,
          userRole: isAthlete ? 'athlete' : 'coach',
          allScheduledSessions: _allScheduledSessions,
        ),
      ),
    );

    // إذا تم الحفظ، نعيد تحميل البيانات فوراً ليتغير لون اسم اللاعب
    if (result == true || mounted) {
      _loadAll();
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final dateStr = dstr(_selectedDate);

    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: _gold));
    }

    final isAthlete = widget.user?.isAthlete == true;
    final totalSessionsCount = _todayWorkouts.length;

    return Container(
      color: _navy,
      child: RefreshIndicator(
        onRefresh: _loadAll,
        color: _gold,
        backgroundColor: _cardFill,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 850),
            child: isAthlete
                ? _buildAthleteView(s, dateStr)
                : _buildCoachView(s, dateStr, totalSessionsCount),
          ),
        ),
      ),
    );
  }

  /// واجهة المدرب: قائمة بكل اللاعبين وإحصائيات الحصص
  Widget _buildCoachView(AppStrings s, String dateStr, int totalSessionsCount) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      children: [
        _buildTodayWorkoutsHeader(s, dateStr),
        const SizedBox(height: 16),
        _buildPlayersSectionHeader(s, totalSessionsCount),
        const SizedBox(height: 10),
        if (_players.isEmpty)
          _buildNoPlayersCard(s)
        else
          ..._players.map((p) => _buildPlayerItem(s, p, totalSessionsCount)),
        const SizedBox(height: 24),
      ],
    );
  }

  /// واجهة اللاعب: خاصة بتمارينه هو فقط، بدون قائمة أي لاعبين آخرين
  Widget _buildAthleteView(AppStrings s, String dateStr) {
    if (_players.isEmpty) {
      return ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        children: [
          _buildTodayWorkoutsHeader(s, dateStr),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: _cardFill,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _gridLine),
            ),
            child: Column(
              children: [
                const Icon(Icons.person_off_rounded,
                    color: EngineRowingUI.labelSlate, size: 40),
                const SizedBox(height: 12),
                Text(
                  s.isArabic
                      ? 'لم يتم ربط حسابك بملف لاعب بعد. يرجى مراجعة المدرب.'
                      : 'No athlete profile linked to your account. Please consult your coach.',
                  style: const TextStyle(
                      color: EngineRowingUI.labelSlate, fontSize: 14),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ],
      );
    }

    final athlete = _players.first;

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      children: [
        _buildTodayWorkoutsHeader(s, dateStr),
        const SizedBox(height: 16),

        // بطاقة ملخص تمرين اليوم للاعب وزر فتح التسجيل
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _cardFill,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _gold.withAlpha(140)),
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
              LayoutBuilder(
                builder: (context, constraints) {
                  final isCompact = constraints.maxWidth < 340;
                  final infoRow = Row(
                    children: [
                      UserAvatarWidget(
                        photoPath: (athlete['photo_path'] as String?) ??
                            widget.user?.photoPath,
                        radius: 22,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              athlete['name'] as String? ??
                                  (s.isArabic
                                      ? 'بطل التجديف'
                                      : 'Rowing Athlete'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: EngineRowingUI.textWhite,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              s.athleteWorkoutTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 12,
                                  color: EngineRowingUI.labelSlate),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );

                  final logBtn = ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _gold,
                      foregroundColor: _navy,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      elevation: 2,
                    ),
                    icon: const Icon(Icons.edit_note_rounded, size: 18),
                    label: Text(
                      s.isArabic ? 'تسجيل الأرقام' : 'Log Workout',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    onPressed: () => _openAthleteEntry(athlete),
                  );

                  if (isCompact) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        infoRow,
                        const SizedBox(height: 12),
                        logBtn,
                      ],
                    );
                  }

                  return Row(
                    children: [
                      Expanded(child: infoRow),
                      const SizedBox(width: 8),
                      logBtn,
                    ],
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),

        // عنوان قائمة الحصص
        Row(
          children: [
            const Icon(Icons.event_note_rounded, color: _gold, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                s.isArabic
                    ? 'حصص اليوم التدريبية وحالة القفل:'
                    : "Today's Sessions & Lock Status:",
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: EngineRowingUI.textWhite,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        if (_todayWorkouts.isEmpty)
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: _cardFill,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _gridLine),
            ),
            child: Text(
              s.noScheduledSessionsForDate,
              style: const TextStyle(
                  color: EngineRowingUI.labelSlate, fontSize: 13),
            ),
          )
        else
          ..._todayWorkouts.map((w) {
            final idx = (w['idx'] as num?)?.toInt() ?? 0;
            final time = w['time'] as String? ?? '07:00';
            final kind = w['kind'] as String? ?? 'Erg';
            final zone = w['zone'] as String? ?? 'Z2';

            final sessionInfo = ScheduledSessionInfo(
              date: dateStr,
              idx: idx,
              time: time,
              kind: kind,
              zone: zone,
            );

            final lockReason = SessionLockService.checkLockReason(
              session: sessionInfo,
              allSessions: _allScheduledSessions,
              athleteLogs: _athleteTodayLogs,
              userRole: 'athlete',
            );

            final isLocked = (lockReason != SessionLockReason.none);

            String statusLabel;
            Color statusColor;
            IconData statusIcon;

            if (lockReason == SessionLockReason.notStartedYet) {
              statusLabel = s.sessionNotStartedNotice;
              statusColor = Colors.amber;
              statusIcon = Icons.schedule_rounded;
            } else if (isLocked) {
              statusLabel = s.sessionLockedNotice;
              statusColor = Colors.redAccent;
              statusIcon = Icons.lock_rounded;
            } else {
              statusLabel = s.sessionOpenNotice;
              statusColor = Colors.greenAccent;
              statusIcon = Icons.check_circle_outline;
            }

            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _cardFill,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isLocked ? _gridLine : _gold.withAlpha(140),
                  width: isLocked ? 1.0 : 1.3,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: EngineRowingUI.equationCardFill,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: _gridLine),
                    ),
                    child: Directionality(
                      textDirection: TextDirection.ltr,
                      child: Text(
                        time,
                        style: const TextStyle(
                          color: _gold,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$kind ($zone)',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: EngineRowingUI.textWhite,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            Icon(statusIcon, color: statusColor, size: 14),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                statusLabel,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: statusColor,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      isLocked
                          ? Icons.visibility_rounded
                          : Icons.edit_note_rounded,
                      color: isLocked ? EngineRowingUI.labelSlate : _gold,
                      size: 22,
                    ),
                    tooltip: isLocked
                        ? (s.isArabic
                            ? 'عرض الأرقام (قراءة فقط)'
                            : 'View numbers (Read-only)')
                        : (s.isArabic ? 'تسجيل أرقام الحصة' : 'Log session'),
                    onPressed: () => _openAthleteEntry(athlete),
                  ),
                ],
              ),
            );
          }),

        const SizedBox(height: 24),
      ],
    );
  }

  /// الهيدر العلوي لحصص اليوم بمواعيدها
  Widget _buildTodayWorkoutsHeader(AppStrings s, String dateStr) {
    return Container(
      decoration: EngineRowingUI.neonGlowBoxDecoration(
        backgroundColor: _cardFill,
        borderColor: _gold,
        borderRadius: 14,
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // العنوان الرئيسي في سطر كامل بعرض اللوحة بدون انقسام
          Row(
            children: [
              const Icon(Icons.fitness_center, color: _gold, size: 28),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  s.todaysWorkoutsHeader,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: EngineRowingUI.textWhite,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            s.todaysWorkoutsSubtitle,
            style:
                const TextStyle(fontSize: 14, color: EngineRowingUI.labelSlate),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 12),
          // سطر خيارات التحكم بالكامل أسفل العنوان لمنع أي تضارب أو Overflow
          Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              InkWell(
                onTap: _pickDate,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: EngineRowingUI.equationCardFill,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _gridLine),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.calendar_today, color: _gold, size: 18),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Directionality(
                          textDirection: TextDirection.ltr,
                          child: Text(
                            RowingNumberFormatter.toEnglishDigits(dateStr),
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: EngineRowingUI.textWhite,
                              fontWeight: FontWeight.bold,
                              fontFeatures: [FontFeature.tabularFigures()],
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              InkWell(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const MetricsCurvePage()),
                  );
                },
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: _gold.withAlpha(35),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _gold),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.auto_graph_rounded,
                          color: _gold, size: 18),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          s.curveZone,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: _gold,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const Divider(color: _gridLine, height: 20),

          // عرض كل تمارين اليوم بمواعيدها وأنواعها والزون
          if (_todayWorkouts.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
              decoration: BoxDecoration(
                color: EngineRowingUI.equationCardFill,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _gridLine),
              ),
              child: Row(
                children: [
                  const Icon(Icons.nightlight_round, color: _gold, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      s.noWorkoutsToday,
                      style: const TextStyle(
                          color: EngineRowingUI.textWhite, fontSize: 13),
                    ),
                  ),
                ],
              ),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: List.generate(_todayWorkouts.length, (idx) {
                final session = _todayWorkouts[idx];
                final time = session['time'] as String? ?? '07:00';
                final kind = session['kind'] as String? ?? 'Erg';
                final zone = session['zone'] as String? ?? 'Z2';

                return Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: EngineRowingUI.equationCardFill,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _gridLine),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: _gold,
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          '${idx + 1}',
                          style: const TextStyle(
                            color: _navy,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Directionality(
                              textDirection: TextDirection.ltr,
                              child: Text(
                                '$kind • ${RowingNumberFormatter.toEnglishDigits(time)}',
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: EngineRowingUI.textWhite,
                                  fontWeight: FontWeight.bold,
                                  fontFeatures: [FontFeature.tabularFigures()],
                                  fontSize: 13,
                                ),
                              ),
                            ),
                            Text(
                              'Zone: $zone',
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: _gold,
                                fontWeight: FontWeight.w600,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ),
        ],
      ),
    );
  }

  Widget _buildPlayersSectionHeader(AppStrings s, int totalSessions) {
    int fullyCompletedCount = 0;
    if (totalSessions > 0) {
      for (final p in _players) {
        final pid = p['id'] as int;
        final logged = _playerCompletedCounts[pid] ?? 0;
        if (logged >= totalSessions) {
          fullyCompletedCount++;
        }
      }
    }

    final isAllDone =
        fullyCompletedCount == _players.length && _players.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.people_alt, color: _gold, size: 26),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                s.athletesListTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: EngineRowingUI.textWhite,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: EngineRowingUI.equationCardFill,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isAllDone ? _gold : _gridLine,
                ),
              ),
              child: Directionality(
                textDirection: TextDirection.ltr,
                child: Text(
                  '${RowingNumberFormatter.toEnglishDigits(fullyCompletedCount.toString())} / ${RowingNumberFormatter.toEnglishDigits(_players.length.toString())} Done',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    color: isAllDone ? _gold : EngineRowingUI.labelSlate,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          s.tapAthleteToLogMulti,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style:
              const TextStyle(fontSize: 14, color: EngineRowingUI.labelSlate),
        ),
      ],
    );
  }

  /// عنصر اللاعب في القائمة - يتغير لونه بالكامل عند إكمال تسجيل جميع تمارين اليوم
  Widget _buildPlayerItem(
      AppStrings s, Map<String, Object?> player, int totalSessions) {
    final pid = player['id'] as int;
    final name = player['name'] as String? ?? '';
    final mhr = player['mhr'] as int? ?? 190;
    final loggedCount = _playerCompletedCounts[pid] ?? 0;

    final isFullyCompleted = totalSessions > 0 && loggedCount >= totalSessions;
    final isPartiallyCompleted = loggedCount > 0 && loggedCount < totalSessions;

    // ألوان الحالة
    final Color cardBg = _cardFill;

    final Color borderColor = isFullyCompleted
        ? _gold
        : isPartiallyCompleted
            ? const Color(0xFFFF9100)
            : _gold.withAlpha(140);

    final Color nameColor = isFullyCompleted
        ? _gold // يتغير لون اسم اللاعب للفسفوري عند إكمال كل تمارين يومه!
        : isPartiallyCompleted
            ? const Color(0xFFFF9100)
            : EngineRowingUI.textWhite;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      color: cardBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: borderColor, width: isFullyCompleted ? 1.5 : 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _openAthleteEntry(player),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              // أفاتار اللاعب
              UserAvatarWidget(
                photoPath: player['photo_path'] as String?,
                radius: 20,
              ),
              const SizedBox(width: 12),

              // اسم اللاعب وتفاصيله (اللون يتغير هنا مباشرة)
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: nameColor, // تغيير لون اسم اللاعب!
                      ),
                    ),
                    const SizedBox(height: 2),
                    Directionality(
                      textDirection: TextDirection.ltr,
                      child: Text(
                        '${s.maxHRLabel}: ${RowingNumberFormatter.toEnglishDigits(mhr.toString())} bpm',
                        style: const TextStyle(
                          fontSize: 12,
                          color: EngineRowingUI.labelSlate,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // شارة حالة إكمال التمارين لليوم
              if (isFullyCompleted)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: _gold,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.check_circle, color: _navy, size: 15),
                      const SizedBox(width: 4),
                      Text(
                        s.allWorkoutsCompleted,
                        style: const TextStyle(
                          color: _navy,
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                )
              else if (isPartiallyCompleted)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF9100),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    s.partialWorkoutsCompleted(loggedCount, totalSessions),
                    style: const TextStyle(
                      color: _navy,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                )
              else
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: EngineRowingUI.equationCardFill,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _gridLine),
                  ),
                  child: Text(
                    s.noWorkoutsCompletedYet,
                    style: const TextStyle(
                      color: EngineRowingUI.captionGrey,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                ),

              const SizedBox(width: 6),
              Icon(
                Icons.chevron_left_rounded,
                color: isFullyCompleted ? _gold : EngineRowingUI.captionGrey,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNoPlayersCard(AppStrings s) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Icon(Icons.person_off_outlined,
                size: 48, color: EngineRowingUI.captionGrey),
            const SizedBox(height: 12),
            Text(
              s.noActivePlayers,
              style: const TextStyle(
                  fontSize: 16, color: EngineRowingUI.labelSlate),
            ),
          ],
        ),
      ),
    );
  }
}
