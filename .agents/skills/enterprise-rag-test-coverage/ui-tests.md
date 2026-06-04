# Enterprise RAG UI Tests

18 tests executed via **agent-browser** in a single browser session with screenshot evidence at each step. Execute in order — collection creation and document upload must complete before chat/citation tests.

**MANDATORY:** Execute ALL tests in order. If a test fails, record the failure, refresh the page (`agent-browser open "$BASE_URL"`), and continue. Do NOT skip any test.

**No authentication required.**

**Three pages:** `/` (Chat), `/collections/new` (New Collection), `/settings` (Settings)

---

## Session Setup

```bash
EVIDENCE_DIR="/tmp/erag-evidence-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$EVIDENCE_DIR"
SESSION="erag-test-$(date +%s)"
BASE_URL="$STARTER_PACK_URL"

# Self-signed certs on nip.io domains — must use --ignore-https-errors
agent-browser --headed --session $SESSION --ignore-https-errors open "$BASE_URL"
agent-browser --session $SESSION wait --load networkidle
agent-browser --session $SESSION wait 3000
```

All subsequent commands use `--session $SESSION`. For brevity, examples below omit the flag — **always include it**.

---

## Execution Order

| # | ID | Test | Page | P | Type | Timeout |
|---|---|---|---|---|---|---|
| 1 | EU-1 | Header renders | `/` | P0 | smoke | 30s |
| 2 | EU-2 | Collection sidebar visible | `/` | P0 | smoke | 30s |
| 3 | EU-3 | Navigate to New Collection | `/collections/new` | P0 | e2e | 30s |
| 4 | EU-4 | Create collection with file | `/collections/new` | P0 | e2e | **3min** |
| 5 | EU-5 | Collection appears in sidebar | `/` | P0 | smoke | 60s |
| 6 | EU-6 | Select collection | `/` | P0 | e2e | 30s |
| 7 | EU-7 | Collection chips display | `/` | P1 | smoke | 30s |
| 8 | EU-8 | Send chat message (RAG) | `/` | P0 | e2e | **3min** |
| 9 | EU-9 | Streaming response renders | `/` | P0 | smoke | 30s |
| 10 | EU-10 | View citations | `/` | P0 | e2e | 30s |
| 11 | EU-11 | Citation drawer content | `/` | P1 | e2e | 30s |
| 12 | EU-12 | Close citation drawer | `/` | P1 | smoke | 30s |
| 13 | EU-13 | Chat without collection | `/` | P1 | e2e | **2min** |
| 14 | EU-14 | Collection drawer — view documents | `/` | P1 | e2e | 30s |
| 15 | EU-15 | Settings page — navigation | `/settings` | P1 | smoke | 30s |
| 16 | EU-16 | Settings — RAG configuration | `/settings` | P1 | e2e | 30s |
| 17 | EU-17 | Settings — feature toggles | `/settings` | P1 | e2e | 30s |
| 18 | EU-18 | Delete test collection | `/` | P1 | e2e | 30s |

---

## Critical Context

### Chat page layout
The chat page (`/`) has a 12-column grid:
- **Left 3 columns:** CollectionList sidebar with search, collection items, "Add New Collection" button
- **Right 9 columns:** Chat area (messages + input) with results/citation drawer

### Collection selection
Collections are toggled via click (multi-select). Selected collections appear as chips above the message input. When exactly 1 collection is selected, a filter bar may appear.

### Streaming chat
Chat responses stream via SSE. A streaming indicator (animated dots) shows during response generation. Users can stop streaming mid-response.

### Citations
After a RAG response, a "View N Citations" button appears. Clicking it opens a right-side drawer (75vw wide) showing citation cards with scores, source names, and expandable content.

### Ingestion is async
Document upload returns a `task_id`. A notification bell in the header shows ingestion progress. The TaskPoller polls every 5 seconds until the task completes.

---

## Test Details

### EU-1: Header Renders (P0 smoke, 30s)

- **Page:** `/`
- **Steps:**
  1. `agent-browser snapshot -i` — look for Oracle logo, title text, notification bell, settings icon
