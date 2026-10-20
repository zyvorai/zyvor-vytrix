# AI code review (zyvor-vytrix)

_Generated 2026-10-20 by claude-opus-5-5 from a snapshot of tracked sources; verify before acting._

# Code review: zyvor-vytrix

## Summary

Vytrix is a read-only system activity monitor for macOS and Linux. It has four parts:

- a React 19 / Next / vinext dashboard, built for Cloudflare Workers and also published as a static GitHub Pages demo;
- a dependency-free Python collector (`agent/vytrix.py`, not shown in this excerpt) that serves snapshot and history APIs;
- an optional push-based Mac cluster and a "Fleet Pro" layer;
- a SwiftUI native Mac app with widgets and App Intents.

The project is unusually careful about documenting what it has and has not verified. The code has a few correctness and consistency gaps between the web, native and fleet paths.

## Bugs and correctness risks

**Missing divide-by-zero guards (web only).**
- `lib/alerts.ts` divides by `s.host.memoryTotal` and `s.diskTotal` with no guard.
- `lib/forecast.ts` (`fleetCapacity`) and `components/monitor/AppsTable.tsx` (`a.memory/memoryTotal*100`) do the same.
- If a snapshot reports a total of 0, you get `NaN` or `Infinity`. With `Infinity` an alert fires reading "Infinity% full", and forecasts become garbage.
- The native port, `native/App/Model/Alerts.swift`, does guard this (`memoryTotal > 0 ? … : 0`). The two clients therefore disagree on the same input.

**Forecast is a two-point slope.**
- In `lib/forecast.ts`, `forecast()` computes `trendPerHour` from only the first and last points, so one noisy endpoint dominates the ETA.
- `Date.parse` on a malformed timestamp yields `NaN`, which then flows into `hours` unchecked.
- A least-squares fit and a finite check would make this robust.

**History URLs drop the path prefix.**
- `lib/evidence.ts` builds history URLs with `collectorUrl` = `new URL('/v1/history?...', endpoint)`.
- An absolute path resolves against the origin. A collector behind a reverse proxy at a sub-path (e.g. `https://host/vytrix/v1/snapshot`) will have its history, evidence, anomalies and timeline requests sent to `https://host/v1/...`.
- The README explicitly suggests a TLS reverse proxy, so this deployment shape is expected.

**Connect field cannot be cleared.**
- In `components/monitor/ConnectDialog.tsx`, the input is `value={url||defaultUrl}`.
- When `defaultUrl` is set (an https dashboard), clearing the field sets `url=''`, which immediately redisplays `defaultUrl`.
- The user can edit the text but can never empty it.

**IPv6 loopback handled inconsistently.**
- `hooks/use-telemetry.ts` (`isAllowedCollectorUrl`) allows `localhost` and `127.0.0.1` but not `[::1]`.
- `lib/cluster.ts` and `agent/cluster_worker.py` do allow `::1`.
- Error text always says "Use a valid HTTPS snapshot endpoint", even for loopback-HTTP failures.

**Threshold ranges differ across clients.**

| Where | Allowed threshold |
| --- | --- |
| Web slider (`components/monitor/SettingsView.tsx`) | 10–100 |
| Web preference loader (`hooks/use-preferences.ts`) | 1–100 |
| Native slider (`native/App/Views/AlertsView.swift`) | 50–99 |

Also, at a threshold of 100 the critical level is `min(100,110)=100`, so every alert is critical.

**Backup can silently copy an empty database.**
- In `cluster/backup.py`, `sqlite3.connect(args.database)` creates the file if it is missing.
- A mistyped path therefore produces a valid, empty "backup" with exit code 0.
- Opening with `file:...?mode=ro` (and `uri=True`) would fail loudly instead.
- `dst` is also not closed if `src.backup` raises.

**Update helper has a race and a single backup slot.**
- In `scripts/vytrix-agent-update.py`, the candidate is checksum-verified and then re-read by `shutil.copy2`. The file can change between the two steps.
- Copy to the temporary file first, verify that copy, then `os.replace`.
- `.bak` is overwritten on every run, so a second bad update destroys the only rollback.

**Homebrew stub licence is wrong.** `packaging/homebrew/vytrix.rb` points at the v0.3.0 tarball but declares `license "BUSL-1.1"`. v0.3.0 is Apache-2.0 per `THIRD_PARTY.md` and `CHANGELOG.md`.

**Release archive contents (possibly intended).** `scripts/package-release.sh` omits all Fleet Pro files (`vytrix_fleet.py`, `advanced.py`, `fleet.py`, `fleet_coordinator.py`, `backup.py`) and `THIRD_PARTY.md`, which `NOTICE` and `THIRD_PARTY.md` say distributors must retain. Fleet may be source-only on purpose; either way, document it.

**Native token generation ignores failure.** In `native/App/Model/CollectorProcess.swift`, `randomToken()` discards the `SecRandomCopyBytes` status. On failure the token is 48 zeros.
- `freePort()` has a bind-then-release race before Python binds the port.
- `stop()` sends `terminate()` without waiting.

**Webhook created with an empty secret.** `components/monitor/FleetAdminPanel.tsx` calls `addWebhook(..., url, '')`.
- `SECURITY.md` promises webhooks "are signed"; with an empty HMAC key the signature is meaningless. I can't see whether the coordinator rejects this.
- The `useEffect` depends on the `connection` object. If the parent builds it inline on each render, the panel refetches every render (uncertain; the parent is not shown).

