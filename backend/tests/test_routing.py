from datetime import date
import unittest
from unittest.mock import AsyncMock, patch

from fastapi.testclient import TestClient

from app.city_data import parse_works
from app.main import app
from app.road_routes import bicycle_assessment, costing
from app.transit import Connection, active_services, scan


class RouteTests(unittest.TestCase):
    def test_city_works_dates_are_respected_and_unknown_is_not_current(self):
        xml = '''<kml xmlns="http://www.opengis.net/kml/2.2"><Document>'''
        for title, start, end in [('active', '01.10.2026', '31.10.2026'), ('expired', '01.10.2025', '31.10.2025'), ('unknown', '', '')]:
            xml += f'''<Placemark><name>{title}</name><ExtendedData><Data name="od"><value>{start}</value></Data><Data name="do"><value>{end}</value></Data></ExtendedData><Point><coordinates>19.94,50.06,0</coordinates></Point></Placemark>'''
        xml += '</Document></kml>'
        works, unknown = parse_works(xml, date(2026, 10, 4))
        self.assertEqual([w['title'] for w in works], ['active'])
        self.assertEqual(unknown, 1)
        self.assertEqual(works[0]['point'], [50.06, 19.94])

    def test_wheelchair_has_a_distinct_profile_and_grade_limit(self):
        profile, options = costing('wheelchair')
        self.assertEqual(profile, 'pedestrian')
        self.assertEqual(options['pedestrian']['type'], 'wheelchair')
        self.assertEqual(options['pedestrian']['max_grade'], 6)
        self.assertNotEqual(costing('bike'), costing('car'))

    def test_bicycle_coverage_uses_real_nearby_segments_and_rough_surfaces(self):
        feature = dict(geometry=dict(type='LineString', coordinates=[[19.94, 50.06], [19.94, 50.061]]), properties=dict(nawierzchnia='kostka'))
        result = bicycle_assessment([[50.06, 19.94], [50.061, 19.94]], [feature])
        self.assertEqual(result['coverage_pct'], 100)
        self.assertGreater(result['rough_m'], 100)
        far = bicycle_assessment([[50.06, 19.95], [50.061, 19.95]], [feature])
        self.assertEqual(far['coverage_pct'], 0)

    def test_transit_transfer_and_boarding_time(self):
        connections = [Connection(100, 200, 'a', 'b', 'one', '10'), Connection(300, 400, 'c', 'd', 'two', '20')]
        journey = scan(connections, {'a': 0}, {'d': 50}, {'b': [('c', 30)]})
        self.assertEqual([e.trip for e in journey], ['one', 'walk', 'two'])
        self.assertIsNone(scan(connections, {'a': 90}, {'d': 50}, {'b': [('c', 30)]}))

    def test_service_exceptions_override_weekday_calendar(self):
        calendar = [dict(service_id='x', sunday='1', start_date='20260101', end_date='20261231')]
        self.assertEqual(active_services(calendar, [dict(service_id='x', date='20261004', exception_type='2')], date(2026, 10, 4)), set())

    def test_transit_can_finish_with_a_walk_between_platforms(self):
        journey = scan([Connection(100, 200, 'a', 'b', 'one', '10')], {'a': 0}, {'c': 50}, {'b': [('c', 30)]})
        self.assertEqual([e.trip for e in journey], ['one', 'walk'])
        self.assertEqual(journey[-1].arrive, 230)

    def test_invalid_coordinate_or_mode_is_rejected_before_external_calls(self):
        client = TestClient(app)
        response = client.post('/routes', json=dict(origin=dict(latitude=52, longitude=21), destination=dict(latitude=50.06, longitude=19.94), mode='car'))
        self.assertEqual(response.status_code, 422)

    def test_unavailable_routing_returns_error_not_fake_geometry(self):
        client = TestClient(app)
        with patch('app.main.city.bikes', new=AsyncMock(return_value=([], {}))), patch('app.main.city.works', new=AsyncMock(return_value=([], {}))), patch('app.main.city.barriers', new=AsyncMock(return_value=([], {}))), patch('app.main.road_plan', new=AsyncMock(side_effect=RuntimeError('provider unavailable'))):
            with self.assertRaises(RuntimeError):
                client.post('/routes', json=dict(origin=dict(latitude=50.0679, longitude=19.9454), destination=dict(latitude=50.06143, longitude=19.93658), mode='walk'))


if __name__ == '__main__':
    unittest.main()
