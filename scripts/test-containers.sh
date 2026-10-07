#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Integration test against a real container runtime.
#
#   scripts/test-containers.sh [docker|podman]
#
# Starts nginx:alpine with a published port, runs the collector (--once) and checks
# the container, its state and the port mapping.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
RUNTIME=""
for arg in "$@"; do
  case "$arg" in
    docker|podman) RUNTIME="$arg" ;;
    *) echo "Unknown argument: $arg" >&2; exit 2 ;;
  esac
done
if [[ -z "$RUNTIME" ]]; then
  if command -v podman >/dev/null; then RUNTIME=podman; elif command -v docker >/dev/null; then RUNTIME=docker; else
    echo "Neither podman nor docker is installed." >&2; exit 1
  fi
fi
command -v "$RUNTIME" >/dev/null || { echo "$RUNTIME is not installed." >&2; exit 1; }

NAME="vytrix-it-$$"
PORT="${VYTRIX_TEST_PORT:-18080}"
cleanup() { "$RUNTIME" rm -f "$NAME" >/dev/null 2>&1 || true; }
trap cleanup EXIT

echo "==> [$RUNTIME] starting nginx:alpine as $NAME on port $PORT"
"$RUNTIME" run -d --name "$NAME" -p "$PORT:80" docker.io/library/nginx:alpine >/dev/null
for _ in $(seq 1 30); do
  [[ "$("$RUNTIME" inspect -f '{{.State.Running}}' "$NAME" 2>/dev/null)" == "true" ]] && break
  sleep 1
done

echo "==> [$RUNTIME] running native collector"
SNAPSHOT="$(python3 agent/vytrix.py --once)"
RUNTIME="$RUNTIME" NAME="$NAME" PORT="$PORT" python3 - "$SNAPSHOT" <<'PY'
import json, os, sys
s = json.loads(sys.argv[1])
runtime, name, port = os.environ['RUNTIME'], os.environ['NAME'], int(os.environ['PORT'])
status = {r['name']: r for r in s.get('runtimes', [])}
assert status[runtime]['available'], f"{runtime} not available: {status[runtime]}"
matches = [c for c in s['containers'] if c['name'] == name and c['runtime'] == runtime]
assert matches, f"container {name} missing from {[c['name'] for c in s['containers']]}"
c = matches[0]
assert c['state'] == 'running', c
assert c['image'].endswith('nginx:alpine'), c['image']
assert {'hostPort': port, 'containerPort': 80, 'protocol': 'tcp'} in c['ports'], c['ports']
assert c['memory'] > 0, c
print(f"    ok: {name} running, {c['memory']/1024**2:.1f} MB, cpu {c['cpu']}%, ports {c['ports']}")
PY

echo "==> [$RUNTIME] all container checks passed"
