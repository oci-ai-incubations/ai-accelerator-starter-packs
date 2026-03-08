# Enterprise RAG UI Tests

18 tests executed via Playwright in a **single browser context** with **continuous video recording**. Execute in order — collection creation and document upload must complete before chat/citation tests.

**MANDATORY:** Execute ALL tests in order. If a test fails, record the failure, refresh the page, and continue. Do NOT skip any test.

**No authentication required.**

**Three pages:** `/` (Chat), `/collections/new` (New Collection), `/settings` (Settings)

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
- **Selector:** Oracle logo (`img[src*="oracle"]` or `img[alt*="Oracle"]`), title text "Enterprise Knowledge Chat Agent"
- **Interaction:** None (visual check)
- **Verify:**
  - Oracle logo is visible
  - Title text containing "Enterprise" or "Knowledge" or "Chat" is visible
  - Notification bell icon is visible in header
  - Settings button/icon is visible in header

### EU-2: Collection Sidebar Visible (P0 smoke, 30s)

- **Page:** `/`
- **Selector:** Left sidebar panel with collection list
- **Interaction:** None (visual check)
- **Verify:**
  - Sidebar is visible (left side of page)
  - Search input for filtering collections is present
  - "Add New Collection" button is visible at the bottom of the sidebar
  - Collections list area is present (may be empty on fresh deploy)

### EU-3: Navigate to New Collection (P0 e2e, 30s)

- **Page:** Start at `/`, navigate to `/collections/new`
- **Selector:** "Add New Collection" button in sidebar
- **Interaction:** Click "Add New Collection" button
- **Verify:**
  - URL changes to `/collections/new`
  - Collection name input field is visible
  - File upload zone (drag-and-drop area) is visible
  - "Create Collection" button is visible

### EU-4: Create Collection with File Upload (P0 e2e, 3min timeout)

- **Page:** `/collections/new`
- **Selector:** Name input, file upload zone, Create Collection button
- **Interaction:**
  1. Type "ui_test_collection" in the collection name input
  2. Upload a test file — create a small `.txt` file via the file input (use `page.setInputFiles()` on the file input element)
  3. Click "Create Collection"
  4. Wait for navigation back to `/` or success indication
  5. Watch the notification bell for ingestion status updates
- **Verify:**
  - Collection name input accepts text (spaces auto-replaced with underscores)
  - File appears in the file list after upload
  - "Create Collection" button click triggers submission
  - Notification bell shows pending task notification
  - Task eventually completes (notification updates to success)
- **CRITICAL:** Ingestion is async. After clicking "Create Collection", the page may navigate back to `/`. Monitor the notification bell — a notification should appear showing ingestion progress. Wait for it to show "FINISHED" or similar success state. This may take 1-3 minutes.
- **Note:** To upload a file in Playwright, use `page.setInputFiles('input[type="file"]', ...)` with a Buffer containing test text.

### EU-5: Collection Appears in Sidebar (P0 smoke, 60s)

- **Page:** `/`
- **Selector:** Collection list in sidebar
- **Interaction:** Wait for the collection list to refresh (may need to reload page)
- **Verify:**
  - "ui_test_collection" appears in the sidebar collection list
  - Collection shows entity count (>=1 after ingestion completes)
- **Note:** If the collection doesn't appear immediately, reload the page. The collection list fetches from `/api/collections`.

### EU-6: Select Collection (P0 e2e, 30s)

- **Page:** `/`
- **Selector:** Collection item for "ui_test_collection" in sidebar
- **Interaction:** Click on the "ui_test_collection" item in the sidebar
- **Verify:**
  - Collection item shows selected state (highlighted/active styling)
  - Collection chip appears above the chat input area

### EU-7: Collection Chips Display (P1 smoke, 30s)

- **Page:** `/`
- **Selector:** Chip/tag components above the chat input
- **Interaction:** None (visual check — collection was selected in EU-6)
- **Verify:**
  - A chip showing "ui_test_collection" is visible above the message input
  - Chip has a remove/close button (X icon)

### EU-8: Send Chat Message — RAG Query (P0 e2e, 3min timeout)

- **Page:** `/`
- **Selector:** Chat input textarea, Send button
- **Interaction:**
  1. Ensure "ui_test_collection" is still selected (chip visible)
  2. Click the chat input textarea
  3. Type "What is in the uploaded document?"
  4. Click Send button (or press Enter)
  5. Wait for the assistant response to complete
- **Verify:**
  - User message appears in the chat (right-aligned, colored background)
  - Streaming indicator appears (animated dots)
  - Assistant response appears (left-aligned) with non-empty text
  - Streaming indicator disappears when response completes
- **CRITICAL:** LLM response with RAG retrieval may take 30-120 seconds. Wait patiently. Update banner: "EU-8: Waiting for RAG response... Xs elapsed". Do NOT click Send again while streaming.

### EU-9: Streaming Response Renders (P0 smoke, 30s)

- **Page:** `/` (after EU-8 response completed)
- **Selector:** Assistant message bubble
- **Interaction:** None (verify the completed response from EU-8)
- **Verify:**
  - Assistant message contains readable text (not empty, not error)
  - Text is rendered as formatted content (markdown rendering)
  - Message bubble has correct styling (left-aligned, light background)

