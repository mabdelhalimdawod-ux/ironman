import 'package:flutter/material.dart';
import 'db.dart';
import 'app_strings.dart';
import 'engine_rowing_ui.dart';
import 'program_service.dart';
import 'athlete_day_entry_page.dart';
import 'metrics_curve_page.dart';

const Color _navy = EngineRowingUI.bgNavy;
const Color _cardFill = EngineRowingUI.cardFill;
const Color _gold = EngineRowingUI.neonLime;
const Color _gridLine = EngineRowingUI.bgGridLine;

/// تاب "التمارين" (Workouts Tab):
/// - هيدر علوي يعرض كل تمارين اليوم الجاية من تاب البرنامج بمواعيدها ونوعها
/// - تحت الهيدر قائمة أسماء اللاعبين
/// - بالضغط على اسم لاعب تدخل لصفحته الفرعية لتسجيل فورمات تمارين اليوم
/// - بعد الحفظ يتم الرجوع تلقائياً واسم اللاعب الذي أتم تسجيل كل تمارين يومه يتغير لونه
class WorkoutsTab extends StatefulWidget {
  const WorkoutsTab({super.key});

  @override
  State<WorkoutsTab> createState() => _WorkoutsTabState();
}

class _WorkoutsTabState extends State<WorkoutsTab> {
  DateTime _selectedDate = DateTime.now();
  List<Map<String, Object?>> _todayWorkouts = [];
  List<Map<String, Object?>> _players = [];
  
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

    // 2. جلب اللاعبين النشطين
    _players = await DB.q('SELECT * FROM players WHERE active=1 ORDER BY name');

    // 3. فحص سجلات كل لاعب لليوم لمعرفة من أتم كل التمارين
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

    if (mounted) setState(() => _loading = false);
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2024),
      lastDate: DateTime(2035),
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
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AthleteDayEntryPage(
          player: player,
          date: dateStr,
          sessions: _todayWorkouts,
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
            child: PinchZoomArea(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                children: [
                  // ══════════════════════════════════════════════════
                  // الهيدر العلوي: يعرض كل تمارين اليوم الجاية من تاب البرنامج بمواعيدها
                  // ══════════════════════════════════════════════════
                  _buildTodayWorkoutsHeader(s, dateStr),
                  const SizedBox(height: 16),

                  // ══════════════════════════════════════════════════
                  // قائمة أسماء اللاعبين
                  // ══════════════════════════════════════════════════
                  _buildPlayersSectionHeader(s, totalSessionsCount),
                  const SizedBox(height: 10),

                  if (_players.isEmpty)
                    _buildNoPlayersCard(s)
                  else
                    ..._players.map((p) => _buildPlayerItem(s, p, totalSessionsCount)),

                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// الهيدر العلوي لحصص اليوم بمواعيدها
  Widget _buildTodayWorkoutsHeader(AppStrings s, String dateStr) {
    return Container(
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
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // شريط اختيار التاريخ وعنوان تمارين اليوم
          Row(
            children: [
              const Icon(Icons.fitness_center, color: _gold, size: 26),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.todaysWorkoutsHeader,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: EngineRowingUI.textWhite,
                      ),
                    ),
                    Text(
                      s.todaysWorkoutsSubtitle,
                      style: const TextStyle(fontSize: 12, color: EngineRowingUI.labelSlate),
                    ),
                  ],
                ),
              ),
              InkWell(
                onTap: _pickDate,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: EngineRowingUI.equationCardFill,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _gridLine),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.calendar_today, color: _gold, size: 16),
                      const SizedBox(width: 6),
                      Directionality(
                        textDirection: TextDirection.ltr,
                        child: Text(
                          RowingNumberFormatter.toEnglishDigits(dateStr),
                          style: const TextStyle(
                            color: EngineRowingUI.textWhite,
                            fontWeight: FontWeight.bold,
                            fontFeatures: [FontFeature.tabularFigures()],
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const MetricsCurvePage()),
                  );
                },
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: _gold.withAlpha(35),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _gold),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.auto_graph_rounded, color: _gold, size: 16),
                      const SizedBox(width: 6),
                      Text(
                        s.curveZone,
                        style: const TextStyle(
                          color: _gold,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
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
                      style: const TextStyle(color: EngineRowingUI.textWhite, fontSize: 13),
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
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Directionality(
                            textDirection: TextDirection.ltr,
                            child: Text(
                              '$kind • ${RowingNumberFormatter.toEnglishDigits(time)}',
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
                            style: const TextStyle(
                              color: _gold,
                              fontWeight: FontWeight.w600,
                              fontSize: 11,
                            ),
                          ),
                        ],
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

    final isAllDone = fullyCompletedCount == _players.length && _players.isNotEmpty;

    return Row(
      children: [
        const Icon(Icons.people_alt, color: _gold, size: 22),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                s.athletesListTitle,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: EngineRowingUI.textWhite,
                ),
              ),
              Text(
                s.tapAthleteToLogMulti,
                style: const TextStyle(fontSize: 12, color: EngineRowingUI.labelSlate),
              ),
            ],
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
                fontSize: 12,
                fontWeight: FontWeight.bold,
                fontFeatures: const [FontFeature.tabularFigures()],
                color: isAllDone ? _gold : EngineRowingUI.labelSlate,
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// عنصر اللاعب في القائمة - يتغير لونه بالكامل عند إكمال تسجيل جميع تمارين اليوم
  Widget _buildPlayerItem(AppStrings s, Map<String, Object?> player, int totalSessions) {
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
            : _gridLine;

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
              // أفاتار اللاعب بلون مميز
              CircleAvatar(
                radius: 20,
                backgroundColor: isFullyCompleted ? _gold : EngineRowingUI.equationCardFill,
                child: Text(
                  name.isNotEmpty ? name[0] : 'P',
                  style: TextStyle(
                    color: isFullyCompleted ? _navy : _gold,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
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
                        fontSize: 16,
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
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
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
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
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
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
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
            const Icon(Icons.person_off_outlined, size: 48, color: EngineRowingUI.captionGrey),
            const SizedBox(height: 12),
            Text(
              s.noActivePlayers,
              style: const TextStyle(fontSize: 16, color: EngineRowingUI.labelSlate),
            ),
          ],
        ),
      ),
    );
  }
}
