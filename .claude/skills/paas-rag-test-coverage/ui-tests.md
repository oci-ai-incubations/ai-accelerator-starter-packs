# PaaS RAG UI Tests

18 tests executed via Playwright in a **single browser context** with **continuous video recording**. Execute in order — collection creation and document upload must complete before chat/citation tests.

**MANDATORY:** Execute ALL tests in order. If a test fails, record the failure, refresh the page, and continue. Do NOT skip any test.

**No authentication required.**

**Two pages:** `/` (Chat with collections sidebar), `/settings` (Settings)

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
- **Interaction:** None (visual check)
- **Verify:**
  - Oracle logo is visible (img element)
  - "Chat" navigation button is visible and active
  - "Settings" navigation button/icon is visible in header

### PU-2: Collections Sidebar Visible (P0 smoke, 30s)

- **Page:** `/`
- **Selector:** Left sidebar panel with collection list
- **Interaction:** None (visual check)
- **Verify:**
  - Sidebar is visible (left side of page)
  - Search input for filtering collections is present
  - "New Collection" button is visible at the bottom of the sidebar
  - Collections list area is present (may be empty on fresh deploy with empty state message)

### PU-3: Empty Chat State (P0 smoke, 30s)

- **Page:** `/`
- **Selector:** Chat messages area when no messages exist
- **Interaction:** None (visual check)
- **Verify:**
  - Welcome message "Welcome to OracleNet" or similar greeting text is visible
  - Oracle sparkle animation/icon is visible
  - Message input textarea is visible at the bottom
  - Send button is visible (disabled when input is empty)

### PU-4: Create Collection Modal (P0 e2e, 30s)

- **Page:** `/`
- **Selector:** "New Collection" button, modal dialog
- **Interaction:**
  1. Click "New Collection" button in sidebar
  2. Verify modal opens
- **Verify:**
  - Modal dialog appears with "Create Collection" or similar heading
  - Collection name text input is visible (required)
  - Embedding Model dropdown is visible (required)
  - Embedding Dimensions number input is visible (required)
  - Optional metadata fields are visible (Purpose, Source, Content Type)
  - "Add Custom Field" button is visible
  - "Cancel" and "Create Collection" buttons are visible
- **Dismiss:** Click "Cancel" to close the modal before PU-5.

### PU-5: Create Collection with Embedding Model (P0 e2e, 60s)

- **Page:** `/`
- **Selector:** "New Collection" button, modal form fields
- **Interaction:**
  1. Click "New Collection" button
  2. Type "ui_test_collection" in the collection name input
  3. Select an embedding model from the dropdown (pick the first available option)
  4. Set embedding dimensions (2048 or use default)
  5. Optionally fill in Purpose: "testing"
  6. Click "Create Collection"
  7. Wait for modal to close and success toast
- **Verify:**
  - Collection name input accepts text
  - Embedding model dropdown populates with options (from `/v1/models`)
  - "Create Collection" button becomes enabled after required fields are filled
  - Clicking "Create Collection" triggers submission
  - Success toast notification appears
  - Modal closes after successful creation

### PU-6: Collection Appears in Sidebar (P0 smoke, 60s)

- **Page:** `/`
- **Selector:** Collection list in sidebar
- **Interaction:** Wait for sidebar to refresh (may need to reload page)
- **Verify:**
  - "ui_test_collection" appears in the sidebar collection list
  - Collection item has a checkbox for selection
  - Collection item has a chevron/details button (hover to reveal)
- **Note:** If the collection doesn't appear immediately, reload the page. The list fetches from `/v1/vector_stores`.

### PU-7: Open Collection Drawer (P0 e2e, 30s)

- **Page:** `/`
- **Selector:** Chevron/details button on "ui_test_collection" item
- **Interaction:**
  1. Hover over the "ui_test_collection" item to reveal the chevron button
  2. Click the chevron/details button
