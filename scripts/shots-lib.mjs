// SPDX-License-Identifier: BUSL-1.1
// Shared by shots.mjs and demo.mjs: start the dev server on a free port and open the app with chosen preferences.
// Everything captured here is the built-in simulated telemetry (host zyvor-dev-01). Never point it at a real collector.
import { spawn } from "node:child_process";
import net from "node:net";
import { fileURLToPath } from "node:url";
import { chromium } from "@playwright/test";

export const root = fileURLToPath(new URL("../", import.meta.url));

export const freePort = () =>
  new Promise((resolve) => {
    const s = net.createServer().listen(0, "127.0.0.1", () => {
      const { port } = s.address();
      s.close(() => resolve(port));
    });
  });

export async function startDevServer() {
  const port = await freePort();
  const proc = spawn(process.execPath, ["scripts/run-framework.mjs", "dev", "--port", String(port), "--host", "127.0.0.1"], {
    cwd: root, stdio: "ignore", env: { ...process.env, CI: "1" },
  });
  const base = `http://127.0.0.1:${port}`;
  const stop = () => proc.kill();
  process.on("exit", stop); // never leave a dev server behind, even when a script fails
  for (let i = 0; i < 240; i++) {
    // A per-request timeout: the first request compiles the app and must not block the loop forever.
    try { if ((await fetch(base, { signal: AbortSignal.timeout(5000) })).ok) return { base, stop }; } catch { /* not up yet */ }
    await new Promise((r) => setTimeout(r, 500));
  }
  stop();
  throw new Error("dev server did not start");
}

export async function launch() {
  // Playwright's bundled Chromium; fall back to the system Chrome if it is not installed.
  return chromium.launch().catch(() => chromium.launch({ channel: "chrome" }));
}

/** New page with stored preferences applied before first paint. prefs: { theme: glass|macos27|adwaita, appearance: light|dark, accent } */
export async function openApp(browser, base, prefs, viewport, extra = {}) {
  const context = await browser.newContext({ viewport, deviceScaleFactor: 1, reducedMotion: "reduce", ...extra });
  const page = await context.newPage();
  const problems = [];
  page.on("pageerror", (e) => problems.push(`pageerror: ${e.message}`));
  page.on("console", (m) => { if (m.type() === "error") problems.push(`console: ${m.text()}`); });
  await page.addInitScript((p) => localStorage.setItem("vytrix-preferences", JSON.stringify(p)), prefs);
  await page.goto(base);
  await page.locator("html[data-transparency]").waitFor({ state: "attached" });
  await page.locator(".metric-tile").first().waitFor();
  return { page, context, problems };
}

export const goTo = async (page, label, mobile = false) => {
  if (mobile) await page.getByRole("button", { name: "Toggle sidebar" }).click();
  await page.locator(".nav-item:visible").filter({ hasText: label }).first().click();
  await page.waitForTimeout(600);
};
