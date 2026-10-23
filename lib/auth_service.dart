import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'db.dart';

/// نموذج بيانات المستخدم (User Model)
class AppUser {
  final int id;
  final String email;
  final String name;
  final String role; // 'admin' | 'coach' | 'athlete'
  final int? coachId;
  final bool subscriptionActive;
  final int? playerId;
  final String? createdAt;

  const AppUser({
    required this.id,
    required this.email,
    required this.name,
    required this.role,
    this.coachId,
    required this.subscriptionActive,
    this.playerId,
    this.createdAt,
  });

  bool get isAdmin => role == 'admin';
  bool get isCoach => role == 'coach';
  bool get isAthlete => role == 'athlete';

  factory AppUser.fromMap(Map<String, dynamic> map) {
    return AppUser(
      id: map['id'] as int,
      email: (map['email'] as String?) ?? '',
      name: (map['name'] as String?) ?? '',
      role: (map['role'] as String?) ?? 'athlete',
      coachId: map['coach_id'] as int?,
      subscriptionActive: (map['subscription_active'] as int? ?? 1) == 1,
      playerId: map['player_id'] as int?,
      createdAt: map['created_at'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'email': email,
      'name': name,
      'role': role,
      'coach_id': coachId,
      'subscription_active': subscriptionActive ? 1 : 0,
      'player_id': playerId,
      'created_at': createdAt,
    };
  }
}

/// خدمة المصادقة وإدارة المستخدمين والجلسات (Authentication Service)
class AuthService {
  static const String _keyUserId = 'auth_session_user_id';
  static const String _keyRemember = 'auth_remember_me';
  static const String _keySavedEmail = 'auth_saved_email';

  static AppUser? currentUser;

  // ============================================================================
  // تحذير أمني: الحسابات التالية مخصصة لبيئة التطوير والاختبار المحلي فقط (DEBUG ONLY)
  // ويتم زراعتها فقط عند تفعيل kDebugMode. لا يتم زراعة أي حساب في وضع Release.
  // يجب التأكد من عدم استخدامها أو زرعها في بيئة الإنتاج الحقيقية وتتشال قبل الإصدار.
  // SECURITY NOTICE: The following test credentials are for local debug development only.
  // Never seed or use in production release mode. Must be removed before release.
  // ============================================================================
  static const String devAdminEmail = 'admin@engine.rowing';
  static const String devAdminPassword = 'Dev#Admin@2026';

  static const String devCoachEmail = 'coach@engine.rowing';
  static const String devCoachPassword = 'Dev#Coach@2026';

  static const String devAthleteEmail = 'athlete@engine.rowing';
  static const String devAthletePassword = 'Dev#Athlete@2026';

