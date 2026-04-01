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

```bash
agent-browser --session-name oci snapshot -i 2>&1 | grep "Region menu"
# Output: button "Region menu, active region is US East (Ashburn)" [ref=e10]
```

### How to change the region

```bash
# Click the region menu button
agent-browser --session-name oci click @<region-menu-ref>
agent-browser --session-name oci wait 1000
# Take snapshot to find target region menuitem
agent-browser --session-name oci snapshot -i 2>&1 | grep -i "<target-region>"
# Click the target region
agent-browser --session-name oci click @<region-menuitem-ref>
agent-browser --session-name oci wait --load networkidle
```

Or navigate directly via URL (more reliable):
```bash
agent-browser --session-name oci open "https://cloud.oracle.com/resourcemanager/stacks?region=<region>"
```

---

## Compartment Selection

The compartment picker in ORM is a tree widget with a search box. It is unreliable to click — radio buttons and treeitems often don't respond to agent-browser clicks.

### Primary approach: URL parameter (recommended)

Navigate directly with the compartment OCID in the URL. This is the most reliable method:

```bash
agent-browser --session-name oci open "https://cloud.oracle.com/resourcemanager/stacks?region=<region>&compartmentId=<compartment_ocid>"
agent-browser --session-name oci wait --load networkidle
agent-browser --session-name oci wait 3000
```

Get the compartment OCID beforehand via OCI CLI:
```bash
oci iam compartment list --compartment-id-in-subtree true --all \
  --query "data[?name=='<compartment_name>'].id | [0]" --raw-output
```

### Fallback: search + click treeitem

If you don't have the compartment OCID, try the tree widget. This is fragile:

```bash
# Click the compartment selector button (look for "Select to expand options" in snapshot)
agent-browser --session-name oci click @<selector-ref>
agent-browser --session-name oci wait 1000
# Type compartment name in the search textbox
agent-browser --session-name oci fill @<search-textbox-ref> "<compartment-name>"
agent-browser --session-name oci wait 2000
# Click the treeitem (NOT the radio button — click the treeitem itself)
agent-browser --session-name oci click @<treeitem-ref>
agent-browser --session-name oci wait --load networkidle
```

**Known issue:** The radio buttons inside treeitems often don't register clicks. If the heading still shows the old compartment after clicking, fall back to the URL approach.

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
