import 'package:flutter/material.dart';
import 'app_strings.dart';
import 'auth_service.dart';
import 'engine_rowing_ui.dart';
import 'progress_curve_page.dart';
import 'progress_panel.dart';

/// عنصر واحد في قائمة منحنيات تبويب Progress
class _ProgressMenuEntry {
  final ProgressCurveType type;
  final IconData icon;
  final Color accentColor;
  final String Function(AppStrings s) title;
  final String Function(AppStrings s) subtitle;

  const _ProgressMenuEntry({
    required this.type,
    required this.icon,
    required this.accentColor,
    required this.title,
    required this.subtitle,
  });
}

/// تبويب التقدم والتحليلات (Progress Tab)
/// أول شاشة فيه: قائمة بأيقونات كل المنحنيات السبعة بأسمائها، وكل أيقونة تفتح شاشة المنحنى.
class ProgressTab extends StatefulWidget {
  final AppUser? user;

  const ProgressTab({super.key, this.user});

  @override
  State<ProgressTab> createState() => _ProgressTabState();
}

class _ProgressTabState extends State<ProgressTab> {
  static final List<_ProgressMenuEntry> _menuEntries = [
    _ProgressMenuEntry(
      type: ProgressCurveType.matrixZone,
      icon: Icons.grid_view_rounded,
      accentColor: const Color(0xFF00E5FF),
      title: (s) => s.matrixZoneTitle,
      subtitle: (s) => s.matrixZoneDesc,
    ),
    _ProgressMenuEntry(
      type: ProgressCurveType.efAndDecoupling,
      icon: Icons.speed_rounded,
      accentColor: EngineRowingUI.neonLime,
      title: (s) => s.efDecouplingTitle,
      subtitle: (s) => s.efDecouplingDesc,
    ),
    _ProgressMenuEntry(
      type: ProgressCurveType.watts,
      icon: Icons.bolt_rounded,
      accentColor: const Color(0xFFFFD600),
      title: (s) => s.wattsCurveTitle,
      subtitle: (s) => s.wattsCurveDesc,
    ),
    _ProgressMenuEntry(
      type: ProgressCurveType.pmcLoad,
      icon: Icons.analytics_rounded,
      accentColor: const Color(0xFF2979FF),
      title: (s) => s.pmcLoadTitle,
      subtitle: (s) => s.pmcLoadDesc,
    ),
    _ProgressMenuEntry(
      type: ProgressCurveType.recovery,
      icon: Icons.favorite_outline_rounded,
      accentColor: const Color(0xFF69F0AE),
      title: (s) => s.recoveryCurvesTitle,
      subtitle: (s) => s.recoveryCurvesDesc,
    ),
    _ProgressMenuEntry(
      type: ProgressCurveType.zoneHours,
      icon: Icons.pie_chart_outline_rounded,
      accentColor: const Color(0xFFFF9100),
      title: (s) => s.zoneHoursTitle,
      subtitle: (s) => s.zoneHoursDesc,
    ),
    _ProgressMenuEntry(
      type: ProgressCurveType.cpTests,
      icon: Icons.workspace_premium_rounded,
      accentColor: const Color(0xFFB388FF),
      title: (s) => s.cpTestsCurveTitle,
      subtitle: (s) => s.cpTestsCurveDesc,
    ),
  ];

  void _openCurve(ProgressCurveType type) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProgressCurvePage(
          curveType: type,
          user: widget.user,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);

    return RowingGridBackground(
      maxContentWidth: 850,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        children: [
          ProgressPanel(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                const Icon(
                  Icons.auto_graph_rounded,
                  color: EngineRowingUI.neonLime,
                  size: 26,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.progressTitle,
                        style: const TextStyle(
                          color: EngineRowingUI.textWhite,
                          fontSize: 16.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        s.progressSubtitle,
                        style: const TextStyle(
                          color: EngineRowingUI.captionGrey,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 560;
              final itemWidth = isWide
                  ? (constraints.maxWidth - 10) / 2
                  : constraints.maxWidth;

              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: _menuEntries.map((entry) {
                  return SizedBox(
                    width: itemWidth,
                    child: _buildCurveMenuTile(s, entry),
                  );
                }).toList(),
              );
            },
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildCurveMenuTile(AppStrings s, _ProgressMenuEntry entry) {
    return InkWell(
      onTap: () => _openCurve(entry.type),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: EngineRowingUI.cardFill,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: entry.accentColor.withValues(alpha: 0.45),
            width: 1.1,
          ),
          boxShadow: [
            BoxShadow(
              color: entry.accentColor.withValues(alpha: 0.12),
              blurRadius: 8,
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: entry.accentColor.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: entry.accentColor.withValues(alpha: 0.5),
                ),
              ),
              child: Icon(
                entry.icon,
                color: entry.accentColor,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.title(s),
                    style: const TextStyle(
                      color: EngineRowingUI.textWhite,
                      fontSize: 14.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    entry.subtitle(s),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: EngineRowingUI.labelSlate,
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: entry.accentColor,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }
}
