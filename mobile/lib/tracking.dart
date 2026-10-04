import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

const krakow = LatLng(50.06143, 19.93658);

abstract class LocationSource {
  Future<void> prepare();
  Future<Position> current();
  Stream<Position> watch();
}

class DeviceLocation implements LocationSource {
  @override
  Future<void> prepare() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw StateError(
        'Włącz lokalizację na swoim urządzeniu i spróbuj ponownie.',
      );
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw StateError(
        'Brak dostępu do lokalizacji. Zezwól na lokalizację w ustawieniach przeglądarki lub urządzenia.',
      );
    }
  }

  @override
  Future<Position> current() => Geolocator.getCurrentPosition(
    locationSettings: const LocationSettings(
      accuracy: LocationAccuracy.high,
      timeLimit: Duration(seconds: 20),
    ),
  );

  @override
  Stream<Position> watch() => Geolocator.getPositionStream(
    locationSettings: const LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 3,
    ),
  );
}

class TrackingController extends ChangeNotifier {
  TrackingController({LocationSource? source})
    : source = source ?? DeviceLocation();
  final LocationSource source;
  StreamSubscription<Position>? _subscription;
  Timer? _demoTimer;
  Timer? _clock;
  final Stopwatch _stopwatch = Stopwatch();
  int _generation = 0;
  bool _disposed = false;
  bool active = false;
  bool loading = false;
  bool demo = false;
  bool follow = true;
  String? error;
  LatLng? position;
  DateTime? lastFix;
  double accuracy = 0;
  double distance = 0;
  double heading = 0;
  final List<LatLng> _route = [];
  List<LatLng> get route => List.unmodifiable(_route);
  Duration get elapsed => _stopwatch.elapsed;

  void _emit() {
    if (!_disposed) notifyListeners();
  }

  void setFollow(bool value) {
    follow = value;
    _emit();
  }

  Future<void> startGps() async {
    final generation = ++_generation;
    _halt();
    _reset();
    demo = false;
    loading = true;
    error = null;
    _emit();
    try {
      await source.prepare();
      if (_disposed || generation != _generation) return;
      final initial = await source.current();
      if (_disposed || generation != _generation) return;
      active = true;
      loading = false;
      _startClock();
      _accept(initial);
      _subscription = source.watch().listen(
        (value) {
          if (generation == _generation) _accept(value);
        },
        onError: (Object exception) {
          if (generation == _generation) _fail(exception);
        },
        onDone: () {
          if (generation == _generation && active) {
            _fail(
              StateError(
                'Śledzenie lokalizacji zakończyło się. Uruchom GPS ponownie.',
              ),
            );
          }
        },
      );
    } catch (exception) {
      if (!_disposed && generation == _generation) _fail(exception);
    }
  }

  void _fail(Object exception) {
    _halt();
    loading = false;
    error = exception is StateError
        ? exception.message.toString()
        : exception is TimeoutException
        ? 'Nie udało się ustalić pozycji. Spróbuj ponownie na zewnątrz lub włącz demo.'
        : 'Nie można odczytać lokalizacji. Sprawdź GPS i uprawnienia, a następnie spróbuj ponownie.';
    _emit();
  }

  void _accept(Position value) {
    if (!value.latitude.isFinite ||
        !value.longitude.isFinite ||
        value.latitude.abs() > 90 ||
        value.longitude.abs() > 180) {
      return;
    }
    accuracy = value.accuracy;
    heading = value.heading.isFinite && value.heading >= 0 ? value.heading : 0;
    final next = LatLng(value.latitude, value.longitude);
    position = next;
    lastFix = value.timestamp;
    // Inaccurate fixes are visible, but do not inflate the walking distance.
    if (accuracy.isFinite && accuracy >= 0 && accuracy <= 100) {
      _record(next);
    }
    _emit();
  }

  void _record(LatLng next) {
    if (_route.isNotEmpty) {
      final delta = const Distance().as(LengthUnit.Meter, _route.last, next);
      if (delta < 3) return;
      distance += delta;
    }
    _route.add(next);
    // Bound memory for long sessions while retaining the recent route.
    if (_route.length > 5000) _route.removeAt(0);
  }

  void startDemo() {
    ++_generation;
    _halt();
    _reset();
    demo = true;
    active = true;
    loading = false;
    error = null;
    accuracy = 5;
    position = demoPath.first;
    lastFix = DateTime.now();
    _record(position!);
    _startClock();
    var segment = 0;
    var step = 0;
    _demoTimer = Timer.periodic(const Duration(milliseconds: 700), (_) {
      step++;
      final a = demoPath[segment];
      final b = demoPath[segment + 1];
      final t = step / 16;
      position = LatLng(
        a.latitude + (b.latitude - a.latitude) * t,
        a.longitude + (b.longitude - a.longitude) * t,
      );
      heading = const Distance().bearing(a, b);
      lastFix = DateTime.now();
      _record(position!);
      if (step == 16) {
        segment++;
        step = 0;
      }
      if (segment == demoPath.length - 1) _halt();
      _emit();
    });
    _emit();
  }

  void stop() {
    ++_generation;
    _halt();
    loading = false;
    _emit();
  }

  void _startClock() {
    _stopwatch.start();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) => _emit());
  }

  void _reset() {
    _route.clear();
    distance = 0;
    position = null;
    lastFix = null;
    accuracy = 0;
    follow = true;
    _stopwatch.reset();
  }

  void _halt() {
    _subscription?.cancel();
    _subscription = null;
    _demoTimer?.cancel();
    _clock?.cancel();
    _stopwatch.stop();
    active = false;
  }

  Future<void> refreshPosition() async {
    if (demo || loading) return;
    final generation = _generation;
    try {
      final value = await source.current();
      if (!_disposed && generation == _generation) _accept(value);
    } catch (_) {
      error =
          'Nie udało się odświeżyć pozycji. Sprawdź GPS i spróbuj ponownie.';
      _emit();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    _halt();
    super.dispose();
  }
}

const demoPath = [
  krakow,
  LatLng(50.0619, 19.9374),
  LatLng(50.0625, 19.9381),
  LatLng(50.0641, 19.9390),
  LatLng(50.0653, 19.9400),
  LatLng(50.0649, 19.9411),
  LatLng(50.0639, 19.9410),
  LatLng(50.0620, 19.9410),
  LatLng(50.0621, 19.9401),
  LatLng(50.0605, 19.9388),
  LatLng(50.0593, 19.9377),
  LatLng(50.0571, 19.9372),
  LatLng(50.0544, 19.9354),
];
