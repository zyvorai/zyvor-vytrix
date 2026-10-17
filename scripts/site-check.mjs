// SPDX-License-Identifier: BUSL-1.1
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

async function open(scheme, viewport, tag, opts = {}) {
  const ctx = await browser.newContext({ colorScheme: scheme, viewport, permissions: ["clipboard-read", "clipboard-write"], reducedMotion: opts.motion ? "no-preference" : "reduce", javaScriptEnabled: opts.js !== false });
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
check((await page.locator("#support a.btn").getAttribute("href")).startsWith("https://"), "landing: support link is https");
check(await page.getAttribute("html", "data-theme") === "light", "landing: follows OS light");
check(await page.locator(".reveal").count() === 0, "reduced motion: nothing is hidden waiting for a scroll reveal");
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
check(await page.locator("#steps .step-img").first().isVisible() && !(await page.locator(".stage").isVisible()), "mobile: each tour step carries its own image, the pinned stage is off");
check(await page.locator('.seg.wide').evaluate((el) => el.scrollWidth >= el.clientWidth), "mobile: the view picker scrolls instead of overflowing the page");
await shot(page, "site-landing-mobile");
bad.forEach((b) => check(false, b));
await ctx.close();

// ---------- feature sections: reveal, the pinned tour, the native-app showcase (motion allowed)
({ ctx, page, bad } = await open("dark", { width: 1440, height: 900 }, "features", { motion: true }));
await page.goto(base);
for (const id of ["tour", "mac", "depth"]) check(await page.locator("#" + id).count() === 1, `features: #${id} is on the page`);
check(await page.locator("#steps .step").count() === 5, "tour: five steps");
check(await page.locator('#sections a[href="#tour"], #sections a[href="#mac"]').count() === 2, "nav: Tour and Mac app are linked");
for (const [view, label] of [["containers", "Containers"], ["alerts", "Alerts"]]) {
  await page.locator(`#steps .step[data-view="${view}"]`).evaluate((el) => el.scrollIntoView({ block: "center" }));
  await page.waitForFunction((v) => document.getElementById("stage-img").src.includes(`glass-dark-${v}.png`), view);
  check((await page.locator("#stage-cap").innerText()).startsWith(label), `tour: scrolling to ${label} swaps the pinned screenshot and caption`);
  check(await page.locator(`#steps .step[data-view="${view}"]`).getAttribute("aria-current") === "true", `tour: ${label} is the current step`);
  const top = await page.locator(".stage").evaluate((el) => el.getBoundingClientRect().top);
  check(top >= 0 && top < 220, `tour: the stage stays pinned in view while ${label} is read`);
}
await shot(page, "site-tour");
await page.locator("#mac").scrollIntoViewIfNeeded();
await page.waitForTimeout(500);
await shot(page, "site-mac");
// a hard flick (1400px jumps, more than a screen) must not leave anything hidden behind the reader
await page.evaluate(async () => { for (let y = 0; y < document.body.scrollHeight; y += 1400) { window.scrollTo(0, y); await new Promise((r) => setTimeout(r, 70)); } window.scrollTo(0, document.body.scrollHeight); });
await page.waitForFunction(() => [...document.querySelectorAll(".reveal")].every((e) => e.classList.contains("in")), null, { timeout: 4000 }).catch(() => {});
const stuck = await page.evaluate(() => [...document.querySelectorAll(".reveal:not(.in)")].map((e) => `${e.tagName.toLowerCase()}.${e.className.replace(/\s*reveal\s*/, " ").trim()}:${(e.textContent || e.getAttribute("alt") || "").trim().slice(0, 30)}`));
check(stuck.length === 0 && await page.locator(".reveal").count() > 10, `reveal: everything has revealed after scrolling the page${stuck.length ? " (stuck: " + stuck.join(" | ") + ")" : ""}`);
await page.click("#theme");
await page.waitForFunction(() => document.getElementById("stage-img").src.includes("glass-light-") && document.querySelector("img[data-native]").src.includes("native-light-"));
check(true, "features: the pinned and native screenshots follow the page theme");
await page.locator("#mac").scrollIntoViewIfNeeded();
const bad2 = await page.evaluate(async () => { const out = []; for (const i of document.querySelectorAll("img[data-native], img[data-view]")) { i.loading = "eager"; await i.decode().catch(() => out.push(i.getAttribute("src"))); } return out; });
check(bad2.length === 0, `features: every tour and native image decodes${bad2.length ? " (" + bad2.join(", ") + ")" : ""}`);
check(await noSideScroll(page), "features: no horizontal scroll (desktop, motion on)");
bad.forEach((b) => check(false, b));
await ctx.close();

// ---------- without JavaScript every step still shows its own image and nothing is hidden
({ ctx, page, bad } = await open("light", { width: 1440, height: 900 }, "nojs", { js: false }));
await page.goto(base);
check(await page.locator("#steps .step-img").first().isVisible() && !(await page.locator(".stage").isVisible()), "no JS: every tour step shows its own image");
check(await page.locator(".reveal").count() === 0 && await page.locator("#features .card").first().isVisible(), "no JS: nothing is hidden waiting for a script");
check(await noSideScroll(page), "no JS: no horizontal scroll");
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
await page.waitForSelector(".view:not([hidden]) .data-table tbody tr");
check(await page.locator(".view:not([hidden]) .data-table tbody tr").count() >= 5, "demo: applications table renders");
await page.locator(".view:not([hidden]) .data-table tbody tr").first().click();
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
