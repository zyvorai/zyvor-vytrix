// SPDX-License-Identifier: BUSL-1.1
// Records the README demo GIF from the simulated telemetry: overview, a process sheet, containers,
// switch to the Adwaita window style, then dark mode.
// Same command locally: pnpm demo [out.gif]    (needs ffmpeg; Playwright's Chromium or system Chrome)
// Frame capture is deterministic (hold(ms) records ms/125 frames, played at 8 fps), because Playwright's
// own video recorder needs a separate ffmpeg download.
import { execFileSync } from "node:child_process";
import { mkdtempSync, rmSync, statSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { goTo, launch, openApp, root, startDevServer } from "./shots-lib.mjs";

const out = path.resolve(process.argv[2] || path.join(root, "docs/ux/vytrix-demo.gif"));
const dir = mkdtempSync(path.join(tmpdir(), "vytrix-demo-"));
const FPS = 8;
let n = 0;

const server = await startDevServer();
const browser = await launch();
const { page, context } = await openApp(browser, server.base, { theme: "glass", appearance: "light", accent: "blue" }, { width: 1280, height: 800 });
const snap = () => page.screenshot({ path: path.join(dir, `f${String(n++).padStart(5, "0")}.png`) });
const hold = async (ms) => { for (let i = 0; i < Math.max(1, Math.round((ms / 1000) * FPS)); i++) await snap(); };

await hold(1800); // glass, light
await goTo(page, "Applications");
await hold(1400);
await page.locator(".view:not([hidden]) .data-table tbody tr").first().click();
await page.locator(".process-sheet").waitFor();
await hold(2200);
await page.keyboard.press("Escape");
await goTo(page, "Containers");
await hold(2000);
await goTo(page, "Settings");
await page.getByRole("radiogroup", { name: "Window style" }).getByRole("radio", { name: "Linux" }).click();
await hold(1600); // adwaita
await page.getByRole("radiogroup", { name: "Appearance" }).getByRole("radio", { name: "Dark" }).click();
await hold(1200);
await goTo(page, "Overview");
await hold(2200);

await context.close();
await browser.close();
server.stop();

const pal = path.join(dir, "pal.png");
const vf = "scale=960:-1:flags=lanczos";
const input = ["-framerate", String(FPS), "-i", path.join(dir, "f%05d.png")];
execFileSync("ffmpeg", ["-y", "-loglevel", "error", ...input, "-vf", `${vf},palettegen=stats_mode=diff`, pal]);
execFileSync("ffmpeg", ["-y", "-loglevel", "error", ...input, "-i", pal, "-lavfi", `${vf}[x];[x][1:v]paletteuse=dither=bayer:bayer_scale=4`, out]);
rmSync(dir, { recursive: true, force: true });
console.log(`wrote ${path.relative(process.cwd(), out)} (${(statSync(out).size / 1024).toFixed(0)} KiB, ${n} frames)`);
