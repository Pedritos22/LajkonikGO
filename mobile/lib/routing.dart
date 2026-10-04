import 'dart:convert';
import 'dart:math' as math;

import 'game_api.dart';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

enum TravelMode {
  walk('walk', 'Pieszo'),
  bike('bike', 'Rowerem'),
  transit('transit', 'Komunikacja'),
  car('car', 'Samochodem'),
  wheelchair('wheelchair', 'Na wózku');

  const TravelMode(this.api, this.label);
  final String api;
  final String label;
}

class CitySource {
  CitySource.fromJson(Map<String, dynamic> data)
    : name = data['name'] as String,
      detail = data['detail'] as String,
      status = data['status'] as String,
      url = data['url'] as String,
      updatedAt = DateTime.tryParse(data['updated_at']?.toString() ?? ''),
      fetchedAt = DateTime.tryParse(data['fetched_at']?.toString() ?? '');
  final String name, detail, status, url;
  final DateTime? updatedAt, fetchedAt;
  bool get available => status == 'available';
  String get label => switch (status) {
    'available' => 'Dane dostępne',
    'partial' => 'Dane częściowe',
    'stale' => 'Dane nieaktualne',
    _ => 'Brak danych',
  };
}

class PlannedRoute {
  PlannedRoute.fromJson(
    Map<String, dynamic> data,
    this.origin,
    this.destination,
    this.mode,
  ) : points = (data['geometry'] as List)
          .map(
            (p) => LatLng((p[0] as num).toDouble(), (p[1] as num).toDouble()),
          )
          .toList(),
      distance = (data['distance_m'] as num).toDouble(),
      duration = Duration(seconds: (data['duration_s'] as num).round()),
      warnings = (data['warnings'] as List? ?? []).cast<String>(),
      steps = (data['steps'] as List? ?? [])
          .map((s) => s['text'].toString())
          .toList(),
      sources = (data['sources'] as List)
          .map((s) => CitySource.fromJson(Map<String, dynamic>.from(s)))
          .toList(),
      bicycle = data['bicycle'] == null
          ? null
          : Map<String, dynamic>.from(data['bicycle']);
  final LatLng origin, destination;
  final TravelMode mode;
  final List<LatLng> points;
  final double distance;
  final Duration duration;
  final List<String> warnings, steps;
  final List<CitySource> sources;
  final Map<String, dynamic>? bicycle;
  String get distanceLabel => distance < 1000
      ? '${distance.round()} m'
      : '${(distance / 1000).toStringAsFixed(1).replaceAll('.', ',')} km';
  String get durationLabel =>
      '${math.max(1, (duration.inSeconds / 60).ceil())} min';
}

class RoutingService {
  RoutingService({http.Client? client, String? baseUrl})
    : client = client ?? http.Client(),
      baseUrl = baseUrl ?? apiBaseUrl;
  final http.Client client;
  final String baseUrl;

  Future<List<CitySource>> sources() async {
    final response = await client
        .get(Uri.parse('$baseUrl/city-data'))
        .timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      throw StateError('Nie można pobrać danych miasta.');
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return (data['sources'] as List)
        .map((s) => CitySource.fromJson(Map<String, dynamic>.from(s)))
        .toList();
  }

  Future<PlannedRoute> plan(
    LatLng origin,
    LatLng destination,
    TravelMode mode,
  ) async {
    final response = await client
        .post(
          Uri.parse('$baseUrl/routes'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'origin': {
              'latitude': origin.latitude,
              'longitude': origin.longitude,
            },
            'destination': {
              'latitude': destination.latitude,
              'longitude': destination.longitude,
            },
            'mode': mode.api,
          }),
        )
        .timeout(const Duration(seconds: 120));
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode != 200) {
      final detail = data['detail'];
      throw StateError(
        detail is String ? detail : 'Planowanie tras obsługuje Kraków i okolicę. Wybierz punkt w tym obszarze.',
      );
    }
    return PlannedRoute.fromJson(data, origin, destination, mode);
  }

  void dispose() => client.close();
}

double distanceToRoute(LatLng point, List<LatLng> points) {
  var best = double.infinity;
  final scale = math.cos(point.latitude * math.pi / 180);
  for (var i = 1; i < points.length; i++) {
    final a = points[i - 1], b = points[i];
    final ax = (a.longitude - point.longitude) * scale * 111195;
    final ay = (a.latitude - point.latitude) * 111195;
    final bx = (b.longitude - point.longitude) * scale * 111195;
    final by = (b.latitude - point.latitude) * 111195;
    final dx = bx - ax, dy = by - ay;
    final t = dx == 0 && dy == 0
        ? 0.0
        : (-(ax * dx + ay * dy) / (dx * dx + dy * dy)).clamp(0.0, 1.0);
    best = math.min(
      best,
      math.sqrt(math.pow(ax + t * dx, 2) + math.pow(ay + t * dy, 2)),
    );
  }
  return best;
}
