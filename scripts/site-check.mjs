// SPDX-License-Identifier: Apache-2.0
// Browser check of the built Pages site, served under the real /zyvor-vytrix/ sub-path (as GitHub Pages does).
// Same command locally: ./scripts/build-site.sh && node scripts/site-check.mjs [--shots dir]
// --base https://zyvorai.github.io/zyvor-vytrix/ checks the live site instead of serving _site locally.
import fs from "node:fs";
import http from "node:http";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { chromium } from "@playwright/test";

const root = fileURLToPath(new URL("../", import.meta.url));
const arg = (k, d) => { const i = process.argv.indexOf(k); return i > 0 ? process.argv[i + 1] : d; };
const shotsDir = arg("--shots", "");
const siteDir = path.resolve(arg("--dir", path.join(root, "_site")));
let base = arg("--base", "");
const PREFIX = "/zyvor-vytrix/";
const MIME = { ".html": "text/html", ".css": "text/css", ".js": "text/javascript", ".json": "application/json", ".svg": "image/svg+xml", ".png": "image/png", ".jpg": "image/jpeg", ".gif": "image/gif", ".txt": "text/plain", ".xml": "application/xml", ".woff2": "font/woff2" };

const failures = [];
const check = (ok, msg) => { console.log(`${ok ? "ok  " : "FAIL"} ${msg}`); if (!ok) failures.push(msg); };

function serve() {
  return new Promise((resolve) => {
    const srv = http.createServer((req, res) => {
      let p = decodeURIComponent(req.url.split("?")[0]);
      if (!p.startsWith(PREFIX)) { res.writeHead(404); return res.end("outside the project path"); }
      p = p.slice(PREFIX.length) || "index.html";
      if (p.endsWith("/")) p += "index.html";
      let file = path.join(siteDir, p);
      if (!file.startsWith(siteDir) || !fs.existsSync(file) || fs.statSync(file).isDirectory()) { file = path.join(siteDir, "404.html"); res.statusCode = 404; }
      res.setHeader("Content-Type", MIME[path.extname(file)] || "application/octet-stream");
      res.end(fs.readFileSync(file));
    }).listen(0, "127.0.0.1", () => resolve({ srv, url: `http://127.0.0.1:${srv.address().port}${PREFIX}` }));
  });
}

let srv;
if (!base) { const s = await serve(); srv = s.srv; base = s.url; }
if (!base.endsWith("/")) base += "/";
const browser = await chromium.launch().catch(() => chromium.launch({ channel: "chrome" }));
const shot = async (page, name) => { if (shotsDir) { fs.mkdirSync(shotsDir, { recursive: true }); await page.screenshot({ path: path.join(shotsDir, name + ".png") }); } };

async function open(scheme, viewport, tag) {
  const ctx = await browser.newContext({ colorScheme: scheme, viewport, permissions: ["clipboard-read", "clipboard-write"], reducedMotion: "reduce" });
  const page = await ctx.newPage();
  const bad = [];
  page.on("pageerror", (e) => bad.push(`${tag} pageerror: ${e.message}`));
  page.on("console", (m) => { if (m.type() === "error" && !m.text().startsWith("Failed to load resource")) bad.push(`${tag} console: ${m.text()}`); });
  page.on("response", (r) => { if (r.status() >= 400 && !/\/404\.html$/.test(r.url()) && !r.url().includes("no-such-page")) bad.push(`${tag} ${r.status()} ${r.url()}`); });
  return { ctx, page, bad };
}
const scrollAll = (page) => page.evaluate(async () => { for (let y = 0; y < document.body.scrollHeight; y += 700) { window.scrollTo(0, y); await new Promise((r) => setTimeout(r, 60)); } window.scrollTo(0, 0); });
const noSideScroll = (page) => page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth);

