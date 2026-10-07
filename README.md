# Zyvor Vytrix

[![verify](https://github.com/zyvorai/zyvor-vytrix/actions/workflows/ci.yml/badge.svg)](https://github.com/zyvorai/zyvor-vytrix/actions/workflows/ci.yml)

A system activity monitor with a macOS 26 Liquid Glass interface (and an Adwaita-style variant on Linux). Original Vytrix code is licensed under **Apache-2.0**.

## Included

- CPU, memory, disk, network, battery and application summary tiles.
- Grouped process inspection, search, CPU/memory sorting, project folders and listening ports.
- Captured resource history, pause/resume, threshold alerts, light/dark appearance, accent colours and reduced transparency.
- Docker and Podman containers: state, CPU, memory against its limit, network I/O and published ports (read-only CLI calls).
- Real Linux/macOS collector in Python, without Python dependencies.
- Authenticated read-only snapshot/history API, exact CORS origin allow-list and 30-day SQLite retention.
- JSON import/export: use real host data without exposing a collector to the browser.

The deployed preview starts with **clearly labeled simulated telemetry**. A webpage cannot read local processes. Connect a collector or import its snapshot for real readings.

## Web app

Node >=22.13; pnpm is used in this checkout. The lockfile is included.

```sh
npm install -g pnpm@11.25.0
pnpm install --frozen-lockfile
pnpm dev
```

For a production bundle:

```sh
pnpm build
pnpm start
```

This starter uses React 19, TypeScript and Vinext (Next-compatible) with Cloudflare Worker output. `pnpm start` serves the built Worker locally through Wrangler on loopback. Host `dist/server` and `dist/client` on a supported Worker host; the public hosted preview is optional. The collector is a separate host process and does not run inside a cloud Worker.

## Collect a real snapshot

Python 3.10+ on Linux or macOS:

```sh
python3 agent/vytrix.py --once > snapshot.json
```

In the dashboard choose **Connect collector → Import collector snapshot**, or **Settings → Import**.

## Live telemetry

Generate and retain a token outside source control:

```sh
export VYTRIX_TOKEN="$(python3 -c 'import secrets; print(secrets.token_urlsafe(32))')"
python3 agent/vytrix.py --allow-origin https://YOUR-DASHBOARD-ORIGIN
```

The collector binds `127.0.0.1:9847` by default. For browser access from another machine, serve HTTPS with `--tls-cert`/`--tls-key` (or put it behind a TLS reverse proxy that passes the Authorization header). `--ui-upstream http://127.0.0.1:8787` also serves the dashboard on the same origin, so one HTTPS port is enough. Use your actual dashboard origin, with no trailing slash. TLS and origin access must be configured before a hosted dashboard can connect. Browsers may also prompt for local-network access.

Enter `https://YOUR-COLLECTOR/v1/snapshot` and the token in **Connect collector**. The dashboard polls every two seconds. Tokens remain in tab memory; they are not stored in localStorage or sent to the hosted app server. Disconnect using **Settings → Use demo data**.

For local development, allow the actual local dashboard origin with `--allow-origin http://localhost:3000` (adjust to the dev server's reported port). The UI permits HTTP collector URLs only for localhost and 127.0.0.1.

## Install as a service

```sh
scripts/install-macos.sh --allow-origin http://localhost:5173     # launchd agent, token in the login Keychain
scripts/install-linux.sh --allow-origin http://localhost:5173     # systemd user unit (--system for a hardened system unit)
```

Both accept `--dry-run`, `--port` and `--no-containers`.

## Deploy to a Linux server

```sh
./scripts/deploy-remote.sh 203.0.113.10 deploy      # HOST USER, or user@host
```

Syncs the checkout over SSH to `~/.deployments/zyvor-vytrix`, builds it there (with a private Node 22 if the system Node is older), and installs two systemd units: the dashboard on `127.0.0.1:8787` and the collector on `https://HOST:30847`, which serves the API and proxies the dashboard. The token is kept in `~/.vytrix/env` and printed at the end; the certificate is self-signed. `--quick` skips the build, `--verify-only` checks the running deployment, `--dry-run` prints the plan. Details in [RELEASE.md](docs/RELEASE.md#deploying-to-a-linux-host).

## Verification

```sh
pnpm typecheck
pnpm test          # telemetry schema tests + Python collector tests
pnpm test:e2e      # Playwright, WebKit and Chromium
pnpm build
```

See the [changelog](CHANGELOG.md), [testing on macOS and Linux](docs/TESTING.md), [API and telemetry definitions](docs/API.md), [release status](docs/RELEASE.md), [security](SECURITY.md), and [third-party notices](THIRD_PARTY.md).

## Scope

This is an initial read-only release. It does not kill processes, control fans or volume, inspect Bluetooth devices, measure per-app network/disk I/O, or collect GPU metrics. Collection is exercised on macOS 26 and on Ubuntu 24.04.

History in the dashboard contains samples captured during the open tab (at most 1,800 samples). The collector separately retains up to 30 days in SQLite and provides authenticated history retrieval; the dashboard does not yet browse that persisted 30-day history. Process RSS sums can double-count shared memory; app memory is summed RSS, not unique physical memory. App grouping is based on executable names and macOS `.app` bundle paths; developer project discovery is best-effort on Linux and unavailable on macOS in this release.
