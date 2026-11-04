import 'package:flutter_test/flutter_test.dart';
import 'package:rowing_app/app_strings.dart';

void main() {
  test('AppStrings provides correct tab labels', () {
    const s = AppStrings(true);
    expect(s.tabDashboard, isNotEmpty);
    expect(s.tabWorkouts, isNotEmpty);
    expect(s.tabSettings, isNotEmpty);
  });
}
