import 'dart:math' as math;
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import 'tracking.dart';
import 'places.dart';
import 'rewards.dart';
import 'point_sheet.dart';
import 'routing.dart';
import 'route_sheet.dart';

const ink = Color(0xFF283B2D);
const green = Color(0xFF476C42);
const lime = Color(0xFFD9EDAC);
const cream = Color(0xFFF7F8F2);
const muted = Color(0xFF7C8478);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Keep the canvas UI accessible to browsers, keyboards and screen readers.
  SemanticsBinding.instance.ensureSemantics();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Lajkonik GO · Odkrywaj po swojemu',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: cream,
      colorScheme: ColorScheme.fromSeed(seedColor: green, surface: cream),
      fontFamily: 'Segoe UI',
      textTheme: const TextTheme(bodyMedium: TextStyle(color: ink)),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: green,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
        ),
      ),
    ),
    home: const ExplorePage(),
  );
}

class ExplorePage extends StatefulWidget {
  const ExplorePage({super.key});
  @override
  State<ExplorePage> createState() => _ExplorePageState();
}

class _ExplorePageState extends State<ExplorePage>
    with SingleTickerProviderStateMixin {
  late final TrackingController tracker;
  final map = MapController();
  late final AnimationController motion;
  bool ready = false;
  bool mapFailed = false;
  LatLng? lastTarget;
  LatLng from = krakow;
  LatLng to = krakow;
  int selectedTab = 0;
  final RewardsController rewards = RewardsController();
  final RoutingService routing = RoutingService();
  PlannedRoute? planned;
  Landmark? routePlace;
  DateTime lastRouting = DateTime.now();
  bool refreshingRoute = false;
  int routeGeneration = 0;
  String? routeError;

  @override
  void initState() {
    super.initState();
    tracker = TrackingController()..addListener(_onTracking);
    rewards.addListener(_onRewards);
    unawaited(rewards.load());
    motion =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 600),
        )..addListener(() {
          if (!ready || !tracker.follow) return;
          final t = Curves.easeInOut.transform(motion.value);
          map.move(
            LatLng(
              from.latitude + (to.latitude - from.latitude) * t,
              from.longitude + (to.longitude - from.longitude) * t,
            ),
            map.camera.zoom,
          );
        });
  }

  void _onTracking() {
    if (!mounted) return;
    final target = tracker.position;
    if (target != null && ready && tracker.follow && target != lastTarget) {
      from = map.camera.center;
      to = target;
      lastTarget = target;
      // Avoid an animated trip across the world when acquiring the first fix.
      if (const Distance().as(LengthUnit.Kilometer, from, target) > 2) {
        motion.stop();
        map.move(target, map.camera.zoom);
      } else {
        motion.forward(from: 0);
      }
    }
    final plan = planned;
    if (plan != null && target != null && tracker.active && !refreshingRoute) {
      final elapsed = DateTime.now().difference(lastRouting);
      if (elapsed >= const Duration(minutes: 5) ||
          (elapsed >= const Duration(seconds: 45) &&
              tracker.accuracy <= 25 &&
              distanceToRoute(target, plan.points) > 60)) {
        unawaited(_refreshRoute());
      }
    }
    setState(() {});
  }

  void _recenter() {
    tracker.setFollow(true);
    lastTarget = null;
    _onTracking();
    if (tracker.position == null && ready) map.move(krakow, 16);
  }

  void _onRewards() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    tracker.removeListener(_onTracking);
    tracker.dispose();
    ++routeGeneration;
    rewards.removeListener(_onRewards);
    rewards.dispose();
    routing.dispose();
    motion.dispose();
    map.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 1000;
    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            if (wide) _sidebar(),
            Expanded(
              child: Column(
                children: [
                  _header(wide),
                  Expanded(
                    child: IndexedStack(
                      index: selectedTab == 0 ? 0 : 1,
                      children: [_mapView(wide), _otherPage()],
                    ),
                  ),
                  if (!wide) _mobileNav(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sidebar() => Container(
    width: 278,
    decoration: const BoxDecoration(
      color: cream,
      border: Border(right: BorderSide(color: Color(0xFFE3E6DA))),
    ),
    padding: const EdgeInsets.fromLTRB(26, 33, 26, 22),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _brand(),
        const SizedBox(height: 42),
        _eyebrow('TWOJA PRZYGODA'),
        const SizedBox(height: 14),
        _nav(0, Icons.explore_outlined, 'Odkrywaj'),
        _nav(1, Icons.auto_stories_outlined, 'Dziennik spaceru'),
        _nav(2, Icons.collections_bookmark_outlined, 'Moja kolekcja'),
        const Spacer(),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFFEBEFDF),
            borderRadius: BorderRadius.circular(22),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.local_florist_outlined, color: green, size: 30),
              const SizedBox(height: 14),
              const Text(
                'Mały spacer.\nWielka przygoda.',
                style: TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w700,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Miasto ma swoje sekrety.\nOdkryj je krok po kroku.',
                style: TextStyle(color: muted, fontSize: 13, height: 1.6),
              ),
              const SizedBox(height: 15),
              TextButton(
                onPressed: _startDemo,
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  foregroundColor: green,
                ),
                child: const Row(
                  children: [
                    Text('Wypróbuj spacer demo'),
                    SizedBox(width: 7),
                    Icon(Icons.arrow_forward, size: 16),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 25),
        const Divider(color: Color(0xFFE0E4D6)),
        const SizedBox(height: 12),
        Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(
                color: lime,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.person_outline_rounded, color: green),
            ),
            const SizedBox(width: 11),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Odkrywca',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    'Twoja lokalna przygoda',
                    style: TextStyle(fontSize: 11, color: muted),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: _settings,
              tooltip: 'Ustawienia',
              icon: const Icon(Icons.settings_outlined, size: 19, color: muted),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _brand() => const Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(Icons.explore_rounded, size: 35, color: green),
      SizedBox(width: 10),
      Text(
        'lajkonik',
        style: TextStyle(
          fontSize: 26,
          fontWeight: FontWeight.w800,
          letterSpacing: -1.3,
        ),
      ),
      SizedBox(width: 5),
      Text(
        'GO',
        style: TextStyle(
          fontSize: 13,
          color: green,
          fontWeight: FontWeight.w900,
        ),
      ),
    ],
  );

  Widget _nav(int index, IconData icon, String label) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Material(
      color: selectedTab == index ? green : Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => setState(() => selectedTab = index),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 17),
          child: Row(
            children: [
              Icon(icon, size: 21, color: selectedTab == index ? lime : muted),
              const SizedBox(width: 13),
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: selectedTab == index ? Colors.white : ink,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _header(bool wide) => Container(
    height: wide ? 91 : 74,
    padding: EdgeInsets.symmetric(horizontal: wide ? 32 : 18),
    child: Row(
      children: [
        if (wide)
          const Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Czas na małą przygodę',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.6,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  'Wyjdź na zewnątrz. Resztę podpowie miasto.',
                  style: TextStyle(fontSize: 13, color: muted),
                ),
              ],
            ),
          )
        else
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: _brand(),
            ),
          ),
        if (wide)
          _pill(
            Icons.place_outlined,
            tracker.active && !tracker.demo
                ? 'Twoja okolica'
                : 'Kraków · podgląd',
            Colors.white,
          ),
        const SizedBox(width: 12),
        _pill(
          Icons.stars_rounded,
          '${rewards.balance(tracker.demo)}${tracker.demo ? ' demo' : ''}',
          const Color(0xFFEBEFDF),
        ),
        IconButton(
          onPressed: _help,
          tooltip: 'Jak to działa?',
          icon: const Icon(Icons.help_outline_rounded, color: muted, size: 22),
        ),
      ],
    ),
  );

  Widget _mapView(bool wide) => Padding(
    padding: EdgeInsets.fromLTRB(
      wide ? 12 : 0,
      0,
      wide ? 22 : 0,
      wide ? 20 : 0,
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(wide ? 26 : 0),
      child: Stack(
        children: [
          Positioned.fill(
            child: FlutterMap(
              mapController: map,
              options: MapOptions(
                initialCenter: krakow,
                initialZoom: 16,
                minZoom: 3,
                maxZoom: 19,
                backgroundColor: const Color(0xFFE5EAD7),
                onMapReady: () {
                  ready = true;
                  _onTracking();
                },
                onPositionChanged: (_, gesture) {
                  if (gesture && tracker.follow) tracker.setFollow(false);
                },
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'pl.lajkonik.go',
                  errorTileCallback: (_, _, _) {
                    if (!mapFailed && mounted) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) setState(() => mapFailed = true);
                      });
                    }
                  },
                  tileBuilder: (_, tile, _) => ColorFiltered(
                    colorFilter: const ColorFilter.matrix([
                      .82,
                      .12,
                      .06,
                      0,
                      3,
                      .08,
                      .86,
                      .06,
                      0,
                      7,
                      .10,
                      .18,
                      .65,
                      0,
                      0,
                      0,
                      0,
                      0,
                      1,
                      0,
                    ]),
                    child: tile,
                  ),
                ),
                if (planned != null)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: planned!.points,
                        strokeWidth: 6,
                        color: const Color(0xFF5678B4),
                        borderStrokeWidth: 2,
                        borderColor: Colors.white,
                      ),
                    ],
                  ),
                if (planned != null && tracker.position == null)
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: planned!.origin,
                        width: 36,
                        height: 36,
                        child: const Tooltip(
                          message: 'Start podglądu: Dworzec Główny',
                          child: Icon(
                            Icons.trip_origin,
                            color: Color(0xFF5678B4),
                            size: 28,
                          ),
                        ),
                      ),
                    ],
                  ),
                if (tracker.route.length > 1)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: tracker.route,
                        strokeWidth: 5,
                        color: green,
                        borderStrokeWidth: 2,
                        borderColor: Colors.white,
                      ),
                    ],
                  ),
                if (tracker.position != null && tracker.accuracy.isFinite)
                  CircleLayer(
                    circles: [
                      CircleMarker(
                        point: tracker.position!,
                        radius: tracker.accuracy.clamp(5, 250),
                        useRadiusInMeter: true,
                        color: green.withValues(alpha: .09),
                        borderColor: green.withValues(alpha: .2),
                        borderStrokeWidth: 1,
                      ),
                    ],
                  ),
                MarkerLayer(
                  markers: [
                    for (final landmark in landmarks)
                      Marker(
                        point: landmark.position,
                        width: 64,
                        height: 76,
                        child: Tooltip(
                          message: '${landmark.name} · punkt przygody',
                          child: GestureDetector(
                            onTap: () => _landmarkSheet(landmark),
                            child: Column(
                              children: [
                                Container(
                                  width: 48,
                                  height: 48,
                                  decoration: BoxDecoration(
                                    color: landmark.color,
                                    borderRadius: BorderRadius.circular(17),
                                    border: Border.all(
                                      color: Colors.white,
                                      width: 3,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: ink.withValues(alpha: .18),
                                        blurRadius: 12,
                                        offset: const Offset(0, 5),
                                      ),
                                    ],
                                  ),
                                  child: Icon(
                                    landmark.icon,
                                    color: Colors.white,
                                    size: 25,
                                  ),
                                ),
                                Icon(
                                  Icons.arrow_drop_down,
                                  color: landmark.color,
                                  size: 22,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    if (tracker.position != null)
                      Marker(
                        point: tracker.position!,
                        width: 88,
                        height: 88,
                        child: Semantics(
                          label: tracker.demo
                              ? 'Pozycja demonstracyjna'
                              : 'Twoja pozycja',
                          child: Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: green.withValues(alpha: .13),
                              border: Border.all(
                                color: green.withValues(alpha: .24),
                              ),
                            ),
                            padding: const EdgeInsets.all(19),
                            child: Transform.rotate(
                              angle: tracker.heading * math.pi / 180,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: green,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white,
                                    width: 4,
                                  ),
                                  boxShadow: const [
                                    BoxShadow(
                                      color: Color(0x30476C42),
                                      blurRadius: 15,
                                    ),
                                  ],
                                ),
                                child: const Icon(
                                  Icons.navigation_rounded,
                                  color: lime,
                                  size: 25,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                RichAttributionWidget(
                  alignment: AttributionAlignment.bottomLeft,
                  attributions: [
                    TextSourceAttribution(
                      'OpenStreetMap contributors',
                      onTap: () => launchUrl(
                        Uri.parse('https://www.openstreetmap.org/copyright'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (planned == null)
            Positioned(
              top: 22,
              left: wide ? 25 : 16,
              right: wide ? null : 16,
              child: Container(
                width: wide ? 350 : null,
                padding: const EdgeInsets.all(20),
                decoration: _card(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: tracker.active
                                ? green
                                : const Color(0xFFBE9A5E),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            tracker.demo
                                ? 'SPACER DEMONSTRACYJNY'
                                : tracker.active
                                ? 'LOKALIZACJA NA ŻYWO'
                                : 'TWÓJ ŚWIAT CZEKA',
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: green,
                              letterSpacing: 1.5,
                            ),
                          ),
                        ),
                        if (tracker.active)
                          const Icon(Icons.sensors, size: 18, color: green),
                      ],
                    ),
                    const SizedBox(height: 11),
                    Text(
                      tracker.active
                          ? 'Idź. Odkrywaj. Powtarzaj.'
                          : 'Przygoda zaczyna się tutaj.',
                      style: TextStyle(
                        fontSize: wide ? 23 : 20,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -.7,
                      ),
                    ),
                    if (wide ||
                        MediaQuery.sizeOf(context).height >= 740 ||
                        tracker.error != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        tracker.error ??
                            (tracker.loading
                                ? 'Ustalamy Twoją pozycję…'
                                : tracker.active
                                ? tracker.demo
                                      ? 'Wirtualny spacer po Krakowie. Mapa podąża za znacznikiem.'
                                      : 'Mapa podąża za Tobą. Każdy krok tworzy Twoją trasę.'
                                : 'Włącz lokalizację i zobacz, dokąd\nzaprowadzą Cię Twoje kroki.'),
                        style: TextStyle(
                          color: tracker.error != null
                              ? const Color(0xFFAA573B)
                              : muted,
                          fontSize: 13,
                          height: 1.5,
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: tracker.active || tracker.loading
                            ? tracker.stop
                            : tracker.startGps,
                        icon: tracker.loading
                            ? const SizedBox(
                                width: 17,
                                height: 17,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Icon(
                                tracker.active
                                    ? Icons.pause_rounded
                                    : Icons.near_me_outlined,
                                size: 18,
                              ),
                        label: Text(
                          tracker.loading
                              ? 'Anuluj'
                              : tracker.active
                              ? 'Zakończ spacer'
                              : 'Włącz lokalizację',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                    if (!tracker.active && !tracker.loading)
                      Center(
                        child: TextButton(
                          onPressed: _startDemo,
                          child: const Text(
                            'Najpierw sprawdzę demo →',
                            style: TextStyle(fontSize: 12, color: green),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          if (wide)
            Positioned(
              top: 24,
              right: 25,
              child: _pill(
                Icons.auto_awesome_outlined,
                'Punkty przygody · 4',
                Colors.white,
              ),
            ),
          Positioned(
            right: wide ? 25 : 16,
            bottom: planned != null
                ? 270
                : wide
                ? 205
                : 173,
            child: Container(
              padding: const EdgeInsets.all(5),
              decoration: _card(),
              child: Column(
                children: [
                  if (wide)
                    IconButton(
                      onPressed: () => map.rotate(0),
                      tooltip: 'Północ u góry',
                      icon: const Icon(Icons.explore_outlined, color: green),
                    ),
                  if (wide)
                    const SizedBox(width: 30, child: Divider(height: 1)),
                  IconButton(
                    onPressed: () => map.move(
                      map.camera.center,
                      (map.camera.zoom + 1).clamp(3, 19),
                    ),
                    tooltip: 'Przybliż',
                    icon: const Icon(Icons.add, color: ink),
                  ),
                  IconButton(
                    onPressed: () => map.move(
                      map.camera.center,
                      (map.camera.zoom - 1).clamp(3, 19),
                    ),
                    tooltip: 'Oddal',
                    icon: const Icon(Icons.remove, color: ink),
                  ),
                  const SizedBox(width: 30, child: Divider(height: 1)),
                  IconButton(
                    onPressed: _recenter,
                    tooltip: 'Podążaj za mną',
                    icon: Icon(
                      tracker.follow
                          ? Icons.my_location
                          : Icons.location_searching,
                      color: tracker.follow ? green : muted,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (!tracker.follow)
            Positioned(
              right: wide ? 94 : 78,
              bottom: planned != null
                  ? 280
                  : wide
                  ? 215
                  : 184,
              child: ActionChip(
                label: const Text('Wróć do mnie'),
                onPressed: _recenter,
                backgroundColor: Colors.white,
              ),
            ),
          if (mapFailed)
            Positioned(
              left: 20,
              bottom: wide ? 202 : 165,
              child: _pill(
                Icons.wifi_off,
                'Mapa niedostępna · sprawdź internet',
                cream,
              ),
            ),
          Positioned(
            left: wide ? 25 : 12,
            right: wide ? 25 : 12,
            bottom: 32,
            child: planned == null ? _walkCard(wide) : _routeCard(wide),
          ),
        ],
      ),
    ),
  );

  Widget _walkCard(bool wide) => Container(
    padding: EdgeInsets.all(wide ? 24 : 17),
    decoration: _card(),
    child: wide
        ? Row(
            children: [
              Container(
                width: 57,
                height: 57,
                decoration: BoxDecoration(
                  color: const Color(0xFFEBEFDF),
                  borderRadius: BorderRadius.circular(17),
                ),
                child: const Icon(Icons.hiking_rounded, color: green, size: 31),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Twój dzisiejszy spacer',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 5),
                    Text(
                      'Każda przygoda zaczyna się od pierwszego kroku.',
                      style: TextStyle(fontSize: 12, color: muted),
                    ),
                  ],
                ),
              ),
              _stat(_distance, 'przebyta trasa'),
              _stat(_time, 'czas spaceru'),
              _stat('${tracker.route.length}', 'punkty trasy'),
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.hiking_rounded, color: green, size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Twój spacer',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(child: _stat(_distance, 'trasa')),
                  Expanded(child: _stat(_time, 'czas')),
                  Expanded(child: _stat('${tracker.route.length}', 'punkty')),
                ],
              ),
            ],
          ),
  );

  String get _distance =>
      '${(tracker.distance / 1000).toStringAsFixed(2).replaceAll('.', ',')} km';
  String get _time =>
      '${tracker.elapsed.inMinutes.toString().padLeft(2, '0')}:${(tracker.elapsed.inSeconds % 60).toString().padLeft(2, '0')}';
  Widget _stat(String value, String label) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: ink,
            letterSpacing: -.7,
          ),
        ),
        const SizedBox(height: 3),
        Text(label, style: const TextStyle(fontSize: 11, color: muted)),
      ],
    ),
  );

  Widget _otherPage() => SingleChildScrollView(
    padding: const EdgeInsets.all(28),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _eyebrow(selectedTab == 1 ? 'KROK PO KROKU' : 'PAMIĄTKI Z MIASTA'),
        const SizedBox(height: 10),
        Text(
          selectedTab == 1 ? 'Dziennik spaceru' : 'Moja kolekcja',
          style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        Text(
          selectedTab == 1
              ? 'Twoja trasa jest zapisywana podczas bieżącej sesji. ${tracker.demo ? 'Dane pochodzą ze spaceru demo.' : ''}'
              : 'Podejdź do punktu i obróć dysk, aby zdobyć 50 punktów.',
          style: const TextStyle(color: muted, height: 1.5),
        ),
        const SizedBox(height: 28),
        if (selectedTab == 1) ...[
          Container(
            padding: const EdgeInsets.all(22),
            decoration: _card(),
            child: Wrap(
              spacing: 20,
              runSpacing: 20,
              children: [
                _stat(_distance, 'przebyta trasa'),
                _stat(_time, 'czas spaceru'),
                _stat('${tracker.route.length}', 'zapisane pozycje'),
              ],
            ),
          ),
          const SizedBox(height: 20),
          if (tracker.route.isEmpty)
            _empty(
              Icons.route_outlined,
              'Twoja historia dopiero się zaczyna.',
              'Włącz lokalizację lub uruchom demo, aby zapisać pierwszą trasę.',
            )
          else ...[
            if (tracker.position != null)
              Text(
                'Dokładność ostatniej pozycji: ±${tracker.accuracy.round()} m',
                style: const TextStyle(color: muted),
              ),
            const SizedBox(height: 10),
            for (final point in tracker.route.reversed.take(20))
              ListTile(
                leading: const Icon(Icons.location_on_outlined, color: green),
                title: Text(
                  '${point.latitude.toStringAsFixed(6)}, ${point.longitude.toStringAsFixed(6)}',
                ),
                subtitle: const Text('Punkt bieżącego spaceru'),
                dense: true,
              ),
          ],
        ] else ...[
          for (final place in landmarks)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Material(
                color: cream,
                elevation: 1,
                shadowColor: ink.withValues(alpha: .08),
                borderRadius: BorderRadius.circular(21),
                clipBehavior: Clip.antiAlias,
                child: ListTile(
                  contentPadding: const EdgeInsets.all(15),
                  leading: Icon(
                    place.icon,
                    color: rewards.visited(place.name, tracker.demo)
                        ? place.color
                        : muted,
                    size: 32,
                  ),
                  title: Text(
                    place.name,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    rewards.visited(place.name, tracker.demo)
                        ? 'Zdobyto punkty'
                        : 'Obróć w pobliżu · +50 pkt',
                  ),
                  trailing: Icon(
                    rewards.visited(place.name, tracker.demo)
                        ? Icons.check_circle
                        : Icons.lock_outline,
                    color: rewards.visited(place.name, tracker.demo)
                        ? green
                        : muted,
                  ),
                  onTap: () => _landmarkSheet(place),
                ),
              ),
            ),
        ],
        const SizedBox(height: 22),
        FilledButton.icon(
          onPressed: () => setState(() => selectedTab = 0),
          icon: const Icon(Icons.map_outlined),
          label: const Text('Wróć na mapę'),
        ),
      ],
    ),
  );

  Widget _empty(IconData icon, String title, String text) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(32),
    decoration: _card(),
    child: Column(
      children: [
        Icon(icon, color: green, size: 45),
        const SizedBox(height: 20),
        Text(
          title,
          style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 10),
        Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(color: muted),
        ),
      ],
    ),
  );

  Widget _mobileNav() => NavigationBar(
    height: 65,
    selectedIndex: selectedTab,
    backgroundColor: cream,
    indicatorColor: lime,
    onDestinationSelected: (value) => setState(() => selectedTab = value),
    destinations: const [
      NavigationDestination(
        icon: Icon(Icons.explore_outlined),
        label: 'Odkrywaj',
      ),
      NavigationDestination(
        icon: Icon(Icons.auto_stories_outlined),
        label: 'Dziennik',
      ),
      NavigationDestination(
        icon: Icon(Icons.collections_bookmark_outlined),
        label: 'Kolekcja',
      ),
    ],
  );

  void _startDemo() {
    setState(() => selectedTab = 0);
    lastTarget = null;
    tracker.startDemo();
  }

  void _sheet(Widget child) => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    backgroundColor: cream,
    constraints: BoxConstraints(
      maxWidth: 560,
      maxHeight: MediaQuery.sizeOf(context).height * .9,
    ),
    builder: (_) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(28, 10, 28, 30),
        child: child,
      ),
    ),
  );

  void _landmarkSheet(Landmark place) => _sheet(
    PointSheet(
      place: place,
      tracker: tracker,
      rewards: rewards,
      onPlan: () {
        Navigator.pop(context);
        _planSheet(place);
      },
    ),
  );

  void _planSheet(Landmark place, {PlannedRoute? initial}) {
    final origin = tracker.position ?? const LatLng(50.0679, 19.9454);
    _sheet(
      RouteSheet(
        place: place,
        origin: origin,
        originLabel: tracker.position == null
            ? 'Start podglądu: Dworzec Główny (bez GPS)'
            : tracker.demo
            ? 'Start: pozycja w spacerze demo'
            : 'Start: Twoja aktualna pozycja GPS',
        service: routing,
        initial: initial,
        onSelected: (value) {
          Navigator.pop(context);
          ++routeGeneration;
          setState(() {
            planned = value;
            routePlace = place;
            selectedTab = 0;
            routeError = null;
            lastRouting = DateTime.now();
          });
          tracker.setFollow(false);
          if (ready) {
            map.fitCamera(
              CameraFit.bounds(
                bounds: LatLngBounds.fromPoints(value.points),
                padding: EdgeInsets.fromLTRB(
                  MediaQuery.sizeOf(context).width >= 1000 ? 80 : 35,
                  95,
                  75,
                  190,
                ),
                maxZoom: 17,
              ),
            );
          }
        },
      ),
    );
  }

  Future<void> _refreshRoute() async {
    final old = planned;
    if (old == null || refreshingRoute) return;
    final generation = ++routeGeneration;
    setState(() {
      refreshingRoute = true;
      routeError = null;
      lastRouting = DateTime.now();
    });
    try {
      final value = await routing.plan(
        tracker.position ?? old.origin,
        old.destination,
        old.mode,
      );
      if (!mounted || generation != routeGeneration) return;
      setState(() {
        planned = value;
        refreshingRoute = false;
      });
    } catch (_) {
      if (!mounted || generation != routeGeneration) return;
      setState(() {
        refreshingRoute = false;
        routeError =
            'Aktualizacja trasy nie powiodła się. Pokazujemy ostatni plan.';
      });
    }
  }

  void _closeRoute() {
    ++routeGeneration;
    setState(() {
      planned = null;
      routePlace = null;
      refreshingRoute = false;
      routeError = null;
    });
  }

  Widget _routeCard(bool wide) {
    final route = planned!;
    return Container(
      padding: const EdgeInsets.all(19),
      decoration: _card(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(modeIcon(route.mode), color: green),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Do ${routePlace!.name}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 17,
                  ),
                ),
              ),
              IconButton(
                onPressed: _closeRoute,
                tooltip: 'Zamknij trasę',
                icon: const Icon(Icons.close, size: 19),
              ),
            ],
          ),
          Row(
            children: [
              Text(
                '${route.durationLabel} · ${route.distanceLabel}',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 21,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  route.mode.label,
                  style: const TextStyle(color: muted, fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            routeError ??
                (refreshingRoute
                    ? 'Aktualizujemy trasę i miejskie dane…'
                    : route.mode == TravelMode.wheelchair
                    ? 'Dostępność całej trasy niepotwierdzona — sprawdź szczegóły.'
                    : route.mode == TravelMode.car
                    ? 'Czas szacunkowy · brak miejskich danych o korkach.'
                    : 'Trasa oceniona na podstawie dostępnych danych miejskich.'),
            style: const TextStyle(fontSize: 11, color: muted, height: 1.4),
          ),
          const SizedBox(height: 7),
          Row(
            children: [
              TextButton.icon(
                onPressed: () => _planSheet(routePlace!, initial: route),
                icon: const Icon(Icons.list_alt, size: 17),
                label: const Text('Szczegóły'),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: refreshingRoute ? null : _refreshRoute,
                icon: const Icon(Icons.refresh, size: 17),
                label: const Text('Odśwież trasę'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _help() => _sheet(
    const Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Miasto jest Twoją planszą.',
          style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
        ),
        SizedBox(height: 20),
        Text(
          '1. Włącz lokalizację i zezwól na dostęp do GPS.\n\n2. Ruszaj na spacer. Twój znacznik i mapa poruszają się razem z Tobą. Zielona linia pokazuje trasę.\n\n3. Przesuń mapę, żeby rozejrzeć się po okolicy. Przycisk celownika przywraca podążanie.\n\nChcesz sprawdzić wszystko przy biurku? Uruchom spacer demo po Krakowie.',
          style: TextStyle(height: 1.7, color: ink),
        ),
      ],
    ),
  );

  void _settings() => _sheet(
    Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Twój spacer, Twoje zasady.',
          style: TextStyle(fontSize: 25, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 16),
        const Text(
          'Lokalizacja jest odczytywana wyłącznie po włączeniu spaceru. Trasa pozostaje w pamięci tej sesji i znika po odświeżeniu aplikacji. Dostawca map OpenStreetMap otrzymuje żądania kafelków dla oglądanego obszaru.',
          style: TextStyle(height: 1.6, color: muted),
        ),
        const SizedBox(height: 18),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.my_location, color: green),
          title: const Text('Automatyczne podążanie'),
          trailing: Switch(
            value: tracker.follow,
            onChanged: (value) {
              tracker.setFollow(value);
              Navigator.pop(context);
            },
          ),
        ),
        if (tracker.active || tracker.loading)
          TextButton.icon(
            onPressed: () {
              tracker.stop();
              Navigator.pop(context);
            },
            icon: const Icon(Icons.stop_circle_outlined),
            label: const Text('Zatrzymaj odczyt lokalizacji'),
          ),
      ],
    ),
  );

  Widget _eyebrow(String text) => Text(
    text,
    style: const TextStyle(
      color: muted,
      fontSize: 10,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.7,
    ),
  );
  Widget _pill(IconData icon, String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(30),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: green, size: 16),
        const SizedBox(width: 7),
        Text(text, style: const TextStyle(fontSize: 12, color: ink)),
      ],
    ),
  );
  BoxDecoration _card() => BoxDecoration(
    color: cream,
    borderRadius: BorderRadius.circular(21),
    border: Border.all(color: Colors.white.withValues(alpha: .7)),
    boxShadow: [
      BoxShadow(
        color: ink.withValues(alpha: .08),
        blurRadius: 26,
        offset: const Offset(0, 7),
      ),
    ],
  );
}
