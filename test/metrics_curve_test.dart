import 'package:flutter_test/flutter_test.dart';
import 'package:rowing_app/heart_rate_zones.dart';
import 'package:rowing_app/power_calculations.dart';

void main() {
  group('Zone Curve & Karvonen Calculations Tests', () {
    test('Karvonen zone determination from HR, MHR and RHR', () {
      const mhr = 200;
      const rhr = 50;
      // HRR = 150
      // Z1: < 60% -> HR < 50 + 90 = 140
      // Z2: 60% to < 70% -> 140 to < 155
      // Z3: 70% to < 80% -> 155 to < 170
      // Z4: 80% to < 90% -> 170 to < 185
      // Z5: >= 90% -> >= 185

      expect(HeartRateZones.determineZone(hr: 130, mhr: mhr, rhr: rhr), equals('Z1'));
      expect(HeartRateZones.determineZone(hr: 145, mhr: mhr, rhr: rhr), equals('Z2'));
      expect(HeartRateZones.determineZone(hr: 160, mhr: mhr, rhr: rhr), equals('Z3'));
      expect(HeartRateZones.determineZone(hr: 175, mhr: mhr, rhr: rhr), equals('Z4'));
      expect(HeartRateZones.determineZone(hr: 190, mhr: mhr, rhr: rhr), equals('Z5'));
    });

    test('Daily aggregation for same zone averages watts correctly', () {
      final workouts = [
        {'date': '2026-10-20', 'zone': 'Z2', 'watts': 180.0},
        {'date': '2026-10-20', 'zone': 'Z2', 'watts': 200.0},
        {'date': '2026-10-20', 'zone': 'Z3', 'watts': 240.0},
      ];

      final Map<String, Map<String, List<double>>> zoneAccumulator = {
        'Z1': {},
        'Z2': {},
        'Z3': {},
        'Z4': {},
        'Z5': {},
      };

      for (final w in workouts) {
        final z = w['zone'] as String;
        final d = w['date'] as String;
        final p = w['watts'] as double;
        zoneAccumulator[z]!.putIfAbsent(d, () => []).add(p);
      }

      final z2List = zoneAccumulator['Z2']!['2026-10-20']!;
      final avgZ2 = z2List.reduce((a, b) => a + b) / z2List.length;
      expect(avgZ2, equals(190.0));

      final z3List = zoneAccumulator['Z3']!['2026-10-20']!;
      final avgZ3 = z3List.reduce((a, b) => a + b) / z3List.length;
      expect(avgZ3, equals(240.0));

      expect(zoneAccumulator['Z1']!['2026-10-20'], isNull);
    });

    test('Zone colors and display names mapping', () {
      expect(HeartRateZones.zoneColor('Z1').value, equals(0xFFB8F229));
      expect(HeartRateZones.zoneColor('Z2').value, equals(0xFF2979FF));
      expect(HeartRateZones.zoneColor('Z3').value, equals(0xFFFF9100));
      expect(HeartRateZones.zoneColor('Z4').value, equals(0xFFE65100));
      expect(HeartRateZones.zoneColor('Z5').value, equals(0xFFFF5252));
    });
  });
}
