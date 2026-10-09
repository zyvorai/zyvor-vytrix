# SPDX-License-Identifier: BUSL-1.1
import inspect
import json
import sys
import tempfile
import threading
import unittest
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'agent'))
sys.path.insert(0, str(ROOT / 'cluster'))
import coordinator
import cluster_worker
from coordinator import Cluster, APIError, Server, password_hash, verify_password, SESSION_TTL
from cluster_worker import Client, coordinator_url, private_json, write_private

PASSWORD = 'secure-cluster-password'
HASH = password_hash(PASSWORD)


def snapshot():
    return {'version': 1, 'timestamp': '2026-10-08T12:00:00Z', 'host': {'name': 'test-mac', 'os': 'macOS', 'cores': 12, 'memoryTotal': 100}, 'cpu': 20, 'memoryUsed': 50, 'diskUsed': 50, 'diskTotal': 100, 'download': 0, 'upload': 0, 'battery': None, 'processes': []}


class ClusterTests(unittest.TestCase):
    def setUp(self):
        self.now = 1000
        users = {name: {'role': role, 'password': HASH, 'nodes': ['*']} for name, role in [('admin', 'admin'), ('view', 'viewer')]}
        users['limited'] = {'role': 'viewer', 'password': HASH, 'nodes': []}
        self.c = Cluster(':memory:', users, lambda: self.now)
        self.tokens = {name: self.call('POST', '/v1/login', '', {'username': name, 'password': PASSWORD})['token'] for name in users}
        self.devices = [self.enroll('Mac A'), self.enroll('Mac B')]

    def tearDown(self):
        self.c.db.close()

    def call(self, method, path, token='', body=None):
        return self.c.dispatch(method, path, token, body or {})

    def enroll(self, name):
        pairing = self.call('POST', '/v1/pairings', self.tokens['admin'], {'name': name})
        return self.call('POST', '/v1/enroll', '', {'code': pairing['code']})

    def heartbeat(self, device, **extra):
        return self.call('POST', '/v1/heartbeat', device['token'], {'snapshot': snapshot(), **extra})

    def assertAPI(self, status, fn):
        with self.assertRaises(APIError) as error:
            fn()
        self.assertEqual(error.exception.status, status)

    def test_enrollment_single_use_expiry_and_roles(self):
        self.assertAPI(403, lambda: self.call('POST', '/v1/pairings', self.tokens['view'], {'name': 'Denied'}))
        pairing = self.call('POST', '/v1/pairings', self.tokens['admin'], {'name': 'Mac C'})
        self.call('POST', '/v1/enroll', '', {'code': pairing['code']})
        self.assertAPI(401, lambda: self.call('POST', '/v1/enroll', '', {'code': pairing['code']}))
        pairing = self.call('POST', '/v1/pairings', self.tokens['admin'], {'name': 'Mac D'})
        self.now += 301
        self.assertAPI(401, lambda: self.call('POST', '/v1/enroll', '', {'code': pairing['code']}))

    def test_telemetry_is_stored_and_served_without_secrets(self):
        self.assertTrue(all(not n['online'] and n['snapshot'] is None for n in self.call('GET', '/v1/cluster', self.tokens['view'])['nodes']))
        for d in self.devices:
            self.heartbeat(d)
        rows = self.call('GET', '/v1/cluster', self.tokens['view'])
        self.assertEqual({n['name'] for n in rows['nodes']}, {'Mac A', 'Mac B'})
        self.assertTrue(all(n['online'] and n['snapshot']['host']['name'] == 'test-mac' for n in rows['nodes']))
        self.assertNotIn(self.devices[0]['token'], json.dumps(rows))
        self.assertAPI(403, lambda: self.call('GET', '/v1/audit', self.tokens['view']))
        self.assertTrue(self.call('GET', '/v1/audit', self.tokens['admin'])['events'])

    def test_there_is_no_command_channel(self):
        """The coordinator is telemetry only: it cannot ask a Mac to do anything."""
        self.assertEqual(self.heartbeat(self.devices[0]), {'ok': True})
        for path in ('/v1/commands', '/v1/services', '/v1/exec'):
            self.assertAPI(404, lambda path=path: self.call('POST', path, self.tokens['admin'], {'action': 'restart'}))
        self.assertNotIn('commands', self.call('GET', '/v1/cluster', self.tokens['admin']))
        # A worker cannot smuggle service state or results in: unknown fields are ignored and nothing is dispatched back.
        self.assertEqual(self.heartbeat(self.devices[0], services={'x': 'running'}, results=[{'id': 'y', 'status': 'succeeded'}]), {'ok': True})
        tables = {r[0] for r in self.c.db.execute("SELECT name FROM sqlite_master WHERE type='table'")}
        self.assertFalse({'commands', 'batches'} & tables)
        for module in (coordinator, cluster_worker):
            source = inspect.getsource(module)
            for forbidden in ('launchctl', 'subprocess', 'os.system'):
                self.assertNotIn(forbidden, source)

    def test_stale_machines_go_offline(self):
        for d in self.devices:
            self.heartbeat(d)
        self.now += 16
        self.assertTrue(all(not n['online'] for n in self.call('GET', '/v1/cluster', self.tokens['view'])['nodes']))

    def test_revocation_and_session_expiry(self):
        d = self.devices[0]
        self.assertAPI(403, lambda: self.call('POST', '/v1/revoke', self.tokens['view'], {'node': d['id']}))
        self.call('POST', '/v1/revoke', self.tokens['admin'], {'node': d['id']})
        self.assertAPI(401, lambda: self.heartbeat(d))
        self.call('POST', '/v1/logout', self.tokens['view'])
        self.assertAPI(401, lambda: self.call('GET', '/v1/cluster', self.tokens['view']))
        self.now += SESSION_TTL + 1
        self.assertAPI(401, lambda: self.call('GET', '/v1/cluster', self.tokens['admin']))

    def test_scoped_reads(self):
        self.c.users['limited']['nodes'] = [self.devices[0]['id']]
        self.assertEqual([n['id'] for n in self.call('GET', '/v1/cluster', self.tokens['limited'])['nodes']], [self.devices[0]['id']])

    def test_malformed_telemetry_rejected(self):
        for value in [None, {}, {**snapshot(), 'cpu': float('nan')}, {**snapshot(), 'cpu': 101}, {**snapshot(), 'memoryUsed': 500}]:
            self.assertAPI(400, lambda: self.call('POST', '/v1/heartbeat', self.devices[0]['token'], {'snapshot': value}))

    def test_operator_role_does_not_exist(self):
        with self.assertRaises(ValueError):
            Cluster(':memory:', {'ops': {'role': 'operator', 'password': HASH, 'nodes': ['*']}})

    def test_password_and_login_rate_limit(self):
        self.assertTrue(verify_password(PASSWORD, HASH))
        self.assertFalse(verify_password('wrong', HASH))
        for _ in range(10):
            with self.assertRaises(APIError):
                self.c.dispatch('POST', '/v1/login', '', {'username': 'admin', 'password': 'incorrect'}, 'bad-ip')
        self.assertAPI(429, lambda: self.c.dispatch('POST', '/v1/login', '', {'username': 'admin', 'password': PASSWORD}, 'bad-ip'))


