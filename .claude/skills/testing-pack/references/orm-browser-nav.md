# ORM Browser Navigation Patterns

## Overview

OCI Resource Manager (ORM) is a single-page application (SPA) running inside the OCI Console. Browser automation requires handling dynamic rendering, iframes, and Oracle's custom component library. These patterns were discovered through manual testing and cover the most common navigation operations.

**Freedom level: HIGH — these are guidance patterns, not exact scripts. Adapt as needed.**

---

## Authentication / Login

OCI Console requires authentication. The agent cannot enter credentials — the user must do this manually in the headed browser window.

### Recommended flow

1. Launch headed browser and navigate to OCI:
   ```bash
   agent-browser --headed --session-name oci open "https://cloud.oracle.com"
   agent-browser --session-name oci wait --load networkidle
   ```

2. Check if already authenticated by taking a snapshot:
   ```bash
   agent-browser --session-name oci snapshot -i
   ```

3. **If login form visible** (User Name / Password fields, or redirected to `oracle.com/cloud/sign-in.html`):
   - Tell the user: "Please enter your OCI credentials in the browser window that just opened. Let me know when you're done."
   - **Wait for explicit user confirmation** before proceeding. Do not poll or guess.

4. **If Console home page visible** (Navigation menu, Region menu, compartment selector):
   - Proceed to next phase.

### Session persistence

Use `--session-name oci` on all agent-browser commands. This auto-saves cookies/localStorage so subsequent runs may skip login. However, OCI sessions expire — always check the snapshot after opening, don't assume a saved session means authenticated.

### What NOT to do

- Don't try to fill username/password fields — the user enters credentials manually
- Don't poll the page waiting for login to complete — wait for user confirmation
- Don't use `--auto-connect` as the primary strategy — it only works if Chrome is already running with remote debugging enabled, which is rare

---

## Region Verification

The active region is displayed in the region menu button in the top navigation bar. Its text content reflects the currently selected region display name.

### How to check the current region

```python
# The region selector is a button in the top nav — its text is the region display name
# e.g., "US West (San Jose)", "US East (Ashburn)"
region_button = page.locator('[data-testid="region-menu"]')
# or fallback: look for a button containing the region name
region_text = page.locator('button:has-text("US West")').text_content()
print(f"Current region: {region_text}")
```

### How to change the region

```python
# Click the region menu button to open the dropdown
page.click('[data-testid="region-menu"]')
page.wait_for_timeout(500)

# Search for the target region or click it directly
page.click(f'text="{target_region_display_name}"')
page.wait_for_load_state("networkidle")
```

If `data-testid` attributes are not present, locate by role and approximate text:
```python
page.locator('button').filter(has_text="US West").click()
```

---

## Compartment Selection

The compartment picker is a dropdown/tree widget that supports text search. It appears in the breadcrumb bar or as a standalone selector depending on the ORM page.

### Pattern: click dropdown, search, click treeitem

```python
# Step 1: Click the compartment selector to open it
page.click('[aria-label="Compartment"]')
# or: page.locator('text="Compartment"').locator('..').click()
page.wait_for_timeout(300)

# Step 2: Type to filter compartments by name
page.keyboard.type("Grant-Compartment")
page.wait_for_timeout(500)

# Step 3: Click the matching tree item
# Compartment options render with role="treeitem"
page.click('[role="treeitem"]:has-text("Grant-Compartment")')
page.wait_for_load_state("networkidle")
```

Notes:
- The compartment tree is lazy-loaded — wait after opening before typing
- Partial name matches work for the search filter
- If multiple compartments have similar names, use a longer search string

---

## Iframe Scoping

ORM embeds content (variable forms, file upload dialogs, preview panes) inside iframes. Standard Playwright selectors do not cross iframe boundaries by default.

### Scoping into an iframe with `-s "iframe"`

When using the agent-browser CLI tool, pass `-s "iframe"` to scope all subsequent selectors into the first iframe. For specific iframes, use a more targeted selector:

```bash
# Scope into the first iframe on the page
browser -s "iframe" click "button:has-text('Upload')"

# Scope into a specific iframe by src or title
browser -s "iframe[src*='resource-manager']" fill "input[name='stack-name']" "my-stack"
```

### Evaluating JavaScript in an iframe's contentDocument

For operations that require direct DOM access inside an iframe (e.g., reading input values, triggering events), use `iframe.contentDocument`:

```python
# Get the iframe element handle
iframe_handle = page.locator("iframe").first.element_handle()
content_doc = iframe_handle.content_frame()

# Now interact with elements inside the iframe
content_doc.click("button:has-text('Next')")
content_doc.fill("input[name='stack-name']", "my-stack")

# Or evaluate JS in the iframe context
result = content_doc.evaluate("document.querySelector('input[type=\"file\"]').id")
```

Note: For cross-origin iframes, JavaScript evaluation via `evaluate()` will be blocked by the browser's same-origin policy. Use CDP directly in that case (see `cdp-file-upload.md`).

---

## Edit Stack Wizard Navigation

The ORM "Edit Stack" wizard has 3 steps:
1. **Stack information** — name, description, zip upload
2. **Configure variables** — all Terraform variables from the schema
3. **Review** — summary before saving

### Step 1 to Step 2

After uploading the zip and setting the stack name on Step 1, click "Next":

```python
page.click("button:has-text('Next')")
# Wait for the variable form to render — it can take several seconds
page.wait_for_selector('[data-testid="variable-form"]', timeout=15000)
# or fallback: wait for a known variable label to appear
page.wait_for_selector('text="Compartment OCID"', timeout=15000)
```

### Step 2 to Step 3

After filling in all required variables, click "Next" again:

```python
page.click("button:has-text('Next')")
# Wait for the Review step header
page.wait_for_selector('text="Review"', timeout=10000)
# or wait for networkidle to confirm the review page has loaded
page.wait_for_load_state("networkidle")
```

### Step 3 — Save (not Apply)

The final step offers "Save changes" (or "Create") and "Cancel". Click Save to persist without running an apply:

```python
page.click("button:has-text('Save changes')")
# or for a new stack:
page.click("button:has-text('Create')")
page.wait_for_load_state("networkidle")
# Verify we landed on the stack detail page
page.wait_for_selector('text="Stack Information"', timeout=10000)
```

### Timing Notes

- Step 1 → 2 transition is slow when the schema has many variables — allow up to 20 seconds
- Step 2 → 3 transition is usually fast (< 5 seconds)
- After Save/Create, ORM redirects to the stack detail page and may show a brief loading spinner

---

## Common Failure Modes

| Symptom | Likely Cause | Fix |
|---|---|---|
| Compartment treeitem not found | Compartment list still loading | Add `wait_for_timeout(1000)` after opening dropdown |
| Variable form empty on Step 2 | Schema failed to parse (zip corrupt or wrong format) | Re-upload the zip; verify schema.yaml is present at root |
| "Next" button disabled on Step 1 | Required field missing (usually stack name or zip) | Fill all required fields before clicking Next |
| Iframe content not accessible | Cross-origin iframe — JS eval blocked | Use CDP approach from `cdp-file-upload.md` |
| Region menu not found | OCI Console loaded in a different layout | Check for `[aria-label="Region"]` or look for header nav elements |
