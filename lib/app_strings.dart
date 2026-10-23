import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// نظام إدارة وتوطين النصوص (Localization & Strings Dictionary)
/// يدعم اللغة العربية (الافتراضية) والإنجليزية
class AppLanguage extends ChangeNotifier {
  static final AppLanguage instance = AppLanguage._();
  AppLanguage._();

  static const String _prefKey = 'app_language_code';

  Locale _locale = const Locale('ar');
  Locale get locale => _locale;
  bool get isArabic => _locale.languageCode == 'ar';

  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final code = prefs.getString(_prefKey);
      if (code != null && (code == 'ar' || code == 'en')) {
        _locale = Locale(code);
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> setLocale(Locale newLocale) async {
    if (_locale == newLocale) return;
    _locale = newLocale;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKey, newLocale.languageCode);
    } catch (_) {}
  }

  Future<void> toggleLanguage() async {
    final next = _locale.languageCode == 'ar' ? const Locale('en') : const Locale('ar');
    await setLocale(next);
  }
}

class AppStrings {
  final bool isArabic;
  const AppStrings(this.isArabic);

  static AppStrings of(BuildContext context) {
    return AppStrings(AppLanguage.instance.isArabic);
  }

  // ==================== General App ====================
  String get appTitle => isArabic ? 'تطبيق انجن روينج للتجديف' : 'Engine Rowing App';
  String get tabDashboard => isArabic ? 'Engine Rowing Dashboard' : 'Engine Rowing Dashboard';
  String get tabHome => isArabic ? 'الرئيسية' : 'Home';
  String get tabProgram => isArabic ? 'البرنامج' : 'Program';
  String get tabWorkouts => isArabic ? 'التمارين' : 'Workouts';
  String get tabPlayers => isArabic ? 'اللاعبين' : 'Athletes';
  String get tabSettings => isArabic ? 'الإعدادات' : 'Settings';
  String get save => isArabic ? 'حفظ' : 'Save';
  String get cancel => isArabic ? 'إلغاء' : 'Cancel';
  String get delete => isArabic ? 'حذف' : 'Delete';
  String get edit => isArabic ? 'تعديل' : 'Edit';
  String get add => isArabic ? 'إضافة' : 'Add';
  String get savedSuccessfully => isArabic ? 'تم حفظ البيانات بنجاح ✔' : 'Data saved successfully ✔';
  String get loading => isArabic ? 'جاري التحميل...' : 'Loading...';
  String get noData => isArabic ? 'لا توجد بيانات' : 'No data available';
  String get error => isArabic ? 'خطأ' : 'Error';
  String get close => isArabic ? 'إغلاق' : 'Close';
  String get back => isArabic ? 'رجوع' : 'Back';
  String get search => isArabic ? 'بحث' : 'Search';
  String get all => isArabic ? 'الكل' : 'All';
  String get minutes => isArabic ? 'دقيقة' : 'min';
  String get hours => isArabic ? 'ساعات' : 'hrs';
  String get meters => isArabic ? 'متر' : 'm';
  String get bpm => isArabic ? 'نبضة/د' : 'bpm';