  /// توليد قيمة Salt عشوائية مشفرة باستخدام Random.secure
  static String generateSalt([int length = 16]) {
    final random = Random.secure();
    final values = List<int>.generate(length, (_) => random.nextInt(256));
    return values.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// تشفير كلمة المرور بدمج الـ Salt مع كلمة السر وتطبيق SHA-256 بالمكتبة crypto
  static String hashPassword(String password, String salt) {
    final bytes = utf8.encode('$salt:$password');
    return sha256.convert(bytes).toString();
  }

  /// إنشاء مستخدم جديد مع توليد Salt عشوائي وتشفير كلمة السر
  static Future<int> registerUser({
    required String email,
    required String password,
    required String name,
    required String role,
    int? coachId,
    int? playerId,
    bool subscriptionActive = true,
  }) async {
    await ensureTables();
    final database = await DB.db;
    final salt = generateSalt();
    final hash = hashPassword(password, salt);

    return await database.insert('users', {
      'email': email.trim().toLowerCase(),
      'password_hash': hash,
      'salt': salt,
      'name': name.trim(),
      'role': role,
      'coach_id': coachId,
      'subscription_active': subscriptionActive ? 1 : 0,
      'player_id': playerId,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  /// إنشاء الجداول الخاصة بنظام المستخدمين والرسائل والمواعيد (CREATE TABLE IF NOT EXISTS)
  static Future<void> ensureTables() async {
    final database = await DB.db;

    // 1. جدول المستخدمين (مع عمود salt عشوائي و player_id)
    await database.execute('''
      CREATE TABLE IF NOT EXISTS users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        email TEXT NOT NULL UNIQUE,
        password_hash TEXT NOT NULL,
        salt TEXT NOT NULL,
        name TEXT NOT NULL,
        role TEXT NOT NULL DEFAULT 'athlete',
        coach_id INTEGER,
        subscription_active INTEGER DEFAULT 1,
        player_id INTEGER,
        created_at TEXT
      )
    ''');

    // ترقية آمنة لأي جدول سابق في حال نقص عمود salt أو player_id
    try {
      final columns = await database.rawQuery('PRAGMA table_info(users)');
      final columnNames = columns.map((c) => c['name'] as String).toSet();
      if (!columnNames.contains('salt')) {
        await database.execute("ALTER TABLE users ADD COLUMN salt TEXT DEFAULT ''");
      }
      if (!columnNames.contains('player_id')) {
        await database.execute("ALTER TABLE users ADD COLUMN player_id INTEGER");
      }
    } catch (_) {}

    // 2. جدول رسائل المدرب
    await database.execute('''
      CREATE TABLE IF NOT EXISTS coach_messages (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        athlete_id INTEGER NOT NULL,
        coach_id INTEGER NOT NULL,
        message TEXT NOT NULL,
        date TEXT NOT NULL,
        is_read INTEGER DEFAULT 0
      )
    ''');

    // 3. جدول مواعيد الاختبارات
    await database.execute('''
      CREATE TABLE IF NOT EXISTS testing_dates (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        coach_id INTEGER NOT NULL,
        test_name TEXT NOT NULL,
        test_date TEXT NOT NULL,
        created_at TEXT
      )
    ''');

    // 4. جدول مستلمي مواعيد الاختبارات
    await database.execute('''
      CREATE TABLE IF NOT EXISTS testing_date_recipients (
        testing_date_id INTEGER NOT NULL,
        athlete_id INTEGER NOT NULL,
        PRIMARY KEY (testing_date_id, athlete_id)
      )
    ''');
  }

  /// زرع المستخدمين الافتراضيين للتطوير والتجربة في وضع kDebugMode فقط.
  /// في وضع Release Mode، لا يتم زرع أي حساب إطلاقاً!
  static Future<void> seedInitialData() async {
    await ensureTables();

    // في وضع Release لا نزرع أي حساب نهائياً
    if (!kDebugMode) {
      return;
    }

    final database = await DB.db;

    // ============================================================================
    // تحذير أمني: الحسابات الـ 3 التالية مخصصة لبيئة التطوير والاختبار المحلي فقط (DEBUG ONLY)
    // - حساب الأدمن: admin@engine.rowing
    // - حساب المدرب: coach@engine.rowing
    // - حساب اللاعب: athlete@engine.rowing (مربوط بلاعب حقيقي في players وتابع للمدرب)
    // يجب إزالة هذه الحسابات التجريبية بالكامل قبل طرح التطبيق للإنتاج (Release).
    // ============================================================================

    // 1. حساب الأدمن التجريبي
    final adminRows = await database.rawQuery(
      "SELECT id, salt FROM users WHERE role = 'admin' LIMIT 1",
    );
    if (adminRows.isEmpty) {
      final salt = generateSalt();
      await database.insert('users', {
        'email': devAdminEmail,
        'password_hash': hashPassword(devAdminPassword, salt),
        'salt': salt,
        'name': 'System Admin (Dev)',
        'role': 'admin',
        'coach_id': null,
        'subscription_active': 1,
        'player_id': null,
        'created_at': DateTime.now().toIso8601String(),
      });
    }

    // 2. حساب المدرب التجريبي
    final coachRows = await database.rawQuery(
      "SELECT id, salt FROM users WHERE role = 'coach' LIMIT 1",
    );
    int coachId;
    if (coachRows.isEmpty) {
      final salt = generateSalt();
      coachId = await database.insert('users', {
        'email': devCoachEmail,
        'password_hash': hashPassword(devCoachPassword, salt),
        'salt': salt,
        'name': 'Coach Tamer (Dev)',
        'role': 'coach',
        'coach_id': null,
        'subscription_active': 1,
        'player_id': null,
        'created_at': DateTime.now().toIso8601String(),
      });
    } else {
      coachId = coachRows.first['id'] as int;
    }

    // 3. حساب اللاعب التجريبي (مربوط بلاعب في جدول players ومتبع للمدرب)
    final athleteRows = await database.rawQuery(
      "SELECT id, salt FROM users WHERE role = 'athlete' LIMIT 1",
    );
    if (athleteRows.isEmpty) {
      // التأكد من وجود لاعب في جدول players لربطه به
      final existingPlayers = await database.rawQuery('SELECT id, name FROM players LIMIT 1');
      int linkedPlayerId;
      String athleteName = 'Ziad (Dev)';

      if (existingPlayers.isNotEmpty) {
        linkedPlayerId = existingPlayers.first['id'] as int;
        athleteName = (existingPlayers.first['name'] as String?) ?? athleteName;
      } else {
        // إنشاء لاعب في جدول players لضمان اكتمال الربط
        linkedPlayerId = await database.insert('players', {
          'name': 'Ziad (Dev Player)',
          'mhr': 195,
          'active': 1,
        });
      }

      final salt = generateSalt();
      final athleteId = await database.insert('users', {
        'email': devAthleteEmail,
        'password_hash': hashPassword(devAthletePassword, salt),
        'salt': salt,
        'name': athleteName,
        'role': 'athlete',
        'coach_id': coachId, // متبع للمدرب
        'subscription_active': 1,
        'player_id': linkedPlayerId, // مربوط بلاعب موجود في جدول players
        'created_at': DateTime.now().toIso8601String(),
      });

      // زرع رسالة ترحيبية تجريبية من المدرب للاعب
      await database.insert('coach_messages', {
        'athlete_id': athleteId,
        'coach_id': coachId,
        'message': 'أهلاً بك في سيكل التدريب الجديد! ركّز اليوم على الإوقاع الثابت في الزون 2.',
        'date': DateTime.now().toIso8601String().substring(0, 10),
        'is_read': 0,
      });

      // زرع موعد اختبار قادم تجريبي
      final futureDate = DateTime.now().add(const Duration(days: 4));
      final testDateStr =
          '${futureDate.year}-${futureDate.month.toString().padLeft(2, '0')}-${futureDate.day.toString().padLeft(2, '0')}';
      final testId = await database.insert('testing_dates', {
        'coach_id': coachId,
        'test_name': '2000m Critical Power Erg Test',
        'test_date': testDateStr,
        'created_at': DateTime.now().toIso8601String(),
      });

      await database.insert('testing_date_recipients', {
        'testing_date_id': testId,
        'athlete_id': athleteId,
      });
    }
  }

  /// تسجيل الدخول والتحقق من كلمة السر والـ Salt والاشتراك
  static Future<LoginResult> login(String email, String password) async {
    await ensureTables();
    final cleanEmail = email.trim().toLowerCase();

    final database = await DB.db;
    final rows = await database.rawQuery(
      'SELECT * FROM users WHERE LOWER(email) = ?',
      [cleanEmail],
    );

    if (rows.isEmpty) {
      return const LoginResult.failure(LoginError.invalidCredentials);
    }

    final userMap = rows.first;
    final storedSalt = (userMap['salt'] as String?) ?? '';
    final storedHash = (userMap['password_hash'] as String?) ?? '';

    // التحقق بالـ salt المخزن للمستخدم
    final computedHash = hashPassword(password, storedSalt);
    if (storedHash.isEmpty || storedHash != computedHash) {
      return const LoginResult.failure(LoginError.invalidCredentials);
    }

    final user = AppUser.fromMap(userMap);

    // فحص اشتراك المستخدم نفسه
    if (!user.subscriptionActive) {
      return const LoginResult.failure(LoginError.accountInactive);
    }

    // إذا كان لاعباً تابعاً لمدرب، يتم فحص اشتراك المدرب
    if (user.isAthlete && user.coachId != null) {
      final coachRows = await database.rawQuery(
        'SELECT subscription_active FROM users WHERE id = ?',
        [user.coachId],
      );
      if (coachRows.isNotEmpty) {
        final coachActive = (coachRows.first['subscription_active'] as int? ?? 1) == 1;
        if (!coachActive) {
          return const LoginResult.failure(LoginError.coachSubscriptionInactive);
        }
      }
    }

    currentUser = user;
    return LoginResult.success(user);
  }


  /// حفظ بيانات الجلسة (تذكرني)
  static Future<void> saveSession(AppUser user, bool remember) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyRemember, remember);
    if (remember) {
      await prefs.setInt(_keyUserId, user.id);
      await prefs.setString(_keySavedEmail, user.email);
    } else {
      await prefs.remove(_keyUserId);
      await prefs.remove(_keySavedEmail);
    }
  }

  /// التحقق من وجود جلسة مسجلة محفوظة
  static Future<AppUser?> checkSavedSession() async {
    await ensureTables();
    final prefs = await SharedPreferences.getInstance();
    final remember = prefs.getBool(_keyRemember) ?? false;
    if (!remember) return null;

    final userId = prefs.getInt(_keyUserId);
    if (userId == null) return null;

    final database = await DB.db;
    final rows = await database.rawQuery('SELECT * FROM users WHERE id = ?', [userId]);
    if (rows.isEmpty) return null;

    final user = AppUser.fromMap(rows.first);
    if (!user.subscriptionActive) return null;

    if (user.isAthlete && user.coachId != null) {
      final coachRows = await database.rawQuery(
        'SELECT subscription_active FROM users WHERE id = ?',
        [user.coachId],
      );
      if (coachRows.isNotEmpty) {
        final coachActive = (coachRows.first['subscription_active'] as int? ?? 1) == 1;
        if (!coachActive) return null;
      }
    }

    currentUser = user;
    return user;
  }

  /// جلب الإيميل المحفوظ للتعبئة التلقائية
  static Future<String?> getSavedEmail() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keySavedEmail);
  }

  /// تسجيل الخروج ومسح الجلسة
  static Future<void> logout() async {
    currentUser = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyUserId);
    // نترك _keySavedEmail لو تذكرني كان مفعل أو نمسحه مع الجلسة
  }

  /// تحديد فترة التحية حسب الساعة:
  /// - قبل 12:00 -> 'morning'
  /// - من 12:00 إلى 16:59 -> 'afternoon'
  /// - من 17:00 فما بعد -> 'evening'
  static String getGreetingPeriod([DateTime? time]) {
    final hour = (time ?? DateTime.now()).hour;
    if (hour < 12) {
      return 'morning';
    } else if (hour < 17) {
      return 'afternoon';
    } else {
      return 'evening';
    }
  }
}

/// أخطاء تسجيل الدخول
enum LoginError {
  invalidCredentials,
  accountInactive,
  coachSubscriptionInactive,
}

/// نتيجة محاولة تسجيل الدخول
class LoginResult {
  final bool isSuccess;
  final AppUser? user;
  final LoginError? error;

  const LoginResult.success(this.user)
      : isSuccess = true,
        error = null;

  const LoginResult.failure(this.error)
      : isSuccess = false,
        user = null;
}
