// SPDX-License-Identifier: Apache-2.0
import { expect, test, type Page } from "@playwright/test";

const nav = (page: Page, name: string) =>
  page.locator(".window .nav-item").filter({ hasText: name }).click();

// The preferences hook sets data-transparency only after hydration, so it marks the page as interactive.
async function open(page: Page) {
  await page.goto("/");
  await page.locator("html[data-transparency]").waitFor({ state: "attached" });
}

test.beforeEach(async ({ page }) => {
  await page.addInitScript(() => {
    if (!sessionStorage.getItem("vytrix-e2e")) { localStorage.clear(); sessionStorage.setItem("vytrix-e2e", "1"); }
  });
});

test.describe("desktop", () => {
  test.skip(({ isMobile }) => isMobile, "desktop layout only");

  test("overview shows simulated telemetry in the glass window", async ({ page }) => {
    await open(page);
    await expect(page.getByText("simulated telemetry")).toBeVisible();
    await expect(page.locator(".metric-tile")).toHaveCount(6);
    await expect(page.locator(".toolbar h1")).toHaveText("Overview");
    await expect(page.locator(".window .host-card")).toContainText("zyvor-dev-01");
    await expect(page.locator(".activity-chart svg").first()).toBeVisible();
    await expect(page.locator("html")).toHaveAttribute("data-theme", /glass|adwaita/);
  });

  test("containers view groups Docker and Podman and filters by state", async ({ page }) => {
    await open(page);
    await nav(page, "Containers");
    await expect(page.locator(".toolbar h1")).toHaveText("Containers");
    await expect(page.locator(".runtime-card .runtime-badge.docker")).toBeVisible();
    await expect(page.locator(".runtime-card .runtime-badge.podman")).toBeVisible();
    await expect(page.locator(".container-card")).toHaveCount(5);
    await page.getByRole("radio", { name: "Running" }).click();
    await expect(page.locator(".container-card")).toHaveCount(4);
    await page.getByRole("radio", { name: "Stopped" }).click();
    await expect(page.locator(".container-card")).toHaveCount(1);
    await expect(page.locator(".container-card")).toContainText("grafana");
    await page.getByRole("radio", { name: "All" }).click();
    await page.getByLabel("Search").fill("redis");
    await expect(page.locator(".container-card")).toHaveCount(1);
  });

  test("window style, appearance and accent persist", async ({ page }) => {
    await open(page);
    await nav(page, "Settings");
    await page.getByRole("radiogroup", { name: "Window style" }).getByRole("radio", { name: "Linux" }).click();
    await expect(page.locator("html")).toHaveAttribute("data-theme", "adwaita");
    await expect(page.locator(".gnome-controls")).toBeVisible();
    await expect(page.locator(".traffic-lights")).toHaveCount(0);
    await page.getByRole("radiogroup", { name: "Window style" }).getByRole("radio", { name: "macOS" }).click();
    await expect(page.locator("html")).toHaveAttribute("data-theme", "glass");
    await expect(page.locator(".traffic-lights")).toBeVisible();
    await page.getByRole("radiogroup", { name: "Appearance" }).getByRole("radio", { name: "Dark" }).click();
    await expect(page.locator("html")).toHaveClass(/dark/);
    await page.getByRole("radio", { name: "purple" }).click();
    await expect(page.locator("html")).toHaveAttribute("data-accent", "purple");
    await page.reload();
    await page.locator("html[data-transparency]").waitFor({ state: "attached" });
    await expect(page.locator("html")).toHaveClass(/dark/);
    await expect(page.locator("html")).toHaveAttribute("data-accent", "purple");
  });

  test("reduce transparency swaps glass for solid surfaces", async ({ page }) => {
    await open(page);
    await nav(page, "Settings");
    await page.getByRole("switch", { name: "Reduce transparency" }).click();
    await expect(page.locator("html")).toHaveAttribute("data-transparency", "reduced");
    const blur = await page.locator(".window").evaluate((el) => getComputedStyle(el).backdropFilter || getComputedStyle(el).getPropertyValue("-webkit-backdrop-filter"));
    expect(blur === "none" || blur === "").toBeTruthy();
  });

  test("process sheet lists processes for an application", async ({ page }) => {
    await open(page);
    await page.locator(".leader-list button").first().click();
    const sheet = page.locator(".process-sheet");
    await expect(sheet).toBeVisible();
    await expect(sheet.locator("tbody tr").first()).toBeVisible();
    await page.keyboard.press("Escape");
    await expect(sheet).toBeHidden();
  });

  test("connect dialog rejects plain-HTTP remote collectors", async ({ page }) => {
    await open(page);
    await page.locator(".toolbar").getByRole("button", { name: "Connect" }).click();
    await page.getByLabel("Collector endpoint").fill("http://example.com/v1/snapshot");
    await page.getByLabel("Access token").fill("x".repeat(32));
    await page.getByRole("button", { name: "Connect", exact: true }).last().click();
    await expect(page.getByRole("alert")).toContainText("Could not connect");
  });

  test("alerts fire when the threshold is lowered", async ({ page }) => {
    await open(page);
    await nav(page, "Settings");
    await page.getByLabel("Alert threshold percent").fill("10");
    await nav(page, "Alerts");
    await expect(page.locator(".alert-row").first()).toBeVisible();
    await page.locator(".alert-row").first().getByRole("button", { name: "Dismiss" }).click();
  });
});

test("mobile layout uses a sheet for navigation @mobile", async ({ page, isMobile }) => {
  test.skip(!isMobile, "mobile only");
  await open(page);
  await expect(page.locator(".window > .sidebar")).toBeHidden();
  await page.getByRole("button", { name: "Toggle sidebar" }).click();
  await page.locator(".mobile-nav .nav-item").filter({ hasText: "Containers" }).click();
  await expect(page.locator(".toolbar h1")).toHaveText("Containers");
});
