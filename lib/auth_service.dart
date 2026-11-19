import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'db.dart';
import 'cloud_api.dart';
import 'cloud_config.dart';

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
  final String? photoPath;

  const AppUser({
    required this.id,
    required this.email,
    required this.name,
    required this.role,
    this.coachId,
    required this.subscriptionActive,
    this.playerId,
    this.createdAt,
    this.photoPath,
  });

  bool get isAdmin => role == 'admin';
  bool get isCoach => role == 'coach';
  bool get isAthlete => role == 'athlete';

  AppUser copyWith({
    int? id,
    String? email,
    String? name,
    String? role,
    int? coachId,
    bool? subscriptionActive,
    int? playerId,
    String? createdAt,
    String? photoPath,
  }) {
    return AppUser(
      id: id ?? this.id,
      email: email ?? this.email,
      name: name ?? this.name,
      role: role ?? this.role,
      coachId: coachId ?? this.coachId,
      subscriptionActive: subscriptionActive ?? this.subscriptionActive,
      playerId: playerId ?? this.playerId,
      createdAt: createdAt ?? this.createdAt,
      photoPath: photoPath ?? this.photoPath,
    );
  }

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
      photoPath: map['photo_path'] as String?,
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
      'photo_path': photoPath,
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
  static const String devAdminEmail = 'admin.mabdelhalimdawod@engine.rowing';
  static const String devAdminPassword = 'mahmoud@76Mm';

  static const String devCoachEmail = 'mabdelhalimdawod@engine.rowing';
  static const String devCoachPassword = 'mahmoud@76Mm';

  static const String devAthleteEmail =
      'athlete.mabdelhalimdawod@engine.rowing';
  static const String devAthletePassword = 'mahmoud@76Mm';

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

  /// التحقق مما إذا كان البريد الإلكتروني مسجلاً مسبقاً
  static Future<bool> isEmailRegistered(String email) async {
    await ensureTables();
    final database = await DB.db;
    final rows = await database.rawQuery(
      'SELECT id FROM users WHERE LOWER(email) = ?',
      [email.trim().toLowerCase()],
    );
    return rows.isNotEmpty;
  }

  /// تفعيل حساب مستخدم (للأدمن أو بعد تأكيد الدفع الكاش)
  static Future<bool> activateUser(int userId) async {
    await ensureTables();
    final database = await DB.db;
    final count = await database.update(
      'users',
      {'subscription_active': 1},
      where: 'id = ?',
      whereArgs: [userId],
    );
    return count > 0;
  }

  /// إنشاء مستخدم جديد مع التحقق السحابي والمزامنة المحلية كمرآة للـ profile
  static Future<int> registerUser({
    required String email,
    required String password,
    required String name,
    required String role,
    int? coachId,
    int? playerId,
    bool subscriptionActive = false,
  }) async {
    final cleanRole = role.trim().toLowerCase();
    if (cleanRole == 'admin') {
      throw ArgumentError('غير مسموح بالتسجيل بدور مسؤول');
    }

    await ensureTables();

    // 1. محاولة التسجيل في السحابة إذا كانت مهيأة أو في الاختبارات
    if (CloudConfig.isConfigured || CloudApi.instance is MockCloudApi) {
      final cloudRes = await CloudApi.instance.signUp(
        email: email,
        password: password,
        name: name,
        role: cleanRole,
      );
      if (!cloudRes.isSuccess && cloudRes.errorCode != null) {
        if (cloudRes.errorCode == CloudAuthErrorCode.adminRoleForbidden) {
          throw ArgumentError('غير مسموح بالتسجيل بدور مسؤول');
        } else if (cloudRes.errorCode == CloudAuthErrorCode.emailAlreadyInUse) {
          throw Exception('البريد الإلكتروني مسجل مسبقاً');
        }
      }
    }

    final database = await DB.db;
    final salt = generateSalt();
    final hash = hashPassword(password, salt);

    // 2. إدخال/مزامنة صف المستخدم محلياً كمرآة للـ profile
    return await database.insert(
        'users',
        {
          'email': email.trim().toLowerCase(),
          'password_hash': hash,
          'salt': salt,
          'name': name.trim(),
          'role': cleanRole,
          'coach_id': coachId,
          'subscription_active': subscriptionActive ? 1 : 0,
          'player_id': playerId,
          'created_at': DateTime.now().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// إنشاء الجداول الخاصة بنظام المستخدمين والرسائل والمواعيد (CREATE TABLE IF NOT EXISTS)
  static Future<void> ensureTables() async {
    final database = await DB.db;

    // 1. جدول المستخدمين (مع عمود salt عشوائي و player_id و photo_path)
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
        photo_path TEXT,
        created_at TEXT
      )
    ''');

    // ترقية آمنة لأي جدول سابق في حال نقص عمود salt أو player_id أو photo_path
    try {
      final columns = await database.rawQuery('PRAGMA table_info(users)');
      final columnNames = columns.map((c) => c['name'] as String).toSet();
      if (!columnNames.contains('salt')) {
        await database
            .execute("ALTER TABLE users ADD COLUMN salt TEXT DEFAULT ''");
      }
      if (!columnNames.contains('player_id')) {
        await database
            .execute("ALTER TABLE users ADD COLUMN player_id INTEGER");
      }
      if (!columnNames.contains('photo_path')) {
        await database.execute("ALTER TABLE users ADD COLUMN photo_path TEXT");
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

  /// زرع وتحديث حسابات المستخدمين الثلاثة المعتمدة (الأدمن، المدرب، اللاعب)
  static Future<void> seedInitialData() async {
    await ensureTables();
    final database = await DB.db;

    // 1. حساب الأدمن
    final adminSalt = generateSalt();
    final adminHash = hashPassword(devAdminPassword, adminSalt);
    final adminRows = await database.rawQuery(
      "SELECT id FROM users WHERE role = 'admin' LIMIT 1",
    );
    if (adminRows.isEmpty) {
      await database.insert('users', {
        'email': devAdminEmail,
        'password_hash': adminHash,
        'salt': adminSalt,
        'name': 'محمود عبد الحليم (الأدمن)',
        'role': 'admin',
        'coach_id': null,
        'subscription_active': 1,
        'player_id': null,
        'created_at': DateTime.now().toIso8601String(),
      });
    } else {
      final adminId = adminRows.first['id'] as int;
      await database.update(
          'users',
          {
            'email': devAdminEmail,
            'password_hash': adminHash,
            'salt': adminSalt,
            'name': 'محمود عبد الحليم (الأدمن)',
            'subscription_active': 1,
          },
          where: 'id = ?',
          whereArgs: [adminId]);
    }

    // 2. حساب المدرب (الأساسي بـ mabdelhalimdawod@engine.rowing)
    int coachId;
    final coachSalt = generateSalt();
    final coachHash = hashPassword(devCoachPassword, coachSalt);
    final coachRows = await database.rawQuery(
      "SELECT id FROM users WHERE role = 'coach' LIMIT 1",
    );
    if (coachRows.isEmpty) {
      coachId = await database.insert('users', {
        'email': devCoachEmail,
        'password_hash': coachHash,
        'salt': coachSalt,
        'name': 'كابتن محمود عبد الحليم',
        'role': 'coach',
        'coach_id': null,
        'subscription_active': 1,
        'player_id': null,
        'created_at': DateTime.now().toIso8601String(),
      });
    } else {
      coachId = coachRows.first['id'] as int;
      await database.update(
          'users',
          {
            'email': devCoachEmail,
            'password_hash': coachHash,
            'salt': coachSalt,
            'name': 'كابتن محمود عبد الحليم',
            'subscription_active': 1,
          },
          where: 'id = ?',
          whereArgs: [coachId]);
    }

    // 3. حساب اللاعب (مربوط بالمدرب)
    final athleteSalt = generateSalt();
    final athleteHash = hashPassword(devAthletePassword, athleteSalt);
    final athleteRows = await database.rawQuery(
      "SELECT id FROM users WHERE role = 'athlete' LIMIT 1",
    );
    if (athleteRows.isEmpty) {
      final existingPlayers =
          await database.rawQuery('SELECT id, name FROM players LIMIT 1');
      int linkedPlayerId;
      String athleteName = 'محمود عبد الحليم (لاعب)';

      if (existingPlayers.isNotEmpty) {
        linkedPlayerId = existingPlayers.first['id'] as int;
      } else {
        linkedPlayerId = await database.insert('players', {
          'name': 'محمود عبد الحليم (لاعب)',
          'mhr': 195,
          'active': 1,
        });
      }

      final athleteId = await database.insert('users', {
        'email': devAthleteEmail,
        'password_hash': athleteHash,
        'salt': athleteSalt,
        'name': athleteName,
        'role': 'athlete',
        'coach_id': coachId,
        'subscription_active': 1,
        'player_id': linkedPlayerId,
        'created_at': DateTime.now().toIso8601String(),
      });

      // زرع رسالة ترحيبية من المدرب للاعب
      await database.insert('coach_messages', {
        'athlete_id': athleteId,
        'coach_id': coachId,
        'message':
            'أهلاً بك في الدورة التدريبية الجديدة! ركّز اليوم على الإيقاع الثابت في المنطقة 2.',
        'date': DateTime.now().toIso8601String().substring(0, 10),
        'is_read': 0,
      });
    } else {
      final athleteId = athleteRows.first['id'] as int;
      await database.update(
          'users',
          {
            'email': devAthleteEmail,
            'password_hash': athleteHash,
            'salt': athleteSalt,
            'subscription_active': 1,
          },
          where: 'id = ?',
          whereArgs: [athleteId]);
    }
  }

  /// تسجيل الدخول عبر السحابة مع المزامنة المحلية للحساب والعمل أوفلاين
  static Future<LoginResult> login(String email, String password,
      [String? role]) async {
    await ensureTables();
    final cleanEmail = email.trim().toLowerCase();

    // 1. محاولة تسجيل الدخول عبر السحابة (أو المحاكي الوهمي في الاختبارات)
    if (CloudConfig.isConfigured || (CloudApi.instance is MockCloudApi)) {
      final cloudRes = await CloudApi.instance.signIn(
        email: cleanEmail,
        password: password,
      );

      if (cloudRes.isSuccess && cloudRes.profile != null) {
        final profile = cloudRes.profile!;
        final database = await DB.db;

        // مزامنة و Upsert في جدول users المحلي كمرآة للـ profile
        final existing = await database.rawQuery(
          'SELECT * FROM users WHERE LOWER(email) = ?',
          [cleanEmail],
        );

        int localId;
        if (existing.isNotEmpty) {
          localId = existing.first['id'] as int;
          await database.update(
              'users',
              {
                'name': profile.name,
                'role': profile.role,
                'subscription_active': profile.subscriptionActive ? 1 : 0,
                'photo_path': profile.photoPath,
              },
              where: 'id = ?',
              whereArgs: [localId]);
        } else {
          localId = await database.insert('users', {
            'email': cleanEmail,
            'password_hash': '',
            'salt': '',
            'name': profile.name,
            'role': profile.role,
            'coach_id': null,
            'subscription_active': profile.subscriptionActive ? 1 : 0,
            'player_id': profile.playerId,
            'photo_path': profile.photoPath,
            'created_at': DateTime.now().toIso8601String(),
          });
        }

        final updatedRows = await database
            .rawQuery('SELECT * FROM users WHERE id = ?', [localId]);
        final user = AppUser.fromMap(updatedRows.first);
        currentUser = user;
        return LoginResult.success(user);
      } else if (cloudRes.errorCode == CloudAuthErrorCode.accountInactive) {
        return const LoginResult.failure(LoginError.accountInactive);
      }
    }

    // 2. التحقق من الحسابات المحلية في SQLite (الوضع المحلي / Offline / الحسابات التجريبية)
    final database = await DB.db;

    List<Map<String, Object?>> rows = [];

    // إذا كان الإيميل المدخل mabdelhalimdawod@engine.rowing
    if (cleanEmail == 'mabdelhalimdawod@engine.rowing') {
      if (role == 'admin') {
        rows = await database.rawQuery(
          "SELECT * FROM users WHERE (LOWER(email) = ? OR LOWER(email) = ?) AND role = 'admin' LIMIT 1",
          [cleanEmail, devAdminEmail.toLowerCase()],
        );
      } else if (role == 'athlete') {
        rows = await database.rawQuery(
          "SELECT * FROM users WHERE (LOWER(email) = ? OR LOWER(email) = ?) AND role = 'athlete' LIMIT 1",
          [cleanEmail, devAthleteEmail.toLowerCase()],
        );
      } else {
        // افتراضياً دور المدرب
        rows = await database.rawQuery(
          "SELECT * FROM users WHERE (LOWER(email) = ? OR LOWER(email) = ?) AND role = 'coach' LIMIT 1",
          [cleanEmail, devCoachEmail.toLowerCase()],
        );
        if (rows.isEmpty) {
          rows = await database.rawQuery(
            'SELECT * FROM users WHERE LOWER(email) = ? LIMIT 1',
            [cleanEmail],
          );
        }
      }
    } else {
      rows = await database.rawQuery(
        'SELECT * FROM users WHERE LOWER(email) = ?',
        [cleanEmail],
      );
    }

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

    // فحص اشتراك وتفعيل المستخدم نفسه
    if (!user.subscriptionActive) {
      return const LoginResult.failure(LoginError.awaitingActivation);
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
    final rows =
        await database.rawQuery('SELECT * FROM users WHERE id = ?', [userId]);
    if (rows.isEmpty) return null;

    final user = AppUser.fromMap(rows.first);
    if (!user.subscriptionActive) return null;

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
    try {
      await CloudApi.instance.signOut();
    } catch (_) {}
  }

  /// تحديث صورة الملف الشخصي للمستخدم وحفظها في مجلد المستندات
  /// شرط أمان صارم: كل مستخدم يغير صورته هو فقط (actingUserId == targetUserId)
  static Future<String?> updateUserPhoto({
    required int targetUserId,
    required int actingUserId,
    required String sourcePath,
  }) async {
    if (targetUserId != actingUserId) {
      throw Exception(
          'Unauthorized: Users can only update their own profile photo');
    }

    final database = await DB.db;

    // استعلام عن المسار القديم لحذفه
    final currentRows = await database.query(
      'users',
      columns: ['photo_path'],
      where: 'id = ?',
      whereArgs: [targetUserId],
    );
    if (currentRows.isNotEmpty) {
      final oldPath = currentRows.first['photo_path'] as String?;
      if (oldPath != null && oldPath.isNotEmpty) {
        try {
          final oldFile = File(oldPath);
          if (oldFile.existsSync()) {
            oldFile.deleteSync();
          }
        } catch (_) {}
      }
    }

    // حفظ الملف الجديد في مجلد المستندات
    final docsDir = await getApplicationDocumentsDirectory();
    final photosDir = Directory(p.join(docsDir.path, 'profile_photos'));
    if (!photosDir.existsSync()) {
      photosDir.createSync(recursive: true);
    }

    final ext =
        p.extension(sourcePath).isEmpty ? '.jpg' : p.extension(sourcePath);
    final fileName =
        'user_${targetUserId}_${DateTime.now().millisecondsSinceEpoch}$ext';
    final targetFile = File(p.join(photosDir.path, fileName));

    final sourceFile = File(sourcePath);
    if (sourceFile.existsSync()) {
      await sourceFile.copy(targetFile.path);
    } else {
      await targetFile.writeAsString('photo_data');
    }

    final newPath = targetFile.path;
    await database.update(
      'users',
      {'photo_path': newPath},
      where: 'id = ?',
      whereArgs: [targetUserId],
    );

    // رفع الصورة إلى باكت avatars في السحابة
    try {
      if (targetFile.existsSync()) {
        final bytes = await targetFile.readAsBytes();
        await CloudApi.instance.uploadAvatar(
          userId: targetUserId.toString(),
          bytes: bytes,
        );
      }
    } catch (_) {}

    if (currentUser != null && currentUser!.id == targetUserId) {
      currentUser = currentUser!.copyWith(photoPath: newPath);
    }

    return newPath;
  }

  /// تنزيل صورة المستخدم من باكت avatars وتخزينها محلياً إن وجدت
  static Future<String?> ensureAvatarDownloaded(int userId) async {
    try {
      final docsDir = await getApplicationDocumentsDirectory();
      final localPath = p.join(docsDir.path, 'profile_photos', 'avatar_$userId.jpg');
      final localFile = File(localPath);
      if (localFile.existsSync()) return localPath;

      final bytes = await CloudApi.instance.downloadAvatar(userId.toString());
      if (bytes != null && bytes.isNotEmpty) {
        if (!localFile.parent.existsSync()) {
          localFile.parent.createSync(recursive: true);
        }
        await localFile.writeAsBytes(bytes);
        return localPath;
      }
    } catch (_) {}
    return null;
  }

  /// حذف صورة الملف الشخصي
  static Future<void> deleteUserPhoto({
    required int targetUserId,
    required int actingUserId,
  }) async {
    if (targetUserId != actingUserId) {
      throw Exception(
          'Unauthorized: Users can only delete their own profile photo');
    }

    final database = await DB.db;
    final currentRows = await database.query(
      'users',
      columns: ['photo_path'],
      where: 'id = ?',
      whereArgs: [targetUserId],
    );
    if (currentRows.isNotEmpty) {
      final oldPath = currentRows.first['photo_path'] as String?;
      if (oldPath != null && oldPath.isNotEmpty) {
        try {
          final oldFile = File(oldPath);
          if (oldFile.existsSync()) {
            oldFile.deleteSync();
          }
        } catch (_) {}
      }
    }

    await database.update(
      'users',
      {'photo_path': null},
      where: 'id = ?',
      whereArgs: [targetUserId],
    );

    if (currentUser != null && currentUser!.id == targetUserId) {
      currentUser = currentUser!.copyWith(photoPath: null);
    }
  }

  /// جلب مسار صورة لاعب بناءً على player_id
  static Future<String?> getPhotoPathForPlayer(int playerId) async {
    try {
      final database = await DB.db;
      final rows = await database.query(
        'users',
        columns: ['photo_path'],
        where: 'player_id = ?',
        whereArgs: [playerId],
        limit: 1,
      );
      if (rows.isNotEmpty) {
        return rows.first['photo_path'] as String?;
      }
    } catch (_) {}
    return null;
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
  awaitingActivation,
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
