import 'package:flutter/material.dart';
import 'app_strings.dart';
import 'sync_engine.dart';

/// ويدجت أيقونة حالة المزامنة اللحظية في الشريط العلوي (Top App Bar)
class SyncStatusIcon extends StatelessWidget {
  const SyncStatusIcon({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: SyncEngine.instance,
      builder: (context, _) {
        final engine = SyncEngine.instance;
        final s = AppStrings.of(context);

        IconData iconData;
        Color iconColor;
        String tooltipText;

        switch (engine.status) {
          case SyncStatus.syncing:
            iconData = Icons.sync;
            iconColor = const Color(0xFF00E5FF); // Neon cyan
            tooltipText = s.syncStatusSyncing;
            break;
          case SyncStatus.synced:
            iconData = Icons.cloud_done_rounded;
            iconColor = const Color(0xFF00E676); // Neon green
            final lastTime = engine.lastSyncedAt != null
                ? '${engine.lastSyncedAt!.hour.toString().padLeft(2, '0')}:${engine.lastSyncedAt!.minute.toString().padLeft(2, '0')}'
                : '';
            tooltipText = lastTime.isNotEmpty
                ? '${s.syncStatusSynced} (${s.syncLastTime(lastTime)})'
                : s.syncStatusSynced;
            break;
          case SyncStatus.offline:
            iconData = Icons.cloud_off_rounded;
            iconColor = Colors.white54;
            tooltipText = s.syncStatusOffline;
            break;
          case SyncStatus.error:
            iconData = Icons.sync_problem_rounded;
            iconColor = const Color(0xFFFF5252); // Neon red
            tooltipText = engine.lastError != null && engine.lastError!.isNotEmpty
                ? '${s.syncStatusError}: ${engine.lastError}'
                : s.syncStatusError;
            break;
        }

        final pending = engine.pendingDirtyCount;
        if (pending > 0 && engine.status != SyncStatus.syncing) {
          tooltipText += ' • ${s.syncPendingCount(pending)}';
        }

        return Tooltip(
          message: tooltipText,
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () {
              SyncEngine.instance.syncNow();
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  if (engine.status == SyncStatus.syncing)
                    const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF00E5FF)),
                      ),
                    )
                  else
                    Icon(
                      iconData,
                      size: 20,
                      color: iconColor,
                    ),
                  if (pending > 0 && engine.status != SyncStatus.syncing)
                    Positioned(
                      top: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: const BoxDecoration(
                          color: Color(0xFFFF9100),
                          shape: BoxShape.circle,
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 10,
                          minHeight: 10,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
