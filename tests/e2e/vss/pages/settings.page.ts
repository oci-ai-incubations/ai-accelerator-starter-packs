import { type Page, type Locator } from "@playwright/test";

export class SettingsPage {
  readonly page: Page;
  readonly inputs: Locator;
  readonly textareas: Locator;

  constructor(page: Page) {
    this.page = page;
    this.inputs = page.locator("input");
    this.textareas = page.locator("textarea");
  }

  async goto() {
    await this.page.goto("/settings", { waitUntil: "networkidle" });
  }

  async getBucketValue(): Promise<string | null> {
    const count = await this.inputs.count();
    for (let i = 0; i < count; i++) {
      const val = await this.inputs.nth(i).inputValue().catch(() => "");
      if (val && (val.includes("vss") || val.includes("bucket") || val.includes("test"))) {
        return val;
      }
    }
    // Check page text
    const text = await this.page.textContent("body");
    if (text?.includes("vss-test")) return "vss-test (in page text)";
    return null;
  }

  async hasPrompts() {
    const text = await this.page.textContent("body");
    return (
      (text?.includes("prompt") || text?.includes("caption") || text?.includes("summar")) ?? false
    );
  }

  async hasParams() {
    const text = await this.page.textContent("body");
    return (
      (text?.includes("model") || text?.includes("chunk") || text?.includes("duration")) ?? false
    );
  }

  async getInputCount() {
    const inputs = await this.inputs.count();
    const textareas = await this.textareas.count();
    return inputs + textareas;
  }
}
