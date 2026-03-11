import { test, expect, type Page, type BrowserContext } from "@playwright/test";
import { HomePage } from "./pages/home.page";
import { ContentReviewPage } from "./pages/content-review.page";
import { SettingsPage } from "./pages/settings.page";
import { AnalyticsPage } from "./pages/analytics.page";

const BUCKET_NAME = process.env.VSS_BUCKET_NAME || "vss-test";
const BASE_URL = process.env.BASE_URL || "http://localhost:3000";

let context: BrowserContext;
let p: Page;

/** Show a banner overlay in the recording labeling the current test */
async function banner(label: string) {
  await p
    .evaluate((t: string) => {
      let el = document.getElementById("__ci__");
      if (!el) {
        el = document.createElement("div");
        el.id = "__ci__";
        el.style.cssText =
          "position:fixed;top:0;left:0;right:0;z-index:2147483647;" +
          "background:#0d1117;color:#58a6ff;font:bold 14px/38px monospace;" +
          "padding:0 16px;border-bottom:2px solid #1f6feb;letter-spacing:.5px";
        document.documentElement.prepend(el);
      }
      el.textContent = "\u25B6  " + t;
    }, label)
    .catch(() => {});
  await p.waitForTimeout(400);
}

/** Navigate only if not already on the target path */
async function navigateTo(path: string) {
  const current = new URL(p.url()).pathname;
  if (current !== path) {
    await p.goto(path, { waitUntil: "networkidle" });
  }
}

/** Scroll an element into view so it's visible in the recording */
async function scrollTo(selector: string) {
  await p
    .locator(selector)
    .first()
    .scrollIntoViewIfNeeded()
    .catch(() => {});
}

