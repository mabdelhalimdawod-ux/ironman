import 'package:flutter/material.dart';
import 'app_strings.dart';
import 'db.dart';
import 'heart_rate_zones.dart';
import 'power_calculations.dart';

const Color _navy = Color(0xFF0D3B66);
const Color _sky = Color(0xFFE8F4FC);
const Color _gold = Color(0xFFFFC93C);
const Color _green = Color(0xFF2E7D32);

/// نموذج إدارة حالة فورم تمرين واحد من تمارين اليوم
class _SingleWorkoutFormState {
  final int sessionIdx;
  final String kind;
  final String time;
  final String initialZone;

  // Controllers
  final avgPowerCtrl = TextEditingController();
  final splitCtrl = TextEditingController();
  final distanceCtrl = TextEditingController();
  final hrCtrl = TextEditingController();
  final postHRCtrl = TextEditingController();
  final recovery1minCtrl = TextEditingController();
  final npWattsCtrl = TextEditingController();
  final decouplingHRCtrl = TextEditingController();

  String currentZone;
  HeartRateZoneRange? targetRange;
  double? calculatedNP;
  double? calculatedDecoupling;
  double? calculatedEF;

  _SingleWorkoutFormState({
    required this.sessionIdx,
    required this.kind,
    required this.time,
    required this.initialZone,
  }) : currentZone = initialZone;

  void dispose() {
    avgPowerCtrl.dispose();
    splitCtrl.dispose();
    distanceCtrl.dispose();
    hrCtrl.dispose();
    postHRCtrl.dispose();
    recovery1minCtrl.dispose();
    npWattsCtrl.dispose();
    decouplingHRCtrl.dispose();
  }
}

/// الصفحة الفرعية لتسجيل جميع تمارين اليوم للاعب (Multi-workout entry per athlete per day)
class AthleteDayEntryPage extends StatefulWidget {
  final Map<String, Object?> player;
  final String date;
  final List<Map<String, Object?>> sessions;

  const AthleteDayEntryPage({
    super.key,
    required this.player,
    required this.date,
    required this.sessions,
  });

  @override
  State<AthleteDayEntryPage> createState() => _AthleteDayEntryPageState();
}

class _AthleteDayEntryPageState extends State<AthleteDayEntryPage> {
  bool _loading = true;
  bool _isSaving = false;
  int _effectiveRHR = 60;

  // المؤشرات اليومية المشتركة للاعب لليوم
  final _hrvCtrl = TextEditingController();
  final _sleepCtrl = TextEditingController();
  final _weightCtrl = TextEditingController();
  final _fatigueCtrl = TextEditingController();
  final _mhrCtrl = TextEditingController();
  final _rhrCtrl = TextEditingController();

  // قائمة الفورمات بعدد حصص اليوم
  final List<_SingleWorkoutFormState> _workoutForms = [];

  int get _playerId => widget.player['id'] as int;
  int get _mhr => (widget.player['mhr'] as int?) ?? 190;
  String get _playerName => widget.player['name'] as String? ?? '';

  int get _currentMHR => int.tryParse(_mhrCtrl.text) ?? _mhr;
  int get _currentRHR => int.tryParse(_rhrCtrl.text) ?? _effectiveRHR;

  @override
  void initState() {
    super.initState();
    _mhrCtrl.addListener(_onDailyHeartRatesChanged);
    _rhrCtrl.addListener(_onDailyHeartRatesChanged);
    _initFormsAndLoadExistingData();
  }

  @override
  void dispose() {
    _mhrCtrl.removeListener(_onDailyHeartRatesChanged);
    _rhrCtrl.removeListener(_onDailyHeartRatesChanged);
    _mhrCtrl.dispose();
    _rhrCtrl.dispose();
    _hrvCtrl.dispose();
    _sleepCtrl.dispose();
    _weightCtrl.dispose();
    _fatigueCtrl.dispose();
    for (final form in _workoutForms) {
      form.dispose();
    }
    super.dispose();
  }

