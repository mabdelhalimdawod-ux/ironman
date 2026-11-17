import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'app_strings.dart';
import 'auth_service.dart';
import 'engine_rowing_ui.dart';

/// ويدجت موحدة لعرض وإدارة الصورة الشخصية (Avatar) للمستخدم أو اللاعب
/// - تعرض الصورة إن وُجدت وكان ملفها سليماً، أو الأيقونة الافتراضية
/// - لا تنهار أبداً حتى لو كان مسار الصورة غير موجود
/// - تتيح للمستخدم تغيير صورته هو فقط عبر الكاميرا أو المعرض أو حذفها
class UserAvatarWidget extends StatelessWidget {
  final String? photoPath;
  final double radius;
  final bool isEditable;
  final int? targetUserId;
  final int? currentUserId;
  final ValueChanged<String?>? onPhotoChanged;

  const UserAvatarWidget({
    super.key,
    this.photoPath,
    this.radius = 26,
    this.isEditable = false,
    this.targetUserId,
    this.currentUserId,
    this.onPhotoChanged,
  });

  bool get _hasValidFile {
    if (photoPath == null || photoPath!.trim().isEmpty) return false;
    try {
      final f = File(photoPath!);
      return f.existsSync();
    } catch (_) {
      return false;
    }
  }

  Future<void> _showPhotoOptions(BuildContext context) async {
    final s = AppStrings.of(context);
    final targetId = targetUserId ?? currentUserId;
    final actingId = currentUserId;

    if (targetId == null || actingId == null || targetId != actingId) {
      return; // الأمان: كل مستخدم يغير صورته هو فقط
    }

    final picker = ImagePicker();

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: EngineRowingUI.cardFill,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: EngineRowingUI.bgGridLine,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Text(
                  s.isArabic ? 'صورة الملف الشخصي' : 'Profile Photo',
                  style: const TextStyle(
                    color: EngineRowingUI.textWhite,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                ListTile(
                  leading: const Icon(Icons.camera_alt_rounded,
                      color: EngineRowingUI.neonLime),
                  title: Text(
                    s.isArabic ? 'التقاط صورة' : 'Take a Photo',
                    style: const TextStyle(color: EngineRowingUI.textWhite),
                  ),
                  onTap: () async {
                    Navigator.pop(sheetCtx);
                    try {
                      final photo = await picker.pickImage(
                        source: ImageSource.camera,
                        maxWidth: 512,
                        imageQuality: 80,
                      );
                      if (photo != null) {
                        final newPath = await AuthService.updateUserPhoto(
                          targetUserId: targetId,
                          actingUserId: actingId,
                          sourcePath: photo.path,
                        );
                        onPhotoChanged?.call(newPath);
                      }
                    } catch (_) {}
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.photo_library_rounded,
                      color: Color(0xFF00E5FF)),
                  title: Text(
                    s.isArabic ? 'اختيار من المعرض' : 'Choose from Gallery',
                    style: const TextStyle(color: EngineRowingUI.textWhite),
                  ),
                  onTap: () async {
                    Navigator.pop(sheetCtx);
                    try {
                      final photo = await picker.pickImage(
                        source: ImageSource.gallery,
                        maxWidth: 512,
                        imageQuality: 80,
                      );
                      if (photo != null) {
                        final newPath = await AuthService.updateUserPhoto(
                          targetUserId: targetId,
                          actingUserId: actingId,
                          sourcePath: photo.path,
                        );
                        onPhotoChanged?.call(newPath);
                      }
                    } catch (_) {}
                  },
                ),
                if (_hasValidFile)
                  ListTile(
                    leading: const Icon(Icons.delete_outline_rounded,
                        color: Colors.redAccent),
                    title: Text(
                      s.isArabic ? 'حذف الصورة' : 'Delete Photo',
                      style: const TextStyle(color: Colors.redAccent),
                    ),
                    onTap: () async {
                      Navigator.pop(sheetCtx);
                      try {
                        await AuthService.deleteUserPhoto(
                          targetUserId: targetId,
                          actingUserId: actingId,
                        );
                        onPhotoChanged?.call(null);
                      } catch (_) {}
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget avatarContent;
    if (_hasValidFile) {
      avatarContent = ClipOval(
        child: Image.file(
          File(photoPath!),
          width: radius * 2,
          height: radius * 2,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _buildFallbackIcon(),
        ),
      );
    } else {
      avatarContent = _buildFallbackIcon();
    }

    final avatar = Stack(
      children: [
        CircleAvatar(
          radius: radius,
          backgroundColor: EngineRowingUI.equationCardFill,
          child: avatarContent,
        ),
        if (isEditable)
          Positioned(
            bottom: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: const BoxDecoration(
                color: EngineRowingUI.neonLime,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.camera_alt_rounded,
                size: radius * 0.45,
                color: EngineRowingUI.bgNavy,
              ),
            ),
          ),
      ],
    );

    if (isEditable) {
      return InkWell(
        onTap: () => _showPhotoOptions(context),
        borderRadius: BorderRadius.circular(radius),
        child: avatar,
      );
    }

    return avatar;
  }

  Widget _buildFallbackIcon() {
    return Icon(
      Icons.person_rounded,
      size: radius * 1.25,
      color: EngineRowingUI.neonLime,
    );
  }
}
