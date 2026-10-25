import 'dart:io';
import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'admin_placeholder.dart';
import 'app_strings.dart';
import 'auth_service.dart';
import 'dashboard_tab.dart';
import 'login_page.dart';
import 'program_tab.dart';
import 'workouts_tab.dart';

const Color navy = Color(0xFF0D3B66);
const Color sky = Color(0xFFE8F4FC);
const Color yellow = Color(0xFFFFC93C);

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
      listenable: AppLanguage.instance,
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
          theme: ThemeData(
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(
              seedColor: navy,
              primary: navy,
              secondary: yellow,
              surface: Colors.white,
            ),
            scaffoldBackgroundColor: const Color(0xFFF9FBFC),
            appBarTheme: const AppBarTheme(
              backgroundColor: navy,
              foregroundColor: Colors.white,
              elevation: 0,
              centerTitle: true,
              titleTextStyle: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            cardTheme: CardThemeData(
              color: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: Colors.grey.shade200),
              ),
            ),
            filledButtonTheme: FilledButtonThemeData(
              style: FilledButton.styleFrom(
                backgroundColor: yellow,
                foregroundColor: navy,
                minimumSize: const Size(0, 52),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
            inputDecorationTheme: InputDecorationTheme(
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            ),
          ),
          home: _checkingSession
              ? const Scaffold(
                  backgroundColor: navy,
                  body: Center(
                    child: CircularProgressIndicator(color: yellow),
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
  double _navWidth = 200.0;
  bool _isResizing = false;

  // ── أحجام الشريط الجانبي ──
  static const double _minWidth = 72.0;   // أيقونات فقط
  static const double _midWidth = 200.0;  // أيقونات + نصوص
  static const double _maxWidth = 280.0;  // موسّع بالكامل

  List<Widget> get _tabs => [
    DashboardTab(user: widget.user),
    const ProgramTab(),
    const WorkoutsTab(),
  ];

  /// يرجع لأقرب حجم مسبق بعد انتهاء السحب
  void _snapToNearest() {
    const presets = [_minWidth, _midWidth, _maxWidth];
    double closest = presets.reduce((a, b) =>
        (a - _navWidth).abs() < (b - _navWidth).abs() ? a : b);
    setState(() {
      _navWidth = closest;
      _isResizing = false;
    });
  }

  /// التبديل بين الأحجام الثلاثة
  void _cycleSize() {
    setState(() {
      if (_navWidth <= _minWidth + 30) {
        _navWidth = _midWidth;
      } else if (_navWidth <= _midWidth + 30) {
        _navWidth = _maxWidth;
      } else {
        _navWidth = _minWidth;
      }
    });
  }

  String _sizeLabel(AppStrings s) {
    if (_navWidth <= _minWidth + 30) return s.isArabic ? 'مصغّر' : 'Compact';
    if (_navWidth <= _midWidth + 30) return s.isArabic ? 'عادي' : 'Normal';
    return s.isArabic ? 'موسّع' : 'Expanded';
  }

  IconData _cycleIcon() {
    if (_navWidth <= _minWidth + 30) return Icons.chevron_left_rounded;
    if (_navWidth <= _midWidth + 30) return Icons.chevron_left_rounded;
    return Icons.chevron_right_rounded;
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

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final isCollapsed = _navWidth < 120;

    final navItems = [
      _SideNavItemData(Icons.home_outlined, Icons.home, s.tabHome),
      _SideNavItemData(Icons.event_repeat_outlined, Icons.event_repeat, s.tabProgram),
      _SideNavItemData(Icons.fitness_center_outlined, Icons.fitness_center, s.tabWorkouts),
    ];

    return Scaffold(
      body: Row(
        textDirection: TextDirection.ltr, // النافيجيشن دائماً على اليمين
        children: [
          // ════════════════════════════════════════
          // ██  المحتوى الرئيسي
          // ════════════════════════════════════════
          Expanded(
            child: Column(
              children: [
                // ── AppBar ──
                Container(
                  height: 60,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [navy, Color(0xFF164B7A)],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    [s.tabHome, s.tabProgram, s.tabWorkouts][_currentIndex],
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                // ── Body ──
                Expanded(
                  child: IndexedStack(
                    index: _currentIndex,
                    children: _tabs,
                  ),
                ),
              ],
            ),
          ),

          // ════════════════════════════════════════
          // ██  مقبض السحب (Drag Handle)
          // ════════════════════════════════════════
          GestureDetector(
            onHorizontalDragStart: (_) =>
                setState(() => _isResizing = true),
            onHorizontalDragUpdate: (details) {
              setState(() {
                _navWidth = (_navWidth - details.delta.dx)
                    .clamp(_minWidth, _maxWidth);
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
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ),
            ),
          ),

          // ════════════════════════════════════════
          // ██  الشريط الجانبي (Side Navigation)
          // ════════════════════════════════════════
          AnimatedContainer(
            duration: _isResizing
                ? Duration.zero
                : const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            width: _navWidth,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF0F4070), navy],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(40),
                  blurRadius: 24,
                  offset: const Offset(-4, 0),
                ),
              ],
            ),
            child: Column(
              children: [
                // ── منطقة الشعار ──
                Container(
                  height: 60,
                  alignment: Alignment.center,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    switchInCurve: Curves.easeOut,
                    switchOutCurve: Curves.easeIn,
                    child: isCollapsed
                        ? const Icon(
                            Icons.rowing_rounded,
                            key: ValueKey('icon'),
                            color: yellow,
                            size: 30,
                          )
                        : Row(
                            key: const ValueKey('brand'),
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.rowing_rounded,
                                  color: yellow, size: 26),
                              const SizedBox(width: 10),
                              Text(
                                'ENGINE ROWING',
                                style: TextStyle(
                                  color: yellow,
                                  fontSize: _navWidth > 240 ? 18 : 14,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.5,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
                // ── فاصل ──
                Padding(
                  padding: EdgeInsets.symmetric(
                      horizontal: isCollapsed ? 14 : 20),
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
                    isActive: isActive,
                    isCollapsed: isCollapsed,
                    navWidth: _navWidth,
                    onTap: () => setState(() => _currentIndex = i),
                  );
                }),

                const Spacer(),

                // ── فاصل سفلي ──
                Padding(
                  padding: EdgeInsets.symmetric(
                      horizontal: isCollapsed ? 14 : 20),
                  child: Divider(
                    color: Colors.white.withAlpha(30),
                    height: 1,
                  ),
                ),
                const SizedBox(height: 6),

                // ── زرار تسجيل الخروج المؤقت ──
                _SideNavItem(
                  icon: Icons.logout_rounded,
                  label: s.logout,
                  isActive: false,
                  isCollapsed: isCollapsed,
                  navWidth: _navWidth,
                  onTap: () => _confirmLogout(context, s),
                ),

                const SizedBox(height: 4),

                // ── زر تغيير الحجم ──
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  child: Material(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: _cycleSize,
                      hoverColor: Colors.white.withAlpha(20),
                      splashColor: yellow.withAlpha(40),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: EdgeInsets.symmetric(
                          horizontal: isCollapsed ? 0 : 14,
                          vertical: 12,
                        ),
                        child: Row(
                          mainAxisAlignment: isCollapsed
                              ? MainAxisAlignment.center
                              : MainAxisAlignment.start,
                          children: [
                            Icon(
                              _cycleIcon(),
                              color: Colors.white54,
                              size: 22,
                            ),
                            if (!isCollapsed) ...[
                              const SizedBox(width: 12),
                              Flexible(
                                child: Text(
                                  _sizeLabel(s),
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white54,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w400,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ],
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
  const _SideNavItemData(this.icon, this.activeIcon, this.label);
}

// ════════════════════════════════════════════════════════════════
// ويدجت عنصر التنقل الجانبي
// ════════════════════════════════════════════════════════════════
class _SideNavItem extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final bool isCollapsed;
  final double navWidth;
  final VoidCallback onTap;

  const _SideNavItem({
    required this.icon,
    required this.label,
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
                  color: isActive
                      ? yellow.withAlpha(70)
                      : Colors.transparent,
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
                  // ── الأيقونة ──
                  AnimatedScale(
                    scale: _isHovered && !isActive ? 1.15 : 1.0,
                    duration: const Duration(milliseconds: 180),
                    child: Icon(
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
