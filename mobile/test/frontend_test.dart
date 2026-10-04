import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lajkonik_go/main.dart';

void main() {
  testWidgets(
    'Phone navigation and collection cards render without framework errors',
    (tester) async {
      tester.view.physicalSize = const Size(390, 667);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const MyApp());
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
