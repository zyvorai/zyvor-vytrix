# Contributing

1. **Open an issue first** for anything beyond a typo, so we agree on the shape.
2. **Respect the boundaries** in [AGENTS.md](AGENTS.md): read-only, dependency-free collector, tokens stay in the tab.
3. **Add tests.** Schema and alert logic go in `tests/telemetry.mjs`; collector behavior in `tests/test_agent.py` or `tests/test_containers.py` (record real CLI output into `tests/fixtures/` rather than mocking it); UI behavior in `tests/e2e/dashboard.spec.ts`.
4. **Run what CI runs:**
   ```bash
   pnpm install --frozen-lockfile
   pnpm typecheck && pnpm lint && pnpm test && pnpm build && pnpm test:e2e
   ```
   Node ≥ 22.13, pnpm 11.25 (`npx pnpm@11.25.0 …` works without installing it), Python 3.10+.
5. **UI changes** follow [docs/design/UX-CONTRACT.md](docs/design/UX-CONTRACT.md): tokens only, both window styles, light and dark, 390px with no horizontal scroll. Run `pnpm shots` and look at the result.
6. Add a line under `## Unreleased` in [CHANGELOG.md](CHANGELOG.md).

By contributing you agree your work is licensed under Apache-2.0.
