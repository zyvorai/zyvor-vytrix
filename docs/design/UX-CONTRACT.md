# Vytrix UX contract

Vytrix is a quiet instrument: it shows what a machine is doing and never changes it. The interface borrows the platform's own look, so it feels native on the machine it monitors. All tokens live in `app/globals.css`; components use tokens, not raw colors.

## Three window styles, one token set

| Style | `data-theme` | Looks like | Chosen |
| --- | --- | --- | --- |
| macOS 27 | `macos27` | Opaque, flat grouped surfaces with one accent colour (charts and icons are neutral greys, status colours only for state), no blur, roomier spacing, traffic lights, 220pt sidebar flush to the window edge with a hairline divider, 52pt toolbar with a hairline separator, round toolbar buttons. Values sampled from real macOS 27.2 captures (`zyvor-velora`); card and control radii and type sizes are not measured | Default when the monitored host reports macOS 27 or newer, or Settings → Window style |
| macOS 26 Liquid Glass | `glass` | Floating window, traffic lights, translucent sidebar capsule, 40px blur, light edge highlights | Default on macOS 26 and older, and in the browser demo, or Settings → Window style |
| Adwaita | `adwaita` | GNOME/libadwaita headerbar and flat cards, window controls on the right | Default on Linux, or Settings |

Light and dark are a `.dark` class (auto follows the OS). Eight accents via `data-accent`: blue, purple, pink, red, orange, yellow, green, graphite. Preferences persist in `localStorage["vytrix-preferences"]` and an inline script in `app/layout.tsx` applies them before first paint, so the wrong theme never flashes.

## Laws

1. **Color is data.** Chart colors are fixed per metric (`--chart-cpu` blue, `--chart-memory` purple, `--chart-disk` amber, `--chart-network` green, upload pink, containers cyan, apps orange). The accent is for intent: selection, focus, primary actions. Red/amber/green mean a threshold, not decoration.
2. **Read-only.** No control that mutates the host. Actions are limited to view, filter, sort, pause, export, import, connect.
3. **Say what the numbers are.** Demo data is labeled "simulated telemetry". App memory is RSS. Anything not collected (GPU, sensors, per-app network) is absent, not zero.
4. **Tokens stay in the tab.** The collector token is held in memory only.
5. **Concentric radii.** Window 26px → sidebar and panels 18px → controls 12px → small 8px.
6. **Respect the user.** `prefers-reduced-motion` and `prefers-reduced-transparency` are honored (plus a manual "Reduce transparency"); focus is always visible (`:focus-visible`, 3px accent ring); hit targets are comfortable on touch.

## Layout

Sidebar sections: **Monitor** (Overview, CPU, Memory, Disk, Network, Battery), **Workloads** (Applications, Containers, Projects), **System** (Alerts, Settings). Breakpoints at 1100px and 767px; on phones the sidebar becomes a sheet. No horizontal scroll at 390px.

## Author checklist

1. Both window styles, light and dark.
2. 390px: no horizontal scroll, nothing cut off.
3. Empty and error states say what happened and what to do next.
4. Keyboard: every control reachable, focus ring visible.
5. Public images come from demo data only. Run `pnpm shots` and open the files.
