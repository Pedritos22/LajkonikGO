import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

class RewardsController extends ChangeNotifier {
  RewardsController({DateTime Function()? now}) : now = now ?? DateTime.now;
  final DateTime Function() now;
  final Map<String, int> balances = {};
  final Map<String, DateTime> claims = {};
  bool loaded = false;
  bool persistent = true;
  bool _disposed = false;
  Future<void> _saving = Future.value();
  static const radius = 45.0;
  static const reward = 50;
  static const cooldown = Duration(minutes: 5);

  String _key(String place, bool demo) => '${demo ? 'demo' : 'gps'}:$place';
  int balance(bool demo) => balances[demo ? 'demo' : 'gps'] ?? 0;
  bool visited(String place, bool demo) =>
      claims.containsKey(_key(place, demo));

  Duration remaining(String place, bool demo) {
    final last = claims[_key(place, demo)];
    if (last == null) return Duration.zero;
    final value = cooldown - now().difference(last);
    return value.isNegative ? Duration.zero : value;
  }

  String? reason({
    required String place,
    required LatLng target,
    required bool demo,
    required LatLng? position,
    required double accuracy,
    required DateTime? lastFix,
  }) {
    if (!loaded) return 'Wczytujemy Twoje punkty…';
    if (position == null || lastFix == null) {
      return 'Włącz lokalizację lub spacer demo.';
    }
    if (!accuracy.isFinite || accuracy < 0 || accuracy > 25) {
      return 'Potrzebujemy dokładniejszej pozycji (do ±25 m).';
    }
    if (now().difference(lastFix) > const Duration(seconds: 30)) {
      return 'Odśwież pozycję, żeby obrócić punkt.';
    }
    if (const Distance().as(LengthUnit.Meter, position, target) + accuracy >
        radius) {
      return 'Podejdź bliżej — punkt jest dostępny w promieniu 45 m.';
    }
    final wait = remaining(place, demo);
    if (wait > Duration.zero) {
      return 'Kolejny obrót za ${wait.inMinutes}:${(wait.inSeconds % 60).toString().padLeft(2, '0')}';
    }
    return null;
  }

  bool claim({
    required String place,
    required LatLng target,
    required bool demo,
    required LatLng? position,
    required double accuracy,
    required DateTime? lastFix,
  }) {
    if (reason(
          place: place,
          target: target,
          demo: demo,
          position: position,
          accuracy: accuracy,
          lastFix: lastFix,
        ) !=
        null) {
      return false;
    }
    claims[_key(place, demo)] = now();
    final profile = demo ? 'demo' : 'gps';
    balances[profile] = balance(demo) + reward;
    notifyListeners();
    _save();
    return true;
  }

  Future<void> load() async {
    try {
      final store = await SharedPreferences.getInstance();
      final raw = store.getString('lajkonik.rewards.v1');
      if (raw != null) {
        final data = jsonDecode(raw) as Map<String, dynamic>;
        for (final entry in (data['balances'] as Map).entries) {
          if (entry.value is int && entry.value >= 0) {
            balances[entry.key as String] = entry.value as int;
          }
        }
        for (final entry in (data['claims'] as Map).entries) {
          final date = DateTime.tryParse(entry.value.toString());
          if (date != null) claims[entry.key as String] = date;
        }
      }
    } catch (_) {
      persistent = false;
    }
    loaded = true;
    if (!_disposed) notifyListeners();
  }

  void _save() {
    final value = jsonEncode({
      'balances': balances,
      'claims': claims.map(
        (key, value) => MapEntry(key, value.toIso8601String()),
      ),
    });
    _saving = _saving.then((_) async {
      try {
        final store = await SharedPreferences.getInstance();
        if (!await store.setString('lajkonik.rewards.v1', value)) {
          throw StateError('Save failed');
        }
      } catch (_) {
        persistent = false;
        if (!_disposed) notifyListeners();
      }
    });
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