  // ==================== Dashboard Strings ====================
  String get teamReadiness => isArabic ? 'نسبة الجاهزية للفريق' : 'Team Readiness';
  String get readinessScore => isArabic ? 'مؤشر الجاهزية' : 'Readiness Index';
  String get teamReadinessDesc => isArabic ? 'متوسط جاهزية جميع اللاعبين للتدريب' : 'Average readiness of all athletes';
  String get currentCycle => isArabic ? 'السيكل الحالي' : 'Current Cycle';
  String get noActiveCycle => isArabic ? 'لا يوجد سيكل نشط حالياً' : 'No active cycle currently';
  String get nextSession => isArabic ? 'الحصة التدريبية القادمة' : 'Next Session';
  String get noUpcomingSessions => isArabic ? 'لا توجد حصص مجدولة لليوم' : 'No sessions scheduled for today';
  String get efTrendTitle => isArabic ? 'اتجاه كفاءة الأداء (EF) للفريق' : 'Team Efficiency Factor (EF) Trend';
  String get efMetricDesc => isArabic ? 'المؤشر الأهم لتقييم الكفاءة الهوائية (الواط / النبض)' : 'Primary metric for aerobic efficiency (Watts / HR)';
  String get efImproving => isArabic ? 'اتجاه تصاعدي ممتاز 📈 (+تحسن في الكفاءة)' : 'Excellent upward trend 📈 (Improved efficiency)';
  String get efStable => isArabic ? 'أداء مستقر ومثالي ➡️' : 'Stable & optimal performance ➡️';
  String get efDeclining => isArabic ? 'تنبيه: انخفاض في الكفاءة 📉 (يُوصى بمراقبة الاستشفاء)' : 'Alert: Decline in efficiency 📉 (Monitor recovery)';
  String get efNoData => isArabic ? 'لا توجد بيانات كافية لحساب متوسط EF' : 'Not enough data to compute team EF trend';
  String get currentAvgEF => isArabic ? 'متوسط EF الحالي' : 'Current Team EF';
  String get baselineEF => isArabic ? 'خط الأساس لـ EF' : 'Baseline EF';
  String get readyPlayers => isArabic ? 'جاهز' : 'Ready';
  String get tiredPlayers => isArabic ? 'إجهاد' : 'Fatigued';
  String get daysRemaining => isArabic ? 'يوم متبقي' : 'days left';
  String get cycleProgress => isArabic ? 'تقدم السيكل' : 'Cycle Progress';

  // ==================== Program & Cycles Strings (المرحلة الثانية) ====================
  String get trainingCycles => isArabic ? 'سيكلات التدريب' : 'Training Cycles';
  String get cyclesSubtitle => isArabic ? 'سيكلات مرقمة (1 - 12) مع قوالب تدريب أسبوعية متكررة' : 'Cycles (1-12) with recurring weekly training templates';
  String get cycleNumber => isArabic ? 'السيكل' : 'Cycle';
  String cycleTitle(int num) => isArabic ? 'السيكل $num' : 'Cycle $num';
  String get activeCycleBadge => isArabic ? 'السيكل الشغال حالياً' : 'Currently Active Cycle';
  String get cycleDuration => isArabic ? 'المدة' : 'Duration';
  String weeksCount(int count) => isArabic ? '$count أسابيع' : '$count weeks';
  String get startDate => isArabic ? 'تاريخ البداية' : 'Start Date';
  String get endDate => isArabic ? 'تاريخ النهاية' : 'End Date';
  String get editCycleDates => isArabic ? 'تعديل تواريخ السيكل' : 'Edit Cycle Dates';
  String get cycleDateConstraint => isArabic ? 'مدة السيكل المرنة من 2 إلى 6 أسابيع' : 'Flexible cycle duration: 2 to 6 weeks';
  String get weeklyTemplateTitle => isArabic ? 'القالب الأسبوعي المتكرر' : 'Recurring Weekly Template';
  String get weeklyTemplateSubtitle => isArabic ? 'تحديد حتى 6 خانات تمرين يومية تغذي جدول التمارين تلقائياً' : 'Up to 6 slots per day feeding daily sessions automatically';
  String get daySaturday => isArabic ? 'السبت' : 'Saturday';
  String get daySunday => isArabic ? 'الأحد' : 'Sunday';
  String get dayMonday => isArabic ? 'الإثنين' : 'Monday';
  String get dayTuesday => isArabic ? 'الثلاثاء' : 'Tuesday';
  String get dayWednesday => isArabic ? 'الأربعاء' : 'Wednesday';
  String get dayThursday => isArabic ? 'الخميس' : 'Thursday';
  String get dayFriday => isArabic ? 'الجمعة' : 'Friday';
  String get addSlot => isArabic ? 'إضافة خانة تمرين' : 'Add Workout Slot';
  String get maxSlotsReached => isArabic ? 'الحد الأقصى هو 6 خانات تمرين في اليوم' : 'Maximum 6 workout slots reached for this day';
  String get slotNumber => isArabic ? 'تمرين' : 'Workout';
  String slotTitle(int index) => isArabic ? 'تمرين ${index + 1}' : 'Workout ${index + 1}';
  String get workoutTime => isArabic ? 'ميعاد التمرين بالساعة' : 'Workout Time (Hour)';
  String get selectTime => isArabic ? 'اختر الساعة' : 'Select Time';
  String get selectWorkoutType => isArabic ? 'اختر نوع التمرين' : 'Select Workout Type';
  String get selectZone => isArabic ? 'الزون المستهدف' : 'Target Zone';
  String get removeSlot => isArabic ? 'حذف الخانة' : 'Remove Slot';
  String get copyTemplateToDay => isArabic ? 'نسخ القالب ليوم آخر' : 'Copy Template to Another Day';
  String get templateSaved => isArabic ? 'تم حفظ القالب الأسبوعي وتحديث جدول التمارين' : 'Weekly template saved and schedule updated';

