"""Integration tests in an isolated PostgreSQL schema; no application data deleted."""
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta, timezone
import os
from pathlib import Path
import unittest
from unittest.mock import patch
from uuid import uuid4

from alembic import command
from alembic.config import Config
from fastapi.testclient import TestClient
from sqlalchemy import create_engine, func, select, text
from sqlalchemy.orm import sessionmaker

from app.database import DATABASE_URL, engine, get_db
from app.main import app
from app.models import GameOperation, GameProfile, SkinOwnership, SpinClaim, Visit


@unittest.skipUnless(os.getenv('RUN_POSTGRES_TESTS') == '1', 'Set RUN_POSTGRES_TESTS=1 for isolated PostgreSQL integration tests')
class GameTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.schema = 'game_test_' + uuid4().hex
        with engine.begin() as conn:
            conn.execute(text(f'CREATE SCHEMA {cls.schema}'))
        cls.engine = create_engine(DATABASE_URL, connect_args={'options': f'-csearch_path={cls.schema}'})
        cls.sessions = sessionmaker(bind=cls.engine)
        config = Config(str(Path(__file__).resolve().parents[1] / 'alembic.ini'))
        with cls.engine.begin() as conn:
            config.attributes['connection'] = conn
            command.upgrade(config, '59603852cabe')
            conn.execute(text("INSERT INTO users (username, email, points) VALUES ('existing', 'existing@example.test', 125)"))
            command.upgrade(config, 'head')

        def database():
            with cls.sessions() as db:
                yield db
        app.dependency_overrides[get_db] = database

    @classmethod
    def tearDownClass(cls):
        app.dependency_overrides.pop(get_db, None)
        cls.engine.dispose()
        with engine.begin() as conn:
            conn.execute(text(f'DROP SCHEMA {cls.schema} CASCADE'))

    def setUp(self):
        self.client = TestClient(app)
        result = self.client.post('/game/sessions')
        self.assertEqual(result.status_code, 201)
        self.token = result.json()['token']
        self.uid = result.json()['state']['user_id']
        self.headers = {'Authorization': 'Bearer ' + self.token}

    def tearDown(self):
        self.client.close()

    def payload(self, profile='gps', **values):
        return dict(request_id=str(uuid4()), profile=profile, **values)

    def spin(self, **values):
        payload = self.payload(place_key='sukiennice', latitude=50.06143, longitude=19.93658,
                               accuracy=5, recorded_at=datetime.now(timezone.utc).isoformat())
        payload.update(values)
        return payload

    def post(self, path, body):
        return self.client.post('/game/' + path, json=body, headers=self.headers)

    def state(self):
        return self.client.get('/game/state', headers=self.headers).json()

    def count(self, model):
        with self.sessions() as db:
            return db.scalar(select(func.count()).select_from(model).join(GameProfile, model.profile_id == GameProfile.id).where(GameProfile.user_id == self.uid))

    def test_migration_preserves_existing_database_balances(self):
        with self.sessions() as db:
            profiles = db.scalars(select(GameProfile).where(GameProfile.user_id == 1)).all()
            self.assertEqual({p.mode: p.points for p in profiles}, {'gps': 125, 'demo': 0})

    def test_expanded_catalog_and_reward_at_new_point(self):
        places = self.state()['places']
        self.assertEqual(len(places), 20)
        self.assertEqual(len({p['key'] for p in places}), 20)
        self.assertTrue(all(p['reward'] == 50 and p['radius_m'] == 45 for p in places))
        point = next(p for p in places if p['key'] == 'plac-centralny')
        self.assertEqual(point['category'], 'square')
        self.assertTrue(point['description'])
        result = self.post('spins', self.spin(place_key=point['key'], latitude=point['latitude'], longitude=point['longitude']))
        self.assertEqual(result.status_code, 200)
        self.assertEqual(result.json()['state']['profiles']['gps']['points'], 50)
        self.assertIn('plac-centralny', self.state()['profiles']['gps']['claims'])

    def test_authentication_identity_isolation_and_no_client_balance(self):
        self.assertEqual(self.client.get('/game/state').status_code, 401)
        self.assertEqual(self.client.get('/game/state', headers={'Authorization': 'Bearer invalid'}).status_code, 401)
        self.assertEqual(self.post('spins', self.spin(points=99999)).status_code, 422)
        self.assertEqual(self.post('spins', self.spin(user_id=1)).status_code, 422)
        self.post('spins', self.spin())
        other = self.client.post('/game/sessions').json()
        result = self.client.get('/game/state', headers={'Authorization': 'Bearer ' + other['token']}).json()
        self.assertEqual(result['profiles']['gps']['points'], 0)

    def test_spin_distance_freshness_cooldown_demo_and_retry(self):
        self.assertEqual(self.post('spins', self.spin(latitude=50.1)).status_code, 422)
        self.assertEqual(self.post('spins', self.spin(accuracy=26)).status_code, 422)
        old = (datetime.now(timezone.utc) - timedelta(minutes=1)).isoformat()
        self.assertEqual(self.post('spins', self.spin(recorded_at=old)).status_code, 422)
        payload = self.spin()
        first = self.post('spins', payload)
        self.assertEqual(first.status_code, 200)
        self.assertEqual(first.json()['state']['profiles']['gps']['points'], 50)
        self.assertTrue(self.post('spins', payload).json()['replayed'])
        self.assertEqual(self.post('spins', self.spin()).status_code, 409)
        self.assertEqual(self.post('spins', {**payload, 'place_key': 'wawel'}).status_code, 409)
        self.assertEqual(self.post('spins', self.spin(profile='demo')).status_code, 200)
        self.assertEqual(self.state()['profiles']['demo']['points'], 50)
        with self.sessions() as db:
            self.assertEqual(db.scalar(select(func.count()).select_from(Visit).where(Visit.user_id == self.uid)), 1)

    def test_purchase_selection_and_reloaded_state(self):
        buy = self.payload(skin_id='lajkonik')
        self.assertEqual(self.post('skins/purchase', buy).status_code, 409)
        self.assertEqual(self.post('skins/select', self.payload(skin_id='lajkonik')).status_code, 409)
        self.post('spins', self.spin())
        self.assertEqual(self.post('skins/purchase', self.payload(profile='demo', skin_id='lajkonik')).status_code, 409)
        self.assertEqual(self.post('skins/purchase', buy).status_code, 200)
        self.assertTrue(self.post('skins/purchase', buy).json()['replayed'])
        self.post('skins/purchase', self.payload(skin_id='lajkonik'))
        self.assertEqual(self.state()['profiles']['gps']['points'], 0)
        self.assertEqual(self.state()['profiles']['gps']['selected_skin'], 'lajkonik')
        self.post('skins/select', self.payload(skin_id='default'))
        self.assertIsNone(self.state()['profiles']['gps']['selected_skin'])
        self.post('skins/select', self.payload(skin_id='lajkonik'))
        self.assertEqual(self.count(SkinOwnership), 1)

    def test_parallel_spins_cannot_double_credit(self):
        payloads = [self.spin() for _ in range(6)]
        with ThreadPoolExecutor(max_workers=6) as pool:
            codes = list(pool.map(lambda p: self.post('spins', p).status_code, payloads))
        self.assertEqual(codes.count(200), 1)
        self.assertEqual(codes.count(409), 5)
        self.assertEqual(self.state()['profiles']['gps']['points'], 50)
        self.assertEqual(self.count(SpinClaim), 1)
        self.assertEqual(self.count(GameOperation), 1)

    def test_parallel_purchases_charge_once_and_ledger_balances(self):
        self.post('spins', self.spin())
        self.post('spins', self.spin(place_key='wawel', latitude=50.0544, longitude=19.9354))
        payloads = [self.payload(skin_id='lajkonik') for _ in range(6)]
        with ThreadPoolExecutor(max_workers=6) as pool:
            codes = list(pool.map(lambda p: self.post('skins/purchase', p).status_code, payloads))
        self.assertEqual(codes, [200] * 6)
        self.assertEqual(self.state()['profiles']['gps']['points'], 50)
        self.assertEqual(self.count(SkinOwnership), 1)
        with self.sessions() as db:
            total = db.scalar(select(func.sum(GameOperation.points_delta)).join(GameProfile).where(GameProfile.user_id == self.uid))
            self.assertEqual(total, 50)

    def test_failed_transaction_rolls_back_points_and_claim(self):
        with patch('app.game.finish', side_effect=RuntimeError('test failure')):
            with self.assertRaises(RuntimeError):
                self.post('spins', self.spin())
        self.assertEqual(self.state()['profiles']['gps']['points'], 0)
        self.assertEqual(self.count(SpinClaim), 0)
        self.assertEqual(self.count(GameOperation), 0)
