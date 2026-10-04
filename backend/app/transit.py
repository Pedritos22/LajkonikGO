"""Timetable routing from official Kraków GTFS, with GTFS-RT delays.

Connection scan supports transfers. First/last mile use the pedestrian router;
transfer walks are checked before returning a journey. No fabricated buses.
"""
import asyncio
import csv
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
import io
import time
import zipfile
from zoneinfo import ZoneInfo

import httpx
from fastapi import HTTPException
from google.transit import gtfs_realtime_pb2 as rt

from app.city_data import GTFS, source
from app.geo import meters
from app.road_routes import valhalla

WARSAW = ZoneInfo('Europe/Warsaw')


def seconds(value):
    h, m, s = map(int, value.split(':'))
    return h * 3600 + m * 60 + s


def active_services(calendar, exceptions, day):
    date = day.strftime('%Y%m%d')
    weekday = ('monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday')[day.weekday()]
    active = {i['service_id'] for i in calendar if i['start_date'] <= date <= i['end_date'] and i[weekday] == '1'}
    for row in exceptions:
        if row['date'] == date:
            if row['exception_type'] == '1':
                active.add(row['service_id'])
            else:
                active.discard(row['service_id'])
    return active


def parse_gtfs(content, prefix):
    archive = zipfile.ZipFile(io.BytesIO(content))
    if sum(i.file_size for i in archive.infolist()) > 300_000_000:
        raise ValueError('GTFS archive too large')

    def rows(name):
        if name not in archive.namelist():
            return []
        return csv.DictReader(io.TextIOWrapper(archive.open(name), encoding='utf-8-sig'))

    stops = {r['stop_id']: dict(point=[float(r['stop_lat']), float(r['stop_lon'])], name=r['stop_name'], wheelchair=r.get('wheelchair_boarding', '0')) for r in rows('stops.txt') if r.get('stop_lat') and r.get('stop_lon')}
    trips = {r['trip_id']: r for r in rows('trips.txt')}
    routes = {r['route_id']: r for r in rows('routes.txt')}
    times = {}
    for row in rows('stop_times.txt'):
        if row['stop_id'] not in stops or not row.get('arrival_time') or not row.get('departure_time'):
            continue
        times.setdefault(row['trip_id'], []).append(dict(stop=row['stop_id'], seq=int(row['stop_sequence']),
            arrive=seconds(row['arrival_time']), depart=seconds(row['departure_time']),
            pickup=row.get('pickup_type', '0') != '1', dropoff=row.get('drop_off_type', '0') != '1'))
    for stops_on_trip in times.values():
        stops_on_trip.sort(key=lambda x: x['seq'])
    shapes = {}
    for row in rows('shapes.txt'):
        shapes.setdefault(row['shape_id'], []).append((int(row['shape_pt_sequence']), [float(row['shape_pt_lat']), float(row['shape_pt_lon'])]))
    shapes = {key: [p for _, p in sorted(value)] for key, value in shapes.items()}
    return dict(prefix=prefix, stops=stops, trips=trips, routes=routes, times=times, shapes=shapes,
                calendar=list(rows('calendar.txt')), exceptions=list(rows('calendar_dates.txt')))


@dataclass(frozen=True)
class Connection:
    depart: float
    arrive: float
    start: str
    end: str
    trip: str
    route: str
    pickup: bool = True
    dropoff: bool = True


@dataclass(frozen=True)
class Node:
    edge: Connection
    previous: object = None


def scan(connections, origins, destinations, transfers):
    labels = {stop: (arrival, None, 0) for stop, arrival in origins.items()}
    aboard = {}
    best = None
    for connection in sorted(connections, key=lambda c: c.depart):
        if best and connection.depart > best[0]:
            break
        ride = aboard.get(connection.trip)
        label = labels.get(connection.start)
        if connection.pickup and label and label[0] + 60 <= connection.depart and label[2] < 3:
            candidate = (label[1], label[2] + 1)
            if ride is None or candidate[1] < ride[1]:
                ride = candidate
        if ride is None:
            continue
        node = Node(connection, ride[0])
        aboard[connection.trip] = (node, ride[1])
        if not connection.dropoff:
            continue
        arrival = (connection.arrive, node, ride[1])
        if arrival[0] < labels.get(connection.end, (float('inf'),))[0]:
            labels[connection.end] = arrival
            if connection.end in destinations:
                finish = connection.arrive + destinations[connection.end]
                if best is None or finish < best[0]:
                    best = (finish, node)
            for stop, duration in transfers.get(connection.end, []):
                if connection.arrive + duration < labels.get(stop, (float('inf'),))[0]:
                    edge = Connection(connection.arrive, connection.arrive + duration, connection.end, stop, 'walk', '')
                    walk_node = Node(edge, node)
                    labels[stop] = (edge.arrive, walk_node, ride[1])
                    if stop in destinations:
                        finish = edge.arrive + destinations[stop]
                        if best is None or finish < best[0]:
                            best = (finish, walk_node)
    if best is None:
        return None
    edges, node = [], best[1]
    while node:
        edges.append(node.edge)
        node = node.previous
    return list(reversed(edges))


