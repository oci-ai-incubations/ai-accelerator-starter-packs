# PaaS RAG UI Tests

18 tests executed via **agent-browser** in a **single browser session** with **screenshot evidence at each step**. Execute in order — collection creation and document upload must complete before chat/citation tests.

**MANDATORY:** Execute ALL tests in order. If a test fails, record the failure, reload the page, and continue. Do NOT skip any test.

**No authentication required.**

**Two pages:** `/` (Chat with collections sidebar), `/settings` (Settings)

---

## Session Setup

```bash
EVIDENCE_DIR="/tmp/paas-rag-evidence-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$EVIDENCE_DIR"
# AGENT_BROWSER_SESSION is inherited from the calling /testing-pack session (see CRITICAL RULE #5 in /testing-pack/SKILL.md).
BASE_URL="$STARTER_PACK_URL"
agent-browser --headed --ignore-https-errors open "$BASE_URL"
agent-browser wait --load networkidle
agent-browser wait 3000
```

---

## Execution Order

| # | ID | Test | Page | P | Type | Timeout |
|---|---|---|---|---|---|---|
| 1 | PU-1 | Header renders | `/` | P0 | smoke | 30s |
| 2 | PU-2 | Collections sidebar visible | `/` | P0 | smoke | 30s |
| 3 | PU-3 | Empty chat state | `/` | P0 | smoke | 30s |
| 4 | PU-4 | Create collection modal | `/` | P0 | e2e | 30s |
| 5 | PU-5 | Create collection with embedding model | `/` | P0 | e2e | 60s |
| 6 | PU-6 | Collection appears in sidebar | `/` | P0 | smoke | 60s |
| 7 | PU-7 | Open collection drawer | `/` | P0 | e2e | 30s |
| 8 | PU-8 | Upload document via drawer | `/` | P0 | e2e | **3min** |
| 9 | PU-9 | Close collection drawer | `/` | P1 | smoke | 30s |
| 10 | PU-10 | Select collection for chat | `/` | P0 | e2e | 30s |
| 11 | PU-11 | Send RAG chat message | `/` | P0 | e2e | **3min** |
| 12 | PU-12 | Streaming response renders | `/` | P0 | smoke | 30s |
| 13 | PU-13 | View inline citations | `/` | P0 | e2e | 30s |
| 14 | PU-14 | Chat without collection | `/` | P1 | e2e | **2min** |
| 15 | PU-15 | Documents modal — view and manage | `/` | P1 | e2e | 30s |
| 16 | PU-16 | Settings page — navigation and model config | `/settings` | P1 | e2e | 30s |
| 17 | PU-17 | Settings — reset to defaults | `/settings` | P1 | e2e | 30s |
| 18 | PU-18 | Delete test collection | `/` | P1 | e2e | 30s |

---

## Critical Context

### Chat page layout
The chat page (`/`) has a sidebar + main area layout:
- **Left sidebar:** CollectionsSidebar with search input, collection list (checkboxes for multi-select), "New Collection" button at bottom
- **Right main area:** Chat messages area (empty state with Oracle sparkle animation, or message bubbles) + message input at bottom

### Collection selection
Collections are selected via checkboxes (multi-select). Selected collections appear as "Searching in:" badges above the message input. When no collection is selected, the chat still works (pure LLM mode without RAG).

### Streaming chat
Chat responses stream via SSE. A typing indicator (3 bouncing dots) shows during response generation. Users can click "Stop" to abort streaming mid-response.

### Citations
After a RAG response, inline citation footnotes appear as numbered references (e.g., `[1]`, `[2]`). Each footnote has a "Download" button to get the source file and/or a "Source" button for URL citations.

### File upload is async
Document upload goes through stages: uploading → attaching → indexing → completed. The drawer shows progress bars and status per file. Indexing may take seconds to minutes depending on file size.

