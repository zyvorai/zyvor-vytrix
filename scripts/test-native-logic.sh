#!/usr/bin/env bash
# SPDX-License-Identifier: BUSL-1.1
# Unit tests for the native app's pure logic (alert rules, notification hysteresis, snapshot round trip,
# anomaly and evidence decoding), compiled with swiftc against the real model files. The anomaly and
# evidence fixtures are produced by the real collector code, so a schema drift fails here. macOS only;
# no app launch, no Accessibility needed.
set -euo pipefail
cd "$(dirname "$0")/.."
[[ "$(uname -s)" == Darwin ]] || { echo "Run on macOS." >&2; exit 1; }
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
python3 -I - "$tmp" <<'PY'
import datetime as dt, importlib.util, json, sys
spec = importlib.util.spec_from_file_location('vytrix', 'agent/vytrix.py')
v = importlib.util.module_from_spec(spec); spec.loader.exec_module(v)
base = 1_760_000_000
samples = []
for i in range(400):
    busy = 300 <= i < 305
    stamp = dt.datetime.fromtimestamp(base + i * 2, dt.timezone.utc).isoformat().replace('+00:00', 'Z')
    samples.append({'timestamp': stamp, 'host': {'memoryTotal': 1000}, 'cpu': 95.0 if busy else 20.0,
                    'memoryUsed': 400, 'diskUsed': 500, 'diskTotal': 1000, 'download': 1000.0, 'upload': 0,
                    'processes': [{'pid': 2, 'name': 'node', 'app': 'Build', 'cpu': 90.0 if busy else 2.0, 'memory': 5000, 'ports': []}],
                    'containers': [{'runtime': 'docker', 'id': 'abc', 'name': 'db', 'image': 'pg', 'state': 'running',
                                    'cpu': 3.0, 'memory': 400, 'memoryLimit': 1000}]})
ts = lambda i: base + i * 2
tmp = sys.argv[1]
json.dump(v.anomaly_report(samples), open(tmp + '/anomalies.json', 'w'))
late = [dict(s) for s in samples[290:320]]
for s in late[15:]:
    s['processes'] = s['processes'] + [{'pid': 9, 'name': 'late', 'app': 'Late', 'cpu': 1.0, 'memory': 1, 'ports': [4000]}]
json.dump(v.timeline_report(samples[290:320], samples[260:290], samples[:290][-v.ANOMALY_WARMUP:], ts(290), ts(319), 85.0),
          open(tmp + '/timeline.json', 'w'))
json.dump(v.changes_report(late, ts(290), ts(319)), open(tmp + '/changes.json', 'w'))
json.dump(v.changes_report([], ts(290), ts(319)), open(tmp + '/changes-empty.json', 'w'))
json.dump(v.evidence_report(samples[290:320], samples[260:290], samples[:290][-v.ANOMALY_WARMUP:], ts(290), ts(319)),
          open(tmp + '/evidence.json', 'w'))
PY
xcrun swiftc -swift-version 5 -parse-as-library -o "$tmp/logic" \
  native/App/Model/Snapshot.swift native/App/Model/Alerts.swift native/App/Model/Evidence.swift native/Tests/AlertTests.swift
"$tmp/logic" "$tmp"