class Transit:
    def __init__(self):
        self.bundles = []
        self.updated = 0
        self.lock = asyncio.Lock()

    async def load(self):
        async with self.lock:
            if self.bundles and time.monotonic() - self.updated < 3600:
                return self.bundles
            async def one(prefix):
                async with httpx.AsyncClient(timeout=45) as client:
                    response = await client.get(GTFS + f'GTFS_KRK_{prefix}.zip')
                    response.raise_for_status()
                return await asyncio.to_thread(parse_gtfs, response.content, prefix)
            try:
                self.bundles = await asyncio.gather(*(one(p) for p in ('A', 'M', 'T')))
                self.updated = time.monotonic()
            except Exception as error:
                raise HTTPException(503, 'Nie udało się pobrać miejskich rozkładów ZTP. Spróbuj ponownie.') from error
        return self.bundles

    async def realtime(self):
        async def one(prefix):
            url = GTFS + f'TripUpdates_{prefix}.pb'
            updates = {}
            try:
                async with httpx.AsyncClient(timeout=12) as client:
                    response = await client.get(url)
                    response.raise_for_status()
                feed = rt.FeedMessage()
                feed.ParseFromString(response.content)
                if not feed.header.timestamp or not -60 <= time.time() - feed.header.timestamp <= 600:
                    return updates, source(f'ZTP · odjazdy {prefix}', url, 'stale', 'Nieaktualne dane odjazdów; użyto rozkładu planowego.')
                for entity in feed.entity:
                    if entity.HasField('trip_update'):
                        descriptor = entity.trip_update.trip
                        updates[(prefix, descriptor.trip_id, descriptor.start_date)] = entity.trip_update
                return updates, source(f'ZTP · odjazdy {prefix}', url, 'available', 'Uwzględniono zgłoszone opóźnienia i odwołane kursy.', datetime.fromtimestamp(feed.header.timestamp, timezone.utc).isoformat())
            except Exception:
                return {}, source(f'ZTP · odjazdy {prefix}', url, 'unavailable', 'Brak bieżących odjazdów; użyto rozkładu planowego.')
        values = await asyncio.gather(*(one(p) for p in ('A', 'M', 'T')))
        return {k: v for values, _ in values for k, v in values.items()}, [s for _, s in values]

    def connections(self, bundles, updates, departure, blocked):
        result, trip_details = [], {}
        for bundle in bundles:
            prefix = bundle['prefix']
            for offset in (-1, 0, 1):
                day = departure.date() + timedelta(days=offset)
                midnight = datetime.combine(day, datetime.min.time(), tzinfo=WARSAW).timestamp()
                services = active_services(bundle['calendar'], bundle['exceptions'], day)
                date = day.strftime('%Y%m%d')
                for trip_id, trip in bundle['trips'].items():
                    route = prefix + ':' + trip['route_id']
                    if trip['service_id'] not in services or route in blocked:
                        continue
                    update = updates.get((prefix, trip_id, date)) or updates.get((prefix, trip_id, ''))
                    if update and update.trip.schedule_relationship == rt.TripDescriptor.CANCELED:
                        continue
                    events = {s.stop_sequence: s for s in update.stop_time_update} if update else {}
                    delay = update.delay if update and update.HasField('delay') else 0
                    times = []
                    for row in bundle['times'].get(trip_id, []):
                        event = events.get(row['seq'])
                        if event and event.schedule_relationship == rt.TripUpdate.StopTimeUpdate.SKIPPED:
                            times.append({**row, 'pickup': False, 'dropoff': False, 'arrive': midnight + row['arrive'] + delay, 'depart': midnight + row['depart'] + delay})
                            continue
                        arrival, leave = midnight + row['arrive'] + delay, midnight + row['depart'] + delay
                        if event:
                            if event.HasField('arrival'):
                                arrival = event.arrival.time if event.arrival.HasField('time') else midnight + row['arrive'] + event.arrival.delay
                                delay = arrival - (midnight + row['arrive'])
                            if event.HasField('departure'):
                                leave = event.departure.time if event.departure.HasField('time') else midnight + row['depart'] + event.departure.delay
                                delay = leave - (midnight + row['depart'])
                            else:
                                leave = midnight + row['depart'] + delay
                        times.append({**row, 'arrive': arrival, 'depart': leave})
                    key = prefix + ':' + trip_id + ':' + date
                    trip_details[key] = (bundle, trip)
                    for a, b in zip(times, times[1:]):
                        if departure.timestamp() <= a['depart'] <= departure.timestamp() + 21600 and b['arrive'] >= a['depart']:
                            result.append(Connection(a['depart'], b['arrive'], prefix + ':' + a['stop'], prefix + ':' + b['stop'], key, route, a['pickup'], b['dropoff']))
        return result, trip_details

    async def plan(self, origin, destination, alerts):
        bundles = await self.load()
        updates, realtime_sources = await self.realtime()
        departure = datetime.now(WARSAW)
        stops = {b['prefix'] + ':' + key: value for b in bundles for key, value in b['stops'].items()}
        def closest(point):
            # Choose nearby physical platforms, not duplicate IDs in different feeds.
            candidates = []
            for distance, key in sorted((meters(point, s['point']), key) for key, s in stops.items()):
                if distance > 900 or len(candidates) >= 6:
                    break
                if all(meters(stops[key]['point'], stops[other]['point']) > 15 for _, other in candidates):
                    candidates.append((distance, key))
            return candidates
        origin_stops = [(d, key) for d, key in closest(origin) if d <= 900]
        destination_stops = [(d, key) for d, key in closest(destination) if d <= 900]
        if not origin_stops or not destination_stops:
            raise HTTPException(422, 'Brak przystanku ZTP w promieniu 900 m od początku lub celu.')
        access, egress = {}, {}
        for _, key in origin_stops:
            access[key] = (await valhalla(origin, stops[key]['point'], 'walk', alternatives=0))[0]
        for _, key in destination_stops:
            egress[key] = (await valhalla(stops[key]['point'], destination, 'walk', alternatives=0))[0]
        # GTFS A/M/T sometimes use different IDs for the same platform.
        access_platforms, egress_platforms = list(access), list(egress)
        for key, stop in stops.items():
            for original in access_platforms:
                if meters(stop['point'], stops[original]['point']) <= 5:
                    access[key] = access[original]
                    break
            for original in egress_platforms:
                if meters(stop['point'], stops[original]['point']) <= 5:
                    egress[key] = egress[original]
                    break
        # Start the clock after access calculations so a departing service is not missed.
        departure = datetime.now(WARSAW)
        blocked = {route for alert in alerts if alert['effect'] == rt.Alert.NO_SERVICE for route in alert['routes']}
        connections, details = await asyncio.to_thread(self.connections, bundles, updates, departure, blocked)
        transfers, grid = {}, {}
        for key, stop in stops.items():
            grid.setdefault((int(stop['point'][0] * 500), int(stop['point'][1] * 500)), []).append(key)
        for key, stop in stops.items():
            x, y = int(stop['point'][0] * 500), int(stop['point'][1] * 500)
            for dx in (-1, 0, 1):
                for dy in (-1, 0, 1):
                    for other in grid.get((x + dx, y + dy), []):
                        distance = meters(stop['point'], stops[other]['point'])
                        if other != key and distance <= 150:
                            transfers.setdefault(key, []).append((other, distance / 1.1 + 30))
        seeds = {key: departure.timestamp() + walk['duration_s'] for key, walk in access.items()}
        ends = {key: walk['duration_s'] for key, walk in egress.items()}
        edges = await asyncio.to_thread(scan, connections, seeds, ends, transfers)
        if not edges:
            raise HTTPException(422, 'Brak połączenia w ciągu 6 godzin. Wybierz inny sposób podróży lub cel.')
        walks = {}
        for attempt in range(2):
            valid = True
            for index, edge in enumerate(edges):
                if edge.trip != 'walk':
                    continue
                pair = (edge.start, edge.end)
                walks[pair] = (await valhalla(stops[edge.start]['point'], stops[edge.end]['point'], 'walk', alternatives=0))[0]
                duration = walks[pair]['duration_s']
                edges[index] = Connection(edge.depart, edge.depart + duration, edge.start, edge.end, 'walk', '')
                if index + 1 < len(edges) and edge.depart + duration + 60 > edges[index + 1].depart:
                    valid = False
                    transfers[edge.start] = [(k, duration if k == edge.end else d) for k, d in transfers[edge.start]]
            if valid:
                break
            edges = await asyncio.to_thread(scan, connections, seeds, ends, transfers)
            if not edges or attempt == 1:
                raise HTTPException(422, 'Nie znaleziono połączenia z wystarczającym czasem na dojście i przesiadki.')
        geometry = list(access[edges[0].start]['geometry'])
        distance = access[edges[0].start]['distance_m'] + egress[edges[-1].end]['distance_m']
        legs = []
        groups = []
        for edge in edges:
            if groups and edge.trip == groups[-1][-1].trip and edge.trip != 'walk':
                groups[-1].append(edge)
            else:
                groups.append([edge])
        warnings = ['Podróż jest planowana na teraz. Odjazdy i przesiadki mogą się zmienić.']
        waiting = edges[0].depart - seeds[edges[0].start]
        if waiting > 900:
            warnings.append(f'Po dojściu oczekiwanie na pierwszy kurs: około {round(waiting / 60)} min. Rozważ trasę pieszą lub rowerową.')
        for group in groups:
            first, last = group[0], group[-1]
            if first.trip == 'walk':
                walk = walks[(first.start, first.end)]
                geometry.extend(walk['geometry']); distance += walk['distance_m']
                legs.append(dict(text=f"Przejdź do przystanku {stops[last.end]['name']} ({walk['distance_m']} m)", distance_m=walk['distance_m'], duration_s=walk['duration_s']))
                continue
            bundle, trip = details[first.trip]
            shape = bundle['shapes'].get(trip.get('shape_id'), [])
            if shape:
                start = min(range(len(shape)), key=lambda i: meters(shape[i], stops[first.start]['point']))
                end = min(range(start, len(shape)), key=lambda i: meters(shape[i], stops[last.end]['point']))
                segment = shape[start:end + 1]
            else:
                segment = [stops[first.start]['point']] + [stops[e.end]['point'] for e in group]
                warnings.append('Odcinek komunikacji przedstawiono schematycznie: brak geometrii w GTFS.')
            geometry.extend(segment)
            distance += sum(meters(a, b) for a, b in zip(segment, segment[1:]))
            route = bundle['routes'][trip['route_id']]
            dep = datetime.fromtimestamp(first.depart, WARSAW).strftime('%H:%M')
            arr = datetime.fromtimestamp(last.arrive, WARSAW).strftime('%H:%M')
            legs.append(dict(text=f"{dep}–{arr} · linia {route['route_short_name']} · {stops[first.start]['name']} → {stops[last.end]['name']}", duration_s=round(last.arrive - first.depart), distance_m=round(sum(meters(a, b) for a, b in zip(segment, segment[1:])))))
            if trip.get('wheelchair_accessible') != '1':
                warnings.append(f"ZTP nie potwierdza dostępności dla wózka w kursie linii {route['route_short_name']}.")
        geometry.extend(egress[edges[-1].end]['geometry'])
        legs.insert(0, dict(text=f"Dojdź do przystanku {stops[edges[0].start]['name']}", distance_m=access[edges[0].start]['distance_m'], duration_s=access[edges[0].start]['duration_s']))
        legs.append(dict(text='Dojdź z przystanku do celu', distance_m=egress[edges[-1].end]['distance_m'], duration_s=egress[edges[-1].end]['duration_s']))
        routes_used = {e.route for e in edges if e.route}
        warnings.extend(a['title'] for a in alerts if not a['routes'] or routes_used.intersection(a['routes']))
        return dict(geometry=geometry, distance_m=round(distance), duration_s=round(edges[-1].arrive + ends[edges[-1].end] - departure.timestamp()),
                    steps=legs, warnings=list(dict.fromkeys(warnings)), bicycle=None,
                    sources=[source('ZTP · rozkłady GTFS', GTFS, 'available', 'Rozkłady autobusów i tramwajów; dojście i maksymalnie dwie przesiadki.')]+realtime_sources)


transit = Transit()
