import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import 'places.dart';
import 'routing.dart';

IconData modeIcon(TravelMode mode) => switch (mode) {
  TravelMode.walk => Icons.directions_walk,
  TravelMode.bike => Icons.directions_bike,
  TravelMode.transit => Icons.tram_outlined,
  TravelMode.car => Icons.directions_car_outlined,
  TravelMode.wheelchair => Icons.accessible_forward,
};

class RouteSheet extends StatefulWidget {
  const RouteSheet({
    super.key,
    required this.place,
    required this.origin,
    required this.originLabel,
    required this.service,
    required this.onSelected,
    this.initial,
  });
  final Landmark place;
  final LatLng origin;
  final String originLabel;
  final RoutingService service;
  final ValueChanged<PlannedRoute> onSelected;
  final PlannedRoute? initial;
  @override
  State<RouteSheet> createState() => _RouteSheetState();
}

class _RouteSheetState extends State<RouteSheet> {
  TravelMode mode = TravelMode.walk;
  PlannedRoute? result;
  bool loading = false;
  String? error;
  int generation = 0;

  @override
  void initState() {
    super.initState();
    result = widget.initial;
    mode = result?.mode ?? TravelMode.walk;
  }

  Future<void> plan() async {
    final request = ++generation;
    setState(() {
      loading = true;
      error = null;
      result = null;
    });
    try {
      final route = await widget.service.plan(
        widget.origin,
        widget.place.position,
        mode,
      );
      if (!mounted || request != generation) return;
      setState(() {
        result = route;
        loading = false;
      });
    } catch (exception) {
      if (!mounted || request != generation) return;
      setState(() {
        loading = false;
        error = exception is StateError ? exception.message.toString() : 'Nie udało się połączyć z planowaniem tras. Sprawdź połączenie i spróbuj ponownie.';
      });
    }
  }

  @override
  void dispose() {
    ++generation;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final route = result;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'PODRÓŻ PO TWOJEMU',
          style: TextStyle(
            fontSize: 10,
            color: Color(0xFF476C42),
            fontWeight: FontWeight.w700,
            letterSpacing: 1.6,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Do ${widget.place.name}',
          style: const TextStyle(fontSize: 27, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            const Icon(Icons.trip_origin, size: 17, color: Color(0xFF476C42)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                widget.originLabel,
                style: const TextStyle(fontSize: 13),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final value in TravelMode.values)
              ChoiceChip(
                avatar: Icon(modeIcon(value), size: 18),
                label: Text(value.label),
                selected: mode == value,
                onSelected: (_) {
                  ++generation;
                  setState(() {
                    mode = value;
                    result = null;
                    error = null;
                    loading = false;
                  });
                },
              ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          switch (mode) {
            TravelMode.bike => 'Preferujemy drogi rowerowe. Ocena nawierzchni pochodzi z miejskich danych ZTP.',
            TravelMode.wheelchair => 'Profil dla wózka: ograniczenie nachyleń i schodów. Brak pełnego wykazu miejskich barier oznacza niepotwierdzoną dostępność.',
            TravelMode.transit => 'Rozkłady, bieżące odjazdy i komunikaty ZTP Kraków. Plan na teraz, z dojściem i przesiadkami.',
            TravelMode.car => 'Porównujemy warianty z miejską mapą prac ZDMK. Bieżące korki: brak miejskiego feedu.',
            TravelMode.walk => 'Trasa piesza z uwzględnieniem zgłoszonych miejskich prac w okolicy.',
          },
          style: const TextStyle(
            fontSize: 13,
            color: Color(0xFF7C8478),
            height: 1.6,
          ),
        ),
        const SizedBox(height: 20),
        if (loading) ...[
          const LinearProgressIndicator(),
          const SizedBox(height: 12),
          const Text(
            'Wyznaczamy drogę i sprawdzamy miejskie dane…',
            style: TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () {
              ++generation;
              setState(() => loading = false);
            },
            child: const Text('Anuluj'),
          ),
        ] else
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: plan,
              icon: const Icon(Icons.route),
              label: Text(
                route == null ? 'Wyznacz trasę' : 'Sprawdź trasę ponownie',
              ),
            ),
          ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Text(
              error!,
              style: const TextStyle(color: Color(0xFFAA573B), height: 1.5),
            ),
          ),
        if (route != null) ...[
          const SizedBox(height: 24),
          Row(
            children: [
              Text(
                route.durationLabel,
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 16),
              Text(route.distanceLabel, style: const TextStyle(fontSize: 18)),
              const Spacer(),
              Icon(modeIcon(mode), color: const Color(0xFF476C42), size: 28),
            ],
          ),
          const Text(
            'Szacunek na podstawie dostępnych danych',
            style: TextStyle(fontSize: 11, color: Color(0xFF7C8478)),
          ),
          if (route.bicycle != null && mode == TravelMode.bike)
            Padding(
              padding: const EdgeInsets.only(top: 15),
              child: Text(
                'Około ${route.bicycle!['coverage_pct']}% trasy przy infrastrukturze z wykazu ZTP. Nawierzchnie: ${(route.bicycle!['surfaces'] as List).join(', ')}. Pokrycie nie potwierdza przejezdności całej trasy.',
                style: const TextStyle(fontSize: 13, height: 1.5),
              ),
            ),
          for (final warning in route.warnings)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.info_outline,
                    size: 17,
                    color: Color(0xFFAA7B39),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      warning,
                      style: const TextStyle(fontSize: 12, height: 1.5),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => widget.onSelected(route),
              icon: const Icon(Icons.map_outlined),
              label: const Text('Pokaż trasę na mapie'),
            ),
          ),
          const SizedBox(height: 14),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text(
              'Przebieg podróży',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            children: [
              for (final text in route.steps)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    children: [
                      const Icon(Icons.arrow_forward, size: 16),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(text, style: const TextStyle(fontSize: 13)),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          SourceList(sources: route.sources),
        ],
        const SizedBox(height: 14),
        const Text(
          'Ocena: ZTP i ZDMK Kraków. Przebieg dróg: OpenStreetMap / Valhalla.',
          style: TextStyle(fontSize: 11, color: Color(0xFF7C8478), height: 1.5),
        ),
      ],
    );
  }
}

class SourceList extends StatelessWidget {
  const SourceList({super.key, required this.sources});
  final List<CitySource> sources;
  @override
  Widget build(BuildContext context) => ExpansionTile(
    tilePadding: EdgeInsets.zero,
    title: const Text(
      'Źródła i aktualność danych',
      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
    ),
    children: [
      for (final source in sources)
        Padding(
          padding: const EdgeInsets.only(bottom: 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    source.available
                        ? Icons.check_circle_outline
                        : Icons.info_outline,
                    size: 17,
                    color: source.available
                        ? const Color(0xFF476C42)
                        : const Color(0xFFAA7B39),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      source.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '${source.label} · ${source.detail}',
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF7C8478),
                  height: 1.5,
                ),
              ),
              if (source.updatedAt != null)
                Text(
                  'Aktualizacja źródła: ${source.updatedAt!.toLocal().toString().split('.').first}',
                  style: const TextStyle(
                    fontSize: 10,
                    color: Color(0xFF7C8478),
                  ),
                ),
              TextButton(
                onPressed: () => launchUrl(Uri.parse(source.url)),
                style: TextButton.styleFrom(padding: EdgeInsets.zero),
                child: const Text(
                  'Otwórz miejskie źródło / dokumentację ↗',
                  style: TextStyle(fontSize: 11),
                ),
              ),
            ],
          ),
        ),
    ],
  );
}
