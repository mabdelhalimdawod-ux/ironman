import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'cloud_config.dart';

/// كود خطأ المصادقة السحابية
enum CloudAuthErrorCode {
  invalidCredentials,
  accountInactive,
  adminRoleForbidden,
  emailAlreadyInUse,
  networkError,
  unknown,
}

/// ملف المستخدم السحابي (Cloud Profile)
class CloudUserProfile {
  final String id; // UUID
  final String email;
  final String name;
  final String role; // 'athlete' | 'coach' | 'admin'
  final String? coachId;
  final int? playerId;
  final String? photoPath;
  final String timezone;
  final bool subscriptionActive;

  const CloudUserProfile({
    required this.id,
    required this.email,
    required this.name,
    required this.role,
    this.coachId,
    this.playerId,
    this.photoPath,
    this.timezone = 'Africa/Cairo',
    required this.subscriptionActive,
  });

  bool get isAdmin => role == 'admin';
  bool get isCoach => role == 'coach';
  bool get isAthlete => role == 'athlete';

  factory CloudUserProfile.fromMap(Map<String, dynamic> map, {bool subscriptionActive = false}) {
    return CloudUserProfile(
      id: map['id']?.toString() ?? '',
      email: map['email']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
      role: map['role']?.toString() ?? 'athlete',
      coachId: map['coach_id']?.toString(),
      playerId: (map['player_id'] as num?)?.toInt(),
      photoPath: map['photo_path']?.toString(),
      timezone: map['timezone']?.toString() ?? 'Africa/Cairo',
      subscriptionActive: subscriptionActive,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'email': email,
        'name': name,
        'role': role,
        'coach_id': coachId,
        'player_id': playerId,
        'photo_path': photoPath,
        'timezone': timezone,
        'subscription_active': subscriptionActive ? 1 : 0,
      };
}

/// نتيجة عملية المصادقة
class CloudAuthResult {
  final bool isSuccess;
  final CloudUserProfile? profile;
  final CloudAuthErrorCode? errorCode;
  final String? errorMessage;

  const CloudAuthResult.success(this.profile)
      : isSuccess = true,
        errorCode = null,
        errorMessage = null;

  const CloudAuthResult.failure(this.errorCode, [this.errorMessage])
      : isSuccess = false,
        profile = null;
}

/// واجهة الاتصال بالسحابة (CloudApi Interface)
abstract class CloudApi {
  static CloudApi? _instance;

  static CloudApi get instance {
    _instance ??= _createDefaultInstance();
    return _instance!;
  }

  static set instance(CloudApi api) {
    _instance = api;
  }

  static CloudApi _createDefaultInstance() {
    if (CloudConfig.isConfigured) {
      return SupabaseCloudApi();
    }
    return MockCloudApi();
  }

  /// هل خدمة السحابة متوفرة ومضبوطة
  bool get isAvailable;

  /// تهيئة الاتصال بالسحابة (إن لزم)
  Future<void> initialize();

  /// إنشاء حساب جديد
  Future<CloudAuthResult> signUp({
    required String email,
    required String password,
    required String name,
    required String role,
  });

  /// تسجيل الدخول
  Future<CloudAuthResult> signIn({
    required String email,
    required String password,
  });

  /// تسجيل الخروج
  Future<void> signOut();

  /// جلب الملف الشخصي للمستخدم الحالي
  Future<CloudUserProfile?> getCurrentProfile();

  /// التحقق من حالة تفعيل الاشتراك
  Future<bool> isSubscriptionActive(String userId);

  /// رفع دفعة من السجلات إلى جدول في السحابة
  Future<List<Map<String, dynamic>>> pushBatch(
    String table,
    List<Map<String, dynamic>> records, {
    String? userRole,
    String? userId,
  });

  /// سحب التحديثات من جدول في السحابة منذ تاريخ محدد
  Future<List<Map<String, dynamic>>> pullBatch(
    String table, {
    String? since,
    String? userRole,
    String? userId,
    String? coachId,
  });

