import 'package:flutter/material.dart';

/// نظام إدارة وتوطين النصوص (Localization & Strings Dictionary)
/// يدعم اللغة العربية (الافتراضية) والإنجليزية
class AppLanguage extends ChangeNotifier {
  static final AppLanguage instance = AppLanguage._();
  AppLanguage._();

  Locale _locale = const Locale('ar');
  Locale get locale => _locale;
  bool get isArabic => _locale.languageCode == 'ar';

  void setLocale(Locale newLocale) {
    if (_locale == newLocale) return;
    _locale = newLocale;
    notifyListeners();
  }

  void toggleLanguage() {
    if (_locale.languageCode == 'ar') {
      _locale = const Locale('en');
    } else {
      _locale = const Locale('ar');
    }
    notifyListeners();
  }
}

class AppStrings {
  final bool isArabic;
  const AppStrings(this.isArabic);

  static AppStrings of(BuildContext context) {
    return AppStrings(AppLanguage.instance.isArabic);
  }

  // General App
  String get appTitle => isArabic ? 'تطبيق Ironman للتجديف' : 'Ironman Rowing App';
  String get tabDashboard => isArabic ? 'Ironman Dashboard' : 'Ironman Dashboard';
  String get tabWorkouts => isArabic ? 'التمارين' : 'Workouts';
  String get tabSettings => isArabic ? 'الإعدادات' : 'Settings';
  String get save => isArabic ? 'حفظ' : 'Save';
  String get cancel => isArabic ? 'إلغاء' : 'Cancel';
  String get delete => isArabic ? 'حذف' : 'Delete';
  String get savedSuccessfully => isArabic ? 'تم حفظ البيانات بنجاح ✔' : 'Data saved successfully ✔';
  String get loading => isArabic ? 'جاري التحميل...' : 'Loading...';
  String get noData => isArabic ? 'لا توجد بيانات' : 'No data available';
  String get error => isArabic ? 'خطأ' : 'Error';
  String get close => isArabic ? 'إغلاق' : 'Close';

  // Dashboard Strings
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

  // Workouts Tab Strings
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

  // Player Entry Form Strings
  String get playerEntryTitle => isArabic ? 'تسجيل بيانات اللاعب' : 'Athlete Data Entry';
  String get targetHRRange => isArabic ? 'نطاق النبض المستهدف' : 'Target HR Range';
  String get maxHRLabel => isArabic ? 'أقصى نبض (MHR)' : 'Max HR (MHR)';
  String get preWorkoutSection => isArabic ? 'المؤشرات قبل التمرين (الصباحية)' : 'Pre-Workout Morning Metrics';
  String get rhrLabel => isArabic ? 'نبض الراحة (RHR)' : 'Resting HR (RHR)';
  String get rhrHint => isArabic ? 'نبض قبل التمرين' : 'Pre-workout pulse';
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
  String get workoutHRLabel => isArabic ? 'متوسط النبض' : 'Workout Avg HR';
  String get workoutHRHint => isArabic ? 'bpm' : 'bpm';
  String get workoutMaxHRLabel => isArabic ? 'أقصى نبض بالتمرين' : 'Workout Max HR';
  String get workoutMaxHRHint => isArabic ? 'bpm' : 'bpm';
  String get distanceLabel => isArabic ? 'المسافة' : 'Distance (m)';
  String get distanceHint => isArabic ? 'متر' : 'Meters';
  String get splitLabel => isArabic ? 'الاسبليت (ث/500م)' : 'Split (s/500m)';
  String get splitHint => isArabic ? 'ثانية' : 'sec';
  String get efLabel => isArabic ? 'معدل الكفاءة (EF)' : 'Efficiency Factor (EF)';
  String get efHint => isArabic ? 'واط / نبض' : 'Watts / HR';

  String get postWorkoutSection => isArabic ? 'مؤشرات بعد التمرين والاستشفاء' : 'Post-Workout & Recovery';
  String get postHRLabel => isArabic ? 'النبض فور الانتهاء' : 'Immediate Post HR';
  String get postHRHint => isArabic ? 'فورًا' : 'Immediate';
  String get hr1MinLabel => isArabic ? 'نبض بعد دقيقة' : '1-Min Recovery HR';
  String get hr1MinHint => isArabic ? 'استشفاء 60 ث' : 'Recovery 60s';

  // Key Athletes Optional Fields
  String get keyAthletesSection => isArabic ? 'مؤشرات اللاعبين الأساسيين (اختياري)' : 'Key Athletes Metrics (Optional)';
  String get npWattsLabel => isArabic ? 'واط NP (قراءات متعددة)' : 'NP Watts (Multiple Readings)';
  String get npWattsHint => isArabic ? 'أدخل قراءات مفصولة بفواصل: 210, 220, 235...' : 'Comma-separated watts: 210, 220, 235...';
  String get calculatedNP => isArabic ? 'القدرة المعيارية المحسوبة (NP)' : 'Calculated Normalized Power (NP)';
  String get decouplingHRLabel => isArabic ? 'نبض Decoupling (قراءات متعددة)' : 'Decoupling HR (Multiple Readings)';
  String get decouplingHRHint => isArabic ? 'أدخل قراءات مفصولة بفواصل: 145, 150, 156...' : 'Comma-separated HR: 145, 150, 156...';
  String get calculatedDecoupling => isArabic ? 'نسبة الـ Decoupling المتوقعة' : 'Estimated Decoupling %';
  String get saveAndReturn => isArabic ? 'حفظ البيانات والعودة' : 'Save Data & Return';

  // Validation messages
  String invalidHR(String name) => isArabic ? 'نبض غير منطقي للاعب $name' : 'Unrealistic HR for athlete $name';
  String get invalidPostHR => isArabic ? 'النبض بعد التمرين أعلى من أثناء التمرين' : 'Post-workout HR is higher than workout HR';
  String get invalidRecoveryHR => isArabic ? 'نبض الاستشفاء (دقيقة) أعلى من النبض فور الانتهاء' : '1-min recovery HR cannot exceed immediate post HR';
  String get invalidFatigue => isArabic ? 'الإرهاق يجب أن يكون من 1 (ممتاز) إلى 5 (مرهق)' : 'Fatigue must be between 1 (Fresh) and 5 (Exhausted)';
  String get invalidAvgPower => isArabic ? 'متوسط الواط غير منطقي' : 'Invalid average power';
  String get invalidMaxPower => isArabic ? 'أقصى واط يجب ألا يقل عن المتوسط' : 'Max power cannot be less than average power';
  String get invalidDistance => isArabic ? 'المسافة يجب أن تكون أكبر من صفر' : 'Distance must be greater than zero';
  String get invalidEF => isArabic ? 'معدل EF غير منطقي' : 'Invalid EF value';

  // Settings Tab Strings
  String get languageSettings => isArabic ? 'لغة التطبيق' : 'App Language';
  String get languageSwitchDesc => isArabic ? 'التبديل الفوري بين اللغة العربية والإنجليزية' : 'Toggle instantly between Arabic and English';
  String get arabic => isArabic ? 'العربية' : 'Arabic';
  String get english => isArabic ? 'الإنجليزية' : 'English';
  String get appArchitecture => isArabic ? 'بنية المرحلة الأولى' : 'Phase 1 Architecture';
  String get phase1Active => isArabic ? 'المرحلة الأولى: لوحة Ironman، التمارين، والإعدادات' : 'Phase 1: Ironman Dashboard, Workouts & Settings';
  String get databaseStatus => isArabic ? 'حالة قاعدة البيانات: متصلة ونشطة' : 'Database Status: Connected & Active';
}
