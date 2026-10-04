import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lajkonik_go/rewards.dart';
import 'package:lajkonik_go/skin_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'game_fixture.dart';

void main() {
  testWidgets(
    'Phone skin shop spends points, equips Lajkonik and switches back for free',
    (tester) async {
      tester.view.physicalSize = const Size(390, 667);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      final server = FakeGameServer();
      server.points['gps'] = 50;
      final rewards = RewardsController(api: server.api());
      await rewards.load();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(28),
              child: SkinCard(rewards: rewards, demo: false),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Odblokuj · 50 pkt'));
      await tester.pumpAndSettle();
      expect(rewards.balance(false), 0);
      expect(find.text('Lajkonik wybrany'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Użyj zwykłego znacznika'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Użyj Lajkonika'));
      await tester.pumpAndSettle();
      expect(rewards.usesLajkonik(false), isTrue);
      expect(rewards.balance(false), 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      rewards.dispose();
    },
  );
}
