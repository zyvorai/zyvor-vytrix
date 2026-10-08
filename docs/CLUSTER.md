# Mac cluster (read-only)

Vytrix can show one machine or a fleet. Each Mac runs a small worker that **pushes** its snapshot to a coordinator; the dashboard reads the coordinator. This is opt-in and separate from `agent/vytrix.py`.

**It is read-only end to end.** The coordinator has no command channel: it cannot start, stop or change anything on a Mac, and the worker has no code that runs `launchctl`, a shell or any other subprocess. A test (`test_there_is_no_command_channel`) fails if that changes. The only thing a pairing code or an administrator can do is let a Mac send telemetry, or stop it from doing so.

## Components

- Dashboard: **Monitor → Mac cluster**. Machine cards with CPU, memory, disk and network, a recent CPU sparkline, machine details (applications, containers), and, for administrators, pairing codes, revocation and the audit log.
- `cluster/coordinator.py`: Python 3.10+ standard library HTTP/TLS server with SQLite. Runs on a Mac or Linux host and only receives outbound worker heartbeats; it never connects to your Macs.
- `agent/cluster_worker.py`: reuses the collector (`Collector`, `ContainerProbe`) to read this Mac and POST the snapshot. Runs as the logged-in user, never root. No inbound port.

It does not pool memory or GPUs, schedule work, or collect GPU/sensor data. App memory is RSS.

## 1. Start the coordinator

In a private folder outside the checkout:

```bash
mkdir -p ~/.vytrix-cluster && chmod 700 ~/.vytrix-cluster && cd ~/.vytrix-cluster && umask 077
python3 /path/to/zyvor-vytrix/cluster/coordinator.py --init-user admin > users.json
python3 /path/to/zyvor-vytrix/cluster/coordinator.py \
  --config users.json --database cluster.sqlite \
  --allow-origin http://localhost:5173
```

The password is prompted privately (12+ characters); the file stores a salted PBKDF2-SHA256 hash. `--init-user NAME --role viewer` prints another entry to merge into `users.json` (roles: `admin`, `viewer`). Users have `nodes: ["*"]` or a list of machine IDs; scope is checked on every request. Restart after editing. The default listener is `http://127.0.0.1:9848`.

For remote Macs use HTTPS (a non-loopback listener without TLS is refused):

```bash
python3 /path/to/zyvor-vytrix/cluster/coordinator.py \
  --config users.json --database cluster.sqlite --bind 0.0.0.0 \
  --tls-cert server.pem --tls-key server-key.pem --allow-origin https://console.example.com
```

Origins are exact. Private CAs work with the worker's `--ca`; TLS verification is never disabled. Keep the config, database and WAL files in the private directory on local storage.

## 2. Join each Mac

Sign in under **Mac cluster** as an administrator, enter a machine name and choose **Create pairing code**. On the new Mac:

```bash
mkdir -p ~/.vytrix-cluster && chmod 700 ~/.vytrix-cluster
python3 agent/cluster_worker.py --config ~/.vytrix-cluster/device.json --enroll https://cluster.example.com:9848
python3 agent/cluster_worker.py --config ~/.vytrix-cluster/device.json
```

Codes expire after five minutes and work once. The device credential is saved with mode 0600. The worker sends a snapshot every two seconds (`--interval`, 1–60). A machine is offline after 15 seconds without one. The dashboard keeps 60 recent samples per machine in tab memory; the coordinator stores each machine's latest snapshot and the audit log, not full history.

## API

All `/v1` calls except `login`, `enroll` and `heartbeat` need `Authorization: Bearer <session>`. Browser requests need an exact allowed Origin.

| Endpoint | Who | What |
|---|---|---|
| `POST /v1/login` | anyone | `{username, password}` → `{token, expires, actor, role}`; rate limited |
| `POST /v1/enroll` | a worker | `{code}` → `{id, token}` |
| `POST /v1/heartbeat` | a device | `{snapshot}` → `{ok: true}`; the snapshot is validated against the same bounds as the dashboard |
| `GET /v1/cluster` | viewer, admin | `{version, actor, role, nodes: [{id, name, seen, online, snapshot}]}` |
| `POST /v1/pairings` | admin | `{name}` → one-time pairing code |
| `POST /v1/revoke` | admin | `{node}`; the device can no longer send telemetry |
| `GET /v1/audit` | global admin | last 200 events |
| `POST /v1/logout` | any session | |

Anything else is 404, including any command endpoint.

## Failure behaviour

A dashboard that loses the coordinator keeps the last readings and shows an error. A worker that loses it prints a message and retries. Revoked devices get 401. Malformed snapshots get 400 and are never stored.

## Acceptance checks before relying on it

- Enroll two Macs; both show online within five seconds and go offline about 15 seconds after the worker stops.
- A viewer sees no pairing or revoke controls; revoking a Mac stops its readings.
- Sign out clears the token; `localStorage` never contains it.
- Confirm over HTTPS from a second machine with your CA.
