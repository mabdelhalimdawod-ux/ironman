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
  String get currentCycle => isArabic ? 'الدورة المرحلية الحالية' : 'Current Phase Cycle';
  String get noActiveCycle => isArabic ? 'لا توجد دورة مرحلية نشطة حالياً' : 'No active phase cycle currently';
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
  String get cycleProgress => isArabic ? 'تقدم الدورة المرحلية' : 'Phase Cycle Progress';

  // ==================== Program & Cycles Strings (المرحلة الثانية) ====================
  String get trainingCycles => isArabic ? 'الدورات المرحلية للتدريب' : 'Training Phase Cycles';
  String get cyclesSubtitle => isArabic ? 'نظام الدورات المرحلية والدورات الأسبوعية' : 'Training Phase Cycles & Weekly Microcycles';
  String get cycleNumber => isArabic ? 'الدورة المرحلية' : 'Phase Cycle';
  String cycleTitle(int num) => isArabic ? 'الدورة المرحلية $num' : 'Phase Cycle $num';
  String get addCycle => isArabic ? 'إضافة دورة مرحلية جديدة' : 'Add New Phase Cycle';
  String get deleteCycle => isArabic ? 'حذف الدورة المرحلية' : 'Delete Phase Cycle';
  String get deleteCycleConfirm => isArabic ? 'هل أنت متأكد من حذف هذه الدورة المرحلية؟' : 'Are you sure you want to delete this phase cycle?';
  String get cannotDeleteLastCycle => isArabic ? 'لا يمكن حذف الدورة المرحلية الوحيدة المتبقية' : 'Cannot delete the only remaining phase cycle';
  String get cycleAddedSuccess => isArabic ? 'تم إضافة دورة مرحلية جديدة بنجاح' : 'New phase cycle added successfully';
  String get activeCycleBadge => isArabic ? 'الدورة المرحلية الشغالة حالياً' : 'Currently Active Phase Cycle';
  String get cycleDuration => isArabic ? 'المدة' : 'Duration';
  String weeksCount(int count) => isArabic ? '$count أسابيع' : '$count weeks';
  String get startDate => isArabic ? 'تاريخ البداية' : 'Start Date';
  String get endDate => isArabic ? 'تاريخ النهاية' : 'End Date';
  String get editCycleDates => isArabic ? 'تعديل تواريخ الدورة المرحلية' : 'Edit Phase Cycle Dates';
  String get cycleDateConstraint => isArabic ? 'مدة الدورة المرحلية المرنة من 2 إلى 6 أسابيع' : 'Flexible phase cycle duration: 2 to 6 weeks';
  String get trainingLocation => isArabic ? 'منطقة أو مكان التدريب' : 'Training Location';
  String get trainingLocationHint => isArabic ? 'مثال: مجرى التجديف الدولي' : 'e.g. International Rowing Course';
  String get creationDate => isArabic ? 'تاريخ الإنشاء' : 'Created Date';
  String get lastEditDate => isArabic ? 'آخر تعديل' : 'Last Edit';
  String get weeksCountCalculated => isArabic ? 'عدد الدورات الأسبوعية بالدورة المرحلية' : 'Total Weeks in Phase Cycle';
  String get enterCycle => isArabic ? 'دخول' : 'Enter';
  String get comment => isArabic ? 'تعليق' : 'Comment';
  String get addComment => isArabic ? 'إضافة تعليق' : 'Add Comment';
  String get physiologicalNote => isArabic ? 'ملاحظة فسيولوجية' : 'Physiological Note';
  String get technicalNote => isArabic ? 'ملاحظة فنية' : 'Technical Note';
  String get addNote => isArabic ? 'إضافة ملاحظة' : 'Add Note';
  String get testDatesTitle => isArabic ? 'تواريخ التستات المقررة للدورة المرحلية' : 'Scheduled Phase Cycle Tests';
  String get zoneParticipationTitle => isArabic ? 'نسب مشاركة الزونات بالدورة المرحلية' : 'Zone Distribution';

  // المستوى 2: الدورات الأسبوعية الأساسية والفرعية
  String get basicWeeklyCycleTitle => isArabic ? 'الدورة التدريبية الأسبوعية الأساسية' : 'Basic Weekly Training Cycle';
  String get secondaryWeeklyCycleTitle => isArabic ? 'الدورة التدريبية الأسبوعية الفرعية (تستات وتهدئة)' : 'Secondary Weekly Training Cycle (Taper & Tests)';
  String get basicRepsCount => isArabic ? 'عدد تكرارات الدورة الأساسية' : 'Basic Cycle Repetitions';
  String get secondaryRepsCount => isArabic ? 'عدد تكرارات الدورة الفرعية' : 'Secondary Cycle Repetitions';
  String get repsMismatchWarning => isArabic
      ? 'تنبيه: مجموع تكرارات الدورة الأساسية والفرعية لا يساوي أسابيع الدورة المرحلية الكلية!'
      : 'Alert: Sum of basic and secondary cycle repetitions does not equal total phase cycle weeks!';
  String get dispatchScheduleTitle => isArabic ? 'موعد إرسال مضمون اليوم التدريبي للاعبين' : 'Weekly Schedule Dispatch';
  String get dispatchTime => isArabic ? 'وقت الإرسال' : 'Dispatch Time';
  String get dispatchDate => isArabic ? 'تاريخ الإرسال' : 'Dispatch Date';
  String get dayDatesInCycle => isArabic ? 'تواريخ هذا اليوم داخل الدورة المرحلية' : 'Dates in Phase Cycle';
  String get pastDateBadge => isArabic ? 'منقضي' : 'Past';
  String get sessionsCountLabel => isArabic ? 'عدد الحصص' : 'Sessions';

  // المستوى 3: الحصص التدريبية
  String get daySessionsPageTitle => isArabic ? 'الحصص التدريبية لليوم' : 'Daily Training Sessions';
  String get addSession => isArabic ? 'إضافة حصة تدريبية' : 'Add Training Session';
  String get removeSession => isArabic ? 'حذف الحصة' : 'Delete Session';
  String get removeSessionConfirm => isArabic ? 'هل تريد حذف هذه الحصة وجميع تمارينها؟' : 'Delete this session and all its workouts?';
  String sessionNumberTitle(int index) => isArabic ? 'الحصة ${index + 1}' : 'Session ${index + 1}';
  String get sessionTime => isArabic ? 'وقت الحصة' : 'Session Time';
  String get noSessionsForDay => isArabic ? 'لا توجد حصص تدريبية مجدولة لهذا اليوم (يوم راحة)' : 'No sessions scheduled for this day (Rest day)';

  // المستوى 4: تفاصيل التمارين
  String get workoutsPageTitle => isArabic ? 'تمارين الحصة التدريبية' : 'Session Workouts';
  String get warmupSection => isArabic ? '1. الإحماء' : '1. Warm-up';
  String get mainWorkoutSection => isArabic ? '2. التمرين الرئيسي' : '2. Main Workout';
  String get cooldownSection => isArabic ? '3. التهدئة' : '3. Cool-down';
  String get warmupTime => isArabic ? 'وقت الإحماء' : 'Time';
  String get warmupDuration => isArabic ? 'مدة زمن الإحماء' : 'Duration';
  String get warmupHR => isArabic ? 'نسبة نبض الإحماء' : 'HR %';
  String get warmupDistance => isArabic ? 'مسافة الإحماء (متر)' : 'Distance (m)';
  String get warmupKind => isArabic ? 'نوع الإحماء' : 'Type';
  String get addWarmup => isArabic ? 'إضافة إحماء جديد' : 'Add Warm-up';

  String get mainTime => isArabic ? 'وقت التمرين الرئيسي' : 'Time';
  String get mainDuration => isArabic ? 'مدة زمن التمرين' : 'Duration';
  String get mainDistance => isArabic ? 'مسافة التمرين (متر)' : 'Distance (m)';
  String get mainReps => isArabic ? 'عدد تكرارات التمرين' : 'Reps';
  String get mainHR => isArabic ? 'نسبة النبض للتمرين الرئيسي' : 'HR %';
  String get mainKind => isArabic ? 'نوع التمرين الرئيسي' : 'Type';
  String get addMainWorkout => isArabic ? 'إضافة تمرين رئيسي جديد' : 'Add Main Workout';

  String get cooldownTime => isArabic ? 'وقت التهدئة' : 'Time';
  String get cooldownDuration => isArabic ? 'مدة زمن التهدئة' : 'Duration';
  String get cooldownHR => isArabic ? 'نسبة نبض التهدئة' : 'HR %';
  String get cooldownDistance => isArabic ? 'مسافة التهدئة (متر)' : 'Distance (m)';
  String get cooldownKind => isArabic ? 'نوع التهدئة' : 'Type';
  String get addCooldown => isArabic ? 'إضافة تهدئة جديدة' : 'Add Cool-down';

  String get workoutDetails => isArabic ? 'ملاحظات / تفاصيل' : 'Details / Notes';
  String get weeklyTemplateTitle => isArabic ? 'القالب الأسبوعي للحصص والتمارين' : 'Weekly Sessions & Workouts Template';
  String get weeklyTemplateSubtitle => isArabic ? 'تنظيم الحصص اليومية والتمارين التابعة لكل حصة' : 'Organize daily sessions and workouts within each session';
  String get addWorkoutToSession => isArabic ? 'إضافة تمرين للحصة' : 'Add Workout to Session';
  String get daySaturday => isArabic ? 'السبت' : 'Saturday';
  String get daySunday => isArabic ? 'الأحد' : 'Sunday';
  String get dayMonday => isArabic ? 'الإثنين' : 'Monday';
  String get dayTuesday => isArabic ? 'الثلاثاء' : 'Tuesday';
  String get dayWednesday => isArabic ? 'الأربعاء' : 'Wednesday';
  String get dayThursday => isArabic ? 'الخميس' : 'Thursday';
  String get dayFriday => isArabic ? 'الجمعة' : 'Friday';
  String get copyTemplateToDay => isArabic ? 'نسخ القالب ليوم آخر' : 'Copy Template to Another Day';
  String get templateSaved => isArabic ? 'تم حفظ القالب وتحديث جدول التمارين' : 'Template saved successfully';

  // أنواع التمارين المحددة بدقة
  String get typeErg => isArabic ? 'إرج' : 'Erg';
  String get typeWater => isArabic ? 'ماء' : 'Water';
  String get typeRunning => isArabic ? 'جري' : 'Running';
  String get typeFlexibility => isArabic ? 'مرونة' : 'Flexibility';
  String get typeStrength => isArabic ? 'قوة' : 'Strength';
  String get typeFitness => isArabic ? 'لياقة' : 'Fitness';

  // ==================== Workouts Tab Strings (المرحلة الثانية) ====================
  String get todaysWorkoutsHeader => isArabic ? 'تمارين اليوم' : "Today's Workouts";
  String get todaysWorkoutsSubtitle => isArabic ? 'الحصص المجدولة لليوم من قالب الدورة المرحلية النشطة' : 'Sessions scheduled for today from active phase cycle';
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
  String get maxSlotsReached => isArabic ? 'تم الوصول للحد الأقصى للخانة (6 خانات)' : 'Max slots reached (6 slots)';
  String get addSlot => isArabic ? 'إضافة خانة' : 'Add Slot';
  String slotTitle(int idx) => isArabic ? 'تمرين ${idx + 1}' : 'Workout ${idx + 1}';
  String get removeSlot => isArabic ? 'حذف الخانة' : 'Remove Slot';
  String get workoutTime => isArabic ? 'وقت التمرين' : 'Workout Time';
  String get selectZone => isArabic ? 'اختر الزون' : 'Select Zone';
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
  String get mhrFieldLabel => isArabic ? 'أقصى نبض (MHR)' : 'Max HR (MHR)';
  String get mhrFieldHint => 'bpm';
  String get preWorkoutSection => isArabic ? 'المؤشرات قبل التمرين (الصباحية)' : 'Pre-Workout Morning Metrics';
  String get rhrLabel => isArabic ? 'نبض الراحة (RHR)' : 'Resting HR (RHR)';
  String get rhrHint => isArabic ? 'متوسط آخر 7 أيام' : '7-day average';
  String get morningRHRLabel => isArabic ? 'نبض الراحة الصباحي (RHR)' : 'Morning Resting HR (RHR)';
  String get morningRHRHint => 'bpm';
  String get autoZoneBadgeLabel => isArabic ? 'الزون المحسوب' : 'Calculated Zone';
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
  String get phase2Active => isArabic ? 'المرحلة الثانية: البرنامج وقوالب الدورات المرحلية، تمارين اليوم، وبوابة اللاعبين' : 'Phase 2: Program & Phase Cycle Templates, Daily Workouts, Athletes Gateway';
  String get phase1Active => isArabic ? 'المرحلة الأولى: لوحة انجن روينج، التمارين، والإعدادات' : 'Phase 1: Engine Rowing Dashboard, Workouts & Settings';
  String get databaseStatus => isArabic ? 'حالة قاعدة البيانات: متصلة ونشطة' : 'Database Status: Connected & Active';

  // ==================== Login & Authentication ====================
  String get authBrandTitle => 'ENGINE ROWING';
  String get authBrandSubtitle =>
      isArabic ? 'منصة التدريب وتحليل الأداء الذكي' : 'Smart Training & Performance Analytics';
  String get loginTab => isArabic ? 'تسجيل الدخول' : 'Sign In';
  String get signUpTab => isArabic ? 'إنشاء حساب' : 'Sign Up';
  String get loginTitle => isArabic ? 'تسجيل الدخول' : 'Sign In';
  String get loginSubtitle => isArabic ? 'مرحباً بك في منصة Engine Rowing' : 'Welcome to Engine Rowing Platform';
  String get email => isArabic ? 'البريد الإلكتروني' : 'Email Address';
  String get emailHint => 'coach@engine.rowing';
  String get password => isArabic ? 'كلمة المرور' : 'Password';
  String get passwordHint => '••••••••';
  String get firstName => isArabic ? 'الاسم الأول' : 'First Name';
  String get lastName => isArabic ? 'اسم العائلة' : 'Last Name';
  String get confirmPassword => isArabic ? 'تأكيد كلمة المرور' : 'Confirm Password';
  String get accountType => isArabic ? 'نوع الحساب' : 'Account Type';
  String get roleAthlete => isArabic ? 'لاعب' : 'Athlete';
  String get roleCoach => isArabic ? 'مدرب' : 'Coach';
  String get agreeToTerms => isArabic ? 'أوافق على الشروط والأحكام' : 'I agree to the Terms & Conditions';
  String get termsAndConditionsTitle => isArabic ? 'الشروط والأحكام' : 'Terms & Conditions';
  String get termsComingSoon => isArabic ? 'الشروط والأحكام ستتوفر قريباً.' : 'Terms and conditions coming soon.';
  String get continueWithGoogle => isArabic ? 'المتابعة باستخدام Google' : 'Continue with Google';
  String get googleComingSoon => isArabic ? 'ميزة تسجيل الدخول عبر Google ستتوفر قريباً.' : 'Google Sign-In is coming soon.';
  String get forgotPasswordTitle => isArabic ? 'استعادة كلمة المرور' : 'Forgot Password';
  String get forgotPasswordDialogText => isArabic
      ? 'يرجى التواصل مع المدرب أو إدارة النظام لإعادة تعيين كلمة المرور الخاصة بحسابك.'
      : 'Please contact your coach or system administrator to reset your password.';
  String get rememberMe => isArabic ? 'تذكرني' : 'Remember me';
  String get signInButton => isArabic ? 'دخول' : 'Sign In';
  String get signingIn => isArabic ? 'جاري التحقق...' : 'Signing in...';
  String get createAccountButton => isArabic ? 'إنشاء حساب جديد' : 'Create Account';
  String get creatingAccount => isArabic ? 'جاري إنشاء الحساب...' : 'Creating account...';
  String get forgotPasswordNote => isArabic ? 'نسيت كلمة المرور؟ تواصل مع مدربك' : 'Forgot password? Contact your coach';
  String get invalidEmail => isArabic ? 'يرجى إدخال بريد إلكتروني صحيح' : 'Please enter a valid email address';
  String get emptyPassword => isArabic ? 'يرجى إدخال كلمة المرور' : 'Please enter your password';
  String get invalidCredentials => isArabic ? 'البريد الإلكتروني أو كلمة المرور غير صحيحة' : 'Invalid email or password';
  String get accountInactive => isArabic ? 'تم إيقاف هذا الحساب. يرجى مراجعة الإدارة' : 'This account is inactive. Please contact administration';
  String get awaitingActivationError => isArabic ? 'حسابك بانتظار التفعيل من الإدارة' : 'Your account is awaiting admin activation';
  String get coachSubscriptionInactive => isArabic ? 'اشتراك المدرب متوقف حالياً. تواصل مع مدربك' : 'Coach subscription is inactive. Contact your coach';
  String get signUpSuccessTitle => isArabic ? 'تم إنشاء الحساب بنجاح!' : 'Account Created Successfully!';
  String get signUpSuccessMessage => isArabic
      ? 'تم تسجيل حسابك بنجاح. حسابك الآن بانتظار التفعيل من إدارة النظام، وستتمكن من تسجيل الدخول فور تفعيله.'
      : 'Your account was created successfully and is awaiting admin activation. You can sign in once activated.';
  String get emailAlreadyExists => isArabic ? 'هذا البريد الإلكتروني مسجل بالفعل' : 'This email is already registered';
  String get passwordMismatch => isArabic ? 'كلمتا المرور غير متطابقتين' : 'Passwords do not match';
  String get passwordTooShort => isArabic ? 'كلمة المرور يجب ألا تقل عن 6 أحرف' : 'Password must be at least 6 characters';
  String get mustAcceptTerms => isArabic ? 'يجب الموافقة على الشروط والأحكام للمتابعة' : 'You must accept the Terms & Conditions';
  String get fieldRequired => isArabic ? 'هذا الحقل مطلوب' : 'This field is required';
  String get orDivider => isArabic ? 'أو' : 'OR';
  String get ok => isArabic ? 'حسناً' : 'OK';
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

  // ==================== Metrics Curves Strings (المنحنيات الخمسة) ====================
  String get metricsCurvesTitle => isArabic ? 'منحنيات مؤشرات التدريب' : 'Training Metrics Curves';
  String get metricsCurvesSubtitle => isArabic ? 'تحليل بياني ذكي وتطور الأداء الفسيولوجي' : 'Smart analytics & physiological performance curves';
  String get curveEF => isArabic ? 'معامل الكفاءة (EF)' : 'Efficiency Factor (EF)';
  String get curveWatts => isArabic ? 'القدرة (الواط)' : 'Power (Watts)';
  String get curveDecoupling => isArabic ? 'التفكك القلبي (Decoupling)' : 'Cardiac Decoupling';
  String get curveHR => isArabic ? 'النبض (Heart Rate)' : 'Heart Rate';
  String get curveZone => isArabic ? 'زون كيرف (Zone Curve)' : 'Zone Curve';
  String get zoneCurvePurpose => isArabic ? 'مراقبة تحسن الواط في كل زون تدريبي على مدار الفترة' : 'Track watts progression across training zones over time';
  String get zoneCurveSubtitle => isArabic ? 'منحنى الزونات الخمسة بمعادلة كارفونين التلقائية' : '5-zone curve with auto Karvonen calculation';
  String get selectZonesPrompt => isArabic ? 'علّم الزونات لعرض خطوطها في المنحنى:' : 'Select zones to plot on the curve:';
  String get zoneNoData => isArabic ? 'لا توجد بيانات' : 'No data';
  String get exportExcel => isArabic ? 'تصدير Excel' : 'Export Excel';
  String get exportExcelDone => isArabic ? 'تم تصدير الزونات المعلّمة بنجاح' : 'Checked zones exported successfully';
  String get selectAtLeastOneZone => isArabic ? 'يرجى تعليم زون واحد على الأقل للعرض والتصدير' : 'Please check at least one zone to display & export';
  String get periodLast7Days => isArabic ? '7 أيام' : '7 Days';
  String get periodLast30Days => isArabic ? '30 يوم' : '30 Days';
  String get periodLast90Days => isArabic ? '90 يوم' : '90 Days';
  String get periodAllTime => isArabic ? 'الكل' : 'All Time';
  String get periodCustomRange => isArabic ? 'تحديد فترة' : 'Custom';
  String get avgWattsLabel => isArabic ? 'متوسط الواط' : 'Avg Watts';
  String get maxWattsLabel => isArabic ? 'أقصى واط' : 'Max Watts';
  String get autoKarvonenNote => isArabic ? 'الزون محسوب تلقائياً من النبض بمعادلة كارفونين' : 'Zone is automatically calculated from HR via Karvonen';
  String get dailyAggregationNote => isArabic ? 'كل نقطة تمثل متوسط الواط لورك أوت اليوم لنفس الزون' : 'Each point represents daily average watts for the zone';

  // ==================== Hamburger Menu Hub Strings ====================
  String get hamburgerTitle => isArabic ? 'لوحة التحكم والعمليات' : 'Command & Operations Hub';
  String get hamburgerSubtitle => isArabic ? 'إدارة التحليلات، الحسابات، الأجهزة، والتقارير' : 'Analytics, profiles, hardware & reports management';
  String get multiDashboardNav => isArabic ? 'الانتقال بين شاشات التحليل المعقدة' : 'Multi-Dashboard Navigation';
  String get physicalPerformance => isArabic ? 'شاشة الأداء البدني (النبض، السرعة، المسافة)' : 'Physical Performance (HR, Speed, Distance)';
  String get analyticsDashboard => isArabic ? 'شاشة التحليلات المتقدمة' : 'Advanced Analytics Dashboard';
  String get medicalReport => isArabic ? 'التقرير الطبي (مستويات الإرهاق والاستشفاء والإصابات)' : 'Medical Report (Fatigue, Recovery & Injuries)';
  String get peerDataComparison => isArabic ? 'مقارنة بيانات وأداء اللاعبين' : 'Athlete Peer Comparison';
  String get rosterManagement => isArabic ? 'إدارة وتبديل الحسابات (Profiles & Roster)' : 'Profiles & Team Roster Management';
  String get switchAthlete => isArabic ? 'تبديل اللاعب السريع' : 'Quick Athlete Switch';
  String get hardwareIntegration => isArabic ? 'التحكم في أدوات التتبع وأجهزة الاستشعار' : 'Hardware & Sensor Integration';
  String get coachConnection => isArabic ? 'فحص اتصال اللاعب بالمدرب' : 'Coach-Athlete Connection Status';
  String get sensorCalibration => isArabic ? 'معايرة المستشعرات والاتصال بالبلوتوث' : 'Sensor Calibration & Bluetooth Pairing';
  String get cloudSync => isArabic ? 'مزامنة البيانات السحابية' : 'Cloud Data Sync';
  String get metricsCurvesShortcut => isArabic ? 'لوحة المنحنيات (اختصارات جميع المنحنيات)' : 'Metrics Curves Hub (All Curves)';
  String get advancedDataExport => isArabic ? 'تصدير التقارير المتقدمة' : 'Advanced Data Export';
  String get exportToExcel => isArabic ? 'تحويل البيانات إلى ملف Excel' : 'Export Data to Excel (.xlsx)';
  String get exportToPdf => isArabic ? 'تحويل البيانات إلى تقرير PDF' : 'Export Report to PDF';
  String get shareReportAction => isArabic ? 'مشاركة التقرير عبر البريد أو الفريق' : 'Share Report via Email / Chat';

  // ==================== Display Settings, Zoom & Intensity ====================
  String get displayScaleTitle => isArabic ? 'مقياس الرؤية والتكبير' : 'Display Scale & Zoom';
  String get displayScaleDesc => isArabic ? 'تكبير أو تصغير عناصر الواجهة للموبايل' : 'Scale UI elements for mobile';
  String get colorIntensityTitle => isArabic ? 'حدة الألوان والإضاءة' : 'Color & Light Intensity';
  String get colorIntensityDesc => isArabic ? 'التحكم في قوة إضاءة الخطوط والأرقام والحدود' : 'Control brightness & contrast of text & neon borders';
  String get intensityNormal => isArabic ? 'عادي (متوازن)' : 'Normal';
  String get intensityBright => isArabic ? 'ساطع (واضح)' : 'Bright';
  String get intensityUltra => isArabic ? 'فائق الإضاءة (نيون)' : 'Ultra Neon';
  String get pinchZoomHint => isArabic ? 'يمكنك التكبير والتصغير بأصابعك على الشاشة' : 'Pinch with two fingers to zoom anywhere';
  String get defaultBoardName => isArabic ? 'إحماء' : 'Warm-up';
}