  /// إعادة حساب الزونات ونطاقات النبض فورياً لجميع تمارين اليوم عند تعديل MHR أو RHR
  void _onDailyHeartRatesChanged() {
    final mhr = _currentMHR;
    final rhr = _currentRHR;
    setState(() {
      for (final form in _workoutForms) {
        final hr = int.tryParse(form.hrCtrl.text);
        final calculatedZone = HeartRateZones.determineZone(hr: hr, mhr: mhr, rhr: rhr);
        if (calculatedZone != null) {
          form.currentZone = calculatedZone;
        }
        form.targetRange = HeartRateZones.calculate(
          mhr: mhr,
          rhr: rhr,
          zone: form.currentZone,
        );
      }
    });
  }

  Future<void> _initFormsAndLoadExistingData() async {
    setState(() => _loading = true);

    // 1. حساب نبض الراحة الفعال (متوسط 7 أيام أو آخر قيمة مسجلة)
    _effectiveRHR = await HeartRateZones.getEffectiveRHR(_playerId);

    if (_rhrCtrl.text.isEmpty) {
      _rhrCtrl.text = _effectiveRHR.toString();
    }
    if (_mhrCtrl.text.isEmpty) {
      _mhrCtrl.text = _mhr.toString();
    }

    final initialMHR = _currentMHR;
    final initialRHR = _currentRHR;

    // 2. إنشاء الفورمات لحصص اليوم
    _workoutForms.clear();
    for (int i = 0; i < widget.sessions.length; i++) {
      final s = widget.sessions[i];
      final idx = (s['idx'] as num?)?.toInt() ?? i;
      final kind = s['kind'] as String? ?? 'Erg';
      final time = s['time'] as String? ?? '07:00';
      final zone = s['zone'] as String? ?? 'Z2';

      final formState = _SingleWorkoutFormState(
        sessionIdx: idx,
        kind: kind,
        time: time,
        initialZone: zone,
      );

      // حساب نطاق كارفونين الأولي لهذا الزون
      formState.targetRange = HeartRateZones.calculate(
        mhr: initialMHR,
        rhr: initialRHR,
        zone: zone,
      );

      _workoutForms.add(formState);
    }

    // 3. تحميل السجلات الموجودة مسبقاً لهذا اليوم إن وجدت لملء الخانات تلقائياً
    final existingLogs = await DB.q(
      'SELECT * FROM logs WHERE player_id = ? AND date = ?',
      [_playerId, widget.date],
    );

    for (final log in existingLogs) {
      final idx = (log['idx'] as num?)?.toInt() ?? 0;

      // ملء المؤشرات اليومية المشتركة من أول سجل متوفر
      if (log['rhr'] != null && (log['rhr'] as num) > 0) {
        _rhrCtrl.text = log['rhr'].toString();
      }
      if (log['hr_max'] != null && (log['hr_max'] as num) > 0) {
        _mhrCtrl.text = log['hr_max'].toString();
      }
      if (_hrvCtrl.text.isEmpty && log['hrv'] != null) {
        _hrvCtrl.text = log['hrv'].toString();
      }
      if (_sleepCtrl.text.isEmpty && log['sleep_hours'] != null) {
        _sleepCtrl.text = log['sleep_hours'].toString();
      }
      if (_weightCtrl.text.isEmpty && log['weight'] != null) {
        _weightCtrl.text = log['weight'].toString();
      }
      if (_fatigueCtrl.text.isEmpty && log['fatigue'] != null) {
        _fatigueCtrl.text = log['fatigue'].toString();
      }

      // البحث عن الفورم المطابق للحصة
      final form = _workoutForms.firstWhere(
        (f) => f.sessionIdx == idx,
        orElse: () => _workoutForms.isNotEmpty ? _workoutForms.first : _SingleWorkoutFormState(sessionIdx: 0, kind: 'Erg', time: '07:00', initialZone: 'Z2'),
      );

      if (log['avg_power'] != null && (log['avg_power'] as num) > 0) {
        form.avgPowerCtrl.text = (log['avg_power'] as num).round().toString();
      }
      if (log['split_500'] != null && (log['split_500'] as num) > 0) {
        form.splitCtrl.text = (log['split_500'] as num).toStringAsFixed(1);
      }
      if (log['distance'] != null && (log['distance'] as num) > 0) {
        form.distanceCtrl.text = log['distance'].toString();
      }
      if (log['hr'] != null && (log['hr'] as num) > 0) {
        form.hrCtrl.text = log['hr'].toString();
      }
      if (log['hr_post'] != null && (log['hr_post'] as num) > 0) {
        form.postHRCtrl.text = log['hr_post'].toString();
      }
      if (log['hr_1min'] != null && (log['hr_1min'] as num) > 0) {
        form.recovery1minCtrl.text = log['hr_1min'].toString();
      }
      if (log['ef'] != null) {
        form.calculatedEF = (log['ef'] as num).toDouble();
      }

      // حساب الـ EF الأولي
      _updateEF(form);
    }

    // إعادة حساب الزونات التلقائية بناءً على البيانات المحملة
    final currentMhr = _currentMHR;
    final currentRhr = _currentRHR;
    for (final form in _workoutForms) {
      final hr = int.tryParse(form.hrCtrl.text);
      final calculatedZone = HeartRateZones.determineZone(hr: hr, mhr: currentMhr, rhr: currentRhr);
      if (calculatedZone != null) {
        form.currentZone = calculatedZone;
      }
      form.targetRange = HeartRateZones.calculate(
        mhr: currentMhr,
        rhr: currentRhr,
        zone: form.currentZone,
      );
      _updateEF(form);
    }

    if (mounted) setState(() => _loading = false);
  }

