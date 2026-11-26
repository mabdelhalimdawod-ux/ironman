import 'package:flutter/material.dart';
import 'app_strings.dart';
import 'auth_service.dart';
import 'coach_request_service.dart';
import 'engine_rowing_ui.dart';
import 'home_service.dart';
import 'metrics_curve_page.dart';
import 'progress_tab.dart';
import 'today_workout_page.dart';
import 'user_avatar_widget.dart';

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

  // رسالة المدرب غير المقروءة
  CoachMessageItem? _unreadMessage;

  // بطاقات المؤشرات (Highlights)
  List<HighlightItem> _highlights = [];

  // مواعيد الاختبارات
  List<TestingDateItem> _testingDates = [];

  // طلبات انضمام المدرب (المرحلة س3)
  Map<String, dynamic>? _pendingCoachRequest;
  List<Map<String, dynamic>> _coachPendingRequests = [];

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

      // 1. رسالة المدرب والطلبات (للاعب)
      if (user != null && user.isAthlete) {
        _unreadMessage = await HomeService.getUnreadCoachMessage(user.id);
        _pendingCoachRequest =
            await CoachRequestService.getPendingRequestForAthlete(user.id);
      } else {
        _unreadMessage = null;
        _pendingCoachRequest = null;
      }

      // 2. طلبات اللاعبين الواردة (للمدرب)
      if (user != null && user.isCoach) {
        _coachPendingRequests =
            await CoachRequestService.getPendingRequestsForCoach(user.id);
      } else {
        _coachPendingRequests = [];
      }

      // 3. Highlights
      _highlights = await HomeService.getHighlights(playerId: user?.playerId);

      // 4. مواعيد الاختبارات القادمة
      if (user != null && user.isCoach) {
        _testingDates =
            await HomeService.getUpcomingTestingDates(coachUserId: user.id);
      } else if (user != null && user.isAthlete) {
        _testingDates =
            await HomeService.getUpcomingTestingDates(athleteUserId: user.id);
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
        child: CircularProgressIndicator(color: EngineRowingUI.neonLime),
      );
    }

    return RowingGridBackground(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 850),
          child: RefreshIndicator(
            onRefresh: _loadHomeData,
            color: EngineRowingUI.neonLime,
            backgroundColor: EngineRowingUI.cardFill,
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

                // ── كارت اختيار المدرب أو الطلب المعلق (فقط للاعبين) ──
                if (user != null && user.isAthlete) ...[
                  _buildAthleteCoachCard(s, user),
                  const SizedBox(height: 16),
                ],

                // ── كارت طلبات اللاعبين الواردة (فقط للمدربين) ──
                if (user != null &&
                    user.isCoach &&
                    _coachPendingRequests.isNotEmpty) ...[
                  _buildCoachRequestsCard(s, user),
                  const SizedBox(height: 16),
                ],

                // ── أيقونتا تمرين اليوم والأرشيف ──
                _buildQuickActionCards(s, user),
                const SizedBox(height: 16),

                // ── كارت منحنيات مؤشرات التدريب (خمسة منحنيات) ──
                _buildMetricsCurvesBanner(s),
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
          ),
        ),
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
        color: EngineRowingUI.cardFill,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: EngineRowingUI.bgGridLine, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          UserAvatarWidget(
            photoPath: user?.photoPath,
            radius: 28,
            isEditable: true,
            targetUserId: user?.id,
            currentUserId: user?.id,
            onPhotoChanged: (newPath) {
              setState(() {});
            },
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      s.greetingWithName(userName, greeting),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: EngineRowingUI.textWhite,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: EngineRowingUI.neonLime.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: EngineRowingUI.neonLime.withValues(alpha: 0.4),
                        ),
                      ),
                      child: Text(
                        roleName,
                        style: const TextStyle(
                          color: EngineRowingUI.neonLime,
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
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: EngineRowingUI.labelSlate,
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
        color: EngineRowingUI.cardFill,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: EngineRowingUI.neonLime.withValues(alpha: 0.5),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
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
                  color: EngineRowingUI.neonLime,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.mark_email_unread_rounded,
                  color: EngineRowingUI.bgNavy,
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
                    color: EngineRowingUI.textWhite,
                  ),
                ),
              ),
              Directionality(
                textDirection: TextDirection.ltr,
                child: Text(
                  RowingNumberFormatter.toEnglishDigits(msg.date),
                  style: const TextStyle(
                      fontSize: 12, color: EngineRowingUI.labelSlate),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            msg.message,
            style: const TextStyle(
              fontSize: 14,
              color: EngineRowingUI.textWhite,
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
              icon: const Icon(
                Icons.check_circle_outline_rounded,
                size: 18,
                color: EngineRowingUI.neonLime,
              ),
              label: Text(
                s.markAsRead,
                style: const TextStyle(
                  color: EngineRowingUI.neonLime,
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

  // ── كارت اختيار المدرب أو الطلب المعلق للاعب ──
  Widget _buildAthleteCoachCard(AppStrings s, AppUser user) {
    if (_pendingCoachRequest != null) {
      return Container(
        decoration: BoxDecoration(
          color: EngineRowingUI.cardFill,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.amber.withAlpha(120), width: 1.2),
        ),
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.amber.withAlpha(40),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.hourglass_top_rounded,
                      color: Colors.amber, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.pendingCoachRequest,
                        style: const TextStyle(
                          color: EngineRowingUI.textWhite,
                          fontWeight: FontWeight.bold,
                          fontSize: 13.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        s.isArabic
                            ? 'طلبك قيد المراجعة لدى المدرب، يمكنك إلغاؤه إن أردت'
                            : 'Your request is pending review by the coach',
                        style: const TextStyle(
                            color: EngineRowingUI.captionGrey, fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton.icon(
                icon: const Icon(Icons.close_rounded, size: 16),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.redAccent,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                ),
                onPressed: () async {
                  final reqId =
                      (_pendingCoachRequest!['id'] as num?)?.toInt() ?? 0;
                  if (reqId > 0) {
                    await CoachRequestService.cancelRequest(reqId);
                    await _loadHomeData();
                  }
                },
                label:
                    Text(s.cancelRequest, style: const TextStyle(fontSize: 12)),
              ),
            ),
          ],
        ),
      );
    }

    if (user.coachId == null) {
      return Container(
        decoration: BoxDecoration(
          color: EngineRowingUI.cardFill,
          borderRadius: BorderRadius.circular(16),
          border:
              Border.all(color: EngineRowingUI.gold.withAlpha(140), width: 1.2),
        ),
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: EngineRowingUI.gold.withAlpha(40),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.person_search_rounded,
                      color: EngineRowingUI.gold, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.chooseCoach,
                        style: const TextStyle(
                          color: EngineRowingUI.textWhite,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        s.chooseCoachSubtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: EngineRowingUI.captionGrey, fontSize: 11.5),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.person_add_alt_1_rounded, size: 16),
                style: ElevatedButton.styleFrom(
                  backgroundColor: EngineRowingUI.gold,
                  foregroundColor: EngineRowingUI.bgNavy,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () => _openCoachSelectionDialog(s, user),
                label: Text(s.chooseCoach,
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      );
    }

    // اللاعب لديه مدرب بالفعل: كارت معلومات مختصر
    return Container(
      decoration: BoxDecoration(
        color: EngineRowingUI.equationCardFill,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: EngineRowingUI.bgGridLine),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        children: [
          const Icon(Icons.sports_rounded,
              color: EngineRowingUI.gold, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${s.currentCoach}: كوتش الفريق',
              style: const TextStyle(
                  color: EngineRowingUI.textWhite, fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          TextButton(
            onPressed: () => _openCoachSelectionDialog(s, user),
            child: Text(s.changeCoach,
                style:
                    const TextStyle(color: EngineRowingUI.gold, fontSize: 11)),
          ),
        ],
      ),
    );
  }

  Future<void> _openCoachSelectionDialog(AppStrings s, AppUser user) async {
    showDialog(
      context: context,
      builder: (ctx) {
        return FutureBuilder<List<Map<String, dynamic>>>(
          future: CoachRequestService.getActiveCoaches(),
          builder: (context, snapshot) {
            return AlertDialog(
              backgroundColor: EngineRowingUI.cardFill,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: EngineRowingUI.bgGridLine),
              ),
              title: Text(
                s.chooseCoach,
                style: const TextStyle(
                    color: EngineRowingUI.textWhite, fontSize: 16),
              ),
              content: SizedBox(
                width: double.maxFinite,
                child: snapshot.connectionState == ConnectionState.waiting
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(20),
                          child: CircularProgressIndicator(
                              color: EngineRowingUI.gold),
                        ),
                      )
                    : (snapshot.data == null || snapshot.data!.isEmpty)
                        ? Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(
                              s.isArabic
                                  ? 'لا يوجد مدربين مفعّلين متاحين حالياً'
                                  : 'No active coaches available at the moment',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  color: EngineRowingUI.captionGrey,
                                  fontSize: 13),
                            ),
                          )
                        : ListView.separated(
                            shrinkWrap: true,
                            itemCount: snapshot.data!.length,
                            separatorBuilder: (_, __) => const Divider(
                                color: EngineRowingUI.bgGridLine, height: 1),
                            itemBuilder: (context, idx) {
                              final coach = snapshot.data![idx];
                              final coachId = coach['id']?.toString() ?? '';
                              final coachName =
                                  coach['name']?.toString() ?? 'مدرب';

                              return ListTile(
                                leading: CircleAvatar(
                                  backgroundColor:
                                      EngineRowingUI.gold.withAlpha(40),
                                  child: const Icon(Icons.sports,
                                      color: EngineRowingUI.gold, size: 20),
                                ),
                                title: Text(
                                  coachName,
                                  style: const TextStyle(
                                      color: EngineRowingUI.textWhite,
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.bold),
                                ),
                                subtitle: Text(
                                  coach['email']?.toString() ?? '',
                                  style: const TextStyle(
                                      color: EngineRowingUI.captionGrey,
                                      fontSize: 11),
                                ),
                                trailing: ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: EngineRowingUI.gold,
                                    foregroundColor: EngineRowingUI.bgNavy,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 4),
                                    visualDensity: VisualDensity.compact,
                                  ),
                                  onPressed: () async {
                                    Navigator.pop(ctx);
                                    try {
                                      await CoachRequestService
                                          .sendCoachRequest(
                                        athleteId: user.id,
                                        coachId: coachId,
                                      );
                                      await _loadHomeData();
                                      if (mounted) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              s.isArabic
                                                  ? 'تم إرسال طلب الانضمام للمدرب بنجاح'
                                                  : 'Coach request sent successfully',
                                            ),
                                            backgroundColor: Colors.green,
                                          ),
                                        );
                                      }
                                    } catch (e) {
                                      if (mounted) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          SnackBar(
                                            content: Text('$e'),
                                            backgroundColor: Colors.redAccent,
                                          ),
                                        );
                                      }
                                    }
                                  },
                                  child: Text(s.sendRequest,
                                      style: const TextStyle(fontSize: 11)),
                                ),
                              );
                            },
                          ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(s.cancel,
                      style:
                          const TextStyle(color: EngineRowingUI.captionGrey)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ── كارت طلبات اللاعبين الواردة للمدرب ──
  Widget _buildCoachRequestsCard(AppStrings s, AppUser user) {
    return Container(
      decoration: BoxDecoration(
        color: EngineRowingUI.cardFill,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: EngineRowingUI.neonLime.withAlpha(120), width: 1.2),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: EngineRowingUI.neonLime.withAlpha(40),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.group_add_rounded,
                    color: EngineRowingUI.neonLime, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${s.coachRequestsTitle} (${_coachPendingRequests.length})',
                      style: const TextStyle(
                        color: EngineRowingUI.textWhite,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      s.isArabic
                          ? 'لديك طلبات انضمام جديدة من لاعبين بانتظار موافقتك'
                          : 'You have new athlete join requests waiting for review',
                      style: const TextStyle(
                          color: EngineRowingUI.captionGrey, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.checklist_rounded, size: 16),
              style: ElevatedButton.styleFrom(
                backgroundColor: EngineRowingUI.neonLime,
                foregroundColor: EngineRowingUI.bgNavy,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () => _openCoachRequestsDialog(s, user),
              label: Text(
                s.isArabic ? 'مراجعة الطلبات' : 'Review Requests',
                style:
                    const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openCoachRequestsDialog(AppStrings s, AppUser user) async {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: EngineRowingUI.cardFill,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: EngineRowingUI.bgGridLine),
        ),
        title: Text(
          s.coachRequestsTitle,
          style: const TextStyle(color: EngineRowingUI.textWhite, fontSize: 16),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: _coachPendingRequests.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    s.isArabic
                        ? 'لا توجد طلبات معلّقة حالياً'
                        : 'No pending requests',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: EngineRowingUI.captionGrey, fontSize: 13),
                  ),
                )
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: _coachPendingRequests.length,
                  separatorBuilder: (_, __) => const Divider(
                      color: EngineRowingUI.bgGridLine, height: 1),
                  itemBuilder: (context, idx) {
                    final req = _coachPendingRequests[idx];
                    final reqId = (req['id'] as num?)?.toInt() ?? 0;
                    final athleteId = req['athlete_id'];

                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        backgroundColor: Colors.lightBlueAccent.withAlpha(40),
                        child: const Icon(Icons.person,
                            color: Colors.lightBlueAccent, size: 20),
                      ),
                      title: Text(
                        'لاعب #$athleteId',
                        style: const TextStyle(
                            color: EngineRowingUI.textWhite,
                            fontSize: 13,
                            fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(
                        'تاريخ الطلب: ${(req['created_at']?.toString() ?? "").substring(0, 10)}',
                        style: const TextStyle(
                            color: EngineRowingUI.captionGrey, fontSize: 10.5),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.check_circle_rounded,
                                color: Colors.greenAccent, size: 22),
                            tooltip: s.accept,
                            onPressed: () async {
                              Navigator.pop(ctx);
                              try {
                                await CoachRequestService.respondToRequest(
                                  requestId: reqId,
                                  accept: true,
                                  coach: user,
                                );
                                await _loadHomeData();
                              } catch (e) {
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                        content: Text('$e'),
                                        backgroundColor: Colors.redAccent),
                                  );
                                }
                              }
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.cancel_rounded,
                                color: Colors.redAccent, size: 22),
                            tooltip: s.reject,
                            onPressed: () async {
                              Navigator.pop(ctx);
                              try {
                                await CoachRequestService.respondToRequest(
                                  requestId: reqId,
                                  accept: false,
                                  coach: user,
                                );
                                await _loadHomeData();
                              } catch (e) {
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                        content: Text('$e'),
                                        backgroundColor: Colors.redAccent),
                                  );
                                }
                              }
                            },
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(s.cancel,
                style: const TextStyle(color: EngineRowingUI.captionGrey)),
          ),
        ],
      ),
    );
  }

  // ── صف الأيقونات الثلاث: تمرين اليوم، الأرشيف، والمنحنيات ──
  Widget _buildQuickActionCards(AppStrings s, AppUser? user) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 420;

        Widget buildActionTile({
          required IconData icon,
          required Color color,
          required String title,
          required VoidCallback onTap,
        }) {
          return Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: onTap,
              child: Container(
                padding: EdgeInsets.symmetric(
                  horizontal: isNarrow ? 6 : 10,
                  vertical: isNarrow ? 10 : 12,
                ),
                decoration: BoxDecoration(
                  color: EngineRowingUI.cardFill,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: color.withValues(alpha: 0.5),
                    width: 1.1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.18),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: isNarrow
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(7),
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(icon, color: color, size: 20),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: EngineRowingUI.textWhite,
                              fontSize: 11.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(7),
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(icon, color: color, size: 20),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: EngineRowingUI.textWhite,
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          );
        }

        return Row(
          children: [
            buildActionTile(
              icon: Icons.fitness_center_rounded,
              color: EngineRowingUI.neonLime,
              title: s.todayWorkout,
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => TodayWorkoutPage(user: user),
                  ),
                );
              },
            ),
            const SizedBox(width: 8),
            buildActionTile(
              icon: Icons.archive_outlined,
              color: const Color(0xFF00E5FF),
              title: s.archive,
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Row(
                      children: [
                        const Icon(Icons.archive_outlined,
                            color: Color(0xFF00E5FF)),
                        const SizedBox(width: 8),
                        Text(s.archiveComingSoon),
                      ],
                    ),
                    backgroundColor: EngineRowingUI.cardFill,
                  ),
                );
              },
            ),
            const SizedBox(width: 8),
            buildActionTile(
              icon: Icons.auto_graph_rounded,
              color: const Color(0xFFFF9100),
              title: s.progressCurves,
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => Scaffold(
                      appBar: AppBar(
                        title: Text(s.progressCurves),
                        backgroundColor: EngineRowingUI.bgNavy,
                        elevation: 0,
                      ),
                      body: ProgressTab(user: user),
                    ),
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }

  // ── قسم بطاقات Highlights ──
  Widget _buildHighlightsSection(AppStrings s) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.insights_rounded,
              color: EngineRowingUI.neonLime,
              size: 22,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                s.highlightsTitle,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: EngineRowingUI.textWhite,
                ),
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: EngineRowingUI.cardFill,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: EngineRowingUI.bgGridLine),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.15),
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
                          color: EngineRowingUI.equationCardFill,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: EngineRowingUI.bgGridLine),
                        ),
                        child: Icon(
                          item.icon,
                          color: EngineRowingUI.neonLime,
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
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: EngineRowingUI.labelSlate,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Directionality(
                              textDirection: TextDirection.ltr,
                              child: Text(
                                RowingNumberFormatter.toEnglishDigits(
                                    item.value),
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: EngineRowingUI.textWhite,
                                  fontFeatures: [FontFeature.tabularFigures()],
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
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
        color: EngineRowingUI.cardFill,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: EngineRowingUI.bgGridLine),
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.timer_outlined,
                color: EngineRowingUI.neonLime,
                size: 22,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  s.testingDatesTitle,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: EngineRowingUI.textWhite,
                  ),
                ),
              ),
              if (isCoach)
                IconButton(
                  tooltip: s.addTestingDate,
                  icon: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: EngineRowingUI.neonLime,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.add,
                      color: EngineRowingUI.bgNavy,
                      size: 18,
                    ),
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
                style: const TextStyle(
                    color: EngineRowingUI.labelSlate, fontSize: 14),
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
                final formattedDate =
                    RowingNumberFormatter.toEnglishDigits(test.testDate);
                return Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: EngineRowingUI.equationCardFill,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: EngineRowingUI.bgGridLine),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: EngineRowingUI.cardFill,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: EngineRowingUI.bgGridLine),
                        ),
                        child: Column(
                          children: [
                            const Icon(
                              Icons.calendar_today_rounded,
                              size: 16,
                              color: EngineRowingUI.neonLime,
                            ),
                            const SizedBox(height: 4),
                            Directionality(
                              textDirection: TextDirection.ltr,
                              child: Text(
                                formattedDate.length >= 10
                                    ? formattedDate.substring(5)
                                    : formattedDate,
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: EngineRowingUI.neonLime,
                                  fontFeatures: [FontFeature.tabularFigures()],
                                ),
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
                                color: EngineRowingUI.textWhite,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Directionality(
                              textDirection: TextDirection.ltr,
                              child: Text(
                                '${s.testDate}: $formattedDate',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: EngineRowingUI.labelSlate,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (isCoach)
                        IconButton(
                          icon: const Icon(
                            Icons.delete_outline_rounded,
                            color: Colors.redAccent,
                            size: 20,
                          ),
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
  void _showAddTestDialog(
      BuildContext context, AppStrings s, AppUser coach) async {
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
              backgroundColor: EngineRowingUI.cardFill,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: const BorderSide(
                    color: EngineRowingUI.bgGridLine, width: 1.5),
              ),
              title: Row(
                children: [
                  const Icon(Icons.event_note_rounded,
                      color: EngineRowingUI.neonLime),
                  const SizedBox(width: 10),
                  Text(
                    s.addTestingDate,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: EngineRowingUI.textWhite,
                    ),
                  ),
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
                      Text(
                        s.testName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          color: EngineRowingUI.labelSlate,
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: nameCtrl,
                        style: const TextStyle(color: EngineRowingUI.textWhite),
                        decoration: InputDecoration(
                          hintText: s.testNameHint,
                          hintStyle: const TextStyle(
                              color: EngineRowingUI.captionGrey),
                          filled: true,
                          fillColor: EngineRowingUI.equationCardFill,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(
                                color: EngineRowingUI.bgGridLine),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(
                                color: EngineRowingUI.bgGridLine),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(
                                color: EngineRowingUI.neonLime, width: 1.5),
                          ),
                          prefixIcon: const Icon(
                            Icons.speed_rounded,
                            size: 20,
                            color: EngineRowingUI.neonLime,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // تاريخ الاختبار
                      Text(
                        s.testDate,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          color: EngineRowingUI.labelSlate,
                        ),
                      ),
                      const SizedBox(height: 6),
                      InkWell(
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: selectedDate,
                            firstDate: DateTime.now(),
                            lastDate:
                                DateTime.now().add(const Duration(days: 365)),
                            builder: (context, child) {
                              return Theme(
                                data: ThemeData.dark().copyWith(
                                  colorScheme: const ColorScheme.dark(
                                    primary: EngineRowingUI.neonLime,
                                    onPrimary: EngineRowingUI.bgNavy,
                                    surface: EngineRowingUI.cardFill,
                                    onSurface: EngineRowingUI.textWhite,
                                  ),
                                  dialogTheme: const DialogThemeData(
                                      backgroundColor: EngineRowingUI.cardFill),
                                ),
                                child: child!,
                              );
                            },
                          );
                          if (picked != null) {
                            setDlgState(() => selectedDate = picked);
                          }
                        },
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            border:
                                Border.all(color: EngineRowingUI.bgGridLine),
                            borderRadius: BorderRadius.circular(10),
                            color: EngineRowingUI.equationCardFill,
                          ),
                          child: Directionality(
                            textDirection: TextDirection.ltr,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  RowingNumberFormatter.toEnglishDigits(
                                      dateStr),
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: EngineRowingUI.textWhite,
                                    fontFeatures: [
                                      FontFeature.tabularFigures()
                                    ],
                                  ),
                                ),
                                const Icon(
                                  Icons.calendar_month_rounded,
                                  size: 20,
                                  color: EngineRowingUI.neonLime,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // المستهدفون
                      Text(
                        s.recipients,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          color: EngineRowingUI.labelSlate,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          ChoiceChip(
                            label: Text(s.allAthletes),
                            selected: allSelected,
                            selectedColor: EngineRowingUI.neonLime,
                            backgroundColor: EngineRowingUI.equationCardFill,
                            labelStyle: TextStyle(
                              color: allSelected
                                  ? EngineRowingUI.bgNavy
                                  : EngineRowingUI.textWhite,
                              fontWeight: FontWeight.bold,
                            ),
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
                            selectedColor: EngineRowingUI.neonLime,
                            backgroundColor: EngineRowingUI.equationCardFill,
                            labelStyle: TextStyle(
                              color: !allSelected
                                  ? EngineRowingUI.bgNavy
                                  : EngineRowingUI.textWhite,
                              fontWeight: FontWeight.bold,
                            ),
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
                            border:
                                Border.all(color: EngineRowingUI.bgGridLine),
                            borderRadius: BorderRadius.circular(10),
                            color: EngineRowingUI.equationCardFill,
                          ),
                          child: ListView(
                            shrinkWrap: true,
                            children: athletes.map((a) {
                              final id = a['id'] as int;
                              final name = a['name'] as String;
                              final checked = selectedAthleteIds.contains(id);
                              return CheckboxListTile(
                                dense: true,
                                activeColor: EngineRowingUI.neonLime,
                                checkColor: EngineRowingUI.bgNavy,
                                title: Text(
                                  name,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: EngineRowingUI.textWhite,
                                  ),
                                ),
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
                  child: Text(
                    s.cancel,
                    style: const TextStyle(color: EngineRowingUI.labelSlate),
                  ),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: EngineRowingUI.neonLime,
                    foregroundColor: EngineRowingUI.bgNavy,
                  ),
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
                      recipientIds =
                          athletes.map((e) => e['id'] as int).toList();
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
                  child: Text(
                    s.add,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ── كارت منحنيات مؤشرات التدريب المتطورة (متجاوب بالكامل بدون overflow) ──
  Widget _buildMetricsCurvesBanner(AppStrings s) {
    return Container(
      decoration: BoxDecoration(
        color: EngineRowingUI.cardFill,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: EngineRowingUI.neonLime.withValues(alpha: 0.5),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 16,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: EngineRowingUI.equationCardFill,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: EngineRowingUI.neonLime.withValues(alpha: 0.6),
                  ),
                ),
                child: const Icon(
                  Icons.auto_graph_rounded,
                  color: EngineRowingUI.neonLime,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      s.metricsCurvesTitle,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: EngineRowingUI.textWhite,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: EngineRowingUI.neonLime,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        s.isArabic ? '5 منحنيات' : '5 Curves',
                        style: const TextStyle(
                          color: EngineRowingUI.bgNavy,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            s.isArabic
                ? 'تحليل ذكي لـ EF، الواط، Decoupling، النبض، ومنحنى مناطق التدريب (كارفونين)'
                : 'Smart curves for EF, Watts, Decoupling, HR & Zone Curve',
            style: const TextStyle(
              fontSize: 12,
              color: EngineRowingUI.labelSlate,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: EngineRowingUI.neonLime,
              foregroundColor: EngineRowingUI.bgNavy,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            icon: const Icon(Icons.analytics_outlined, size: 18),
            label: Text(
              s.isArabic ? 'فتح التحليل والمنحنيات' : 'Open Analytics & Curves',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: EngineRowingUI.bgNavy,
              ),
            ),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const MetricsCurvePage()),
              );
            },
          ),
        ],
      ),
    );
  }
}
