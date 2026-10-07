# Changelog

## v0.2.0 — 2026-10-07

### Added
- macOS 26 Liquid Glass interface: sidebar, toolbar with traffic lights, glass cards, smooth charts, gauges and animated numbers; Adwaita-style variant chosen automatically on Linux.
- Light/dark/auto appearance, accent colours, reduced transparency and alert threshold in Settings, persisted locally.
- Docker and Podman monitoring: container state, CPU, memory against its limit, network I/O and published ports, via read-only CLI calls.
- Collector HTTPS (`--tls-cert`/`--tls-key`), dashboard proxy on the same origin (`--ui-upstream`) and an unauthenticated `/healthz`.
- `scripts/deploy-remote.sh HOST USER`: SSH + rsync deploy to a Linux host with systemd units and a self-signed certificate.
- `scripts/install-macos.sh` (launchd, token in the Keychain) and `scripts/install-linux.sh` (systemd user or hardened system unit).
- Playwright end-to-end tests on WebKit, Chromium and mobile WebKit; recorded-output tests for container parsing; `scripts/test-containers.sh`.
- CI on Ubuntu and macOS with real Docker and Podman checks.

### Fixed
- `docker ps` no longer computes container sizes (took over a minute on hosts with many stopped containers).
- A Docker engine with no containers is no longer reported as unreachable.

## v0.1.0

- Initial read-only monitor: CPU, memory, disk, network, battery, grouped apps and processes, listening ports, demo mode, JSON import/export.
- Python collector for Linux and macOS with bearer-token API, CORS allow-list and 30-day SQLite history.
