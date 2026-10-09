// SPDX-License-Identifier: BUSL-1.1
// Screenshots of every main view in both window styles, light and dark, plus 390px mobile. Demo data only.
// Same command locally: pnpm shots [outdir]     (default docs/ux; needs Playwright's Chromium or system Chrome)
import { mkdirSync } from "node:fs";
import path from "node:path";
import { devices } from "@playwright/test";
import { goTo, launch, openApp, root, startDevServer } from "./shots-lib.mjs";

const out = path.resolve(process.argv[2] || path.join(root, "docs/ux"));
mkdirSync(out, { recursive: true });

const views = ["Overview", "Applications", "Containers", "Projects", "Alerts", "Mac cluster"];
const styles = ["glass", "macos27", "adwaita"];
const modes = ["light", "dark"];

const server = await startDevServer();
const browser = await launch();
const failures = [];
let count = 0;

const noSideScroll = (page) => page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth);

for (const theme of styles) for (const appearance of modes) {
  const { page, context, problems } = await openApp(browser, server.base, { theme, appearance, accent: "blue" }, { width: 1440, height: 900 });
  for (const view of views) {
    if (view !== "Overview") await goTo(page, view);
    await page.mouse.move(2, 2);
    await page.screenshot({ path: path.join(out, `${theme}-${appearance}-${view.toLowerCase().replaceAll(" ", "-")}.png`) });
    count++;
    if (!(await noSideScroll(page))) failures.push(`${theme}/${appearance}/${view}: horizontal scroll`);
  }
  failures.push(...problems.map((p) => `${theme}/${appearance}: ${p}`));
  await context.close();
}

// Mobile: the sidebar is a sheet, so navigate through the toggle.
for (const appearance of modes) {
  const { page, context, problems } = await openApp(browser, server.base, { theme: "glass", appearance, accent: "blue" }, { width: 390, height: 844 },
    { isMobile: true, hasTouch: true, userAgent: devices["iPhone 15"].userAgent });
  for (const view of ["Overview", "Containers"]) {
    if (view !== "Overview") await goTo(page, view, true);
    await page.screenshot({ path: path.join(out, `mobile-${appearance}-${view.toLowerCase()}.png`) });
    count++;
    if (!(await noSideScroll(page))) failures.push(`mobile/${appearance}/${view}: horizontal scroll`);
  }
  failures.push(...problems.map((p) => `mobile/${appearance}: ${p}`));
  await context.close();
}

await browser.close();
server.stop();
console.log(`wrote ${count} screenshots to ${path.relative(process.cwd(), out) || "."}`);
if (failures.length) { console.error(failures.join("\n")); process.exit(1); }
