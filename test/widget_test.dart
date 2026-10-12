// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:rowing_app/main.dart';
import 'package:rowing_app/app_strings.dart';

void main() {
  test('AppStrings provides correct tab labels', () {
    const s = AppStrings(true);
    expect(s.tabDashboard, isNotEmpty);
    expect(s.tabWorkouts, isNotEmpty);
    expect(s.tabSettings, isNotEmpty);
  });
}