  // أنواع التمارين المحددة بدقة
  String get typeErg => isArabic ? 'إرج' : 'Erg';
  String get typeWater => isArabic ? 'ماء' : 'Water';
  String get typeRunning => isArabic ? 'جري' : 'Running';
  String get typeFlexibility => isArabic ? 'مرونة' : 'Flexibility';
  String get typeStrength => isArabic ? 'قوة' : 'Strength';
  String get typeFitness => isArabic ? 'لياقة' : 'Fitness';

  // ==================== Workouts Tab Strings (المرحلة الثانية) ====================
  String get todaysWorkoutsHeader => isArabic ? 'تمارين اليوم' : "Today's Workouts";
  String get todaysWorkoutsSubtitle => isArabic ? 'الحصص المجدولة لليوم من قالب السيكل النشط' : 'Sessions scheduled for today from active cycle';
  String get noWorkoutsToday => isArabic ? 'لا توجد تمارين مجدولة في برنامج اليوم (راحة)' : 'No workouts scheduled for today (Rest day)';
  String workoutTimeAndType(String time, String type) => isArabic ? '$type • الساعة $time' : '$type • $time';
  String get athletesListTitle => isArabic ? 'قائمة اللاعبين لتسجيل تمارين اليوم' : "Athletes List for Today's Workouts";
  String get tapAthleteToLogMulti => isArabic ? 'اضغط على اللاعب لفتح فورمات تمارين اليوم وحفظها' : "Tap an athlete to open today's workout forms";
  String get allWorkoutsCompleted => isArabic ? 'اكتمل تسجيل كل تمارين اليوم ✔' : 'All today workouts completed ✔';
  String partialWorkoutsCompleted(int done, int total) => isArabic ? 'تم تسجيل $done من $total تمارين' : '$done of $total workouts recorded';
  String get noWorkoutsCompletedYet => isArabic ? 'لم يبدأ التسجيل اليوم' : 'Not recorded yet today';
  String get multiEntryTitle => isArabic ? 'تسجيل تمارين اليوم للاعب' : "Today's Athlete Workout Forms";
  String formForSession(int idx, String type, String time) => isArabic ? 'تمرين ${idx + 1}: $type (الساعة $time)' : 'Workout ${idx + 1}: $type ($time)';
  String get commonDailyMetrics => isArabic ? 'المؤشرات اليومية المشتركة (HRV، النوم، الوزن، الإرهاق)' : 'Common Daily Metrics (HRV, Sleep, Weight, Fatigue)';
  String get saveAllWorkouts => isArabic ? 'حفظ جميع تمارين اليوم والعودة' : "Save All Today's Workouts & Return";
  String get playerCompletedBanner => isArabic ? 'تم إنهاء وتسجيل كل تمارين اليوم بنجاح' : "All workouts completed and logged for today";

