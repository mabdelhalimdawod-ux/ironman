import 'package:flutter/material.dart';
import 'db.dart';
import 'app_strings.dart';
import 'program_service.dart';
import 'athlete_day_entry_page.dart';

const Color _navy = Color(0xFF0D3B66);
const Color _sky = Color(0xFFE8F4FC);
const Color _gold = Color(0xFFFFC93C);
const Color _green = Color(0xFF2E7D32);

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
      return const Center(child: CircularProgressIndicator(color: _navy));
    }

    final totalSessionsCount = _todayWorkouts.length;

    return RefreshIndicator(
      onRefresh: _loadAll,
      color: _navy,
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
    );
  }

  /// الهيدر العلوي لحصص اليوم بمواعيدها
  Widget _buildTodayWorkoutsHeader(AppStrings s, String dateStr) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: const LinearGradient(
            colors: [_navy, Color(0xFF1B4975)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
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
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        s.todaysWorkoutsSubtitle,
                        style: const TextStyle(fontSize: 12, color: Colors.white70),
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
                      color: Colors.white.withOpacity(0.18),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white30),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.calendar_today, color: _gold, size: 16),
                        const SizedBox(width: 6),
                        Text(
                          dateStr,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const Divider(color: Colors.white24, height: 20),

            // عرض كل تمارين اليوم بمواعيدها وأنواعها والزون
            if (_todayWorkouts.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.nightlight_round, color: _gold, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        s.noWorkoutsToday,
                        style: const TextStyle(color: Colors.white, fontSize: 13),
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
                      color: Colors.white.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: _gold.withOpacity(0.4)),
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
                            Text(
                              '$kind • الساعة $time',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                            Text(
                              'الزون: $zone',
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

    return Row(
      children: [
        const Icon(Icons.people_alt, color: _navy, size: 22),
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
                  color: _navy,
                ),
              ),
              Text(
                s.tapAthleteToLogMulti,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: fullyCompletedCount == _players.length && _players.isNotEmpty
                ? _green.withOpacity(0.15)
                : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: fullyCompletedCount == _players.length && _players.isNotEmpty
                  ? _green
                  : Colors.grey.shade300,
            ),
          ),
          child: Text(
            '$fullyCompletedCount / ${_players.length} مكتمل',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: fullyCompletedCount == _players.length && _players.isNotEmpty
                  ? _green
                  : _navy,
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
    final Color cardBg = isFullyCompleted
        ? const Color(0xFFE8F5E9) // أخضر فاتح مريح
        : isPartiallyCompleted
            ? const Color(0xFFFFF8E1) // عنبري فاتح
            : Colors.white;

    final Color borderColor = isFullyCompleted
        ? _green
        : isPartiallyCompleted
            ? Colors.amber.shade700
            : Colors.grey.shade200;

    final Color nameColor = isFullyCompleted
        ? _green // يتغير لون اسم اللاعب للأخضر عند إكمال كل تمارين يومه!
        : isPartiallyCompleted
            ? Colors.amber.shade900
            : _navy;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: isFullyCompleted ? 2 : 1,
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
                backgroundColor: isFullyCompleted ? _green : _navy,
                child: Text(
                  name.isNotEmpty ? name[0] : 'P',
                  style: TextStyle(
                    color: isFullyCompleted ? Colors.white : _gold,
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
                    Text(
                      '${s.maxHRLabel}: $mhr bpm',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),

              // شارة حالة إكمال التمارين لليوم
              if (isFullyCompleted)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: _green,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.check_circle, color: Colors.white, size: 15),
                      const SizedBox(width: 4),
                      Text(
                        s.allWorkoutsCompleted,
                        style: const TextStyle(
                          color: Colors.white,
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
                    color: Colors.amber.shade700,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    s.partialWorkoutsCompleted(loggedCount, totalSessions),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    s.noWorkoutsCompletedYet,
                    style: TextStyle(
                      color: Colors.grey.shade700,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                ),

              const SizedBox(width: 6),
              Icon(
                Icons.chevron_left_rounded,
                color: isFullyCompleted ? _green : Colors.grey.shade400,
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
            Icon(Icons.person_off_outlined, size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text(
              s.noActivePlayers,
              style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }
}
