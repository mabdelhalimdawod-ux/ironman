import 'package:flutter/material.dart';
import 'app_strings.dart';
import 'engine_rowing_ui.dart';
import 'progress_period_filter.dart';

/// الشريط الفاصل المكتوب المشترك فوق كل منحنى وبين كل منحنى وآخر في تبويب Progress.
/// يعرض: اسم المنحنى + الفترة المختارة من فلتر المدة المشترك:
/// AR: "اسم المنحنى، من D/M/YYYY إلى D/M/YYYY"
/// EN: "Curve Name, From D/M/YYYY to D/M/YYYY"
class ProgressCurveHeader extends StatelessWidget {
  final String curveName;
  final ProgressPeriodSelection period;
  final Widget? trailing;
  final Color? accentColor;

  const ProgressCurveHeader({
    super.key,
    required this.curveName,
    required this.period,
    this.trailing,
    this.accentColor,
  });

  /// تنسيق نص العنوان والفترة بدقة لإعادة الاستخدام والاختبار
  static String formatTitle(
    BuildContext context, {
    required String curveName,
    required ProgressPeriodSelection period,
  }) {
    final s = AppStrings.of(context);
    return s.curveHeaderTitle(curveName, period.start, period.end);
  }

  @override
  Widget build(BuildContext context) {
    final headerText = formatTitle(
      context,
      curveName: curveName,
      period: period,
    );
    final accent = accentColor ?? EngineRowingUI.neonLime;

    return Container(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: EngineRowingUI.equationCardFill,
        border: Border(
          top: BorderSide(color: accent.withValues(alpha: 0.45), width: 1.0),
          bottom: const BorderSide(color: EngineRowingUI.bgGridLine, width: 1.0),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 16,
            decoration: BoxDecoration(
              color: accent,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              headerText,
              style: const TextStyle(
                color: EngineRowingUI.textWhite,
                fontSize: 12.5,
                fontWeight: FontWeight.bold,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}