  // القديم للتوافق
  String get todaySession => isArabic ? 'حصة اليوم' : "Today's Session";
  String get sessionNumber => isArabic ? 'الحصة' : 'Session';
  String get selectDate => isArabic ? 'تحديد التاريخ' : 'Select Date';
  String get targetZone => isArabic ? 'الزون المستهدف' : 'Target Zone';
  String get workoutType => isArabic ? 'نوع التمرين' : 'Workout Type';
  String get playersList => isArabic ? 'قائمة اللاعبين' : 'Athletes List';
  String get tapPlayerToLog => isArabic ? 'اضغط على اللاعب لإدخال بيانات الحصة' : 'Tap an athlete to enter session data';
  String get statusRecorded => isArabic ? 'تم التسجيل ✔' : 'Recorded ✔';
  String get statusPending => isArabic ? 'لم يسجل بعد' : 'Pending';
  String get addNewSession => isArabic ? 'إضافة حصة تدريبية' : 'Add Training Session';
  String get noActivePlayers => isArabic ? 'لا يوجد لاعبون نشطون حالياً' : 'No active athletes available';

  // ==================== Player Entry Form Strings ====================
  String get playerEntryTitle => isArabic ? 'تسجيل بيانات اللاعب' : 'Athlete Data Entry';
  String get targetHRRange => isArabic ? 'نطاق النبض المستهدف (كارفونين)' : 'Target HR Range (Karvonen)';
  String get karvonenFormulaDesc => isArabic ? 'محسوب بمعادلة كارفونين وفق متوسط نبض الراحة لآخر 7 أيام' : 'Calculated via Karvonen using 7-day average resting HR';
  String get maxHRLabel => isArabic ? 'أقصى نبض (MHR)' : 'Max HR (MHR)';
  String get preWorkoutSection => isArabic ? 'المؤشرات قبل التمرين (الصباحية)' : 'Pre-Workout Morning Metrics';
  String get rhrLabel => isArabic ? 'نبض الراحة (RHR)' : 'Resting HR (RHR)';
  String get rhrHint => isArabic ? 'متوسط آخر 7 أيام' : '7-day average';
  String get hrvLabel => isArabic ? 'تغير النبض (HRV)' : 'Heart Rate Var (HRV)';
  String get hrvHint => isArabic ? 'ms' : 'ms';
  String get sleepLabel => isArabic ? 'ساعات النوم' : 'Sleep Hours';
  String get sleepHint => isArabic ? 'ساعات' : 'Hours';
  String get fatigueLabel => isArabic ? 'مستوى الإرهاق' : 'Fatigue Level';
  String get fatigueHint => isArabic ? '1 (ممتاز) - 5 (مرهق)' : '1 (Fresh) - 5 (Exhausted)';
  String get weightLabel => isArabic ? 'الوزن (كجم)' : 'Weight (kg)';
  String get weightHint => isArabic ? 'كجم' : 'kg';

  String get duringWorkoutSection => isArabic ? 'الأداء أثناء التمرين' : 'During Workout Performance';
  String get avgPowerLabel => isArabic ? 'متوسط الواط' : 'Average Watts';
  String get avgPowerHint => isArabic ? 'واط' : 'Watts';
  String get maxPowerLabel => isArabic ? 'أقصى واط' : 'Max Watts';
  String get maxPowerHint => isArabic ? 'أقصى واط' : 'Max Watts';
  String get workoutHRLabel => isArabic ? 'معدل النبض' : 'Heart Rate (HR)';
  String get workoutHRHint => isArabic ? 'bpm' : 'bpm';
  String get workoutMaxHRLabel => isArabic ? 'أقصى نبض بالتمرين' : 'Workout Max HR';
  String get workoutMaxHRHint => isArabic ? 'bpm' : 'bpm';
  String get distanceLabel => isArabic ? 'المسافة بالمتر' : 'Distance in Meters';
  String get distanceHint => isArabic ? 'متر' : 'Meters';
  String get splitLabel => isArabic ? 'السبليت (ث/500م)' : 'Split (s/500m)';
  String get splitHint => isArabic ? 'ثانية أو د:ث' : 'sec or m:s';
  String get efLabel => isArabic ? 'معدل الكفاءة (EF)' : 'Efficiency Factor (EF)';
  String get efHint => isArabic ? 'واط / نبض' : 'Watts / HR';