- **Verify:**
  - [ ] Oracle logo is visible (img with "oracle" or "Oracle" in src/alt)
  - [ ] Title text containing "Enterprise" or "Knowledge" or "Chat" is visible
  - [ ] Notification bell icon is visible in header
  - [ ] Settings button/icon is visible in header
- **Evidence:** `agent-browser screenshot "$EVIDENCE_DIR/EU-01-header.png"`

### EU-2: Collection Sidebar Visible (P0 smoke, 30s)

- **Page:** `/`
- **Steps:**
  1. `agent-browser snapshot -i` — look for sidebar panel, search input, "Add New Collection" button
- **Verify:**
  - [ ] Sidebar is visible (left side of page)
  - [ ] Search input for filtering collections is present
  - [ ] "Add New Collection" button is visible at the bottom of the sidebar
  - [ ] Collections list area is present (may be empty on fresh deploy)
- **Evidence:** `agent-browser screenshot "$EVIDENCE_DIR/EU-02-sidebar.png"`

### EU-3: Navigate to New Collection (P0 e2e, 30s)

- **Page:** Start at `/`, navigate to `/collections/new`
- **Steps:**
  1. `agent-browser snapshot -i` — find the "Add New Collection" button ref
  2. `agent-browser click @ref` — click it
  3. `agent-browser wait --url "**/collections/new"`
  4. `agent-browser snapshot -i` — verify new page elements
- **Verify:**
  - [ ] URL changes to `/collections/new` (`agent-browser get url`)
  - [ ] Collection name input field is visible
  - [ ] File upload zone (drag-and-drop area) is visible
  - [ ] "Create Collection" button is visible
- **Evidence:** `agent-browser screenshot "$EVIDENCE_DIR/EU-03-new-collection.png"`

### EU-4: Create Collection with File Upload (P0 e2e, 3min timeout)

- **Page:** `/collections/new`
- **Steps:**
  1. `agent-browser snapshot -i` — find name input, file input, Create button refs
  2. `agent-browser fill @name_ref "ui_test_collection"` — type collection name
  3. Create a test file:
     ```bash
     echo "This is a test document for Enterprise RAG UI testing. It contains information about cloud infrastructure and AI workloads." > /tmp/test_document.txt
     ```
  4. `agent-browser upload @file_ref /tmp/test_document.txt` — upload the test file
  5. `agent-browser snapshot -i` — verify file appears in file list
  6. Find and click the "Create Collection" button ref
  7. `agent-browser wait --load networkidle`
  8. Watch the notification bell for ingestion status — poll with snapshots every 15s for up to 3 minutes:
     ```bash
     agent-browser snapshot -i  # Look for notification bell with status
     ```
- **Verify:**
  - [ ] Collection name input accepts text
  - [ ] File appears in the file list after upload
  - [ ] "Create Collection" button click triggers submission
  - [ ] Notification bell shows pending task notification
  - [ ] Task eventually completes (notification updates to success/finished)
- **CRITICAL:** Ingestion is async. After clicking "Create Collection", the page may navigate back to `/`. Monitor the notification bell — a notification should appear showing ingestion progress. Wait for it to show "FINISHED" or similar success state. This may take 1-3 minutes.
- **Evidence:** `agent-browser screenshot "$EVIDENCE_DIR/EU-04-collection-created.png"`

### EU-5: Collection Appears in Sidebar (P0 smoke, 60s)

- **Page:** `/`
- **Steps:**
  1. `agent-browser open "$BASE_URL"` — navigate to chat page (may already be there)
  2. `agent-browser wait --load networkidle`
  3. `agent-browser snapshot -i` — look for "ui_test_collection" in the sidebar
  4. If not visible, `agent-browser reload` and re-snapshot
- **Verify:**
  - [ ] "ui_test_collection" appears in the sidebar collection list
  - [ ] Collection shows entity count (>=1 after ingestion completes)
- **Evidence:** `agent-browser screenshot "$EVIDENCE_DIR/EU-05-collection-in-sidebar.png"`

### EU-6: Select Collection (P0 e2e, 30s)

- **Page:** `/`
- **Steps:**
  1. `agent-browser snapshot -i` — find "ui_test_collection" item ref in sidebar
  2. `agent-browser click @ref` — click the collection item
  3. `agent-browser snapshot -i` — verify selected state
