import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lajkonik_go/game_api.dart';
import 'package:lajkonik_go/rewards.dart';
import 'package:lajkonik_go/tracking.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'game_fixture.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'Spin displays server points, sends location and keeps demo separate',
    () async {
      var now = DateTime.utc(2026, 10, 4, 12);
      final server = FakeGameServer(now: () => now)..spinReward = 33;
      final rewards = RewardsController(api: server.api(), now: () => now);
      await rewards.load();
      Future<bool> claim(bool demo) => rewards.claim(
        place: 'Sukiennice',
        target: krakow,
        demo: demo,
        position: krakow,
        accuracy: 5,
        lastFix: now,
      );
      expect(await claim(true), isTrue);
      expect(rewards.balance(true), 33);
      expect(rewards.balance(false), 0);
      expect(await claim(true), isFalse);
      expect(await claim(false), isTrue);
      final body = jsonDecode(server.requests.last.body) as Map;
      expect(body['place_key'], 'sukiennice');
      expect(body['latitude'], krakow.latitude);
      expect(body['profile'], 'gps');
      expect(body.containsKey('points'), isFalse);
      expect(body['request_id'], matches(RegExp(r'^[0-9a-f-]{36}$')));
      now = now.add(const Duration(minutes: 5));
      expect(await claim(true), isTrue);
      expect(rewards.balance(true), 66);
      rewards.dispose();
    },
  );

  test('Purchase and selected skin reload from server; only session token stays local', () async {
    final server = FakeGameServer();
    server.points['gps'] = 50;
    var rewards = RewardsController(api: server.api());
    await rewards.load();
    expect(await rewards.buyLajkonik(true), isFalse);
    expect(await rewards.buyLajkonik(false), isTrue);
    expect(rewards.balance(false), 0);
    expect(await rewards.buyLajkonik(false), isFalse);
    expect(await rewards.selectLajkonik(false, false), isTrue);
    rewards.dispose();
    rewards = RewardsController(api: server.api());
    await rewards.load();
    expect(server.sessionsCreated, 1);
    expect(rewards.ownsLajkonik(false), isTrue);
    expect(rewards.usesLajkonik(false), isFalse);
    expect(await rewards.selectLajkonik(false, true), isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys(), {'lajkonik.session.v1:http://test-api'});
    rewards.dispose();
  });

  test(
    'Rejected purchase cannot locally spend points or unlock a skin',
    () async {
      final server = FakeGameServer()..rejectPurchase = true;
      server.points['gps'] = 50;
      final rewards = RewardsController(api: server.api());
      await rewards.load();
      expect(await rewards.buyLajkonik(false), isFalse);
      expect(rewards.balance(false), 50);
      expect(rewards.ownsLajkonik(false), isFalse);
      expect(rewards.error, 'Serwer odrzucił zakup');
      rewards.dispose();
    },
  );

  test(
    'Unreachable backend does not restore legacy browser points or skins',
    () async {
      SharedPreferences.setMockInitialValues({
        'lajkonik.rewards.v1': jsonEncode({
          'balances': {'gps': 9999},
          'claims': {},
          'lajkonikOwned': ['gps'],
        }),
      });
      final rewards = RewardsController(
        api: GameApi(client: MockClient((_) async => http.Response('{}', 503))),
      );
      await rewards.load();
      expect(rewards.loaded, isFalse);
      expect(rewards.balance(false), 0);
      expect(rewards.ownsLajkonik(false), isFalse);
      expect(rewards.error, isNotNull);
      rewards.dispose();
    },
  );

  test(
    'Retry after a lost reply uses exactly the same operation ID and body',
    () async {
      final requests = <String>[];
      final server = FakeGameServer();
      final api = GameApi(
        token: 'test-session-token',
        client: MockClient((request) async {
          if (request.url.path.endsWith('/state')) {
            return FakeGameServer.response(server.state, 200);
          }
          requests.add(request.body);
          if (requests.length == 1) throw http.ClientException('lost reply');
          return FakeGameServer.response({'state': server.state}, 200);
        }),
      );
      await api.load();
      await api.mutate('skins/select', {
        'profile': 'gps',
        'skin_id': 'default',
      });
      expect(requests.length, 2);
      expect(requests.first, requests.last);
      api.dispose();
    },
  );

  test(
    'Distant, stale, imprecise or missing fixes do not request a spin',
    () async {
      final now = DateTime.utc(2026, 10, 4, 12);
      final server = FakeGameServer(now: () => now);
      final rewards = RewardsController(api: server.api(), now: () => now);
      await rewards.load();
      Future<bool> claim({
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
      expect(await claim(position: const LatLng(50.0649, 19.9411)), isFalse);
      expect(await claim(accuracy: 60), isFalse);
      expect(await claim(accuracy: double.nan), isFalse);
      expect(
        await claim(fix: now.subtract(const Duration(seconds: 31))),
        isFalse,
      );
      expect(await claim(position: null), isFalse);
      expect(
        server.requests.where((r) => r.url.path == '/game/spins'),
        isEmpty,
      );
      rewards.dispose();
    },
  );
}
