import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 1. محرك التجاوب والمرونة التلقائية مع جميع الشاشات (Responsive Scaling Engine)
class RowingResponsive {
  static const double _baseWidth = 390.0;

  static double scaleFactor(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final effectiveWidth = width > 650 ? 500.0 : width;
    return (effectiveWidth / _baseWidth).clamp(0.85, 1.35);
  }

  static double sp(BuildContext context, double size) =>
      size * scaleFactor(context);

  static double dp(BuildContext context, double size) =>
      size * scaleFactor(context);
}

/// 2. محرك توحيد الأرقام والرموز بالإنجليزية ومن اليسار لليمين (English LTR Formatter)
class RowingNumberFormatter {
  /// يحول أي أرقام عربية/هندية (٠١٢٣٤٥٦٧٨٩) إلى إنجليزية (0123456789)
  static String toEnglishDigits(String input) {
    const arabicDigits = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
    const farsiDigits = ['۰', '۱', '۲', '۳', '۴', '۵', '۶', '۷', '۸', '۹'];
    var output = input;
    for (int i = 0; i < 10; i++) {
      output = output.replaceAll(arabicDigits[i], i.toString());
      output = output.replaceAll(farsiDigits[i], i.toString());
    }
    return output.replaceAll('،', '.').replaceAll('٫', '.');
  }

  /// فلتر لحقول الإدخال (TextField) يجبر الكتابة بالأرقام الإنجليزية فوراً
  static TextInputFormatter get englishDigitsInputFormatter =>
      TextInputFormatter.withFunction((oldValue, newValue) {
        final converted = toEnglishDigits(newValue.text);
        return newValue.copyWith(
          text: converted,
          selection: newValue.selection,
        );
      });
}

/// 3. ويدجت تغليف إجباري لاتجاه اليسار إلى اليمين (LTR Wrapper for Numbers & Units)
class LtrNumericBox extends StatelessWidget {
  final Widget child;
  const LtrNumericBox({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: child,
    );
  }
}

/// 4. نظام الألوان والخطوط الشامل (Design Tokens & Global Theme)
class EngineRowingUI {
  // الألوان الأساسية المعتمدة (Hex Codes)
  static const Color bgNavy = Color(0xFF0A1633);
  static const Color bgGridLine = Color(0xFF11224A);
  static const Color cardFill = Color(0xFF15264F);
  static const Color equationCardFill = Color(0xFF122147);
  static const Color toastBg = Color(0xFF050C1E);

  static const Color neonLime = Color(0xFF9ED82E);
  static const Color textWhite = Color(0xFFF2F4F8);
  static const Color labelSlate = Color(0xFF8596B8);
  static const Color captionGrey = Color(0xFF637599);
  static const Color barTrackBg = Color(0xFF162752);

  // ألوان الزونات الجديدة المعتمدة
  // اللون الفسفوري الخفيف لـ zone1
  static const Color zone1Color = Color(0xFF9ED82E);
  // اللون الأزرق المتوسط لـ zone2
  static const Color zone2Color = Color(0xFF2979FF);
  // اللون البرتقالي المتوسط لـ zone3
  static const Color zone3Color = Color(0xFFFF9100);
  // اللون البرتقالي الغامق لـ Threshold / zone4
  static const Color thresholdColor = Color(0xFFE65100);
  static const Color zone4Color = Color(0xFFF4511E);
  // اللون الأحمر الخفيف لـ zone5
  static const Color zone5Color = Color(0xFFFF5252);

  static const Map<String, Color> zoneColors = {
    'Z1': zone1Color,
    'zone1': zone1Color,
    'Z2': zone2Color,
    'zone2': zone2Color,
    'Z3': zone3Color,
    'zone3': zone3Color,
    'Z4': zone4Color,
    'zone4': zone4Color,
    'Threshold': thresholdColor,
    'threshold': thresholdColor,
    'Z5': zone5Color,
    'zone5': zone5Color,
  };

  static const String fontFamily = 'Poppins';