- **Verify:**
  - [ ] Collection item shows selected state (highlighted/active styling)
  - [ ] Collection chip appears above the chat input area
- **Evidence:** `agent-browser screenshot "$EVIDENCE_DIR/EU-06-collection-selected.png"`

### EU-7: Collection Chips Display (P1 smoke, 30s)

- **Page:** `/`
- **Steps:**
  1. `agent-browser snapshot -i` — look for chip/tag components above the chat input
- **Verify:**
  - [ ] A chip showing "ui_test_collection" is visible above the message input
  - [ ] Chip has a remove/close button (X icon)
- **Evidence:** `agent-browser screenshot "$EVIDENCE_DIR/EU-07-chips.png"`

### EU-8: Send Chat Message — RAG Query (P0 e2e, 3min timeout)

- **Page:** `/`
- **Steps:**
  1. `agent-browser snapshot -i` — verify "ui_test_collection" chip is still visible, find chat input textarea ref
  2. `agent-browser click @textarea_ref` — focus the chat input
  3. `agent-browser fill @textarea_ref "What is in the uploaded document?"` — type the query
  4. `agent-browser snapshot -i` — find the Send button ref
  5. `agent-browser click @send_ref` — send the message
  6. Wait for the response — poll with snapshots every 15s for up to 3 minutes:
     ```bash
     agent-browser wait 15000
     agent-browser snapshot -i  # Look for assistant response text
     ```
  7. Wait until streaming indicator disappears and full response is visible
- **Verify:**
  - [ ] User message appears in the chat
  - [ ] Streaming indicator appears (animated dots)
  - [ ] Assistant response appears with non-empty text
  - [ ] Streaming indicator disappears when response completes
- **CRITICAL:** LLM response with RAG retrieval may take 30-120 seconds. Wait patiently. Do NOT click Send again while streaming.
- **Evidence:** `agent-browser screenshot "$EVIDENCE_DIR/EU-08-rag-response.png"`

### EU-9: Streaming Response Renders (P0 smoke, 30s)

- **Page:** `/` (after EU-8 response completed)
- **Steps:**
  1. `agent-browser snapshot -i` — examine the assistant message content
  2. `agent-browser get text body` — get full page text to verify response content
- **Verify:**
  - [ ] Assistant message contains readable text (not empty, not error)
  - [ ] Text is rendered as formatted content (markdown rendering)
  - [ ] Message bubble has correct styling (left-aligned)
- **Evidence:** `agent-browser screenshot "$EVIDENCE_DIR/EU-09-response-rendered.png"`

### EU-10: View Citations (P0 e2e, 30s)

- **Page:** `/`
- **Steps:**
  1. `agent-browser snapshot -i` — find "View Citations" or "Citations" button ref on the assistant message
  2. `agent-browser click @citations_ref` — open the citation drawer
  3. `agent-browser wait 2000` — wait for drawer animation
  4. `agent-browser snapshot -i` — verify drawer content
- **Verify:**
  - [ ] A citation button is visible on the assistant message (e.g., "View N Citations")
  - [ ] Clicking it opens a right-side drawer/panel
  - [ ] Drawer shows "Source Citations" or similar heading
- **Note:** If no citations button is visible, the RAG query may not have returned citations. Record as conditional pass and continue.
- **Evidence:** `agent-browser screenshot "$EVIDENCE_DIR/EU-10-citations-open.png"`

### EU-11: Citation Drawer Content (P1 e2e, 30s)

- **Page:** `/` (citation drawer open from EU-10)
- **Steps:**
  1. `agent-browser snapshot -i` — examine citation cards inside the drawer
  2. If citation cards are collapsed, click a card ref to expand it
  3. `agent-browser snapshot -i` — verify expanded content
- **Verify:**
  - [ ] >=1 citation card visible
  - [ ] Each card shows: confidence score badge, source file name, document type
  - [ ] Expanding a card shows text content from the ingested document
- **Note:** If drawer was not opened (no citations in EU-10), skip this test and mark as N/A.
- **Evidence:** `agent-browser screenshot "$EVIDENCE_DIR/EU-11-citation-content.png"`