- **Verify:**
  - Collection drawer slides in from the right with a backdrop overlay
  - Close button (X) is visible
  - Document count card is visible (showing 0 documents initially)
  - Metadata tags section is visible (shows "purpose: testing" if set in PU-5)
  - "Upload Documents" button is visible
  - "Delete Collection" button is visible (red/danger style)

### PU-8: Upload Document via Drawer (P0 e2e, 3min timeout)

- **Page:** `/` (collection drawer open from PU-7)
- **Selector:** "Upload Documents" button, file input, upload controls
- **Interaction:**
  1. Click "Upload Documents" button in the drawer
  2. Drawer switches to upload view with drag-and-drop zone
  3. Upload a test file via `page.setInputFiles('input[type="file"]', ...)` with a Buffer containing test text (use `.txt` format)
  4. File appears in the file list with "pending" status
  5. Click "Upload" button
  6. Watch progress: uploading → attaching → indexing → completed
- **Verify:**
  - Upload view shows drag-and-drop zone with accepted formats (.txt, .pdf, .doc, .docx, .md)
  - File appears in list after selection
  - Progress bar shows during upload
  - Status transitions through stages (may see uploading, attaching, indexing, completed)
  - File reaches "completed" status (green checkmark or similar indicator)
- **CRITICAL:** File indexing is async. After upload, the status will poll every 2 seconds. Wait for the file to reach "completed" state. This may take 30-120 seconds.
- **Note:** To upload a file in Playwright, use `page.setInputFiles('input[type="file"]', ...)` with a Buffer containing test text.

### PU-9: Close Collection Drawer (P1 smoke, 30s)

- **Page:** `/` (collection drawer open)
- **Selector:** Close button (X) on the drawer, or back chevron
- **Interaction:** Click the close button (X) or click the backdrop overlay
- **Verify:**
  - Drawer closes with slide-out animation
  - Chat area returns to full width
  - Sidebar and chat input are accessible again
- **Note:** **Always close the drawer before proceeding** — an open drawer blocks interaction with elements behind it.

### PU-10: Select Collection for Chat (P0 e2e, 30s)

- **Page:** `/`
- **Selector:** Checkbox on "ui_test_collection" item in sidebar
- **Interaction:** Click the checkbox on the "ui_test_collection" item
- **Verify:**
  - Checkbox shows selected state (checked)
  - "Searching in:" badge appears above the message input showing "ui_test_collection"
  - Message input placeholder or state may change to indicate RAG mode

### PU-11: Send RAG Chat Message (P0 e2e, 3min timeout)

- **Page:** `/`
- **Selector:** Chat input textarea, Send button
- **Interaction:**
  1. Ensure "ui_test_collection" is still selected (badge visible above input)
  2. Click the chat input textarea
  3. Type "What is in the uploaded document?"
  4. Click Send button (or press Enter)
  5. Wait for the assistant response to complete
- **Verify:**
  - User message appears in the chat (right-aligned, with User icon)
  - Typing indicator appears (3 bouncing dots)
  - Assistant response appears (left-aligned, with Bot icon) with non-empty text
  - Typing indicator disappears when response completes
  - Response contains markdown-formatted text
- **CRITICAL:** LLM response with RAG retrieval may take 30-120 seconds. Wait patiently. Update banner: "PU-11: Waiting for RAG response... Xs elapsed". Do NOT click Send again while streaming.

### PU-12: Streaming Response Renders (P0 smoke, 30s)

- **Page:** `/` (after PU-11 response completed)
- **Selector:** Assistant message bubble
- **Interaction:** None (verify the completed response from PU-11)
- **Verify:**
  - Assistant message contains readable text (not empty, not error)
  - Text is rendered as formatted markdown content
  - Message bubble has correct styling (left-aligned, oracle-red-tinted background)
  - No error message (red background with AlertCircle icon)

### PU-13: View Inline Citations (P0 e2e, 30s)

