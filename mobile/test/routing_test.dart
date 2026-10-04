import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lajkonik_go/routing.dart';
import 'package:lajkonik_go/tracking.dart';
import 'package:latlong2/latlong.dart';

void main() {
  test(
    'Planning sends the selected mode and preserves unknown city data',
    () async {
      final service = RoutingService(
        client: MockClient((request) async {
          final body = jsonDecode(request.body);
          expect(body['mode'], 'wheelchair');
          expect(body['origin']['latitude'], krakow.latitude);
          return http.Response(
            jsonEncode({
              'geometry': [
                [50.06143, 19.93658],
                [50.0649, 19.9411],
              ],
              'distance_m': 500,
              'duration_s': 700,
              'steps': [],
              'warnings': ['Dostępność niepotwierdzona'],
              'sources': [
                {
                  'name': 'Bariery',
                  'status': 'unconfigured',
                  'detail': 'Brak wykazu',
                  'url': 'https://msip.krakow.pl/',
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      final result = await service.plan(
        krakow,
        const LatLng(50.0649, 19.9411),
        TravelMode.wheelchair,
      );
      expect(result.sources.single.available, isFalse);
      expect(result.warnings, contains('Dostępność niepotwierdzona'));
      expect(result.points.length, 2);
      service.dispose();
    },
  );

  test(
    'A failed route never becomes a fabricated straight-line itinerary',
    () async {
      final service = RoutingService(
        client: MockClient(
          (_) async => http.Response(
            '{"detail":"Brak połączenia"}',
            422,
            headers: {'content-type': 'application/json; charset=utf-8'},
          ),
        ),
      );
      await expectLater(
        service.plan(
          krakow,
          const LatLng(50.0649, 19.9411),
          TravelMode.transit,
        ),
        throwsStateError,
      );
      service.dispose();
    },
  );
}
