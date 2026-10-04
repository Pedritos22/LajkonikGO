// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lajkonik_go/main.dart';
import 'package:lajkonik_go/rewards.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'game_fixture.dart';

void main() {
  testWidgets('Explorer opens successfully', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    SharedPreferences.setMockInitialValues({});
    final rewards = RewardsController(api: FakeGameServer().api());
    await rewards.load();
    await tester.pumpWidget(MyApp(rewards: rewards));

    await tester.pump();
    expect(find.text('lajkonik'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
