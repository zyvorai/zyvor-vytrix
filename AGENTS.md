# AGENTS.md

Guidance for AI coding agents and humans working in this repository.

## What Vytrix is

A **read-only** system activity monitor for macOS and Linux. A React 19 / Next 16 / vinext dashboard (Cloudflare Worker output) with two window styles, macOS 26 Liquid Glass and Adwaita, plus a single-file, dependency-free Python collector (`agent/vytrix.py`) that serves an authenticated snapshot/history API.

## Hard boundaries

- **Read-only.** Vytrix never kills processes, changes settings, controls fans or volume, or writes to the host beyond its own SQLite history. Do not add a control that mutates the machine.
- **The collector stays dependency-free.** Python 3.10+ standard library only. No `pip install`, no vendored packages.
- **Tokens never leave the tab.** The bearer token lives in memory only: not in `localStorage`, not in URLs, not in logs, not in screenshots.
- **Never claim more than was measured.** App memory is RSS, GPU/sensors/per-app network are not collected. Copy and README say so.
- **Demo data in public images.** Screenshots, the hero, and the demo GIF come from the built-in simulated telemetry (`demoSnapshot`, host `zyvor-dev-01`). Never publish a capture of a real collector: it contains real process names, paths and ports.
- **Auth is the host's job.** The dashboard has no login. `SECURITY.md` explains what the collector token does and does not protect.

## Layout

| Path | What |
| --- | --- |
| `app/` | Single page (`page.tsx`), layout and metadata, `globals.css` (all design tokens) |
| `components/monitor/` | The dashboard: shell, sidebar, toolbar, views, dialogs |
| `components/ui/` | shadcn primitives |
| `hooks/`, `lib/` | Telemetry polling, preferences, schema (zod), grouping, alerts |
| `worker/index.ts` | Worker entry (hands requests to vinext) |
| `agent/vytrix.py` | The collector |
| `scripts/` | Installers (macOS/Linux), `deploy-remote.sh`, release packaging, screenshots and demo GIF |
| `site/`, `scripts/build-site.sh` | The Pages landing page, and the build that adds the static live demo (`VYTRIX_BASE_PATH`) |
| `tests/` | Telemetry tests, Python collector tests, Playwright e2e, recorded container output |
| `docs/` | API, testing, release status, UX contract, social images and screenshots (generated) |

## Validation before a PR

```bash
pnpm install --frozen-lockfile
pnpm typecheck && pnpm lint
pnpm test                      # telemetry schema + Python collector
pnpm build
pnpm test:e2e                  # WebKit, Chromium, mobile WebKit
shellcheck scripts/*.sh
```

| Command | CI job |
| --- | --- |
| typecheck, `pnpm test`, build, `pnpm test:e2e` | `ci.yml` / verify (Ubuntu and macOS) |
| `scripts/test-containers.sh docker|podman` | `ci.yml` / containers |
| `./scripts/build-site.sh && node scripts/site-check.mjs` | `ci.yml` / site |
| `shellcheck`, installer and deploy `--dry-run` | `ci.yml` / scripts |

When you change the UI, regenerate images with `pnpm shots` and `pnpm demo`, then look at them. See `docs/README.md`.
