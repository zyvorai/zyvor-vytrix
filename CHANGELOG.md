# Changelog

## Unreleased

### Added
- **Fleet Pro layer** (opt-in, read-only): advanced silicon/AI telemetry, safe inventory, macOS per-process rates, agent health and verified updates, centralized history, tags/groups, roles, alerts, webhooks, SSO-proxy assertions, entitlements, Prometheus export, capacity forecasting, and backup tooling. New entry points: `agent/vytrix_fleet.py`, `agent/cluster_worker_fleet.py`, `cluster/fleet_coordinator.py`; the original collector, worker and coordinator are unchanged. See `docs/FLEET-PRO.md`. No command channel to agents was added.
- **Mac download:** the v0.3.0 release carries `Vytrix-0.3.0.dmg`, the native app signed with a Developer ID, not yet notarized (Apple silicon, macOS 26+), with its `.sha256`. README, the Pages site and `docs/RELEASE.md` link to it.

### Changed
- **License:** future versions are under the Business Source License 1.1 (non-production use free; production use needs a commercial license from Zyvor AI Labs Private Limited; each version converts to Apache-2.0 four years after its first public release). v0.3.0 and earlier remain Apache-2.0. Contribution terms in CONTRIBUTING.md updated accordingly.

## v0.3.0 — 2026-10-09

A macOS 27 window style, a native SwiftUI Mac app, an opt-in read-only Mac cluster view, and the Pages site with a live demo.

### Added
- **Mac cluster telemetry** (opt-in, read-only): `cluster/coordinator.py` (stdlib HTTP/TLS + SQLite, sessions, viewer/admin roles, single-use pairing, revocation, audit) and `agent/cluster_worker.py` push each Mac's snapshot to it; **Monitor → Mac cluster** shows per-machine CPU, memory, disk and network, applications and containers. Adapted from an externally contributed branch with its service-control half removed: no commands, services, `launchctl` or operator role, and tests that fail if a command channel appears.
- **Native Mac app** (`native/`, `scripts/build-native.sh`): SwiftUI and Swift Charts, no packages. Overview, Applications (sortable table with a process inspector), Containers and Projects, in the calm macOS 27 look. It launches the bundled collector on loopback with a random in-memory token, or connects to a remote one (HTTPS, or HTTP to localhost only), and stops the collector when it quits. `--demo` shows simulated telemetry; `scripts/shots-native.sh` writes `docs/ux/native-*.png`.
- **macOS 27 window style** (`data-theme="macos27"`): opaque surfaces, a flush 220pt sidebar, a 52pt toolbar and round toolbar buttons, with values sampled from real macOS 27.2 captures. Auto picks it when the host reports macOS 27 or newer; Settings → Window style has a `macOS 27` option next to `macOS 26` and `Linux`. `pnpm shots` writes `docs/ux/macos27-*.png`, and the landing-page gallery gains the style.
- **Site and live demo on GitHub Pages** (`https://zyvorai.github.io/zyvor-vytrix/`): a landing page with an interactive gallery of the real screenshots (window style x appearance x view), feature grid, quickstart with copy buttons and deploy notes; and `/demo/`, the real dashboard on its simulated telemetry, built static. `VYTRIX_BASE_PATH` (empty by default) sets Next's `basePath` for that build only. `scripts/build-site.sh` assembles `_site/`; `scripts/site-check.mjs` drives both under the real sub-path in CI.
- README with hero, demo GIF, screenshots (Liquid Glass and Adwaita, light and dark, 390px), architecture and read-only cards, collector flag table, and a documentation map. Every image is built-in simulated telemetry.
- Social images (`docs/social/`: hero, share card, `build.sh`), `public/og.jpg`, `apple-touch-icon.png`, and `openGraph`/`twitter` metadata.
- `pnpm shots` and `pnpm demo` regenerate the screenshots and the GIF (`scripts/shots.mjs`, `scripts/demo.mjs`).
- `docs/design/UX-CONTRACT.md`, `docs/README.md`, `CONTRIBUTING.md`, `AGENTS.md`, issue and pull request templates, CODEOWNERS, Dependabot.

### Changed
- Dependencies updated through Dependabot (React group, Next group, `@base-ui/react`, `@shadcn/react`).
- The collector release archive now includes the cluster worker and coordinator (`agent/cluster_worker.py`, `cluster/coordinator.py`) and `docs/CLUSTER.md`.
- `scripts/deploy-remote.sh` keeps its checkout in `~/.vytrix/app` instead of the shared `~/.deployments`, and reuses one SSH connection per run.
- Playwright and the screenshot scripts bind the dev server with `--host 127.0.0.1` (vinext 1.0.1 removed `--hostname`; an unbound server could listen on `::1` only and not answer `127.0.0.1`). `scripts/run-framework.mjs` adds its default dev port only when none is given.
- Homebrew stub points at the `zyvorai` organization.

### Fixed
- Connect dialog: the pre-filled collector endpoint is derived during render instead of by a state update in an effect (it failed `pnpm lint`).

### Removed
- Starter and sandbox leftovers that the monitor never used: the vendored "Sites" Vite plugin and its mock sign-in, connector preview, the D1/Drizzle scaffold, ChatGPT auth helper, `examples/d1`, the sandbox installer scripts, and the starter `public/*.svg`. `worker/index.ts` is the Worker entry. Removes `drizzle-orm`, `drizzle-kit`, `json-rpc-2.0` and `raw-body`.

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
