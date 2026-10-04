import asyncio
import os
import time

import httpx
from fastapi import HTTPException

from app.city_data import source, stamp
from app.geo import decode_polyline, meters, near_path, samples, segment_distance

_lock = asyncio.Lock()
_last_call = 0.0
VALHALLA = os.getenv('ROUTING_BASE_URL', 'https://valhalla1.openstreetmap.de').rstrip('/')


def costing(mode):
    if mode == 'bike':
        return 'bicycle', {'bicycle': {'bicycle_type': 'Hybrid', 'use_roads': .15, 'use_hills': .2}}
    if mode == 'wheelchair':
        return 'pedestrian', {'pedestrian': {'type': 'wheelchair', 'walking_speed': 3.5, 'max_grade': 6, 'step_penalty': 600, 'use_hills': 0}}
    if mode == 'car':
        return 'auto', {'auto': {'exclude_unpaved': True}}
    return 'pedestrian', {'pedestrian': {'walking_speed': 4.5}}


async def valhalla(origin, destination, mode, exclude=None, alternatives=1):
    global _last_call
    profile, options = costing(mode)
    payload = dict(locations=[dict(lat=p[0], lon=p[1]) for p in (origin, destination)],
                   costing=profile, costing_options=options, units='kilometers',
                   language='pl-PL', alternates=alternatives)
    if exclude:
        payload['exclude_locations'] = [dict(lat=p[0], lon=p[1]) for p in exclude[:30]]
    # Public demo service has a per-user 1 request/second limit.
    async with _lock:
        await asyncio.sleep(max(0, 1.05 - (time.monotonic() - _last_call)))
        _last_call = time.monotonic()
        try:
            async with httpx.AsyncClient(timeout=25, headers={'X-Client-Id': 'lajkonik-go-local-prototype', 'User-Agent': 'LajkonikGO/0.1'}) as client:
                response = await client.post(VALHALLA + '/route', json=payload)
                response.raise_for_status()
                data = response.json()
        except (httpx.HTTPError, ValueError) as error:
            raise HTTPException(503, 'Nie udało się wyznaczyć trasy. Spróbuj ponownie za chwilę.') from error
    trips = [data.get('trip')] + [a.get('trip') for a in data.get('alternates', [])]
    routes = []
    for trip in trips:
        if not trip or not trip.get('legs'):
            continue
        geometry, steps = [], []
        for leg in trip['legs']:
            geometry.extend(decode_polyline(leg['shape']))
            steps.extend(dict(text=m.get('instruction', ''), distance_m=round(m.get('length', 0) * 1000), duration_s=round(m.get('time', 0))) for m in leg.get('maneuvers', []))
        routes.append(dict(geometry=geometry, distance_m=round(trip['summary']['length'] * 1000),
                           duration_s=round(trip['summary']['time']), steps=steps))
    if not routes:
        raise HTTPException(422, 'Nie znaleziono przejezdnej trasy dla wybranego sposobu podróży.')
    return routes


def bicycle_assessment(path, features):
    lines = []
    for feature in features:
        geom = feature.get('geometry') or {}
        if geom.get('type') == 'LineString':
            paths = [geom['coordinates']]
        elif geom.get('type') == 'MultiLineString':
            paths = geom['coordinates']
        else:
            continue
        for line in paths:
            points = [[p[1], p[0]] for p in line]
            lines.extend((a, b, feature.get('properties', {})) for a, b in zip(points, points[1:]))
    covered, rough, total = 0.0, 0.0, 0.0
    surfaces = set()
    # A spatial grid avoids comparing every route sample to every city segment.
    grid = {}
    for a, b, props in lines:
        for x in range(int(min(a[0], b[0]) * 1000) - 1, int(max(a[0], b[0]) * 1000) + 2):
            for y in range(int(min(a[1], b[1]) * 1000) - 1, int(max(a[1], b[1]) * 1000) + 2):
                grid.setdefault((x, y), []).append((a, b, props))
    for point, length in samples(path):
        total += length
        candidates = grid.get((int(point[0] * 1000), int(point[1] * 1000)), [])
        nearest = min(((segment_distance(point, a, b), props) for a, b, props in candidates), key=lambda v: v[0], default=(999, {}))
        if nearest[0] <= 12:
            covered += length
            surface = nearest[1].get('nawierzchnia')
            if surface:
                surfaces.add(surface)
            if surface in ('szuter', 'nieutwardzona', 'w budowie/remoncie', 'kostka', 'płyty'):
                rough += length
    return dict(coverage_pct=round(100 * covered / total) if total else 0,
                covered_m=round(covered), rough_m=round(rough), surfaces=sorted(surfaces))


async def road_plan(origin, destination, mode, bikes, barriers, works):
    exclusions = [b['point'] for b in barriers if mode in b.get('modes', [])]
    candidates = await valhalla(origin, destination, mode, exclusions)
    for route in candidates:
        route['bicycle'] = bicycle_assessment(route['geometry'], bikes) if mode in ('bike', 'wheelchair') else None
        route['works_count'] = sum(near_path(w['point'], route['geometry'], 60) for w in works)
    if mode in ('bike', 'wheelchair'):
        route = min(candidates, key=lambda r: r['distance_m'] + r['bicycle']['rough_m'] * 3 - r['bicycle']['covered_m'] * .3 + r['works_count'] * 350)
    else:
        route = min(candidates, key=lambda r: r['duration_s'] + r['works_count'] * 120)
    route['warnings'] = []
    if mode == 'wheelchair':
        route['warnings'].append('Profil dla wózka uwzględnia dostęp, nachylenie i nawierzchnie zapisane w mapie. Brakuje potwierdzenia wszystkich krawężników, szerokości chodników i wejścia do celu.')
        if route['bicycle']['rough_m']:
            route['warnings'].append(f"Miejski wykaz wskazuje około {route['bicycle']['rough_m']} m potencjalnie trudnej nawierzchni przy trasie.")
    nearby = [b for b in barriers if mode in b.get('modes', []) and near_path(b['point'], route['geometry'], 20)]
    if nearby:
        raise HTTPException(422, 'Nie znaleziono trasy omijającej znane bariery. Zmień sposób podróży lub cel.')
    active_works = [w for w in works if near_path(w['point'], route['geometry'], 60)]
    route['warnings'].extend(w['title'] for w in active_works[:5])
    route['sources'] = [source('Trasa · Valhalla / OpenStreetMap', VALHALLA, 'available', 'Trasa wyznaczona po sieci dróg dla wybranego profilu.', stamp())]
    if mode == 'car':
        route['sources'].append(source('Korki · dane miejskie', 'https://ztp.krakow.pl/dane-otwarte', 'unavailable', 'Nie podłączono miejskiego feedu prędkości ani zatorów. Czas przejazdu jest szacunkowy.'))
        route['warnings'].append('Preferujemy omijanie zgłoszonych prac; bieżące korki nie są uwzględnione w czasie przejazdu.')
        gap = meters(route['geometry'][-1], destination)
        if gap > 30:
            walk = (await valhalla(route['geometry'][-1], destination, 'walk', alternatives=0))[0]
            route['geometry'].extend(walk['geometry'])
            route['distance_m'] += walk['distance_m']
            route['duration_s'] += walk['duration_s']
            route['steps'].append(dict(text=f"Ostatnie {walk['distance_m']} m pokonaj pieszo — cel jest poza drogą dostępną dla auta.", distance_m=walk['distance_m'], duration_s=walk['duration_s']))
            route['warnings'].append('Trasa samochodowa kończy się dojściem pieszym. Sprawdź możliwość parkowania i ograniczenia wjazdu.')
    return route
