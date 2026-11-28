import 'dart:math';
import 'package:flutter/material.dart';
import 'engine_rowing_ui.dart';

/// إطار موحد للرسوم البيانية قابل للتمرير الأفقي يميناً ويساراً:
/// - محور القيمة (Y) ثابت خارج منطقة التمرير على اليسار بحجم خط >= 12
/// - عرض الرسم = max(عرض المنطقة المتاحة على الشاشة, عدد الخانات × عرض الخانة الثابت)
/// - يبدأ التمرير تلقائياً عند أحدث تاريخ (أقصى اليمين في الرسم)
/// - ممنوع تصغير الخط عن 12
class ScrollableChartFrame extends StatefulWidget {
  final double height;
  final int slotsCount;
  final double slotWidth;
  final double minY;
  final double maxY;
  final int yTicksCount;
  final String Function(double value) formatYLabel;
  final String? yAxisUnitLabel;
  final double yAxisWidth;
  final double topPadding;
  final double bottomReservedSize;
  final Widget Function(double chartWidth, double chartHeight) chartBuilder;

  const ScrollableChartFrame({
    super.key,
    this.height = 250.0,
    required this.slotsCount,
    this.slotWidth = 64.0,
    required this.minY,
    required this.maxY,
    this.yTicksCount = 5,
    required this.formatYLabel,
    this.yAxisUnitLabel,
    this.yAxisWidth = 58.0,
    this.topPadding = 14.0,
    this.bottomReservedSize = 34.0,
    required this.chartBuilder,
  });

  @override
  State<ScrollableChartFrame> createState() => _ScrollableChartFrameState();
}

