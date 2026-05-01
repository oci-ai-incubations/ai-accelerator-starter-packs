# Document Extractor UI Tests

9 tests executed via **agent-browser** in a **single browser session** with **screenshot evidence at each step**. Execute in order — PDF upload and extraction must complete before download and chat tests.

**MANDATORY:** Execute ALL tests in order. If a test fails, record the failure, reload the page, and continue. Do NOT skip any test.

**No authentication required.**

---

## Session Setup

```bash
EVIDENCE_DIR="/tmp/dox-pack-evidence-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$EVIDENCE_DIR"
SESSION="dox-pack-test-$(date +%s)"
BASE_URL="$STARTER_PACK_URL"
agent-browser --headed --session $SESSION --ignore-https-errors open "$BASE_URL"
agent-browser --session $SESSION wait --load networkidle
agent-browser --session $SESSION wait 3000
```

All subsequent commands use `--session $SESSION --ignore-https-errors`. For brevity, test descriptions omit these flags — always include them.

---

## Execution Order

| # | ID | Test | Page | P | Type | Timeout |
|---|---|---|---|---|---|---|
| 1 | CU-1 | Homepage loads | `/` | P0 | smoke | 30s |
| 2 | CU-2 | Upload contract PDF | `/` | P0 | e2e | 60s |
| 3 | CU-3 | Extraction progress | `/` | P0 | e2e | **15min** |
| 4 | CU-4 | View extraction results | `/` | P0 | smoke | 30s |
| 5 | CU-5 | Download CSV | `/` | P0 | e2e | 30s |
| 6 | CU-6 | Download JSON | `/` | P1 | e2e | 30s |
| 7 | CU-7 | Chat with contract | `/` | P0 | e2e | **3min** |
| 8 | CU-8 | History tab | `/` | P1 | smoke | 30s |
| 9 | CU-9 | Prompt configuration | `/` | P1 | e2e | 30s |

> CU-3 (extraction progress) takes 10-15 minutes. Do NOT skip or timeout early.

---

## Critical Context

### Extraction pipeline timing
The 3-pass extraction pipeline (Qwen3-VL OCR -> Maverick expansion -> validation) takes 10-15 minutes for a typical contract. The UI shows real-time progress updates during this process. Use polling loops with periodic screenshots.

### Frontend proxies to backend
All `/api/*` calls from the frontend are proxied to the dox-backend service. The frontend URL is the `STARTER_PACK_URL`.

### File upload
PDF upload uses a file input or drag-and-drop zone. Only PDF files are accepted. The upload triggers an extraction job immediately.

### Chat requires completed extraction
The RAG chat feature only works after at least one extraction has completed, because the contract data must be ingested into the vector store first.

---

## Test Details

### CU-1: Homepage Loads (P0 smoke, 30s)

- **Page:** `/`
- **Interaction:**
  1. `agent-browser snapshot -i` — look for page title, logo, or heading text identifying the Document Extractor application
  2. Verify the page loaded without error (no blank white screen, no 500 error)
- **Verify:**
  - Application title or logo is visible (e.g., "Document Extractor", "Rate Card Extractor", or similar heading)
  - Upload area or main interface elements are present
  - No error messages or loading spinners stuck indefinitely
- **Evidence:** `agent-browser screenshot "$EVIDENCE_DIR/CU-01-homepage.png"`

### CU-2: Upload Contract PDF (P0 e2e, 60s)

- **Page:** `/`
- **Interaction:**
  1. `agent-browser snapshot -i` — identify the file upload element (file input, drag-and-drop zone, or "Upload" button)
  2. If a file input is found:
     - `agent-browser upload @<file-input-ref> "${TEST_PDF_PATH}"` — upload the test PDF
  3. If a button/drop zone is found instead:
     - `agent-browser click @<upload-button-ref>` — trigger the file picker
     - `agent-browser upload @<file-input-ref> "${TEST_PDF_PATH}"` — upload via the revealed input
  4. `agent-browser wait 3000`
  5. `agent-browser snapshot -i` — verify upload was accepted and extraction started