  void _onWorkoutHRChanged(_SingleWorkoutFormState form) {
    final hr = int.tryParse(form.hrCtrl.text);
    final mhr = _currentMHR;
    final rhr = _currentRHR;
    final newZone = HeartRateZones.determineZone(hr: hr, mhr: mhr, rhr: rhr);
    setState(() {
      if (newZone != null) {
        form.currentZone = newZone;
      }
      form.targetRange = HeartRateZones.calculate(
        mhr: mhr,
        rhr: rhr,
        zone: form.currentZone,
      );
      _updateEF(form);
    });
  }

  void _updateEF(_SingleWorkoutFormState form) {
    final watts = double.tryParse(form.avgPowerCtrl.text);
    final hr = int.tryParse(form.hrCtrl.text);
    if (watts != null && hr != null && hr > 0 && watts > 0) {
      form.calculatedEF = PowerCalculations.calculateEF(watts, hr);
    }
  }

  void _onAdvancedCalculationsChanged(_SingleWorkoutFormState form) {
    final watts = PowerCalculations.parseSeries(form.npWattsCtrl.text);
    final hrs = PowerCalculations.parseSeries(form.decouplingHRCtrl.text);

    setState(() {
      form.calculatedNP = PowerCalculations.calculateNormalizedPower(watts);
      form.calculatedDecoupling = PowerCalculations.calculateDecoupling(watts, hrs);
    });
  }