  String get postWorkoutSection => isArabic ? 'مؤشرات بعد التمرين والاستشفاء' : 'Post-Workout & Recovery';
  String get postHRLabel => isArabic ? 'النبض فور الانتهاء' : 'Immediate Post HR';
  String get postHRHint => isArabic ? 'فورًا' : 'Immediate';
  String get recoveryHRLabel => isArabic ? 'نبض الاستشفاء' : 'Recovery Heart Rate';
  String get hr1MinLabel => isArabic ? 'نبض بعد دقيقة (الاستشفاء)' : '1-Min Recovery HR';
  String get hr1MinHint => isArabic ? 'استشفاء 60 ث' : 'Recovery 60s';

  // Key Athletes Optional Fields
  String get keyAthletesSection => isArabic ? 'مؤشرات اختيارية (NP & Decoupling)' : 'Optional Metrics (NP & Decoupling)';
  String get npWattsLabel => isArabic ? 'واط NP (اختياري)' : 'NP Watts (Optional)';
  String get npWattsHint => isArabic ? 'قراءات مفصولة بفواصل أو قيمة واحدة' : 'Comma-separated watts or single value';
  String get calculatedNP => isArabic ? 'القدرة المعيارية المحسوبة (NP)' : 'Calculated Normalized Power (NP)';
  String get decouplingHRLabel => isArabic ? 'نبض Decoupling (اختياري)' : 'Decoupling HR (Optional)';
  String get decouplingHRHint => isArabic ? 'قراءات مفصولة بفواصل' : 'Comma-separated HR values';
  String get calculatedDecoupling => isArabic ? 'نسبة الـ Decoupling المتوقعة' : 'Estimated Decoupling %';
  String get saveAndReturn => isArabic ? 'حفظ والعودة لقائمة اللاعبين' : 'Save & Return to Athletes';

  // Validation messages
  String invalidHR(String name) => isArabic ? 'نبض غير منطقي للاعب $name' : 'Unrealistic HR for athlete $name';
  String get invalidPostHR => isArabic ? 'النبض بعد التمرين أعلى من أثناء التمرين' : 'Post-workout HR is higher than workout HR';
  String get invalidRecoveryHR => isArabic ? 'نبض الاستشفاء (دقيقة) أعلى من النبض فور الانتهاء' : '1-min recovery HR cannot exceed immediate post HR';
  String get invalidFatigue => isArabic ? 'الإرهاق يجب أن يكون من 1 (ممتاز) إلى 5 (مرهق)' : 'Fatigue must be between 1 (Fresh) and 5 (Exhausted)';
  String get invalidAvgPower => isArabic ? 'متوسط الواط غير منطقي' : 'Invalid average power';
  String get invalidMaxPower => isArabic ? 'أقصى واط يجب ألا يقل عن المتوسط' : 'Max power cannot be less than average power';
  String get invalidDistance => isArabic ? 'المسافة يجب أن تكون أكبر من صفر' : 'Distance must be greater than zero';
  String get invalidEF => isArabic ? 'معدل EF غير منطقي' : 'Invalid EF value';

