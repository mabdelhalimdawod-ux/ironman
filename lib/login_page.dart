import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'app_strings.dart';
import 'auth_service.dart';
import 'engine_rowing_ui.dart';

// ============================================================================
// ثيم وألوان شاشة المصادقة (Auth Theme Constants) - Aligned with EngineRowingUI
// ============================================================================
const Color authBlueDeep = EngineRowingUI.equationCardFill; // #122147
const Color authBlueMid = EngineRowingUI.cardFill; // #15264F
const Color authCyan = EngineRowingUI.neonLime; // #B8F229
const Color authGold = EngineRowingUI.neonLime; // #B8F229
const Color authGoldDeep = Color(0xFFA4D924);
const Color authCardDark = EngineRowingUI.cardFill; // #15264F
const Color authScrim = EngineRowingUI.bgNavy; // #0A1633

/// شاشة المصادقة الموحدة: تسجيل الدخول + إنشاء حساب بتبويبين (Login & Sign Up Page)
class LoginPage extends StatefulWidget {
  final ValueChanged<AppUser> onLoginSuccess;

  const LoginPage({
    super.key,
    required this.onLoginSuccess,
  });

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  // التبويب النشط: 0 = تسجيل الدخول، 1 = إنشاء حساب
  int _activeTabIndex = 0;

  // ── متحكمات تسجيل الدخول ──
  final _loginFormKey = GlobalKey<FormState>();
  final _loginEmailController = TextEditingController();
  final _loginPasswordController = TextEditingController();
  bool _rememberMe = true;
  bool _isLoginLoading = false;
  String? _loginError;
  String _loginRole = 'coach'; // 'coach' | 'athlete' | 'admin'

  // ── متحكمات إنشاء حساب ──
  final _signUpFormKey = GlobalKey<FormState>();
  final _signUpFirstNameController = TextEditingController();
  final _signUpLastNameController = TextEditingController();
  final _signUpEmailController = TextEditingController();
  final _signUpPasswordController = TextEditingController();
  final _signUpConfirmPasswordController = TextEditingController();
  String _selectedRole = 'athlete'; // 'athlete' | 'coach'
  bool _agreedToTerms = false;
  bool _isSignUpLoading = false;
  String? _signUpError;

  // ── الساعة الحية ──
  Timer? _clockTimer;
  DateTime _currentTime = DateTime.now();

  @override
  void initState() {
    super.initState();
    _startClock();
    _loadSavedEmail();
  }

