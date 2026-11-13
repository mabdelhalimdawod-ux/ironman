import 'dart:io';
import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'admin_placeholder.dart';
import 'app_strings.dart';
import 'auth_service.dart';
import 'dashboard_tab.dart';
import 'engine_rowing_ui.dart';
import 'login_page.dart';
import 'metrics_curve_page.dart';
import 'program_tab.dart';
import 'progress_tab.dart';
import 'workouts_tab.dart';

const Color navy = EngineRowingUI.bgNavy;
const Color sky = EngineRowingUI.cardFill;
const Color yellow = EngineRowingUI.neonLime;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isWindows || Platform.isLinux) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
  await AppLanguage.instance.init();
  await AuthService.seedInitialData();
  runApp(const IronmanApp());
}

class IronmanApp extends StatefulWidget {
  const IronmanApp({super.key});

  @override
  State<IronmanApp> createState() => _IronmanAppState();
}

class _IronmanAppState extends State<IronmanApp> {
  AppUser? _currentUser;
  bool _checkingSession = true;

  @override
  void initState() {
    super.initState();
    _checkSession();
  }

  Future<void> _checkSession() async {
    try {
      final user = await AuthService.checkSavedSession();
      if (mounted) {
        setState(() {
          _currentUser = user;
          _checkingSession = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _checkingSession = false;
        });
      }
    }
  }

  void _handleLoginSuccess(AppUser user) {
    setState(() {
      _currentUser = user;
    });
  }

  void _handleLogout() async {
    await AuthService.logout();
    setState(() {
      _currentUser = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        AppLanguage.instance,
        RowingResponsive.userScaleNotifier,
        RowingResponsive.intensityNotifier,
      ]),
      builder: (context, _) {
        final isArabic = AppLanguage.instance.isArabic;

        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'Engine Rowing',
          locale: AppLanguage.instance.locale,
          builder: (context, child) {
            return Directionality(
              textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
              child: child!,
            );
          },
          theme: EngineRowingUI.globalTheme,
          home: _checkingSession
              ? const Scaffold(
                  backgroundColor: EngineRowingUI.bgNavy,
                  body: Center(
                    child: CircularProgressIndicator(
                        color: EngineRowingUI.neonLime),
                  ),
                )
              : _currentUser == null
                  ? LoginPage(onLoginSuccess: _handleLoginSuccess)
                  : _currentUser!.isAdmin
                      ? AdminPlaceholderPage(onLogout: _handleLogout)
                      : MainNavigationScaffold(
                          user: _currentUser,
                          onLogout: _handleLogout,
                        ),
        );
      },
    );
  }
}

/// الهيكل الرئيسي للتطبيق مع شريط التنقل الجانبي (Side Navigation)
class MainNavigationScaffold extends StatefulWidget {
  final AppUser? user;
  final VoidCallback onLogout;

  const MainNavigationScaffold({
    super.key,
    this.user,
    required this.onLogout,
  });

  @override
  State<MainNavigationScaffold> createState() => _MainNavigationScaffoldState();
}

class _MainNavigationScaffoldState extends State<MainNavigationScaffold> {
  int _currentIndex = 0;
  double _navWidth = 0.0;
  bool _isResizing = false;

  // ── أحجام الشريط الجانبي ──
  static const double _minWidth = 0.0; // مخفي تماماً
  static const double _midWidth = 200.0; // أيقونات + نصوص
  static const double _maxWidth = 260.0; // موسّع بالكامل

  List<Widget> get _tabs => [
        DashboardTab(user: widget.user),
        const ProgramTab(),
        const WorkoutsTab(),
        ProgressTab(user: widget.user),
      ];

  void _toggleSideNav() {
    setState(() {
      if (_navWidth > 0) {
        _navWidth = 0.0;
      } else {
        _navWidth = 240.0;
      }
    });
  }

  /// يرجع لأقرب حجم مسبق بعد انتهاء السحب
  void _snapToNearest() {
    if (_navWidth < 100) {
      setState(() => _navWidth = 0.0);
      return;
    }
    const presets = [_midWidth, _maxWidth];
    double closest = presets.reduce(
        (a, b) => (a - _navWidth).abs() < (b - _navWidth).abs() ? a : b);
    setState(() {
      _navWidth = closest;
      _isResizing = false;
    });
  }

