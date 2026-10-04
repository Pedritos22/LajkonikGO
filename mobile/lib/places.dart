import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import 'tracking.dart';

class Landmark {
  const Landmark(
    this.name,
    this.subtitle,
    this.position,
    this.icon,
    this.color,
  );
  final String name, subtitle;
  final LatLng position;
  final IconData icon;
  final Color color;

  factory Landmark.fromJson(Map<String, dynamic> data) {
    final name = data['name'] as String;
    final original = landmarks.where((place) => place.name == name).firstOrNull;
    final (icon, color) = switch (data['category']) {
      'nature' => (Icons.park_rounded, const Color(0xFF5C9272)),
      'square' => (Icons.location_city_rounded, const Color(0xFFBC8A48)),
      'bridge' => (Icons.linear_scale_rounded, const Color(0xFF588B9B)),
      'monument' => (Icons.castle_rounded, const Color(0xFF9B7970)),
      _ => (Icons.account_balance_rounded, const Color(0xFF476C42)),
    };
    return Landmark(
      name,
      data['description'] as String? ??
          original?.subtitle ??
          'Odkryj Kraków po swojemu',
      LatLng(
        (data['latitude'] as num).toDouble(),
        (data['longitude'] as num).toDouble(),
      ),
      original?.icon ?? icon,
      original?.color ?? color,
    );
  }
}

const landmarks = [
  Landmark(
    'Sukiennice',
    'Serce krakowskiego rynku',
    krakow,
    Icons.account_balance_rounded,
    Color(0xFF476C42),
  ),
  Landmark(
    'Brama Floriańska',
    'Brama do historii miasta',
    LatLng(50.0649, 19.9411),
    Icons.castle_rounded,
    Color(0xFFBC8A48),
  ),
  Landmark(
    'Planty',
    'Zielony oddech Krakowa',
    LatLng(50.0620, 19.9410),
    Icons.park_rounded,
    Color(0xFF5C9272),
  ),
  Landmark(
    'Wawel',
    'Na królewskim wzgórzu',
    LatLng(50.0544, 19.9354),
    Icons.fort_rounded,
    Color(0xFF9B7970),
  ),
];
