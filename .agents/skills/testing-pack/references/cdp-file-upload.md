# CDP File Upload for ORM Hidden File Inputs

## Overview

OCI Resource Manager's "Upload Stack" UI uses a hidden `<input type="file">` element inside an iframe. Standard browser automation (Playwright `setInputFiles`, drag-and-drop, clicking labels) does not work because:

1. The file input is hidden (`display: none` or `visibility: hidden`)
2. It lives inside a sandboxed iframe, not the top-level frame
3. ORM's iframe may have a different origin than the console page

The only reliable workaround is to bypass the browser automation layer entirely and use the **Chrome DevTools Protocol (CDP)** directly via a WebSocket connection, which allows setting file inputs regardless of visibility or cross-frame boundaries.

**Freedom level: LOW — follow this sequence exactly.**

## CRITICAL: Do NOT click Browse before CDP upload

Clicking the Browse/file-input button opens a native OS file dialog that **blocks CDP from interacting with the file input**. If a file dialog is open, it must be dismissed first (user presses Escape).

Run CDP upload **directly** — no click on the file input button beforehand.

After CDP upload, verify the file name appears in the UI. If it still shows "Drop a .zip file Browse" with no file, the upload failed. Retry CDP or ask the user to select the file manually via Browse.

---

## Prerequisites

- `agent-browser` must be running (provides the CDP endpoint)
- `websocket-client` Python package must be installed:
  ```bash
  pip install websocket-client
  ```
- The zip file to upload must exist at a known absolute path on disk

---

## 3-Step Process

### Step 1 — Get the CDP Port

Get the CDP port from agent-browser:

```bash
CDP_URL=$(agent-browser --session-name oci get cdp-url)
CDP_PORT=$(echo "$CDP_URL" | sed -n 's|.*127.0.0.1:\([0-9]*\).*|\1|p')
echo "CDP_PORT: $CDP_PORT"
```

### Step 2 — Get the Page WebSocket URL

List open pages and find the ORM tab's WebSocket debugger URL:

```bash
# List all open pages
curl -s http://localhost:${CDP_PORT}/json/list

# The response is a JSON array of page objects. Find the one whose "url" matches
# the ORM console URL (e.g., contains "resource-manager" or "cloud.oracle.com").
# Extract its "webSocketDebuggerUrl" field.

WS_URL=$(curl -s http://localhost:${CDP_PORT}/json/list | \
  python3 -c "
import json, sys
pages = json.load(sys.stdin)
for p in pages:
    if 'resource-manager' in p.get('url', '') or 'oracle.com' in p.get('url', ''):
        print(p['webSocketDebuggerUrl'])
        break
")
echo "WebSocket URL: ${WS_URL}"
```

### Step 3 — Run the Upload Script

```bash
python3 .claude/skills/testing-pack/scripts/cdp_upload.py "${WS_URL}" "/absolute/path/to/stack.zip"
```

Expected output on success:
```
Connecting to CDP...
Enabling DOM...
Getting document...
Searching for file input (pierce=True)...
Found file input node: <nodeId>
Setting file input files...
SUCCESS: file input set to /absolute/path/to/stack.zip
```

If the script prints `ERROR: No input[type="file"] found` and exits 1, the ORM page may not have rendered the upload dialog yet — wait for the upload UI to be fully visible and retry.

---

## Why This Works

### `suppress_origin=True`

The WebSocket handshake to the CDP endpoint normally includes an `Origin` header matching the caller. Chrome's CDP server rejects connections whose Origin does not match a trusted origin. Setting `suppress_origin=True` in the `websocket-client` library omits the `Origin` header entirely, which CDP accepts without validation — bypassing the cross-origin check.

### `pierce=True` in `DOM.getDocument`

By default, `DOM.getDocument` only returns the DOM tree of the top-level frame. Setting `pierce=True` tells CDP to traverse into all shadow roots and iframe `contentDocument` trees as part of the single document snapshot. This makes it possible to locate nodes inside cross-origin iframes without needing to switch execution contexts.

### `DOM.setFileInputFiles`

This CDP command sets the file(s) on a file input element by node ID, bypassing all browser security restrictions that normally prevent programmatic file setting (the same restrictions that block `input.files = ...` from JavaScript). It works on hidden inputs and inputs inside iframes. It does not trigger the OS file picker.

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| `ConnectionRefusedError` on port 9222 | agent-browser is not running or is on a different port |
| `ERROR: No input[type="file"] found` | Upload dialog not yet rendered; wait and retry |
| Script hangs at "Connecting to CDP..." | Chrome is busy; check for modal dialogs or alerts blocking the page |
| File appears selected in UI but stack creation fails | Verify the zip path is absolute and the file exists on disk |