  /// الثيم العام لتطبيقه على مستوى التطبيق بالكامل واستبدال الألوان القديمة
  static ThemeData get globalTheme => ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: bgNavy,
        primaryColor: neonLime,
        fontFamily: fontFamily,
        colorScheme: const ColorScheme.dark(
          primary: neonLime,
          secondary: neonLime,
          surface: cardFill,
          onPrimary: bgNavy,
          onSurface: textWhite,
        ),
        cardTheme: CardThemeData(
          color: cardFill,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: bgGridLine, width: 1.0),
          ),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: bgNavy,
          foregroundColor: textWhite,
          elevation: 0,
          centerTitle: true,
          titleTextStyle: TextStyle(
            color: textWhite,
            fontSize: 18,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: cardFill,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: const BorderSide(color: bgGridLine, width: 1.5),
          ),
          titleTextStyle: const TextStyle(
            color: textWhite,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
          contentTextStyle: const TextStyle(
            color: textWhite,
            fontSize: 14,
          ),
        ),
        bottomSheetTheme: const BottomSheetThemeData(
          backgroundColor: bgNavy,
          modalBackgroundColor: bgNavy,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: neonLime,
            foregroundColor: bgNavy,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            textStyle: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 15,
            ),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: neonLime,
            foregroundColor: bgNavy,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            textStyle: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 15,
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: textWhite,
            side: const BorderSide(color: bgGridLine, width: 1.2),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            textStyle: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: cardFill,
          labelStyle: const TextStyle(color: labelSlate, fontWeight: FontWeight.w500),
          hintStyle: const TextStyle(color: captionGrey),
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: bgGridLine, width: 1.5),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: neonLime, width: 2.0),
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: bgGridLine, width: 1.5),
          ),
        ),
      );

  // أنماط الخطوط المرنة والثابتة
  static TextStyle headlineWhite(BuildContext context) => TextStyle(
        fontFamily: fontFamily,
        fontSize: RowingResponsive.sp(context, 30),
        fontWeight: FontWeight.w800,
        color: textWhite,
        height: 1.2,
        letterSpacing: -0.5,
      );

  static TextStyle headlineLime(BuildContext context) => TextStyle(
        fontFamily: fontFamily,
        fontSize: RowingResponsive.sp(context, 30),
        fontWeight: FontWeight.w800,
        color: neonLime,
        height: 1.2,
        letterSpacing: -0.5,
      );

  static TextStyle cardHeaderLabel(BuildContext context) => TextStyle(
        fontFamily: fontFamily,
        fontSize: RowingResponsive.sp(context, 16),
        fontWeight: FontWeight.w500,
        color: labelSlate,
        letterSpacing: 0.4,
      );

  static TextStyle bigMetricValue(BuildContext context,
          {bool isHighlighted = false}) =>
      TextStyle(
        fontFamily: fontFamily,
        fontSize: RowingResponsive.sp(context, 50),
        fontWeight: FontWeight.w800,
        color: isHighlighted ? neonLime : textWhite,
        letterSpacing: -1.0,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  static TextStyle footnoteCaption(BuildContext context) => TextStyle(
        fontFamily: fontFamily,
        fontSize: RowingResponsive.sp(context, 13.5),
        fontWeight: FontWeight.w400,
        color: captionGrey,
        height: 1.4,
      );

  static TextStyle analysisToastText(BuildContext context) => TextStyle(
        fontFamily: fontFamily,
        fontSize: RowingResponsive.sp(context, 17),
        fontWeight: FontWeight.w500,
        color: textWhite,
        height: 1.4,
      );

  static TextStyle progressLabel(BuildContext context) => TextStyle(
        fontFamily: fontFamily,
        fontSize: RowingResponsive.sp(context, 15),
        fontWeight: FontWeight.w500,
        color: labelSlate,
        letterSpacing: 0.5,
      );

  static TextStyle progressValue(BuildContext context) => TextStyle(
        fontFamily: fontFamily,
        fontSize: RowingResponsive.sp(context, 17),
        fontWeight: FontWeight.w600,
        color: textWhite,
        fontFeatures: const [FontFeature.tabularFigures()],
      );
}

/// 5. خلفية الشبكة الهندسية المتجاوبة (Responsive Grid Background Wrapper)
class RowingGridBackground extends StatelessWidget {
  final Widget child;
  final double maxContentWidth;

  const RowingGridBackground({
    super.key,
    required this.child,
    this.maxContentWidth = 650.0,
  });

