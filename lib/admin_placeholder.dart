import 'package:flutter/material.dart';
import 'app_strings.dart';
import 'auth_service.dart';
import 'engine_rowing_ui.dart';

/// شاشة مؤقتة للوحة الأدمن مع زر تسجيل الخروج
class AdminPlaceholderPage extends StatelessWidget {
  final VoidCallback onLogout;

  const AdminPlaceholderPage({
    super.key,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);

    return Scaffold(
      backgroundColor: EngineRowingUI.bgNavy,
      appBar: AppBar(
        backgroundColor: EngineRowingUI.bgNavy,
        foregroundColor: EngineRowingUI.textWhite,
        elevation: 0,
        title: Text(s.adminPlaceholderTitle),
        actions: [
          IconButton(
            tooltip: s.logout,
            icon: const Icon(Icons.logout_rounded, color: Colors.redAccent),
            onPressed: () => _confirmLogout(context, s),
          ),
        ],
      ),
      body: RowingGridBackground(
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 520),
            margin: const EdgeInsets.all(24),
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: EngineRowingUI.cardFill,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 30,
                  offset: const Offset(0, 10),
                ),
              ],
              border: Border.all(color: EngineRowingUI.bgGridLine),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: EngineRowingUI.equationCardFill,
                    shape: BoxShape.circle,
                    border: Border.all(color: EngineRowingUI.bgGridLine),
                  ),
                  child: const Icon(
                    Icons.admin_panel_settings_rounded,
                    size: 46,
                    color: EngineRowingUI.neonLime,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  s.adminPlaceholderTitle,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: EngineRowingUI.textWhite,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  s.adminPlaceholderDesc,
                  style: const TextStyle(
                    fontSize: 14,
                    color: EngineRowingUI.labelSlate,
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => _confirmLogout(context, s),
                    icon: const Icon(Icons.logout_rounded, color: Colors.redAccent),
                    label: Text(
                      s.logout,
                      style: const TextStyle(
                        color: Colors.redAccent,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.redAccent, width: 1.2),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _confirmLogout(BuildContext context, AppStrings s) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: EngineRowingUI.cardFill,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: EngineRowingUI.bgGridLine),
        ),
        title: Text(
          s.logout,
          style: const TextStyle(color: EngineRowingUI.textWhite, fontWeight: FontWeight.bold),
        ),
        content: Text(
          s.logoutConfirm,
          style: const TextStyle(color: EngineRowingUI.labelSlate),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: Text(s.cancel, style: const TextStyle(color: EngineRowingUI.labelSlate)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
            onPressed: () async {
              Navigator.pop(dialogCtx);
              await AuthService.logout();
              onLogout();
            },
            child: Text(s.logout),
          ),
        ],
      ),
    );
  }
}