### EU-12: Close Citation Drawer (P1 smoke, 30s)

- **Page:** `/` (citation drawer open)
- **Steps:**
  1. `agent-browser snapshot -i` — find the close button (X) on the citation drawer
  2. `agent-browser click @close_ref` — close the drawer
  3. If no close button found, try: `agent-browser press Escape`
  4. `agent-browser snapshot -i` — verify drawer is closed
- **Verify:**
  - [ ] Drawer closes
  - [ ] Chat area returns to full width
- **Note:** **Always close the drawer before proceeding** — an open drawer blocks interaction with elements behind it.
- **Evidence:** `agent-browser screenshot "$EVIDENCE_DIR/EU-12-drawer-closed.png"`

### EU-13: Chat Without Collection (P1 e2e, 2min timeout)

- **Page:** `/`
- **Steps:**
  1. `agent-browser snapshot -i` — find the X button on the "ui_test_collection" chip
  2. `agent-browser click @chip_x_ref` — remove the chip to deselect all collections
  3. `agent-browser snapshot -i` — verify no collection chips remain above the input
  4. `agent-browser fill @textarea_ref "What is retrieval augmented generation?"` — type query
  5. `agent-browser snapshot -i` — find and click Send button
  6. `agent-browser click @send_ref`
  7. Wait for response — poll with snapshots every 15s for up to 2 minutes
- **Verify:**
  - [ ] Message sends successfully even without collections selected
  - [ ] Assistant responds with text about RAG (pure LLM mode, no retrieval)
  - [ ] No citations button on this response (knowledge base not used)
- **Evidence:** `agent-browser screenshot "$EVIDENCE_DIR/EU-13-no-collection-chat.png"`

### EU-14: Collection Drawer — View Documents (P1 e2e, 30s)

- **Page:** `/`
- **Steps:**
  1. `agent-browser snapshot -i` — find the "More" button (vertical dots / kebab menu) on the "ui_test_collection" item in sidebar
  2. `agent-browser click @more_ref` — open the collection drawer
  3. `agent-browser wait 2000` — wait for drawer animation
  4. `agent-browser snapshot -i` — examine drawer contents
- **Verify:**
  - [ ] Collection drawer opens (right side, ~50vw)
  - [ ] Collection name heading is visible
  - [ ] Documents list shows >=1 document (the uploaded test file)
  - [ ] "Add Source" button is visible
  - [ ] "Delete Collection" button is visible
- **Dismiss:** Close the drawer before continuing — find the close/X button and click it, or `agent-browser press Escape`.
- **Evidence:** `agent-browser screenshot "$EVIDENCE_DIR/EU-14-collection-drawer.png"`

### EU-15: Settings Page — Navigation (P1 smoke, 30s)

- **Page:** Navigate from `/` to `/settings`
- **Steps:**
  1. `agent-browser snapshot -i` — find the Settings button/icon in the header
  2. `agent-browser click @settings_ref` — navigate to settings
  3. `agent-browser wait --url "**/settings"`
  4. `agent-browser snapshot -i` — verify settings page structure
- **Verify:**
  - [ ] URL changes to `/settings` (`agent-browser get url`)
  - [ ] Settings sidebar navigation is visible (left side) with sections: RAG Configuration, Feature Toggles, Model Configuration, Endpoint Configuration, Advanced Settings
  - [ ] Settings content area is visible (right side)
- **Evidence:** `agent-browser screenshot "$EVIDENCE_DIR/EU-15-settings.png"`

### EU-16: Settings — RAG Configuration (P1 e2e, 30s)

- **Page:** `/settings`
- **Steps:**
  1. `agent-browser snapshot -i` — verify RAG Configuration section is visible (should be default active)
  2. Find the Temperature slider ref
  3. `agent-browser click @slider_ref` — interact with the slider to change value
  4. `agent-browser snapshot -i` — check that the displayed value updated
- **Verify:**
  - [ ] Temperature slider is visible with current value displayed
  - [ ] Top P slider is visible
  - [ ] Confidence Score Threshold slider is visible
  - [ ] Vector DB Top K input is visible
  - [ ] Max Tokens input is visible
  - [ ] Changing the Temperature slider updates the displayed value