  @override
  Widget build(BuildContext context) {
    final gridStep = RowingResponsive.dp(context, 36.0);
    return Container(
      width: double.infinity,
      height: double.infinity,
      color: EngineRowingUI.bgNavy,
      child: CustomPaint(
        painter: _GridPainter(step: gridStep),
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxContentWidth),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  final double step;
  _GridPainter({required this.step});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = EngineRowingUI.bgGridLine
      ..strokeWidth = 1.0;

    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _GridPainter oldDelegate) =>
      oldDelegate.step != step;
}

/// 6. مؤشر اتجاه وصعود وهبوط المعدلات (Rowing Trend Indicator)
enum MetricTrendDirection {
  up, // ارتفاع المعدل (أخضر فسفوري للأعلى)
  down, // انخفاض المعدل (أحمر للأسفل)
  neutral, // محايد / مستقر (خط أفقي رمادي)
}

class RowingTrendIndicator extends StatelessWidget {
  final MetricTrendDirection direction;
  final double size;

  const RowingTrendIndicator({
    super.key,
    required this.direction,
    this.size = 36.0,
  });

  @override
  Widget build(BuildContext context) {
    switch (direction) {
      case MetricTrendDirection.up:
        return Icon(
          Icons.change_history_rounded,
          color: const Color(0xFFB8F229), // أخضر فسفوري مطابق لهوية التطبيق
          size: size,
        );
      case MetricTrendDirection.down:
        return Transform.rotate(
          angle: 3.14159,
          child: Icon(
            Icons.change_history_rounded,
            color: const Color(0xFFFF4D4D), // أحمر تحذيري للانخفاض
            size: size,
          ),
        );
      case MetricTrendDirection.neutral:
        return Container(
          width: size * 0.9,
          height: size * 0.17,
          decoration: BoxDecoration(
            color: const Color(0xFF8596B8).withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(3),
          ),
        );
    }
  }
}

/// مستطيل المدخلات والمخرجات الرئيسي المرن (Responsive Metric Card - Forced English LTR)
enum MetricStatus { neutral, upArrow, fasterText }

class RowingMetricCard extends StatelessWidget {
  final String title; // مثال: 'SPLIT' أو 'STROKE RATE'
  final String unit; // مثال: '/500m' أو 'spm' أو 'W'
  final String value; // مثال: '1:53.4' أو '33'
  final bool highlightLime;
  final MetricStatus status;
  final String? footnote;
  final double? previousValue;
  final MetricTrendDirection? trendDirection;

  const RowingMetricCard({
    super.key,
    required this.title,
    required this.unit,
    required this.value,
    this.highlightLime = false,
    this.status = MetricStatus.neutral,
    this.footnote,
    this.previousValue,
    this.trendDirection,
  });

  @override
  Widget build(BuildContext context) {
    final padH = RowingResponsive.dp(context, 22);
    final padV = RowingResponsive.dp(context, 20);
    final radius = RowingResponsive.dp(context, 14);
    final cleanValue = RowingNumberFormatter.toEnglishDigits(value);
    final cleanUnit = RowingNumberFormatter.toEnglishDigits(unit);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: EdgeInsets.symmetric(horizontal: padH, vertical: padV),
          decoration: BoxDecoration(
            color: EngineRowingUI.cardFill,
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: EngineRowingUI.bgGridLine, width: 1.0),
          ),
          // إجبار اتجاه الأرقام والوحدات من اليسار لليمين دائماً (LTR)
          child: LtrNumericBox(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$title • $cleanUnit',
                  style: EngineRowingUI.cardHeaderLabel(context),
                ),
                SizedBox(height: RowingResponsive.dp(context, 8)),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            cleanValue,
                            style: EngineRowingUI.bigMetricValue(
                              context,
                              isHighlighted: highlightLime,
                            ),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: RowingResponsive.dp(context, 12)),
                    _buildStatusIndicator(context),
                  ],
                ),
              ],
            ),
          ),
        ),
        if (footnote != null && footnote!.isNotEmpty) ...[
          SizedBox(height: RowingResponsive.dp(context, 10)),
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: RowingResponsive.dp(context, 4),
            ),
            child: Text(
              RowingNumberFormatter.toEnglishDigits(footnote!),
              style: EngineRowingUI.footnoteCaption(context),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildStatusIndicator(BuildContext context) {
    if (status == MetricStatus.fasterText) {
      return Text(
        'faster',
        style: TextStyle(
          fontFamily: EngineRowingUI.fontFamily,
          fontSize: RowingResponsive.sp(context, 18),
          fontWeight: FontWeight.w500,
          color: EngineRowingUI.neonLime,
        ),
      );
    }

    MetricTrendDirection direction = MetricTrendDirection.neutral;
    if (trendDirection != null) {
      direction = trendDirection!;
    } else if (previousValue != null) {
      final currentNum = double.tryParse(value.replaceAll(RegExp(r'[^0-9.]'), ''));
      if (currentNum != null) {
        if (currentNum > previousValue!) {
          direction = MetricTrendDirection.up;
        } else if (currentNum < previousValue!) {
          direction = MetricTrendDirection.down;
        } else {
          direction = MetricTrendDirection.neutral;
        }
      }
    } else if (status == MetricStatus.upArrow) {
      direction = MetricTrendDirection.up;
    }

    return RowingTrendIndicator(
      direction: direction,
      size: RowingResponsive.dp(context, 32),
    );
  }
}

