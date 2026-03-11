import { type Page } from "@playwright/test";

export class AnalyticsPage {
  readonly page: Page;

  constructor(page: Page) {
    this.page = page;
  }

  async goto() {
    await this.page.goto("/analytics", { waitUntil: "networkidle" });
  }

  async hasPlaceholder() {
    const text = await this.page.textContent("body");
    return (
      text?.toLowerCase().includes("coming soon") ||
      text?.toLowerCase().includes("placeholder") ||
      text?.toLowerCase().includes("under construction") ||
      false
    );
  }

  async isLoaded() {
    const text = await this.page.textContent("body");
    return (text?.length ?? 0) > 50;
  }
}
