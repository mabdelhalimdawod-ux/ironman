import 'package:flutter/material.dart';
import 'app_strings.dart';
import 'auth_service.dart';

const Color _navy = Color(0xFF0D3B66);
const Color _yellow = Color(0xFFFFC93C);

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
      backgroundColor: const Color(0xFFF9FBFC),
      appBar: AppBar(
        title: Text(s.adminPlaceholderTitle),
        actions: [
          IconButton(
            tooltip: s.logout,
            icon: const Icon(Icons.logout_rounded),
            onPressed: () => _confirmLogout(context, s),
          ),
        ],
      ),
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 520),
          margin: const EdgeInsets.all(24),
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: _navy.withAlpha(20),
                blurRadius: 30,
                offset: const Offset(0, 10),
              ),
            ],
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: _yellow.withAlpha(40),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.admin_panel_settings_rounded,
                  size: 46,
                  color: _navy,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                s.adminPlaceholderTitle,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: _navy,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                s.adminPlaceholderDesc,
                style: TextStyle(
                  fontSize: 15,
                  color: Colors.grey.shade600,
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
    );
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
