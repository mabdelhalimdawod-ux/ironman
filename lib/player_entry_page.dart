import 'dart:convert';
import 'package:flutter/material.dart';
import 'app_strings.dart';
import 'db.dart';
import 'engine_rowing_ui.dart';
import 'power_calculations.dart';

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

  // 2 Optional Fields (for Key Athletes)
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

    final fatigue = int.tryParse(_fatigueCtrl.text);
    if (fatigue != null && (fatigue < 1 || fatigue > 5)) {
      _showError(s.invalidFatigue);
      return;
    }

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

    final distance = int.tryParse(_distanceCtrl.text);
    if (distance != null && distance <= 0) {
      _showError(s.invalidDistance);
      return;
    }

    double? ef = double.tryParse(_efCtrl.text);
    if (ef == null && avgPower != null && hr != null && hr > 0) {
      ef = PowerCalculations.calculateEF(avgPower, hr);
    }
    if (ef != null && ef < 0) {
      _showError(s.invalidEF);
      return;
    }

    setState(() => _isSaving = true);

    final extraData = {
      'np_watts_raw': _npWattsCtrl.text.trim(),
      'decoupling_hr_raw': _decouplingHrCtrl.text.trim(),
      'calculated_np': _calculatedNP,
      'calculated_decoupling': _calculatedDecoupling,
    };
    final playerNotesJson = jsonEncode(extraData);

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
          content: Text(s.savedSuccessfully, style: const TextStyle(color: EngineRowingUI.bgNavy, fontWeight: FontWeight.bold)),
          backgroundColor: EngineRowingUI.neonLime,
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.pop(context, true);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.redAccent,
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
        backgroundColor: EngineRowingUI.bgNavy,
        appBar: AppBar(title: Text(s.playerEntryTitle)),
        body: const Center(child: CircularProgressIndicator(color: EngineRowingUI.neonLime)),
      );
    }

    return Scaffold(
      backgroundColor: EngineRowingUI.bgNavy,
      appBar: AppBar(
        title: Text('${s.playerEntryTitle} - ${widget.player['name']}'),
        backgroundColor: EngineRowingUI.bgNavy,
        foregroundColor: EngineRowingUI.textWhite,
        elevation: 0,
      ),
      body: RowingGridBackground(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 850),
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              children: [
                // بطاقة ملخص الحصة واللاعب
                _buildSessionHeaderCard(s, zone, mhr, targetHR),
                const SizedBox(height: 16),

                // 1. المؤشرات قبل التمرين (الصباحية)
                _buildSectionHeader(s.preWorkoutSection, Icons.nightlight_round, EngineRowingUI.neonLime),
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
                _buildSectionHeader(s.duringWorkoutSection, Icons.fitness_center, EngineRowingUI.neonLime),
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
                _buildSectionHeader(s.postWorkoutSection, Icons.favorite_border, EngineRowingUI.neonLime),
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

                // 4. الحقلين الاختياريين للاعبين الأساسيين
                _buildKeyAthletesSection(s),
                const SizedBox(height: 24),

                // زر الحفظ والعودة
                FilledButton.icon(
                  onPressed: _isSaving ? null : _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: EngineRowingUI.neonLime,
                    foregroundColor: EngineRowingUI.bgNavy,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  icon: _isSaving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: EngineRowingUI.bgNavy),
                        )
                      : const Icon(Icons.check_circle_outline, size: 24, color: EngineRowingUI.bgNavy),
                  label: Text(
                    s.saveAndReturn,
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: EngineRowingUI.bgNavy),
                  ),
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSessionHeaderCard(AppStrings s, String zone, int mhr, String targetHR) {
    return Container(
      decoration: BoxDecoration(
        color: EngineRowingUI.cardFill,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: EngineRowingUI.bgGridLine),
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: EngineRowingUI.equationCardFill,
            radius: 26,
            child: Text(
              widget.player['name'].toString().isNotEmpty
                  ? widget.player['name'].toString()[0]
                  : 'P',
              style: const TextStyle(
                color: EngineRowingUI.neonLime,
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
                    color: EngineRowingUI.textWhite,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${s.workoutType}: ${widget.session['kind']} ($zone)',
                  style: const TextStyle(
                    color: EngineRowingUI.neonLime,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Directionality(
                textDirection: TextDirection.ltr,
                child: Text(
                  '${s.maxHRLabel}: $mhr bpm',
                  style: const TextStyle(
                    color: EngineRowingUI.labelSlate,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: EngineRowingUI.equationCardFill,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: EngineRowingUI.bgGridLine),
                ),
                child: Directionality(
                  textDirection: TextDirection.ltr,
                  child: Text(
                    '$targetHR bpm',
                    style: const TextStyle(
                      color: EngineRowingUI.neonLime,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
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
        Icon(icon, size: 24, color: color),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            fontSize: 18,
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
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: TextField(
          controller: ctrl,
          keyboardType: TextInputType.numberWithOptions(decimal: isDecimal),
          textInputAction: TextInputAction.next,
          textAlign: TextAlign.left,
          style: const TextStyle(
            color: EngineRowingUI.textWhite,
            fontFamily: EngineRowingUI.fontFamily,
            fontSize: 20,
            fontWeight: FontWeight.bold,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
          inputFormatters: [RowingNumberFormatter.englishDigitsInputFormatter],
          decoration: InputDecoration(
            labelText: label,
            labelStyle: const TextStyle(
              color: EngineRowingUI.labelSlate,
              fontSize: 15,
              fontWeight: FontWeight.bold,
            ),
            hintText: hint,
            hintStyle: const TextStyle(color: EngineRowingUI.captionGrey, fontSize: 13),
            isDense: true,
            filled: true,
            fillColor: EngineRowingUI.equationCardFill,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: EngineRowingUI.bgGridLine),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: EngineRowingUI.bgGridLine),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: EngineRowingUI.neonLime, width: 2.0),
            ),
          ),
        ),
      ),
    );
  }

  // 4. الحقلين الاختياريين للاعبين الأساسيين
  Widget _buildKeyAthletesSection(AppStrings s) {
    return Container(
      decoration: BoxDecoration(
        color: EngineRowingUI.cardFill,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: EngineRowingUI.bgGridLine, width: 1.2),
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
                  color: EngineRowingUI.equationCardFill,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Icon(Icons.star, color: EngineRowingUI.neonLime, size: 20),
              ),
              const SizedBox(width: 8),
              Text(
                s.keyAthletesSection,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: EngineRowingUI.textWhite,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // الحقل الأول: واط NP (قراءات متعددة)
          Directionality(
            textDirection: TextDirection.ltr,
            child: TextField(
              controller: _npWattsCtrl,
              keyboardType: TextInputType.text,
              textInputAction: TextInputAction.next,
              textAlign: TextAlign.left,
              style: const TextStyle(
                color: EngineRowingUI.textWhite,
                fontFamily: EngineRowingUI.fontFamily,
                fontSize: 18,
                fontWeight: FontWeight.bold,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
              inputFormatters: [RowingNumberFormatter.englishDigitsInputFormatter],
              decoration: InputDecoration(
                labelText: s.npWattsLabel,
                labelStyle: const TextStyle(
                  color: EngineRowingUI.labelSlate,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
                hintText: s.npWattsHint,
                hintStyle: const TextStyle(color: EngineRowingUI.captionGrey, fontSize: 13),
                prefixIcon: const Icon(Icons.electric_bolt, color: EngineRowingUI.neonLime, size: 22),
                isDense: true,
                filled: true,
                fillColor: EngineRowingUI.equationCardFill,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: EngineRowingUI.bgGridLine),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: EngineRowingUI.bgGridLine),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: EngineRowingUI.neonLime, width: 2.0),
                ),
              ),
            ),
          ),
          if (_calculatedNP != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: EngineRowingUI.equationCardFill,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: EngineRowingUI.bgGridLine),
              ),
              child: Directionality(
                textDirection: TextDirection.ltr,
                child: Row(
                  children: [
                    const Icon(Icons.check_circle, color: EngineRowingUI.neonLime, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      '${s.calculatedNP}: ',
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: EngineRowingUI.textWhite),
                    ),
                    Text(
                      '${_calculatedNP!} W',
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: EngineRowingUI.neonLime,
                      ),
                    ),
                    const Spacer(),
                    InkWell(
                      onTap: () {
                        _avgPowerCtrl.text = _calculatedNP.toString();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: EngineRowingUI.neonLime,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          'Use as Avg',
                          style: TextStyle(
                            color: EngineRowingUI.bgNavy,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 14),

          // الحقل الثاني: نبض Decoupling (قراءات متعددة)
          Directionality(
            textDirection: TextDirection.ltr,
            child: TextField(
              controller: _decouplingHrCtrl,
              keyboardType: TextInputType.text,
              textInputAction: TextInputAction.done,
              textAlign: TextAlign.left,
              style: const TextStyle(
                color: EngineRowingUI.textWhite,
                fontFamily: EngineRowingUI.fontFamily,
                fontSize: 18,
                fontWeight: FontWeight.bold,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
              inputFormatters: [RowingNumberFormatter.englishDigitsInputFormatter],
              decoration: InputDecoration(
                labelText: s.decouplingHRLabel,
                labelStyle: const TextStyle(
                  color: EngineRowingUI.labelSlate,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
                hintText: s.decouplingHRHint,
                hintStyle: const TextStyle(color: EngineRowingUI.captionGrey, fontSize: 13),
                prefixIcon: const Icon(Icons.monitor_heart, color: Colors.redAccent, size: 22),
                isDense: true,
                filled: true,
                fillColor: EngineRowingUI.equationCardFill,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: EngineRowingUI.bgGridLine),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: EngineRowingUI.bgGridLine),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: EngineRowingUI.neonLime, width: 2.0),
                ),
              ),
            ),
          ),
          if (_calculatedDecoupling != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: EngineRowingUI.equationCardFill,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: EngineRowingUI.bgGridLine),
              ),
              child: Directionality(
                textDirection: TextDirection.ltr,
                child: Row(
                  children: [
                    const Icon(Icons.analytics_outlined, color: EngineRowingUI.neonLime, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      '${s.calculatedDecoupling}: ',
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: EngineRowingUI.textWhite),
                    ),
                    Text(
                      '${_calculatedDecoupling!}% (${_calculatedDecoupling! < 5.0 ? 'Excellent' : 'Decoupled'})',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: _calculatedDecoupling! < 5.0 ? EngineRowingUI.neonLime : const Color(0xFFFF9100),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
