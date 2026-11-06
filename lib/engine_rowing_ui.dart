import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// خيارات حدة الألوان والسطوع والإضاءة الفسفورية
enum DisplayIntensity { normal, high, ultra }

/// 1. محرك التجاوب والمرونة التلقائية مع جميع الشاشات (Responsive Scaling Engine)
class RowingResponsive {
  static const double _baseWidth = 390.0;

  /// مؤشر نسبة التكبير التي يختارها المستخدم يدوياً من القائمة المنسدلة
  static final ValueNotifier<double> userScaleNotifier = ValueNotifier<double>(1.0);

  /// مؤشر مستوى حدة الألوان والإضاءة الفسفورية
  static final ValueNotifier<DisplayIntensity> intensityNotifier =
      ValueNotifier<DisplayIntensity>(DisplayIntensity.normal);

  static double scaleFactor(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final effectiveWidth = width > 650 ? 500.0 : width;
    final autoScale = (effectiveWidth / _baseWidth).clamp(0.85, 1.35);
    return autoScale * userScaleNotifier.value;
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

  static const Color neonLime = Color(0xFFB8F229);
  static const Color textWhite = Color(0xFFF2F4F8);
  static const Color labelSlate = Color(0xFF8596B8);
  static const Color captionGrey = Color(0xFF637599);
  static const Color barTrackBg = Color(0xFF162752);

  // ألوان الزونات الجديدة المعتمدة
  // اللون الفسفوري الخفيف لـ zone1
  static const Color zone1Color = Color(0xFFB8F229);
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

  /// تصميم إضاءة فسفورية خفيفة أو واضحة على حدود اللوحات مع الاستجابة لمستوى الإضاءة
  static BoxDecoration neonGlowBoxDecoration({
    Color backgroundColor = equationCardFill,
    Color? borderColor,
    double borderRadius = 12.0,
    DisplayIntensity? intensity,
  }) {
    final curIntensity = intensity ?? RowingResponsive.intensityNotifier.value;
    final baseBorder = borderColor ?? neonLime;
    double borderOpacity = 0.50;
    double blurRadius = 6.0;
    double spreadRadius = 0.5;

    switch (curIntensity) {
      case DisplayIntensity.normal:
        borderOpacity = 0.50;
        blurRadius = 6.0;
        spreadRadius = 0.5;
        break;
      case DisplayIntensity.high:
        borderOpacity = 0.80;
        blurRadius = 10.0;
        spreadRadius = 1.0;
        break;
      case DisplayIntensity.ultra:
        borderOpacity = 1.0;
        blurRadius = 16.0;
        spreadRadius = 2.0;
        break;
    }

    return BoxDecoration(
      color: backgroundColor,
      borderRadius: BorderRadius.circular(borderRadius),
      border: Border.all(
        color: baseBorder.withValues(alpha: borderOpacity),
        width: curIntensity == DisplayIntensity.ultra ? 2.0 : 1.4,
      ),
      boxShadow: [
        BoxShadow(
          color: baseBorder.withValues(alpha: borderOpacity * 0.55),
          blurRadius: blurRadius,
          spreadRadius: spreadRadius,
        ),
      ],
    );
  }
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

/// 6. مستطيل المدخلات والمخرجات الرئيسي المرن (Responsive Metric Card - Forced English LTR)
enum MetricStatus { neutral, upArrow, fasterText }

class RowingMetricCard extends StatelessWidget {
  final String title; // مثال: 'SPLIT' أو 'STROKE RATE'
  final String unit; // مثال: '/500m' أو 'spm' أو 'W'
  final String value; // مثال: '1:53.4' أو '33'
  final bool highlightLime;
  final MetricStatus status;
  final String? footnote;

  const RowingMetricCard({
    super.key,
    required this.title,
    required this.unit,
    required this.value,
    this.highlightLime = false,
    this.status = MetricStatus.neutral,
    this.footnote,
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
    switch (status) {
      case MetricStatus.upArrow:
        return Icon(
          Icons.change_history_rounded,
          color: EngineRowingUI.neonLime,
          size: RowingResponsive.dp(context, 36),
        );
      case MetricStatus.fasterText:
        return Text(
          'faster',
          style: TextStyle(
            fontFamily: EngineRowingUI.fontFamily,
            fontSize: RowingResponsive.sp(context, 18),
            fontWeight: FontWeight.w500,
            color: EngineRowingUI.neonLime,
          ),
        );
      case MetricStatus.neutral:
        return Container(
          width: RowingResponsive.dp(context, 32),
          height: RowingResponsive.dp(context, 6),
          decoration: BoxDecoration(
            color: EngineRowingUI.labelSlate.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(RowingResponsive.dp(context, 3)),
          ),
        );
    }
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

/// 11. لوحة الزونات والكيرف المتجاوبة بالكامل لجميع الشاشات والموبايل (Adaptive Zone Boxes & White Curve)
/// - تمنع تماماً كسر الكلمات أو الأرقام رأسياً (Threshold و الأزمنة دائماً أفقية ومقروءة بالكامل)
/// - تترتب أفقياً إذا اتسعت الشاشة، وتنتقل لصفوف متراصة تحت بعضها في شاشات الموبايل
/// - خلفية كيرف المعدلات بيضاء بالكامل مع الاحتفاظ بألوان الزونات الفسفورية
/// - حدود فسفورية متوهجة تستجيب لحدة الإضاءة
class RowingAdaptiveZoneBoxes extends StatelessWidget {
  final Map<String, int> zoneTotals;
  final String title;
  final String? curveTitle;
  final String Function(int seconds)? formatDuration;

  const RowingAdaptiveZoneBoxes({
    super.key,
    required this.zoneTotals,
    this.title = 'إجمالي أحمال الزونات:',
    this.curveTitle,
    this.formatDuration,
  });

  static const List<String> defaultZones = [
    'Z1',
    'Z2',
    'Z3',
    'Z4',
    'Threshold',
    'Z5',
  ];

  static const Map<String, Color> defaultZoneColors = {
    'Z1': EngineRowingUI.zone1Color,
    'Z2': EngineRowingUI.zone2Color,
    'Z3': EngineRowingUI.zone3Color,
    'Z4': EngineRowingUI.zone4Color,
    'Threshold': EngineRowingUI.thresholdColor,
    'Z5': EngineRowingUI.zone5Color,
  };

  String _format(int secs) {
    if (formatDuration != null) return formatDuration!(secs);
    if (secs == 0) return '-';
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
    final totalAllSecs = zoneTotals.values.fold<int>(0, (a, b) => a + b);

    return ValueListenableBuilder<DisplayIntensity>(
      valueListenable: RowingResponsive.intensityNotifier,
      builder: (context, intensity, _) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final isNarrow = constraints.maxWidth < 620;

            final zoneTiles = defaultZones.map((z) {
              final secs = zoneTotals[z] ?? 0;
              final color = defaultZoneColors[z] ?? EngineRowingUI.neonLime;
              final isZero = secs == 0;

              return Container(
                constraints: const BoxConstraints(minWidth: 95),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                decoration: BoxDecoration(
                  color: isZero
                      ? EngineRowingUI.equationCardFill.withValues(alpha: 0.5)
                      : color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(
                    color: isZero
                        ? EngineRowingUI.bgGridLine
                        : color.withValues(
                            alpha: intensity == DisplayIntensity.ultra
                                ? 0.95
                                : (intensity == DisplayIntensity.high
                                    ? 0.75
                                    : 0.55)),
                    width: isZero ? 1.0 : (intensity == DisplayIntensity.ultra ? 1.8 : 1.3),
                  ),
                  boxShadow: isZero
                      ? null
                      : [
                          BoxShadow(
                            color: color.withValues(
                                alpha: intensity == DisplayIntensity.ultra
                                    ? 0.35
                                    : 0.18),
                            blurRadius: intensity == DisplayIntensity.ultra ? 8 : 4,
                          ),
                        ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // اسم الزون أفقي كامل بدون أي كسر رأسي
                    Text(
                      z,
                      maxLines: 1,
                      overflow: TextOverflow.visible,
                      style: TextStyle(
                        fontFamily: EngineRowingUI.fontFamily,
                        fontSize: RowingResponsive.sp(context, z == 'Threshold' ? 11 : 12),
                        fontWeight: FontWeight.bold,
                        color: isZero ? EngineRowingUI.captionGrey : color,
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(height: 4),
                    // المدة الزمنية أفقية بالكامل
                    Directionality(
                      textDirection: TextDirection.ltr,
                      child: Text(
                        isZero ? '-' : RowingNumberFormatter.toEnglishDigits(_format(secs)),
                        maxLines: 1,
                        overflow: TextOverflow.visible,
                        style: TextStyle(
                          fontFamily: EngineRowingUI.fontFamily,
                          fontSize: RowingResponsive.sp(context, 11),
                          fontWeight: FontWeight.bold,
                          fontFeatures: const [FontFeature.tabularFigures()],
                          color: isZero ? EngineRowingUI.captionGrey : EngineRowingUI.textWhite,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }).toList();

            // ── كيرف المعدلات الشريطي ذو الخلفية البيضاء ──
            final curveWidget = Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white, // خلفية بيضاء نقية للكيرف حسب الطلب
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: EngineRowingUI.neonLime.withValues(
                      alpha: intensity == DisplayIntensity.ultra ? 0.9 : 0.5),
                  width: intensity == DisplayIntensity.ultra ? 2.0 : 1.4,
                ),
                boxShadow: [
                  BoxShadow(
                    color: EngineRowingUI.neonLime.withValues(
                        alpha: intensity == DisplayIntensity.ultra
                            ? 0.45
                            : (intensity == DisplayIntensity.high ? 0.25 : 0.15)),
                    blurRadius: intensity == DisplayIntensity.ultra ? 12 : 6,
                    spreadRadius: intensity == DisplayIntensity.ultra ? 1 : 0.5,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (curveTitle != null) ...[
                    Text(
                      curveTitle!,
                      style: const TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0A1633), // داكن ليظهر على الأبيض
                      ),
                    ),
                    const SizedBox(height: 6),
                  ],
                  Directionality(
                    textDirection: TextDirection.ltr,
                    child: SizedBox(
                      height: 56,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: defaultZones.map((z) {
                          final secs = zoneTotals[z] ?? 0;
                          final fraction = totalAllSecs > 0
                              ? (secs / totalAllSecs).clamp(0.08, 1.0)
                              : 0.08;
                          final color = defaultZoneColors[z] ?? EngineRowingUI.neonLime;

                          return Tooltip(
                            message:
                                '$z: ${totalAllSecs > 0 ? ((secs / totalAllSecs) * 100).toStringAsFixed(1) : 0}%',
                            child: Container(
                              width: 14,
                              height: 52 * fraction,
                              margin: const EdgeInsets.symmetric(horizontal: 2.5),
                              decoration: BoxDecoration(
                                color: secs > 0 ? color : Colors.grey.shade300,
                                borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
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

            if (isNarrow) {
              // ── شاشات الموبايل الضيقة: ترتيب الخانات في صفوف متراصة تحت بعضها ──
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: RowingResponsive.sp(context, 12),
                      fontWeight: FontWeight.bold,
                      color: EngineRowingUI.textWhite,
                    ),
                  ),
                  const SizedBox(height: 10),
                  // شبكة متجاوبة بـ 3 أعمدة بحيث تظهر الخانات كاملة ومستريحة أفقياً
                  GridView.count(
                    crossAxisCount: 3,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                    childAspectRatio: 1.85,
                    children: zoneTiles,
                  ),
                  const SizedBox(height: 12),
                  // كيرف المعدلات بالخلفية البيضاء أسفل الزونات بكامل الوضوح
                  curveWidget,
                ],
              );
            } else {
              // ── الشاشات الواسعة والتابلت: صف أفقي للزونات وبجواره كيرف المعدلات ──
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: RowingResponsive.sp(context, 12.5),
                      fontWeight: FontWeight.bold,
                      color: EngineRowingUI.textWhite,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Directionality(
                          textDirection: TextDirection.ltr,
                          child: Row(
                            children: zoneTiles
                                .map((t) => Expanded(
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 2.5),
                                        child: t,
                                      ),
                                    ))
                                .toList(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      curveWidget,
                    ],
                  ),
                ],
              );
            }
          },
        );
      },
    );
  }
}

/// 12. حاوية التكبير والتصغير التفاعلية بأصابع المستخدم لجميع الشاشات (Pinch-to-Zoom Area)
class PinchZoomArea extends StatelessWidget {
  final Widget child;
  final double minScale;
  final double maxScale;

  const PinchZoomArea({
    super.key,
    required this.child,
    this.minScale = 0.8,
    this.maxScale = 2.5,
  });

  @override
  Widget build(BuildContext context) {
    return InteractiveViewer(
      minScale: minScale,
      maxScale: maxScale,
      panEnabled: true,
      scaleEnabled: true,
      child: child,
    );
  }
}