- **Verify:**
  - File upload is accepted (no "File must be a PDF" error)
  - UI shows extraction has started (progress indicator, "Processing..." status, or job ID displayed)
  - File name of the uploaded PDF appears in the interface
- **Note:** If `TEST_PDF_PATH` is not set, create a minimal test PDF before this step (see CA-3 in api-tests.md for the PDF creation script).
- **Evidence:** `agent-browser screenshot "$EVIDENCE_DIR/CU-02-upload.png"`

### CU-3: Extraction Progress (P0 e2e, 15min timeout)

- **Page:** `/`
- **Interaction:**
  1. After CU-2 triggered extraction, monitor progress in the UI
  2. **Poll for completion** using a loop:
     ```bash
     # Poll every 30 seconds, up to 30 iterations (15 min)
     for i in $(seq 1 30); do
       agent-browser --session $SESSION wait 30000
       agent-browser --session $SESSION snapshot -i
       agent-browser --session $SESSION screenshot "$EVIDENCE_DIR/CU-03-progress-${i}.png"
       # Check snapshot output: if status shows "complete" or results table appears, break
       # If status shows "error", record and break
     done
     ```
  3. Once extraction completes, take a final screenshot
- **Verify:**
  - Progress indicator updates during extraction (not stuck)
  - Extraction eventually reaches "complete" status
  - If extraction shows "error", record the error message and continue to remaining tests
- **CRITICAL — DO NOT SKIP OR TIMEOUT EARLY.** Extraction takes 10-15 minutes due to per-page Qwen3-VL vision OCR. Use a polling loop with `agent-browser wait 30000` + `agent-browser snapshot -i` to monitor progress, taking periodic screenshots.
- **Evidence:** `agent-browser screenshot "$EVIDENCE_DIR/CU-03-complete.png"` (plus periodic progress screenshots from the polling loop)

### CU-4: View Extraction Results (P0 smoke, 30s)

- **Page:** `/`
- **Interaction:**
  1. `agent-browser snapshot -i` — after extraction completes, look for results display (table, CSV preview, or data grid)
  2. If a results tab or section is visible, `agent-browser click @<results-ref>` to navigate to it
  3. `agent-browser snapshot -i` — verify extracted data is displayed
- **Verify:**
  - Extraction results are visible (table rows, data fields, or CSV preview)
  - Row count is displayed and matches extraction output
  - Data includes recognizable fields from the contract (services, rates, categories)
- **Precondition:** CU-3 extraction completed successfully. If extraction failed, this test may show an error state — record it and continue.
- **Evidence:** `agent-browser screenshot "$EVIDENCE_DIR/CU-04-results.png"`

### CU-5: Download CSV (P0 e2e, 30s)

- **Page:** `/`
- **Interaction:**
  1. `agent-browser snapshot -i` — locate the CSV download button (button with "Download CSV", "Export CSV", download icon, or similar)
  2. `agent-browser click @<download-csv-ref>` — trigger the download
  3. `agent-browser wait 3000`
  4. `agent-browser snapshot -i` — verify download was initiated (browser may show download notification or the button state may change)
- **Verify:**
  - Download button is present and clickable
  - Clicking the button initiates a file download (no error)
  - Downloaded file has a `.csv` extension
- **Precondition:** CU-3 extraction completed successfully.
- **Evidence:** `agent-browser screenshot "$EVIDENCE_DIR/CU-05-download-csv.png"`

### CU-6: Download JSON (P1 e2e, 30s)

- **Page:** `/`
- **Interaction:**
  1. `agent-browser snapshot -i` — locate the JSON download button (button with "Download JSON", "Export JSON", or similar)
  2. If a JSON download button is found:
     - `agent-browser click @<download-json-ref>` — trigger the download
     - `agent-browser wait 3000`
  3. `agent-browser snapshot -i` — verify download was initiated
- **Verify:**
  - JSON download button is present (may not exist if preliminary JSON was not generated — mark N/A in that case)
  - If present: clicking the button initiates a file download without error