// ---------- landing, desktop, light
let { ctx, page, bad } = await open("light", { width: 1440, height: 900 }, "landing");
await page.goto(base);
check((await page.title()).includes("Vytrix"), "landing: title");
check((await page.locator("h1").innerText()).includes("really doing"), "landing: h1");
check(await page.getAttribute("html", "data-theme") === "light", "landing: follows OS light");
check((await page.locator("#shot").getAttribute("src")).includes("glass-light-overview"), "gallery: starts on the glass overview matching the page theme");
await shot(page, "site-landing-light");
// gallery: every control changes the real screenshot, by click and by keyboard
await page.click('[aria-label="Window style"] [data-value="adwaita"]');
await page.waitForFunction(() => document.getElementById("shot").src.includes("adwaita-light-overview"));
check((await page.locator("#shot-cap").innerText()) === "Adwaita · light · Overview", "gallery: caption describes the selection");
await page.click('[aria-label="View"] [data-value="containers"]');
await page.waitForFunction(() => document.getElementById("shot").src.includes("adwaita-light-containers"));
check(await page.locator("#shot").evaluate((i) => i.complete && i.naturalWidth > 0), "gallery: the swapped image loads");
await page.focus('[aria-label="View"] [aria-checked="true"]');
await page.keyboard.press("ArrowRight");
await page.waitForFunction(() => document.getElementById("shot").src.includes("adwaita-light-projects"));
check(true, "gallery: ArrowRight moves to the next view");
await page.keyboard.press("End");
await page.waitForFunction(() => document.getElementById("shot").src.includes("adwaita-light-alerts"));
check(true, "gallery: End goes to the last view");
// the page theme drives the gallery
await page.click("#theme");
check(await page.getAttribute("html", "data-theme") === "dark", "landing: theme toggle -> dark");
await page.waitForFunction(() => document.getElementById("shot").src.includes("adwaita-dark-alerts"));
check(await page.locator('[aria-label="Appearance"] [aria-checked="true"]').innerText() === "Dark", "gallery: follows the page theme");
await page.reload();
check(await page.getAttribute("html", "data-theme") === "dark", "landing: theme persists across reload");
await shot(page, "site-landing-dark");
// every one of the 60 screenshot combinations exists
const combos = [];
for (const s of ["glass", "macos27", "adwaita"]) for (const m of ["light", "dark"]) for (const v of ["overview", "applications", "containers", "projects", "alerts"]) combos.push(`ux/${s}-${m}-${v}.png`);
const missing = [];
for (const c of combos) { const r = await page.request.get(base + c); if (!r.ok()) missing.push(c); }
check(missing.length === 0, `gallery: all ${combos.length} screenshots are served${missing.length ? " (missing: " + missing.join(", ") + ")" : ""}`);
// images, copy, spy
await scrollAll(page);
const brokenImgs = () => page.evaluate(() => [...document.images].filter((i) => i.offsetParent !== null && (!i.complete || i.naturalWidth === 0)).map((i) => i.getAttribute("src")));
let broken = await brokenImgs();
for (let i = 0; broken.length && i < 40; i++) { await page.waitForTimeout(250); broken = await brokenImgs(); }
check(broken.length === 0, `landing: every visible image loads${broken.length ? " (broken: " + broken.join(", ") + ")" : ""}`);
await page.locator("#quickstart .copy").first().click();
await page.waitForSelector("#toast:not([hidden])");
check((await page.locator("#toast").innerText()).includes("Copied"), "quickstart: copy reports success");
check((await page.evaluate(() => navigator.clipboard.readText())).includes("pnpm@11.25.0 install"), "quickstart: clipboard holds the commands");
await page.locator("#deploy").scrollIntoViewIfNeeded();
await page.waitForTimeout(400);
check(await page.locator('#sections a[href="#deploy"]').getAttribute("aria-current") === "true", "nav: scroll-spy marks the section in view");
check(await noSideScroll(page), "landing: no horizontal scroll (desktop)");
const meta = await page.evaluate(() => ({ og: document.querySelector('meta[property="og:image"]')?.content, canonical: document.querySelector("link[rel=canonical]")?.href, ld: !!document.querySelector('script[type="application/ld+json"]') }));
check(!!meta.og && meta.og.endsWith("/social/vytrix-hero-dark.jpg") && !!meta.canonical && meta.ld, "landing: og:image, canonical, JSON-LD");
for (const f of ["robots.txt", "sitemap.xml", "favicon.svg", "apple-touch-icon.png", "social/vytrix-hero-dark.jpg"]) check((await page.request.get(base + f)).ok(), `landing: ${f} is served`);
const r404 = await page.request.get(base + "no-such-page");
check(r404.status() === 404 && (await r404.text()).includes("Nothing running here"), "404: unknown path serves the 404 page");
bad.forEach((b) => check(false, b));
await ctx.close();