class WorkerTests(unittest.TestCase):
    def test_coordinator_url_security(self):
        self.assertEqual(coordinator_url('https://mac.example/'), 'https://mac.example')
        for value in ['http://mac.example', 'https://user:secret@mac.example', 'https://mac.example/path', 'https://mac.example?token=secret', 'file:///tmp/x']:
            with self.assertRaises(ValueError):
                coordinator_url(value)

    def test_private_credentials(self):
        with tempfile.TemporaryDirectory() as d:
            path = Path(d) / 'config.json'
            write_private(path, {'token': 'test'})
            self.assertEqual(private_json(path), {'token': 'test'})
            path.chmod(0o644)
            with self.assertRaises(ValueError):
                private_json(path)


class HTTPTests(unittest.TestCase):
    def test_real_http_login_enrollment_auth_and_origins(self):
        c = Cluster(':memory:', {'admin': {'password': HASH, 'role': 'admin', 'nodes': ['*']}})
        server = Server(('127.0.0.1', 0), c, ['http://localhost:5173'])
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        client = Client(f'http://127.0.0.1:{server.server_port}')
        try:
            session = client.post('/v1/login', {'username': 'admin', 'password': PASSWORD})
            client.token = session['token']
            code = client.post('/v1/pairings', {'name': 'Integration Mac'})['code']
            device = client.post('/v1/enroll', {'code': code})
            worker = Client(client.origin, device['token'])
            self.assertEqual(worker.post('/v1/heartbeat', {'snapshot': snapshot()}), {'ok': True})
            for origin, expected in [('https://evil.example', 403), ('http://localhost:5173', 200)]:
                request = urllib.request.Request(client.origin + '/v1/cluster', headers={'Authorization': 'Bearer ' + client.token, 'Origin': origin})
                try:
                    response = urllib.request.urlopen(request)
                    self.assertEqual(response.status, expected)
                    self.assertEqual(response.headers['Access-Control-Allow-Origin'], origin)
                except urllib.error.HTTPError as e:
                    self.assertEqual(e.code, expected)
            with self.assertRaises(urllib.error.HTTPError) as e:
                urllib.request.urlopen(client.origin + '/v1/cluster')
            self.assertEqual(e.exception.code, 401)
            self.assertEqual(json.load(urllib.request.urlopen(client.origin + '/healthz')), {'status': 'ok'})
        finally:
            server.shutdown()
            server.server_close()
            c.db.close()


if __name__ == '__main__':
    unittest.main()