/// 7. حقل إدخال الأرقام الموحد بالإنجليزية (Rowing Numeric Input Field - Forced LTR)
class RowingNumericInputField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String unitSuffix; // مثال: 'W', 'spm', '/500m', 'bpm'
  final String? footnote;
  final ValueChanged<String>? onChanged;

  const RowingNumericInputField({
    super.key,
    required this.controller,
    required this.label,
    required this.unitSuffix,
    this.footnote,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: EdgeInsets.symmetric(
            horizontal: RowingResponsive.dp(context, 22),
            vertical: RowingResponsive.dp(context, 16),
          ),
          decoration: BoxDecoration(
            color: EngineRowingUI.cardFill,
            borderRadius: BorderRadius.circular(RowingResponsive.dp(context, 14)),
            border: Border.all(color: EngineRowingUI.bgGridLine, width: 1.0),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LtrNumericBox(
                child: Text(
                  '$label • $unitSuffix',
                  style: EngineRowingUI.cardHeaderLabel(context),
                ),
              ),
              SizedBox(height: RowingResponsive.dp(context, 6)),
              LtrNumericBox(
                child: TextField(
                  controller: controller,
                  textDirection: TextDirection.ltr,
                  textAlign: TextAlign.left,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    RowingNumberFormatter.englishDigitsInputFormatter,
                  ],
                  style: EngineRowingUI.bigMetricValue(context),
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                    hintText: '0.0',
                    hintStyle: EngineRowingUI.bigMetricValue(context).copyWith(
                      color: EngineRowingUI.captionGrey.withValues(alpha: 0.4),
                    ),
                  ),
                  onChanged: onChanged,
                ),
              ),
            ],
          ),
        ),
        if (footnote != null && footnote!.isNotEmpty) ...[
          SizedBox(height: RowingResponsive.dp(context, 8)),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: RowingResponsive.dp(context, 4)),
            child: Text(
              RowingNumberFormatter.toEnglishDigits(footnote!),
              style: EngineRowingUI.footnoteCaption(context),
            ),
          ),
        ],
      ],
    );
  }
}

/// 8. شريط القياس والتحليل المرن (Responsive Progress Bar - Forced LTR Values)
class RowingProgressBar extends StatelessWidget {
  final String label;
  final String valueText; // مثال: '36 spm' أو '400 J' أو '240 W'
  final double progress;
  final bool isLime;

  const RowingProgressBar({
    super.key,
    required this.label,
    required this.valueText,
    required this.progress,
    this.isLime = false,
  });

