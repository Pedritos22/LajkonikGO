import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lajkonik_go/main.dart';
import 'package:lajkonik_go/rewards.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'game_fixture.dart';

void main() {
  testWidgets('Map and collection use places received from the backend', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final server = FakeGameServer();
    server.extraPlaces.add({
      'key': 'plac-centralny',
      'name': 'Plac Centralny',
      'description': 'Początek odkrywania Nowej Huty',
      'category': 'square',
      'latitude': 50.07205,
      'longitude': 20.03785,
      'radius_m': 45.0,
      'reward': 50,
    });
    final rewards = RewardsController(api: server.api());
    await rewards.load();
    await tester.pumpWidget(MyApp(rewards: rewards));
    await tester.pump();
    expect(find.text('Punkty przygody · 5'), findsOneWidget);
    await tester.tap(find.byTooltip('Pokaż wszystkie punkty'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Plac Centralny · punkt przygody'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Moja kolekcja'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Plac Centralny'));
    await tester.tap(find.text('Plac Centralny'));
    await tester.pumpAndSettle();
    expect(find.text('Początek odkrywania Nowej Huty'), findsOneWidget);
    expect(find.text('Zaplanuj trasę do tego miejsca'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'Phone navigation and collection cards render without framework errors',
    (tester) async {
      tester.view.physicalSize = const Size(390, 667);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      final rewards = RewardsController(api: FakeGameServer().api());
      await rewards.load();
      await tester.pumpWidget(MyApp(rewards: rewards));
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Kolekcja'));
      await tester.pumpAndSettle();
      expect(find.text('Moja kolekcja'), findsOneWidget);
      expect(find.text('Sukiennice'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Dziennik'));
      await tester.pumpAndSettle();
      expect(find.text('Twoja historia dopiero się zaczyna.'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Kolekcja'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Sukiennice'));
      await tester.tap(find.text('Sukiennice'));
      await tester.pumpAndSettle();
      expect(find.text('Obróć punkt · +50 pkt'), findsOneWidget);
      expect(tester.takeException(), isNull);
      final plan = find.text('Zaplanuj trasę do tego miejsca');
      await tester.ensureVisible(plan);
      await tester.tap(plan);
      await tester.pumpAndSettle();
      for (final label in [
        'Pieszo',
        'Rowerem',
        'Komunikacja',
        'Samochodem',
        'Na wózku',
      ]) {
        expect(find.text(label), findsOneWidget);
      }
      await tester.tap(find.text('Na wózku'));
      await tester.pumpAndSettle();
      expect(find.textContaining('niepotwierdzoną dostępność'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