**Python version may not be 3.10-compatible.** `agent/vytrix_fleet.py` and `agent/cluster_worker_fleet.py` monkey-patch `vytrix.Collector` through `sys.modules`. This works but is fragile. `__init__` guesses attributes via `getattr(self, "proc", "/proc")`. CI only uses Python 3.12 and 3.13, so the "3.10+" claim is unverified.

## Security concerns

**CI permissions and action pinning.**
- `.github/workflows/ci.yml` has no top-level `permissions:` block, so it gets the default token scope.
- All actions are pinned by major tag (`@v7`, `@v6`), not by commit SHA.
- `pages.yml` runs on a **self-hosted** runner (`[self-hosted, mini]`) with `pages: write` and `id-token: write`. It installs pnpm unpinned via `npm install` and then runs repository scripts. It only triggers on `main`, but a compromised dependency or tag runs with those permissions on a persistent machine.

**Webhook signing.** The empty-secret path above undermines the "signed webhooks" claim.

**SSO replay.** The SSO assertion (`tests/test_fleet.py`, `cluster/fleet_core.py`) is HMAC(`user\ntimestamp`) with a 60-second window and no nonce or audience. A captured assertion can be replayed within that window. The tests do not check future-dated timestamps.

**Update manifest is not authenticated.** The update helper's checksum protects only against corruption. Anyone who can supply the manifest can supply a matching malicious candidate. Consider signing the manifest.

**Prometheus label escaping (unverified).** The output embeds node IDs in labels (`vytrix_cpu{node="n1"}`). I can't see whether quotes and backslashes are escaped; verify, since node names come from enrollment.

**Token exposure in the native app.**
- The collector token is passed via the environment (`CollectorProcess.swift`). That is readable by same-user processes, which is acceptable for a loopback collector but worth documenting.
- `VYTRIX_AGENT` lets the environment choose the script to execute if the bundled one is missing.

## Test and CI gaps

**CI does not match its own documentation.**
- `CONTRIBUTING.md` says "Run what CI runs: … `pnpm lint` …", but `ci.yml` never runs `pnpm lint`.
- `ci.yml` also runs node and Python tests directly rather than `pnpm test`, so the two can drift.

**Shellcheck covers a hand-picked subset.**
- `AGENTS.md` says `shellcheck scripts/*.sh`.
- CI skips `build-native.sh`, `shots-native.sh`, `test-native-logic.sh`, `package-release.sh`, `docs/social/build.sh` and `docs/ux/build-readme-cards.sh`.

**No Python 3.10 job.** The collector advertises "Python 3.10+, standard library only".

**No tests for the web edge cases.** Nothing covers zero totals in `lib/alerts.ts` or `lib/forecast.ts`, the sub-path `collectorUrl` case, or `isAllowedCollectorUrl`.

**Fleet Pro coverage is thin.** `tests/test_fleet.py` has five unit tests. Nothing covers:
- HTTP role enforcement in `fleet_coordinator.py`;
- webhook signing or empty-secret rejection;
- SSO replay or future timestamps;
- `cluster/backup.py`;
- `scripts/vytrix-agent-update.py` end to end.

**Native checks run only in `fleet-complete.yml`.**
- `scripts/test-native-logic.sh` and the widgets build run there; `test-native-ui.sh` is not in CI at all (this is documented).
- The plain `scripts/build-native.sh` path is not built in CI.

**Duplicated workflows.**
- The `fleet-complete.yml` web job duplicates `ci.yml` but pins Node `22.13.0`, while `ci.yml` uses `22`.
- Other e2e specs mock the collector with `page.route`. I can't see whether any e2e test exercises a real collector.

## Documentation gaps

**README.**
- The "Views" table and the UX contract's Layout section omit **Timeline** and **Mac cluster**, both of which exist in `components/monitor/nav.ts`.
- The "Collector flags" table omits `--exit-with-parent`, which was added in v0.7.0.
- A stray "## Fleet Pro" section sits after the centered footer.
- The Maturity row contains a lowercase "the v0.7.0" mid-sentence.

**UX contract.** `docs/design/UX-CONTRACT.md` "Laws" lists purple, amber and green chart colours and 26/18/12/8 radii. The macOS 27 style intentionally uses neutral greys and 14/10/7 radii (`native/App/Views/Theme.swift`, CHANGELOG v0.5.0). The contract should scope those laws per style.

**CHANGELOG.** v0.5.0 has two `### Added` headings.

**Commercial licence.**
- `docs/COMMERCIAL-LICENSE.md` still has placeholders for governing law and tax.
- Its pricing ("minimum US$0.99") differs from the README ("suggested ₹99 or US$1").
- It is linked as an operative licence despite listing open questions for counsel.

**"Writes nowhere else" claim.** `docs/ux/readme-read-only.html` says Vytrix "Writes anywhere but its own history file" under "never". The native app also writes `widget.json` and UserDefaults. Arguably that is the app rather than the collector, but the wording is absolute.

**Fleet packaging.** No document says whether Fleet Pro is distributed in release archives.

## Top 5 recommended actions (ordered)

1. **Harden CI and Pages.**
   - Add least-privilege `permissions:` to `ci.yml`.
   - Pin actions by SHA, especially on the self-hosted Pages runner.
   - Add `pnpm lint`, full `shellcheck scripts/*.sh` and a Python 3.10 matrix entry.
2. **Fix webhook and SSO trust gaps.**
   - Reject empty webhook secrets server-side, and have `F