### EU-10: View Citations (P0 e2e, 30s)

- **Page:** `/`
- **Selector:** "View Citations" or "Citations" button on the assistant message
- **Interaction:** Click the citations button on the most recent assistant message
- **Verify:**
  - A citation button is visible on the assistant message (e.g., "View N Citations")
  - Clicking it opens a right-side drawer/panel
  - Drawer shows "Source Citations" or similar heading
- **Note:** If no citations button is visible, the RAG query may not have returned citations. Record as conditional pass and continue.

### EU-11: Citation Drawer Content (P1 e2e, 30s)

- **Page:** `/` (citation drawer open from EU-10)
- **Selector:** Citation cards inside the drawer
- **Interaction:** Expand a citation card if collapsed
- **Verify:**
  - >=1 citation card visible
  - Each card shows: confidence score badge, source file name, document type
  - Expanding a card shows text content from the ingested document
- **Note:** If drawer was not opened (no citations in EU-10), skip this test and mark as N/A.

### EU-12: Close Citation Drawer (P1 smoke, 30s)

- **Page:** `/` (citation drawer open)
- **Selector:** Close button on the citation drawer
- **Interaction:** Click the close button (X) on the drawer
- **Verify:**
  - Drawer closes
  - Chat area returns to full width
- **Note:** **Always close the drawer before proceeding** — an open drawer blocks interaction with elements behind it.

### EU-13: Chat Without Collection (P1 e2e, 2min timeout)

- **Page:** `/`
- **Selector:** Collection chips, chat input, Send button
- **Interaction:**
  1. Deselect all collections — click the X on the "ui_test_collection" chip (or click the collection in sidebar to toggle off)
  2. Verify no collection chips remain above the input
  3. Type "What is retrieval augmented generation?" in the chat input
  4. Click Send
  5. Wait for response
- **Verify:**
  - Message sends successfully even without collections selected
  - Assistant responds with text about RAG (pure LLM mode, no retrieval)
  - No citations button on this response (knowledge base not used)

### EU-14: Collection Drawer — View Documents (P1 e2e, 30s)

- **Page:** `/`
- **Selector:** "More" button (vertical dots / kebab menu) on the "ui_test_collection" item in sidebar
- **Interaction:**
  1. Find the "ui_test_collection" in the sidebar
  2. Click the "More" button (three dots) on that collection item
  3. A drawer/side panel opens showing the collection details
- **Verify:**
  - Collection drawer opens (right side, ~50vw)
  - Collection name heading is visible
  - Documents list shows >=1 document (the uploaded test file)
  - "Add Source" button is visible
  - "Delete Collection" button is visible
- **Dismiss:** Close the drawer before continuing.

### EU-15: Settings Page — Navigation (P1 smoke, 30s)

- **Page:** Navigate from `/` to `/settings`
- **Selector:** Settings button/icon in the header
- **Interaction:** Click the Settings button in the header
- **Verify:**
  - URL changes to `/settings`
  - Settings sidebar navigation is visible (left side) with sections: RAG Configuration, Feature Toggles, Model Configuration, Endpoint Configuration, Advanced Settings
  - Settings content area is visible (right side)

### EU-16: Settings — RAG Configuration (P1 e2e, 30s)

- **Page:** `/settings`
- **Selector:** RAG Configuration section (should be default active)
- **Interaction:**
  1. Verify RAG Configuration section is visible
  2. Locate the Temperature slider
  3. Interact with the slider (drag or click to change value)
- **Verify:**
  - Temperature slider is visible with current value displayed
  - Top P slider is visible
  - Confidence Score Threshold slider is visible
  - Vector DB Top K input is visible
  - Max Tokens input is visible
  - Changing the Temperature slider updates the displayed value

### EU-17: Settings — Feature Toggles (P1 e2e, 30s)

- **Page:** `/settings`
- **Selector:** "Feature Toggles" in the settings sidebar navigation
- **Interaction:**
  1. Click "Feature Toggles" in the settings sidebar
  2. Locate the feature toggle switches
  3. Click one toggle (e.g., "Enable Reranker")
  4. If a confirmation warning modal appears, dismiss it (click Cancel or confirm)
- **Verify:**
  - Feature Toggles section shows >=4 toggle switches
  - Toggle labels visible: "Enable Reranker", "Include Citations", "Use Guardrails", "Query Rewriting"
  - Clicking a toggle triggers a warning modal (FeatureWarningModal)
  - **Dismiss the modal** before continuing (click Cancel to avoid changing settings)

### EU-18: Delete Test Collection (P1 e2e, 30s) — CLEANUP

- **Page:** `/` (navigate back from settings)
- **Selector:** Collection drawer for "ui_test_collection"
- **Interaction:**
  1. Navigate back to `/` (click the Oracle logo or title in header)
  2. Open the collection drawer for "ui_test_collection" (click the "More" button)
  3. Click "Delete Collection" button
  4. Confirm deletion in the confirmation modal
- **Verify:**
  - Confirmation modal appears asking to confirm deletion
  - After confirmation, collection disappears from the sidebar
  - Drawer closes
- **Note:** This cleans up the test collection. If the collection drawer can't be opened, try refreshing the page first.