  /// تسجيل حذف ناعم في السحابة لمجموعة سجلات
  Future<void> softDeleteBatch(
    String table,
    List<String> remoteIds,
  );
}

/// التنفيذ الحقيقي لخدمة السحابة عبر Supabase
class SupabaseCloudApi implements CloudApi {
  bool _initialized = false;
  SupabaseClient? _client;

  @override
  bool get isAvailable => CloudConfig.isConfigured;

  SupabaseClient get client {
    if (_client != null) return _client!;
    if (!_initialized) {
      throw StateError('SupabaseCloudApi must be initialized before use.');
    }
    return Supabase.instance.client;
  }

  @override
  Future<void> initialize() async {
    if (_initialized) return;
    if (!isAvailable) return;

    try {
      await Supabase.initialize(
        url: CloudConfig.url,
        // ignore: deprecated_member_use
        anonKey: CloudConfig.anonKey,
      );
      _client = Supabase.instance.client;
      _initialized = true;
    } catch (_) {
      // إذا كان مهيأ مسبقاً في مكان آخر
      try {
        _client = Supabase.instance.client;
        _initialized = true;
      } catch (_) {}
    }
  }

  @override
  Future<CloudAuthResult> signUp({
    required String email,
    required String password,
    required String name,
    required String role,
  }) async {
    final cleanRole = role.trim().toLowerCase();

    // منع التسجيل بدور مسؤول نهائياً
    if (cleanRole == 'admin') {
      return const CloudAuthResult.failure(
        CloudAuthErrorCode.adminRoleForbidden,
        'غير مسموح بالتسجيل كمسؤول أثناء إنشاء الحساب',
      );
    }

    try {
      await initialize();
      final res = await client.auth.signUp(
        email: email.trim().toLowerCase(),
        password: password,
        data: {
          'name': name.trim(),
          'role': cleanRole,
        },
      );

      final user = res.user;
      if (user == null) {
        return const CloudAuthResult.failure(
          CloudAuthErrorCode.unknown,
          'فشل إنشاء الحساب بالسحابة',
        );
      }

      // بعد التسجيل، الحساب يكون في انتظار التفعيل (subscriptionActive = false)
      final profile = CloudUserProfile(
        id: user.id,
        email: user.email ?? email,
        name: name.trim(),
        role: cleanRole,
        subscriptionActive: false,
      );

      return CloudAuthResult.success(profile);
    } on AuthException catch (e) {
      if (e.message.toLowerCase().contains('already registered') ||
          e.message.toLowerCase().contains('unique')) {
        return const CloudAuthResult.failure(
          CloudAuthErrorCode.emailAlreadyInUse,
          'البريد الإلكتروني مسجل مسبقاً',
        );
      }
      return CloudAuthResult.failure(CloudAuthErrorCode.unknown, e.message);
    } catch (e) {
      return CloudAuthResult.failure(CloudAuthErrorCode.networkError, e.toString());
    }
  }

  @override
  Future<CloudAuthResult> signIn({
    required String email,
    required String password,
  }) async {
    try {
      await initialize();
      final res = await client.auth.signInWithPassword(
        email: email.trim().toLowerCase(),
        password: password,
      );

      final user = res.user;
      if (user == null) {
        return const CloudAuthResult.failure(
          CloudAuthErrorCode.invalidCredentials,
          'بيانات الدخول غير صحيحة',
        );
      }

      // جلب الملف الشخصي وحالة الاشتراك
      final profile = await getCurrentProfile();
      if (profile == null) {
        return const CloudAuthResult.failure(
          CloudAuthErrorCode.unknown,
          'لم يتم العثور على الملف الشخصي',
        );
      }

      // فحص تفعيل الاشتراك (RLS / Server validation)
      if (!profile.subscriptionActive) {
        // تسجيل الخروج لتأكيد عدم فتح الجلسة للحساب غير المفعل
        await client.auth.signOut();
        return const CloudAuthResult.failure(
          CloudAuthErrorCode.accountInactive,
          'حسابك غير مفعّل حاليًا، تواصل مع الإدارة',
        );
      }

      return CloudAuthResult.success(profile);
    } on AuthException catch (e) {
      return CloudAuthResult.failure(
        CloudAuthErrorCode.invalidCredentials,
        e.message,
      );
    } catch (e) {
      return CloudAuthResult.failure(CloudAuthErrorCode.networkError, e.toString());
    }
  }

