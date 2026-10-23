import 'package:flutter/material.dart';
import 'app_strings.dart';
import 'auth_service.dart';
import 'db.dart';
import 'home_service.dart';

const Color _navy = Color(0xFF0D3B66);
const Color _sky = Color(0xFFE8F4FC);
const Color _yellow = Color(0xFFFFC93C);
const Color _cardBg = Color(0xFFF7FAFC);

/// التاب الأول: الشاشة الرئيسية (Home Tab)
class DashboardTab extends StatefulWidget {
  final AppUser? user;

  const DashboardTab({
    super.key,
    this.user,
  });

  @override
  State<DashboardTab> createState() => _DashboardTabState();
}

class _DashboardTabState extends State<DashboardTab> {
  bool _loading = true;

  // الحصة القادمة
  Map<String, Object?>? _nextSession;
  String _nextSessionDate = '';

  // رسالة المدرب غير المقروءة
  CoachMessageItem? _unreadMessage;

  // بطاقات المؤشرات (Highlights)
  List<HighlightItem> _highlights = [];

  // مواعيد الاختبارات
  List<TestingDateItem> _testingDates = [];

  @override
  void initState() {
    super.initState();
    _loadHomeData();
  }

  @override
  void didUpdateWidget(covariant DashboardTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.user?.id != widget.user?.id) {
      _loadHomeData();
    }
  }

  Future<void> _loadHomeData() async {
    setState(() => _loading = true);

    try {
      final user = widget.user ?? AuthService.currentUser;
      final now = DateTime.now();
      final nowStr = dstr(now);

      // 1. الحصة القادمة
      final todaySessions = await DB.sessions(nowStr);
      if (todaySessions.isNotEmpty) {
        _nextSession = todaySessions.first;
        _nextSessionDate = nowStr;
      } else {
        final futureSessions = await DB.q(
          'SELECT * FROM sessions WHERE date >= ? ORDER BY date ASC, idx ASC LIMIT 1',
          [nowStr],
        );
        if (futureSessions.isNotEmpty) {
          _nextSession = futureSessions.first;
          _nextSessionDate = _nextSession!['date'] as String? ?? nowStr;
        } else {
          _nextSession = null;
        }
      }

      // 2. رسالة المدرب (للاعب)
      if (user != null && user.isAthlete) {
        _unreadMessage = await HomeService.getUnreadCoachMessage(user.id);
      } else {
        _unreadMessage = null;
      }

      // 3. Highlights
      _highlights = await HomeService.getHighlights(playerId: user?.playerId);

      // 4. مواعيد الاختبارات القادمة
      if (user != null && user.isCoach) {
        _testingDates = await HomeService.getUpcomingTestingDates(coachUserId: user.id);
      } else if (user != null && user.isAthlete) {
        _testingDates = await HomeService.getUpcomingTestingDates(athleteUserId: user.id);
      } else {
        _testingDates = await HomeService.getUpcomingTestingDates();
      }
    } catch (_) {}

    if (mounted) setState(() => _loading = false);
  }

  String _getTimeGreeting(AppStrings s) {
    final period = AuthService.getGreetingPeriod();
    if (period == 'morning') return s.goodMorning;
    if (period == 'afternoon') return s.goodAfternoon;
    return s.goodEvening;
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final user = widget.user ?? AuthService.currentUser;

    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: _navy),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadHomeData,
      color: _navy,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        children: [
          // ── ترويسة الترحيب ──
          _buildGreetingHeader(s, user),
          const SizedBox(height: 16),

          // ── رسالة المدرب إن وجدت (فقط للاعبين) ──
          if (_unreadMessage != null) ...[
            _buildCoachMessageCard(s, _unreadMessage!),
            const SizedBox(height: 16),
          ],

          // ── كارت الحصة التدريبية القادمة ──
          _buildNextSessionCard(s),
          const SizedBox(height: 16),

          // ── كروت المؤشرات Highlights (تظهر فقط إن توفرت بيانات) ──
          if (_highlights.isNotEmpty) ...[
            _buildHighlightsSection(s),
            const SizedBox(height: 16),
          ],

          // ── مواعيد الاختبارات القادمة ──
          _buildTestingDatesCard(s, user),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ── الترويسة والتحية ──
  Widget _buildGreetingHeader(AppStrings s, AppUser? user) {
    final greeting = _getTimeGreeting(s);
    final userName = user?.name ?? (s.isArabic ? 'بطل' : 'Athlete');
    final roleName = user?.isCoach == true
        ? (s.isArabic ? 'المدرب' : 'Coach')
        : (s.isArabic ? 'لاعب' : 'Athlete');

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [_navy, Color(0xFF1B4D7E)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: _navy.withAlpha(35),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 26,
            backgroundColor: _yellow,
            child: const Icon(
              Icons.person_rounded,
              size: 32,
              color: _navy,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        s.greetingWithName(userName, greeting),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: _yellow.withAlpha(40),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        roleName,
                        style: const TextStyle(
                          color: _yellow,
                          fontWeight: FontWeight.w700,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  s.isArabic
                      ? 'جاهز لجلسة تدريب مميزة اليوم على الأرجو؟'
                      : 'Ready for an elite rowing session today?',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: Colors.white.withAlpha(200),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── كارت رسالة المدرب ──
  Widget _buildCoachMessageCard(AppStrings s, CoachMessageItem msg) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFFF9E6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _yellow.withAlpha(160), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: _yellow.withAlpha(20),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: const BoxDecoration(
                  color: _yellow,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.mark_email_unread_rounded,
                  color: _navy,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${s.coachMessageTitle} (${msg.coachName})',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: _navy,
                  ),
                ),
              ),
              Text(
                msg.date,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            msg.message,
            style: const TextStyle(
              fontSize: 14,
              color: Color(0xFF2C3E50),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton.icon(
              onPressed: () async {
                await HomeService.markMessageRead(msg.id);
                setState(() => _unreadMessage = null);
              },
              icon: const Icon(Icons.check_circle_outline_rounded, size: 18, color: _navy),
              label: Text(
                s.markAsRead,
                style: const TextStyle(
                  color: _navy,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── كارت الحصة التدريبية القادمة ──
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
              const Icon(Icons.event_available_rounded, color: _navy, size: 22),
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
                          '${s.isArabic ? "التاريخ" : "Date"}: $_nextSessionDate',
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

  // ── قسم بطاقات Highlights ──
  Widget _buildHighlightsSection(AppStrings s) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.insights_rounded, color: _navy, size: 22),
            const SizedBox(width: 8),
            Text(
              s.highlightsTitle,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: _navy,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth > 550;
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: isWide ? 2 : 1,
                mainAxisExtent: 88,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              itemCount: _highlights.length,
              itemBuilder: (context, index) {
                final item = _highlights[index];
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.grey.shade200),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withAlpha(6),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Color(item.colorHex).withAlpha(25),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          item.icon,
                          color: Color(item.colorHex),
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              s.isArabic ? item.titleAr : item.titleEn,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey.shade600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              item.value,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: _navy,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ],
    );
  }

  // ── كارت مواعيد الاختبارات Testing Dates ──
  Widget _buildTestingDatesCard(AppStrings s, AppUser? user) {
    final isCoach = user?.isCoach == true;

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
              const Icon(Icons.timer_outlined, color: _navy, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  s.testingDatesTitle,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: _navy,
                  ),
                ),
              ),
              if (isCoach)
                IconButton(
                  tooltip: s.addTestingDate,
                  icon: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: _navy,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.add, color: Colors.white, size: 18),
                  ),
                  onPressed: () => _showAddTestDialog(context, s, user!),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (_testingDates.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                s.noUpcomingTests,
                style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
              ),
            )
          else ...[
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _testingDates.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, idx) {
                final test = _testingDates[idx];
                return Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: _sky,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Column(
                          children: [
                            const Icon(Icons.calendar_today_rounded, size: 16, color: _navy),
                            const SizedBox(height: 4),
                            Text(
                              test.testDate.length >= 10 ? test.testDate.substring(5) : test.testDate,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: _navy,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              test.testName,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: _navy,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${s.testDate}: ${test.testDate}',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (isCoach)
                        IconButton(
                          icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 20),
                          tooltip: s.deleteTestDate,
                          onPressed: () async {
                            await HomeService.deleteTestingDate(test.id);
                            _loadHomeData();
                          },
                        ),
                    ],
                  ),
                );
              },
            ),
          ]
        ],
      ),
    );
  }

  // ── نافذة إضافة موعد اختبار للمدرب ──
  void _showAddTestDialog(BuildContext context, AppStrings s, AppUser coach) async {
    final athletes = await HomeService.getCoachAthletes(coach.id);
    final nameCtrl = TextEditingController();
    DateTime selectedDate = DateTime.now().add(const Duration(days: 1));
    bool allSelected = true;
    final selectedAthleteIds = <int>{};

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (context, setDlgState) {
            final dateStr =
                '${selectedDate.year}-${selectedDate.month.toString().padLeft(2, '0')}-${selectedDate.day.toString().padLeft(2, '0')}';

            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Row(
                children: [
                  const Icon(Icons.event_note_rounded, color: _navy),
                  const SizedBox(width: 10),
                  Text(s.addTestingDate, style: const TextStyle(fontWeight: FontWeight.bold, color: _navy)),
                ],
              ),
              content: SingleChildScrollView(
                child: SizedBox(
                  width: 400,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // اسم الاختبار
                      Text(s.testName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                      const SizedBox(height: 6),
                      TextField(
                        controller: nameCtrl,
                        decoration: InputDecoration(
                          hintText: s.testNameHint,
                          prefixIcon: const Icon(Icons.speed_rounded, size: 20),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // تاريخ الاختبار
                      Text(s.testDate, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                      const SizedBox(height: 6),
                      InkWell(
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: selectedDate,
                            firstDate: DateTime.now(),
                            lastDate: DateTime.now().add(const Duration(days: 365)),
                          );
                          if (picked != null) {
                            setDlgState(() => selectedDate = picked);
                          }
                        },
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey.shade400),
                            borderRadius: BorderRadius.circular(10),
                            color: Colors.white,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(dateStr, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                              const Icon(Icons.calendar_month_rounded, size: 20, color: _navy),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // المستهدفون
                      Text(s.recipients, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          ChoiceChip(
                            label: Text(s.allAthletes),
                            selected: allSelected,
                            onSelected: (val) {
                              setDlgState(() {
                                allSelected = true;
                                selectedAthleteIds.clear();
                              });
                            },
                          ),
                          const SizedBox(width: 8),
                          ChoiceChip(
                            label: Text(s.selectAthletes),
                            selected: !allSelected,
                            onSelected: (val) {
                              setDlgState(() => allSelected = false);
                            },
                          ),
                        ],
                      ),
                      if (!allSelected && athletes.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Container(
                          constraints: const BoxConstraints(maxHeight: 140),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey.shade200),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: ListView(
                            shrinkWrap: true,
                            children: athletes.map((a) {
                              final id = a['id'] as int;
                              final name = a['name'] as String;
                              final checked = selectedAthleteIds.contains(id);
                              return CheckboxListTile(
                                dense: true,
                                title: Text(name, style: const TextStyle(fontSize: 13)),
                                value: checked,
                                onChanged: (val) {
                                  setDlgState(() {
                                    if (val == true) {
                                      selectedAthleteIds.add(id);
                                    } else {
                                      selectedAthleteIds.remove(id);
                                    }
                                  });
                                },
                              );
                            }).toList(),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogCtx),
                  child: Text(s.cancel),
                ),
                FilledButton(
                  onPressed: () async {
                    final name = nameCtrl.text.trim();
                    if (name.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(s.testNameRequired)),
                      );
                      return;
                    }

                    List<int> recipientIds;
                    if (allSelected) {
                      recipientIds = athletes.map((e) => e['id'] as int).toList();
                    } else {
                      recipientIds = selectedAthleteIds.toList();
                    }

                    await HomeService.addTestingDate(
                      coachUserId: coach.id,
                      testName: name,
                      testDate: dateStr,
                      athleteUserIds: recipientIds,
                    );

                    if (mounted) {
                      Navigator.pop(dialogCtx);
                      _loadHomeData();
                    }
                  },
                  child: Text(s.add),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