  // ==================== Players Tab & Profile Strings (المرحلة الثانية) ====================
  String get playersTabTitle => isArabic ? 'سجل وبوابة اللاعبين' : 'Athletes Portal & Directory';
  String get playersTabSubtitle => isArabic ? 'إدارة قائمة اللاعبين واستعراض البروفايل الفسيولوجي الكامل' : 'Manage athlete roster and explore comprehensive physiological profiles';
  String get addNewPlayer => isArabic ? 'إضافة لاعب جديد' : 'Add New Athlete';
  String get playerName => isArabic ? 'اسم اللاعب' : 'Athlete Name';
  String get athleteMhr => isArabic ? 'أقصى نبض (MHR)' : 'Max HR (MHR)';
  String get enterPlayerName => isArabic ? 'أدخل اسم اللاعب' : 'Enter athlete name';
  String get enterMhr => isArabic ? 'أدخل أقصى نبض (مثال: 195)' : 'Enter Max HR (e.g. 195)';
  String get playerAdded => isArabic ? 'تمت إضافة اللاعب بنجاح' : 'Athlete added successfully';
  String get playerStatusActive => isArabic ? 'نشط' : 'Active';
  String get playerStatusInactive => isArabic ? 'غير نشط' : 'Inactive';
  String get viewProfile => isArabic ? 'عرض الملف التفصيلي' : 'View Full Profile';
  String get athleteDetails => isArabic ? 'تفاصيل اللاعب' : 'Athlete Details';
  String get baselineMetrics => isArabic ? 'المؤشرات الأساسية' : 'Baseline Metrics';
  String get physiologicalBalance => isArabic ? 'التوازن الفسيولوجي' : 'Physiological Balance';
  String get overtrainingAlerts => isArabic ? 'تنبيهات الإجهاد والإفراط التدريبي' : 'Overtraining & Fatigue Alerts';
  String get noAlertsHealthy => isArabic ? 'لا توجد تنبيهات - المؤشرات الفسيولوجية ممتازة ✔' : 'No alerts - Physiological metrics look optimal ✔';
  String get cpTestsHistory => isArabic ? 'سجل اختبارات القدرة الحرجة (CP)' : 'Critical Power (CP) Tests';
  String get recoveryAnalytics => isArabic ? 'تحليلات الاستشفاء ونبض القلب' : 'Recovery & Heart Rate Analytics';
  String get sessionsHistory => isArabic ? 'سجل التمارين السابقة' : 'Past Workouts History';
  String get noLogsForPlayer => isArabic ? 'لا توجد تمارين مسجلة لهذا اللاعب حتى الآن' : 'No workout logs recorded for this athlete yet';

  // ==================== Settings Tab Strings ====================
  String get languageSettings => isArabic ? 'لغة التطبيق' : 'App Language';
  String get languageSwitchDesc => isArabic ? 'التبديل الفوري بين اللغة العربية والإنجليزية' : 'Toggle instantly between Arabic and English';
  String get arabic => isArabic ? 'العربية' : 'Arabic';
  String get english => isArabic ? 'الإنجليزية' : 'English';
  String get appArchitecture => isArabic ? 'بنية التطبيق' : 'App Architecture';
  String get phase2Active => isArabic ? 'المرحلة الثانية: البرنامج وقوالب السيكلات، تمارين اليوم، وبوابة اللاعبين' : 'Phase 2: Program & Cycle Templates, Daily Workouts, Athletes Gateway';
  String get phase1Active => isArabic ? 'المرحلة الأولى: لوحة انجن روينج، التمارين، والإعدادات' : 'Phase 1: Engine Rowing Dashboard, Workouts & Settings';
  String get databaseStatus => isArabic ? 'حالة قاعدة البيانات: متصلة ونشطة' : 'Database Status: Connected & Active';

  // ==================== Login & Authentication ====================
  String get loginTitle => isArabic ? 'تسجيل الدخول' : 'Sign In';
  String get loginSubtitle => isArabic ? 'مرحباً بك في منصة Engine Rowing' : 'Welcome to Engine Rowing Platform';
  String get email => isArabic ? 'البريد الإلكتروني' : 'Email Address';
  String get emailHint => 'coach@engine.rowing';
  String get password => isArabic ? 'كلمة المرور' : 'Password';
  String get passwordHint => '••••••••';
  String get rememberMe => isArabic ? 'تذكرني' : 'Remember me';
  String get signInButton => isArabic ? 'دخول' : 'Sign In';
  String get signingIn => isArabic ? 'جاري التحقق...' : 'Signing in...';
  String get forgotPasswordNote => isArabic ? 'نسيت كلمة المرور؟ تواصل مع مدربك' : 'Forgot password? Contact your coach';
  String get invalidEmail => isArabic ? 'يرجى إدخال بريد إلكتروني صحيح' : 'Please enter a valid email address';
  String get emptyPassword => isArabic ? 'يرجى إدخال كلمة المرور' : 'Please enter your password';
  String get invalidCredentials => isArabic ? 'البريد الإلكتروني أو كلمة المرور غير صحيحة' : 'Invalid email or password';
  String get accountInactive => isArabic ? 'تم إيقاف هذا الحساب. يرجى مراجعة الإدارة' : 'This account is inactive. Please contact administration';
  String get coachSubscriptionInactive => isArabic ? 'اشتراك المدرب متوقف حالياً. تواصل مع مدربك' : 'Coach subscription is inactive. Contact your coach';
  String get logout => isArabic ? 'تسجيل الخروج' : 'Log Out';
  String get logoutConfirm => isArabic ? 'هل تريد تسجيل الخروج من التطبيق؟' : 'Are you sure you want to log out?';

