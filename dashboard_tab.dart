import 'package:flutter/material.dart';
import 'db.dart';
import 'app_strings.dart';

const Color _navy = Color(0xFF0D3B66);
const Color _sky = Color(0xFFE8F4FC);
const Color _gold = Color(0xFFFFC93C);
const Color _accentBlue = Color(0xFF1E88E5);
const Color _cardBg = Color(0xFFF7FAFC);

/// التاب الأول: Ironman Dashboard
class DashboardTab extends StatefulWidget {
  const DashboardTab({super.key});

  @override
  State<DashboardTab> createState() => _DashboardTabState();
}

class _DashboardTabState extends State<DashboardTab> {
  bool _loading = true;

  // 1. نسبة الجاهزية
  double _teamReadiness = 0;
  int _readyCount = 0;
  int _fatiguedCount = 0;
  int _totalActivePlayers = 0;

  // 2. السيكل الحالي
  Map<String, Object?>? _currentCycle;
  int _cycleDaysTotal = 0;
  int _cycleDaysElapsed = 0;
  int _cycleDaysLeft = 0;

  // 3. الحصة القادمة
  Map<String, Object?>? _nextSession;
  String _nextSessionDate = '';

  // 4. مؤشر وتنبيه اتجاه EF للفريق
  double _currentAvgEF = 0;
  double _baselineAvgEF = 0;
  double _efDeltaPercentage = 0;
  String _efStatus = 'none'; // 'improving', 'stable', 'declining', 'none'

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
  }

  Future<void> _loadDashboardData() async {
    setState(() => _loading = true);

    try {
      // 1. حساب جاهزية الفريق
      final readinessList = await DB.allPlayersReadiness();
      _totalActivePlayers = readinessList.length;
      if (readinessList.isNotEmpty) {
        double totalScore = 0;
        int ready = 0;
        int tired = 0;

        for (final p in readinessList) {
          final score = (p['readiness'] as num?)?.toDouble() ?? 70;
          totalScore += score;
          if (score >= 60) {
            ready++;
          } else {
            tired++;
          }
        }
        _teamReadiness = totalScore / readinessList.length;
        _readyCount = ready;
        _fatiguedCount = tired;
      }

      // 2. جلب السيكل الحالي
      final now = DateTime.now();
      final nowStr = dstr(now);
      final cycles = await DB.q('SELECT * FROM cycles ORDER BY start DESC');
      if (cycles.isNotEmpty) {
        // البحث عن سيكل نشط يغطي اليوم
        Map<String, Object?>? active;
        for (final c in cycles) {
          final start = c['start'] as String? ?? '';
          final end = c['end'] as String? ?? '';
          if (start.compareTo(nowStr) <= 0 && end.compareTo(nowStr) >= 0) {
            active = c;
            break;
          }
        }
        active ??= cycles.first;
        _currentCycle = active;

        final startDt = DateTime.tryParse(active['start'] as String? ?? '') ?? now;
        final endDt = DateTime.tryParse(active['end'] as String? ?? '') ?? now.add(const Duration(days: 28));
        _cycleDaysTotal = endDt.difference(startDt).inDays;
        if (_cycleDaysTotal <= 0) _cycleDaysTotal = 1;
        _cycleDaysElapsed = now.difference(startDt).inDays.clamp(0, _cycleDaysTotal);
        _cycleDaysLeft = (_cycleDaysTotal - _cycleDaysElapsed).clamp(0, _cycleDaysTotal);
      }

      // 3. جلب الحصة القادمة
      final todaySessions = await DB.sessions(nowStr);
      if (todaySessions.isNotEmpty) {
        _nextSession = todaySessions.first;
        _nextSessionDate = nowStr;
      } else {
        // البحث عن أقرب حصة قادمة
        final futureSessions = await DB.q(
          'SELECT * FROM sessions WHERE date >= ? ORDER BY date ASC, idx ASC LIMIT 1',
          [nowStr],
        );
        if (futureSessions.isNotEmpty) {
          _nextSession = futureSessions.first;
          _nextSessionDate = _nextSession!['date'] as String? ?? nowStr;
        }
      }

      // 4. تحليل اتجاه EF للفريق (أهم مؤشر في المشروع)
      final recentLogs = await DB.q('''
        SELECT AVG(ef) as avg_ef, COUNT(ef) as count
        FROM logs
        WHERE ef IS NOT NULL AND ef > 0 AND date >= ?
      ''', [dstr(now.subtract(const Duration(days: 7)))]);

      final baselineLogs = await DB.q('''
        SELECT AVG(ef) as avg_ef, COUNT(ef) as count
        FROM logs
        WHERE ef IS NOT NULL AND ef > 0 AND date >= ? AND date < ?
      ''', [
        dstr(now.subtract(const Duration(days: 30))),
        dstr(now.subtract(const Duration(days: 7))),
      ]);

      final recentEF = (recentLogs.isNotEmpty ? (recentLogs.first['avg_ef'] as num?)?.toDouble() : null) ?? 0;
      final baselineEF = (baselineLogs.isNotEmpty ? (baselineLogs.first['avg_ef'] as num?)?.toDouble() : null) ?? 0;

      _currentAvgEF = recentEF;
      _baselineAvgEF = baselineEF;

      if (recentEF > 0 && baselineEF > 0) {
        _efDeltaPercentage = ((recentEF - baselineEF) / baselineEF) * 100;
        if (_efDeltaPercentage >= 2.0) {
          _efStatus = 'improving';
        } else if (_efDeltaPercentage <= -2.0) {
          _efStatus = 'declining';
        } else {
          _efStatus = 'stable';
        }
      } else if (recentEF > 0) {
        _efStatus = 'stable';
        _efDeltaPercentage = 0;
      } else {
        _efStatus = 'none';
      }
    } catch (_) {}

    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);

    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: _navy),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadDashboardData,
      color: _navy,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          // رأس الصفحة
          _buildHeader(s),
          const SizedBox(height: 16),

          // 1. بطاقة الجاهزية الكلية للفريق
          _buildReadinessCard(s),
          const SizedBox(height: 16),

          // 2. بطاقة تنبيه واتجاه EF للفريق (المؤشر الأهم)
          _buildEFTrendCard(s),
          const SizedBox(height: 16),

          // 3. بطاقة السيكل الحالي
          _buildCurrentCycleCard(s),
          const SizedBox(height: 16),

          // 4. بطاقة الحصة التدريبية القادمة
          _buildNextSessionCard(s),
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
          child: const Icon(Icons.bolt, color: _gold, size: 28),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                s.tabDashboard,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: _navy,
                ),
              ),
              Text(
                s.teamReadinessDesc,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey.shade700,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: _loadDashboardData,
          icon: const Icon(Icons.refresh, color: _navy),
          tooltip: 'تحديث',
        )
      ],
    );
  }

  // 1. كارت نسبة الجاهزية
  Widget _buildReadinessCard(AppStrings s) {
    final score = _teamReadiness.clamp(0.0, 100.0).toDouble();
    final color = Color(readinessColor(score));
    final statusText = readinessText(score);

    return Container(
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(10),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.health_and_safety, color: _navy, size: 24),
                  const SizedBox(width: 8),
                  Text(
                    s.teamReadiness,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: _navy,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withAlpha(30),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: color, width: 1.5),
                ),
                child: Text(
                  statusText,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              // دائرة النسبة
              Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 86,
                    height: 86,
                    child: CircularProgressIndicator(
                      value: score / 100,
                      strokeWidth: 9,
                      backgroundColor: Colors.grey.shade200,
                      valueColor: AlwaysStoppedAnimation<Color>(color),
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${score.round()}%',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: color,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(width: 20),
              // إحصائيات اللاعبين
              Expanded(
                child: Column(
                  children: [
                    _buildStatPill(
                      icon: Icons.check_circle,
                      color: Colors.green,
                      label: '${s.readyPlayers}: $_readyCount',
                      total: 'من أصل $_totalActivePlayers',
                    ),
                    const SizedBox(height: 8),
                    _buildStatPill(
                      icon: Icons.warning_amber_rounded,
                      color: Colors.orange,
                      label: '${s.tiredPlayers}: $_fatiguedCount',
                      total: 'يحتاجون استشفاء',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatPill({
    required IconData icon,
    required Color color,
    required String label,
    required String total,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
          ),
          Text(
            total,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  // 2. كارت ملخص وتنبيه اتجاه EF للفريق
  Widget _buildEFTrendCard(AppStrings s) {
    Color trendColor = _navy;
    IconData trendIcon = Icons.trending_flat;
    String trendMsg = s.efStable;

    if (_efStatus == 'improving') {
      trendColor = Colors.green.shade700;
      trendIcon = Icons.trending_up;
      trendMsg = s.efImproving;
    } else if (_efStatus == 'declining') {
      trendColor = Colors.red.shade700;
      trendIcon = Icons.trending_down;
      trendMsg = s.efDeclining;
    } else if (_efStatus == 'none') {
      trendColor = Colors.grey.shade600;
      trendIcon = Icons.info_outline;
      trendMsg = s.efNoData;
    }

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            _navy,
            _navy.withAlpha(220),
          ],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: _navy.withAlpha(40),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: _gold,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.speed, color: _navy, size: 20),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    s.efTrendTitle,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(30),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'EF = W / HR',
                  style: TextStyle(
                    color: _gold,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            s.efMetricDesc,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: trendColor.withAlpha(25),
                  radius: 22,
                  child: Icon(trendIcon, color: trendColor, size: 26),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            _currentAvgEF > 0 ? _currentAvgEF.toStringAsFixed(2) : '--',
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                              color: _navy,
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (_efDeltaPercentage != 0)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: trendColor.withAlpha(25),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '${_efDeltaPercentage > 0 ? '+' : ''}${_efDeltaPercentage.toStringAsFixed(1)}%',
                                style: TextStyle(
                                  color: trendColor,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        trendMsg,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: trendColor,
                        ),
                      ),
                      if (_baselineAvgEF > 0) ...[
                        const SizedBox(height: 4),
                        Text(
                          '${s.baselineEF}: ${_baselineAvgEF.toStringAsFixed(2)}',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 3. كارت السيكل الحالي
  Widget _buildCurrentCycleCard(AppStrings s) {
    final cycle = _currentCycle;
    final progress = _cycleDaysTotal > 0
        ? (_cycleDaysElapsed / _cycleDaysTotal).clamp(0.0, 1.0)
        : 0.0;

    return Container(
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade200),
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.cached_rounded, color: _navy, size: 22),
              const SizedBox(width: 8),
              Text(
                s.currentCycle,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: _navy,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (cycle == null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                s.noActiveCycle,
                style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
              ),
            )
          else ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  cycle['name'] as String? ?? 'Cycle',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: _navy,
                  ),
                ),
                Text(
                  '$_cycleDaysLeft ${s.daysRemaining}',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: _accentBlue,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '${cycle['start']}  ➔  ${cycle['end']}',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 10,
                backgroundColor: _sky,
                valueColor: const AlwaysStoppedAnimation<Color>(_navy),
              ),
            ),
          ]
        ],
      ),
    );
  }

  // 4. كارت الحصة التدريبية القادمة
  Widget _buildNextSessionCard(AppStrings s) {
    final session = _nextSession;

    return Container(
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade200),
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.event_available, color: _navy, size: 22),
              const SizedBox(width: 8),
              Text(
                s.nextSession,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: _navy,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (session == null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                s.noUpcomingSessions,
                style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
              ),
            )
          else ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: _navy,
                    radius: 20,
                    child: Text(
                      '${(session['idx'] as int? ?? 0) + 1}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${session['kind']} (${session['zone']})',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: _navy,
                          ),
                        ),
                        Text(
                          'التاريخ: $_nextSessionDate',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: _sky,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${session['zone']}',
                      style: const TextStyle(
                        color: _navy,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  )
                ],
              ),
            ),
          ]
        ],
      ),
    );
  }
}
