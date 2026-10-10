import 'package:flutter/material.dart';
import 'app_strings.dart';
import 'dashboard_tab.dart';
import 'workouts_tab.dart';
import 'settings_tab.dart';

const Color navy = Color(0xFF0D3B66);
const Color sky = Color(0xFFE8F4FC);
const Color yellow = Color(0xFFFFC93C);

void main() => runApp(const IronmanApp());

class IronmanApp extends StatelessWidget {
  const IronmanApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppLanguage.instance,
      builder: (context, _) {
        final isArabic = AppLanguage.instance.isArabic;

        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'Ironman Rowing',
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
          home: const MainNavigationScaffold(),
        );
      },
    );
  }
}

/// الهيكل الرئيسي للتطبيق مع شريط التنقل السفلي (BottomNavigationBar)
class MainNavigationScaffold extends StatefulWidget {
  const MainNavigationScaffold({super.key});

  @override
  State<MainNavigationScaffold> createState() => _MainNavigationScaffoldState();
}

class _MainNavigationScaffoldState extends State<MainNavigationScaffold> {
  int _currentIndex = 0;

  final List<Widget> _tabs = const [
    DashboardTab(),
    WorkoutsTab(),
    SettingsTab(),
  ];

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _currentIndex == 0
              ? s.tabDashboard
              : _currentIndex == 1
                  ? s.tabWorkouts
                  : s.tabSettings,
        ),
      ),
      body: IndexedStack(
        index: _currentIndex,
        children: _tabs,
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(15),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: NavigationBar(
          selectedIndex: _currentIndex,
          onDestinationSelected: (idx) => setState(() => _currentIndex = idx),
          backgroundColor: Colors.white,
          indicatorColor: yellow.withAlpha(180),
          elevation: 0,
          destinations: [
            NavigationDestination(
              icon: const Icon(Icons.dashboard_outlined, color: navy),
              selectedIcon: const Icon(Icons.dashboard, color: navy),
              label: s.tabDashboard,
            ),
            NavigationDestination(
              icon: const Icon(Icons.fitness_center_outlined, color: navy),
              selectedIcon: const Icon(Icons.fitness_center, color: navy),
              label: s.tabWorkouts,
            ),
            NavigationDestination(
              icon: const Icon(Icons.settings_outlined, color: navy),
              selectedIcon: const Icon(Icons.settings, color: navy),
              label: s.tabSettings,
            ),
          ],
        ),
      ),
    );
  }
}
