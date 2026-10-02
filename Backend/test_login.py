"""Offline device-flow contract tests; no identity/payment provider calls."""
import unittest
from unittest.mock import patch
import httpx
from fastapi.testclient import TestClient
from . import server


class LoginTests(unittest.TestCase):
    def setUp(self):
        self.client = TestClient(server.app)
        self.environment = patch.dict(server.os.environ, {
            'OIDC_DEVICE_URL': 'https://identity.example.test/device',
            'OIDC_TOKEN_URL': 'https://identity.example.test/token',
            'OIDC_CLIENT_ID': 'fixture-native-client',
            'OIDC_AUDIENCE': 'fixture-api',
        })
        self.environment.start()
        self.addCleanup(self.environment.stop)

    @patch.object(server, 'call')
    def test_start_uses_native_client_and_audience(self, call):
        call.return_value = dict(device_code='fixture-device', user_code='fixture-code',
                                 verification_uri='https://identity.example.test/verify',
                                 interval=5, expires_in=900)
        result = self.client.post('/login/start', json={})
        self.assertEqual(result.status_code, 200)
        self.assertEqual(result.json()['deviceCode'], 'fixture-device')
        self.assertEqual(call.call_args.kwargs['data']['client_id'], 'fixture-native-client')
        self.assertEqual(call.call_args.kwargs['data']['audience'], 'fixture-api')

    @patch.object(server.httpx, 'post')
    def test_pending_and_slow_down(self, post):
        for error in ('authorization_pending', 'slow_down'):
            post.return_value = httpx.Response(400, json={'error': error})
            result = self.client.post('/login/poll', json={'deviceCode': 'fixture-device'})
            self.assertEqual(result.status_code, 200)
            self.assertIsNone(result.json()['token'])
            self.assertEqual(result.json().get('interval'), 10 if error == 'slow_down' else None)

    @patch.object(server, 'account', return_value='fixture-owner')
    @patch.object(server.httpx, 'post')
    def test_success_validates_api_token(self, post, account):
        post.return_value = httpx.Response(200, json={'access_token': 'fixture-access'},
                                          request=httpx.Request('POST', 'https://identity.example.test/token'))
        result = self.client.post('/login/poll', json={'deviceCode': 'fixture-device'})
        self.assertEqual(result.json()['token'], 'fixture-access')
        account.assert_called_once_with('Bearer fixture-access')

    @patch.object(server.httpx, 'post')
    def test_denied_or_expired_device_code(self, post):
        for error in ('access_denied', 'expired_token'):
            post.return_value = httpx.Response(400, json={'error': error},
                                              request=httpx.Request('POST', 'https://identity.example.test/token'))
            self.assertEqual(self.client.post('/login/poll', json={'deviceCode': 'fixture-device'}).status_code, 401)

    def test_account_routes_require_bearer(self):
        for path in ('/checkout', '/restore', '/manage'):
            self.assertEqual(self.client.post(path, json={}).status_code, 401)
        self.assertEqual(self.client.get('/entitlement').status_code, 401)