  Future<void> _saveAllWorkouts() async {
    final s = AppStrings.of(context);
    setState(() => _isSaving = true);

    try {
      final hrvVal = int.tryParse(_hrvCtrl.text);
      final sleepVal = double.tryParse(_sleepCtrl.text);
      final weightVal = double.tryParse(_weightCtrl.text);
      final fatigueVal = int.tryParse(_fatigueCtrl.text);
      final mhrVal = int.tryParse(_mhrCtrl.text) ?? _mhr;
      final rhrVal = int.tryParse(_rhrCtrl.text) ?? _effectiveRHR;

      for (final form in _workoutForms) {
        final avgWatts = double.tryParse(form.avgPowerCtrl.text);
        final splitVal = double.tryParse(form.splitCtrl.text);
        final distVal = int.tryParse(form.distanceCtrl.text);
        final hrVal = int.tryParse(form.hrCtrl.text);
        final postHRVal = int.tryParse(form.postHRCtrl.text);
        final rec1minVal = int.tryParse(form.recovery1minCtrl.text);

        // حساب الزون التلقائي قبل الحفظ
        final autoZone = HeartRateZones.determineZone(hr: hrVal, mhr: mhrVal, rhr: rhrVal);
        if (autoZone != null) {
          form.currentZone = autoZone;
        }

        // حساب EF تلقائي
        double? efVal = form.calculatedEF;
        if (efVal == null && avgWatts != null && hrVal != null && hrVal > 0) {
          efVal = PowerCalculations.calculateEF(avgWatts, hrVal);
        }

        // حفظ السجل في جدول logs
        await DB.put('logs', {
          'player_id': _playerId,
          'date': widget.date,
          'idx': form.sessionIdx,
          'rhr': rhrVal,
          'hrv': hrvVal,
          'hr': hrVal,
          'hr_max': mhrVal,
          'hr_post': postHRVal,
          'hr_1min': rec1minVal,
          'weight': weightVal,
          'fatigue': fatigueVal,
          'sleep_hours': sleepVal,
          'avg_power': avgWatts ?? form.calculatedNP,
          'distance': distVal,
          'split_500': splitVal,
          'ef': efVal,
        });

        // تحديث جدول sessions بالزون
        await DB.put('sessions', {
          'date': widget.date,
          'idx': form.sessionIdx,
          'kind': form.kind,
          'zone': form.currentZone,
          'time': form.time,
        });
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 8),
                Text('${s.savedSuccessfully} - تم تسجيل كل تمارين اليوم للاعب $_playerName'),
              ],
            ),
            backgroundColor: _green,
            duration: const Duration(seconds: 2),
          ),
        );

        // العودة التلقائية لقائمة اللاعبين مع إشعار بالنجاح
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${s.error}: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text('${s.multiEntryTitle}: $_playerName'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _navy))
          : Column(
              children: [
                // رأس تعريفي باللاعب ونبض الراحة المعتمد بمعادلة كارفونين
                _buildAthleteHeaderCard(s),

                // المحتوى القابل للتمرير
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    children: [
                      // قسم المؤشرات اليومية المشتركة (HRV، النوم، الوزن، الإرهاق)
                      _buildCommonMetricsCard(s),
                      const SizedBox(height: 16),

                      // هيدر تمارين اليوم
                      Row(
                        children: [
                          const Icon(Icons.fitness_center, color: _navy, size: 22),
                          const SizedBox(width: 8),
                          Text(
                            'فورمات تمارين اليوم (${_workoutForms.length} تمارين)',
                            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: _navy),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),

                      // عدد من الفورمات بعدد تمارين اليوم، كل فورم مخصص لتمرين ومكتوب عليه ميعاده ونوعه
                      ...List.generate(_workoutForms.length, (idx) {
                        return _buildWorkoutSessionForm(s, idx, _workoutForms[idx]);
                      }),

                      const SizedBox(height: 24),
                    ],
                  ),
                ),

                // زر الحفظ الرئيسي والعودة لقائمة اللاعبين
                _buildSaveBottomButton(s),
              ],
            ),
    );
  }

  Widget _buildAthleteHeaderCard(AppStrings s) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: _sky.withValues(alpha: 0.6),
        border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: _navy,
            child: Text(
              _playerName.isNotEmpty ? _playerName[0] : 'A',
              style: const TextStyle(color: _gold, fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _playerName,
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: _navy),
                ),
                Text(
                  'التاريخ: ${widget.date} • ${s.maxHRLabel}: $_currentMHR bpm',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade800),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const Text('RHR (7 أيام)', style: TextStyle(fontSize: 10, color: Colors.black54)),
                Text(
                  '$_effectiveRHR bpm',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: _navy),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCommonMetricsCard(AppStrings s) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.monitor_heart, color: _navy, size: 20),
                const SizedBox(width: 8),
                Text(
                  s.commonDailyMetrics,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: _navy),
                ),
              ],
            ),
            const Divider(height: 16),
            // الصف الأول: MHR و RHR الصباحي والوزن
            Row(
              children: [
                // أقصى نبض (MHR)
                Expanded(
                  child: TextFormField(
                    controller: _mhrCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: s.mhrFieldLabel,
                      hintText: s.mhrFieldHint,
                      suffixText: 'bpm',
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),

                // نبض الراحة الصباحي (RHR)
                Expanded(
                  child: TextFormField(
                    controller: _rhrCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: s.morningRHRLabel,
                      hintText: s.morningRHRHint,
                      suffixText: 'bpm',
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),

                // الوزن
                Expanded(
                  child: TextFormField(
                    controller: _weightCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: s.weightLabel,
                      hintText: s.weightHint,
                      suffixText: 'كجم',
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // الصف الثاني: ساعات النوم ومستوى الإرهاق و HRV
            Row(
              children: [
                // ساعات النوم
                Expanded(
                  child: TextFormField(
                    controller: _sleepCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: s.sleepLabel,
                      hintText: s.sleepHint,
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),

                // الإرهاق (1-5)
                Expanded(
                  child: TextFormField(
                    controller: _fatigueCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: s.fatigueLabel,
                      hintText: '1 - 5',
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),

                // HRV
                Expanded(
                  child: TextFormField(
                    controller: _hrvCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: s.hrvLabel,
                      hintText: s.hrvHint,
                      suffixText: 'ms',
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWorkoutSessionForm(AppStrings s, int formIdx, _SingleWorkoutFormState form) {
    final rangeText = form.targetRange?.format() ?? '-';

    // حساب الزون التلقائي من النبض الحالي ومعادلة كارفونين
    final hrVal = int.tryParse(form.hrCtrl.text);
    final autoZone = HeartRateZones.determineZone(
      hr: hrVal,
      mhr: _currentMHR,
      rhr: _currentRHR,
    );

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.blueGrey.shade100, width: 1.2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // هيدر الفورم مخصص للتمرين ومكتوب عليه ميعاده ونوعه
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: _navy,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.timer_outlined, color: _gold, size: 16),
                      const SizedBox(width: 4),
                      Text(
                        'الساعة ${form.time}',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    s.formForSession(formIdx, form.kind, form.time),
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _navy),
                  ),
                ),
                // شارة الزون التلقائية بناءً على النبض ومعادلة كارفونين بدلاً من الاختيار اليدوي
                if (autoZone != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: HeartRateZones.zoneColor(autoZone),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.flash_on, color: Colors.white, size: 14),
                        const SizedBox(width: 4),
                        Text(
                          HeartRateZones.zoneDisplayName(autoZone, isArabic: s.isArabic),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),

            // عرض نطاق النبض المستهدف بمعادلة كارفونين حسب زون التمرين
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.amber.shade300),
              ),
              child: Row(
                children: [
                  const Icon(Icons.favorite, color: Colors.redAccent, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'نطاق النبض المستهدف (${form.currentZone}): $rangeText',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Colors.brown.shade900,
                      ),
                    ),
                  ),
                  Text(
                    'HRR: ${form.targetRange?.hrr ?? (_currentMHR - _currentRHR)} bpm',
                    style: TextStyle(fontSize: 11, color: Colors.brown.shade700),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // الحقول الأساسية للتمرين: الواط، السبليت، المسافة بالمتر، معدل النبض
            Row(
              children: [
                // الواط
                Expanded(
                  child: TextFormField(
                    controller: form.avgPowerCtrl,
                    keyboardType: TextInputType.number,
                    onChanged: (_) {
                      setState(() => _updateEF(form));
                    },
                    decoration: InputDecoration(
                      labelText: s.avgPowerLabel,
                      hintText: s.avgPowerHint,
                      suffixText: 'W',
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),

                // السبليت
                Expanded(
                  child: TextFormField(
                    controller: form.splitCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: s.splitLabel,
                      hintText: s.splitHint,
                      suffixText: 'ث',
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            Row(
              children: [
                // المسافة بالمتر
                Expanded(
                  child: TextFormField(
                    controller: form.distanceCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: s.distanceLabel,
                      hintText: s.distanceHint,
                      suffixText: 'م',
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),

                // معدل النبض
                Expanded(
                  child: TextFormField(
                    controller: form.hrCtrl,
                    keyboardType: TextInputType.number,
                    onChanged: (_) => _onWorkoutHRChanged(form),
                    decoration: InputDecoration(
                      labelText: s.workoutHRLabel,
                      hintText: s.workoutHRHint,
                      suffixText: 'bpm',
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // نبض الاستشفاء (فور الانتهاء + بعد دقيقة)
            Row(
              children: [
                // نبض الاستشفاء فوراً
                Expanded(
                  child: TextFormField(
                    controller: form.postHRCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: s.postHRLabel,
                      hintText: s.postHRHint,
                      suffixText: 'bpm',
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),

                // نبض الاستشفاء بعد دقيقة
                Expanded(
                  child: TextFormField(
                    controller: form.recovery1minCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: s.hr1MinLabel,
                      hintText: s.hr1MinHint,
                      suffixText: 'bpm',
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),

            // مؤشر الكفاءة EF إذا كان محسوباً
            if (form.calculatedEF != null && form.calculatedEF! > 0) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'معدل الكفاءة المحسوب: EF = ${form.calculatedEF} (واط / نبض)',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blue.shade900),
                ),
              ),
            ],

            const SizedBox(height: 10),

            // حقلي واط NP ونبض Decoupling الاختياريين (Expansion Tile للتنظيم الأنيق)
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text(
                s.keyAthletesSection,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black87),
              ),
              subtitle: Text(
                'NP Watts & Decoupling HR (اختياري للاعبين الأساسيين)',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              ),
              children: [
                const SizedBox(height: 6),
                TextFormField(
                  controller: form.npWattsCtrl,
                  onChanged: (_) => _onAdvancedCalculationsChanged(form),
                  decoration: InputDecoration(
                    labelText: s.npWattsLabel,
                    hintText: s.npWattsHint,
                    isDense: true,
                  ),
                ),
                if (form.calculatedNP != null) ...[
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '${s.calculatedNP}: ${form.calculatedNP} W',
                      style: const TextStyle(fontWeight: FontWeight.bold, color: _green, fontSize: 12),
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                TextFormField(
                  controller: form.decouplingHRCtrl,
                  onChanged: (_) => _onAdvancedCalculationsChanged(form),
                  decoration: InputDecoration(
                    labelText: s.decouplingHRLabel,
                    hintText: s.decouplingHRHint,
                    isDense: true,
                  ),
                ),
                if (form.calculatedDecoupling != null) ...[
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '${s.calculatedDecoupling}: ${form.calculatedDecoupling}%',
                      style: const TextStyle(fontWeight: FontWeight.bold, color: _navy, fontSize: 12),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSaveBottomButton(AppStrings s) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            offset: const Offset(0, -3),
            blurRadius: 10,
          ),
        ],
      ),
      child: SafeArea(
        child: SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: _navy,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            icon: _isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.check_circle_outline),
            label: Text(
              s.saveAllWorkouts,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            onPressed: _isSaving ? null : _saveAllWorkouts,
          ),
        ),
      ),
    );
  }
}
