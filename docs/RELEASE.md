# v0.2.0 release status

## Verified

- TypeScript compilation, production build, telemetry schema and alert tests.
- Python collector tests: real snapshot, bearer auth, CORS, history, retention, TLS, dashboard proxy, `/healthz`, Docker/Podman parsing from recorded output.
- Native collector on macOS 26.7.1 (Apple silicon) and Ubuntu 24.04 (kernel 6.8).
- Playwright end-to-end on WebKit, Chromium and mobile WebKit: theme switching, navigation, the Containers view, preferences persistence.
- Real containers: Podman on macOS (nginx with an `18080→80/tcp` mapping); Docker (16 containers) and rootless Podman on the Ubuntu host.
- `scripts/deploy-remote.sh` against an Ubuntu 24.04 host: the dashboard and API on `https://HOST:30847`.

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
| `~/.deployments/zyvor-vytrix` | Checkout (`VYTRIX_REMOTE_SUBDIR` overrides) |
| `~/.vytrix/env` | `VYTRIX_TOKEN`, 0600, kept across deploys (`VYTRIX_TOKEN=… ./scripts/deploy-remote.sh` replaces it) |
| `~/.vytrix/tls.{crt,key}` | Self-signed certificate; regenerated only when the host changes |
| `vytrix-dashboard.service` | Dashboard on `127.0.0.1:8787` |
| `vytrix-collector.service` | Collector on `https://HOST:30847` (`VYTRIX_PORT` overrides); proxies the dashboard |

Open `https://HOST:30847`, accept the certificate, choose **Connect collector** (the endpoint is pre-filled) and paste the token. If `ufw` is active the port is opened. The collector runs as the SSH user, so it sees that user's Docker access and rootless Podman containers.

## Not verified

- Optional WebMCP registration in a supported browser.
- Homebrew formula (`packaging/homebrew/vytrix.rb` is a stub).

The hosted preview starts in demo mode with no collector connected. GPU, hardware sensors, fan control, audio, Bluetooth and process termination are not implemented. App memory is RSS, not unique physical memory. Persistent 30-day history is accessible through the collector API; the UI history is tab-local.
