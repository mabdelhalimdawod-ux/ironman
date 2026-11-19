import 'package:flutter/material.dart';
import 'app_strings.dart';
import 'auth_service.dart';
import 'cloud_api.dart';
import 'engine_rowing_ui.dart';

/// شاشة لوحة تحكم الأدمن (Admin Dashboard)
/// مخصصة لدور admin فقط لإدارة المستخدمين وحسابات الاشتراكات
/// لا تعرض أي بيانات صحية أو تمارين على الإطلاق
class AdminPage extends StatefulWidget {
  final VoidCallback onLogout;
  final AppUser? currentUser;

  const AdminPage({
    super.key,
    required this.onLogout,
    this.currentUser,
  });

  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  bool _loading = true;
  String? _error;
  List<CloudUserProfile> _allProfiles = [];
  String _searchQuery = '';
  String _statusFilter = 'all'; // 'all', 'pending', 'active', 'inactive'
  String _roleFilter = 'all'; // 'all', 'coach', 'athlete'

  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadProfiles();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadProfiles() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final profiles = await CloudApi.instance.listAllProfiles();
      if (mounted) {
        setState(() {
          _allProfiles = profiles;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'تعذر تحميل المستخدمين من السحابة: $e';
          _loading = false;
        });
      }
    }
  }

  List<CloudUserProfile> get _filteredProfiles {
    return _allProfiles.where((p) {
      // 1. استبعاد الأدمن الآخرين أو النفس إن رغبنا، ولكن عرضهم مفيد
      // 2. فلتر البحث
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final matchesName = p.name.toLowerCase().contains(q);
        final matchesEmail = p.email.toLowerCase().contains(q);
        if (!matchesName && !matchesEmail) return false;
      }

      // 3. فلتر الدور
      if (_roleFilter != 'all' && p.role != _roleFilter) {
        return false;
      }

      // 4. فلتر حالة الاشتراك
      if (_statusFilter == 'active' && !p.subscriptionActive) return false;
      if (_statusFilter == 'inactive' && p.subscriptionActive) return false;
      if (_statusFilter == 'pending' && (p.subscriptionActive || p.role == 'admin')) {
        return false; // بانتظار التفعيل: غير مفعّل وليس أدمن
      }

      return true;
    }).toList();
  }

  Future<void> _toggleSubscription(CloudUserProfile profile) async {
    final s = AppStrings.of(context);
    final targetActive = !profile.subscriptionActive;
    final noteController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: EngineRowingUI.cardFill,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: EngineRowingUI.bgGridLine),
        ),
        title: Text(
          targetActive
              ? (s.isArabic ? 'تأكيد تفعيل الاشتراك' : 'Confirm Subscription Activation')
              : (s.isArabic ? 'تأكيد إيقاف الاشتراك' : 'Confirm Subscription Deactivation'),
          style: const TextStyle(color: EngineRowingUI.textWhite, fontSize: 16),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              targetActive
                  ? (s.isArabic
                      ? 'هل تم استلام قيمة الاشتراك نقداً وتريد تفعيل حساب (${profile.name})؟'
                      : 'Confirm activating subscription for (${profile.name})?')
                  : (s.isArabic
                      ? 'هل أنت متأكد من رغبتك في إيقاف اشتراك (${profile.name})؟'
                      : 'Confirm deactivating subscription for (${profile.name})?'),
              style: const TextStyle(color: EngineRowingUI.captionGrey, fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: noteController,
              style: const TextStyle(color: EngineRowingUI.textWhite, fontSize: 13),
              decoration: InputDecoration(
                labelText: s.isArabic ? 'ملاحظة (اختياري)' : 'Note (Optional)',
                labelStyle: const TextStyle(color: EngineRowingUI.labelSlate, fontSize: 12),
                hintText: s.isArabic ? 'مثال: تم السداد كاش 500 جنيه' : 'e.g. Cash payment received',
                hintStyle: const TextStyle(color: EngineRowingUI.captionGrey, fontSize: 11),
                filled: true,
                fillColor: EngineRowingUI.equationCardFill,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: EngineRowingUI.bgGridLine),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(s.isArabic ? 'إلغاء' : 'Cancel',
                style: const TextStyle(color: EngineRowingUI.captionGrey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: targetActive ? EngineRowingUI.neonLime : Colors.redAccent,
              foregroundColor: targetActive ? EngineRowingUI.bgNavy : Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(s.isArabic ? 'تأكيد' : 'Confirm'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final adminId = widget.currentUser?.id.toString() ?? 'admin';
        await CloudApi.instance.updateSubscription(
          userId: profile.id,
          active: targetActive,
          note: noteController.text.trim(),
          adminId: adminId,
        );
        await _loadProfiles();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                targetActive
                    ? (s.isArabic ? 'تم تفعيل الحساب بنجاح' : 'Account activated successfully')
                    : (s.isArabic ? 'تم إيقاف الحساب' : 'Account deactivated'),
              ),
              backgroundColor: targetActive ? Colors.green : Colors.orange,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('حدث خطأ أثناء تعديل الاشتراك: $e'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      }
    }
    noteController.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);

    return Scaffold(
      backgroundColor: EngineRowingUI.bgNavy,
      appBar: AppBar(
        backgroundColor: EngineRowingUI.bgNavy,
        foregroundColor: EngineRowingUI.textWhite,
        elevation: 0,
        title: Text(
          s.isArabic ? 'لوحة الإدارة السحابية' : 'Admin Cloud Dashboard',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
        ),
        actions: [
          IconButton(
            tooltip: s.isArabic ? 'تحديث' : 'Refresh',
            icon: const Icon(Icons.refresh_rounded, color: EngineRowingUI.gold),
            onPressed: _loadProfiles,
          ),
          IconButton(
            tooltip: s.logout,
            icon: const Icon(Icons.logout_rounded, color: Colors.redAccent),
            onPressed: widget.onLogout,
          ),
        ],
      ),
      body: RowingGridBackground(
        child: SafeArea(
          child: Column(
            children: [
              // ── شريط البحث والفلترة ──
              _buildSearchAndFilters(s),

              // ── محتوى القائمة ──
              Expanded(
                child: _loading
                    ? const Center(
                        child: CircularProgressIndicator(color: EngineRowingUI.gold),
                      )
                    : _error != null
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.cloud_off_rounded,
                                      size: 48, color: Colors.orangeAccent),
                                  const SizedBox(height: 12),
                                  Text(
                                    _error!,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                        color: EngineRowingUI.textWhite, fontSize: 13),
                                  ),
                                  const SizedBox(height: 16),
                                  ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                        backgroundColor: EngineRowingUI.gold,
                                        foregroundColor: EngineRowingUI.bgNavy),
                                    icon: const Icon(Icons.refresh),
                                    label: Text(s.isArabic ? 'إعادة المحاولة' : 'Retry'),
                                    onPressed: _loadProfiles,
                                  ),
                                ],
                              ),
                            ),
                          )
                        : _buildUserList(s),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchAndFilters(AppStrings s) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: const BoxDecoration(
        color: EngineRowingUI.cardFill,
        border: Border(bottom: BorderSide(color: EngineRowingUI.bgGridLine)),
      ),
      child: Column(
        children: [
          // حقل البحث
          TextField(
            controller: _searchController,
            style: const TextStyle(color: EngineRowingUI.textWhite, fontSize: 13),
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              hintText: s.isArabic ? 'بحث بالاسم أو البريد...' : 'Search by name or email...',
              hintStyle: const TextStyle(color: EngineRowingUI.captionGrey, fontSize: 12),
              prefixIcon: const Icon(Icons.search, color: EngineRowingUI.gold, size: 20),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, color: EngineRowingUI.captionGrey, size: 18),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _searchQuery = '');
                      },
                    )
                  : null,
              filled: true,
              fillColor: EngineRowingUI.equationCardFill,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: EngineRowingUI.bgGridLine),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: EngineRowingUI.bgGridLine),
              ),
            ),
            onChanged: (val) => setState(() => _searchQuery = val.trim()),
          ),
          const SizedBox(height: 8),

          // صف شرائح الفلترة (Status & Role)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildFilterChip(
                  label: s.isArabic ? 'الكل' : 'All',
                  isSelected: _statusFilter == 'all',
                  onSelected: () => setState(() => _statusFilter = 'all'),
                ),
                const SizedBox(width: 6),
                _buildFilterChip(
                  label: s.isArabic ? 'بانتظار التفعيل' : 'Pending',
                  isSelected: _statusFilter == 'pending',
                  activeColor: Colors.amber,
                  onSelected: () => setState(() => _statusFilter = 'pending'),
                ),
                const SizedBox(width: 6),
                _buildFilterChip(
                  label: s.isArabic ? 'مفعّل' : 'Active',
                  isSelected: _statusFilter == 'active',
                  activeColor: EngineRowingUI.neonLime,
                  onSelected: () => setState(() => _statusFilter = 'active'),
                ),
                const SizedBox(width: 6),
                _buildFilterChip(
                  label: s.isArabic ? 'غير مفعّل' : 'Inactive',
                  isSelected: _statusFilter == 'inactive',
                  activeColor: Colors.redAccent,
                  onSelected: () => setState(() => _statusFilter = 'inactive'),
                ),
                const SizedBox(width: 12),
                Container(width: 1, height: 20, color: EngineRowingUI.bgGridLine),
                const SizedBox(width: 12),
                _buildFilterChip(
                  label: s.isArabic ? 'مدربين' : 'Coaches',
                  isSelected: _roleFilter == 'coach',
                  activeColor: EngineRowingUI.gold,
                  onSelected: () => setState(
                      () => _roleFilter = _roleFilter == 'coach' ? 'all' : 'coach'),
                ),
                const SizedBox(width: 6),
                _buildFilterChip(
                  label: s.isArabic ? 'لاعبين' : 'Athletes',
                  isSelected: _roleFilter == 'athlete',
                  activeColor: Colors.lightBlueAccent,
                  onSelected: () => setState(
                      () => _roleFilter = _roleFilter == 'athlete' ? 'all' : 'athlete'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip({
    required String label,
    required bool isSelected,
    Color activeColor = EngineRowingUI.gold,
    required VoidCallback onSelected,
  }) {
    return InkWell(
      onTap: onSelected,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? activeColor.withAlpha(40) : EngineRowingUI.equationCardFill,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? activeColor : EngineRowingUI.bgGridLine,
            width: isSelected ? 1.4 : 1.0,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected ? activeColor : EngineRowingUI.captionGrey,
          ),
        ),
      ),
    );
  }

  Widget _buildUserList(AppStrings s) {
    final list = _filteredProfiles;
    if (list.isEmpty) {
      return Center(
        child: Text(
          s.isArabic ? 'لا يوجد مستخدمين مطابقين للبحث' : 'No users match criteria',
          style: const TextStyle(color: EngineRowingUI.captionGrey, fontSize: 13),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      itemCount: list.length,
      itemBuilder: (context, index) {
        final profile = list[index];
        final isSelf = profile.id == widget.currentUser?.id.toString();

        final roleBadgeColor = profile.isAdmin
            ? Colors.purpleAccent
            : profile.isCoach
                ? EngineRowingUI.gold
                : Colors.lightBlueAccent;

        final roleLabel = profile.isAdmin
            ? (s.isArabic ? 'أدمن' : 'Admin')
            : profile.isCoach
                ? (s.isArabic ? 'مدرب' : 'Coach')
                : (s.isArabic ? 'لاعب' : 'Athlete');

        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: EngineRowingUI.cardFill,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: profile.subscriptionActive
                  ? EngineRowingUI.bgGridLine
                  : Colors.redAccent.withAlpha(90),
            ),
          ),
          child: Row(
            children: [
              // الأيقونة أو الصورة
              CircleAvatar(
                radius: 20,
                backgroundColor: roleBadgeColor.withAlpha(40),
                child: Text(
                  profile.name.isNotEmpty ? profile.name.substring(0, 1).toUpperCase() : '?',
                  style: TextStyle(
                    color: roleBadgeColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ),
              const SizedBox(width: 12),

              // بيانات المستخدم
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            profile.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: EngineRowingUI.textWhite,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: roleBadgeColor.withAlpha(30),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            roleLabel,
                            style: TextStyle(
                              color: roleBadgeColor,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        if (isSelf) ...[
                          const SizedBox(width: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: Colors.white12,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              s.isArabic ? 'أنت' : 'You',
                              style: const TextStyle(color: Colors.white70, fontSize: 9),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      profile.email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: EngineRowingUI.captionGrey, fontSize: 11.5),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      profile.subscriptionActive
                          ? (s.isArabic ? 'الحالة: اشتراك نشط' : 'Status: Active')
                          : (s.isArabic ? 'الحالة: بانتظار التفعيل' : 'Status: Inactive'),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: profile.subscriptionActive
                            ? EngineRowingUI.neonLime
                            : Colors.orangeAccent,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),

              // زر التفعيل / الإيقاف
              if (!profile.isAdmin)
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: profile.subscriptionActive
                        ? Colors.redAccent.withAlpha(40)
                        : EngineRowingUI.neonLime.withAlpha(40),
                    foregroundColor: profile.subscriptionActive
                        ? Colors.redAccent
                        : EngineRowingUI.neonLime,
                    side: BorderSide(
                      color: profile.subscriptionActive
                          ? Colors.redAccent
                          : EngineRowingUI.neonLime,
                    ),
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    visualDensity: VisualDensity.compact,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () => _toggleSubscription(profile),
                  child: Text(
                    profile.subscriptionActive
                        ? (s.isArabic ? 'إيقاف' : 'Deactivate')
                        : (s.isArabic ? 'تفعيل' : 'Activate'),
                    style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
