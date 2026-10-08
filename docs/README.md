# Docs

| File | What |
| --- | --- |
| `API.md` | Collector endpoints, flags, metric definitions, containers, storage |
| `TESTING.md` | Test matrix for macOS and Linux, installers, remote verification |
| `RELEASE.md` | Verified and not-verified status, release artifacts, deploy layout |
| `design/UX-CONTRACT.md` | Window styles, tokens, laws, checklist |
| `social/` | Hero (`vytrix-hero-dark`), share card, and their HTML sources |
| `ux/` | Screenshots (`<style>-<mode>-<view>.png`), README cards, demo GIF |

## Regenerating images

Everything image-like in `social/` and `ux/` is generated. The HTML and scripts are the source of truth. All of it uses the **built-in simulated telemetry**: never publish a capture of a real collector.

```bash
pnpm shots                         # docs/ux/*.png: glass and adwaita, light and dark, 390px (Playwright)
pnpm demo                          # docs/ux/vytrix-demo.gif (needs ffmpeg)
./docs/social/build.sh             # hero, share card, og image (macOS: Chrome + sips)
./docs/ux/build-readme-cards.sh    # README cards
```

`pnpm shots` and `pnpm demo` use Playwright's Chromium (`pnpm exec playwright install chromium`) and fall back to system Chrome.

GitHub's **social preview** is uploaded by hand: Settings → General → Social preview → `docs/social/vytrix-hero-dark.jpg`.
