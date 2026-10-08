## What and why

## Checklist

- [ ] `pnpm typecheck`, `pnpm lint`, `pnpm test`, `pnpm build` pass
- [ ] UI change: checked all window styles (glass, macos27, adwaita), light and dark, and 390px; ran `pnpm test:e2e`
- [ ] Nothing mutates the host; the collector still uses only the Python standard library
- [ ] No token, real process list, or real host data in code, tests, or images
- [ ] `CHANGELOG.md` updated under Unreleased