  // ==================== Home & Greetings ====================
  String get goodMorning => isArabic ? 'صباح الخير' : 'Good Morning';
  String get goodAfternoon => isArabic ? 'مساء الخير' : 'Good Afternoon';
  String get goodEvening => isArabic ? 'مساء الخير' : 'Good Evening';
  String greetingWithName(String name, String greeting) =>
      isArabic ? '$greeting يا $name' : '$greeting, $name';

  // ==================== Coach Messages ====================
  String get coachMessageTitle => isArabic ? 'رسالة من المدرب' : "Coach's Message";
  String get markAsRead => isArabic ? 'تمت القراءة' : 'Mark as Read';
  String get noMessages => isArabic ? 'لا توجد رسائل جديدة' : 'No new messages';

  // ==================== Highlights ====================
  String get highlightsTitle => isArabic ? 'أبرز المؤشرات (Highlights)' : 'Key Highlights';
  String get dynamicZoneHighlight => isArabic ? 'آخر زون تدريبي' : 'Latest Zone';
  String get cpHighlight => isArabic ? 'القدرة الحرجة (CP)' : 'Critical Power (CP)';
  String get wellnessHighlight => isArabic ? 'المؤشرات اليومية' : 'Daily Wellness';
  String get efTrendHighlight => isArabic ? 'كفاءة الأداء (EF)' : 'Efficiency Factor (EF)';
  String get hrUnit => isArabic ? 'نبضة/د' : 'bpm';
  String get wattsUnit => isArabic ? 'واط' : 'W';
  String get sleepUnit => isArabic ? 'س' : 'hrs';

  // ==================== Testing Dates ====================
  String get testingDatesTitle => isArabic ? 'مواعيد الاختبارات القادمة' : 'Upcoming Testing Dates';
  String get noUpcomingTests => isArabic ? 'لا توجد اختبارات مجدولة قريباً' : 'No upcoming tests scheduled';
  String get addTestingDate => isArabic ? 'إضافة موعد اختبار' : 'Schedule Test';
  String get testName => isArabic ? 'اسم الاختبار' : 'Test Name';
  String get testNameHint => isArabic ? 'مثال: 2000m Erg Test' : 'e.g. 2000m Erg Test';
  String get testDate => isArabic ? 'تاريخ الاختبار' : 'Test Date';
  String get recipients => isArabic ? 'المستهدفون' : 'Recipients';
  String get allAthletes => isArabic ? 'جميع اللاعبين' : 'All Athletes';
  String get selectAthletes => isArabic ? 'تحديد لاعبين' : 'Select Athletes';
  String get pastDateError => isArabic ? 'لا يمكن اختيار تاريخ في الماضي' : 'Test date cannot be in the past';
  String get testScheduledSuccess => isArabic ? 'تمت جدولة موعد الاختبار بنجاح' : 'Testing date scheduled successfully';
  String get testNameRequired => isArabic ? 'يرجى كتابة اسم الاختبار' : 'Test name is required';
  String get deleteTestDate => isArabic ? 'حذف الموعد' : 'Delete Test Date';

  // ==================== Admin Placeholder ====================
  String get adminPlaceholderTitle => isArabic ? 'لوحة تحكم الأدمن' : 'Admin Dashboard';
  String get adminPlaceholderDesc =>
      isArabic ? 'لوحة الإدارة والمدربين قيد التطوير وستتاح قريباً.' : 'Admin & coach management is under development and coming soon.';
}
