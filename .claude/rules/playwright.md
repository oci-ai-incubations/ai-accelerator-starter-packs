# Playwright UI Testing Rules

## Core Principle
Don't just verify elements exist — **interact with them**. A test that counts buttons without clicking them proves nothing. Every interactive element in the test matrix should be exercised.

## Interaction Rules

### Buttons and Controls
- **Press every actionable button** at least once (play, approve, reject, delete, save, export).
- After clicking, **verify the result** — did the state change? Did a new element appear? Did the URL change?
- If a button triggers an async operation, **wait for the result** before asserting. Use `waitForResponse`, `waitForSelector`, or poll for state changes — not blind `waitForTimeout`.

### Popups, Modals, and Dialogs
- **Always close popups/modals/dialogs before moving to the next test.** An unclosed modal blocks interaction with elements behind it.
- Pattern: detect → interact → verify → **dismiss** → continue.
- Check for modals with: `p.locator('[role="dialog"], [role="alertdialog"], .modal, [data-state="open"]')`.
- **Dismiss using the close button or X button first** — look for `button[aria-label="Close"]`, `button:has-text("Close")`, `button:has-text("×")`, or a close/X icon button inside the dialog. Only fall back to `p.keyboard.press('Escape')` or clicking the overlay backdrop if no close button is found.
- After any interaction that might open a popup, **always check for and dismiss** open dialogs before proceeding.

### Tables
- Don't just count rows — **click into cells**, expand rows, trigger inline edits.
- For editable fields: click to enter edit mode → type new value → verify the value sticks.
- For action columns: click each action type (approve, reject, edit, delete) on at least one row and verify the visual/state change.

### Multi-Item Workflows
- If the feature supports batch/multi-select (e.g., multi-video processing), **test with multiple items selected**, not just one.
- Verify that the count/progress reflects all selected items.
- After batch processing, verify **each item's result** individually — don't just check the first one.

### Media Players
- **Click the play button** and verify the video/audio actually starts (`currentTime > 0` or `!paused`).
- Test scrubbing: click a timeline row's play button and verify the player seeks to the correct timestamp.
- Verify the correct media source loaded (check `src` attribute or network request).

## Recording Rules
- Always use **continuous video recording** via `browser.newContext({ recordVideo: { dir: ..., size: { width: 1280, height: 800 } } })`.
- Inject a **banner overlay** to label each test step in the recording (see banner helper pattern in deploy-and-test skill).
- Close the context in a `finally` block to finalize the `.webm` file.
- Never use `p.screenshot()` — the video recording captures everything; screenshots are redundant.
- **One single video for the entire test run.** All tests share one browser context and one recording. Never create multiple contexts or multiple videos.

## Structural Rules
- **One `browser_run_code` call per test group.** `globalThis` does not persist between separate calls. Group related checks together.
- Use `var` (not `const`/`let`) and string concatenation (not template literals) to avoid escaping issues in the code string.
- Wrap everything in `try/catch/finally` — `finally` must close the recording context.
- Collect results into a `results` object keyed by test ID and return it.

## Test Isolation and Recovery
- **If a test fails, do NOT let it abort the run.** Wrap each individual test in its own `try/catch`. On failure, record the error in results, **refresh the page** (`p.goto(BASE, { waitUntil: 'networkidle' })` or navigate to the next test's page), and continue to the next test. Every test must get a chance to run.
- After any destructive or state-changing action, navigate fresh to the next test's page to avoid stale state.

## State Management
- **Check for pre-existing state** before testing (e.g., localStorage values, saved preferences, cached data). The app may auto-load data from a previous session.
- If a test modifies state (deletes a record, changes a setting), either:
  - Restore the original state after the test, OR
  - Note it as a destructive test and run it last.
- Before asserting "element not found", **wait for async loading** — many SPAs load content after initial render.

## Error Handling
- If an element isn't found by the expected selector, **try alternative selectors** before failing. SPAs change markup across versions.
- Fallback chain: role selector → text selector → data-testid → CSS class → DOM structure.
- On test failure, **log what was actually on the page** (e.g., `p.textContent('body')` or snapshot) to help debug.
