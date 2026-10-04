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
