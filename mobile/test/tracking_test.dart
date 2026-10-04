import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:lajkonik_go/tracking.dart';

Position fix(double lat, double lng, {double accuracy = 5}) => Position(
  latitude: lat,
  longitude: lng,
  timestamp: DateTime.now(),
  accuracy: accuracy,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: 0,
  headingAccuracy: 0,
  speed: 0,
  speedAccuracy: 0,
);

class FakeLocation implements LocationSource {
  final stream = StreamController<Position>.broadcast(sync: true);
  Object? failure;
  Completer<void>? permission;
  @override
  Future<void> prepare() async {
    if (permission != null) await permission!.future;
    if (failure != null) throw failure!;
  }

  @override
  Future<Position> current() async => fix(50.06143, 19.93658);
  @override
  Stream<Position> watch() => stream.stream;
}

void main() {
  test('Live fixes update position and distance; jitter and weak GPS do not inflate route', () async {
    final source = FakeLocation();
    final tracker = TrackingController(source: source);
    await tracker.startGps();
    expect(tracker.active, isTrue);
    expect(tracker.route.length, 1);
    source.stream.add(fix(50.061431, 19.93658));
    expect(tracker.route.length, 1);
    source.stream.add(fix(50.06243, 19.93658));
    expect(tracker.distance, closeTo(111, 2));
    expect(tracker.route.length, 2);
    source.stream.add(fix(50.06443, 19.93658, accuracy: 400));
    expect(tracker.position!.latitude, 50.06443);
    expect(tracker.route.length, 2);
    tracker.setFollow(false);
    source.stream.add(fix(50.06343, 19.93658));
    expect(tracker.follow, isFalse);
    expect(tracker.position!.latitude, 50.06343);
    tracker.stop();
    source.stream.add(fix(51, 20));
    expect(tracker.position!.latitude, 50.06343);
    tracker.dispose();
    await source.stream.close();
  });

  test('Denied permission produces a recoverable state', () async {
    final source = FakeLocation()
      ..failure = StateError('Brak dostępu do lokalizacji');
    final tracker = TrackingController(source: source);
    await tracker.startGps();
    expect(tracker.error, contains('Brak dostępu'));
    expect(tracker.loading, isFalse);
    expect(tracker.active, isFalse);
    source.failure = null;
    await tracker.startGps();
    expect(tracker.active, isTrue);
    expect(tracker.error, isNull);
    tracker.dispose();
    await source.stream.close();
  });

  test(
    'Cancelling permission acquisition cannot restart GPS after demo starts',
    () async {
      final source = FakeLocation()..permission = Completer<void>();
      final tracker = TrackingController(source: source);
      final pending = tracker.startGps();
      tracker.startDemo();
      source.permission!.complete();
      await pending;
      expect(tracker.demo, isTrue);
      expect(tracker.active, isTrue);
      expect(tracker.route.length, 1);
      tracker.dispose();
      await source.stream.close();
    },
  );

  testWidgets(
    'Demo walks, records a route and stops without background updates',
    (tester) async {
      final tracker = TrackingController();
      tracker.startDemo();
      await tester.pump(const Duration(seconds: 5));
      expect(tracker.distance, greaterThan(10));
      expect(tracker.route.length, greaterThan(1));
      tracker.stop();
      final lastPosition = tracker.position;
      await tester.pump(const Duration(seconds: 5));
      expect(tracker.position, lastPosition);
      tracker.dispose();
    },
  );
}
