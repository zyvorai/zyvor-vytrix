# Release status

## Unreleased (after v0.3.0)

- **License:** future versions are under the Business Source License 1.1; v0.3.0 and earlier stay Apache-2.0. Each version converts to Apache-2.0 four years after its first public release; set a concrete Change Date when you cut a release.
- **Fleet Pro** ([FLEET-PRO.md](FLEET-PRO.md)): richer telemetry, central history, roles (`auditor`, `editor`), alerts, webhooks, SSO-proxy endpoint, entitlements, Prometheus export, forecasting.
- Verified in CI on Ubuntu and macOS: typecheck, lint, production build, telemetry, cluster and forecast tests, 36 Python tests, Playwright end-to-end, shellcheck, container tests and the Pages site checks. The native app compiles with `scripts/build-native.sh`.
- Not verified: Fleet Pro across several Macs over HTTPS, webhook delivery, SSO behind a real identity proxy, Prometheus scraping, Apple notarization.

# v0.3.0 release status

## What is new

A macOS 27 window style, a native SwiftUI Mac app (`native/`), an opt-in read-only Mac cluster view (worker + coordinator), the GitHub Pages site with a live demo, and dependency updates. See [CHANGELOG.md](../CHANGELOG.md).

## Verified for v0.3.0

- TypeScript compilation, lint, production build, telemetry and cluster schema tests, 31 Python tests (collector and cluster), shellcheck, and the Pages site build and checks, on macOS 27.2 (Apple silicon, Python 3.14) and in CI on Ubuntu and macOS.
- Playwright end-to-end on Chromium and WebKit (desktop and mobile): style switching including macOS 27, preferences persistence, and the cluster view against a mocked coordinator. 22 passed, 2 expected skips.
- Native Mac app: built with `scripts/build-native.sh` and run on macOS 27.2 against live telemetry (it started the bundled collector, showed this Mac's data, and stopped the collector on quit) and against the simulated demo data.
- Cluster, on one Mac over loopback: enrolled a worker with a pairing code, read its live telemetry as a viewer, confirmed a viewer cannot create pairings, that no command endpoint exists, and that credential and database files are mode 0600.

## Not verified for v0.3.0

- The cluster across two or more Macs, and over HTTPS with a real certificate or private CA. The browser sign-in against a live coordinator is only covered by mocked tests.
- The native Mac app on macOS 26, and on Intel. It has no automated tests, is ad-hoc signed and not notarized, and is not part of the release archives; build it from source.
- Anything from the v0.2.0 verification that was not re-run: the native collector on macOS 26.7.1, real Docker and Podman containers, and `scripts/deploy-remote.sh` against an Ubuntu 24.04 host.
- Optional WebMCP registration in a supported browser.
- Homebrew formula (`packaging/homebrew/vytrix.rb` is a stub).

## Release artifacts

Each `v*` tag runs `.github/workflows/release.yml`, which tests, builds and attaches to the GitHub release:

- `zyvor-vytrix-dashboard-VERSION.tar.gz`: the built Worker (`dist/server`) and assets (`dist/client`). Deploy with `npx wrangler@4 deploy --config dist/server/wrangler.json`.
- `zyvor-vytrix-collector-VERSION.tar.gz`: `agent/vytrix.py`, the cluster worker and coordinator, the macOS and Linux installers, and the API and cluster references.
- `SHA256SUMS`.

Locally: `pnpm build && scripts/package-release.sh` writes the same files to `release/`.

## Deploying to a Linux host

```sh
./scripts/deploy-remote.sh HOST USER            # full deploy
./scripts/deploy-remote.sh HOST USER --quick    # sync + restart, no build
./scripts/deploy-remote.sh HOST USER --verify-only
./scripts/deploy-remote.sh HOST USER --dry-run  # prints the plan; no SSH
```

Requirements on the host: SSH access, passwordless `sudo` (for the systemd units), Python 3.10+, `curl`, `openssl`, `rsync`. Node 22.13+ is used if present; otherwise Node 22 is downloaded into `~/.vytrix/node`, with its SHA-256 checked.

| Path / unit | Purpose |
|---|---|
| `~/.vytrix/app` | Checkout (`VYTRIX_REMOTE_SUBDIR` overrides). Not `~/.deployments`: other projects there `rsync --delete` into the shared parent |
| `~/.vytrix/env` | `VYTRIX_TOKEN`, 0600, kept across deploys (`VYTRIX_TOKEN=… ./scripts/deploy-remote.sh` replaces it) |
| `~/.vytrix/tls.{crt,key}` | Self-signed certificate; regenerated only when the host changes |
| `vytrix-dashboard.service` | Dashboard on `127.0.0.1:8787` |
| `vytrix-collector.service` | Collector on `https://HOST:30847` (`VYTRIX_PORT` overrides); proxies the dashboard |

Open `https://HOST:30847`, accept the certificate, choose **Connect collector** (the endpoint is pre-filled) and paste the token. If `ufw` is active the port is opened. The collector runs as the SSH user, so it sees that user's Docker access and rootless Podman containers.

The hosted preview starts in demo mode with no collector connected. GPU, hardware sensors, fan control, audio, Bluetooth and process termination are not implemented. App memory is RSS, not unique physical memory. Persistent 30-day history is accessible through the collector API; the UI history is tab-local.
