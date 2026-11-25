/// نموذج تهيئة بيانات التطوير المحلية (Dev Seed Configuration).
/// انسخ هذا الملف إلى `lib/dev_seed.local.dart` وضع بياناتك المحلية إذا أردت زرع حسابات تجريبية أثناء وضع Debug فقط.
/// يُحظر تماماً كتابة أو رفع أي بيانات حقيقية أو كلمات مرور في ملفات المصدر.
class DevSeedConfig {
  static const String? adminEmail = null;
  static const String? adminPassword = null;
  static const String? adminName = null;

  static const String? coachEmail = null;
  static const String? coachPassword = null;
  static const String? coachName = null;

  static const String? athleteEmail = null;
  static const String? athletePassword = null;
  static const String? athleteName = null;

  /// فحص توفر أي بيانات تطوير محلية لزرعها
  static bool get hasDevAccounts =>
      (adminEmail != null && adminPassword != null) ||
      (coachEmail != null && coachPassword != null) ||
      (athleteEmail != null && athletePassword != null);
}
