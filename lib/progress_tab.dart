import 'package:flutter/material.dart';
import 'app_strings.dart';
import 'auth_service.dart';
import 'curve_privacy_service.dart';
import 'db.dart';
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

  bool _curvesShared = false;
  List<Map<String, dynamic>> _teammates = [];

  @override
  void initState() {
    super.initState();
    _loadTeammatesAndPrivacy();
  }

  Future<void> _loadTeammatesAndPrivacy() async {
    final user = widget.user;
    if (user != null && user.isAthlete) {
      final db = await DB.db;
      final playerRows = await db.query('players',
          where: 'id = ?', whereArgs: [user.id], limit: 1);
      if (playerRows.isNotEmpty) {
        _curvesShared =
            (playerRows.first['curves_shared'] as num?)?.toInt() == 1;
      }
      if (user.coachId != null) {
        final teamRows = await db.query(
          'players',
          where: 'id != ?',
          whereArgs: [user.id],
        );
        _teammates = teamRows;
      }
      if (mounted) setState(() {});
    }
  }

  void _onTeammateTap(AppStrings s, Map<String, dynamic> teammate) {
    final shared = (teammate['curves_shared'] as num?)?.toInt() == 1;
    final name = teammate['name']?.toString() ?? 'لاعب';
    if (!shared) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: EngineRowingUI.cardFill,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: EngineRowingUI.bgGridLine),
          ),
          title: Row(
            children: [
              const Icon(Icons.lock_rounded, color: Colors.amber, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  name,
                  style: const TextStyle(
                      color: EngineRowingUI.textWhite, fontSize: 16),
                ),
              ),
            ],
          ),
          content: Text(
            s.curvesNotShared,
            style: const TextStyle(
                color: EngineRowingUI.captionGrey, fontSize: 13),
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
    } else {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ProgressCurvePage(
            curveType: ProgressCurveType.matrixZone,
            user: widget.user,
          ),
        ),
      );
    }
  }

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

          // ── قسم مشاركة المنحنيات وزملاء الفريق (خاص باللاعبين) ──
          if (widget.user != null && widget.user!.isAthlete) ...[
            _buildAthletePrivacyCard(s),
            const SizedBox(height: 12),
            if (_teammates.isNotEmpty) ...[
              _buildTeammatesList(s),
              const SizedBox(height: 14),
            ],
          ],
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

  Widget _buildAthletePrivacyCard(AppStrings s) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: EngineRowingUI.cardFill,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: EngineRowingUI.bgGridLine),
      ),
      child: Row(
        children: [
          Icon(
            _curvesShared
                ? Icons.lock_open_rounded
                : Icons.lock_outline_rounded,
            color: _curvesShared ? EngineRowingUI.neonLime : Colors.amber,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.shareMyCurves,
                  style: const TextStyle(
                    color: EngineRowingUI.textWhite,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                Text(
                  s.shareMyCurvesSubtitle,
                  style: const TextStyle(
                      color: EngineRowingUI.captionGrey, fontSize: 12),
                ),
              ],
            ),
          ),
          Switch(
            value: _curvesShared,
            activeThumbColor: EngineRowingUI.neonLime,
            onChanged: (val) async {
              setState(() => _curvesShared = val);
              await CurvePrivacyService.setCurveSharing(
                actor: widget.user!,
                targetPlayerId: widget.user!.id,
                shared: val,
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildTeammatesList(AppStrings s) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          s.myTeammates,
          style: const TextStyle(
            color: EngineRowingUI.gold,
            fontWeight: FontWeight.bold,
            fontSize: 12.5,
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 44,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _teammates.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, idx) {
              final tm = _teammates[idx];
              final shared = (tm['curves_shared'] as num?)?.toInt() == 1;
              final name = tm['name']?.toString() ?? 'لاعب';

              return InkWell(
                onTap: () => _onTeammateTap(s, tm),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: EngineRowingUI.equationCardFill,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: shared
                          ? EngineRowingUI.neonLime.withAlpha(90)
                          : EngineRowingUI.bgGridLine,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircleAvatar(
                        radius: 12,
                        backgroundColor: shared
                            ? EngineRowingUI.neonLime.withAlpha(40)
                            : Colors.white12,
                        child: Text(
                          name.isNotEmpty ? name.substring(0, 1) : '?',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: shared
                                ? EngineRowingUI.neonLime
                                : EngineRowingUI.captionGrey,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        name,
                        style: const TextStyle(
                            color: EngineRowingUI.textWhite, fontSize: 12),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        shared
                            ? Icons.check_circle_outline_rounded
                            : Icons.lock_outline_rounded,
                        size: 14,
                        color: shared ? EngineRowingUI.neonLime : Colors.amber,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
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
                      fontSize: 12,
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
