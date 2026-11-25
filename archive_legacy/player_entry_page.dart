import 'dart:convert';
import 'package:flutter/material.dart';
import 'db.dart';
import 'app_strings.dart';
import 'power_calculations.dart';

const Color _navy = Color(0xFF0D3B66);
const Color _sky = Color(0xFFE8F4FC);
const Color _gold = Color(0xFFFFC93C);

class PlayerEntryPage extends StatefulWidget {
  final String date;
  final Map<String, Object?> session;
  final Map<String, Object?> player;

  const PlayerEntryPage({
    super.key,
    required this.date,
    required this.session,
    required this.player,
  });

  @override
  State<PlayerEntryPage> createState() => _PlayerEntryPageState();
}

class _PlayerEntryPageState extends State<PlayerEntryPage> {
  bool _loading = true;
  bool _isSaving = false;

  // Controllers for standard fields
  final _rhrCtrl = TextEditingController();
  final _hrvCtrl = TextEditingController();
  final _hrCtrl = TextEditingController();
  final _hrMaxCtrl = TextEditingController();
  final _hrPostCtrl = TextEditingController();
  final _hr1minCtrl = TextEditingController();
  final _weightCtrl = TextEditingController();
  final _fatigueCtrl = TextEditingController();
  final _sleepCtrl = TextEditingController();
  final _avgPowerCtrl = TextEditingController();
  final _maxPowerCtrl = TextEditingController();
  final _distanceCtrl = TextEditingController();
  final _splitCtrl = TextEditingController();
  final _efCtrl = TextEditingController();

  // 2 New Optional Fields (for Key Athletes)
  final _npWattsCtrl = TextEditingController();
  final _decouplingHrCtrl = TextEditingController();

  double? _calculatedNP;
  double? _calculatedDecoupling;

  @override
  void initState() {
    super.initState();
    _loadExistingLog();
    _npWattsCtrl.addListener(_onAdvancedFieldsChanged);
    _decouplingHrCtrl.addListener(_onAdvancedFieldsChanged);
    _avgPowerCtrl.addListener(_onPowerOrHRChanged);
    _hrCtrl.addListener(_onPowerOrHRChanged);
  }

  @override
  void dispose() {
    _rhrCtrl.dispose();
    _hrvCtrl.dispose();
    _hrCtrl.dispose();
    _hrMaxCtrl.dispose();
    _hrPostCtrl.dispose();
    _hr1minCtrl.dispose();
    _weightCtrl.dispose();
    _fatigueCtrl.dispose();
    _sleepCtrl.dispose();
    _avgPowerCtrl.dispose();
    _maxPowerCtrl.dispose();
    _distanceCtrl.dispose();
    _splitCtrl.dispose();
    _efCtrl.dispose();
    _npWattsCtrl.dispose();
    _decouplingHrCtrl.dispose();
    super.dispose();
  }

  void _onAdvancedFieldsChanged() {
    final watts = PowerCalculations.parseSeries(_npWattsCtrl.text);
    final hrs = PowerCalculations.parseSeries(_decouplingHrCtrl.text);

    final np = PowerCalculations.calculateNormalizedPower(watts);
    final decoupling = PowerCalculations.calculateDecoupling(watts, hrs);

    setState(() {
      _calculatedNP = np;
      _calculatedDecoupling = decoupling;
    });

    // إذا لم يكن هناك متوسط واط مدخل ومحسوب NP، نحسب EF تلقائياً
    if (np != null && _hrCtrl.text.isNotEmpty) {
      final hr = int.tryParse(_hrCtrl.text);
      if (hr != null && hr > 0 && _efCtrl.text.isEmpty) {
        final autoEF = PowerCalculations.calculateEF(np, hr);
        if (autoEF != null) {
          _efCtrl.text = autoEF.toString();
        }
      }
    }
  }

  void _onPowerOrHRChanged() {
    final power = double.tryParse(_avgPowerCtrl.text) ?? _calculatedNP;
    final hr = int.tryParse(_hrCtrl.text);
    if (power != null && hr != null && hr > 0) {
      final autoEF = PowerCalculations.calculateEF(power, hr);
      if (autoEF != null && _efCtrl.text.isEmpty) {
        _efCtrl.text = autoEF.toString();
      }
    }
  }

