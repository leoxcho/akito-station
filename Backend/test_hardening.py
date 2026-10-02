import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
from fastapi.testclient import TestClient
from . import server

class HardeningTests(unittest.TestCase):
    def setUp(self):
        self.directory=tempfile.TemporaryDirectory()
        self.patch=patch.object(server,'DB',str(Path(self.directory.name)/'payments.sqlite3')); self.patch.start()
        self.client=TestClient(server.app)
    def tearDown(self):
        self.patch.stop();self.directory.cleanup()
    def test_body_bounds(self):
        response=self.client.post('/login/poll',content=b'x'*(1024*1024+1))
        self.assertEqual(response.status_code,413)
    def test_authenticated_idempotent_deletion_request(self):
        self.assertEqual(self.client.post('/account/deletion-request').status_code,401)
        with patch.object(server,'account',return_value='issuer|owner'):
            for _ in range(2): self.assertEqual(self.client.post('/account/deletion-request').json()['status'],'pending')
        with server.db() as connection:
            self.assertEqual(connection.execute('SELECT COUNT(*) FROM deletion_requests').fetchone()[0],1)
    def test_persistent_event_retry_and_dedup(self):
        self.assertFalse(server.event_completed('stripe','evt_fixture'))
        self.assertFalse(server.event_completed('stripe','evt_fixture'))
        server.complete_event('stripe','evt_fixture')
        self.assertTrue(server.event_completed('stripe','evt_fixture'))
        self.assertFalse(server.event_completed('paypal','evt_fixture'))
        with self.assertRaises(Exception): server.event_completed('stripe','')
    def test_health_database(self):
        self.assertEqual(self.client.get('/health').json(),{'status':'ok'})

class BodyTimeoutTests(unittest.IsolatedAsyncioTestCase):
    async def test_slow_body_is_bounded_without_provider_call(self):
        import asyncio
        from .protections import RequestBounds
        messages=[]
        async def app(scope,receive,send):raise AssertionError('Timed-out body reached application')
        async def receive():await asyncio.sleep(1);return {'type':'http.request','body':b'', 'more_body':False}
        async def send(message):messages.append(message)
        middleware=RequestBounds(app,body_timeout=0.01)
        await middleware({'type':'http','method':'POST','path':'/checkout','headers':[],'client':('fixture',1)},receive,send)
        self.assertEqual(messages[0]['status'],408)