  @override
  Widget build(BuildContext context) {
    final barHeight = RowingResponsive.dp(context, 14);
    final cleanValue = RowingNumberFormatter.toEnglishDigits(valueText);

    return Padding(
      padding: EdgeInsets.only(bottom: RowingResponsive.dp(context, 18)),
      child: LtrNumericBox(
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Text(
                    label.toUpperCase(),
                    style: EngineRowingUI.progressLabel(context),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                SizedBox(width: RowingResponsive.dp(context, 8)),
                Text(cleanValue, style: EngineRowingUI.progressValue(context)),
              ],
            ),
            SizedBox(height: RowingResponsive.dp(context, 8)),
            ClipRRect(
              borderRadius: BorderRadius.circular(barHeight / 1.4),
              child: LinearProgressIndicator(
                value: progress.clamp(0.0, 1.0),
                minHeight: barHeight,
                backgroundColor: EngineRowingUI.barTrackBg,
                valueColor: AlwaysStoppedAnimation<Color>(
                  isLime ? EngineRowingUI.neonLime : EngineRowingUI.textWhite,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 9. مستطيل المعادلات المرن ذو الإطار المحدد (Responsive Outlined Equation Box)
class RowingEquationBox extends StatelessWidget {
  final String title;
  final String unit;
  final bool isHighlighted;

  const RowingEquationBox({
    super.key,
    required this.title,
    required this.unit,
    this.isHighlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    final activeColor =
        isHighlighted ? EngineRowingUI.neonLime : EngineRowingUI.textWhite;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        vertical: RowingResponsive.dp(context, 18),
        horizontal: RowingResponsive.dp(context, 16),
      ),
      decoration: BoxDecoration(
        color: EngineRowingUI.equationCardFill,
        borderRadius: BorderRadius.circular(RowingResponsive.dp(context, 12)),
        border: Border.all(
          color: activeColor,
          width: RowingResponsive.dp(context, 2.0),
        ),
      ),
      child: LtrNumericBox(
        child: Column(
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                title.toUpperCase(),
                style: TextStyle(
                  fontFamily: EngineRowingUI.fontFamily,
                  fontSize: RowingResponsive.sp(context, 23),
                  fontWeight: FontWeight.w800,
                  color: activeColor,
                  letterSpacing: 0.6,
                ),
              ),
            ),
            SizedBox(height: RowingResponsive.dp(context, 2)),
            Text(
              RowingNumberFormatter.toEnglishDigits(unit),
              style: TextStyle(
                fontFamily: EngineRowingUI.fontFamily,
                fontSize: RowingResponsive.sp(context, 15),
                fontWeight: FontWeight.w400,
                color: EngineRowingUI.labelSlate,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 10. مستطيل الخلاصة والتوجيه التحليلي السفلي المرن (Responsive Bottom Insight Banner)
class RowingInsightBanner extends StatelessWidget {
  final String message;

  const RowingInsightBanner({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: RowingResponsive.dp(context, 20),
        vertical: RowingResponsive.dp(context, 16),
      ),
      decoration: BoxDecoration(
        color: EngineRowingUI.toastBg,
        borderRadius: BorderRadius.circular(RowingResponsive.dp(context, 10)),
        border: Border.all(color: EngineRowingUI.bgGridLine, width: 1.0),
      ),
      child: Text(
        RowingNumberFormatter.toEnglishDigits(message),
        textAlign: TextAlign.center,
        style: EngineRowingUI.analysisToastText(context),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════
// 11. إعدادات حدة الإضاءة والألوان ومقياس التكبير العام
// ════════════════════════════════════════════════════════════════

enum DisplayIntensity { normal, bright, ultra }

final ValueNotifier<DisplayIntensity> intensityNotifier =
    ValueNotifier<DisplayIntensity>(DisplayIntensity.normal);

final ValueNotifier<double> userScaleNotifier =
    ValueNotifier<double>(1.0);

/// إضاءة فسفورية خفيفة وواضحة على حدود اللوحات تستجيب لحدة الإضاءة
BoxDecoration neonGlowBoxDecoration({
  Color? fillColor,
  Color borderColor = EngineRowingUI.neonLime,
  double borderWidth = 1.0,
  double borderRadius = 12.0,
  DisplayIntensity intensity = DisplayIntensity.normal,
  List<BoxShadow>? extraShadows,
}) {
  double blurRadius = 4.0;
  double spreadRadius = 0.5;
  Color glowColor = borderColor.withValues(alpha: 0.18);

  switch (intensity) {
    case DisplayIntensity.normal:
      blurRadius = 4.0;
      spreadRadius = 0.5;
      glowColor = borderColor.withValues(alpha: 0.18);
      break;
    case DisplayIntensity.bright:
      blurRadius = 8.0;
      spreadRadius = 1.2;
      glowColor = borderColor.withValues(alpha: 0.38);
      break;
    case DisplayIntensity.ultra:
      blurRadius = 14.0;
      spreadRadius = 2.2;
      glowColor = borderColor.withValues(alpha: 0.68);
      break;
  }

  return BoxDecoration(
    color: fillColor ?? EngineRowingUI.cardFill,
    borderRadius: BorderRadius.circular(borderRadius),
    border: Border.all(
      color: intensity == DisplayIntensity.ultra
          ? borderColor
          : (intensity == DisplayIntensity.bright
              ? borderColor.withValues(alpha: 0.85)
              : borderColor.withValues(alpha: 0.55)),
      width: intensity == DisplayIntensity.ultra ? borderWidth * 1.4 : borderWidth,
    ),
    boxShadow: [
      BoxShadow(
        color: glowColor,
        blurRadius: blurRadius,
        spreadRadius: spreadRadius,
      ),
      if (extraShadows != null) ...extraShadows,
    ],
  );
}

/// 12. حاوية التكبير والتصغير بأصابع المستخدم (Pinch-to-Zoom Area)
class PinchZoomArea extends StatelessWidget {
  final Widget child;
  final double minScale;
  final double maxScale;

  const PinchZoomArea({
    super.key,
    required this.child,
    this.minScale = 0.8,
    this.maxScale = 3.0,
  });

  @override
  Widget build(BuildContext context) {
    return InteractiveViewer(
      minScale: minScale,
      maxScale: maxScale,
      panEnabled: true,
      scaleEnabled: true,
      clipBehavior: Clip.none,
      child: child,
    );
  }
}

/// 13. خانات توزيع أحمال الزونات المتجاوبة (RowingAdaptiveZoneBoxes)
/// تمنع تماماً كسر الحروف رأسياً وتوزع الخانات أفقياً أو كشبكة حسب المساحة المتاحة
/// مع جعل خلفية منحنيات الزونات باللون الأبيض النقي (#FFFFFF) مع الحفاظ على ألوان شرايط الزونات
class RowingAdaptiveZoneBoxes extends StatelessWidget {
  final Map<String, int> zoneSeconds;
  final String? title;
  final bool showCurveChart;
  final double curveHeight;

  const RowingAdaptiveZoneBoxes({
    super.key,
    required this.zoneSeconds,
    this.title,
    this.showCurveChart = true,
    this.curveHeight = 72.0,
  });

  static const List<String> zones = [
    'Z1',
    'Z2',
    'Z3',
    'Z4',
    'Threshold',
    'Z5',
  ];

  static const Map<String, Color> zoneColorsMap = {
    'Z1': Color(0xFFB8F229),
    'Z2': Color(0xFF2979FF),
    'Z3': Color(0xFFFF9100),
    'Z4': Color(0xFFF4511E),
    'Threshold': Color(0xFFE65100),
    'Z5': Color(0xFFFF5252),
  };

  static String _formatSecs(int secs) {
    if (secs <= 0) return '00:00';
    final h = secs ~/ 3600;
    final m = (secs % 3600) ~/ 60;
    final s = secs % 60;
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final totalSecs = zones.fold<int>(0, (sum, z) => sum + (zoneSeconds[z] ?? 0));

    return ValueListenableBuilder<DisplayIntensity>(
      valueListenable: intensityNotifier,
      builder: (context, intensity, _) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final w = constraints.maxWidth;
            final isMobile = w < 620;

            final boxes = _buildZoneBoxes(context, totalSecs, isMobile, w, intensity);
            final curveWidget = showCurveChart
                ? _buildCurveChart(totalSecs, intensity)
                : null;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (title != null && title!.isNotEmpty) ...[
                  Text(
                    title!,
                    style: TextStyle(
                      fontSize: RowingResponsive.sp(context, 12),
                      fontWeight: FontWeight.bold,
                      color: EngineRowingUI.textWhite,
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                if (!isMobile && curveWidget != null)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(flex: 5, child: boxes),
                      const SizedBox(width: 12),
                      curveWidget,
                    ],
                  )
                else ...[
                  boxes,
                  if (curveWidget != null) ...[
                    const SizedBox(height: 10),
                    curveWidget,
                  ],
                ],
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildCurveChart(int totalSecs, DisplayIntensity intensity) {
    return Container(
      height: curveHeight,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: neonGlowBoxDecoration(
        fillColor: Colors.white,
        borderColor: const Color(0xFFD0D7DE),
        borderWidth: 1.2,
        borderRadius: 10,
        intensity: intensity,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.show_chart_rounded, size: 14, color: Color(0xFF1E293B)),
              SizedBox(width: 4),
              Text(
                'منحنى توزيع الزونات',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1E293B),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Expanded(
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: zones.map((z) {
                  final secs = zoneSeconds[z] ?? 0;
                  final fraction = totalSecs > 0
                      ? (secs / totalSecs).clamp(0.08, 1.0)
                      : 0.08;
                  final color = zoneColorsMap[z] ?? const Color(0xFF0A1633);

                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2.0),
                      child: Tooltip(
                        message:
                            '$z: ${totalSecs > 0 ? ((secs / totalSecs) * 100).toStringAsFixed(1) : 0}%',
                        child: Container(
                          height: (curveHeight - 34) * fraction,
                          decoration: BoxDecoration(
                            color: secs > 0 ? color : const Color(0xFFE2E8F0),
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildZoneBoxes(
    BuildContext context,
    int totalSecs,
    bool isMobile,
    double maxWidth,
    DisplayIntensity intensity,
  ) {
    if (!isMobile) {
      return Directionality(
        textDirection: TextDirection.ltr,
        child: Row(
          children: zones.map((z) {
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2.5),
                child: _buildSingleBox(context, z, totalSecs, intensity),
              ),
            );
          }).toList(),
        ),
      );
    }

    final cols = maxWidth < 380 ? 2 : 3;
    final itemWidth = (maxWidth - ((cols - 1) * 8.0)) / cols;

    return Directionality(
      textDirection: TextDirection.ltr,
      child: Wrap(
        spacing: 8.0,
        runSpacing: 8.0,
        children: zones.map((z) {
          return SizedBox(
            width: itemWidth,
            child: _buildSingleBox(context, z, totalSecs, intensity),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildSingleBox(
    BuildContext context,
    String zone,
    int totalSecs,
    DisplayIntensity intensity,
  ) {
    final secs = zoneSeconds[zone] ?? 0;
    final isZero = secs == 0;
    final color = zoneColorsMap[zone] ?? EngineRowingUI.neonLime;
    final pct = totalSecs > 0 ? ((secs / totalSecs) * 100).toStringAsFixed(1) : '0';
    final durationStr = isZero ? '-' : _formatSecs(secs);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      decoration: neonGlowBoxDecoration(
        fillColor: isZero
            ? EngineRowingUI.equationCardFill.withAlpha(160)
            : color.withAlpha(40),
        borderColor: isZero ? EngineRowingUI.bgGridLine : color,
        borderWidth: isZero ? 1.0 : 1.5,
        borderRadius: 8.0,
        intensity: intensity,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            height: 3,
            width: double.infinity,
            decoration: BoxDecoration(
              color: isZero ? Colors.transparent : color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              zone,
              maxLines: 1,
              softWrap: false,
              style: TextStyle(
                fontFamily: EngineRowingUI.fontFamily,
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: isZero ? EngineRowingUI.captionGrey : color,
                letterSpacing: 0.5,
              ),
            ),
          ),
          const SizedBox(height: 3),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              durationStr,
              maxLines: 1,
              softWrap: false,
              style: TextStyle(
                fontFamily: EngineRowingUI.fontFamily,
                fontSize: 11,
                fontWeight: FontWeight.bold,
                fontFeatures: const [FontFeature.tabularFigures()],
                color: isZero ? EngineRowingUI.captionGrey : EngineRowingUI.textWhite,
              ),
            ),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              isZero ? '0%' : '$pct%',
              maxLines: 1,
              softWrap: false,
              style: TextStyle(
                fontFamily: EngineRowingUI.fontFamily,
                fontSize: 9.5,
                fontWeight: FontWeight.w600,
                color: isZero ? EngineRowingUI.captionGrey.withValues(alpha: 0.7) : color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}


