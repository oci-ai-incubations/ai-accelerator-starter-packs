import { type Page } from "@playwright/test";

export class ContentReviewPage {
  readonly page: Page;

  constructor(page: Page) {
    this.page = page;
  }

  async goto() {
    await this.page.goto("/content-review", { waitUntil: "networkidle" });
    await this.page.waitForTimeout(1000);
  }

  /** Summary tabs — role="tab" elements with video filenames */
  get tabs() {
    return this.page.locator('[role="tab"]');
  }

  async getTabCount() {
    return this.tabs.count();
  }

  async clickTab(index = 0) {
    const count = await this.tabs.count();
    if (count > index) {
      await this.tabs.nth(index).click();
      await this.page.waitForTimeout(1500);
    }
    return count;
  }

  /** Pagination info — "Page X of Y (N summaries)" text */
  async getSummaryCountFromText(): Promise<number | null> {
    const text = await this.page.textContent("body");
    const match = text?.match(/(\d+)\s*summar/i);
    return match ? parseInt(match[1], 10) : null;
  }

  /** Timeline rows in the table */
  get timelineTable() {
    return this.page.locator("table");
  }

  get timelineRows() {
    return this.page.locator("table tbody tr");
  }

  async hasTimestamps() {
    const text = await this.page.textContent("body");
    return /\d+\.\d+\s*[–\-:]\s*\d+\.\d+/.test(text || "");
  }

  /** Approve button — per-row, aria-label="Approve" */
  get approveButtons() {
    return this.page.getByRole("button", { name: "Approve" });
  }

  /** Reject button — per-row, aria-label="Reject" */
  get rejectButtons() {
    return this.page.getByRole("button", { name: "Reject" });
  }

  /** Reset review button */
  get resetButtons() {
    return this.page.getByRole("button", { name: "Reset review" });
  }

  /** Comment button — per-row, aria-label="Add comment" */
  get commentButtons() {
    return this.page.getByRole("button", { name: "Add comment" });
  }

  /** Play segment button — per-row */
  get playButtons() {
    return this.page.getByRole("button", { name: "Play segment" });
  }

  /** Stats button */
  get statsButton() {
    return this.page.getByRole("button", { name: /stats/i });
  }

  /** Export CSV button */
  get exportButton() {
    return this.page.getByRole("button", { name: /export csv/i });
  }

  /** Delete summary button inside a tab — aria-label="Delete summary" */
  get deleteButtons() {
    return this.page.getByRole("button", { name: "Delete summary" });
  }

  /** Chart in stats dialog */
  get chart() {
    return this.page.locator(".recharts-wrapper, .recharts-bar, svg.recharts-surface");
  }

  /** Delete a summary — handles window.confirm() dialog */
  async deleteSummary(tabIndex = 0) {
    const countBefore = (await this.getSummaryCountFromText()) ?? (await this.getTabCount());

    // Set up confirm dialog handler BEFORE clicking delete
    this.page.once("dialog", async (dialog) => {
      await dialog.accept();
    });

    const deleteBtn = this.deleteButtons.nth(tabIndex);
    if (await deleteBtn.isVisible({ timeout: 3000 }).catch(() => false)) {
      await deleteBtn.click();
      // Wait for delete API call and page update
      await this.page.waitForTimeout(2000);
      await this.page.reload({ waitUntil: "networkidle" });
      await this.page.waitForTimeout(1000);

      const countAfter = (await this.getSummaryCountFromText()) ?? (await this.getTabCount());
      return { countBefore, countAfter, deleted: true };
    }
    return { countBefore, countAfter: countBefore, deleted: false };
  }
}