// ---------- landing, phone
({ ctx, page, bad } = await open("dark", { width: 390, height: 844 }, "landing-mobile"));
await page.goto(base);
check(await noSideScroll(page), "mobile: no horizontal scroll");
check(await page.locator('.seg.wide').evaluate((el) => el.scrollWidth >= el.clientWidth), "mobile: the view picker scrolls instead of overflowing the page");
await shot(page, "site-landing-mobile");
bad.forEach((b) => check(false, b));
await ctx.close();

// ---------- the live demo: the real dashboard, built static
({ ctx, page, bad } = await open("light", { width: 1440, height: 900 }, "demo"));
await page.goto(base + "demo/");
await page.locator("html[data-transparency]").waitFor({ state: "attached" });
check(await page.locator(".metric-tile").count() === 6, "demo: overview hydrates with 6 metric tiles");
check(await page.getByText("simulated telemetry").isVisible(), "demo: says it is simulated telemetry");
await shot(page, "site-demo-overview");
const nav = (label) => page.locator(".window .nav-item").filter({ hasText: label }).click();
await nav("Applications");
await page.waitForSelector(".data-table tbody tr");
check(await page.locator(".data-table tbody tr").count() >= 5, "demo: applications table renders");
await page.locator(".data-table tbody tr").first().click();
await page.locator(".process-sheet").waitFor();
check(await page.locator(".process-sheet tbody tr").first().isVisible(), "demo: process sheet opens");
await page.keyboard.press("Escape");
await nav("Containers");
check(await page.locator(".container-card").count() === 5, "demo: containers view shows Docker and Podman containers");
await nav("Settings");
await page.getByRole("radiogroup", { name: "Window style" }).getByRole("radio", { name: "Linux" }).click();
check(await page.getAttribute("html", "data-theme") === "adwaita", "demo: window style switches to Adwaita");
await page.getByRole("radiogroup", { name: "Appearance" }).getByRole("radio", { name: "Dark" }).click();
check(await page.locator("html").evaluate((h) => h.classList.contains("dark")), "demo: appearance switches to dark");
await shot(page, "site-demo-adwaita-dark");
await page.reload();
await page.locator("html[data-transparency]").waitFor({ state: "attached" });
check(await page.getAttribute("html", "data-theme") === "adwaita", "demo: preferences persist across reload");
const icons = await page.evaluate(() => [...document.querySelectorAll('link[rel~="icon"],link[rel="apple-touch-icon"]')].map((l) => l.getAttribute("href")));
check(icons.length > 0 && icons.every((h) => h.startsWith("/zyvor-vytrix/demo/") || h.startsWith("http")), "demo: icon URLs carry the base path");
check(await page.locator('meta[name="robots"][content="noindex"]').count() === 1, "demo: noindex");
bad.forEach((b) => check(false, b));
await ctx.close();

({ ctx, page, bad } = await open("dark", { width: 390, height: 844 }, "demo-mobile"));
await page.goto(base + "demo/");
await page.locator("html[data-transparency]").waitFor({ state: "attached" });
check(await noSideScroll(page), "demo mobile: no horizontal scroll");
bad.forEach((b) => check(false, b));
await ctx.close();

await browser.close();
if (srv) srv.close();
console.log(failures.length ? `\n${failures.length} failure(s)` : "\nall site checks passed");
process.exit(failures.length ? 1 : 0);
