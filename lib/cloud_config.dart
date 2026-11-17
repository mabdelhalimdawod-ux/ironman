import 'cloud_config.local.dart';

/// إعدادات الاتصال بالسحابة (Supabase)
/// يقرأ الرابط والمفتاح العام (anon key) من lib/cloud_config.local.dart
/// وفي حال عدم ضبطهما أو عدم وجود اتصال يعمل التطبيق في الوضع المحلي (Local-first / Offline).
class CloudConfig {
  static const String _envUrl = String.fromEnvironment('SUPABASE_URL');
  static const String _envAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  /// رابط مشروع Supabase
  static String get url {
    if (_envUrl.trim().isNotEmpty) return _envUrl.trim();
    return localSupabaseUrl.trim();
  }

  /// المفتاح العام للوصول المجهول (anon public key) - ممنوع استخدام service_role هنا نهائياً
  static String get anonKey {
    if (_envAnonKey.trim().isNotEmpty) return _envAnonKey.trim();
    return localSupabaseAnonKey.trim();
  }

  /// هل تم ضبط إعدادات السحابة بقيم حقيقية؟
  static bool get isConfigured {
    final u = url;
    final k = anonKey;
    return u.isNotEmpty &&
        k.isNotEmpty &&
        (u.startsWith('https://') || u.startsWith('http://'));
  }
}
