"""Read-only public ZTP/ZDMK adapters; unavailable/stale is never 'clear'."""
import asyncio
from datetime import datetime, timezone
import os
import time
import xml.etree.ElementTree as ET
from zoneinfo import ZoneInfo

import httpx
from google.transit import gtfs_realtime_pb2

BIKES = 'https://services-eu1.arcgis.com/svTzSt3AvH7sK6q9/arcgis/rest/services/Ciagi_rowerowe/FeatureServer/0'
CITY_WORKS = 'https://www.google.com/maps/d/kml?mid=1_iHhcnIv8THHQSyeLFPArE6k2zhIrtA&forcekml=1'
GTFS = 'https://gtfs.ztp.krakow.pl/'


def stamp():
    return datetime.now(timezone.utc).isoformat()


def source(name, url, status, detail, updated_at=None):
    return dict(name=name, url=url, status=status, detail=detail, updated_at=updated_at, fetched_at=stamp())


def parse_works(content, today):
    root = ET.fromstring(content)
    ns = {'k': 'http://www.opengis.net/kml/2.2'}
    active, unknown = [], 0
    for place in root.findall('.//k:Placemark', ns):
        values = {i.attrib.get('name'): i.findtext('k:value', default='', namespaces=ns) for i in place.findall('k:ExtendedData/k:Data', ns)}
        try:
            start = datetime.strptime(values.get('od', ''), '%d.%m.%Y').date()
            end = datetime.strptime(values.get('do', ''), '%d.%m.%Y').date()
        except ValueError:
            unknown += 1
            continue
        if not start <= today <= end:
            continue
        coords = place.findtext('k:Point/k:coordinates', default='', namespaces=ns).strip().split(',')
        if len(coords) < 2:
            unknown += 1
            continue
        lon, lat = map(float, coords[:2])
        text = values.get('Zmiany organizacji ruchu', '')
        active.append(dict(point=[lat, lon], title=place.findtext('k:name', default='Prace drogowe', namespaces=ns), text=text,
                           starts_at=start.isoformat(), ends_at=end.isoformat()))
    return active, unknown


