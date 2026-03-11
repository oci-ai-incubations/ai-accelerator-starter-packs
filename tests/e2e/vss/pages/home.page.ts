import { type Page, type Locator, expect } from "@playwright/test";

export class HomePage {
  readonly page: Page;
  readonly heading: Locator;
  readonly fileList: Locator;
  readonly refreshButton: Locator;
  readonly checkboxes: Locator;
  readonly analyzeButton: Locator;

  constructor(page: Page) {
    this.page = page;
    this.heading = page.locator("body");
    this.fileList = page.locator("table, [role='grid'], [role='list']").first();
    this.refreshButton = page.locator("button").filter({ hasText: /refresh|reload/i }).first();
    this.checkboxes = page.locator('input[type="checkbox"]');
    this.analyzeButton = page.locator("button").filter({ hasText: /analyze|upload.*analyze|process/i }).first();
  }

  async goto() {
    await this.page.goto("/", { waitUntil: "networkidle" });
  }

  async ensureBucketConfigured(bucketName: string) {
    await this.page.evaluate(
      (name) => localStorage.setItem("vss-bucket", name),
      bucketName,
    );
  }

  async getFileRows() {
    return this.page.locator("tr, [role='row'], div, li").filter({ hasText: /\.(mp4|mov|avi|mkv)/i });
  }

  async refreshFileList() {
    const hasRefresh = await this.refreshButton.isVisible().catch(() => false);
    if (hasRefresh) {
      await this.refreshButton.click();
    } else {
      await this.page.reload({ waitUntil: "networkidle" });
    }
    await this.page.waitForTimeout(2000);
  }

  async selectFiles(count: number) {
    const total = await this.checkboxes.count();
    const toSelect = Math.min(count, total);
    for (let i = 0; i < toSelect; i++) {
      await this.checkboxes.nth(i).check({ force: true });
    }
    return toSelect;
  }

  async getCheckedCount() {
    let checked = 0;
    const total = await this.checkboxes.count();
    for (let i = 0; i < total; i++) {
      if (await this.checkboxes.nth(i).isChecked().catch(() => false)) {
        checked++;
      }
    }
    return checked;
  }

  async clickAnalyze() {
    await expect(this.analyzeButton).toBeVisible({ timeout: 5000 });
    await this.analyzeButton.click();
  }

  async getParameterSections() {
    return this.page
      .locator('[data-state="closed"], [data-state="open"], details, [role="button"]')
      .filter({ hasText: /param|VLM|RAG|summar/i });
  }
}
