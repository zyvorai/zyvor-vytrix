# SPDX-License-Identifier: BUSL-1.1
import importlib.util, json, os, subprocess, sys, tempfile, threading, unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

def load(name, rel):
    spec = importlib.util.spec_from_file_location(name, ROOT / rel)
    module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
    return module

mcp = load('vytrix_mcp', 'agent/vytrix_mcp.py')
collector = load('vytrix_for_mcp', 'agent/vytrix.py')

class FakeOpener:
    def __init__(self): self.requests = []
    def open(self, request, timeout=0):
        self.requests.append(request)
        import io
        return io.BytesIO(json.dumps({'path': request.full_url, 'auth': request.get_header('Authorization')}).encode())

class McpTests(unittest.TestCase):
    def server(self):
        opener = FakeOpener()
        return mcp.Server('http://127.0.0.1:9847', 'tok', opener), opener
    def rpc(self, server, method, params=None, ident=1):
        return server.handle({'jsonrpc': '2.0', 'id': ident, 'method': method, 'params': params or {}})

    def test_every_tool_is_a_get_on_v1_and_marked_read_only(self):
        server, opener = self.server()
        listed = self.rpc(server, 'tools/list')['result']['tools']
        self.assertEqual({t['name'] for t in listed}, set(mcp.TOOLS))
        self.assertTrue(all(t['annotations']['readOnlyHint'] for t in listed))
        sample = {'vytrix_snapshot': {}, 'vytrix_history': {'since': 1}, 'vytrix_anomalies': {'limit': 5},
                  'vytrix_evidence': {'from': 1, 'to': 2, 'metric': 'cpu'}, 'vytrix_timeline': {'from': 1, 'to': 2},
                  'vytrix_changes': {'since': 1}}
        for name in mcp.TOOLS:
            self.rpc(server, 'tools/call', {'name': name, 'arguments': sample[name]})
        self.assertEqual(len(opener.requests), len(mcp.TOOLS))
        for r in opener.requests:
            self.assertEqual(r.get_method(), 'GET')
            self.assertIsNone(r.data)
            self.assertTrue(r.full_url.startswith('http://127.0.0.1:9847/v1/'))
            self.assertEqual(r.get_header('Authorization'), 'Bearer tok')
        names = ' '.join(mcp.TOOLS)
        for verb in ('kill', 'stop', 'set', 'write', 'delete', 'restart', 'run', 'exec'):
            self.assertNotIn(verb, names)

    def test_cluster_tools_only_with_cluster_and_use_its_token(self):
        server, _ = self.server()
        self.assertNotIn('vytrix_cluster', {t['name'] for t in self.rpc(server, 'tools/list')['result']['tools']})
        self.assertEqual(self.rpc(server, 'tools/call', {'name': 'vytrix_cluster'})['error']['code'], -32602)
        opener = FakeOpener()
        server = mcp.Server('http://127.0.0.1:9847', 'tok', opener, cluster=('https://coord.example', 'ctok'))
        listed = self.rpc(server, 'tools/list')['result']['tools']
        self.assertTrue(set(mcp.CLUSTER_TOOLS) <= {t['name'] for t in listed})
        self.assertTrue(all(t['annotations']['readOnlyHint'] for t in listed))
        for name in mcp.CLUSTER_TOOLS:
            self.rpc(server, 'tools/call', {'name': name, 'arguments': {'node': 'a b'} if name == 'vytrix_fleet_history' else {}})
        self.rpc(server, 'tools/call', {'name': 'vytrix_snapshot'})
        *cluster, collector_req = opener.requests
        for r in cluster:
            self.assertEqual((r.get_method(), r.get_header('Authorization')), ('GET', 'Bearer ctok'))
            self.assertTrue(r.full_url.startswith('https://coord.example/v1/'))
        self.assertEqual(collector_req.get_header('Authorization'), 'Bearer tok')
        self.assertIn('node=a+b', cluster[1].full_url)
        self.assertEqual(self.rpc(server, 'tools/call', {'name': 'vytrix_fleet_history', 'arguments': {'node': 5}})['error']['code'], -32602)
        names = ' '.join(mcp.CLUSTER_TOOLS)
        for verb in ('kill', 'stop', 'set', 'write', 'delete', 'restart', 'run', 'exec', 'webhook', 'audit', 'rule'):
            self.assertNotIn(verb, names)

    def test_prompts_and_resources(self):
        server, opener = self.server()
        listed = self.rpc(server, 'prompts/list')['result']['prompts']
        self.assertEqual({p['name'] for p in listed}, set(mcp.PROMPTS))
        for name in mcp.PROMPTS:
            text = self.rpc(server, 'prompts/get', {'name': name, 'arguments': {'minutes': '30'}})['result']['messages'][0]['content']['text']
            self.assertIn('Do not invent counters', text)
        self.assertIn('1800', self.rpc(server, 'prompts/get', {'name': 'vytrix_what_changed', 'arguments': {'minutes': '30'}})['result']['messages'][0]['content']['text'])
        self.assertIn('86400', self.rpc(server, 'prompts/get', {'name': 'vytrix_what_changed', 'arguments': {'minutes': '999999'}})['result']['messages'][0]['content']['text'])
        self.assertEqual({r['uri'] for r in self.rpc(server, 'resources/list')['result']['resources']}, set(mcp.RESOURCES))
        body = self.rpc(server, 'resources/read', {'uri': 'vytrix://snapshot'})['result']['contents'][0]
        self.assertIn('/v1/snapshot', body['text'])
        self.assertEqual(self.rpc(server, 'resources/read', {'uri': 'file:///etc/passwd'})['error']['code'], -32602)
        self.assertEqual(len(opener.requests), 1)

    def test_arguments_are_validated_and_unknown_tools_rejected(self):
        server, opener = self.server()
        self.assertEqual(self.rpc(server, 'tools/call', {'name': 'rm_rf'})['error']['code'], -32602)
        self.assertEqual(self.rpc(server, 'tools/call', {'name': 'vytrix_evidence', 'arguments': {'from': 1}})['error']['code'], -32602)
        self.assertEqual(self.rpc(server, 'tools/call', {'name': 'vytrix_snapshot', 'arguments': {'path': '/etc'}})['error']['code'], -32602)
        self.assertEqual(self.rpc(server, 'tools/call', {'name': 'vytrix_history', 'arguments': {'since': 'x'}})['error']['code'], -32602)
        self.assertEqual(opener.requests, [])

    def test_protocol_basics(self):
        server, _ = self.server()
        init = self.rpc(server, 'initialize', {'protocolVersion': '2025-06-18'})['result']
        self.assertEqual(init['serverInfo']['name'], 'vytrix')
        self.assertIn('Do not invent counters', init['instructions'])
        self.assertIsNone(server.handle({'jsonrpc': '2.0', 'method': 'notifications/initialized'}))
        self.assertEqual(self.rpc(server, 'ping')['result'], {})
        self.assertEqual(self.rpc(server, 'nope')['error']['code'], -32601)
        prompt = self.rpc(server, 'prompts/get', {'name': 'vytrix_triage'})['result']
        self.assertIn('Do not invent counters', prompt['messages'][0]['content']['text'])

    def test_url_rule(self):
        self.assertEqual(mcp.collector_url('http://localhost:9847/'), 'http://localhost:9847')
        self.assertEqual(mcp.collector_url('https://mac.example:9847'), 'https://mac.example:9847')
        with self.assertRaises(ValueError): mcp.collector_url('http://mac.example:9847')

    def test_stdio_against_a_real_collector(self):
        with tempfile.TemporaryDirectory() as d:
            store = collector.Store(str(Path(d) / 'h.sqlite'))
            snap = collector.Collector().snapshot()
            store.add(snap)
            token = 'a' * 32
            httpd = collector.TelemetryServer(('127.0.0.1', 0), token, [], store, snap)
            threading.Thread(target=httpd.serve_forever, daemon=True).start()
            env = dict(os.environ, VYTRIX_TOKEN=token, VYTRIX_URL=f'http://127.0.0.1:{httpd.server_port}')
            lines = [{'jsonrpc': '2.0', 'id': 1, 'method': 'initialize', 'params': {}},
                     {'jsonrpc': '2.0', 'method': 'notifications/initialized'},
                     {'jsonrpc': '2.0', 'id': 2, 'method': 'tools/call', 'params': {'name': 'vytrix_snapshot', 'arguments': {}}}]
            try:
                out = subprocess.run([sys.executable, '-I', str(ROOT / 'agent/vytrix_mcp.py')], input='\n'.join(map(json.dumps, lines)) + '\n',
                                     capture_output=True, text=True, env=env, timeout=20)
            finally:
                httpd.shutdown(); httpd.server_close()
            replies = [json.loads(l) for l in out.stdout.splitlines()]
            self.assertEqual([r['id'] for r in replies], [1, 2])
            body = json.loads(replies[1]['result']['content'][0]['text'])
            self.assertEqual(body['version'], 1)
            self.assertNotIn(token, out.stdout + out.stderr)

    def test_missing_token_exits_without_serving(self):
        env = {k: v for k, v in os.environ.items() if k != 'VYTRIX_TOKEN'}
        out = subprocess.run([sys.executable, '-I', str(ROOT / 'agent/vytrix_mcp.py')], capture_output=True, text=True, env=env, timeout=10)
        self.assertEqual(out.returncode, 2)

if __name__ == '__main__': unittest.main()
