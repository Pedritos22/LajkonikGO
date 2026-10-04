import 'package:flutter_test/flutter_test.dart';
import 'package:lajkonik_go/game_api.dart';
import 'package:lajkonik_go/rewards.dart';
import 'package:lajkonik_go/tracking.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test(
    'Live frontend account: demo spin, purchase and reload from PostgreSQL',
    () async {
      SharedPreferences.setMockInitialValues({});
      final rewards = RewardsController(api: GameApi());
      await rewards.load();
      expect(rewards.error, isNull);
      expect(rewards.loaded, isTrue);
      expect(rewards.places.length, 20);
      final newPoint = rewards.places.singleWhere(
        (p) => p.name == 'Plac Centralny',
      );
      expect(
        await rewards.claim(
          place: 'Sukiennice',
          target: krakow,
          demo: true,
          position: krakow,
          accuracy: 5,
          lastFix: DateTime.now(),
        ),
        isTrue,
      );
      expect(rewards.balance(true), 50);
      expect(rewards.balance(false), 0);
      expect(await rewards.buyLajkonik(true), isTrue);
      expect(rewards.balance(true), 0);
      expect(
        await rewards.claim(
          place: newPoint.name,
          target: newPoint.position,
          demo: true,
          position: newPoint.position,
          accuracy: 5,
          lastFix: DateTime.now(),
        ),
        isTrue,
      );
      expect(rewards.balance(true), 50);
      rewards.dispose();
      final restored = RewardsController(api: GameApi());
      await restored.load();
      expect(restored.error, isNull);
      expect(restored.ownsLajkonik(true), isTrue);
      expect(restored.usesLajkonik(true), isTrue);
      expect(restored.ownsLajkonik(false), isFalse);
      expect(restored.visited('Sukiennice', true), isTrue);
      expect(restored.visited('Plac Centralny', true), isTrue);
      expect(restored.balance(true), 50);
      expect(await restored.selectLajkonik(true, false), isTrue);
      restored.dispose();
    },
    skip: !const bool.fromEnvironment('RUN_LIVE_GAME_TEST'),
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
