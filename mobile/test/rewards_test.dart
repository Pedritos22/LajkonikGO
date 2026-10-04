import 'package:flutter_test/flutter_test.dart';
import 'package:lajkonik_go/rewards.dart';
import 'package:lajkonik_go/tracking.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('A nearby spin earns points once, enforces cooldown and keeps demo separate', () async {
    SharedPreferences.setMockInitialValues({});
    var now = DateTime(2026, 10, 4, 12);
    final rewards = RewardsController(now: () => now);
    await rewards.load();
    bool claim(bool demo) => rewards.claim(
      place: 'Sukiennice',
      target: krakow,
      demo: demo,
      position: krakow,
      accuracy: 5,
      lastFix: now,
    );
    expect(claim(true), isTrue);
    expect(rewards.balance(true), 50);
    expect(rewards.balance(false), 0);
    expect(claim(true), isFalse);
    expect(rewards.balance(true), 50);
    expect(claim(false), isTrue);
    expect(rewards.balance(false), 50);
    now = now.add(const Duration(minutes: 5));
    expect(claim(true), isTrue);
    expect(rewards.balance(true), 100);
    rewards.dispose();
  });

  test(
    'Distant, stale, imprecise and missing positions cannot earn points',
    () async {
      SharedPreferences.setMockInitialValues({});
      final now = DateTime(2026, 10, 4, 12);
      final rewards = RewardsController(now: () => now);
      await rewards.load();
      bool claim({
        LatLng? position = krakow,
        double accuracy = 5,
        DateTime? fix,
      }) => rewards.claim(
        place: 'Sukiennice',
        target: krakow,
        demo: false,
        position: position,
        accuracy: accuracy,
        lastFix: fix ?? now,
      );
      expect(claim(position: const LatLng(50.0649, 19.9411)), isFalse);
      expect(claim(accuracy: 60), isFalse);
      expect(claim(accuracy: double.nan), isFalse);
      expect(claim(fix: now.subtract(const Duration(seconds: 31))), isFalse);
      expect(claim(position: null), isFalse);
      expect(rewards.balance(false), 0);
      rewards.dispose();
    },
  );
}