- **Page:** `/`
- **Selector:** Citation footnotes in the assistant message
- **Interaction:**
  1. Look for numbered footnote references (e.g., `[1]`, `[2]`) in the assistant response
  2. If footnotes are present, look for "Download" button next to each footnote
  3. If URL citations are present, look for expandable "Source" button
- **Verify:**
  - Citation footnotes are visible as numbered references in the response text
  - Each footnote shows the source filename
  - "Download" button is visible for file citations
- **Note:** If no citations appear, the RAG query may not have returned citations. Record as conditional pass and continue.

### PU-14: Chat Without Collection (P1 e2e, 2min timeout)

- **Page:** `/`
- **Selector:** Collection checkbox, chat input, Send button
- **Interaction:**
  1. Deselect all collections — click the checkbox on "ui_test_collection" to uncheck it
  2. Verify no "Searching in:" badges remain above the input
  3. Type "What is retrieval augmented generation?" in the chat input
  4. Click Send
  5. Wait for response
- **Verify:**
  - Message sends successfully even without collections selected
  - Assistant responds with text about RAG (pure LLM mode, no retrieval)
  - No citation footnotes on this response (knowledge base not used)

### PU-15: Documents Modal — View and Manage (P1 e2e, 30s)

- **Page:** `/`
- **Selector:** Collection drawer → document count card → Documents modal
- **Interaction:**
  1. Open the collection drawer for "ui_test_collection" (hover + click chevron)
  2. Click the document count card (should show >=1 document)
  3. Documents modal opens (large modal)
- **Verify:**
  - Documents modal appears with search input
  - Table with columns: ID, Created At, Attributes, Action
  - At least 1 document row visible (the uploaded test file)
  - Each row has Download and Delete action buttons
  - Pagination controls are visible (Previous/Next)
- **Dismiss:** Close the modal (click X or close button), then close the collection drawer.

### PU-16: Settings Page — Navigation and Model Config (P1 e2e, 30s)

- **Page:** Navigate from `/` to `/settings`
- **Selector:** Settings button/icon in the header
- **Interaction:**
  1. Click the Settings button in the header
  2. Verify URL changes to `/settings`
  3. Click "Model Configuration" in the settings sidebar
- **Verify:**
  - URL changes to `/settings`
  - Settings sidebar navigation is visible with sections: RAG Configuration, Model Configuration, Advanced
  - Model Configuration section shows:
    - LLM Model dropdown with available models
    - Temperature slider (0-2 range, step 0.1)
    - Instructions textarea (system prompt)
  - "Reset to Defaults" button is visible at the bottom of the sidebar

### PU-17: Settings — Reset to Defaults (P1 e2e, 30s)

- **Page:** `/settings`
- **Selector:** Temperature slider, "Reset to Defaults" button
- **Interaction:**
  1. Note the current temperature value
  2. Drag or click the temperature slider to change its value
  3. Verify the displayed value changes
  4. Click "Reset to Defaults" button
- **Verify:**
  - Temperature slider is interactive and updates the displayed value
  - After reset, temperature returns to default (0.7)
  - Instructions textarea returns to default ("You are a helpful assistant" or similar)

### PU-18: Delete Test Collection (P1 e2e, 30s) — CLEANUP

- **Page:** `/` (navigate back from settings)
- **Selector:** Collection drawer for "ui_test_collection"
- **Interaction:**
  1. Navigate back to `/` (click "Chat" button or Oracle logo in header)
  2. Open the collection drawer for "ui_test_collection" (hover + click chevron)
  3. Click "Delete Collection" button (red/danger)
  4. Confirm deletion in the browser `confirm()` dialog
- **Verify:**
  - Browser confirmation dialog appears
  - After confirmation, collection disappears from the sidebar
  - Drawer closes
  - Success toast notification may appear
- **Note:** Playwright handles `confirm()` dialogs via `page.on('dialog', d => d.accept())`. Set up the dialog handler BEFORE clicking delete.
