import 'package:flutter/material.dart';
import 'db.dart';
import 'app_strings.dart';
import 'player_entry_page.dart';

const Color _navy = Color(0xFF0D3B66);
const Color _sky = Color(0xFFE8F4FC);
const Color _gold = Color(0xFFFFC93C);

/// التاب الثاني: التمارين (Workout & Sessions Tab)
class WorkoutsTab extends StatefulWidget {
  const WorkoutsTab({super.key});

  @override
  State<WorkoutsTab> createState() => _WorkoutsTabState();
}

class _WorkoutsTabState extends State<WorkoutsTab> {
  DateTime _selectedDate = DateTime.now();
  List<Map<String, Object?>> _sessions = [];
  int _selectedSessionIdx = 0;
  List<Map<String, Object?>> _players = [];
  Set<int> _loggedPlayerIds = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    final dateStr = dstr(_selectedDate);

    // 1. جلب حصص اليوم
    _sessions = await DB.sessions(dateStr);
    if (_sessions.isEmpty) {
      // إذا لم تكن هناك حصص، ننشئ حصة افتراضية لليوم لتسهيل التجربة
      await DB.put('sessions', {
        'date': dateStr,
        'idx': 0,
        'kind': 'Erg',
        'zone': 'Z2',
      });
      _sessions = await DB.sessions(dateStr);
    }

    if (_selectedSessionIdx >= _sessions.length) {
      _selectedSessionIdx = 0;
    }

    // 2. جلب اللاعبين النشطين
    _players = await DB.q('SELECT * FROM players WHERE active=1 ORDER BY name');