  /// التبديل بين الأحجام
  void _cycleSize() {
    setState(() {
      if (_navWidth <= 0) {
        _navWidth = _midWidth;
      } else if (_navWidth <= _midWidth + 20) {
        _navWidth = _maxWidth;
      } else {
        _navWidth = 0.0;
      }
    });
  }

  void _confirmLogout(BuildContext context, AppStrings s) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text(s.logout),
        content: Text(s.logoutConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: Text(s.cancel),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(dialogCtx);
              widget.onLogout();
            },
            child: Text(s.logout),
          ),
        ],
      ),
    );
  }

  /// فتح لوحة التحكم والعمليات من علامة الهمبرجر (☰)
  void _openHamburgerHub(BuildContext context, AppStrings s) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _HamburgerHubSheet(
        user: widget.user,
        onOpenMetricsCurves: () {
          Navigator.pop(ctx);
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => MetricsCurvePage(
                initialPlayer: widget.user != null
                    ? {'id': widget.user!.id, 'name': widget.user!.name}
                    : null,
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final isArabic = AppLanguage.instance.isArabic;

    final navItems = [
      _SideNavItemData(Icons.home_outlined, Icons.home, s.tabHome),
      _SideNavItemData(
        Icons.event_repeat_outlined,
        Icons.event_repeat,
        s.tabProgram,
        imageAsset: 'assets/images/program_tab_icon.png',
      ),
      _SideNavItemData(
          Icons.fitness_center_outlined, Icons.fitness_center, s.tabWorkouts),
      _SideNavItemData(
          Icons.auto_graph_outlined, Icons.auto_graph_rounded, s.tabProgress),
    ];

    // ════════════════════════════════════════
    // ██  المحتوى الرئيسي
    // ════════════════════════════════════════
    final mainContentColumn = Column(
      children: [
        // ── AppBar ──
        Container(
          height: 60,
          decoration: const BoxDecoration(
            color: EngineRowingUI.bgNavy,
            border: Border(
              bottom: BorderSide(color: EngineRowingUI.bgGridLine, width: 1.0),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              // زر الهمبورجر: يظهر الشريط الجانبي بالكامل أو يخفيه تماماً بضغطة واحدة
              IconButton(
                icon: const Icon(Icons.menu_rounded, color: yellow, size: 28),
                tooltip: s.hamburgerTitle,
                onPressed: _toggleSideNav,
              ),
              IconButton(
                icon: const Icon(Icons.tune_rounded, color: yellow, size: 22),
                tooltip: s.hamburgerTitle,
                onPressed: () => _openHamburgerHub(context, s),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  [
                    s.tabHome,
                    s.tabProgram,
                    s.tabWorkouts,
                    s.tabProgress,
                  ][_currentIndex],
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: EngineRowingUI.textWhite,
                    letterSpacing: 0.5,
                  ),
                  textAlign: isArabic ? TextAlign.right : TextAlign.left,
                ),
              ),
              // زرار داخل AppBar للتحكم في مقاسات الرؤية والسطوع والإضاءة
              IconButton(
                icon: const Icon(Icons.tune_rounded, color: yellow, size: 24),
                tooltip: s.displayControlTitle,
                onPressed: () => _openHamburgerHub(context, s),
              ),
            ],
          ),
        ),
        // ── Body مع دعم التكبير والتصغير التفاعلي بالأصابع ──
        Expanded(
          child: ValueListenableBuilder<double>(
            valueListenable: userScaleNotifier,
            builder: (context, scale, child) {
              return Transform.scale(
                scale: scale,
                alignment: Alignment.topCenter,
                child: IndexedStack(
                  index: _currentIndex,
                  children: _tabs,
                ),
              );
            },
          ),
        ),
      ],
    );

    // ════════════════════════════════════════
    // ██  مقبض السحب (Drag Handle)
    // ════════════════════════════════════════
    final dragHandle = _navWidth <= 0
        ? const SizedBox.shrink()
        : GestureDetector(
            onHorizontalDragStart: (_) => setState(() => _isResizing = true),
            onHorizontalDragUpdate: (details) {
              setState(() {
                final delta = isArabic ? -details.delta.dx : details.delta.dx;
                _navWidth = (_navWidth + delta).clamp(_minWidth, _maxWidth);
              });
            },
            onHorizontalDragEnd: (_) => _snapToNearest(),
            onDoubleTap: _cycleSize,
            child: MouseRegion(
              cursor: SystemMouseCursors.resizeColumn,
              child: Container(
                width: 8,
                color: Colors.transparent,
                child: Center(
                  child: Container(
                    width: 3,
                    height: 48,
                    decoration: BoxDecoration(
                      color: EngineRowingUI.bgGridLine,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ),
            ),
          );

    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 700;

    Widget buildSideNavContainer(double width) {
      return Container(
        width: width,
        decoration: BoxDecoration(
          color: const Color(0xFF071126),
          border: Border(
            right: isArabic
                ? BorderSide.none
                : const BorderSide(color: EngineRowingUI.bgGridLine, width: 1),
            left: isArabic
                ? const BorderSide(color: EngineRowingUI.bgGridLine, width: 1)
                : BorderSide.none,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(80),
              blurRadius: 24,
              offset: Offset(isArabic ? -4 : 4, 0),
            ),
          ],
        ),
        child: Column(
          children: [
            // ── منطقة الشعار وزر الإغلاق ──
            Container(
              height: 60,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              alignment: Alignment.center,
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.close_rounded,
                        color: yellow, size: 24),
                    tooltip: s.close,
                    onPressed: _toggleSideNav,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.rowing_rounded,
                            color: yellow, size: 24),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            'ENGINE ROWING',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: yellow,
                              fontSize: width > 240 ? 16 : 13,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // ── فاصل ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Divider(
                color: Colors.white.withAlpha(30),
                height: 1,
              ),
            ),
            const SizedBox(height: 16),

            // ── عناصر التنقل ──
            ...List.generate(navItems.length, (i) {
              final item = navItems[i];
              final isActive = _currentIndex == i;
              return _SideNavItem(
                icon: isActive ? item.activeIcon : item.icon,
                label: item.label,
                imageAsset: item.imageAsset,
                isActive: isActive,
                isCollapsed: false,
                navWidth: width,
                onTap: () {
                  setState(() {
                    _currentIndex = i;
                    _navWidth = 0.0;
                  });
                },
              );
            }),

            const Spacer(),

            // ── فاصل سفلي ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Divider(
                color: Colors.white.withAlpha(30),
                height: 1,
              ),
            ),
            const SizedBox(height: 6),

            // ── زرار لوحة العمليات والتحكم ──
            _SideNavItem(
              icon: Icons.tune_rounded,
              label: s.hamburgerTitle,
              isActive: false,
              isCollapsed: false,
              navWidth: width,
              onTap: () {
                _openHamburgerHub(context, s);
              },
            ),

            // ── زرار تسجيل الخروج ──
            _SideNavItem(
              icon: Icons.logout_rounded,
              label: s.logout,
              isActive: false,
              isCollapsed: false,
              navWidth: width,
              onTap: () => _confirmLogout(context, s),
            ),

            const SizedBox(height: 12),
          ],
        ),
      );
    }

    // ── على الموبايل: المحتوى يأخذ كامل الشاشة، والقائمة الجانبية تظهر كـ Overlay فوق الشاشة بدون ضغط المحتوى ──
    if (isMobile) {
      return Scaffold(
        backgroundColor: EngineRowingUI.bgNavy,
        bottomNavigationBar: Container(
          decoration: const BoxDecoration(
            color: Color(0xFF071126),
            border: Border(
              top: BorderSide(color: EngineRowingUI.bgGridLine, width: 1.0),
            ),
          ),
          child: BottomNavigationBar(
            currentIndex: _currentIndex,
            onTap: (index) {
              setState(() {
                _currentIndex = index;
                _navWidth = 0.0;
              });
            },
            backgroundColor: const Color(0xFF071126),
            selectedItemColor: yellow,
            unselectedItemColor: EngineRowingUI.captionGrey,
            type: BottomNavigationBarType.fixed,
            selectedFontSize: 11,
            unselectedFontSize: 10,
            items: [
              BottomNavigationBarItem(
                icon: const Icon(Icons.home_outlined),
                activeIcon: const Icon(Icons.home),
                label: s.tabHome,
              ),
              BottomNavigationBarItem(
                icon: const Icon(Icons.event_repeat_outlined),
                activeIcon: const Icon(Icons.event_repeat),
                label: s.tabProgram,
              ),
              BottomNavigationBarItem(
                icon: const Icon(Icons.fitness_center_outlined),
                activeIcon: const Icon(Icons.fitness_center),
                label: s.tabWorkouts,
              ),
              BottomNavigationBarItem(
                icon: const Icon(Icons.auto_graph_outlined),
                activeIcon: const Icon(Icons.auto_graph_rounded),
                label: s.tabProgress,
              ),
            ],
          ),
        ),
        body: Stack(
          children: [
            Positioned.fill(
              child: mainContentColumn,
            ),
            if (_navWidth > 0)
              Positioned.fill(
                child: GestureDetector(
                  onTap: _toggleSideNav,
                  child: Container(
                    color: Colors.black.withValues(alpha: 0.6),
                  ),
                ),
              ),
            AnimatedPositioned(
              duration: _isResizing
                  ? Duration.zero
                  : const Duration(milliseconds: 250),
              curve: Curves.easeOutCubic,
              top: 0,
              bottom: 0,
              right: isArabic ? (_navWidth > 0 ? 0 : -270) : null,
              left: isArabic ? null : (_navWidth > 0 ? 0 : -270),
              width: 250,
              child: Material(
                color: Colors.transparent,
                elevation: 16,
                child: ClipRect(
                  child: buildSideNavContainer(250),
                ),
              ),
            ),
          ],
        ),
      );
    }

    // ── على الشاشات الكبيرة (كمبيوتر أو تابلت): المحتوى جنباً إلى جنب ──
    final mainContent = Expanded(child: mainContentColumn);
    final sideNav = AnimatedContainer(
      duration: _isResizing ? Duration.zero : const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
      width: _navWidth,
      child: _navWidth <= 0
          ? const SizedBox.shrink()
          : ClipRect(
              child: buildSideNavContainer(_navWidth),
            ),
    );

    return Scaffold(
      backgroundColor: EngineRowingUI.bgNavy,
      body: Row(
        textDirection: TextDirection.ltr,
        children: isArabic
            ? [mainContent, if (_navWidth > 0) dragHandle, sideNav]
            : [sideNav, if (_navWidth > 0) dragHandle, mainContent],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════
// بيانات عنصر التنقل
// ════════════════════════════════════════════════════════════════
class _SideNavItemData {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final String? imageAsset;
  const _SideNavItemData(this.icon, this.activeIcon, this.label,
      {this.imageAsset});
}

// ════════════════════════════════════════════════════════════════
// ويدجت عنصر التنقل الجانبي
// ════════════════════════════════════════════════════════════════
class _SideNavItem extends StatefulWidget {
  final IconData icon;
  final String label;
  final String? imageAsset;
  final bool isActive;
  final bool isCollapsed;
  final double navWidth;
  final VoidCallback onTap;

  const _SideNavItem({
    required this.icon,
    required this.label,
    this.imageAsset,
    required this.isActive,
    required this.isCollapsed,
    required this.navWidth,
    required this.onTap,
  });

  @override
  State<_SideNavItem> createState() => _SideNavItemState();
}

class _SideNavItemState extends State<_SideNavItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final isActive = widget.isActive;
    final isCollapsed = widget.isCollapsed;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: Tooltip(
            message: isCollapsed ? widget.label : '',
            preferBelow: false,
            waitDuration: const Duration(milliseconds: 400),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              padding: EdgeInsets.symmetric(
                horizontal: isCollapsed ? 0 : 16,
                vertical: 14,
              ),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                color: isActive
                    ? yellow.withAlpha(35)
                    : _isHovered
                        ? Colors.white.withAlpha(18)
                        : Colors.transparent,
                border: Border.all(
                  color: isActive ? yellow.withAlpha(70) : Colors.transparent,
                  width: 1.2,
                ),
              ),
              child: Row(
                mainAxisAlignment: isCollapsed
                    ? MainAxisAlignment.center
                    : MainAxisAlignment.start,
                children: [
                  // ── المؤشر الجانبي ──
                  if (!isCollapsed)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      width: 3,
                      height: isActive ? 22 : 0,
                      margin: const EdgeInsetsDirectional.only(end: 10),
                      decoration: BoxDecoration(
                        color: yellow,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  // ── الأيقونة أو الشعار المخصص ──
                  AnimatedScale(
                    scale: _isHovered && !isActive ? 1.15 : 1.0,
                    duration: const Duration(milliseconds: 180),
                    child: widget.imageAsset != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: Image.asset(
                              widget.imageAsset!,
                              width: isCollapsed ? 26 : 24,
                              height: isCollapsed ? 26 : 24,
                              fit: BoxFit.contain,
                              errorBuilder: (_, __, ___) => Icon(
                                widget.icon,
                                color: isActive
                                    ? yellow
                                    : _isHovered
                                        ? Colors.white
                                        : Colors.white70,
                                size: isCollapsed ? 26 : 24,
                              ),
                            ),
                          )
                        : Icon(
                            widget.icon,
                            color: isActive
                                ? yellow
                                : _isHovered
                                    ? Colors.white
                                    : Colors.white70,
                            size: isCollapsed ? 26 : 24,
                          ),
                  ),
                  // ── النص ──
                  if (!isCollapsed) ...[
                    const SizedBox(width: 14),
                    Flexible(
                      child: AnimatedDefaultTextStyle(
                        duration: const Duration(milliseconds: 200),
                        style: TextStyle(
                          color: isActive
                              ? yellow
                              : _isHovered
                                  ? Colors.white
                                  : Colors.white70,
                          fontSize: widget.navWidth > 240 ? 16 : 14.5,
                          fontWeight:
                              isActive ? FontWeight.w700 : FontWeight.w400,
                          letterSpacing: 0.3,
                        ),
                        child: Text(
                          widget.label,
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                    ),
                  ],
                  // ── نقطة المؤشر للوضع المصغر ──
                  if (isCollapsed && isActive)
                    Container(
                      margin: const EdgeInsets.only(top: 4),
                      width: 5,
                      height: 5,
                      decoration: const BoxDecoration(
                        color: yellow,
                        shape: BoxShape.circle,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════
// نافذة لوحة التحكم والعمليات (قائمة الهمبرجر ☰)
// ════════════════════════════════════════════════════════════════
class _HamburgerHubSheet extends StatelessWidget {
  final AppUser? user;
  final VoidCallback onOpenMetricsCurves;

  const _HamburgerHubSheet({
    required this.user,
    required this.onOpenMetricsCurves,
  });

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: EngineRowingUI.bgNavy,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [
              BoxShadow(
                color: Colors.black54,
                blurRadius: 20,
                offset: Offset(0, -4),
              ),
            ],
          ),
          child: Column(
            children: [
              // ── مقبض السحب العلوي ──
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 10, bottom: 8),
                  width: 48,
                  height: 5,
                  decoration: BoxDecoration(
                    color: EngineRowingUI.bgGridLine,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),

              // ── شريط رأس قائمة الهمبرجر ──
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                decoration: const BoxDecoration(
                  color: EngineRowingUI.cardFill,
                  border: Border(
                    bottom: BorderSide(
                        color: EngineRowingUI.bgGridLine, width: 1.0),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: EngineRowingUI.neonLime.withAlpha(35),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.menu_rounded,
                          color: EngineRowingUI.neonLime, size: 26),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            s.hamburgerTitle,
                            style: const TextStyle(
                              color: EngineRowingUI.textWhite,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            s.hamburgerSubtitle,
                            style: const TextStyle(
                              color: EngineRowingUI.labelSlate,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded,
                          color: EngineRowingUI.textWhite),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),

              // ── محتوى لوحة العمليات والتحكم ──
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(18),
                  children: [
                    // 0. مقياس الرؤية والتكبير وحدّة الإضاءة (Visual Scale & Intensity Controls)
                    _buildVisualControlsCard(context, s),
                    const SizedBox(height: 16),

                    // 1. الانتقال بين شاشات التحليل المعقدة (Multi-Dashboard Navigation)
                    _buildHubCard(
                      context: context,
                      title: s.multiDashboardNav,
                      icon: Icons.dashboard_customize_rounded,
                      iconColor: EngineRowingUI.neonLime,
                      children: [
                        _buildActionTile(
                          icon: Icons.speed_rounded,
                          title: s.physicalPerformance,
                          subtitle:
                              'معدل ضربات القلب: 148 bpm • السرعة: 1:45.2 • المسافة: 8,450m',
                          trailingText: 'عرض مباشر',
                          onTap: () {
                            _showSimpleNotice(context, s.physicalPerformance,
                                'يتم عرض مؤشرات النبض والسرعة والمسافة الآن لحظياً من المستشعرات.');
                          },
                        ),
                        const Divider(
                            height: 1, color: EngineRowingUI.bgGridLine),
                        _buildActionTile(
                          icon: Icons.analytics_outlined,
                          title: s.analyticsDashboard,
                          subtitle:
                              'توزيع الزونات، مؤشرات الحمل التراكمي، وكفاءة القوة',
                          trailingText: 'دخول',
                          onTap: () {
                            _showSimpleNotice(context, s.analyticsDashboard,
                                'لوحة التحليلات المتقدمة جاهزة لمتابعة إحصائيات الفريق.');
                          },
                        ),
                        const Divider(
                            height: 1, color: EngineRowingUI.bgGridLine),
                        _buildActionTile(
                          icon: Icons.healing_rounded,
                          title: s.medicalReport,
                          subtitle:
                              'جاهزية: 88% • إجهاد: منخفض • لا توجد إصابات نشطة',
                          trailingText: 'التقرير',
                          onTap: () {
                            _showSimpleNotice(context, s.medicalReport,
                                'تقرير الاستشفاء الطبي: جميع مؤشرات اللاعبين ضمن النطاق الآمن.');
                          },
                        ),
                        const Divider(
                            height: 1, color: EngineRowingUI.bgGridLine),
                        _buildActionTile(
                          icon: Icons.compare_arrows_rounded,
                          title: s.peerDataComparison,
                          subtitle:
                              'مقارنة ومزامنة الأرقام الفسيولوجية بموافقة اللاعبين',
                          trailingText: 'مقارنة',
                          onTap: () {
                            _showSimpleNotice(context, s.peerDataComparison,
                                'تم تفعيل الاتصال ومقارنة الأداء بين لاعبي الفريق.');
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // 2. إدارة وتبديل الحسابات (Profiles & Team Roster Management)
                    _buildHubCard(
                      context: context,
                      title: s.rosterManagement,
                      icon: Icons.manage_accounts_rounded,
                      iconColor: const Color(0xFF2979FF),
                      children: [
                        _buildActionTile(
                          icon: Icons.switch_account_rounded,
                          title: s.switchAthlete,
                          subtitle:
                              'الانتقال بلمسة واحدة من ملف اللاعب (أ) إلى ملف اللاعب (ب)',
                          trailingText: 'تبديل',
                          onTap: () {
                            _showSimpleNotice(context, s.switchAthlete,
                                'تم التبديل بنجاح إلى ملف اللاعب التالي.');
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // 3. التحكم في أدوات التتبع وأجهزة الاستشعار (Hardware & Sensor Integration)
                    _buildHubCard(
                      context: context,
                      title: s.hardwareIntegration,
                      icon: Icons.sensors_rounded,
                      iconColor: EngineRowingUI.neonLime,
                      children: [
                        _buildActionTile(
                          icon: Icons.wifi_tethering_rounded,
                          title: s.coachConnection,
                          subtitle:
                              'الاتصال بين المدرب واللاعب: متصل ومباشر (42ms)',
                          trailingText: 'فحص',
                          onTap: () {
                            _showSimpleNotice(context, s.coachConnection,
                                'الاتصال سليم ومستقر بين أجهزة اللاعبين والمدرب.');
                          },
                        ),
                        const Divider(
                            height: 1, color: EngineRowingUI.bgGridLine),
                        _buildActionTile(
                          icon: Icons.bluetooth_connected_rounded,
                          title: s.sensorCalibration,
                          subtitle:
                              'الأجهزة: ارجوميتر Concept2 PM5 • ساعة استروك كوتش • حزام نبض',
                          trailingText: 'معايرة',
                          onTap: () {
                            _showSimpleNotice(context, s.sensorCalibration,
                                'تمت معايرة جميع المستشعرات وبلوتوث التجديف بدقة 100%.');
                          },
                        ),
                        const Divider(
                            height: 1, color: EngineRowingUI.bgGridLine),
                        _buildActionTile(
                          icon: Icons.cloud_sync_rounded,
                          title: s.cloudSync,
                          subtitle:
                              'مزامنة البيانات ونقل قراءات الأدوات إلى التخزين السحابي',
                          trailingText: 'مزامنة',
                          onTap: () {
                            _showSimpleNotice(context, s.cloudSync,
                                'تمت مزامنة بيانات التجديف مع الخادم السحابي بنجاح.');
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // 4. لوحة المنحنيات (Metrics Curves Shortcut)
                    _buildHubCard(
                      context: context,
                      title: s.metricsCurvesShortcut,
                      icon: Icons.show_chart_rounded,
                      iconColor: const Color(0xFFFF9100),
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'الوصول المباشر إلى المنحنيات الخمسة في البرنامج (كفاءة EF، الواط، التفكك القلبي، النبض، وزونات كارفونين الذكية).',
                                style: TextStyle(
                                    fontSize: 13,
                                    color: EngineRowingUI.labelSlate),
                              ),
                              const SizedBox(height: 12),
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: EngineRowingUI.neonLime,
                                  foregroundColor: EngineRowingUI.bgNavy,
                                  minimumSize: const Size(double.infinity, 48),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10)),
                                ),
                                icon: const Icon(Icons.insights_rounded),
                                label: const Text('فتح لوحة المنحنيات الكاملة',
                                    style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold)),
                                onPressed: onOpenMetricsCurves,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // 5. تصدير التقارير المتقدمة (Advanced Data Export)
                    _buildHubCard(
                      context: context,
                      title: s.advancedDataExport,
                      icon: Icons.file_download_outlined,
                      iconColor: const Color(0xFF2979FF),
                      children: [
                        _buildActionTile(
                          icon: Icons.table_chart_rounded,
                          title: s.exportToExcel,
                          subtitle: s.isArabic
                              ? 'تحويل جميع بيانات الدورة المرحلية والورك أوت إلى ملف Excel'
                              : 'Export all phase cycle and workout data to Excel',
                          trailingText: 'تصدير',
                          onTap: () {
                            _showSimpleNotice(context, s.exportToExcel,
                                'تم تصدير ملف Excel بنجاح وحفظه في مجلد المستندات.');
                          },
                        ),
                        const Divider(
                            height: 1, color: EngineRowingUI.bgGridLine),
                        _buildActionTile(
                          icon: Icons.picture_as_pdf_rounded,
                          title: s.exportToPdf,
                          subtitle:
                              'توليد تقرير طبي وفني جاهز للطباعة أو الإرسال',
                          trailingText: 'طباعة/PDF',
                          onTap: () {
                            _showSimpleNotice(context, s.exportToPdf,
                                'تم إنشاء تقرير PDF الطبي والفني بنجاح.');
                          },
                        ),
                        const Divider(
                            height: 1, color: EngineRowingUI.bgGridLine),
                        _buildActionTile(
                          icon: Icons.share_rounded,
                          title: s.shareReportAction,
                          subtitle:
                              'مشاركة التقارير مباشرة عبر البريد أو تطبيقات الفريق',
                          trailingText: 'مشاركة',
                          onTap: () {
                            _showSimpleNotice(context, s.shareReportAction,
                                'تم فتح نافذة المشاركة لإرسال التقرير للإدارة الفنية.');
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHubCard({
    required BuildContext context,
    required String title,
    required IconData icon,
    required Color iconColor,
    required List<Widget> children,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: EngineRowingUI.cardFill,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: EngineRowingUI.bgGridLine, width: 1.2),
        boxShadow: const [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 10,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // رأس الكارت
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: const BoxDecoration(
              color: EngineRowingUI.equationCardFill,
              borderRadius: BorderRadius.vertical(top: Radius.circular(13)),
            ),
            child: Row(
              children: [
                Icon(icon, color: iconColor, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.bold,
                      color: EngineRowingUI.textWhite,
                    ),
                  ),
                ),
              ],
            ),
          ),
          ...children,
        ],
      ),
    );
  }

  Widget _buildActionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required String trailingText,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: EngineRowingUI.neonLime, size: 22),
      title: Text(
        title,
        style: const TextStyle(
          fontSize: 13.5,
          fontWeight: FontWeight.w700,
          color: EngineRowingUI.textWhite,
        ),
      ),
      subtitle: Text(
        subtitle,
        style:
            const TextStyle(fontSize: 11.5, color: EngineRowingUI.labelSlate),
      ),
      trailing: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: EngineRowingUI.neonLime,
          foregroundColor: EngineRowingUI.bgNavy,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        onPressed: onTap,
        child: Text(
          trailingText,
          style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
        ),
      ),
      onTap: onTap,
    );
  }

  void _showSimpleNotice(BuildContext context, String title, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_rounded,
                color: EngineRowingUI.neonLime),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '$title: $msg',
                style: const TextStyle(
                    fontSize: 12.5, color: EngineRowingUI.textWhite),
              ),
            ),
          ],
        ),
        backgroundColor: EngineRowingUI.toastBg,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Widget _buildVisualControlsCard(BuildContext context, AppStrings s) {
    return _buildHubCard(
      context: context,
      title: s.displayScaleTitle,
      icon: Icons.zoom_in_rounded,
      iconColor: EngineRowingUI.neonLime,
      children: [
        Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.aspect_ratio_rounded,
                      color: EngineRowingUI.neonLime, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      s.displayScaleDesc,
                      style: const TextStyle(
                        color: EngineRowingUI.textWhite,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ValueListenableBuilder<double>(
                valueListenable: userScaleNotifier,
                builder: (context, currentScale, _) {
                  return Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: EngineRowingUI.equationCardFill,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: EngineRowingUI.bgGridLine),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<double>(
                        value: currentScale,
                        dropdownColor: EngineRowingUI.bgNavy,
                        isExpanded: true,
                        icon: const Icon(Icons.arrow_drop_down,
                            color: EngineRowingUI.neonLime),
                        items: const [
                          DropdownMenuItem(
                              value: 0.80,
                              child: Text('80% (تصغير)',
                                  style: TextStyle(
                                      color: EngineRowingUI.textWhite))),
                          DropdownMenuItem(
                              value: 0.90,
                              child: Text('90%',
                                  style: TextStyle(
                                      color: EngineRowingUI.textWhite))),
                          DropdownMenuItem(
                              value: 1.00,
                              child: Text('100% (الافتراضي)',
                                  style: TextStyle(
                                      color: EngineRowingUI.neonLime,
                                      fontWeight: FontWeight.bold))),
                          DropdownMenuItem(
                              value: 1.10,
                              child: Text('110%',
                                  style: TextStyle(
                                      color: EngineRowingUI.textWhite))),
                          DropdownMenuItem(
                              value: 1.25,
                              child: Text('125% (تكبير متوسط)',
                                  style: TextStyle(
                                      color: EngineRowingUI.textWhite))),
                          DropdownMenuItem(
                              value: 1.50,
                              child: Text('150% (تكبير فائق)',
                                  style: TextStyle(
                                      color: EngineRowingUI.textWhite))),
                        ],
                        onChanged: (newVal) {
                          if (newVal != null) {
                            userScaleNotifier.value = newVal;
                          }
                        },
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Icon(Icons.wb_sunny_rounded,
                      color: EngineRowingUI.neonLime, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      s.colorIntensityTitle,
                      style: const TextStyle(
                        color: EngineRowingUI.textWhite,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ValueListenableBuilder<DisplayIntensity>(
                valueListenable: intensityNotifier,
                builder: (context, currentIntensity, _) {
                  return Row(
                    children: [
                      _buildIntensityChip(
                        label: s.intensityNormal,
                        selected: currentIntensity == DisplayIntensity.normal,
                        onTap: () =>
                            intensityNotifier.value = DisplayIntensity.normal,
                      ),
                      const SizedBox(width: 8),
                      _buildIntensityChip(
                        label: s.intensityBright,
                        selected: currentIntensity == DisplayIntensity.bright,
                        onTap: () =>
                            intensityNotifier.value = DisplayIntensity.bright,
                      ),
                      const SizedBox(width: 8),
                      _buildIntensityChip(
                        label: s.intensityUltra,
                        selected: currentIntensity == DisplayIntensity.ultra,
                        onTap: () =>
                            intensityNotifier.value = DisplayIntensity.ultra,
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(Icons.pinch_rounded,
                      color: EngineRowingUI.captionGrey, size: 16),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      s.pinchZoomHint,
                      style: const TextStyle(
                          color: EngineRowingUI.captionGrey, fontSize: 11),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildIntensityChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected
                ? EngineRowingUI.neonLime.withAlpha(50)
                : EngineRowingUI.equationCardFill,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected
                  ? EngineRowingUI.neonLime
                  : EngineRowingUI.bgGridLine,
              width: selected ? 1.5 : 1.0,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected
                  ? EngineRowingUI.neonLime
                  : EngineRowingUI.labelSlate,
              fontSize: 11.5,
              fontWeight: selected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }
}
