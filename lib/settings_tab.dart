import 'package:flutter/material.dart';
import 'app_strings.dart';
import 'db.dart';
import 'engine_rowing_ui.dart';

/// التاب الثالث: الإعدادات (Settings Tab)
class SettingsTab extends StatefulWidget {
  const SettingsTab({super.key});

  @override
  State<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<SettingsTab> {
  int _playerCount = 0;
  int _cycleCount = 0;
  int _sessionCount = 0;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    try {
      final p = await DB.q('SELECT COUNT(*) as c FROM players');
      final c = await DB.q('SELECT COUNT(*) as c FROM cycles');
      final s = await DB.q('SELECT COUNT(*) as c FROM sessions');
      if (mounted) {
        setState(() {
          _playerCount = (p.first['c'] as int?) ?? 0;
          _cycleCount = (c.first['c'] as int?) ?? 0;
          _sessionCount = (s.first['c'] as int?) ?? 0;
        });
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final isArabic = AppLanguage.instance.isArabic;

    return RowingGridBackground(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 850),
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            children: [
              // رأس الصفحة
              _buildHeader(s),
              const SizedBox(height: 16),

              // 1. قسم تغيير لغة التطبيق
              _buildLanguageSection(s, isArabic),
              const SizedBox(height: 16),

              // 2. بطاقة بنية المرحلة الأولى
              _buildPhase1InfoCard(s),
              const SizedBox(height: 16),

              // 3. إحصائيات النظام وقاعدة البيانات
              _buildDatabaseStatsCard(s),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(AppStrings s) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: EngineRowingUI.cardFill,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: EngineRowingUI.bgGridLine),
          ),
          child: const Icon(Icons.settings, color: EngineRowingUI.neonLime, size: 28),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              s.tabSettings,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: EngineRowingUI.textWhite,
              ),
            ),
            Text(
              s.languageSwitchDesc,
              style: const TextStyle(fontSize: 13, color: EngineRowingUI.labelSlate),
            ),
          ],
        ),
      ],
    );
  }

  // بطاقة تبديل اللغة
  Widget _buildLanguageSection(AppStrings s, bool isArabic) {
    return Container(
      decoration: BoxDecoration(
        color: EngineRowingUI.cardFill,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: EngineRowingUI.bgGridLine),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.translate, color: EngineRowingUI.neonLime, size: 22),
              const SizedBox(width: 8),
              Text(
                s.languageSettings,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: EngineRowingUI.textWhite,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            s.languageSwitchDesc,
            style: const TextStyle(fontSize: 13, color: EngineRowingUI.labelSlate),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              // زر اللغة العربية
              Expanded(
                child: InkWell(
                  onTap: () {
                    AppLanguage.instance.setLocale(const Locale('ar'));
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: isArabic ? EngineRowingUI.neonLime : EngineRowingUI.equationCardFill,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isArabic ? EngineRowingUI.neonLime : EngineRowingUI.bgGridLine,
                        width: isArabic ? 2 : 1,
                      ),
                    ),
                    child: Column(
                      children: [
                        Text(
                          'العربية (افتراضي)',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: isArabic ? EngineRowingUI.bgNavy : EngineRowingUI.textWhite,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Arabic (RTL)',
                          style: TextStyle(
                            fontSize: 11,
                            color: isArabic ? EngineRowingUI.bgNavy.withValues(alpha: 0.8) : EngineRowingUI.labelSlate,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // زر اللغة الإنجليزية
              Expanded(
                child: InkWell(
                  onTap: () {
                    AppLanguage.instance.setLocale(const Locale('en'));
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: !isArabic ? EngineRowingUI.neonLime : EngineRowingUI.equationCardFill,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: !isArabic ? EngineRowingUI.neonLime : EngineRowingUI.bgGridLine,
                        width: !isArabic ? 2 : 1,
                      ),
                    ),
                    child: Column(
                      children: [
                        Text(
                          'English',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: !isArabic ? EngineRowingUI.bgNavy : EngineRowingUI.textWhite,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'إنجليزية (LTR)',
                          style: TextStyle(
                            fontSize: 11,
                            color: !isArabic ? EngineRowingUI.bgNavy.withValues(alpha: 0.8) : EngineRowingUI.labelSlate,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPhase1InfoCard(AppStrings s) {
    return Container(
      decoration: BoxDecoration(
        color: EngineRowingUI.cardFill,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: EngineRowingUI.bgGridLine),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.layers_outlined, color: EngineRowingUI.neonLime, size: 22),
              const SizedBox(width: 8),
              Text(
                s.appArchitecture,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: EngineRowingUI.textWhite,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            s.phase1Active,
            style: const TextStyle(fontSize: 14, color: EngineRowingUI.neonLime, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(
            '• Engine Rowing Dashboard: الجاهزية، السيكل، الحصة القادمة، اتجاه وتنبيه EF للفريق\n'
            '• التمارين: فتح حصة اليوم، قائمة اللاعبين مع تلوين حالة التسجيل، فورم إدخال متكامل مع NP و Decoupling للاعبين الأساسيين\n'
            '• الإعدادات: بنية الترجمة والتبديل السلس بين اللغات',
            style: const TextStyle(fontSize: 12, color: EngineRowingUI.labelSlate, height: 1.5),
          ),
        ],
      ),
    );
  }

  Widget _buildDatabaseStatsCard(AppStrings s) {
    return Container(
      decoration: BoxDecoration(
        color: EngineRowingUI.cardFill,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: EngineRowingUI.bgGridLine),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.storage, color: EngineRowingUI.neonLime, size: 22),
              const SizedBox(width: 8),
              Text(
                s.databaseStatus,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: EngineRowingUI.textWhite,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
            decoration: BoxDecoration(
              color: EngineRowingUI.equationCardFill,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: EngineRowingUI.bgGridLine),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatChip(s.isArabic ? 'اللاعبون' : 'Athletes', '$_playerCount'),
                _buildStatChip('Cycles', '$_cycleCount'),
                _buildStatChip(s.isArabic ? 'الحصص' : 'Sessions', '$_sessionCount'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatChip(String label, String value) {
    return Column(
      children: [
        Directionality(
          textDirection: TextDirection.ltr,
          child: Text(
            RowingNumberFormatter.toEnglishDigits(value),
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: EngineRowingUI.neonLime,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: EngineRowingUI.labelSlate),
        ),
      ],
    );
  }
}
