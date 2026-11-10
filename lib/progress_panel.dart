import 'package:flutter/material.dart';
import 'engine_rowing_ui.dart';

/// عنصر مشترك واحد يلف جميع اللوحات في تبويب Progress
/// مواصفاته المعتمدة:
/// - حد رفيع 1px بلون فسفوري خفيف بشفافية 40% - 55%
/// - توهج خارجي خفيف جداً (BoxShadow: blur 8, spread 0, opacity 20%)
/// - زوايا مدورة ثابتة (14px)
/// - مظهر ثابت هادئ لا يغطي على الرسوم البيانية أو النصوص
class ProgressPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final String? title;
  final Widget? leading;
  final Widget? trailing;
  final Color? backgroundColor;
  final Color? glowBorderColor;

  const ProgressPanel({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.title,
    this.leading,
    this.trailing,
    this.backgroundColor,
    this.glowBorderColor,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor = (glowBorderColor ?? EngineRowingUI.neonLime).withValues(alpha: 0.48);
    final shadowColor = (glowBorderColor ?? EngineRowingUI.neonLime).withValues(alpha: 0.18);
    final bgColor = backgroundColor ?? EngineRowingUI.cardFill;

    return Container(
      margin: margin ?? const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: borderColor,
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: shadowColor,
            blurRadius: 8.0,
            spreadRadius: 0.0,
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 10.0,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (title != null || leading != null || trailing != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: EngineRowingUI.equationCardFill.withValues(alpha: 0.55),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(13)),
                border: Border(
                  bottom: BorderSide(
                    color: EngineRowingUI.bgGridLine,
                    width: 1.0,
                  ),
                ),
              ),
              child: Row(
                children: [
                  if (leading != null) ...[
                    leading!,
                    const SizedBox(width: 8),
                  ],
                  if (title != null)
                    Expanded(
                      child: Text(
                        title!,
                        style: const TextStyle(
                          color: EngineRowingUI.textWhite,
                          fontSize: 14.5,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.3,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  if (trailing != null) trailing!,
                ],
              ),
            ),
          ],
          Padding(
            padding: padding ?? const EdgeInsets.all(14),
            child: child,
          ),
        ],
      ),
    );
  }
}
