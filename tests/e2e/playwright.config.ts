import { defineConfig, devices } from "@playwright/test";

export default defineConfig({
  testDir: ".",
  fullyParallel: false,
  forbidOnly: !!process.env.CI,
  retries: 0,
  workers: 1,
  timeout: 5 * 60 * 1000, // 5 min default per test
  expect: {
    timeout: 30_000,
  },

  reporter: [["html", { open: "never", outputFolder: "playwright-report" }], ["list"]],

  use: {
    baseURL: process.env.BASE_URL,
    ignoreHTTPSErrors: true,
    trace: "retain-on-failure",
    video: "off",
    screenshot: "only-on-failure",
    actionTimeout: 30_000,
    navigationTimeout: 60_000,
  },

  projects: [
    {
      name: "chromium",
      use: { ...devices["Desktop Chrome"] },
    },
  ],
});