  void _startClock() {
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _currentTime = DateTime.now();
        });
      }
    });
  }

  Future<void> _loadSavedEmail() async {
    final savedEmail = await AuthService.getSavedEmail();
    if (savedEmail != null && savedEmail.isNotEmpty && mounted) {
      _loginEmailController.text = savedEmail;
    } else if (mounted) {
      _loginEmailController.text = 'mabdelhalimdawod@engine.rowing';
      _loginPasswordController.text = 'mahmoud@76Mm';
    }
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _loginEmailController.dispose();
    _loginPasswordController.dispose();
    _signUpFirstNameController.dispose();
    _signUpLastNameController.dispose();
    _signUpEmailController.dispose();
    _signUpPasswordController.dispose();
    _signUpConfirmPasswordController.dispose();
    super.dispose();
  }

  String _formatClockTime(DateTime time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    final second = time.second.toString().padLeft(2, '0');
    return '$hour:$minute:$second';
  }

  // ── تنفيذ تسجيل الدخول ──
  Future<void> _handleLogin() async {
    setState(() => _loginError = null);
    if (!_loginFormKey.currentState!.validate()) return;

    setState(() => _isLoginLoading = true);

    try {
      final result = await AuthService.login(
        _loginEmailController.text,
        _loginPasswordController.text,
        _loginRole,
      );

      if (!mounted) return;

      if (result.isSuccess && result.user != null) {
        await AuthService.saveSession(result.user!, _rememberMe);
        widget.onLoginSuccess(result.user!);
      } else {
        final s = AppStrings.of(context);
        String msg = s.invalidCredentials;
        if (result.error == LoginError.awaitingActivation) {
          msg = s.awaitingActivationError;
        } else if (result.error == LoginError.accountInactive) {
          msg = s.accountInactive;
        } else if (result.error == LoginError.coachSubscriptionInactive) {
          msg = s.coachSubscriptionInactive;
        }
        setState(() {
          _loginError = msg;
          _isLoginLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loginError = AppStrings.of(context).invalidCredentials;
          _isLoginLoading = false;
        });
      }
    }
  }

  // ── تنفيذ إنشاء حساب جديد ──
  Future<void> _handleSignUp() async {
    setState(() => _signUpError = null);
    final s = AppStrings.of(context);

    if (!_signUpFormKey.currentState!.validate()) return;

    if (!_agreedToTerms) {
      setState(() => _signUpError = s.mustAcceptTerms);
      return;
    }

    if (_signUpPasswordController.text !=
        _signUpConfirmPasswordController.text) {
      setState(() => _signUpError = s.passwordMismatch);
      return;
    }

    setState(() => _isSignUpLoading = true);

    try {
      final email = _signUpEmailController.text.trim();
      final isTaken = await AuthService.isEmailRegistered(email);
      if (isTaken) {
        if (!mounted) return;
        setState(() {
          _signUpError = s.emailAlreadyExists;
          _isSignUpLoading = false;
        });
        return;
      }

      final fullName =
          '${_signUpFirstNameController.text.trim()} ${_signUpLastNameController.text.trim()}';

      // إنشاء المستخدم بحالة غير مفعلة (نموذج الدفع كاش: بانتظار تفعيل الإدارة)
      await AuthService.registerUser(
        email: email,
        password: _signUpPasswordController.text,
        name: fullName,
        role: _selectedRole,
        coachId: null,
        playerId: null,
        subscriptionActive: false,
      );

      if (!mounted) return;

      setState(() => _isSignUpLoading = false);

      // إظهار نافذة إعلام بالنجاح والتنبيه بأن الحساب بانتظار التفعيل
      await _showAwaitingActivationDialog(context, email);
    } catch (e) {
      if (mounted) {
        setState(() {
          _signUpError = s.error;
          _isSignUpLoading = false;
        });
      }
    }
  }

  // ── نافذة نجاح التسجيل وبانتظار التفعيل ──
  Future<void> _showAwaitingActivationDialog(
      BuildContext context, String registeredEmail) async {
    final s = AppStrings.of(context);
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: AlertDialog(
            backgroundColor: EngineRowingUI.cardFill,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: const BorderSide(
                  color: EngineRowingUI.bgGridLine, width: 1.2),
            ),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: EngineRowingUI.neonLime.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.hourglass_top_rounded,
                    color: EngineRowingUI.neonLime,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    s.signUpSuccessTitle,
                    style: const TextStyle(
                      color: EngineRowingUI.textWhite,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            content: Text(
              s.signUpSuccessMessage,
              style: const TextStyle(
                color: EngineRowingUI.textWhite,
                fontSize: 14.5,
                height: 1.5,
              ),
            ),
            actions: [
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: EngineRowingUI.neonLime,
                  foregroundColor: EngineRowingUI.bgNavy,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: () {
                  Navigator.pop(ctx);
                  // التحويل التلقائي لتبويب تسجيل الدخول وتعبئة الإيميل
                  setState(() {
                    _activeTabIndex = 0;
                    _loginEmailController.text = registeredEmail;
                    _loginPasswordController.clear();
                    _signUpPasswordController.clear();
                    _signUpConfirmPasswordController.clear();
                  });
                },
                child: Text(
                  s.ok,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: EngineRowingUI.bgNavy,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── نافذة الشروط والأحكام المؤقتة ──
  void _showTermsDialog(BuildContext context) {
    final s = AppStrings.of(context);
    showDialog(
      context: context,
      builder: (ctx) {
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: AlertDialog(
            backgroundColor: EngineRowingUI.cardFill,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: const BorderSide(
                  color: EngineRowingUI.bgGridLine, width: 1.2),
            ),
            title: Row(
              children: [
                const Icon(Icons.gavel_rounded,
                    color: EngineRowingUI.neonLime, size: 24),
                const SizedBox(width: 10),
                Text(
                  s.termsAndConditionsTitle,
                  style: const TextStyle(
                    color: EngineRowingUI.textWhite,
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            content: Text(
              s.termsComingSoon,
              style: const TextStyle(
                color: EngineRowingUI.labelSlate,
                fontSize: 14.5,
                height: 1.5,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(
                  s.close,
                  style: const TextStyle(
                    color: EngineRowingUI.neonLime,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── نافذة استعادة كلمة السر ──
  void _showForgotPasswordDialog(BuildContext context) {
    final s = AppStrings.of(context);
    showDialog(
      context: context,
      builder: (ctx) {
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: AlertDialog(
            backgroundColor: EngineRowingUI.cardFill,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: const BorderSide(
                  color: EngineRowingUI.bgGridLine, width: 1.2),
            ),
            title: Row(
              children: [
                const Icon(Icons.help_outline_rounded,
                    color: EngineRowingUI.neonLime, size: 24),
                const SizedBox(width: 10),
                Text(
                  s.forgotPasswordTitle,
                  style: const TextStyle(
                    color: EngineRowingUI.textWhite,
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            content: Text(
              s.forgotPasswordDialogText,
              style: const TextStyle(
                color: EngineRowingUI.textWhite,
                fontSize: 14.5,
                height: 1.5,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(
                  s.close,
                  style: const TextStyle(
                    color: EngineRowingUI.neonLime,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── التنبيه الخاص بدخول جوجل المؤقت ──
  void _handleGoogleSignIn(BuildContext context) {
    final s = AppStrings.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: EngineRowingUI.cardFill,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: EngineRowingUI.bgGridLine),
        ),
        content: Row(
          children: [
            const Icon(Icons.info_outline,
                color: EngineRowingUI.neonLime, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                s.googleComingSoon,
                style: const TextStyle(
                    color: EngineRowingUI.textWhite, fontSize: 13.5),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final isArabic = AppLanguage.instance.isArabic;

    return Scaffold(
      backgroundColor: EngineRowingUI.bgNavy,
      body: RowingGridBackground(
        child: Stack(
          children: [
            // المحتوى المتجاوب
            SafeArea(
              child: Column(
                children: [
                  // ── الشريط العلوي: الساعة الحية + زر تبديل اللغة ──
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // الساعة الحية
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 7),
                          decoration: BoxDecoration(
                            color: EngineRowingUI.cardFill,
                            borderRadius: BorderRadius.circular(20),
                            border:
                                Border.all(color: EngineRowingUI.bgGridLine),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: const BoxDecoration(
                                  color: EngineRowingUI.neonLime,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Directionality(
                                textDirection: TextDirection.ltr,
                                child: Text(
                                  _formatClockTime(_currentTime),
                                  style: const TextStyle(
                                    color: EngineRowingUI.textWhite,
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.bold,
                                    fontFeatures: [
                                      FontFeature.tabularFigures()
                                    ],
                                    letterSpacing: 0.8,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        // زر تبديل اللغة الفوري (عربي / English)
                        Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(20),
                            onTap: () => AppLanguage.instance.toggleLanguage(),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 7),
                              decoration: BoxDecoration(
                                color: EngineRowingUI.cardFill,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                    color: EngineRowingUI.bgGridLine),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.language_rounded,
                                    color: EngineRowingUI.neonLime,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    isArabic ? 'English' : 'العربية',
                                    style: const TextStyle(
                                      color: EngineRowingUI.neonLime,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // ── البطاقة المركزية ──
                  Expanded(
                    child: Center(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 16),
                        child: Container(
                          constraints: const BoxConstraints(maxWidth: 460),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(24),
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 28,
                                  vertical: 32,
                                ),
                                decoration: BoxDecoration(
                                  color: EngineRowingUI.cardFill
                                      .withValues(alpha: 0.88),
                                  borderRadius: BorderRadius.circular(24),
                                  border: Border.all(
                                    color: EngineRowingUI.bgGridLine,
                                    width: 1.5,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color:
                                          Colors.black.withValues(alpha: 0.45),
                                      blurRadius: 35,
                                      offset: const Offset(0, 16),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    // ── لوجو وعنوان التطبيق ──
                                    Center(
                                      child: Column(
                                        children: [
                                          const Text(
                                            'ENGINE ROWING',
                                            style: TextStyle(
                                              color: EngineRowingUI.neonLime,
                                              fontSize: 24,
                                              fontWeight: FontWeight.w900,
                                              letterSpacing: 2.2,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            s.authBrandSubtitle,
                                            textAlign: TextAlign.center,
                                            style: const TextStyle(
                                              color: EngineRowingUI.labelSlate,
                                              fontSize: 12.5,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 24),

                                    // ── شريط التبويبين (تسجيل الدخول / إنشاء حساب) ──
                                    Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: BoxDecoration(
                                        color: EngineRowingUI.equationCardFill,
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(
                                          color: EngineRowingUI.bgGridLine,
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          // تبويب تسجيل الدخول
                                          Expanded(
                                            child: _AuthTabButton(
                                              title: s.loginTab,
                                              isActive: _activeTabIndex == 0,
                                              onTap: () {
                                                if (_activeTabIndex != 0) {
                                                  setState(() {
                                                    _activeTabIndex = 0;
                                                    _loginError = null;
                                                  });
                                                }
                                              },
                                            ),
                                          ),
                                          // تبويب إنشاء حساب
                                          Expanded(
                                            child: _AuthTabButton(
                                              title: s.signUpTab,
                                              isActive: _activeTabIndex == 1,
                                              onTap: () {
                                                if (_activeTabIndex != 1) {
                                                  setState(() {
                                                    _activeTabIndex = 1;
                                                    _signUpError = null;
                                                  });
                                                }
                                              },
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 24),

                                    // ── محتوى التبويب النشط بحركة انسيابية ──
                                    AnimatedCrossFade(
                                      duration:
                                          const Duration(milliseconds: 280),
                                      crossFadeState: _activeTabIndex == 0
                                          ? CrossFadeState.showFirst
                                          : CrossFadeState.showSecond,
                                      firstChild: _buildLoginForm(context),
                                      secondChild: _buildSignUpForm(context),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================================================
  // نموذج تسجيل الدخول (Login Form)
  // ==========================================================================
  Widget _buildLoginForm(BuildContext context) {
    final s = AppStrings.of(context);

    return Form(
      key: _loginFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // رسالة خطأ تسجيل الدخول إن وجدت
          if (_loginError != null) ...[
            _AuthAlertBox(
              message: _loginError!,
              isError: true,
            ),
            const SizedBox(height: 16),
          ],

          // حقل البريد الإلكتروني (Floating Label)
          _AuthFloatingTextField(
            controller: _loginEmailController,
            label: s.email,
            isRequired: true,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            prefixIcon: const Icon(
              Icons.email_outlined,
              color: EngineRowingUI.neonLime,
              size: 20,
            ),
            validator: (val) {
              if (val == null || val.trim().isEmpty) return s.invalidEmail;
              final regex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
              if (!regex.hasMatch(val.trim())) return s.invalidEmail;
              return null;
            },
          ),
          const SizedBox(height: 16),

          // حقل كلمة المرور (Floating Label)
          _AuthFloatingTextField(
            controller: _loginPasswordController,
            label: s.password,
            isRequired: true,
            isPassword: true,
            textInputAction: TextInputAction.done,
            prefixIcon: const Icon(
              Icons.lock_outline_rounded,
              color: EngineRowingUI.neonLime,
              size: 20,
            ),
            onFieldSubmitted: (_) => _handleLogin(),
            validator: (val) {
              if (val == null || val.isEmpty) return s.emptyPassword;
              return null;
            },
          ),
          const SizedBox(height: 12),

          // سطر خيارات: تذكرني + نسيت كلمة المرور
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // خيار تذكرني
              InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: () => setState(() => _rememberMe = !_rememberMe),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 20,
                        height: 20,
                        child: Checkbox(
                          value: _rememberMe,
                          activeColor: EngineRowingUI.neonLime,
                          checkColor: EngineRowingUI.bgNavy,
                          side: const BorderSide(
                            color: EngineRowingUI.bgGridLine,
                            width: 1.5,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(4),
                          ),
                          onChanged: (val) =>
                              setState(() => _rememberMe = val ?? false),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        s.rememberMe,
                        style: const TextStyle(
                          color: EngineRowingUI.textWhite,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // رابط نسيت كلمة المرور
              TextButton(
                onPressed: () => _showForgotPasswordDialog(context),
                style: TextButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  s.forgotPasswordTitle,
                  style: const TextStyle(
                    color: EngineRowingUI.neonLime,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // اختيار دور الدخول: مدرب / لاعب / أدمن
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                s.isArabic ? 'تسجيل الدخول بصلاحية:' : 'Sign in as:',
                style: const TextStyle(
                  color: EngineRowingUI.labelSlate,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _buildLoginRoleChip(
                      role: 'coach',
                      label: s.roleCoach,
                      icon: Icons.sports_rounded,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildLoginRoleChip(
                      role: 'athlete',
                      label: s.roleAthlete,
                      icon: Icons.rowing_rounded,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildLoginRoleChip(
                      role: 'admin',
                      label: s.isArabic ? 'أدمن' : 'Admin',
                      icon: Icons.admin_panel_settings_rounded,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),

          // الزر الرئيسي (Sign In)
          _AuthMainButton(
            title: s.signInButton,
            isLoading: _isLoginLoading,
            onPressed: _handleLogin,
          ),
          const SizedBox(height: 18),

          // فاصل "أو"
          _buildOrDivider(s.orDivider),
          const SizedBox(height: 18),

          // زر المتابعة باستخدام Google
          _buildGoogleButton(context),
        ],
      ),
    );
  }

  Widget _buildLoginRoleChip({
    required String role,
    required String label,
    required IconData icon,
  }) {
    return _RoleChoiceChip(
      title: label,
      icon: icon,
      isSelected: _loginRole == role,
      onTap: () => setState(() => _loginRole = role),
    );
  }

  // ==========================================================================
  // نموذج إنشاء حساب جديد (Sign Up Form)
  // ==========================================================================
  Widget _buildSignUpForm(BuildContext context) {
    final s = AppStrings.of(context);

    return Form(
      key: _signUpFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // رسالة الخطأ إن وجدت
          if (_signUpError != null) ...[
            _AuthAlertBox(
              message: _signUpError!,
              isError: true,
            ),
            const SizedBox(height: 16),
          ],

          // سطر الاسم الأول واسم العائلة جنباً إلى جنب
          Row(
            children: [
              Expanded(
                child: _AuthFloatingTextField(
                  controller: _signUpFirstNameController,
                  label: s.firstName,
                  isRequired: true,
                  textInputAction: TextInputAction.next,
                  validator: (val) {
                    if (val == null || val.trim().isEmpty)
                      return s.fieldRequired;
                    return null;
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _AuthFloatingTextField(
                  controller: _signUpLastNameController,
                  label: s.lastName,
                  isRequired: true,
                  textInputAction: TextInputAction.next,
                  validator: (val) {
                    if (val == null || val.trim().isEmpty)
                      return s.fieldRequired;
                    return null;
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // اختيار نوع الحساب (لاعب / مدرب فقط)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: EngineRowingUI.equationCardFill,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: EngineRowingUI.bgGridLine),
            ),
            child: Row(
              children: [
                Text(
                  '${s.accountType}:',
                  style: const TextStyle(
                    color: EngineRowingUI.labelSlate,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Row(
                    children: [
                      // خيار لاعب
                      Expanded(
                        child: _RoleChoiceChip(
                          title: s.roleAthlete,
                          icon: Icons.directions_run_rounded,
                          isSelected: _selectedRole == 'athlete',
                          onTap: () =>
                              setState(() => _selectedRole = 'athlete'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // خيار مدرب
                      Expanded(
                        child: _RoleChoiceChip(
                          title: s.roleCoach,
                          icon: Icons.sports_rounded,
                          isSelected: _selectedRole == 'coach',
                          onTap: () => setState(() => _selectedRole = 'coach'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // البريد الإلكتروني
          _AuthFloatingTextField(
            controller: _signUpEmailController,
            label: s.email,
            isRequired: true,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            prefixIcon: const Icon(
              Icons.email_outlined,
              color: EngineRowingUI.neonLime,
              size: 20,
            ),
            validator: (val) {
              if (val == null || val.trim().isEmpty) return s.invalidEmail;
              final regex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
              if (!regex.hasMatch(val.trim())) return s.invalidEmail;
              return null;
            },
          ),
          const SizedBox(height: 14),

          // كلمة المرور
          _AuthFloatingTextField(
            controller: _signUpPasswordController,
            label: s.password,
            isRequired: true,
            isPassword: true,
            textInputAction: TextInputAction.next,
            prefixIcon: const Icon(
              Icons.lock_outline_rounded,
              color: EngineRowingUI.neonLime,
              size: 20,
            ),
            validator: (val) {
              if (val == null || val.isEmpty) return s.emptyPassword;
              if (val.length < 6) return s.passwordTooShort;
              return null;
            },
          ),
          const SizedBox(height: 14),

          // تأكيد كلمة المرور
          _AuthFloatingTextField(
            controller: _signUpConfirmPasswordController,
            label: s.confirmPassword,
            isRequired: true,
            isPassword: true,
            textInputAction: TextInputAction.done,
            prefixIcon: const Icon(
              Icons.lock_reset_rounded,
              color: EngineRowingUI.neonLime,
              size: 20,
            ),
            onFieldSubmitted: (_) => _handleSignUp(),
            validator: (val) {
              if (val == null || val.isEmpty) return s.emptyPassword;
              if (val != _signUpPasswordController.text) {
                return s.passwordMismatch;
              }
              return null;
            },
          ),
          const SizedBox(height: 14),

          // مربع الشروط والأحكام
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: Checkbox(
                  value: _agreedToTerms,
                  activeColor: EngineRowingUI.neonLime,
                  checkColor: EngineRowingUI.bgNavy,
                  side: const BorderSide(
                    color: EngineRowingUI.bgGridLine,
                    width: 1.5,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4),
                  ),
                  onChanged: (val) =>
                      setState(() => _agreedToTerms = val ?? false),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: GestureDetector(
                  onTap: () => _showTermsDialog(context),
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: '${s.agreeToTerms} ',
                          style: const TextStyle(
                            color: EngineRowingUI.textWhite,
                            fontSize: 13,
                          ),
                        ),
                        const TextSpan(
                          text: 'ⓘ',
                          style: TextStyle(
                            color: EngineRowingUI.neonLime,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),

          // زر إنشاء حساب
          _AuthMainButton(
            title: s.createAccountButton,
            isLoading: _isSignUpLoading,
            onPressed: _handleSignUp,
          ),
        ],
      ),
    );
  }

  // ── خط فاصل "أو" ──
  Widget _buildOrDivider(String text) {
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 1,
            color: EngineRowingUI.bgGridLine,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Text(
            text,
            style: const TextStyle(
              color: EngineRowingUI.labelSlate,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(
          child: Container(
            height: 1,
            color: EngineRowingUI.bgGridLine,
          ),
        ),
      ],
    );
  }

  // ── زر دخول Google (مع أيقونة Google الأصلية) ──
  Widget _buildGoogleButton(BuildContext context) {
    final s = AppStrings.of(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _handleGoogleSignIn(context),
        hoverColor: EngineRowingUI.equationCardFill,
        child: Container(
          height: 48,
          decoration: BoxDecoration(
            color: EngineRowingUI.equationCardFill,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: EngineRowingUI.bgGridLine),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const _GoogleLogoIcon(size: 20),
              const SizedBox(width: 10),
              Text(
                s.continueWithGoogle,
                style: const TextStyle(
                  color: EngineRowingUI.textWhite,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// عنصر الزر الرئيسي للشاشة
// ============================================================================
class _AuthMainButton extends StatelessWidget {
  final String title;
  final bool isLoading;
  final VoidCallback onPressed;

  const _AuthMainButton({
    required this.title,
    required this.isLoading,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 50,
      decoration: BoxDecoration(
        color: EngineRowingUI.neonLime,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: EngineRowingUI.neonLime.withValues(alpha: 0.3),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: isLoading ? null : onPressed,
          child: Center(
            child: isLoading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      valueColor:
                          AlwaysStoppedAnimation<Color>(EngineRowingUI.bgNavy),
                    ),
                  )
                : Text(
                    title,
                    style: const TextStyle(
                      color: EngineRowingUI.bgNavy,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.1,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// زر التبويب (Login / Sign Up)
// ============================================================================
class _AuthTabButton extends StatelessWidget {
  final String title;
  final bool isActive;
  final VoidCallback onTap;

  const _AuthTabButton({
    required this.title,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isActive ? EngineRowingUI.neonLime : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          boxShadow: isActive
              ? [
                  BoxShadow(
                    color: EngineRowingUI.neonLime.withValues(alpha: 0.25),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Center(
          child: Text(
            title,
            style: TextStyle(
              color:
                  isActive ? EngineRowingUI.bgNavy : EngineRowingUI.labelSlate,
              fontSize: 14.5,
              fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// اختيار نوع الحساب (Chip لاعب / مدرب)
// ============================================================================
class _RoleChoiceChip extends StatelessWidget {
  final String title;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _RoleChoiceChip({
    required this.title,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? EngineRowingUI.neonLime
              : EngineRowingUI.equationCardFill,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected
                ? EngineRowingUI.neonLime
                : EngineRowingUI.bgGridLine,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected
                  ? EngineRowingUI.bgNavy
                  : EngineRowingUI.labelSlate,
            ),
            const SizedBox(width: 4),
            Text(
              title,
              style: TextStyle(
                color: isSelected
                    ? EngineRowingUI.bgNavy
                    : EngineRowingUI.textWhite,
                fontSize: 12.5,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// الحقل المخصص ذو العنوان العائم (Custom Floating Label Input Field)
// ============================================================================
class _AuthFloatingTextField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final bool isRequired;
  final bool isPassword;
  final TextInputType keyboardType;
  final TextInputAction textInputAction;
  final Widget? prefixIcon;
  final String? Function(String?)? validator;
  final void Function(String)? onFieldSubmitted;

  const _AuthFloatingTextField({
    required this.controller,
    required this.label,
    this.isRequired = false,
    this.isPassword = false,
    this.keyboardType = TextInputType.text,
    this.textInputAction = TextInputAction.next,
    this.prefixIcon,
    this.validator,
    this.onFieldSubmitted,
  });

  @override
  State<_AuthFloatingTextField> createState() => _AuthFloatingTextFieldState();
}

class _AuthFloatingTextFieldState extends State<_AuthFloatingTextField> {
  final FocusNode _focusNode = FocusNode();
  bool _isFocused = false;
  bool _hasContent = false;
  bool _obscureText = true;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _obscureText = widget.isPassword;
    _hasContent = widget.controller.text.isNotEmpty;

    _focusNode.addListener(() {
      if (mounted) {
        setState(() {
          _isFocused = _focusNode.hasFocus;
        });
      }
    });

    widget.controller.addListener(() {
      final nowHas = widget.controller.text.isNotEmpty;
      if (nowHas != _hasContent && mounted) {
        setState(() {
          _hasContent = nowHas;
        });
      }
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _validateField() {
    if (widget.validator != null) {
      final res = widget.validator!(widget.controller.text);
      if (mounted) {
        setState(() => _errorText = res);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isFloated = _isFocused || _hasContent;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () => _focusNode.requestFocus(),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            height: 60,
            decoration: BoxDecoration(
              color: EngineRowingUI.equationCardFill,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: _errorText != null
                    ? Colors.redAccent
                    : _isFocused
                        ? EngineRowingUI.neonLime
                        : EngineRowingUI.bgGridLine,
                width: _isFocused ? 1.5 : 1.0,
              ),
              boxShadow: _isFocused
                  ? [
                      BoxShadow(
                        color: EngineRowingUI.neonLime.withValues(alpha: 0.18),
                        blurRadius: 10,
                        spreadRadius: 1,
                      ),
                    ]
                  : [],
            ),
            child: Stack(
              children: [
                // ── العنوان العائم المتحرك (Animated Floating Label) ──
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 240),
                  curve: Curves.easeInOutCubic,
                  left: Directionality.of(context) == TextDirection.rtl
                      ? null
                      : (widget.prefixIcon != null ? 44.0 : 16.0),
                  right: Directionality.of(context) == TextDirection.rtl
                      ? (widget.prefixIcon != null ? 44.0 : 16.0)
                      : null,
                  top: isFloated ? 7.0 : 19.0,
                  child: IgnorePointer(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AnimatedDefaultTextStyle(
                          duration: const Duration(milliseconds: 240),
                          curve: Curves.easeInOutCubic,
                          style: TextStyle(
                            color: isFloated
                                ? (_isFocused
                                    ? EngineRowingUI.neonLime
                                    : EngineRowingUI.labelSlate)
                                : EngineRowingUI.labelSlate,
                            fontSize: isFloated ? 11.5 : 15.0,
                            fontWeight:
                                isFloated ? FontWeight.w700 : FontWeight.normal,
                          ),
                          child: Text(widget.label),
                        ),
                        // النجمة تظهر داخل الحقل عند عدم العوم فقط
                        if (widget.isRequired && !isFloated) ...[
                          const SizedBox(width: 3),
                          const Text(
                            '*',
                            style: TextStyle(
                              color: Colors.redAccent,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),

                // ── حقل الإدخال الفعلي ──
                Positioned.fill(
                  child: Padding(
                    padding: EdgeInsetsDirectional.only(
                      start: widget.prefixIcon != null ? 40 : 14,
                      end: widget.isPassword ? 40 : 14,
                      top: isFloated ? 16 : 0,
                    ),
                    child: TextFormField(
                      controller: widget.controller,
                      focusNode: _focusNode,
                      obscureText: _obscureText,
                      keyboardType: widget.keyboardType,
                      textInputAction: widget.textInputAction,
                      onFieldSubmitted: widget.onFieldSubmitted,
                      style: const TextStyle(
                        color: EngineRowingUI.textWhite,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                      cursorColor: EngineRowingUI.neonLime,
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        errorBorder: InputBorder.none,
                        disabledBorder: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                        isDense: true,
                      ),
                      onChanged: (_) {
                        if (_errorText != null) _validateField();
                      },
                      validator: (val) {
                        final res = widget.validator != null
                            ? widget.validator!(val)
                            : null;
                        setState(() => _errorText = res);
                        return res == null ? null : '';
                      },
                    ),
                  ),
                ),

                // ── أيقونة البادئة (Prefix Icon) إن وجدت ──
                if (widget.prefixIcon != null)
                  PositionedDirectional(
                    start: 12,
                    top: 0,
                    bottom: 0,
                    child: Center(child: widget.prefixIcon!),
                  ),

                // ── أيقونة إظهار/إخفاء كلمة المرور ──
                if (widget.isPassword)
                  PositionedDirectional(
                    end: 4,
                    top: 0,
                    bottom: 0,
                    child: IconButton(
                      icon: Icon(
                        _obscureText
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        color: _obscureText
                            ? EngineRowingUI.labelSlate
                            : EngineRowingUI.neonLime,
                        size: 20,
                      ),
                      onPressed: () {
                        setState(() => _obscureText = !_obscureText);
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),

        // رسالة الخطأ الخاصة بالحقل
        if (_errorText != null && _errorText!.isNotEmpty) ...[
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 8),
            child: Text(
              _errorText!,
              style: const TextStyle(
                color: Colors.redAccent,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// ============================================================================
// صندوق تنبيه الأخطاء والرسائل
// ============================================================================
class _AuthAlertBox extends StatelessWidget {
  final String message;
  final bool isError;

  const _AuthAlertBox({
    required this.message,
    this.isError = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isError
            ? Colors.redAccent.withValues(alpha: 0.18)
            : EngineRowingUI.neonLime.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isError
              ? Colors.redAccent.withValues(alpha: 0.5)
              : EngineRowingUI.neonLime.withValues(alpha: 0.5),
        ),
      ),
      child: Row(
        children: [
          Icon(
            isError ? Icons.error_outline_rounded : Icons.info_outline_rounded,
            color: isError ? Colors.redAccent : EngineRowingUI.neonLime,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: isError ? Colors.red.shade200 : EngineRowingUI.textWhite,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// رسمة لوجو Google الأيقوني الرباعي الألوان برمجياً
// ============================================================================
class _GoogleLogoIcon extends StatelessWidget {
  final double size;
  const _GoogleLogoIcon({this.size = 20});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _GoogleLogoPainter(),
      ),
    );
  }
}

class _GoogleLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;

    final redPaint = Paint()..color = const Color(0xFFEA4335);
    final bluePaint = Paint()..color = const Color(0xFF4285F4);
    final yellowPaint = Paint()..color = const Color(0xFFFBBC05);
    final greenPaint = Paint()..color = const Color(0xFF34A853);

    final rect = Rect.fromLTWH(0, 0, w, h);

    // Blue arc + bar
    canvas.drawArc(rect, -0.785, 1.57, true, bluePaint);
    // Green arc
    canvas.drawArc(rect, 0.785, 1.57, true, greenPaint);
    // Yellow arc
    canvas.drawArc(rect, 2.356, 1.57, true, yellowPaint);
    // Red arc
    canvas.drawArc(rect, 3.927, 1.57, true, redPaint);

    // Hole center
    final holePaint = Paint()..color = EngineRowingUI.equationCardFill;
    canvas.drawCircle(Offset(w / 2, h / 2), w * 0.32, holePaint);

    // Horizontal blue bar
    final barPaint = Paint()..color = const Color(0xFF4285F4);
    final barRect = Rect.fromLTWH(w * 0.45, h * 0.38, w * 0.55, h * 0.24);
    canvas.drawRect(barRect, barPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
