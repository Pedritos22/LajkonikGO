import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lajkonik_go/game_api.dart';

class FakeGameServer {
  FakeGameServer({DateTime Function()? now}) : now = now ?? DateTime.now;
  final DateTime Function() now;
  final points = {'gps': 0, 'demo': 0};
  final owned = <String>{}, selected = <String>{};
  final claims = {'gps': <String, String>{}, 'demo': <String, String>{}};
  final requests = <http.Request>[];
  final extraPlaces = <Map<String, dynamic>>[];
  int spinReward = 50;
  bool rejectPurchase = false;
  int sessionsCreated = 0;

  Map<String, dynamic> get state => {
    'user_id': 7,
    'server_time': now().toUtc().toIso8601String(),
    'cooldown_s': 300,
    'skins': [
      {'id': 'lajkonik', 'name': 'Lajkonik', 'cost': 50},
    ],
    'places': [
      ...extraPlaces,
      {
        'key': 'sukiennice',
        'name': 'Sukiennice',
        'latitude': 50.06143,
        'longitude': 19.93658,
        'radius_m': 45.0,
        'reward': 50,
      },
      {
        'key': 'brama-florianska',
        'name': 'Brama Floriańska',
        'latitude': 50.0649,
        'longitude': 19.9411,
        'radius_m': 45.0,
        'reward': 50,
      },
      {
        'key': 'planty',
        'name': 'Planty',
        'latitude': 50.0620,
        'longitude': 19.9410,
        'radius_m': 45.0,
        'reward': 50,
      },
      {
        'key': 'wawel',
        'name': 'Wawel',
        'latitude': 50.0544,
        'longitude': 19.9354,
        'radius_m': 45.0,
        'reward': 50,
      },
    ],
    'profiles': {
      for (final profile in ['gps', 'demo'])
        profile: {
          'points': points[profile],
          'owned_skins': owned.contains(profile) ? ['lajkonik'] : [],
          'selected_skin': selected.contains(profile) ? 'lajkonik' : null,
          'claims': claims[profile],
        },
    },
  };

  GameApi api() => GameApi(
    baseUrl: 'http://test-api',
    client: MockClient((request) async {
      requests.add(request);
      final path = request.url.path;
      if (path == '/game/sessions') {
        sessionsCreated++;
        return response({'token': 'test-session-token', 'state': state}, 201);
      }
      if (request.headers['authorization'] != 'Bearer test-session-token') {
        return response({'detail': 'Brak sesji'}, 401);
      }
      if (path == '/game/state') return response(state, 200);
      final body = jsonDecode(request.body) as Map;
      final profile = body['profile'] as String;
      if (path == '/game/spins') {
        points[profile] = points[profile]! + spinReward;
        claims[profile]![body['place_key'] as String] = now()
            .toUtc()
            .toIso8601String();
      } else if (path == '/game/skins/purchase') {
        if (rejectPurchase) {
          return response({'detail': 'Serwer odrzucił zakup'}, 409);
        }
        points[profile] = points[profile]! - 50;
        owned.add(profile);
        selected.add(profile);
      } else if (path == '/game/skins/select') {
        if (body['skin_id'] == 'default') {
          selected.remove(profile);
        } else {
          selected.add(profile);
        }
      }
      return response({'state': state}, 200);
    }),
  );

  static http.Response response(Map<String, dynamic> data, int status) =>
      http.Response(
        jsonEncode(data),
        status,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
}
