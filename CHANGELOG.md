# Changelog

## Unreleased

## v0.5.0 — 2026-10-13

Anomaly bands, evidence, an incident timeline and a change recorder, on the collector, the web dashboard and the native app.

### Added
- **Native app: Timeline pane** (System). The same `/v1/timeline` and `/v1/changes` as the web view: events, the fingerprint, why the window differs from the one before, and apps, ports and containers that appeared or went away, over 5, 15 or 30 minutes. Needs a collector; demo data and imported snapshots say so. The collector contract test now decodes real timeline and changes output.
- **Web dashboard: Timeline view** (System). Shows `/v1/timeline` (alert transitions at your threshold, anomaly windows, container changes, the 12-hex fingerprint, and why the window differs from the one before) and `/v1/changes` (apps started or stopped, ports opened or closed, containers). Needs a live collector; demo data and imports say so.
- **Collector: change recorder** (`GET /v1/changes?since&to`). What appeared and went away between the first and last stored sample of a window, and what came and went inside it. Read-only, from stored history. See `docs/API.md`.
- **Collector: incident timeline** (`GET /v1/timeline?from&to&threshold`). Merges alert transitions (with hysteresis), container appearance, disappearance and state changes, and anomaly windows into one ordered list, with a 12-hex fingerprint of the pattern (times excluded) and a `whyChanged` comparison with the window before. Deterministic, no model. See `docs/API.md`.
- **Web dashboard: anomaly bands and evidence.** Connected to a live collector, the CPU, Memory, Disk and Network views shade the ranges `/v1/anomalies` flags, say when the baseline is still warming up, and offer "What was busy in this range?" (or drag across the chart) for CPU, Memory and Network. The evidence sheet lists host mean and peak against the range before, top apps with their change, containers and the anomalies inside it. Demo data and imported snapshots have no history endpoints, so they show none of it. The token stays in tab memory.
- **Native app: anomaly ribbon and evidence.** On the CPU, Memory, Disk and Network panes, anomalous ranges from `/v1/anomalies` are shaded on the history chart, with a caption that says when the band is still warming up. Drag across the chart and choose Show Evidence to see what was busy in that range against the range before it: host stats, top apps with their change, containers and the anomalies inside it. Needs a collector (this Mac or remote); demo data and imported snapshots have no history endpoints, so they show neither. `scripts/test-native-logic.sh` now decodes real collector output, so a schema drift fails the test.
- **Collector: evidence** (`GET /v1/evidence?from&to&metric`). For a time window, returns the top apps by CPU, memory or network with their change from the preceding same-length window, the busiest containers, host stats and the anomaly windows inside it. Absent per-app network is reported as absent, not zero. See `docs/API.md`.
- **Collector: anomaly bands** (`GET /v1/anomalies`). Replays stored history through an exponentially weighted band per metric (CPU, memory, disk, network) and returns per-sample scores, anomaly windows and rates. Warm-up samples and unreported metrics are `null`, not zero. Computed on request, so no schema or database change. See `docs/API.md`.
- **Native app: Settings.** Appearance (Auto, Light, Dark), the eight dashboard accents, alert threshold and notifications, snapshot Import and Export (JSON in the telemetry schema, the same files as the web dashboard), and the data source (This Mac or demo data). An imported snapshot is shown as a single static sample and stops polling. Preferences are stored in UserDefaults; the token is never stored. The native window follows the system look, so there is no window-style switch.
- **Native app: resource panes.** CPU, Memory, Disk, Network and Battery, each with the current reading, a few derived stats (average, peak, capacity), a 1m/5m/1h history chart, and for CPU and Memory the busiest applications (select one to open its process inspector). Battery shows "No battery reading" on hosts without one. The sidebar is grouped Monitor, Workloads and System like the web dashboard.

### Changed
- **Native app: macOS 27 look.** Chart colours are fixed per metric from the `macos27` tokens (CPU blue, everything else neutral grey) instead of following the accent, so changing the accent in Settings no longer recolours the charts; the top-consumer meters are neutral. Panels use the 14/10/7 radii of the web `macos27` style. `native/App/Views/Theme.swift` holds the tokens.
- Native sidebar: the Alerts count is drawn next to its title instead of with `.badge`, which hid the title from accessibility. `scripts/test-native-ui.sh` finds sidebar rows by label and checks all ten.
- `scripts/shots-native.sh` also captures CPU, Memory, Network, Alerts and Settings (18 images).

## v0.4.1 — 2026-10-13

Packaging fix: v0.4.0's release job built the dashboard and collector archives but not the Mac DMG and pkg.

### Fixed
- `scripts/package-mac.sh` expanded an empty signing array under `set -u`, which fails on the macOS runner's bash 3.2, so the unsigned path never wrote the DMG or pkg. The v0.4.0 release has no Mac downloads; use v0.4.1. There are no app changes from v0.4.0.

## v0.4.0 — 2026-10-13

The native Mac app gains a menu bar item and alerts with notifications; Fleet Pro and the BSL license land.

### Added
- **Native app: menu bar item.** Live CPU in the menu bar, and a popover with host totals, the alert count and the five busiest apps, plus Open Vytrix and Quit. Closing the window no longer quits: Vytrix keeps running (and keeps its bundled collector) until you Quit; a Dock click or Open Vytrix brings the window back.
- **Native app: Alerts.** A fifth sidebar section with a count badge, a threshold slider (default 80%, saved) and per-alert Dismiss. Rules are a port of `lib/alerts.ts`: CPU, memory, disk and container memory limit, critical from threshold + 10. Optional local notifications fire once per alert, again on escalation, and re-arm after three quiet samples; they never fire for demo data and have no actions.
- **Native tests.** `scripts/test-native-logic.sh` (alert rules and notification hysteresis, compiled against the real model files) is the first Swift test. `scripts/test-native-ui.sh` now also checks that closing the window keeps the app running, that reopening restores it, and that Quit stops the collector.
- **Mac packaging.** `scripts/package-mac.sh` builds `Vytrix-VERSION.dmg` and `.pkg` with checksums, and signs and notarizes when Developer ID identities and a notarytool profile are provided; the release workflow's `mac` job runs it.
- **Fleet Pro layer** (opt-in, read-only): advanced silicon/AI telemetry, safe inventory, macOS per-process rates, agent health and verified updates, centralized history, tags/groups, roles, alerts, webhooks, SSO-proxy assertions, entitlements, Prometheus export, capacity forecasting, and backup tooling. New entry points: `agent/vytrix_fleet.py`, `agent/cluster_worker_fleet.py`, `cluster/fleet_coordinator.py`; the original collector, worker and coordinator are unchanged. See `docs/FLEET-PRO.md`. No command channel to agents was added.
- **Mac download:** the v0.3.0 release carries `Vytrix-0.3.0.dmg`, the native app signed with a Developer ID, not yet notarized (Apple silicon, macOS 26+), with its `.sha256`.

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