  Future<void> _loadExistingLog() async {
    final logs = await DB.q(
      'SELECT * FROM logs WHERE player_id=? AND date=? AND idx=?',
      [widget.player['id'], widget.date, widget.session['idx']],
    );

    if (logs.isNotEmpty) {
      final l = logs.first;
      _rhrCtrl.text = l['rhr'] != null ? '${l['rhr']}' : '';
      _hrvCtrl.text = l['hrv'] != null ? '${l['hrv']}' : '';
      _hrCtrl.text = l['hr'] != null ? '${l['hr']}' : '';
      _hrMaxCtrl.text = l['hr_max'] != null ? '${l['hr_max']}' : '';
      _hrPostCtrl.text = l['hr_post'] != null ? '${l['hr_post']}' : '';
      _hr1minCtrl.text = l['hr_1min'] != null ? '${l['hr_1min']}' : '';
      _weightCtrl.text = l['weight'] != null ? '${l['weight']}' : '';
      _fatigueCtrl.text = l['fatigue'] != null ? '${l['fatigue']}' : '';
      _sleepCtrl.text = l['sleep_hours'] != null ? '${l['sleep_hours']}' : '';
      _avgPowerCtrl.text = l['avg_power'] != null ? '${l['avg_power']}' : '';
      _maxPowerCtrl.text = l['max_power'] != null ? '${l['max_power']}' : '';
      _distanceCtrl.text = l['distance'] != null ? '${l['distance']}' : '';
      _splitCtrl.text = l['split_500'] != null ? '${l['split_500']}' : '';
      _efCtrl.text = l['ef'] != null ? '${l['ef']}' : '';

      // استخراج الحقول الإضافية من player_notes
      final notes = l['player_notes'] as String?;
      if (notes != null && notes.isNotEmpty) {
        try {
          if (notes.startsWith('{') && notes.endsWith('}')) {
            final parsed = jsonDecode(notes) as Map<String, dynamic>;
            _npWattsCtrl.text = parsed['np_watts_raw'] ?? '';
            _decouplingHrCtrl.text = parsed['decoupling_hr_raw'] ?? '';
          }
        } catch (_) {}
      }
    }

    _onAdvancedFieldsChanged();

    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    final s = AppStrings.of(context);
    final playerName = widget.player['name'] as String? ?? '';
    final mhr = widget.player['mhr'] as int? ?? 200;

    // 1. التحقق من النبض
    final hr = int.tryParse(_hrCtrl.text);
    if (hr != null && (hr < 30 || hr > 230 || hr > mhr + 10)) {
      _showError(s.invalidHR(playerName));
      return;
    }

    final hrPost = int.tryParse(_hrPostCtrl.text);
    if (hrPost != null && hr != null && hrPost > hr + 5) {
      _showError(s.invalidPostHR);
      return;
    }

    final hr1min = int.tryParse(_hr1minCtrl.text);
    if (hr1min != null && hrPost != null && hr1min > hrPost + 5) {
      _showError(s.invalidRecoveryHR);
      return;
    }

    // 2. التحقق من الإرهاق
    final fatigue = int.tryParse(_fatigueCtrl.text);
    if (fatigue != null && (fatigue < 1 || fatigue > 5)) {
      _showError(s.invalidFatigue);
      return;
    }

    // 3. التحقق من الواط
    final avgPower = double.tryParse(_avgPowerCtrl.text) ?? _calculatedNP;
    final maxPower = double.tryParse(_maxPowerCtrl.text);
    if (avgPower != null && avgPower < 0) {
      _showError(s.invalidAvgPower);
      return;
    }
    if (maxPower != null && avgPower != null && maxPower < avgPower) {
      _showError(s.invalidMaxPower);
      return;
    }

    // 4. التحقق من المسافة
    final distance = int.tryParse(_distanceCtrl.text);
    if (distance != null && distance <= 0) {
      _showError(s.invalidDistance);
      return;
    }

    // 5. التحقق من EF
    double? ef = double.tryParse(_efCtrl.text);
    if (ef == null && avgPower != null && hr != null && hr > 0) {
      ef = PowerCalculations.calculateEF(avgPower, hr);
    }
    if (ef != null && ef < 0) {
      _showError(s.invalidEF);
      return;
    }

    setState(() => _isSaving = true);

    // تجميع الملاحظات والحقول الإضافية للاعبين الأساسيين
    final extraData = {
      'np_watts_raw': _npWattsCtrl.text.trim(),
      'decoupling_hr_raw': _decouplingHrCtrl.text.trim(),
      'calculated_np': _calculatedNP,
      'calculated_decoupling': _calculatedDecoupling,
    };
    final playerNotesJson = jsonEncode(extraData);

    // حفظ في قاعدة البيانات
    await DB.put('logs', {
      'player_id': widget.player['id'],
      'date': widget.date,
      'idx': widget.session['idx'],
      'rhr': int.tryParse(_rhrCtrl.text),
      'hrv': int.tryParse(_hrvCtrl.text),
      'hr': hr,
      'hr_max': int.tryParse(_hrMaxCtrl.text),
      'hr_post': hrPost,
      'hr_1min': hr1min,
      'weight': double.tryParse(_weightCtrl.text),
      'fatigue': fatigue,
      'sleep_hours': double.tryParse(_sleepCtrl.text),
      'avg_power': avgPower,
      'max_power': maxPower,
      'distance': distance,
      'split_500': double.tryParse(_splitCtrl.text),
      'ef': ef,
      'player_notes': playerNotesJson,
    });

    if (mounted) {
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(s.savedSuccessfully),
          backgroundColor: Colors.green.shade700,
          behavior: SnackBarBehavior.floating,
        ),
      );
      // العودة التلقائية لقائمة اللاعبين
      Navigator.pop(context, true);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final zone = widget.session['zone'] as String? ?? 'Z2';
    final mhr = widget.player['mhr'] as int? ?? 190;
    final targetHR = hrRange(mhr, zone);

    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: Text(s.playerEntryTitle)),
        body: const Center(child: CircularProgressIndicator(color: _navy)),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('${s.playerEntryTitle} - ${widget.player['name']}'),
        backgroundColor: _navy,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        children: [
          // بطاقة ملخص الحصة واللاعب
          _buildSessionHeaderCard(s, zone, mhr, targetHR),
          const SizedBox(height: 16),

          // 1. المؤشرات قبل التمرين (الصباحية)
          _buildSectionHeader(s.preWorkoutSection, Icons.nightlight_round, Colors.indigo),
          const SizedBox(height: 8),
          Row(
            children: [
              _buildField(_rhrCtrl, s.rhrLabel, hint: s.rhrHint),
              const SizedBox(width: 8),
              _buildField(_hrvCtrl, s.hrvLabel, hint: s.hrvHint),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _buildField(_sleepCtrl, s.sleepLabel, hint: s.sleepHint, isDecimal: true),
              const SizedBox(width: 8),
              _buildField(_fatigueCtrl, s.fatigueLabel, hint: s.fatigueHint),
            ],
          ),
          const SizedBox(height: 16),

          // 2. الأداء أثناء التمرين
          _buildSectionHeader(s.duringWorkoutSection, Icons.fitness_center, Colors.deepOrange),
          const SizedBox(height: 8),
          Row(
            children: [
              _buildField(_avgPowerCtrl, s.avgPowerLabel, hint: s.avgPowerHint, isDecimal: true),
              const SizedBox(width: 8),
              _buildField(_maxPowerCtrl, s.maxPowerLabel, hint: s.maxPowerHint, isDecimal: true),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _buildField(_hrCtrl, s.workoutHRLabel, hint: s.workoutHRHint),
              const SizedBox(width: 8),
              _buildField(_hrMaxCtrl, s.workoutMaxHRLabel, hint: s.workoutMaxHRHint),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _buildField(_distanceCtrl, s.distanceLabel, hint: s.distanceHint),
              const SizedBox(width: 8),
              _buildField(_splitCtrl, s.splitLabel, hint: s.splitHint, isDecimal: true),
              const SizedBox(width: 8),
              _buildField(_efCtrl, s.efLabel, hint: s.efHint, isDecimal: true),
            ],
          ),
          const SizedBox(height: 16),

          // 3. مؤشرات بعد التمرين والاستشفاء
          _buildSectionHeader(s.postWorkoutSection, Icons.favorite_border, Colors.teal),
          const SizedBox(height: 8),
          Row(
            children: [
              _buildField(_hrPostCtrl, s.postHRLabel, hint: s.postHRHint),
              const SizedBox(width: 8),
              _buildField(_hr1minCtrl, s.hr1MinLabel, hint: s.hr1MinHint),
              const SizedBox(width: 8),
              _buildField(_weightCtrl, s.weightLabel, hint: s.weightHint, isDecimal: true),
            ],
          ),
          const SizedBox(height: 20),

          // 4. الحقلين الجديدين للاعبين الأساسيين (اختياري)
          _buildKeyAthletesSection(s),
          const SizedBox(height: 24),

          // زر الحفظ والعودة
          FilledButton.icon(
            onPressed: _isSaving ? null : _save,
            style: FilledButton.styleFrom(
              backgroundColor: _gold,
              foregroundColor: _navy,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              elevation: 2,
            ),
            icon: _isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: _navy),
                  )
                : const Icon(Icons.check_circle_outline, size: 24),
            label: Text(
              s.saveAndReturn,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildSessionHeaderCard(AppStrings s, String zone, int mhr, String targetHR) {
    return Container(
      decoration: BoxDecoration(
        color: _navy,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: _navy.withAlpha(50),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: _gold,
            radius: 26,
            child: Text(
              widget.player['name'].toString().isNotEmpty
                  ? widget.player['name'].toString()[0]
                  : 'P',
              style: const TextStyle(
                color: _navy,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${widget.player['name']}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${s.workoutType}: ${widget.session['kind']} ($zone)',
                  style: const TextStyle(color: _gold, fontSize: 14),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${s.maxHRLabel}: $mhr',
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(30),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$targetHR bpm',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon, Color color) {
    return Row(
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildField(
    TextEditingController ctrl,
    String label, {
    String? hint,
    bool isDecimal = false,
  }) {
    return Expanded(
      child: TextField(
        controller: ctrl,
        keyboardType: TextInputType.numberWithOptions(decimal: isDecimal),
        textInputAction: TextInputAction.next,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          filled: true,
          fillColor: Colors.white,
        ),
      ),
    );
  }

  // 4. الحقلين الاختياريين للاعبين الأساسيين
  Widget _buildKeyAthletesSection(AppStrings s) {
    return Container(
      decoration: BoxDecoration(
        color: _sky.withAlpha(120),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _navy.withAlpha(40), width: 1.5),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: _navy,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Icon(Icons.star, color: _gold, size: 18),
              ),
              const SizedBox(width: 8),
              Text(
                s.keyAthletesSection,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: _navy,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // الحقل الأول: واط NP (قراءات متعددة)
          TextField(
            controller: _npWattsCtrl,
            keyboardType: TextInputType.text,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: s.npWattsLabel,
              hintText: s.npWattsHint,
              prefixIcon: const Icon(Icons.electric_bolt, color: _navy, size: 20),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              filled: true,
              fillColor: Colors.white,
            ),
          ),
          if (_calculatedNP != null) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green.shade300),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.green, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    '${s.calculatedNP}: ',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  Text(
                    '${_calculatedNP!} W',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                    ),
                  ),
                  const Spacer(),
                  InkWell(
                    onTap: () {
                      _avgPowerCtrl.text = _calculatedNP.toString();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: _navy,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'استخدام كمتوسط',
                        style: TextStyle(color: Colors.white, fontSize: 11),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),

          // الحقل الثاني: نبض Decoupling (قراءات متعددة)
          TextField(
            controller: _decouplingHrCtrl,
            keyboardType: TextInputType.text,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              labelText: s.decouplingHRLabel,
              hintText: s.decouplingHRHint,
              prefixIcon: const Icon(Icons.monitor_heart, color: Colors.red, size: 20),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              filled: true,
              fillColor: Colors.white,
            ),
          ),
          if (_calculatedDecoupling != null) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.shade300),
              ),
              child: Row(
                children: [
                  const Icon(Icons.analytics_outlined, color: Colors.blue, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    '${s.calculatedDecoupling}: ',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  Text(
                    '${_calculatedDecoupling!}% (${_calculatedDecoupling! < 5.0 ? 'ممتاز' : 'تراجع كفاءة'})',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: _calculatedDecoupling! < 5.0 ? Colors.green : Colors.orange,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