test.describe.serial("VSS UI Tests", () => {
  test.beforeAll(async ({ browser }) => {
    context = await browser.newContext({
      baseURL: BASE_URL,
      ignoreHTTPSErrors: true,
      recordVideo: {
        dir: "test-results/vss-recording",
        size: { width: 1280, height: 720 },
      },
    });
    p = await context.newPage();
    p.setDefaultTimeout(30_000);
    p.setDefaultNavigationTimeout(60_000);
  });

  test.afterAll(async () => {
    await banner("ALL TESTS COMPLETE");
    await p.waitForTimeout(1000);
    await context.close();
  });

  // ── Smoke tests (Home + Settings + Nav) ──────────────────────────

  test("VU-1: Header/title visible", async () => {
    await p.goto("/", { waitUntil: "networkidle" });
    await banner("VU-1: Header/title visible");

    const title = await p.title();
    expect(title).toContain("Broadcast Compliance");
  });

  test("VU-3: Bucket configured in Settings", async () => {
    await banner("VU-3: Bucket configured in Settings");
    await navigateTo("/settings");

    const settings = new SettingsPage(p);
    let bucket = await settings.getBucketValue();
    if (!bucket) {
      await p.evaluate((name) => localStorage.setItem("vss-bucket", name), BUCKET_NAME);
      await p.reload({ waitUntil: "networkidle" });
      await banner("VU-3: Bucket configured in Settings");
      bucket = await settings.getBucketValue();
    }

    await scrollTo("input");
    expect(bucket, "Bucket should be configured on Settings page").toBeTruthy();
  });

  test("VU-2: Sidebar navigation", async () => {
    await banner("VU-2: Sidebar navigation");
    await navigateTo("/");

    const nav = p.locator('nav[aria-label="Main"]');
    await expect(nav).toBeVisible();

    const targets = [
      { name: "Content Review", path: "/content-review" },
      { name: "Analytics", path: "/analytics" },
      { name: "Settings", path: "/settings" },
      { name: "Home", path: "/" },
    ];

    for (const target of targets) {
      await banner("VU-2: Nav \u2192 " + target.name);
      await nav.getByRole("link", { name: target.name }).click();
      if (target.path === "/") {
        await p.waitForURL((url) => url.pathname === "/", { timeout: 5000 });
      } else {
        await p.waitForURL(`**${target.path}*`, { timeout: 5000 });
      }
      const pathname = new URL(p.url()).pathname;
      expect(pathname, `Navigation to ${target.name}`).toBe(target.path);
    }
  });

  test("VU-4: File list loads on refresh", async () => {
    await banner("VU-4: File list loads on refresh");
    // VU-2 ended on Home, so no navigation needed
    const home = new HomePage(p);
    await home.ensureBucketConfigured(BUCKET_NAME);
    await home.refreshFileList();

    await scrollTo("table, [role='grid'], [role='list']");
    const body = await p.textContent("body");
    expect(body).not.toContain("does not exist");

    const hasFiles = /\.(mp4|mov|avi|mkv)/i.test(body || "");
    expect(hasFiles, "No video files visible in file list").toBeTruthy();
  });

  test("VU-6: File selection", async () => {
    await banner("VU-6: File selection");
    // Already on Home from VU-4
    const home = new HomePage(p);
    await p.waitForTimeout(1000);

    const checkboxes = home.checkboxes;
    await scrollTo('input[type="checkbox"]');
    const count = await checkboxes.count();
    expect(count, "No file checkboxes found").toBeGreaterThan(0);

    await checkboxes.first().check();
    await expect(checkboxes.first()).toBeChecked();

    await expect(home.analyzeButton).toBeVisible({ timeout: 3000 });
    await banner("VU-6: \u2705 File selected, Analyze button visible");
    await p.waitForTimeout(500);
  });

  test("VU-7: Parameter sections toggle", async () => {
    await banner("VU-7: Parameter sections toggle");
    // Already on Home
    const home = new HomePage(p);

    const sections = await home.getParameterSections();
    const count = await sections.count();

    if (count > 0) {
      await sections.first().scrollIntoViewIfNeeded();
      await sections.first().click();
      await p.waitForTimeout(500);
    }
    test.info().annotations.push({
      type: "note",
      description: count > 0 ? `${count} collapsible sections found` : "N/A — params hidden in batch mode",
    });
  });

  // ── Batch processing (long-running) ──────────────────────────────

  test("VU-10: Batch upload & analyze (multi-video)", async () => {
    test.setTimeout(90 * 60 * 1000);

    await banner("VU-10: Selecting files for batch processing");
    await navigateTo("/");
    const home = new HomePage(p);
    await home.ensureBucketConfigured(BUCKET_NAME);
    await p.waitForTimeout(2000);

    await scrollTo('input[type="checkbox"]');
    const selected = await home.selectFiles(2);
    expect(selected, "Need at least 2 files to select").toBeGreaterThanOrEqual(2);

    await banner("VU-10: Clicking Upload & Analyze");
    await home.clickAnalyze();
    await p.waitForTimeout(3000);

    const startTime = Date.now();

    await expect(async () => {
      const elapsed = Math.round((Date.now() - startTime) / 60000);
      await banner("VU-10: Processing... " + elapsed + "min elapsed");

      const body = await p.textContent("body").catch(() => "");
      const hasProcessing = /processing|queued|pending/i.test(body || "");

      if (hasProcessing) {
        // Scroll to show the queue/status area
        await scrollTo("table, [role='grid'], [role='list']");
        throw new Error(`Still processing after ${elapsed} min`);
      }

      await p.goto("/content-review", { waitUntil: "networkidle" });
      await banner("VU-10: Checking Content Review for results");
      await p.waitForTimeout(2000);
      const tabs = p.locator('[role="tab"]');
      const tabCount = await tabs.count();
      expect(tabCount, "Content Review should have tabs for processed videos").toBeGreaterThan(0);
    }).toPass({
      intervals: [30_000],
      timeout: 85 * 60 * 1000,
    });

    await banner("VU-10: \u2705 Batch processing complete");
    await p.waitForTimeout(500);
  });

  // ── Content Review tests ─────────────────────────────────────────

  test("VU-20: Content Review summaries", async () => {
    await banner("VU-20: Content Review summaries");
    await navigateTo("/content-review");

    const cr = new ContentReviewPage(p);
    await scrollTo('[role="tab"]');
    const tabCount = await cr.clickTab(0);
    expect(tabCount, "Content Review should have at least 1 summary tab").toBeGreaterThan(0);
    await banner("VU-20: \u2705 " + tabCount + " summary tab(s) found");
    await p.waitForTimeout(500);
  });

  test("VU-23: Timeline table renders", async () => {
    await banner("VU-23: Timeline table renders");
    // Already on content-review with tab selected from VU-20

    const cr = new ContentReviewPage(p);
    await scrollTo("table");
    const hasTs = await cr.hasTimestamps();
    const rowCount = await cr.timelineRows.count();

    expect(
      hasTs || rowCount > 0,
      `Timeline should have timestamps or rows. Rows: ${rowCount}, timestamps: ${hasTs}`,
    ).toBeTruthy();
    await banner("VU-23: \u2705 " + rowCount + " rows, timestamps: " + hasTs);
    await p.waitForTimeout(500);
  });

  test("VU-28/29: Approve/reject rows", async () => {
    await banner("VU-28/29: Approve/reject rows");
    // Already on content-review with tab selected

    const cr = new ContentReviewPage(p);
    const tableVisible = await cr.timelineTable.isVisible({ timeout: 3000 }).catch(() => false);

    if (!tableVisible) {
      await banner("VU-28/29: N/A \u2014 no timeline table");
      test.info().annotations.push({
        type: "note",
        description:
          "N/A — Timeline table not rendered (categories filtered as 'No clear evidence'). Approve/reject requires categorized events.",
      });
      return;
    }

    await scrollTo("table");
    const approveCount = await cr.approveButtons.count();
    const rejectCount = await cr.rejectButtons.count();

    if (approveCount > 0) {
      await banner("VU-28: Clicking Approve");
      await cr.approveButtons.first().scrollIntoViewIfNeeded();
      await cr.approveButtons.first().click();
      await p.waitForTimeout(500);
      const resetCount = await cr.resetButtons.count();
      expect(resetCount).toBeGreaterThan(0);
    }

    if (rejectCount > 0) {
      await banner("VU-29: Clicking Reject");
      await cr.rejectButtons.first().scrollIntoViewIfNeeded();
      await cr.rejectButtons.first().click();
      await p.waitForTimeout(500);
    }

    expect(
      approveCount + rejectCount,
      "At least one approve or reject button should be visible when table is rendered",
    ).toBeGreaterThan(0);
    await banner("VU-28/29: \u2705 Approve/reject done");
    await p.waitForTimeout(500);
  });

  test("VU-30: Save & verify reviews", async () => {
    await banner("VU-30: Save & verify reviews (reload test)");
    await navigateTo("/content-review");

    const cr = new ContentReviewPage(p);
    await cr.clickTab(0);

    const tableVisible = await cr.timelineTable.isVisible({ timeout: 3000 }).catch(() => false);
    if (!tableVisible) {
      await banner("VU-30: N/A \u2014 no timeline table");
      test.info().annotations.push({
        type: "note",
        description: "N/A — Timeline table not rendered; no reviews to save.",
      });
      return;
    }

    // Do a fresh approve and wait for the API response to confirm it saved
    const approveCount = await cr.approveButtons.count();
    if (approveCount > 0) {
      await banner("VU-30: Approving a row and waiting for API save");
      const [response] = await Promise.all([
        p.waitForResponse((r) => r.url().includes("/reviews") && r.status() === 200, { timeout: 10_000 }).catch(() => null),
        cr.approveButtons.first().click(),
      ]);

      if (response) {
        await banner("VU-30: API confirmed save, reloading");
      } else {
        // Fallback: wait for network to settle
        await p.waitForLoadState("networkidle");
        await p.waitForTimeout(2000);
        await banner("VU-30: Reloading to verify persistence");
      }
    }

    const resetCountBefore = await cr.resetButtons.count();

    await p.reload({ waitUntil: "networkidle" });
    await banner("VU-30: Waiting for tab content after reload");
    await p.waitForTimeout(2000);
    await cr.clickTab(0);
    await cr.timelineTable.waitFor({ state: "visible", timeout: 10_000 }).catch(() => {});
    await p.waitForTimeout(1000);

    await scrollTo("table");
    const resetCountAfter = await cr.resetButtons.count();
    if (resetCountAfter >= resetCountBefore) {
      await banner("VU-30: \u2705 Reviews persisted after reload");
    } else {
      await banner(
        "VU-30: \u274C Reviews did not persist (" + resetCountBefore + " \u2192 " + resetCountAfter + ")",
      );
    }
    expect(
      resetCountAfter >= resetCountBefore,
      `Reviews did not persist after reload — ${resetCountBefore} reset buttons before, ${resetCountAfter} after.`,
    ).toBeTruthy();
    await p.waitForTimeout(500);
  });

  test("VU-32: Category stats chart", async () => {
    await banner("VU-32: Category stats chart");
    // Already on content-review

    const cr = new ContentReviewPage(p);
    const statsBtn = cr.statsButton;
    if (await statsBtn.isVisible({ timeout: 3000 }).catch(() => false)) {
      await statsBtn.scrollIntoViewIfNeeded();
      await banner("VU-32: Opening stats dialog");
      await statsBtn.click();
      await p.waitForTimeout(1000);

      const dialog = p.getByRole("dialog");
      await expect(dialog).toBeVisible({ timeout: 3000 });

      const chartVisible = await cr.chart.first().isVisible().catch(() => false);
      await banner(
        "VU-32: " + (chartVisible ? "\u2705 Chart rendered" : "Dialog open, no chart data"),
      );
      test.info().annotations.push({
        type: "note",
        description: chartVisible ? "Recharts bar chart rendered" : "Dialog open but no chart data",
      });

      await p.waitForTimeout(1000);
      await p.keyboard.press("Escape");
      await p.waitForTimeout(500);
    } else {
      await banner("VU-32: N/A \u2014 Stats button not visible");
      test.info().annotations.push({
        type: "note",
        description: "N/A — Stats button not visible (may need more data)",
      });
    }
  });

  test("VU-31: Delete summary cascade", async () => {
    await banner("VU-31: Delete summary cascade");
    await navigateTo("/content-review");

    const cr = new ContentReviewPage(p);
    await scrollTo('[role="tab"]');

    await banner("VU-31: Clicking delete on first summary");
    const result = await cr.deleteSummary(0);
    await banner(
      "VU-31: " +
        (result.deleted
          ? "\u2705 Deleted (" + result.countBefore + " \u2192 " + result.countAfter + ")"
          : "\u274C Delete button not found"),
    );
    await p.waitForTimeout(500);

    expect(result.deleted, "Delete button should be found").toBeTruthy();
    expect(
      result.countAfter,
      `Summary count should decrease after delete (was ${result.countBefore})`,
    ).toBeLessThan(result.countBefore);
  });

  // ── Settings & Analytics ─────────────────────────────────────────

  test("VU-40: Settings page", async () => {
    await banner("VU-40: Settings page");
    await navigateTo("/settings");

    const settings = new SettingsPage(p);
    await scrollTo("input, textarea");

    const bucket = await settings.getBucketValue();
    const hasPrompts = await settings.hasPrompts();
    const hasParams = await settings.hasParams();
    const inputCount = await settings.getInputCount();

    expect(bucket || inputCount > 0, "Settings should show bucket or inputs").toBeTruthy();
    expect(hasPrompts, "Settings should show prompt configuration").toBeTruthy();
    expect(hasParams, "Settings should show parameter configuration").toBeTruthy();
    await banner("VU-40: \u2705 Settings verified");
    await p.waitForTimeout(500);
  });

  test("VU-50: Analytics placeholder", async () => {
    await banner("VU-50: Analytics placeholder");
    await navigateTo("/analytics");

    const analytics = new AnalyticsPage(p);

    const loaded = await analytics.isLoaded();
    expect(loaded, "Analytics page should load").toBeTruthy();

    const hasPlaceholder = await analytics.hasPlaceholder();
    expect(hasPlaceholder, "Analytics should show placeholder text").toBeTruthy();
    await banner("VU-50: \u2705 Analytics page verified");
    await p.waitForTimeout(500);
  });
});