- **Note:** Preliminary JSON (raw Pass 2 output) may not be available for all extractions. If the button is not visible or returns a 404, mark as N/A, not failure.
- **Evidence:** `agent-browser screenshot "$EVIDENCE_DIR/CU-06-download-json.png"`

### CU-7: Chat with Contract (P0 e2e, 3min timeout)

- **Page:** `/`
- **Interaction:**
  1. `agent-browser snapshot -i` — locate the chat interface (message input, chat panel, or chat tab/page)
  2. If the chat is on a separate page or tab:
     - `agent-browser click @<chat-tab-ref>` or `agent-browser open "$BASE_URL/chat"`
     - `agent-browser wait --load networkidle`
  3. `agent-browser snapshot -i` — identify the message input field and send button
  4. `agent-browser fill @<message-input-ref> "What services and rates are described in this contract?"`
  5. `agent-browser click @<send-button-ref>` — send the message
  6. `agent-browser wait 30000` — wait for LLM response (may take 10-30 seconds)
  7. `agent-browser snapshot -i` — check for response
  8. If no response yet, continue polling:
     ```bash
     for i in $(seq 1 6); do
       agent-browser --session $SESSION wait 15000
       agent-browser --session $SESSION snapshot -i
       # Check if a response message appeared below the user message
       # If response is visible, break
     done
     ```
  9. `agent-browser snapshot -i` — verify the response contains relevant contract information
- **Verify:**
  - Chat input field is visible and accepts text
  - Sending a message triggers a response from the RAG system
  - Response contains relevant information about the contract (mentions services, rates, or other extracted data)
  - Response sources/citations may be displayed (page numbers, relevance scores)
- **Precondition:** At least one extraction has completed (CU-3). Chat requires ingested contract data in the vector store.
- **Evidence:** `agent-browser screenshot "$EVIDENCE_DIR/CU-07-chat.png"`

### CU-8: History Tab (P1 smoke, 30s)

- **Page:** `/`
- **Interaction:**
  1. `agent-browser snapshot -i` — locate history navigation element (tab, sidebar link, or page link labeled "History", "Extraction History", or similar)
  2. If found:
     - `agent-browser click @<history-ref>` or `agent-browser open "$BASE_URL/history"`
     - `agent-browser wait --load networkidle`
  3. `agent-browser snapshot -i` — verify history list is displayed
- **Verify:**
  - History page/section is navigable
  - Past extractions are listed (at least the one from CU-2/CU-3)
  - Each entry shows file name, upload date, and status
  - Entries may have action buttons (download, view, re-extract)
- **Note:** If history is displayed inline on the main page rather than a separate tab, verify it is visible after scrolling down.
- **Evidence:** `agent-browser screenshot "$EVIDENCE_DIR/CU-08-history.png"`

### CU-9: Prompt Configuration (P1 e2e, 30s)

- **Page:** `/` or `/settings`
- **Interaction:**
  1. `agent-browser snapshot -i` — locate settings/configuration navigation (gear icon, "Settings" tab, "Prompt Config" link)
  2. If found:
     - `agent-browser click @<settings-ref>` or `agent-browser open "$BASE_URL/settings"`
     - `agent-browser wait --load networkidle`
  3. `agent-browser snapshot -i` — verify prompt configuration fields are visible
  4. Look for:
     - Extraction prompt text area (large multi-line field with the few-shot prompt template)
     - CSV header field (column names for the output CSV)
     - Save button
     - Reset to defaults button
- **Verify:**
  - Prompt configuration page/section is accessible
  - Extraction prompt field contains a non-empty prompt template
  - CSV header field contains column names
  - Fields are editable (text areas, not read-only displays)
  - Save and Reset buttons are present
- **Note:** Do NOT modify the prompt during testing — just verify the fields are populated and editable. Changing the prompt would affect subsequent extractions.
- **Evidence:** `agent-browser screenshot "$EVIDENCE_DIR/CU-09-prompt-config.png"`

---

## Teardown

```bash
agent-browser --session $SESSION close
echo "Evidence screenshots saved to: $EVIDENCE_DIR"
ls -la "$EVIDENCE_DIR"
```