- **Evidence:** `agent-browser screenshot "$EVIDENCE_DIR/EU-16-rag-config.png"`

### EU-17: Settings — Feature Toggles (P1 e2e, 30s)

- **Page:** `/settings`
- **Steps:**
  1. `agent-browser snapshot -i` — find "Feature Toggles" nav item in the settings sidebar
  2. `agent-browser click @feature_toggles_ref` — navigate to Feature Toggles section
  3. `agent-browser snapshot -i` — find toggle switches
  4. `agent-browser click @toggle_ref` — click one toggle (e.g., "Enable Reranker")
  5. If a confirmation/warning modal appears:
     - `agent-browser snapshot -i` — find Cancel button in the modal
     - `agent-browser click @cancel_ref` — dismiss the modal without changing settings
- **Verify:**
  - [ ] Feature Toggles section shows >=4 toggle switches
  - [ ] Toggle labels visible: "Enable Reranker", "Include Citations", "Use Guardrails", "Query Rewriting"
  - [ ] Clicking a toggle triggers a warning modal (FeatureWarningModal)
  - [ ] **Modal dismissed** before continuing (click Cancel to avoid changing settings)
- **Evidence:** `agent-browser screenshot "$EVIDENCE_DIR/EU-17-feature-toggles.png"`

### EU-18: Delete Test Collection (P1 e2e, 30s) — CLEANUP

- **Page:** `/` (navigate back from settings)
- **Steps:**
  1. `agent-browser open "$BASE_URL"` — navigate back to chat page
  2. `agent-browser wait --load networkidle`
  3. `agent-browser snapshot -i` — find "ui_test_collection" in sidebar, then its "More" button (kebab menu)
  4. `agent-browser click @more_ref` — open the collection drawer
  5. `agent-browser wait 2000`
  6. `agent-browser snapshot -i` — find "Delete Collection" button
  7. `agent-browser click @delete_ref` — click delete
  8. `agent-browser snapshot -i` — find confirmation modal, click Confirm/OK
  9. `agent-browser click @confirm_ref`
  10. `agent-browser wait 2000`
  11. `agent-browser snapshot -i` — verify collection is gone from sidebar
- **Verify:**
  - [ ] Confirmation modal appears asking to confirm deletion
  - [ ] After confirmation, collection disappears from the sidebar
  - [ ] Drawer closes
- **Note:** This cleans up the test collection. If the collection drawer can't be opened, try `agent-browser reload` first.
- **Evidence:** `agent-browser screenshot "$EVIDENCE_DIR/EU-18-collection-deleted.png"`

---

## Teardown

```bash
agent-browser screenshot "$EVIDENCE_DIR/EU-final-state.png"
agent-browser --session $SESSION close
```

## Results Template

```
ENTERPRISE RAG UI TEST RESULTS
Date:  <YYYY-MM-DD>
URL:   <BASE_URL>

EU-1:  Header renders              — PASS/FAIL
EU-2:  Collection sidebar visible  — PASS/FAIL
EU-3:  Navigate to New Collection  — PASS/FAIL
EU-4:  Create collection with file — PASS/FAIL
EU-5:  Collection appears in sidebar — PASS/FAIL
EU-6:  Select collection           — PASS/FAIL
EU-7:  Collection chips display    — PASS/FAIL
EU-8:  Send chat message (RAG)     — PASS/FAIL
EU-9:  Streaming response renders  — PASS/FAIL
EU-10: View citations              — PASS/FAIL
EU-11: Citation drawer content     — PASS/FAIL/N/A
EU-12: Close citation drawer       — PASS/FAIL
EU-13: Chat without collection     — PASS/FAIL
EU-14: Collection drawer — view docs — PASS/FAIL
EU-15: Settings page — navigation  — PASS/FAIL
EU-16: Settings — RAG configuration — PASS/FAIL
EU-17: Settings — feature toggles  — PASS/FAIL
EU-18: Delete test collection      — PASS/FAIL

Evidence: <EVIDENCE_DIR>
Issues:
  - <description, screenshot reference, suspected cause>
```