### Dark theme
The app uses a dark Oracle-branded theme (#191919 primary, #C74634 oracle red). Account for dark backgrounds in visual checks.

---

## Test Details

### PU-1: Header Renders (P0 smoke, 30s)

- **Page:** `/`
- **Selector:** Oracle logo, title text, navigation buttons
- **Interaction:**
  1. `agent-browser snapshot -i` — identify header elements (logo img, "Chat" button, "Settings" button/icon)
  2. Verify Oracle logo, "Chat" nav button, and "Settings" nav button/icon are present in the snapshot
- **Verify:**
  - Oracle logo is visible (img element)
  - "Chat" navigation button is visible and active
  - "Settings" navigation button/icon is visible in header
- **Evidence:** `agent-browser screenshot "$EVIDENCE_DIR/PU-01-header-renders.png"`

### PU-2: Collections Sidebar Visible (P0 smoke, 30s)

- **Page:** `/`
- **Selector:** Left sidebar panel with collection list
- **Interaction:**
  1. `agent-browser snapshot -i` — identify sidebar elements (search input, "New Collection" button, collection list area)
  2. Verify sidebar, search input, and "New Collection" button are present in the snapshot
- **Verify:**
  - Sidebar is visible (left side of page)
  - Search input for filtering collections is present
  - "New Collection" button is visible at the bottom of the sidebar
  - Collections list area is present (may be empty on fresh deploy with empty state message)
- **Evidence:** `agent-browser screenshot "$EVIDENCE_DIR/PU-02-sidebar-visible.png"`

### PU-3: Empty Chat State (P0 smoke, 30s)

- **Page:** `/`
- **Selector:** Chat messages area when no messages exist
- **Interaction:**
  1. `agent-browser snapshot -i` — identify chat area elements (welcome text, sparkle icon, message input, send button)
  2. Verify welcome message, input textarea, and send button are present in the snapshot
- **Verify:**
  - Welcome message "Welcome to OracleNet" or similar greeting text is visible
  - Oracle sparkle animation/icon is visible
  - Message input textarea is visible at the bottom
  - Send button is visible (disabled when input is empty)
- **Evidence:** `agent-browser screenshot "$EVIDENCE_DIR/PU-03-empty-chat.png"`

### PU-4: Create Collection Modal (P0 e2e, 30s)

- **Page:** `/`
- **Selector:** "New Collection" button, modal dialog
- **Interaction:**
  1. `agent-browser snapshot -i` — find the "New Collection" button ref
  2. Click "New Collection" to open the modal (via evaluate — BUG-025 workaround):
     `agent-browser evaluate --stdin <<'EOF'`
     `Array.from(document.querySelectorAll('button, a, [role="button"]')).find(el => (el.textContent || '').trim() === 'New Collection' || el.getAttribute('aria-label') === 'New Collection')?.click();`
     `EOF`
  3. `agent-browser wait 1000`
  4. `agent-browser snapshot -i` — verify modal contents (name input, embedding model dropdown, dimensions input, metadata fields, Cancel/Create buttons)
- **Verify:**
  - Modal dialog appears with "Create Collection" or similar heading
  - Collection name text input is visible (required)
  - Embedding Model dropdown is visible (required)
  - Embedding Dimensions number input is visible (required)
  - Optional metadata fields are visible (Purpose, Source, Content Type)
  - "Add Custom Field" button is visible
  - "Cancel" and "Create Collection" buttons are visible
- **Dismiss:** Click "Cancel" to close the modal before PU-5:
  1. Click "Cancel" (via evaluate — BUG-025 workaround):
     `agent-browser evaluate --stdin <<'EOF'`
     `Array.from(document.querySelectorAll('button, a, [role="button"]')).find(el => (el.textContent || '').trim() === 'Cancel' || el.getAttribute('aria-label') === 'Cancel')?.click();`
     `EOF`
  2. `agent-browser wait 500`
- **Evidence:** `agent-browser screenshot "$EVIDENCE_DIR/PU-04-create-modal.png"`

### PU-5: Create Collection with Embedding Model (P0 e2e, 60s)

- **Page:** `/`
- **Selector:** "New Collection" button, modal form fields
- **Interaction:**
  1. `agent-browser snapshot -i` — find "New Collection" button ref
  2. Click "New Collection" to open modal (via evaluate — BUG-025 workaround):
     `agent-browser evaluate --stdin <<'EOF'`
     `Array.from(document.querySelectorAll('button, a, [role="button"]')).find(el => (el.textContent || '').trim() === 'New Collection' || el.getAttribute('aria-label') === 'New Collection')?.click();`
     `EOF`
  3. `agent-browser wait 1000`
  4. `agent-browser snapshot -i` — find form field refs (name input, embedding model dropdown, dimensions input, purpose input, create button)
  5. `agent-browser fill @<name-input-ref> "ui_test_collection"` — enter collection name
  6. Click the embedding model dropdown to open it (via evaluate — BUG-025 workaround):
     `agent-browser evaluate --stdin <<'EOF'`
     `Array.from(document.querySelectorAll('button, a, [role="button"], [role="combobox"]')).find(el => /embedding model/i.test((el.textContent || '') + ' ' + (el.getAttribute('aria-label') || '')))?.click();`
     `EOF`
  7. `agent-browser wait 500`
  8. `agent-browser snapshot -i` — find available model options
  9. Click the first model option (via evaluate — BUG-025 workaround):
     `agent-browser evaluate --stdin <<'EOF'`
     `document.querySelectorAll('[role="option"]')[0]?.click();`
     `EOF`
  10. Optionally: `agent-browser fill @<purpose-input-ref> "testing"` — fill in purpose
  11. `agent-browser snapshot -i` — verify form is filled and "Create Collection" button is enabled
  12. Click "Create Collection" to submit (via evaluate — BUG-025 workaround):
      `agent-browser evaluate --stdin <<'EOF'`
      `Array.from(document.querySelectorAll('button, a, [role="button"]')).find(el => (el.textContent || '').trim() === 'Create Collection' || el.getAttribute('aria-label') === 'Create Collection')?.click();`
      `EOF`
  13. `agent-browser wait 2000` — wait for modal to close and success toast
  14. `agent-browser snapshot -i` — verify modal closed and toast appeared
- **Verify:**
  - Collection name input accepts text
  - Embedding model dropdown populates with options (from `/v1/models`)
  - "Create Collection" button becomes enabled after required fields are filled
  - Clicking "Create Collection" triggers submission
  - Success toast notification appears
  - Modal closes after successful creation
- **Evidence:** `agent-browser screenshot "$EVIDENCE_DIR/PU-05-collection-created.png"`

### PU-6: Collection Appears in Sidebar (P0 smoke, 60s)

- **Page:** `/`
- **Selector:** Collection list in sidebar
- **Interaction:**
  1. `agent-browser snapshot -i` — look for "ui_test_collection" in the sidebar
  2. If not found, reload and re-check:
     - `agent-browser reload`
     - `agent-browser wait --load networkidle`
     - `agent-browser wait 2000`
     - `agent-browser snapshot -i`
- **Verify:**
  - "ui_test_collection" appears in the sidebar collection list
  - Collection item has a checkbox for selection
  - Collection item has a chevron/details button (hover to reveal)
- **Note:** If the collection doesn't appear immediately, reload the page. The list fetches from `/v1/vector_stores`.
- **Evidence:** `agent-browser screenshot "$EVIDENCE_DIR/PU-06-collection-in-sidebar.png"`

### PU-7: Open Collection Drawer (P0 e2e, 30s)

- **Page:** `/`
- **Selector:** Chevron/details button on "ui_test_collection" item
- **Interaction:**
  1. `agent-browser snapshot -i` — find the "ui_test_collection" item ref
  2. `agent-browser hover @<collection-item-ref>` — hover to reveal the chevron button
  3. `agent-browser wait 500`
  4. `agent-browser snapshot -i` — find the revealed chevron/details button ref
  5. Click the chevron/details button on the collection to open the drawer (via evaluate — BUG-025 workaround):
     `agent-browser evaluate --stdin <<'EOF'`
     `var item = Array.from(document.querySelectorAll('[data-collection-name="ui_test_collection"], li, [role="listitem"]')).find(el => (el.textContent || '').includes('ui_test_collection')); (item && item.querySelector('[aria-label*="detail" i], [aria-label*="chevron" i], [aria-label*="open" i], button:last-of-type'))?.click();`
     `EOF`
  6. `agent-browser wait 1000`
  7. `agent-browser snapshot -i` — verify drawer contents
- **Verify:**
  - Collection drawer slides in from the right with a backdrop overlay
  - Close button (X) is visible
  - Document count card is visible (showing 0 documents initially)
  - Metadata tags section is visible (shows "purpose: testing" if set in PU-5)
  - "Upload Documents" button is visible
  - "Delete Collection" button is visible (red/danger style)
- **Evidence:** `agent-browser screenshot "$EVIDENCE_DIR/PU-07-collection-drawer.png"`

### PU-8: Upload Document via Drawer (P0 e2e, 3min timeout)

- **Page:** `/` (collection drawer open from PU-7)
- **Selector:** "Upload Documents" button, file input, upload controls
- **Interaction:**
  1. `agent-browser snapshot -i` — find "Upload Documents" button ref
  2. Click "Upload Documents" to switch to upload view (via evaluate — BUG-025 workaround):
     `agent-browser evaluate --stdin <<'EOF'`
     `Array.from(document.querySelectorAll('button, a, [role="button"]')).find(el => (el.textContent || '').trim() === 'Upload Documents' || el.getAttribute('aria-label') === 'Upload Documents')?.click();`
     `EOF`
  3. `agent-browser wait 1000`
  4. `agent-browser snapshot -i` — find file input ref in the drag-and-drop zone
  5. Create a test file: `echo "This is a test document for PaaS RAG UI testing. It contains information about retrieval augmented generation." > /tmp/test_document.txt`
  6. `agent-browser upload @<file-input-ref> /tmp/test_document.txt` — upload the test file
  7. `agent-browser wait 1000`
  8. `agent-browser snapshot -i` — verify file appears in list with "pending" status, find "Upload" button ref
  9. Click "Upload" to start the upload (via evaluate — BUG-025 workaround):
     `agent-browser evaluate --stdin <<'EOF'`
     `Array.from(document.querySelectorAll('button, a, [role="button"]')).find(el => (el.textContent || '').trim() === 'Upload' || el.getAttribute('aria-label') === 'Upload')?.click();`
     `EOF`
  10. Poll for completion (up to 3 minutes):
      - `agent-browser wait 5000`
      - `agent-browser snapshot -i` — check for "completed" status (green checkmark)
      - Repeat until status shows "completed" or timeout
- **Verify:**
  - Upload view shows drag-and-drop zone with accepted formats (.txt, .pdf, .doc, .docx, .md)
  - File appears in list after selection
  - Progress bar shows during upload
  - Status transitions through stages (may see uploading, attaching, indexing, completed)
  - File reaches "completed" status (green checkmark or similar indicator)
- **CRITICAL:** File indexing is async. After upload, the status will poll every 2 seconds. Wait for the file to reach "completed" state. This may take 30-120 seconds. Use a polling loop with `wait 5000` + `snapshot -i` to check status.
- **Evidence:** `agent-browser screenshot "$EVIDENCE_DIR/PU-08-document-uploaded.png"`

### PU-9: Close Collection Drawer (P1 smoke, 30s)

- **Page:** `/` (collection drawer open)
- **Selector:** Close button (X) on the drawer, or back chevron
- **Interaction:**
  1. `agent-browser snapshot -i` — find close button (X) ref
  2. Click the drawer close (X) button (via evaluate — BUG-025 workaround):
     `agent-browser evaluate --stdin <<'EOF'`
     `(document.querySelector('[role="dialog"] [aria-label="Close" i], [role="complementary"] [aria-label="Close" i], aside [aria-label="Close" i]') || Array.from(document.querySelectorAll('button, a, [role="button"]')).find(el => (el.textContent || '').trim() === 'Close' || (el.getAttribute('aria-label') || '').toLowerCase() === 'close'))?.click();`
     `EOF`
  3. `agent-browser wait 500`
  4. `agent-browser snapshot -i` — verify drawer is closed
- **Verify:**
  - Drawer closes with slide-out animation
  - Chat area returns to full width
  - Sidebar and chat input are accessible again
- **Note:** **Always close the drawer before proceeding** — an open drawer blocks interaction with elements behind it.
- **Evidence:** `agent-browser screenshot "$EVIDENCE_DIR/PU-09-drawer-closed.png"`

### PU-10: Select Collection for Chat (P0 e2e, 30s)

- **Page:** `/`
- **Selector:** Checkbox on "ui_test_collection" item in sidebar
- **Interaction:**
  1. `agent-browser snapshot -i` — find the checkbox ref on the "ui_test_collection" item
  2. Click the "ui_test_collection" checkbox to select the collection (via evaluate — BUG-025 workaround):
     `agent-browser evaluate --stdin <<'EOF'`
     `var row = Array.from(document.querySelectorAll('li, tr, [role="listitem"], [role="row"], label')).find(el => (el.textContent || '').includes('ui_test_collection')); (row && (row.querySelector('input[type="checkbox"], [role="checkbox"]') || row))?.click();`
     `EOF`
  3. `agent-browser wait 500`
  4. `agent-browser snapshot -i` — verify selection state and "Searching in:" badge
- **Verify:**
  - Checkbox shows selected state (checked)
  - "Searching in:" badge appears above the message input showing "ui_test_collection"
  - Message input placeholder or state may change to indicate RAG mode
- **Evidence:** `agent-browser screenshot "$EVIDENCE_DIR/PU-10-collection-selected.png"`

### PU-11: Send RAG Chat Message (P0 e2e, 3min timeout)

- **Page:** `/`
- **Selector:** Chat input textarea, Send button
- **Interaction:**
  1. `agent-browser snapshot -i` — verify "ui_test_collection" badge is visible, find chat input ref
  2. Click the chat input to focus it (via evaluate — BUG-025 workaround):
     `agent-browser evaluate --stdin <<'EOF'`
     `(document.querySelector('textarea, [role="textbox"], input[type="text"]'))?.focus();`
     `EOF`
  3. `agent-browser fill @<chat-input-ref> "What is in the uploaded document?"` — type the message
  4. `agent-browser snapshot -i` — find the Send button ref (should now be enabled)
  5. Click "Send" to send the message (via evaluate — BUG-025 workaround):
     `agent-browser evaluate --stdin <<'EOF'`
     `Array.from(document.querySelectorAll('button, a, [role="button"]')).find(el => (el.textContent || '').trim() === 'Send' || el.getAttribute('aria-label') === 'Send')?.click();`
     `EOF`
  6. Poll for response completion (up to 3 minutes):
     - `agent-browser wait 5000`
     - `agent-browser snapshot -i` — check for assistant response (look for bot message bubble, typing indicator gone)
     - Repeat until assistant response appears and streaming completes, or timeout
- **Verify:**
  - User message appears in the chat (right-aligned, with User icon)
  - Typing indicator appears (3 bouncing dots)
  - Assistant response appears (left-aligned, with Bot icon) with non-empty text
  - Typing indicator disappears when response completes
  - Response contains markdown-formatted text
- **CRITICAL:** LLM response with RAG retrieval may take 30-120 seconds. Wait patiently. Use a polling loop with `wait 5000` + `snapshot -i`. Do NOT click Send again while streaming.
- **Evidence:** `agent-browser screenshot "$EVIDENCE_DIR/PU-11-rag-chat-response.png"`

### PU-12: Streaming Response Renders (P0 smoke, 30s)

- **Page:** `/` (after PU-11 response completed)
- **Selector:** Assistant message bubble
- **Interaction:**
  1. `agent-browser snapshot -i` — inspect the completed assistant response from PU-11
  2. `agent-browser get text @<assistant-message-ref>` — get the response text content
- **Verify:**
  - Assistant message contains readable text (not empty, not error)
  - Text is rendered as formatted markdown content
  - Message bubble has correct styling (left-aligned, oracle-red-tinted background)
  - No error message (red background with AlertCircle icon)
- **Evidence:** `agent-browser screenshot "$EVIDENCE_DIR/PU-12-streaming-response.png"`

### PU-13: View Inline Citations (P0 e2e, 30s)

- **Page:** `/`
- **Selector:** Citation footnotes in the assistant message
- **Interaction:**
  1. `agent-browser snapshot -i` — look for numbered footnote references (e.g., `[1]`, `[2]`) in the assistant response
  2. If footnotes are present, look for "Download" button refs next to each footnote
  3. If URL citations are present, look for expandable "Source" button refs
- **Verify:**
  - Citation footnotes are visible as numbered references in the response text
  - Each footnote shows the source filename
  - "Download" button is visible for file citations
- **Note:** If no citations appear, the RAG query may not have returned citations. Record as conditional pass and continue.
- **Evidence:** `agent-browser screenshot "$EVIDENCE_DIR/PU-13-inline-citations.png"`

### PU-14: Chat Without Collection (P1 e2e, 2min timeout)

- **Page:** `/`
- **Selector:** Collection checkbox, chat input, Send button
- **Interaction:**
  1. `agent-browser snapshot -i` — find the checkbox ref on "ui_test_collection"
  2. Click the "ui_test_collection" checkbox to deselect (via evaluate — BUG-025 workaround):
     `agent-browser evaluate --stdin <<'EOF'`
     `var row = Array.from(document.querySelectorAll('li, tr, [role="listitem"], [role="row"], label')).find(el => (el.textContent || '').includes('ui_test_collection')); (row && (row.querySelector('input[type="checkbox"], [role="checkbox"]') || row))?.click();`
     `EOF`
  3. `agent-browser wait 500`
  4. `agent-browser snapshot -i` — verify no "Searching in:" badges remain
  5. Click the chat input to focus it (via evaluate — BUG-025 workaround):
     `agent-browser evaluate --stdin <<'EOF'`
     `(document.querySelector('textarea, [role="textbox"], input[type="text"]'))?.focus();`
     `EOF`
  6. `agent-browser fill @<chat-input-ref> "What is retrieval augmented generation?"` — type the message
  7. `agent-browser snapshot -i` — find Send button ref
  8. Click "Send" to send the message (via evaluate — BUG-025 workaround):
     `agent-browser evaluate --stdin <<'EOF'`
     `Array.from(document.querySelectorAll('button, a, [role="button"]')).find(el => (el.textContent || '').trim() === 'Send' || el.getAttribute('aria-label') === 'Send')?.click();`
     `EOF`
  9. Poll for response completion (up to 2 minutes):
     - `agent-browser wait 5000`
     - `agent-browser snapshot -i` — check for assistant response
     - Repeat until assistant response appears and streaming completes, or timeout
- **Verify:**
  - Message sends successfully even without collections selected
  - Assistant responds with text about RAG (pure LLM mode, no retrieval)
  - No citation footnotes on this response (knowledge base not used)
- **Evidence:** `agent-browser screenshot "$EVIDENCE_DIR/PU-14-chat-no-collection.png"`

### PU-15: Documents Modal — View and Manage (P1 e2e, 30s)

- **Page:** `/`
- **Selector:** Collection drawer → document count card → Documents modal
- **Interaction:**
  1. `agent-browser snapshot -i` — find the "ui_test_collection" item ref
  2. `agent-browser hover @<collection-item-ref>` — hover to reveal the chevron button
  3. `agent-browser wait 500`
  4. `agent-browser snapshot -i` — find the revealed chevron/details button ref
  5. Click the chevron/details button on the collection to open the drawer (via evaluate — BUG-025 workaround):
     `agent-browser evaluate --stdin <<'EOF'`
     `var item = Array.from(document.querySelectorAll('[data-collection-name="ui_test_collection"], li, [role="listitem"]')).find(el => (el.textContent || '').includes('ui_test_collection')); (item && item.querySelector('[aria-label*="detail" i], [aria-label*="chevron" i], [aria-label*="open" i], button:last-of-type'))?.click();`
     `EOF`
  6. `agent-browser wait 1000`
  7. `agent-browser snapshot -i` — find the document count card ref (should show >=1 document)
  8. Click the document count card to open the documents modal (via evaluate — BUG-025 workaround):
     `agent-browser evaluate --stdin <<'EOF'`
     `Array.from(document.querySelectorAll('[role="dialog"] *, aside *, [role="complementary"] *')).find(el => /document/i.test(el.textContent || '') && /\d+/.test(el.textContent || '') && (el.matches('button, a, [role="button"], [data-clickable], .card, [class*="card" i]') || el.closest('button, a, [role="button"], [data-clickable], .card, [class*="card" i]')))?.click();`
     `EOF`
  9. `agent-browser wait 1000`
  10. `agent-browser snapshot -i` — verify documents modal contents (search input, table, pagination)
- **Verify:**
  - Documents modal appears with search input
  - Table with columns: ID, Created At, Attributes, Action
  - At least 1 document row visible (the uploaded test file)
  - Each row has Download and Delete action buttons
  - Pagination controls are visible (Previous/Next)
- **Dismiss:** Close the modal, then close the collection drawer:
  1. `agent-browser snapshot -i` — find modal close button (X) ref
  2. Click the modal close (X) button (via evaluate — BUG-025 workaround):
     `agent-browser evaluate --stdin <<'EOF'`
     `(document.querySelector('[role="dialog"] [aria-label="Close" i], .modal [aria-label="Close" i], [data-state="open"] [aria-label="Close" i]'))?.click();`
     `EOF`
  3. `agent-browser wait 500`
  4. `agent-browser snapshot -i` — find drawer close button (X) ref
  5. Click the drawer close (X) button (via evaluate — BUG-025 workaround):
     `agent-browser evaluate --stdin <<'EOF'`
     `(document.querySelector('aside [aria-label="Close" i], [role="complementary"] [aria-label="Close" i]') || Array.from(document.querySelectorAll('button, [role="button"]')).find(el => (el.getAttribute('aria-label') || '').toLowerCase() === 'close'))?.click();`
     `EOF`
  6. `agent-browser wait 500`
- **Evidence:** `agent-browser screenshot "$EVIDENCE_DIR/PU-15-documents-modal.png"`

### PU-16: Settings Page — Navigation and Model Config (P1 e2e, 30s)

- **Page:** Navigate from `/` to `/settings`
- **Selector:** Settings button/icon in the header
- **Interaction:**
  1. `agent-browser snapshot -i` — find the Settings button/icon ref in the header
  2. Click "Settings" to navigate to the settings page (via evaluate — BUG-025 workaround):
     `agent-browser evaluate --stdin <<'EOF'`
     `(Array.from(document.querySelectorAll('header a, header button, header [role="button"]')).find(el => /settings/i.test((el.textContent || '') + ' ' + (el.getAttribute('aria-label') || ''))) || Array.from(document.querySelectorAll('a, button, [role="button"]')).find(el => (el.textContent || '').trim() === 'Settings' || el.getAttribute('aria-label') === 'Settings'))?.click();`
     `EOF`
  3. `agent-browser wait --url "**/settings"` — wait for URL change
  4. `agent-browser wait --load networkidle`
  5. `agent-browser snapshot -i` — verify settings page loaded, find "Model Configuration" nav item ref
  6. Click "Model Configuration" (via evaluate — BUG-025 workaround):
     `agent-browser evaluate --stdin <<'EOF'`
     `Array.from(document.querySelectorAll('button, a, [role="button"], [role="tab"], [role="menuitem"]')).find(el => (el.textContent || '').trim() === 'Model Configuration' || el.getAttribute('aria-label') === 'Model Configuration')?.click();`
     `EOF`
  7. `agent-browser wait 500`
  8. `agent-browser snapshot -i` — verify model config section contents
- **Verify:**
  - URL changes to `/settings`
  - Settings sidebar navigation is visible with sections: RAG Configuration, Model Configuration, Advanced
  - Model Configuration section shows:
    - LLM Model dropdown with available models
    - Temperature slider (0-2 range, step 0.1)
    - Instructions textarea (system prompt)
  - "Reset to Defaults" button is visible at the bottom of the sidebar
- **Evidence:** `agent-browser screenshot "$EVIDENCE_DIR/PU-16-settings-model-config.png"`

### PU-17: Settings — Reset to Defaults (P1 e2e, 30s)

- **Page:** `/settings`
- **Selector:** Temperature slider, "Reset to Defaults" button
- **Interaction:**
  1. `agent-browser snapshot -i` — find temperature slider ref and "Reset to Defaults" button ref
  2. Note the current temperature value displayed
  3. Click the temperature slider to change its value (via evaluate — BUG-025 workaround):
     `agent-browser evaluate --stdin <<'EOF'`
     `var slider = document.querySelector('input[type="range"][name*="temperature" i], input[type="range"][aria-label*="temperature" i], input[type="range"]'); if (slider) { slider.focus(); var min = parseFloat(slider.min || '0'); var max = parseFloat(slider.max || '1'); var step = parseFloat(slider.step || '0.1'); var cur = parseFloat(slider.value || '0'); var next = Math.min(max, Math.max(min, cur + step * 2)); slider.value = String(next); slider.dispatchEvent(new Event('input', { bubbles: true })); slider.dispatchEvent(new Event('change', { bubbles: true })); }`
     `EOF`
  4. `agent-browser wait 500`
  5. `agent-browser snapshot -i` — verify the displayed value changed
  6. Click "Reset to Defaults" (via evaluate — BUG-025 workaround):
     `agent-browser evaluate --stdin <<'EOF'`
     `Array.from(document.querySelectorAll('button, a, [role="button"]')).find(el => (el.textContent || '').trim() === 'Reset to Defaults' || el.getAttribute('aria-label') === 'Reset to Defaults')?.click();`
     `EOF`
  7. `agent-browser wait 1000`
  8. `agent-browser snapshot -i` — verify values returned to defaults
- **Verify:**
  - Temperature slider is interactive and updates the displayed value
  - After reset, temperature returns to default (0.7)
  - Instructions textarea returns to default ("You are a helpful assistant" or similar)
- **Evidence:** `agent-browser screenshot "$EVIDENCE_DIR/PU-17-settings-reset.png"`

### PU-18: Delete Test Collection (P1 e2e, 30s) — CLEANUP

- **Page:** `/` (navigate back from settings)
- **Selector:** Collection drawer for "ui_test_collection"
- **Interaction:**
  1. `agent-browser snapshot -i` — find "Chat" button or Oracle logo ref in header
  2. Click "Chat" (or the Oracle logo) to navigate back to `/` (via evaluate — BUG-025 workaround):
     `agent-browser evaluate --stdin <<'EOF'`
     `(Array.from(document.querySelectorAll('header a, header button, header [role="button"]')).find(el => (el.textContent || '').trim() === 'Chat' || el.getAttribute('aria-label') === 'Chat' || (el.getAttribute('href') || '') === '/'))?.click();`
     `EOF`
  3. `agent-browser wait --load networkidle`
  4. `agent-browser wait 1000`
  5. `agent-browser snapshot -i` — find the "ui_test_collection" item ref
  6. `agent-browser hover @<collection-item-ref>` — hover to reveal chevron
  7. `agent-browser wait 500`
  8. `agent-browser snapshot -i` — find chevron/details button ref
  9. Click the chevron/details button on the collection to open the drawer (via evaluate — BUG-025 workaround):
     `agent-browser evaluate --stdin <<'EOF'`
     `var item = Array.from(document.querySelectorAll('[data-collection-name="ui_test_collection"], li, [role="listitem"]')).find(el => (el.textContent || '').includes('ui_test_collection')); (item && item.querySelector('[aria-label*="detail" i], [aria-label*="chevron" i], [aria-label*="open" i], button:last-of-type'))?.click();`
     `EOF`
  10. `agent-browser wait 1000`
  11. `agent-browser snapshot -i` — find "Delete Collection" button ref (red/danger)
  12. Click "Delete Collection" (via evaluate — BUG-025 workaround):
      `agent-browser evaluate --stdin <<'EOF'`
      `Array.from(document.querySelectorAll('button, a, [role="button"]')).find(el => (el.textContent || '').trim() === 'Delete Collection' || el.getAttribute('aria-label') === 'Delete Collection')?.click();`
      `EOF`
  13. `agent-browser dialog accept` — accept the confirm() dialog
  14. `agent-browser wait 1000`
  15. `agent-browser snapshot -i` — verify collection removed from sidebar
- **Verify:**
  - Browser confirmation dialog appears
  - After confirmation, collection disappears from the sidebar
  - Drawer closes
  - Success toast notification may appear
- **Note:** agent-browser auto-accepts `alert` and `beforeunload` dialogs by default, but `confirm()` dialogs need explicit `agent-browser dialog accept`. The correct pattern is: click Delete, then immediately run `agent-browser dialog accept` to handle the confirm() dialog, then verify deletion.
- **Evidence:** `agent-browser screenshot "$EVIDENCE_DIR/PU-18-collection-deleted.png"`

---

## Teardown

```bash
agent-browser screenshot "$EVIDENCE_DIR/PU-final-state.png"
agent-browser close
echo "Evidence screenshots saved to: $EVIDENCE_DIR"
ls -la "$EVIDENCE_DIR"
```