class CityData:
    def __init__(self):
        self.cache = {}
        self.lock = asyncio.Lock()

    async def json(self, url, params=None, ttl=300):
        key = (url, tuple(sorted((params or {}).items())))
        cached = self.cache.get(key)
        if cached and time.monotonic() - cached[0] < ttl:
            return cached[1]
        async with httpx.AsyncClient(timeout=15, headers={'User-Agent': 'LajkonikGO-local-prototype'}) as client:
            response = await client.get(url, params=params)
            response.raise_for_status()
            value = response.json()
        if len(self.cache) > 80:
            self.cache.clear()
        self.cache[key] = (time.monotonic(), value)
        return value

    async def bikes(self, origin, destination):
        south, north = min(origin[0], destination[0]) - .012, max(origin[0], destination[0]) + .012
        west, east = min(origin[1], destination[1]) - .018, max(origin[1], destination[1]) + .018
        features = []
        try:
            meta = await self.json(BIKES, {'f': 'json'}, ttl=3600)
            edited = meta.get('editingInfo', {}).get('dataLastEditDate')
            updated = datetime.fromtimestamp(edited / 1000, timezone.utc).isoformat() if edited else None
            for offset in range(0, 6000, 2000):
                value = await self.json(BIKES + '/query', {
                    'f': 'geojson', 'where': '1=1', 'outFields': 'rodzaj,nawierzchnia',
                    'outSR': '4326', 'inSR': '4326', 'geometryType': 'esriGeometryEnvelope',
                    'geometry': f'{west},{south},{east},{north}', 'spatialRel': 'esriSpatialRelIntersects',
                    'resultOffset': str(offset), 'resultRecordCount': '2000', 'orderByFields': 'OBJECTID',
                })
                if 'error' in value:
                    raise ValueError('ArcGIS error')
                features.extend(value.get('features', []))
                if not value.get('properties', {}).get('exceededTransferLimit'):
                    return features, source('ZTP · infrastruktura rowerowa', BIKES, 'available',
                        'Miejski wykaz dróg rowerowych i nawierzchni w okolicy trasy.', updated)
            return features, source('ZTP · infrastruktura rowerowa', BIKES, 'partial', 'Pobrano tylko część infrastruktury w obszarze.', updated)
        except (httpx.HTTPError, ValueError, KeyError, TypeError):
            return [], source('ZTP · infrastruktura rowerowa', BIKES, 'unavailable', 'Nie udało się pobrać miejskiej infrastruktury rowerowej.')

    async def works(self):
        try:
            cached = self.cache.get(CITY_WORKS)
            if cached and time.monotonic() - cached[0] < 300:
                content = cached[1]
            else:
                async with httpx.AsyncClient(timeout=15) as client:
                    response = await client.get(CITY_WORKS)
                    response.raise_for_status()
                    content = response.content
                self.cache[CITY_WORKS] = (time.monotonic(), content)
            active, unknown = parse_works(content, datetime.now(ZoneInfo('Europe/Warsaw')).date())
            return active, source('ZDMK · miejska mapa prac', 'https://zdmk.krakow.pl/zestawienie-prac-w-miescie/', 'partial' if unknown else 'available',
                f'Zgłoszenia aktywne według dat: {len(active)}. Pominięto wpisy bez jednoznacznych dat: {unknown}. Lokalizacje są punktowe; nie określają pełnego zasięgu zamknięcia i nie są pomiarem korków.')
        except (httpx.HTTPError, ValueError, TypeError, KeyError, ET.ParseError):
            return [], source('ZDMK · miejska mapa prac', 'https://zdmk.krakow.pl/zestawienie-prac-w-miescie/', 'unavailable', 'Brak bieżących informacji o pracach drogowych.')

    async def barriers(self):
        url = os.getenv('CITY_ACCESSIBILITY_URL', '')
        if not url:
            return [], source('Bariery i dostępność', 'https://msip.krakow.pl/', 'unconfigured',
                'Brak podłączonego miejskiego wykazu schodów, krawężników i szerokości chodników. Dostępność całej trasy nie jest potwierdzona.')
        try:
            data = await self.json(url)
            features = data['features']
            if not isinstance(features, list):
                raise ValueError('Invalid GeoJSON')
            # Accepted schema is documented in backend/README.md.
            barriers = []
            for feature in features:
                props, geom = feature.get('properties', {}), feature.get('geometry', {})
                if geom.get('type') != 'Point' or props.get('active') is not True:
                    continue
                lon, lat = geom['coordinates'][:2]
                if props.get('barrier') in ('steps', 'high_kerb', 'narrow_passage', 'closed'):
                    barriers.append(dict(point=[lat, lon], title=props.get('name', props['barrier']), modes=props.get('modes', ['wheelchair'])))
            updated = data.get('updated_at')
            if not updated or (datetime.now(timezone.utc) - datetime.fromisoformat(updated.replace('Z', '+00:00'))).total_seconds() > 86400:
                return [], source('Miejskie bariery', url, 'stale', 'Wykaz barier nie ma aktualnej daty; wyłączono automatyczne omijanie.', updated)
            return barriers, source('Miejskie bariery', url, 'available', 'Zweryfikowany wykaz punktowych barier. Pozostałe odcinki nadal mogą nie mieć danych.', updated)
        except (httpx.HTTPError, ValueError, TypeError, KeyError):
            return [], source('Miejskie bariery', url, 'unavailable', 'Nie udało się pobrać wykazu barier.')

    async def transit_alerts(self):
        async def one(suffix):
            url = GTFS + f'ServiceAlerts_{suffix}.pb'
            try:
                async with httpx.AsyncClient(timeout=12) as client:
                    response = await client.get(url)
                    response.raise_for_status()
                feed = gtfs_realtime_pb2.FeedMessage()
                feed.ParseFromString(response.content)
                age = time.time() - feed.header.timestamp
                if not feed.header.timestamp or age > 600 or age < -60:
                    return [], source(f'ZTP · alerty {suffix}', url, 'stale', 'Alerty nie są aktualne.')
                alerts = []
                for entity in feed.entity:
                    if not entity.HasField('alert'):
                        continue
                    alert = entity.alert
                    periods = alert.active_period
                    if periods and not any((not p.start or p.start <= time.time()) and (not p.end or p.end >= time.time()) for p in periods):
                        continue
                    texts = alert.header_text.translation
                    title = next((t.text for t in texts if t.language == 'pl'), texts[0].text if texts else 'Utrudnienie w komunikacji')
                    alerts.append(dict(title=title, routes=[suffix + ':' + i.route_id for i in alert.informed_entity if i.route_id], effect=alert.effect))
                return alerts, source(f'ZTP · alerty {suffix}', url, 'available', 'Bieżące komunikaty transportowe.', datetime.fromtimestamp(feed.header.timestamp, timezone.utc).isoformat())
            except Exception:
                return [], source(f'ZTP · alerty {suffix}', url, 'unavailable', 'Nie udało się pobrać alertów komunikacji.')
        values = await asyncio.gather(*(one(s) for s in ('A', 'M', 'T')))
        return [a for alerts, _ in values for a in alerts], [s for _, s in values]


city = CityData()
