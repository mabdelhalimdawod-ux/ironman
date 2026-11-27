import 'dart:math';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'app_strings.dart';
import 'db.dart';
import 'engine_rowing_ui.dart';
import 'progress_calcs.dart';
import 'progress_panel.dart';

/// بيانات اختبار قدرة حرجة واحد معروض في الرسم
class CpTestDisplayItem {
  final String date;
  final double cpWatts;
  final double wPrimeKiloJoules;
  final double balanceIndexSeconds;
  final BalanceIndexLeaning leaning;

  const CpTestDisplayItem({
    required this.date,
    required this.cpWatts,
    required this.wPrimeKiloJoules,
    required this.balanceIndexSeconds,
    this.leaning = BalanceIndexLeaning.unclassified,
  });
}

/// ويدجت منحنى اختبارات CP (أعمدة رأسية ثلاثية لكل اختبار + حاسبة ومدخلات الاختبارات)
class CpBarsCurveBlock extends StatefulWidget {
  final AppStrings s;
  final String athleteName;
  final Color athleteColor;
  final int playerId;
  final DateTime periodStart;
  final DateTime periodEnd;
  final List<Map<String, Object?>> cpTestRows;
  final List<DateValuePoint> cpValuePoints;
  final bool isLoading;
  final VoidCallback? onTestDataChanged;

  const CpBarsCurveBlock({
    super.key,
    required this.s,
    required this.athleteName,
    required this.athleteColor,
    required this.playerId,
    required this.periodStart,
    required this.periodEnd,
    required this.cpTestRows,
    required this.cpValuePoints,
    required this.isLoading,
    this.onTestDataChanged,
  });

  @override
  State<CpBarsCurveBlock> createState() => _CpBarsCurveBlockState();
}

