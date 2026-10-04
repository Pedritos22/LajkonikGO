import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import 'game_api.dart';
import 'places.dart';

/// An in-memory view of the server account. No balances or inventory in local storage.
class RewardsController extends ChangeNotifier {
  RewardsController({GameApi? api, DateTime Function()? now})
    : api = api ?? GameApi(),
      now = now ?? DateTime.now;
  final GameApi api;
  final DateTime Function() now;
  final Map<String, int> _balances = {};
  final Map<String, DateTime> _claims = {};
  final Set<String> _owned = {}, _selected = {};
  final Map<String, Map<String, dynamic>> _places = {};
  bool loaded = false;
  bool busy = false;
  bool _disposed = false;
  String? error;
  Duration _clockOffset = Duration.zero;
  int lajkonikPrice = 50;
  Duration _cooldown = const Duration(minutes: 5);
  static const radius = 45.0;
  static const reward = 50;
  static const lajkonikCost = 50;
  static const cooldown = Duration(minutes: 5);

  String _profile(bool demo) => demo ? 'demo' : 'gps';
  DateTime get _serverNow => now().add(_clockOffset);
  int balance(bool demo) => _balances[_profile(demo)] ?? 0;
  List<Landmark> get places =>
      _places.values.map(Landmark.fromJson).toList(growable: false);
  bool ownsLajkonik(bool demo) => _owned.contains(_profile(demo));
  bool usesLajkonik(bool demo) => _selected.contains(_profile(demo));
  bool visited(String place, bool demo) =>
      _claims.containsKey('${_profile(demo)}:$place');

  void _emit() {
    if (!_disposed) notifyListeners();
  }

  void _apply(Map<String, dynamic> data) {
    final profiles = data['profiles'] as Map;
    final places = (data['places'] as List)
        .map((p) => Map<String, dynamic>.from(p))
        .toList();
    _places.clear();
    for (final place in places) {
      _places[place['name'] as String] = place;
    }
    _balances.clear();
    _claims.clear();
    _owned.clear();
    _selected.clear();
    for (final profile in ['gps', 'demo']) {
      final value = profiles[profile] as Map;
      _balances[profile] = value['points'] as int;
      if ((value['owned_skins'] as List).contains('lajkonik')) {
        _owned.add(profile);
      }
      if (value['selected_skin'] == 'lajkonik') _selected.add(profile);
      for (final entry in (value['claims'] as Map).entries) {
        final place = places.where((p) => p['key'] == entry.key).firstOrNull;
        if (place != null) {
          _claims['$profile:${place['name']}'] = DateTime.parse(
            entry.value as String,
          );
        }
      }
    }
    lajkonikPrice =
        ((data['skins'] as List).firstWhere(
                  (s) => s['id'] == 'lajkonik',
                )['cost']
                as num)
            .toInt();
    _cooldown = Duration(seconds: data['cooldown_s'] as int);
    _clockOffset = DateTime.parse(data['server_time'] as String)
        .difference(now());
    loaded = true;
    error = null;
  }

  Future<void> load() async {
    if (busy || _disposed) return;
    busy = true;
    error = null;
    _emit();
    try {
      final data = await api.load();
      if (!_disposed) _apply(data);
    } catch (exception) {
      if (!_disposed) error = _message(exception);
    } finally {
      busy = false;
      _emit();
    }
  }

  String _message(Object exception) => exception is StateError
      ? exception.message.toString()
      : 'Nie udało się pobrać punktów i wyglądu. Spróbuj ponownie.';

  Future<bool> _mutate(String path, Map<String, dynamic> data) async {
    if (!loaded || busy || _disposed) return false;
    busy = true;
    error = null;
    _emit();
    try {
      final response = await api.mutate(path, data);
      if (_disposed) return false;
      _apply(response);
      return true;
    } catch (exception) {
      if (!_disposed) error = _message(exception);
      // The server may have committed even if the reply was lost. Refresh without
      // inventing a local award or charge; keep the error visible for the user.
      try {
        final response = await api.load();
        if (!_disposed) {
          final message = error;
          _apply(response);
          error = message;
        }
      } catch (_) {
        /* Keep the last confirmed state. */
      }
      return false;
    } finally {
      busy = false;
      _emit();
    }
  }

  Future<bool> buyLajkonik(bool demo) {
    if (!loaded || ownsLajkonik(demo) || balance(demo) < lajkonikPrice) {
      return Future.value(false);
    }
    return _mutate('skins/purchase', {
      'profile': _profile(demo),
      'skin_id': 'lajkonik',
    });
  }

  Future<bool> selectLajkonik(bool demo, bool selected) {
    if (selected && !ownsLajkonik(demo)) return Future.value(false);
    return _mutate('skins/select', {
      'profile': _profile(demo),
      'skin_id': selected ? 'lajkonik' : 'default',
    });
  }

  Duration remaining(String place, bool demo) {
    final last = _claims['${_profile(demo)}:$place'];
    if (last == null) return Duration.zero;
    final value = _cooldown - _serverNow.difference(last);
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
    if (!loaded) return error ?? 'Łączymy się z Twoim kontem…';
    if (busy) return 'Potwierdzamy operację…';
    final point = _places[place];
    if (point == null) return 'Punkt przygody nie jest dostępny.';
    if (position == null || lastFix == null) {
      return 'Włącz lokalizację lub spacer demo.';
    }
    if (!accuracy.isFinite || accuracy < 0 || accuracy > 25) {
      return 'Potrzebujemy dokładniejszej pozycji (do ±25 m).';
    }
    if (now().difference(lastFix) > const Duration(seconds: 30)) {
      return 'Odśwież pozycję, żeby obrócić punkt.';
    }
    final serverTarget = LatLng(
      (point['latitude'] as num).toDouble(),
      (point['longitude'] as num).toDouble(),
    );
    if (const Distance().as(LengthUnit.Meter, position, serverTarget) +
            accuracy >
        (point['radius_m'] as num)) {
      return 'Podejdź bliżej — punkt jest dostępny w promieniu ${point['radius_m'].round()} m.';
    }
    final wait = remaining(place, demo);
    if (wait > Duration.zero) {
      return 'Kolejny obrót za ${wait.inMinutes}:${(wait.inSeconds % 60).toString().padLeft(2, '0')}';
    }
    return null;
  }

  Future<bool> claim({
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
      return Future.value(false);
    }
    return _mutate('spins', {
      'profile': _profile(demo),
      'place_key': _places[place]!['key'],
      'latitude': position!.latitude,
      'longitude': position.longitude,
      'accuracy': accuracy,
      'recorded_at': lastFix!.toUtc().toIso8601String(),
    });
  }

  @override
  void dispose() {
    _disposed = true;
    api.dispose();
    super.dispose();
  }
}
