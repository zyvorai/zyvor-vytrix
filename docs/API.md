# Collector API and metric definitions

All `/v1` reads require `Authorization: Bearer <VYTRIX_TOKEN>`. Browser requests must have an exact allowed Origin. Serve HTTPS with `--tls-cert`/`--tls-key` or terminate TLS at a reverse proxy. All endpoints are read-only.

| Endpoint | Response |
|---|---|
| `GET /v1/snapshot` | Most recent version 1 snapshot |
| `GET /v1/history?since=EPOCH_SECONDS&limit=300` | `{version: 1, samples: [...]}` in chronological order; limit 1–1000 |
| `GET /healthz` | `{"status": "ok"}`; no token, no telemetry |
| `OPTIONS` | CORS preflight for an allowed origin |
| any other path | With `--ui-upstream`: proxied to the dashboard (GET, HEAD, POST). Otherwise 404. |

401 means invalid/missing token, 403 means denied Origin, 400 means invalid history query, 404 means unknown path, 502 means the dashboard upstream is down. Mutations are not supported. The dashboard proxy never forwards the `Authorization` header. Snapshots contain host name, OS, process names, PIDs, RSS, CPU, best-effort project folder basename, listening ports and container metadata. No argv, environment, file contents or packet payloads are collected. Project names, executable paths and container names may still be sensitive; protect your collector and exported snapshots.

## Command line

| Flag | Default | |
|---|---|---|
| `--bind`, `--port` | `127.0.0.1`, `9847` | Plain HTTP on a non-loopback address prints a warning. |
| `--allow-origin URL` | none | Exact origin, repeatable. |
| `--tls-cert`, `--tls-key` | none | PEM files; TLS 1.2+. Both or neither. |
| `--ui-upstream URL` | none | Loopback `http://` origin of the dashboard, e.g. `http://127.0.0.1:8787`. |
| `--interval` | `2` | Seconds between samples, 1–3600. |
| `--database` | `~/.local/share/vytrix/history.sqlite` | |
| `--no-containers` | off | Don't run `docker`/`podman`. |
| `--container-interval` | `5` | Seconds between container polls, 2–3600. |
| `--once` | | Print one snapshot and exit (no token needed). |

## Metrics

- Host CPU: Linux aggregate CPU tick delta; macOS sum of OS-reported `ps` CPU divided by logical cores. First Linux sample has no delta and is zero; `--once` warms up for one second.
- Process CPU: one full logical core is 100%; a multi-threaded process can exceed 100%. Linux deltas track PID + process start time to avoid PID reuse.
- Memory: bytes; host used is total minus available. Per-process/app memory is RSS and can count shared pages more than once.
- Disk: used/total bytes for `/`; not all mounted disks.
- Network: incoming/outgoing bytes per second, excluding loopback. Counter resets are clamped to zero. Linux interfaces can double-count traffic on virtual interfaces.
- Battery: percentage or null when unsupported/missing.
- Listening ports: TCP only; restricted process visibility can hide ports.
- macOS memory: estimate from `vm_stat`; macOS process CPU is the OS-reported `ps` estimate, not a sampled Mach task counter.

## Fleet Pro fields

`agent/vytrix_fleet.py` serves the same API and adds optional fields, so consumers of version 1 snapshots keep working: `hardware`, `aiWorkloads`, `inventory`, `agent`, and per-process `diskReadRate`, `diskWriteRate`, `networkInRate`, `networkOutRate`, `networkSockets` and `ai`. Rates are bytes per second. A field is omitted when the host cannot measure it. See [FLEET-PRO.md](FLEET-PRO.md).

## Containers

Present unless the collector runs with `--no-containers`; both fields are optional, so older snapshots stay valid.

- `runtimes`: `[{name: "docker" | "podman", available, error}]`. `error` is `"Not installed"`, `"Runtime not reachable (daemon or machine stopped?)"` or null.
- `containers`: `[{runtime, id, name, image, state, cpu, memory, memoryLimit, netIn, netOut, ports}]`. `cpu` is percent of one core; `memory`, `memoryLimit` (null when unlimited or unknown), `netIn` and `netOut` are bytes (network totals since the container started). `ports` is `[{hostPort | null, containerPort, protocol}]`. Stopped containers report zero CPU and memory.

The collector polls on a background thread with `docker`/`podman` `ps -a` and `stats --no-stream` only. On macOS the numbers are relative to the Docker Desktop or Podman VM. A `docker` binary that is the `podman-docker` shim is skipped.

## Storage

SQLite retention is 30 days, pruned on each sample. Full process snapshots can occupy substantial disk space; adjust `--interval` and monitor storage. Directory mode 0700, database mode 0600. The history API returns at most 1,000 samples per request; there is no rollup or query pagination in this release.
