// SPDX-License-Identifier: Apache-2.0
import { defineConfig, devices } from "@playwright/test";

const port = Number(process.env.VYTRIX_E2E_PORT || 5198);
const baseURL = `http://127.0.0.1:${port}`;

export default defineConfig({
  testDir: "tests/e2e",
  outputDir: "test-results",
  timeout: 45_000,
  expect: { timeout: 10_000 },
  fullyParallel: true,
  retries: process.env.CI ? 1 : 0,
  reporter: process.env.CI ? [["github"], ["list"]] : "list",
  use: { baseURL, trace: "retain-on-failure", screenshot: "only-on-failure" },
  projects: [
    { name: "webkit", use: { ...devices["Desktop Safari"], viewport: { width: 1440, height: 900 } } },
    { name: "chromium", use: { ...devices["Desktop Chrome"], viewport: { width: 1440, height: 900 } } },
    { name: "mobile-webkit", use: { ...devices["iPhone 15"] }, grep: /@mobile/ },
  ],
  webServer: {
    command: `node scripts/run-framework.mjs dev --port ${port} --host 127.0.0.1`,
    url: baseURL,
    reuseExistingServer: !process.env.CI,
    timeout: 120_000,
  },
});