class _CpBarsCurveBlockState extends State<CpBarsCurveBlock> {
  // مدخلات الاختبار التفاعلي (4 مسافات افتراضية مع إمكانية التعديل)
  late List<TextEditingController> _distanceControllers;
  late List<TextEditingController> _timeControllers;
  DateTime _testDate = DateTime.now();
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _distanceControllers = ProgressCalcs.defaultCpDistances
        .map((d) => TextEditingController(text: d.toInt().toString()))
        .toList();
    _timeControllers = List.generate(
      ProgressCalcs.defaultCpDistances.length,
      (_) => TextEditingController(),
    );
  }

  @override
  void dispose() {
    for (final c in _distanceControllers) {
      c.dispose();
    }
    for (final c in _timeControllers) {
      c.dispose();
    }
    super.dispose();
  }

  /// تحليل الزمن بالثواني (يقبل ثواني صريحة مثل "100" أو دقيقة:ثانية مثل "1:40")
  double? _parseTimeSec(String raw) {
    final clean = raw.trim();
    if (clean.isEmpty) return null;
    if (clean.contains(':')) {
      final parts = clean.split(':');
      if (parts.length == 2) {
        final m = double.tryParse(parts[0]);
        final s = double.tryParse(parts[1]);
        if (m != null && s != null && m >= 0 && s >= 0) {
          return m * 60.0 + s;
        }
      }
    }
    return double.tryParse(clean);
  }

  /// تجميع وتجهيز اختبارات الفترة لحساب الأعمدة الرأسية وتصنيف الميل
  List<CpTestDisplayItem> _buildPeriodTestItems() {
    final startStr = ProgressCalcs.formatDateKey(widget.periodStart);
    final endStr = ProgressCalcs.formatDateKey(widget.periodEnd);

    // تجميع من جدول cp_values أولاً
    final itemsByDate = <String, ({double cp, double wPrime})>{};

    for (final row in widget.cpTestRows) {
      final dStr = ProgressCalcs.formatDateKey(row['date'] ?? '');
      if (dStr.isEmpty || dStr.compareTo(startStr) < 0 || dStr.compareTo(endStr) > 0) {
        continue;
      }
      final cp = (row['cp'] as num?)?.toDouble();
      final wp = (row['w_prime'] as num?)?.toDouble();
      if (cp != null && cp > 0 && wp != null && wp > 0) {
        itemsByDate[dStr] = (cp: cp, wPrime: wp);
      }
    }

    // إذا لم تكن هناك قيم كافية من cp_tests، استعن بـ cpValuePoints
    for (final pt in widget.cpValuePoints) {
      final dStr = ProgressCalcs.formatDateKey(pt.date);
      if (dStr.compareTo(startStr) >= 0 && dStr.compareTo(endStr) <= 0 && pt.value != null && pt.value! > 0) {
        if (!itemsByDate.containsKey(dStr)) {
          // افتراض متوسط W' تقريبي لو لم تتوفر في النقطة
          itemsByDate[dStr] = (cp: pt.value!, wPrime: 15000.0);
        }
      }
    }

    final sortedDates = itemsByDate.keys.toList()..sort();
    if (sortedDates.isEmpty) return const [];

    // تحويل إلى عناصر أولية
    final rawItems = sortedDates.map((dStr) {
      final data = itemsByDate[dStr]!;
      final cp = data.cp;
      final wpJoules = data.wPrime > 200 ? data.wPrime : (data.wPrime * 1000.0);
      final wpKJ = wpJoules / 1000.0;
      final bi = ProgressCalcs.balanceIndex(wpJoules, cp);
      return (date: dStr, cp: cp, wpKJ: wpKJ, bi: bi);
    }).toList();

    // حساب متوسط BI لتصنيف الميل إذا وُجد أكثر من اختبار
    double? avgBi;
    if (rawItems.length > 1) {
      avgBi = rawItems.map((i) => i.bi).reduce((a, b) => a + b) / rawItems.length;
    }

    return rawItems.map((item) {
      final leaning = ProgressCalcs.classifyBalanceIndex(
        bi: item.bi,
        avgBi: avgBi,
      );
      return CpTestDisplayItem(
        date: item.date,
        cpWatts: item.cp,
        wPrimeKiloJoules: double.parse(item.wpKJ.toStringAsFixed(1)),
        balanceIndexSeconds: item.bi,
        leaning: leaning,
      );
    }).toList();
  }

  /// حفظ الاختبار الجديد إلى SQLite
  Future<void> _saveNewCpTest(CpCalculationResult calcResult) async {
    setState(() => _isSaving = true);
    try {
      final dateStr = ProgressCalcs.formatDateKey(_testDate);

      // حفظ القيم المحسوبة في جدول cp_values
      await DB.put('cp_values', {
        'player_id': widget.playerId,
        'date': dateStr,
        'cp': calcResult.cpWatts,
        'w_prime': calcResult.wPrimeJoules,
        'method': 'regression_4dist',
      });

      // حفظ تفاصيل المسافات في جدول cp_tests
      for (int i = 0; i < _distanceControllers.length; i++) {
        final d = double.tryParse(_distanceControllers[i].text.trim()) ?? 0.0;
        final t = _parseTimeSec(_timeControllers[i].text) ?? 0.0;
        if (d > 0 && t > 0) {
          final w = ProgressCalcs.wattsFromTime(d, t);
          await DB.addCPTest({
            'player_id': widget.playerId,
            'date': dateStr,
            'test_type': '${d.toInt()}m',
            'duration_seconds': t.round(),
            'distance': d.round(),
            'avg_power': w,
          });
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(widget.s.savedSuccessfully),
            backgroundColor: EngineRowingUI.neonLime.withValues(alpha: 0.9),
          ),
        );
      }

      widget.onTestDataChanged?.call();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving test: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isLoading) {
      return ProgressPanel(
        title: widget.athleteName,
        child: SizedBox(
          height: 180,
          child: Center(
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: widget.athleteColor,
            ),
          ),
        ),
      );
    }

    final testItems = _buildPeriodTestItems();

    // فحص مدخلات الحاسبة الحالية
    final currentEntries = <({double distanceM, double timeSec})>[];
    for (int i = 0; i < _distanceControllers.length; i++) {
      final d = double.tryParse(_distanceControllers[i].text.trim()) ?? 0.0;
      final t = _parseTimeSec(_timeControllers[i].text) ?? 0.0;
      if (d > 0 && t > 0) {
        currentEntries.add((distanceM: d, timeSec: t));
      }
    }

    final liveCalcResult = ProgressCalcs.calcCpAndWPrime(currentEntries);

    return ProgressPanel(
      title: widget.athleteName,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── 1. عنوان وشرح المنحنى ومفتاح الأعمدة ──
          Wrap(
            spacing: 12,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _BarLegend(
                color: EngineRowingUI.neonLime,
                label: widget.s.chipCP,
              ),
              _BarLegend(
                color: EngineRowingUI.flameOrange,
                label: widget.s.chipWPrime,
              ),
              _BarLegend(
                color: EngineRowingUI.electricCyan,
                label: widget.s.chipBalanceIndex,
              ),
            ],
          ),
          const SizedBox(height: 12),

          // ── 2. رسم الأعمدة الرأسية لاختبارات الفترة ──
          if (testItems.isEmpty) ...[
            Container(
              height: 130,
              alignment: Alignment.center,
              child: Text(
                widget.s.noTestsInThisPeriod,
                style: const TextStyle(color: Colors.white54, fontSize: 13),
              ),
            ),
          ] else ...[
            SizedBox(
              height: 220,
              child: Directionality(
                textDirection: TextDirection.ltr,
                child: BarChart(
                  BarChartData(
                    alignment: BarChartAlignment.spaceAround,
                    maxY: 100, // نسب مئوية معيارية لضمان تناسب طول الأعمدة
                    barTouchData: BarTouchData(
                      enabled: true,
                      touchTooltipData: BarTouchTooltipData(
                        getTooltipColor: (_) => Colors.black.withValues(alpha: 0.85),
                        getTooltipItem: (group, groupIndex, rod, rodIndex) {
                          final item = testItems[group.x.toInt()];
                          String text = '';
                          if (rodIndex == 0) {
                            text = 'CP: ${item.cpWatts.round()} W';
                          } else if (rodIndex == 1) {
                            text = "W': ${item.wPrimeKiloJoules} kJ";
                          } else {
                            text = 'BI: ${item.balanceIndexSeconds.round()} s';
                          }
                          return BarTooltipItem(
                            text,
                            const TextStyle(color: Colors.white, fontSize: 11),
                          );
                        },
                      ),
                    ),
                    titlesData: FlTitlesData(
                      leftTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 26,
                          getTitlesWidget: (val, meta) {
                            final idx = val.toInt();
                            if (idx >= 0 && idx < testItems.length) {
                              final item = testItems[idx];
                              final parts = item.date.split('-');
                              final label = parts.length >= 3 ? '${parts[2]}/${parts[1]}' : item.date;
                              return Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(
                                  label,
                                  style: const TextStyle(
                                    color: Colors.white60,
                                    fontSize: 10,
                                  ),
                                ),
                              );
                            }
                            return const SizedBox.shrink();
                          },
                        ),
                      ),
                    ),
                    gridData: const FlGridData(show: false),
                    borderData: FlBorderData(show: false),
                    barGroups: List.generate(testItems.length, (i) {
                      final item = testItems[i];
                      // معايرة الارتفاعات لتبدو متناسقة على نفس المحور
                      final cpPct = min(100.0, (item.cpWatts / 450.0) * 100.0);
                      final wpPct = min(100.0, (item.wPrimeKiloJoules / 30.0) * 100.0);
                      final biPct = min(100.0, (item.balanceIndexSeconds / 120.0) * 100.0);

                      return BarChartGroupData(
                        x: i,
                        barsSpace: 4,
                        barRods: [
                          // 1. CP
                          BarChartRodData(
                            toY: cpPct,
                            color: EngineRowingUI.neonLime,
                            width: 14,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          // 2. W'
                          BarChartRodData(
                            toY: wpPct,
                            color: EngineRowingUI.flameOrange,
                            width: 14,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          // 3. BI
                          BarChartRodData(
                            toY: biPct,
                            color: EngineRowingUI.electricCyan,
                            width: 14,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ],
                      );
                    }),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),

            // قائمة بطاقات تفاصيل الاختبارات وتصنيف الميل
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: testItems.map((item) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        item.date,
                        style: const TextStyle(color: Colors.white70, fontSize: 11),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${item.cpWatts.round()}W | ${item.wPrimeKiloJoules}kJ | ${item.balanceIndexSeconds.round()}s',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (item.leaning != BalanceIndexLeaning.unclassified) ...[
                        const SizedBox(width: 6),
                        _LeaningBadge(leaning: item.leaning, s: widget.s),
                      ],
                    ],
                  ),
                );
              }).toList(),
            ),
          ],

          const SizedBox(height: 16),
          const Divider(color: Colors.white12, height: 1),
          const SizedBox(height: 14),

          // ── 3. قسم مدخلات وحاسبة اختبارات CP ──
          Row(
            children: [
              const Icon(Icons.calculate_rounded, color: EngineRowingUI.neonLime, size: 18),
              const SizedBox(width: 6),
              Text(
                widget.s.criticalPowerBarsTitle,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              // زر اختيار تاريخ الاختبار
              InkWell(
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _testDate,
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now().add(const Duration(days: 1)),
                  );
                  if (picked != null) {
                    setState(() => _testDate = picked);
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.calendar_today_rounded, color: Colors.white70, size: 12),
                      const SizedBox(width: 4),
                      Text(
                        ProgressCalcs.formatDateKey(_testDate),
                        style: const TextStyle(color: Colors.white70, fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // شبكة المسافات الأربعة (مسافة + زمن + واط محسوب تلقائياً)
          Column(
            children: List.generate(_distanceControllers.length, (idx) {
              final dVal = double.tryParse(_distanceControllers[idx].text.trim()) ?? 0.0;
              final tVal = _parseTimeSec(_timeControllers[idx].text) ?? 0.0;
              final calculatedWatts = (dVal > 0 && tVal > 0)
                  ? ProgressCalcs.wattsFromTime(dVal, tVal)
                  : 0.0;

              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    // حقل المسافة (متر)
                    SizedBox(
                      width: 80,
                      child: TextField(
                        controller: _distanceControllers[idx],
                        keyboardType: TextInputType.number,
                        style: const TextStyle(color: Colors.white, fontSize: 12),
                        decoration: InputDecoration(
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                          suffixText: 'm',
                          suffixStyle: const TextStyle(color: Colors.white38, fontSize: 10),
                          filled: true,
                          fillColor: Colors.white.withValues(alpha: 0.06),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                            borderSide: const BorderSide(color: Colors.white12),
                          ),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // حقل الزمن (ثواني أو mm:ss)
                    Expanded(
                      child: TextField(
                        controller: _timeControllers[idx],
                        keyboardType: TextInputType.text,
                        style: const TextStyle(color: Colors.white, fontSize: 12),
                        decoration: InputDecoration(
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                          hintText: widget.s.testTimeLabel,
                          hintStyle: const TextStyle(color: Colors.white24, fontSize: 11),
                          suffixText: 'sec',
                          suffixStyle: const TextStyle(color: Colors.white38, fontSize: 10),
                          filled: true,
                          fillColor: Colors.white.withValues(alpha: 0.06),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                            borderSide: const BorderSide(color: Colors.white12),
                          ),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // الواط المحسوب تلقائياً
                    Container(
                      width: 85,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      decoration: BoxDecoration(
                        color: calculatedWatts > 0
                            ? EngineRowingUI.neonLime.withValues(alpha: 0.12)
                            : Colors.white.withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: calculatedWatts > 0
                              ? EngineRowingUI.neonLime.withValues(alpha: 0.4)
                              : Colors.white12,
                        ),
                      ),
                      child: Text(
                        calculatedWatts > 0 ? '${calculatedWatts.round()} W' : '-- W',
                        style: TextStyle(
                          color: calculatedWatts > 0
                              ? EngineRowingUI.neonLime
                              : Colors.white38,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ),
          const SizedBox(height: 8),

          // بطاقة النتائج المحسوبة وزر الحفظ
          if (liveCalcResult != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: EngineRowingUI.neonLime.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: EngineRowingUI.neonLime.withValues(alpha: 0.4),
                  width: 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _ResultMetric(
                        title: widget.s.chipCP,
                        value: '${liveCalcResult.cpWatts.round()} W',
                        color: EngineRowingUI.neonLime,
                      ),
                      _ResultMetric(
                        title: widget.s.chipWPrime,
                        value: '${liveCalcResult.wPrimeKiloJoules} kJ',
                        color: EngineRowingUI.flameOrange,
                      ),
                      _ResultMetric(
                        title: widget.s.chipBalanceIndex,
                        value: '${liveCalcResult.balanceIndexSeconds.round()} s',
                        color: EngineRowingUI.electricCyan,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ElevatedButton.icon(
                    onPressed: _isSaving ? null : () => _saveNewCpTest(liveCalcResult),
                    icon: _isSaving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                          )
                        : const Icon(Icons.save_rounded, size: 16, color: Colors.black),
                    label: Text(
                      widget.s.save,
                      style: const TextStyle(
                        color: Colors.black,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: EngineRowingUI.neonLime,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ] else if (currentEntries.length < 3) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                widget.s.need3DistancesForCp,
                style: const TextStyle(color: Colors.white54, fontSize: 11),
                textAlign: TextAlign.center,
              ),
            ),
          ] else ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                widget.s.inconsistentTestResults,
                style: const TextStyle(color: Colors.amber, fontSize: 11),
                textAlign: TextAlign.center,
              ),
            ),
          ],

          const SizedBox(height: 8),
          Center(
            child: Text(
              widget.s.estimationNotice,
              style: const TextStyle(color: Colors.white38, fontSize: 10),
            ),
          ),
        ],
      ),
    );
  }
}

class _BarLegend extends StatelessWidget {
  final Color color;
  final String label;

  const _BarLegend({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            color: color.withValues(alpha: 0.9),
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _LeaningBadge extends StatelessWidget {
  final BalanceIndexLeaning leaning;
  final AppStrings s;

  const _LeaningBadge({required this.leaning, required this.s});

  @override
  Widget build(BuildContext context) {
    String text;
    Color color;

    switch (leaning) {
      case BalanceIndexLeaning.endurance:
        text = s.enduranceLeaning;
        color = EngineRowingUI.electricCyan;
        break;
      case BalanceIndexLeaning.explosive:
        text = s.explosiveLeaning;
        color = EngineRowingUI.flameOrange;
        break;
      case BalanceIndexLeaning.balanced:
        text = s.balancedLeaning;
        color = EngineRowingUI.neonLime;
        break;
      case BalanceIndexLeaning.unclassified:
        return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.5), width: 0.8),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _ResultMetric extends StatelessWidget {
  final String title;
  final String value;
  final Color color;

  const _ResultMetric({
    required this.title,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          title,
          style: const TextStyle(color: Colors.white70, fontSize: 10),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 15,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}
