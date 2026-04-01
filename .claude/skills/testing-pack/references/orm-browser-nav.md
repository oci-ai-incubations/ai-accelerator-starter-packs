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

ORM content is inside an `<iframe>` titled "Content body". Agent-browser auto-inlines iframe content in snapshots, so refs work across iframe boundaries.

### Scoping snapshots to iframe content

```bash
# Snapshot only the iframe content (filters out top nav chrome)
agent-browser --session-name oci snapshot -i -s "iframe"
```

Refs from the scoped snapshot (e.g., `@e25`) work directly with click/fill commands — no frame switching needed.

### Evaluating JavaScript inside the iframe

Use `agent-browser eval` and access the iframe's document via `contentDocument`:

```bash
agent-browser --session-name oci eval --stdin <<'EVALEOF'
var iframe = document.querySelector('iframe');
var doc = iframe.contentDocument || iframe.contentWindow.document;
doc.querySelector('input[type="file"]').id;
EVALEOF
```

For cross-origin iframes, `contentDocument` will be null. Use CDP directly instead (see `cdp-file-upload.md`).

---

## ORM Checkbox Toggling

**Known issue:** ORM checkboxes (Deploy Application, Skip Capacity Check, etc.) often don't respond to `agent-browser click` or `agent-browser check` commands. The `check` command sometimes works, but `click` rarely does.

### Recommended approach: JavaScript eval

Toggle checkboxes via JavaScript and dispatch React-compatible events:

```bash
agent-browser --session-name oci eval --stdin <<'EVALEOF'
(function() {
  var iframe = document.querySelector('iframe');
  var doc = iframe.contentDocument || iframe.contentWindow.document;
  var cb = doc.querySelector('input[name="deploy_application"]');
  cb.click();
  cb.dispatchEvent(new Event('change', { bubbles: true }));
  cb.dispatchEvent(new Event('input', { bubbles: true }));
  return 'checked=' + cb.checked;
})();
EVALEOF
```

To find checkbox names, enumerate them:
```bash
agent-browser --session-name oci eval --stdin <<'EVALEOF'
var iframe = document.querySelector('iframe');
var doc = iframe.contentDocument || iframe.contentWindow.document;
var cbs = doc.querySelectorAll('input[type="checkbox"]');
var result = [];
cbs.forEach(function(cb, i) { result.push(i + ': ' + cb.name + ' = ' + cb.checked); });
result.join('\n');
EVALEOF
```

### Fallback: try `check`/`uncheck` first

The `agent-browser check @ref` command works sometimes. Try it first, verify with a snapshot, and fall back to JS eval if it didn't toggle.

---

## CDP File Upload — Critical Rules

1. **Do NOT click the Browse button before CDP upload.** Clicking Browse opens a native OS file dialog that blocks CDP from interacting with the file input. If a file dialog is open, dismiss it first (user presses Cancel/Escape).

2. **Run CDP upload directly** without any click on the file input button. The CDP `DOM.setFileInputFiles` sets the file programmatically — no dialog needed.

3. **Verify the upload worked** by checking the snapshot after CDP upload. If the file name appears next to the Browse button (e.g., `paas_rag-2026-04-01.zip ×`), the upload succeeded. If it still shows "Drop a .zip file Browse" with no file, the upload failed — retry the CDP script.

4. **If CDP upload keeps failing**, ask the user to click Browse in the headed browser and select the file manually. Tell them the file path and wait for confirmation.

---

## Edit Stack Wizard Navigation

The ORM "Edit Stack" wizard has 3 steps:
1. **Stack information** — name, description, zip upload
2. **Configure variables** — all Terraform variables from the schema
3. **Review** — summary before saving

### Step 1 to Step 2

After uploading the zip on Step 1, find and click the Next button:

```bash
agent-browser --session-name oci snapshot -i -s "iframe"  # find Next button ref
agent-browser --session-name oci click @<next-ref>
agent-browser --session-name oci wait --load networkidle
agent-browser --session-name oci wait 5000  # variable form can take several seconds to render
agent-browser --session-name oci snapshot -i -s "iframe"  # verify Step 2 loaded
```

### Step 2 to Step 3

After verifying/filling variables, click Next again:

```bash
agent-browser --session-name oci snapshot -i -s "iframe"  # find Next button ref
agent-browser --session-name oci click @<next-ref>
agent-browser --session-name oci wait --load networkidle
agent-browser --session-name oci wait 3000
```

### Step 3 — Save and Apply

On the Review page, scroll down to find "Run apply" checkbox and "Save changes" button:

```bash
agent-browser --session-name oci scroll down 500
agent-browser --session-name oci snapshot -i -s "iframe"  # find checkbox and save button refs
agent-browser --session-name oci check @<run-apply-ref>
agent-browser --session-name oci wait 500
agent-browser --session-name oci click @<save-changes-ref>
agent-browser --session-name oci wait --load networkidle
agent-browser --session-name oci wait 5000
agent-browser --session-name oci snapshot -i -s "iframe"  # verify job page appeared
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