  @override
  Future<void> signOut() async {
    try {
      await client.auth.signOut();
    } catch (_) {}
  }

  @override
  Future<CloudUserProfile?> getCurrentProfile() async {
    try {
      final user = client.auth.currentUser;
      if (user == null) return null;

      final pRows = await client
          .from('profiles')
          .select()
          .eq('id', user.id)
          .maybeSingle();

      if (pRows == null) return null;

      final sRows = await client
          .from('subscriptions')
          .select('active')
          .eq('user_id', user.id)
          .maybeSingle();

      final isActive = (sRows != null && sRows['active'] == true);

      return CloudUserProfile.fromMap(pRows, subscriptionActive: isActive);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<bool> isSubscriptionActive(String userId) async {
    try {
      final s = await client
          .from('subscriptions')
          .select('active')
          .eq('user_id', userId)
          .maybeSingle();
      return s != null && s['active'] == true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<List<Map<String, dynamic>>> pushBatch(
    String table,
    List<Map<String, dynamic>> records, {
    String? userRole,
    String? userId,
  }) async {
    try {
      final res = await client.from(table).upsert(records).select();
      return List<Map<String, dynamic>>.from(res);
    } on PostgrestException catch (e) {
      if (e.message.contains('مقفولة تلقائياً') || e.message.contains('locked')) {
        throw ServerLockException(e.message);
      }
      rethrow;
    }
  }

  @override
  Future<List<Map<String, dynamic>>> pullBatch(
    String table, {
    String? since,
    String? userRole,
    String? userId,
    String? coachId,
  }) async {
    var query = client.from(table).select();
    if (since != null && since.isNotEmpty) {
      query = query.gt('updated_at', since);
    }
    final res = await query;
    return List<Map<String, dynamic>>.from(res);
  }

  @override
  Future<void> softDeleteBatch(
    String table,
    List<String> remoteIds,
  ) async {
    if (remoteIds.isEmpty) return;
    await client.from(table).update({
      'deleted_at': DateTime.now().toUtc().toIso8601String(),
    }).inFilter('id', remoteIds);
  }
}

/// استثناء رفض الخادم لتعديل حصة مقفولة
class ServerLockException implements Exception {
  final String message;
  const ServerLockException(this.message);

  @override
  String toString() => message;
}

/// التنفيذ الوهمي في الذاكرة (In-Memory Mock) للاختبارات والوضع المحلي
class MockCloudApi implements CloudApi {
  final Map<String, _MockUserEntry> _users = {};
  final Map<String, Map<String, Map<String, dynamic>>> _cloudTables = {};
  String? _currentUserId;

  @override
  bool get isAvailable => true;

  @override
  Future<void> initialize() async {}

  /// الحصول على بيانات جدول سحابي وهمي مباشرة للاختبارات
  Map<String, Map<String, dynamic>> getCloudTable(String table) {
    return _cloudTables.putIfAbsent(table, () => {});
  }

  @override
  Future<List<Map<String, dynamic>>> pushBatch(
    String table,
    List<Map<String, dynamic>> records, {
    String? userRole,
    String? userId,
  }) async {
    final tableMap = _cloudTables.putIfAbsent(table, () => {});
    final results = <Map<String, dynamic>>[];
    final todayStr = DateTime.now().toUtc().toIso8601String().substring(0, 10);

    for (final raw in records) {
      final rec = Map<String, dynamic>.from(raw);

      // التحقق من قفل الحصص على السيرفر للاعب
      if (table == 'logs' && userRole == 'athlete') {
        final sessionDate = rec['date'] as String? ?? '';
        if (sessionDate.isNotEmpty && sessionDate.compareTo(todayStr) < 0) {
          throw const ServerLockException(
              'هذه الحصة مقفولة تلقائياً بعد منتصف الليل (12:00 AM). يرجى مراجعة المدرب.');
        }
      }

      String id = rec['id']?.toString() ?? rec['remote_id']?.toString() ?? '';
      if (id.isEmpty) {
        id = 'mock-id-${table}-${tableMap.length + 1}-${DateTime.now().microsecondsSinceEpoch}';
        rec['id'] = id;
      }
      rec['remote_id'] = id;
      rec['updated_at'] ??= DateTime.now().toUtc().toIso8601String();
      if (userRole == 'athlete' && userId != null) {
        rec['athlete_user_id'] ??= userId;
      }
      if (userRole == 'coach' && userId != null) {
        rec['coach_id'] ??= userId;
      }

      tableMap[id] = rec;
      results.add(rec);
    }

    return results;
  }

  @override
  Future<List<Map<String, dynamic>>> pullBatch(
    String table, {
    String? since,
    String? userRole,
    String? userId,
    String? coachId,
  }) async {
    final tableMap = _cloudTables.putIfAbsent(table, () => {});
    final list = <Map<String, dynamic>>[];

    for (final rec in tableMap.values) {
      // فلترة التوقيت
      if (since != null && since.isNotEmpty) {
        final updatedAt = rec['updated_at'] as String? ?? '';
        if (updatedAt.isNotEmpty && updatedAt.compareTo(since) <= 0) {
          continue;
        }
      }

      // فلترة صلاحيات الدور RLS
      if (userRole == 'athlete' && userId != null) {
        // اللاعب يقرأ بياناته أو بيانات مدربه
        if (table == 'logs' ||
            table == 'athlete_custom_sessions' ||
            table == 'athlete_custom_workout_items' ||
            table == 'cp_tests' ||
            table == 'cp_values') {
          final authorId = rec['athlete_user_id']?.toString() ??
              rec['user_id']?.toString() ??
              rec['player_id']?.toString();
          if (authorId != null && authorId != userId) {
            continue; // لا يسحب سجلات لاعب آخر
          }
        } else if (table == 'program_cycles' ||
            table == 'program_sessions' ||
            table == 'program_workout_items' ||
            table == 'cycle_templates' ||
            table == 'sessions' ||
            table == 'notes') {
          final cId = rec['coach_id']?.toString();
          if (coachId != null && cId != null && cId != coachId) {
            continue;
          }
        }
      } else if (userRole == 'coach' && userId != null) {
        // المدرب يسحب كل ما يخصه ويخص لاعبيه
        final cId = rec['coach_id']?.toString();
        if (cId != null && cId != userId) {
          continue;
        }
      }

      list.add(Map<String, dynamic>.from(rec));
    }

    return list;
  }

  @override
  Future<void> softDeleteBatch(
    String table,
    List<String> remoteIds,
  ) async {
    final tableMap = _cloudTables.putIfAbsent(table, () => {});
    final nowStr = DateTime.now().toUtc().toIso8601String();
    for (final id in remoteIds) {
      var rec = tableMap[id];
      if (rec == null) {
        rec = tableMap.values.cast<Map<String, dynamic>?>().firstWhere(
              (r) => r?['remote_id'] == id,
              orElse: () => null,
            );
      }
      if (rec != null) {
        rec['deleted_at'] = nowStr;
        rec['updated_at'] = nowStr;
      }
    }
  }

  /// إضافة أو تحديث مستخدم في الذاكرة لأغراض الاختبار
  void seedUser({
    required String id,
    required String email,
    required String password,
    required String name,
    required String role,
    bool subscriptionActive = true,
    String? coachId,
    int? playerId,
  }) {
    _users[email.toLowerCase()] = _MockUserEntry(
      id: id,
      email: email.toLowerCase(),
      password: password,
      name: name,
      role: role,
      subscriptionActive: subscriptionActive,
      coachId: coachId,
      playerId: playerId,
    );
  }

  @override
  Future<CloudAuthResult> signUp({
    required String email,
    required String password,
    required String name,
    required String role,
  }) async {
    final cleanRole = role.trim().toLowerCase();
    final cleanEmail = email.trim().toLowerCase();

    // رفض تسجيل دور المسؤول صراحة
    if (cleanRole == 'admin') {
      return const CloudAuthResult.failure(
        CloudAuthErrorCode.adminRoleForbidden,
        'غير مسموح بالتسجيل بدور مسؤول',
      );
    }

    if (_users.containsKey(cleanEmail)) {
      return const CloudAuthResult.failure(
        CloudAuthErrorCode.emailAlreadyInUse,
        'البريد الإلكتروني مسجل مسبقاً',
      );
    }

    final newId = 'mock-${DateTime.now().millisecondsSinceEpoch}';
    final entry = _MockUserEntry(
      id: newId,
      email: cleanEmail,
      password: password,
      name: name.trim(),
      role: cleanRole,
      subscriptionActive: false, // دائماً غير مفعّل عند التسجيل
    );
    _users[cleanEmail] = entry;

    return CloudAuthResult.success(entry.toProfile());
  }

  @override
  Future<CloudAuthResult> signIn({
    required String email,
    required String password,
  }) async {
    final cleanEmail = email.trim().toLowerCase();
    final user = _users[cleanEmail];

    if (user == null || user.password != password) {
      return const CloudAuthResult.failure(
        CloudAuthErrorCode.invalidCredentials,
        'بيانات الدخول غير صحيحة',
      );
    }

    // فحص تفعيل الحساب
    if (!user.subscriptionActive) {
      return const CloudAuthResult.failure(
        CloudAuthErrorCode.accountInactive,
        'حسابك غير مفعّل حاليًا، تواصل مع الإدارة',
      );
    }

    _currentUserId = user.id;
    return CloudAuthResult.success(user.toProfile());
  }

  @override
  Future<void> signOut() async {
    _currentUserId = null;
  }

  @override
  Future<CloudUserProfile?> getCurrentProfile() async {
    if (_currentUserId == null) return null;
    for (final u in _users.values) {
      if (u.id == _currentUserId) return u.toProfile();
    }
    return null;
  }

  @override
  Future<bool> isSubscriptionActive(String userId) async {
    for (final u in _users.values) {
      if (u.id == userId) return u.subscriptionActive;
    }
    return false;
  }

  /// تفعيل اشتراك مستخدم (للاختبارات)
  void setSubscriptionActive(String email, bool active) {
    final u = _users[email.toLowerCase()];
    if (u != null) {
      u.subscriptionActive = active;
    }
  }

  void reset() {
    _users.clear();
    _cloudTables.clear();
    _currentUserId = null;
  }
}

class _MockUserEntry {
  final String id;
  final String email;
  final String password;
  final String name;
  final String role;
  bool subscriptionActive;
  final String? coachId;
  final int? playerId;

  _MockUserEntry({
    required this.id,
    required this.email,
    required this.password,
    required this.name,
    required this.role,
    this.subscriptionActive = false,
    this.coachId,
    this.playerId,
  });

  CloudUserProfile toProfile() => CloudUserProfile(
        id: id,
        email: email,
        name: name,
        role: role,
        coachId: coachId,
        playerId: playerId,
        subscriptionActive: subscriptionActive,
      );
}