class _ScrollableChartFrameState extends State<ScrollableChartFrame> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scheduleScrollToLatest();
  }

  @override
  void didUpdateWidget(covariant ScrollableChartFrame oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.slotsCount != widget.slotsCount ||
        oldWidget.slotWidth != widget.slotWidth) {
      _scheduleScrollToLatest();
    }
  }

  void _scheduleScrollToLatest() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_scrollController.hasClients) {
        final maxScroll = _scrollController.position.maxScrollExtent;
        if (maxScroll > 0) {
          _scrollController.jumpTo(maxScroll);
        }
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxWidth = constraints.maxWidth.isFinite
              ? constraints.maxWidth
              : 320.0;
          final availableChartWidth =
              max(120.0, maxWidth - widget.yAxisWidth);
          final requiredContentWidth = max(
            availableChartWidth,
            max(1, widget.slotsCount) * widget.slotWidth,
          );

          final plotHeight = max(
            80.0,
            widget.height - widget.topPadding - widget.bottomReservedSize,
          );

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.yAxisUnitLabel != null &&
                  widget.yAxisUnitLabel!.trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    widget.yAxisUnitLabel!,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: EngineRowingUI.labelSlate,
                    ),
                  ),
                ),
              SizedBox(
                height: widget.height,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ── محور Y الثابت خارج منطقة التمرير ──
                    SizedBox(
                      width: widget.yAxisWidth,
                      height: widget.height,
                      child: Padding(
                        padding: EdgeInsets.only(
                          top: widget.topPadding,
                          bottom: widget.bottomReservedSize,
                        ),
                        child: _FixedYAxis(
                          minY: widget.minY,
                          maxY: widget.maxY,
                          ticksCount: widget.yTicksCount,
                          plotHeight: plotHeight,
                          formatYLabel: widget.formatYLabel,
                        ),
                      ),
                    ),
                    // ── منطقة التمرير الأفقية للرسم البياني ──
                    Expanded(
                      child: SingleChildScrollView(
                        controller: _scrollController,
                        scrollDirection: Axis.horizontal,
                        physics: const BouncingScrollPhysics(),
                        child: SizedBox(
                          width: requiredContentWidth,
                          height: widget.height,
                          child: Padding(
                            padding: EdgeInsets.only(top: widget.topPadding),
                            child: widget.chartBuilder(
                              requiredContentWidth,
                              widget.height - widget.topPadding,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _FixedYAxis extends StatelessWidget {
  final double minY;
  final double maxY;
  final int ticksCount;
  final double plotHeight;
  final String Function(double value) formatYLabel;

  const _FixedYAxis({
    required this.minY,
    required this.maxY,
    required this.ticksCount,
    required this.plotHeight,
    required this.formatYLabel,
  });

  @override
  Widget build(BuildContext context) {
    final safeCount = max(2, ticksCount);
    final range = (maxY - minY).abs() < 1e-9 ? 1.0 : (maxY - minY);

    return LayoutBuilder(
      builder: (context, constraints) {
        final actualHeight = constraints.maxHeight;
        return Stack(
          clipBehavior: Clip.none,
          children: List.generate(safeCount, (i) {
            final fraction = i / (safeCount - 1); // 0 في الأسفل .. 1 في الأعلى
            final value = minY + fraction * range;
            final topY = (1.0 - fraction) * actualHeight - 9.0;

            return Positioned(
              left: 0,
              right: 6,
              top: topY.clamp(-6.0, max(0.0, actualHeight - 14.0)),
              child: Text(
                formatYLabel(value),
                textAlign: TextAlign.end,
                maxLines: 1,
                overflow: TextOverflow.visible,
                style: const TextStyle(
                  fontSize: 12,
                  color: EngineRowingUI.labelSlate,
                  fontWeight: FontWeight.w600,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            );
          }),
        );
      },
    );
  }
}

/// وسيلة الإيضاح (Legend) في سطر أفقي واحد قابل للتمرير بدون كسر لسطرين وبخط >= 12
class SingleLineLegend extends StatelessWidget {
  final List<Widget> items;
  final double spacing;

  const SingleLineLegend({
    super.key,
    required this.items,
    this.spacing = 14.0,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (int i = 0; i < items.length; i++) ...[
            if (i > 0) SizedBox(width: spacing),
            items[i],
          ],
        ],
      ),
    );
  }
}

/// عنصر داخل وسيلة الإيضاح بحجم خط لا يقل عن 12
class SingleLineLegendItem extends StatelessWidget {
  final Color color;
  final String label;
  final bool isCircle;
  final bool isDashed;
  final bool isDimmed;

  const SingleLineLegendItem({
    super.key,
    required this.color,
    required this.label,
    this.isCircle = false,
    this.isDashed = false,
    this.isDimmed = false,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveColor = isDimmed ? color.withValues(alpha: 0.4) : color;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isCircle)
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: effectiveColor,
            ),
          )
        else if (isDashed)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 6, height: 3, color: effectiveColor),
              const SizedBox(width: 3),
              Container(width: 6, height: 3, color: effectiveColor),
            ],
          )
        else
          Container(
            width: 14,
            height: 3.5,
            decoration: BoxDecoration(
              color: effectiveColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        const SizedBox(width: 6),
        Text(
          label,
          maxLines: 1,
          softWrap: false,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: effectiveColor,
          ),
        ),
      ],
    );
  }
}

/// صف الشارات (Chips) في سطر أفقي واحد قابل للتمرير بدون تكسير وبخط >= 12
class SingleLineChipsRow extends StatelessWidget {
  final List<String> labels;
  final Color? borderColor;
  final Color? textColor;

  const SingleLineChipsRow({
    super.key,
    required this.labels,
    this.borderColor,
    this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    if (labels.isEmpty) return const SizedBox.shrink();
    final border = borderColor ?? EngineRowingUI.neonLime.withValues(alpha: 0.45);
    final fg = textColor ?? EngineRowingUI.textWhite;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (int i = 0; i < labels.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: EngineRowingUI.equationCardFill,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: border),
              ),
              child: Text(
                labels[i],
                maxLines: 1,
                softWrap: false,
                style: TextStyle(
                  fontSize: 12,
                  color: fg,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
