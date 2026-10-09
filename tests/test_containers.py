# SPDX-License-Identifier: BUSL-1.1
import importlib.util
import json
import unittest
from pathlib import Path

ROOT = Path(__file__).parents[1]
spec = importlib.util.spec_from_file_location('vytrix', ROOT/'agent/vytrix.py')
v = importlib.util.module_from_spec(spec); spec.loader.exec_module(v)
FIXTURES = Path(__file__).parent/'fixtures'

def fixture(name):
    return (FIXTURES/name).read_text()

class FakeRuntime:
    """Replays recorded CLI output; records every command so tests can assert read-only usage."""
    def __init__(self, outputs, installed=('docker', 'podman')):
        self.outputs = outputs
        self.installed = installed
        self.calls = []
    def which(self, name):
        return f'/usr/bin/{name}' if name in self.installed else None
    def run(self, args, timeout=3):
        self.calls.append(args)
        name = Path(args[0]).name
        return self.outputs.get((name, args[1]), '')

def recorded(overrides=None):
    outputs = {
        ('docker', '--version'): 'Docker version 28.4.0, build abc1234',
        ('docker', 'ps'): fixture('docker-ps.jsonl'),
        ('docker', 'stats'): fixture('docker-stats.jsonl'),
        ('podman', 'ps'): fixture('podman-ps.json'),
        ('podman', 'stats'): fixture('podman-stats.json'),
    }
    outputs.update(overrides or {})
    return outputs

class ParsingTests(unittest.TestCase):
    def test_sizes(self):
        self.assertEqual(v.parse_size('412MiB'), 412*1024**2)
        self.assertEqual(v.parse_size('1.2MB'), 1.2e6)
        self.assertEqual(v.parse_size('648kB'), 648000)
        self.assertEqual(v.parse_size('0B'), 0)
        self.assertEqual(v.parse_size('--'), 0)
        self.assertEqual(v.parse_pair('9.2MiB / 512MiB'), (9.2*1024**2, 512*1024**2))
        self.assertEqual(v.parse_percent('38.52%'), 38.52)
        self.assertEqual(v.parse_percent('--'), 0)

    def test_docker_ports(self):
        ports = v.parse_docker_ports('0.0.0.0:8080->80/tcp, [::]:8080->80/tcp, 443/tcp, 0.0.0.0:9000-9001->9000-9001/udp')
        self.assertEqual(ports, [
            dict(hostPort=8080, containerPort=80, protocol='tcp'),
            dict(hostPort=None, containerPort=443, protocol='tcp'),
            dict(hostPort=9000, containerPort=9000, protocol='udp'),
            dict(hostPort=9001, containerPort=9001, protocol='udp'),
        ])
        self.assertEqual(v.parse_docker_ports(''), [])

    def test_podman_ports(self):
        ports = v.parse_podman_ports(json.loads(fixture('podman-ps.json'))[0]['Ports'])
        self.assertEqual([(p['hostPort'], p['containerPort']) for p in ports], [(18000, 8000), (9100, 9100), (9101, 9101)])
        self.assertEqual(v.parse_podman_ports(None), [])

    def test_json_rows_accepts_array_and_lines(self):
        self.assertEqual(len(v.json_rows(fixture('docker-ps.jsonl'))), 3)
        self.assertEqual(len(v.json_rows(fixture('podman-ps.json'))), 2)
        self.assertEqual(v.json_rows('not json\n{"ID":"x"}'), [{'id': 'x'}])

class ProbeTests(unittest.TestCase):
    def probe(self, runtime):
        return v.ContainerProbe(runner=runtime.run, which=runtime.which)

    def test_docker_and_podman(self):
        runtime = FakeRuntime(recorded())
        containers, runtimes = self.probe(runtime).collect()
        self.assertEqual([r['available'] for r in runtimes], [True, True])
        by_name = {c['name']: c for c in containers}
        self.assertEqual(set(by_name), {'postgres', 'web', 'grafana', 'ml-worker', 'cache'})
        pg = by_name['postgres']
        self.assertEqual(pg['runtime'], 'docker')
        self.assertEqual(pg['cpu'], 2.45)
        self.assertEqual(pg['memory'], 412*1024**2)
        self.assertAlmostEqual(pg['memoryLimit'], 7.654*1024**3)
        self.assertEqual(pg['ports'], [dict(hostPort=5432, containerPort=5432, protocol='tcp')])
        self.assertEqual(by_name['grafana']['state'], 'exited')
        self.assertEqual(by_name['grafana']['cpu'], 0)
        worker = by_name['ml-worker']
        self.assertEqual(worker['runtime'], 'podman')
        self.assertEqual(worker['cpu'], 38.52)  # short stats id matched to full ps id
        self.assertEqual(worker['netIn'], 420e6)
        self.assertEqual(by_name['cache']['memory'], 0)

    def test_only_read_only_commands(self):
        runtime = FakeRuntime(recorded())
        self.probe(runtime).collect()
        self.assertTrue(runtime.calls)
        for call in runtime.calls:
            self.assertIn(call[1], ('--version', 'version', 'ps', 'stats'))
            if call[1] == 'stats':
                self.assertIn('--no-stream', call)

    def test_missing_runtimes(self):
        containers, runtimes = self.probe(FakeRuntime({}, installed=())).collect()
        self.assertEqual(containers, [])
        self.assertEqual(runtimes, [dict(name='docker', available=False, error='Not installed'), dict(name='podman', available=False, error='Not installed')])

    def test_unreachable_daemon_or_timeout(self):
        # command() returns '' on timeout or a stopped Docker daemon / Podman machine.
        runtime = FakeRuntime(recorded({('docker', 'ps'): '', ('docker', 'stats'): ''}))
        containers, runtimes = self.probe(runtime).collect()
        self.assertFalse(runtimes[0]['available'])
        self.assertIn('not reachable', runtimes[0]['error'])
        self.assertTrue(all(c['runtime'] == 'podman' for c in containers))

    def test_docker_without_containers_is_available(self):
        runtime = FakeRuntime(recorded({('docker', 'ps'): '', ('docker', 'stats'): '', ('docker', 'version'): '28.4.0\n'}))
        containers, runtimes = self.probe(runtime).collect()
        self.assertEqual(runtimes[0], dict(name='docker', available=True, error=None))
        self.assertTrue(all(c['runtime'] == 'podman' for c in containers))

    def test_docker_listing_skips_size(self):
        runtime = FakeRuntime(recorded())
        self.probe(runtime).collect()
        ps = next(c for c in runtime.calls if Path(c[0]).name == 'docker' and c[1] == 'ps')
        self.assertNotIn('{{json .}}', ps)
        self.assertNotIn('Size', ps[-1])

    def test_podman_docker_shim_not_double_counted(self):
        runtime = FakeRuntime(recorded({('docker', '--version'): 'podman version 5.6.1'}))
        containers, runtimes = self.probe(runtime).collect()
        self.assertFalse(runtimes[0]['available'])
        self.assertEqual({c['runtime'] for c in containers}, {'podman'})

    def test_real_timeout_is_soft(self):
        self.assertEqual(v.command(['sleep', '5'], timeout=.2), '')

    def test_snapshot_includes_containers(self):
        probe = self.probe(FakeRuntime(recorded()))
        probe.collect()
        collector = v.Collector(containers=probe)
        collector.snapshot()
        s = collector.snapshot()
        self.assertEqual(len(s['containers']), 5)
        self.assertEqual(len(s['runtimes']), 2)
        json.dumps(s)

if __name__ == '__main__':
    unittest.main()
