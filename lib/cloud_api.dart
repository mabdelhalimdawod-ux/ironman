import 'dart:async';
import 'dart:typed_data';
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
  final DateTime? createdAt;

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
    this.createdAt,
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
      createdAt: map['created_at'] != null ? DateTime.tryParse(map['created_at'].toString()) : null,
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
        'created_at': createdAt?.toIso8601String(),
        'subscription_active': subscriptionActive ? 1 : 0,
      };
}

/// نتيجة عملية المصادقة
class CloudAuthResult {
  final bool isSuccess;
  final CloudUserProfile? profile;
  final CloudAuthErrorCode? errorCode;
  final String? errorMessage;
  CloudUserProfile? get user => profile;

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

  static set mockInstance(CloudApi? api) {
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

  /// جلب كافة ملفات المستخدمين (للأدمن فقط)
  Future<List<CloudUserProfile>> listAllProfiles();

  /// تحديث حالة الاشتراك (للأدمن فقط مع التسجيل في سجل التدقيق)
  Future<void> updateSubscription({
    required String userId,
    required bool active,
    String? note,
    required String adminId,
  });

  /// جلب سجل تدقيق اشتراكات مستخدم محدد
  Future<List<Map<String, dynamic>>> getSubscriptionLogs(String userId);

  /// جلب قائمة المدربين المفعّلين
  Future<List<CloudUserProfile>> getActiveCoaches();

  /// إرسال طلب انضمام لمدرب
  Future<void> sendCoachRequest({
    required String athleteId,
    required String coachId,
  });

  /// جلب طلبات الانضمام الخاصة باللاعب
  Future<List<Map<String, dynamic>>> getCoachRequestsForAthlete(String athleteId);

  /// جلب طلبات الانضمام الواردة للمدرب
  Future<List<Map<String, dynamic>>> getCoachRequestsForCoach(String coachId);

  /// الرد على طلب الانضمام (قبول / رفض)
  Future<void> respondToCoachRequest({
    required String requestId,
    required String status,
    required String coachId,
  });

  /// إلغاء طلب انضمام معلّق
  Future<void> cancelCoachRequest(String requestId);

  /// إزالة لاعب من قائمة مدرب
  Future<void> removeAthleteFromCoach({
    required String coachId,
    required String athleteId,
  });

  /// تحديث خصوصية مشاركة المنحنيات
  Future<void> updateCurveSharing({
    required String playerId,
    required bool shared,
    required String byWho,
  });

  /// جلب زملاء الفريق تحت نفس المدرب
  Future<List<CloudUserProfile>> getTeammates(String coachId);

  /// جلب بيانات المنحنيات المشتركة للاعب
  Future<List<Map<String, dynamic>>> getSharedCurveData(String playerId);

  /// رفع صورة المستخدم الرمزية إلى باكت avatars
  Future<String?> uploadAvatar({
    required String userId,
    required List<int> bytes,
  });

  /// تنزيل صورة المستخدم الرمزية
  Future<List<int>?> downloadAvatar(String userId);
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

  @override
  Future<List<CloudUserProfile>> listAllProfiles() async {
    final res = await client.from('profiles').select('*, subscriptions(status)');
    return (res as List).map((row) {
      final subMap = row['subscriptions'] as Map<String, dynamic>?;
      final isActive = subMap != null && subMap['status'] == 'active';
      return CloudUserProfile.fromMap(row, subscriptionActive: isActive);
    }).toList();
  }

  @override
  Future<void> updateSubscription({
    required String userId,
    required bool active,
    String? note,
    required String adminId,
  }) async {
    await client.from('subscriptions').upsert({
      'user_id': userId,
      'status': active ? 'active' : 'inactive',
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
    await client.from('subscription_log').insert({
      'user_id': userId,
      'action': active ? 'activated' : 'deactivated',
      'changed_by': adminId,
      'note': note ?? '',
      'created_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  @override
  Future<List<Map<String, dynamic>>> getSubscriptionLogs(String userId) async {
    final res = await client
        .from('subscription_log')
        .select()
        .eq('user_id', userId)
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(res);
  }

  @override
  Future<List<CloudUserProfile>> getActiveCoaches() async {
    final res = await client
        .from('profiles')
        .select('*, subscriptions!inner(status)')
        .eq('role', 'coach')
        .eq('subscriptions.status', 'active');
    return (res as List).map((row) => CloudUserProfile.fromMap(row, subscriptionActive: true)).toList();
  }

  @override
  Future<void> sendCoachRequest({
    required String athleteId,
    required String coachId,
  }) async {
    final existing = await client
        .from('coach_requests')
        .select()
        .eq('athlete_id', athleteId)
        .eq('coach_id', coachId)
        .eq('status', 'pending');
    if ((existing as List).isNotEmpty) {
      throw Exception('يوجد طلب معلّق بالفعل لهذا المدرب');
    }
    await client.from('coach_requests').insert({
      'athlete_id': athleteId,
      'coach_id': coachId,
      'status': 'pending',
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  @override
  Future<List<Map<String, dynamic>>> getCoachRequestsForAthlete(String athleteId) async {
    final res = await client
        .from('coach_requests')
        .select('*, coach:profiles!coach_id(name, email, photo_path)')
        .eq('athlete_id', athleteId)
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(res);
  }

  @override
  Future<List<Map<String, dynamic>>> getCoachRequestsForCoach(String coachId) async {
    final res = await client
        .from('coach_requests')
        .select('*, athlete:profiles!athlete_id(name, email, photo_path)')
        .eq('coach_id', coachId)
        .eq('status', 'pending')
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(res);
  }

  @override
  Future<void> respondToCoachRequest({
    required String requestId,
    required String status,
    required String coachId,
  }) async {
    if (status == 'accepted') {
      final active = await isSubscriptionActive(coachId);
      if (!active) {
        throw Exception('لا يمكن قبول الطلب: اشتراك المدرب غير مفعّل');
      }
      final reqRow = await client.from('coach_requests').select().eq('id', requestId).maybeSingle();
      if (reqRow != null) {
        final athleteId = reqRow['athlete_id'];
        await client.from('profiles').update({'coach_id': coachId}).eq('id', athleteId);
      }
    }
    await client.from('coach_requests').update({
      'status': status,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', requestId);
  }

  @override
  Future<void> cancelCoachRequest(String requestId) async {
    await client.from('coach_requests').update({
      'status': 'cancelled',
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', requestId);
  }

  @override
  Future<void> removeAthleteFromCoach({
    required String coachId,
    required String athleteId,
  }) async {
    await client.from('profiles').update({'coach_id': null}).eq('id', athleteId).eq('coach_id', coachId);
  }

  @override
  Future<void> updateCurveSharing({
    required String playerId,
    required bool shared,
    required String byWho,
  }) async {
    await client.from('players').update({
      'curves_shared': shared ? 1 : 0,
      'curves_shared_by': byWho,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', playerId);
  }

  @override
  Future<List<CloudUserProfile>> getTeammates(String coachId) async {
    final res = await client
        .from('profiles')
        .select('*, players(curves_shared, curves_shared_by)')
        .eq('coach_id', coachId)
        .eq('role', 'athlete');
    return (res as List).map((row) => CloudUserProfile.fromMap(row, subscriptionActive: true)).toList();
  }

  @override
  Future<List<Map<String, dynamic>>> getSharedCurveData(String playerId) async {
    final res = await client.from('shared_curve_data').select().eq('player_id', playerId);
    return List<Map<String, dynamic>>.from(res);
  }

  @override
  Future<String?> uploadAvatar({
    required String userId,
    required List<int> bytes,
  }) async {
    final path = '$userId.jpg';
    await client.storage.from('avatars').uploadBinary(
      path,
      Uint8List.fromList(bytes),
      fileOptions: const FileOptions(upsert: true, contentType: 'image/jpeg'),
    );
    return path;
  }

  @override
  Future<List<int>?> downloadAvatar(String userId) async {
    try {
      final bytes = await client.storage.from('avatars').download('$userId.jpg');
      return bytes;
    } catch (_) {
      return null;
    }
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
    _subscriptionLogs.clear();
    _coachRequests.clear();
    _mockAvatars.clear();
    _currentUserId = null;
  }

  final List<Map<String, dynamic>> _subscriptionLogs = [];
  final List<Map<String, dynamic>> _coachRequests = [];
  final Map<String, List<int>> _mockAvatars = {};

  @override
  Future<List<CloudUserProfile>> listAllProfiles() async {
    return _users.values.map((u) => u.toProfile()).toList();
  }

  @override
  Future<void> updateSubscription({
    required String userId,
    required bool active,
    String? note,
    required String adminId,
  }) async {
    for (final u in _users.values) {
      if (u.id == userId) {
        u.subscriptionActive = active;
        break;
      }
    }
    _subscriptionLogs.add({
      'id': 'log-${_subscriptionLogs.length + 1}',
      'user_id': userId,
      'action': active ? 'activated' : 'deactivated',
      'changed_by': adminId,
      'note': note ?? '',
      'created_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  @override
  Future<List<Map<String, dynamic>>> getSubscriptionLogs(String userId) async {
    return _subscriptionLogs
        .where((l) => l['user_id'] == userId)
        .toList()
      ..sort((a, b) => (b['created_at'] as String).compareTo(a['created_at'] as String));
  }

  @override
  Future<List<CloudUserProfile>> getActiveCoaches() async {
    return _users.values
        .where((u) => u.role == 'coach' && u.subscriptionActive)
        .map((u) => u.toProfile())
        .toList();
  }

  @override
  Future<void> sendCoachRequest({
    required String athleteId,
    required String coachId,
  }) async {
    final existing = _coachRequests.where((r) =>
        r['athlete_id'] == athleteId &&
        r['coach_id'] == coachId &&
        r['status'] == 'pending');
    if (existing.isNotEmpty) {
      throw Exception('يوجد طلب معلّق بالفعل لهذا المدرب');
    }
    _coachRequests.add({
      'id': 'req-${_coachRequests.length + 1}',
      'athlete_id': athleteId,
      'coach_id': coachId,
      'status': 'pending',
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  @override
  Future<List<Map<String, dynamic>>> getCoachRequestsForAthlete(String athleteId) async {
    return _coachRequests.where((r) => r['athlete_id'] == athleteId).toList();
  }

  @override
  Future<List<Map<String, dynamic>>> getCoachRequestsForCoach(String coachId) async {
    return _coachRequests
        .where((r) => r['coach_id'] == coachId && r['status'] == 'pending')
        .toList();
  }

  @override
  Future<void> respondToCoachRequest({
    required String requestId,
    required String status,
    required String coachId,
  }) async {
    final reqIndex = _coachRequests.indexWhere((r) => r['id'] == requestId);
    if (reqIndex == -1) return;
    final req = _coachRequests[reqIndex];

    if (status == 'accepted') {
      final coach = _users.values.firstWhere((u) => u.id == coachId, orElse: () => throw Exception('المدرب غير موجود'));
      if (!coach.subscriptionActive) {
        throw Exception('لا يمكن قبول الطلب: اشتراك المدرب غير مفعّل');
      }
      for (final u in _users.values) {
        if (u.id == req['athlete_id']) {
          u.coachId = coachId;
          break;
        }
      }
    }
    req['status'] = status;
    req['updated_at'] = DateTime.now().toUtc().toIso8601String();
  }

  @override
  Future<void> cancelCoachRequest(String requestId) async {
    final req = _coachRequests.firstWhere((r) => r['id'] == requestId, orElse: () => {});
    if (req.isNotEmpty) {
      req['status'] = 'cancelled';
      req['updated_at'] = DateTime.now().toUtc().toIso8601String();
    }
  }

  @override
  Future<void> removeAthleteFromCoach({
    required String coachId,
    required String athleteId,
  }) async {
    for (final u in _users.values) {
      if (u.id == athleteId && u.coachId == coachId) {
        u.coachId = null;
        break;
      }
    }
  }

  @override
  Future<void> updateCurveSharing({
    required String playerId,
    required bool shared,
    required String byWho,
  }) async {
    final playersTable = _cloudTables.putIfAbsent('players', () => {});
    for (final rec in playersTable.values) {
      if (rec['id']?.toString() == playerId || rec['local_id']?.toString() == playerId) {
        rec['curves_shared'] = shared ? 1 : 0;
        rec['curves_shared_by'] = byWho;
        rec['updated_at'] = DateTime.now().toUtc().toIso8601String();
        return;
      }
    }
    playersTable[playerId] = {
      'id': playerId,
      'curves_shared': shared ? 1 : 0,
      'curves_shared_by': byWho,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
  }

  @override
  Future<List<CloudUserProfile>> getTeammates(String coachId) async {
    return _users.values
        .where((u) => u.coachId == coachId && u.role == 'athlete')
        .map((u) => u.toProfile())
        .toList();
  }

  @override
  Future<List<Map<String, dynamic>>> getSharedCurveData(String playerId) async {
    final logsTable = _cloudTables['logs'] ?? {};
    final playersTable = _cloudTables['players'] ?? {};
    final player = playersTable.values.firstWhere(
      (p) => p['id']?.toString() == playerId || p['local_id']?.toString() == playerId,
      orElse: () => {},
    );
    if (player.isEmpty || (player['curves_shared'] as num?)?.toInt() != 1) {
      return [];
    }
    return logsTable.values
        .where((l) => l['player_id']?.toString() == playerId)
        .map((l) => {
              'player_id': l['player_id'],
              'date': l['date'],
              'zone': l['zone'],
              'kind': l['kind'],
              'avg_power': l['avg_power'],
              'ef': l['ef'],
              'decoupling': l['decoupling'],
              'eupnea_1': l['eupnea_1'],
              'eupnea_2': l['eupnea_2'],
              'eupnea_3': l['eupnea_3'],
              'split_500': l['split_500'],
            })
        .toList();
  }

  @override
  Future<String?> uploadAvatar({
    required String userId,
    required List<int> bytes,
  }) async {
    _mockAvatars[userId] = bytes;
    for (final u in _users.values) {
      if (u.id == userId) {
        u.photoPath = 'avatars/$userId.jpg';
        break;
      }
    }
    return 'avatars/$userId.jpg';
  }

  @override
  Future<List<int>?> downloadAvatar(String userId) async {
    return _mockAvatars[userId];
  }
}

class _MockUserEntry {
  final String id;
  final String email;
  final String password;
  final String name;
  final String role;
  bool subscriptionActive;
  String? coachId;
  final int? playerId;
  String? photoPath;
  DateTime createdAt;

  _MockUserEntry({
    required this.id,
    required this.email,
    required this.password,
    required this.name,
    required this.role,
    this.subscriptionActive = false,
    this.coachId,
    this.playerId,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now().toUtc();

  CloudUserProfile toProfile() => CloudUserProfile(
        id: id,
        email: email,
        name: name,
        role: role,
        coachId: coachId,
        playerId: playerId,
        photoPath: photoPath,
        subscriptionActive: subscriptionActive,
        createdAt: createdAt,
      );
}