    // 3. جلب معرفات اللاعبين المسجلين لهذه الحصة
    if (_sessions.isNotEmpty) {
      final currentSession = _sessions[_selectedSessionIdx];
      final currentIdx = currentSession['idx'] as int? ?? 0;
      final logs = await DB.q(
        'SELECT player_id FROM logs WHERE date=? AND idx=?',
        [dateStr, currentIdx],
      );
      _loggedPlayerIds = logs.map((e) => e['player_id'] as int).toSet();
    } else {
      _loggedPlayerIds = {};
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
      setState(() {
        _selectedDate = picked;
        _selectedSessionIdx = 0;
      });
      _loadAll();
    }
  }

  Future<void> _addSession() async {
    final dateStr = dstr(_selectedDate);
    final newIdx = _sessions.length;
    await DB.put('sessions', {
      'date': dateStr,
      'idx': newIdx,
      'kind': 'Erg',
      'zone': 'Z2',
    });
    setState(() => _selectedSessionIdx = newIdx);
    _loadAll();
  }

  Future<void> _updateSession(int idx, String kind, String zone) async {
    final dateStr = dstr(_selectedDate);
    await DB.put('sessions', {
      'date': dateStr,
      'idx': idx,
      'kind': kind,
      'zone': zone,
    });
    _loadAll();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final dateStr = dstr(_selectedDate);

    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: _navy));
    }

    final currentSession = _sessions.isNotEmpty ? _sessions[_selectedSessionIdx] : null;

    return RefreshIndicator(
      onRefresh: _loadAll,
      color: _navy,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          // شريط اختيار التاريخ والحصة
          _buildDateAndSessionHeader(s, dateStr),
          const SizedBox(height: 14),

          // بطاقة إعدادات وتفاصيل الحصة الحالية
          if (currentSession != null)
            _buildCurrentSessionCard(s, currentSession)
          else
            _buildNoSessionCard(s),
          const SizedBox(height: 20),

          // عنوان قائمة اللاعبين وإحصائية التسجيل
          _buildPlayersSectionHeader(s),
          const SizedBox(height: 10),

          // قائمة اللاعبين
          if (_players.isEmpty)
            _buildNoPlayersCard(s)
          else
            ..._players.map((p) => _buildPlayerItem(s, p, currentSession)),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildDateAndSessionHeader(AppStrings s, String dateStr) {
    return Row(
      children: [
        // زر التاريخ
        Expanded(
          child: InkWell(
            onTap: _pickDate,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: _navy,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: _navy.withAlpha(40),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  const Icon(Icons.calendar_month, color: _gold, size: 22),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.todaySession,
                        style: const TextStyle(color: Colors.white70, fontSize: 11),
                      ),
                      Text(
                        dateStr,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  const Icon(Icons.arrow_drop_down, color: Colors.white70),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        // زر إضافة حصة إضافية لليوم
        if (_sessions.length < 4)
          IconButton.filled(
            onPressed: _addSession,
            icon: const Icon(Icons.add, color: _navy),
            style: IconButton.styleFrom(
              backgroundColor: _gold,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            tooltip: s.addNewSession,
          ),
      ],
    );
  }

  Widget _buildCurrentSessionCard(AppStrings s, Map<String, Object?> session) {
    final idx = session['idx'] as int? ?? 0;
    final kind = session['kind'] as String? ?? 'Erg';
    final zone = session['zone'] as String? ?? 'Z2';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade300),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(8),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          // شريط التبديل بين الحصص إذا وجدت أكثر من حصة
          if (_sessions.length > 1) ...[
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: List.generate(_sessions.length, (i) {
                  final isSelected = i == _selectedSessionIdx;
                  return Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: ChoiceChip(
                      label: Text('${s.sessionNumber} ${i + 1}'),
                      selected: isSelected,
                      selectedColor: _navy,
                      labelStyle: TextStyle(
                        color: isSelected ? Colors.white : _navy,
                        fontWeight: FontWeight.bold,
                      ),
                      onSelected: (val) {
                        if (val) {
                          setState(() => _selectedSessionIdx = i);
                          _loadAll();
                        }
                      },
                    ),
                  );
                }),
              ),
            ),
            const Divider(height: 20),
          ],
          Row(
            children: [
              CircleAvatar(
                backgroundColor: _navy,
                radius: 20,
                child: Text(
                  '${idx + 1}',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: kind,
                  decoration: InputDecoration(
                    labelText: s.workoutType,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  items: kinds.map((k) => DropdownMenuItem(value: k, child: Text(k))).toList(),
                  onChanged: (v) {
                    if (v != null) _updateSession(idx, v, zone);
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: zone,
                  decoration: InputDecoration(
                    labelText: s.targetZone,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  items: zones.keys.map((z) => DropdownMenuItem(value: z, child: Text(z))).toList(),
                  onChanged: (v) {
                    if (v != null) _updateSession(idx, kind, v);
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNoSessionCard(AppStrings s) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _sky,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(s.noUpcomingSessions, style: const TextStyle(fontWeight: FontWeight.bold)),
          FilledButton.icon(
            onPressed: _addSession,
            icon: const Icon(Icons.add),
            label: Text(s.addNewSession),
          ),
        ],
      ),
    );
  }

  Widget _buildPlayersSectionHeader(AppStrings s) {
    final recorded = _loggedPlayerIds.length;
    final total = _players.length;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              s.playersList,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: _navy,
              ),
            ),
            Text(
              s.tapPlayerToLog,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ],
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: recorded == total && total > 0 ? Colors.green.shade50 : _sky,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: recorded == total && total > 0 ? Colors.green : _navy.withAlpha(60),
            ),
          ),
          child: Text(
            '$recorded / $total ${s.statusRecorded}',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 12,
              color: recorded == total && total > 0 ? Colors.green.shade800 : _navy,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNoPlayersCard(AppStrings s) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          s.noActivePlayers,
          style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
        ),
      ),
    );
  }

  // بطاقة اللاعب مع تغيير اللون الواضح عند تسجيل البيانات
  Widget _buildPlayerItem(
    AppStrings s,
    Map<String, Object?> player,
    Map<String, Object?>? session,
  ) {
    final id = player['id'] as int;
    final isLogged = _loggedPlayerIds.contains(id);
    final name = player['name'] as String? ?? 'لاعب';

    // الألوان الديناميكية بناءً على حالة التسجيل
    final cardBg = isLogged ? const Color(0xFFE8F8F0) : Colors.white;
    final borderColor = isLogged ? Colors.green.shade400 : Colors.grey.shade200;
    final nameColor = isLogged ? Colors.green.shade900 : _navy;
    final avatarBg = isLogged ? Colors.green.shade700 : _navy;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Material(
        color: cardBg,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: session == null
              ? null
              : () async {
                  final result = await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => Directionality(
                        textDirection: AppLanguage.instance.isArabic
                            ? TextDirection.rtl
                            : TextDirection.ltr,
                        child: PlayerEntryPage(
                          date: dstr(_selectedDate),
                          session: session,
                          player: player,
                        ),
                      ),
                    ),
                  );
                  if (result == true || mounted) {
                    _loadAll(); // تحديث فوري لحالة التسجيل وتغيير اللون
                  }
                },
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: borderColor, width: isLogged ? 1.5 : 1.0),
              boxShadow: isLogged
                  ? [
                      BoxShadow(
                        color: Colors.green.withAlpha(20),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : null,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                // الصورة الرمزية مع تلوين مميز
                CircleAvatar(
                  backgroundColor: avatarBg,
                  radius: 22,
                  child: isLogged
                      ? const Icon(Icons.check, color: Colors.white, size: 22)
                      : Text(
                          name.isNotEmpty ? name[0] : 'P',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
                const SizedBox(width: 14),
                // اسم اللاعب ومعلومات النبض
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: nameColor,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Text(
                            'MHR: ${player['mhr']}',
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                          ),
                          const SizedBox(width: 8),
                          if (isLogged)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(
                                color: Colors.green.shade100,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                s.statusRecorded,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green.shade800,
                                ),
                              ),
                            )
                          else
                            Text(
                              '• ${s.statusPending}',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.red.shade400,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                // أيقونة التعديل / الدخول
                Icon(
                  isLogged ? Icons.edit_note : Icons.chevron_left,
                  color: isLogged ? Colors.green.shade700 : _navy,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
