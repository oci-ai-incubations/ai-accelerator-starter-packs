# VSS UI Tests

16 tests executed via **agent-browser** in a **single browser session** with **screenshot evidence at each step**. Execute in order — batch processing (VU-10) must complete before Content Review tests.

**MANDATORY:** Execute ALL tests in order. If a test fails, record the failure, reload the page, and continue. Do NOT skip any test. Do NOT skip VU-10 because it takes a long time — 60-90 minutes is expected.

---

## Session Setup

```bash
EVIDENCE_DIR="/tmp/vss-evidence-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$EVIDENCE_DIR"
SESSION="vss-test-$(date +%s)"
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
| 1 | VU-1 | Header/title visible | `/` | P0 | smoke | 30s |
| 2 | VU-3 | Bucket configured in Settings | `/settings` | P0 | smoke | 30s |
| 3 | VU-2 | Sidebar navigation (all pages) | all | P1 | smoke | 30s |
| 4 | VU-4 | File list loads on refresh | `/` | P0 | e2e | 60s |
| 5 | VU-6 | File selection | `/` | P1 | smoke | 30s |
| 6 | VU-7 | Parameter sections toggle | `/` | P2 | smoke | 30s |
| 7 | VU-10 | Batch Upload & Analyze (multi-video) | `/` | P0 | e2e | **90min** |
| 8 | VU-20 | Content Review tabs | `/content-review` | P0 | smoke | 30s |
| 9 | VU-23 | Timeline table renders | `/content-review` | P0 | smoke | 30s |
| 10 | VU-28/29 | Approve/Reject rows | `/content-review` | P1 | e2e | 30s |
| 11 | VU-30 | Save & verify reviews | `/content-review` | P1 | e2e | 30s |
| 12 | VU-32 | Category stats chart | `/content-review` | P2 | smoke | 30s |
| 13 | VU-31 | Delete summary cascade | `/content-review` | P1 | e2e | 30s |
| 14 | VU-40 | Settings page | `/settings` | P2 | smoke | 30s |
| 15 | VU-50 | Analytics placeholder | `/analytics` | P2 | smoke | 30s |

> VU-31 (delete) is after VU-32 (chart) because deletion is destructive — verify chart renders before removing data.

---

## Critical Context

### Bucket auto-loading behavior
The bucket name is configured on the **Settings page** (`/settings`) and persisted to `localStorage` key `vss-bucket`. When the Home page loads, it **automatically reads the bucket from localStorage and lists files** — there is no manual "enter bucket name" step. The Home page is for **browsing and processing files**, not configuring the bucket.

### Batch queue completion rule
When a batch operation (e.g., "Upload & Analyze" for multiple videos) shows a processing queue in the UI, the operation is complete when the **queue clears** (no more "Processing..." or "Queued" items visible). Do NOT poll the API separately — watch the UI queue only.

---

## Test Details

### VU-1: Header/Title Visible (P0 smoke, 30s)

- **Page:** `/`
- **Interaction:**
  1. `agent-browser snapshot -i` — look for title text "AI Broadcast Compliance" or Oracle logo image among the interactive/visible elements
- **Verify:** Title text or logo image is visible after page load
- **Evidence:** `agent-browser screenshot "$EVIDENCE_DIR/VU-01-header.png"`

### VU-3: Bucket Configured in Settings (P0 smoke, 30s)

- **Page:** `/settings`
- **Interaction:**
  1. `agent-browser open "$BASE_URL/settings"`
  2. `agent-browser wait --load networkidle`
  3. `agent-browser snapshot -i` — locate the bucket name input field ref
  4. `agent-browser get text @ref` on the bucket name field (or read value from snapshot)
- **Verify:** Bucket name field is populated (not empty). This confirms the deployment configured the bucket correctly.
- **Note:** This is checked on the Settings page, NOT the Home page.
- **Evidence:** `agent-browser screenshot "$EVIDENCE_DIR/VU-03-bucket-settings.png"`

### VU-2: Sidebar Navigation (P1 smoke, 30s)

- **Page:** Start from any page
- **Interaction:**
  1. `agent-browser snapshot -i` — identify navigation link refs for Home, Content Review, Analytics, Settings
  2. For each nav link:
     - `agent-browser click @ref`
     - `agent-browser wait --load networkidle`
     - `agent-browser get url` — verify correct URL
     - `agent-browser snapshot -i` — verify page rendered (not blank/error)
- **Verify:** Each click navigates to the correct URL:
  - Home → `/`
  - Content Review → `/content-review`
  - Analytics → `/analytics`
  - Settings → `/settings`
  - Each page renders without error (no blank white screen, no 500)
- **Evidence:** `agent-browser screenshot "$EVIDENCE_DIR/VU-02-sidebar-nav.png"` (take one per page visited)

### VU-4: File List Loads on Refresh (P0 e2e, 60s)

- **Page:** `/`
- **Interaction:**
  1. `agent-browser open "$BASE_URL/"`
  2. `agent-browser wait --load networkidle`
  3. `agent-browser snapshot -i` — locate the refresh button (icon button near file list area)
  4. `agent-browser click @ref` on the refresh button
  5. `agent-browser wait --load networkidle`
  6. `agent-browser snapshot -i` — verify file list populated
- **Verify:** File list populates with files from the configured bucket (>=1 file visible with name, size, date)
- **CRITICAL:** If an error appears saying "bucket does not exist in compartment" or similar, **STOP the test run and ask the user** to create the bucket before continuing. Do not proceed to further tests.
- **Evidence:** `agent-browser screenshot "$EVIDENCE_DIR/VU-04-file-list.png"`

### VU-6: File Selection (P1 smoke, 30s)

- **Page:** `/`
- **Interaction:**
  1. `agent-browser snapshot -i` — identify file row refs in the table/grid
  2. `agent-browser click @ref` on a file row
  3. `agent-browser snapshot -i` — verify selection visual change
- **Verify:** Selected file gets a visual highlight/selection indicator; action buttons become enabled
- **Evidence:** `agent-browser screenshot "$EVIDENCE_DIR/VU-06-file-selection.png"`

### VU-7: Parameter Sections Toggle (P2 smoke, 30s)

- **Page:** `/`
- **Interaction:**
  1. `agent-browser snapshot -i` — look for accordion/collapsible section headers for VLM, RAG, Summarize parameters
  2. If found, `agent-browser click @ref` on a section header to expand/collapse
  3. `agent-browser snapshot -i` — verify content toggles visibility
- **Verify:** Section content toggles visibility on click
- **Note:** Current UI may show a simplified batch mode without exposed parameter accordion — mark N/A if no collapsible parameter sections are visible. This is acceptable.
- **Evidence:** `agent-browser screenshot "$EVIDENCE_DIR/VU-07-param-toggle.png"`

### VU-10: Batch Upload & Analyze — Multi-Video (P0 e2e, 90min timeout)

- **Page:** `/`
- **Interaction:**
  1. `agent-browser open "$BASE_URL/"`
  2. `agent-browser wait --load networkidle`
  3. `agent-browser snapshot -i` — identify file checkboxes in the file list
  4. Select >=2 video files by clicking their checkbox refs
  5. `agent-browser snapshot -i` — locate button with text containing "Analyze"
  6. `agent-browser click @ref` on the "Upload & Analyze" button
  7. `agent-browser snapshot -i` — verify jobs are queued (job count in UI matches selected files)
  8. **Poll for completion** using a loop:
     ```bash
     # Poll every 60 seconds, up to 90 iterations (90 min)
     for i in $(seq 1 90); do
       agent-browser wait 60000
       agent-browser snapshot -i
       agent-browser screenshot "$EVIDENCE_DIR/VU-10-progress-${i}min.png"
       # Check snapshot output: if no "Processing..." or "Queued" items visible, break
       # If all jobs show COMPLETED or queue is empty, processing is done
     done
     ```
  9. Once all jobs reach COMPLETED status (queue UI empties), navigate to `/content-review`:
     ```bash
     agent-browser open "$BASE_URL/content-review"
     agent-browser wait --load networkidle
     ```
- **Verify:** A new tab exists in Content Review for each processed video
- **CRITICAL — DO NOT SKIP THIS TEST.** Multi-video batch processing takes 60-90 minutes. That is expected. Use a polling loop with `agent-browser wait 60000` + `agent-browser snapshot -i` to monitor progress, taking periodic screenshots to record status (e.g., "2/3 jobs complete"). Verify entirely through the UI — do NOT use API calls to poll `/api/jobs`.
- **Evidence:** `agent-browser screenshot "$EVIDENCE_DIR/VU-10-complete.png"` (plus periodic progress screenshots from the polling loop)

### VU-20: Content Review Tabs (P0 smoke, 30s)

- **Page:** `/content-review`
- **Interaction:**
  1. `agent-browser open "$BASE_URL/content-review"`
  2. `agent-browser wait --load networkidle`
  3. `agent-browser snapshot -i` — identify tab bar refs (one per summarized video)
  4. `agent-browser click @ref` on a tab
  5. `agent-browser snapshot -i` — verify tab content loads
- **Verify:** Tab bar shows >=1 tab per processed video; clicking a tab loads that video's summary
- **Evidence:** `agent-browser screenshot "$EVIDENCE_DIR/VU-20-content-tabs.png"`

### VU-23: Timeline Table Renders (P0 smoke, 30s)

- **Page:** `/content-review`
- **Interaction:**
  1. `agent-browser snapshot -i` — look for table with columns: Time Range, Categories, Event, Status
  2. Scroll if needed: `agent-browser scroll down 300`
  3. `agent-browser snapshot -i` — read table rows
- **Verify:** >=1 row with timestamp range (e.g., "120.0 - 125.0"), category tags, event text
- **Evidence:** `agent-browser screenshot "$EVIDENCE_DIR/VU-23-timeline-table.png"`

### VU-28/29: Approve/Reject Rows (P1 e2e, 30s)

- **Page:** `/content-review`
- **Interaction:**
  1. `agent-browser snapshot -i` — identify Approve button (checkmark/green) and Reject button (X/red) refs per row
  2. `agent-browser click @ref` on an Approve button for one row
  3. `agent-browser snapshot -i` — verify visual indicator changes (green/check)
  4. `agent-browser click @ref` on a Reject button for a different row
  5. `agent-browser snapshot -i` — verify visual indicator changes (red/X)
- **Verify:** Row visual state reflects the approval/rejection action
- **Evidence:** `agent-browser screenshot "$EVIDENCE_DIR/VU-28-29-approve-reject.png"`

### VU-30: Save & Verify Reviews (P1 e2e, 30s)

- **Page:** `/content-review`
- **Interaction:**
  1. `agent-browser snapshot -i` — locate the Save/persist button ref
  2. `agent-browser click @ref` on the Save button (triggers PUT `/api/videos/summary/[id]/reviews`)
  3. `agent-browser wait --load networkidle`
  4. `agent-browser reload`
  5. `agent-browser wait --load networkidle`
  6. `agent-browser snapshot -i` — navigate back to the same video tab if needed
  7. `agent-browser snapshot -i` — check that previously approved/rejected rows retain their state
- **Verify:** Previously approved/rejected rows still show their saved state after refresh (edits persisted to DB)
- **Evidence:** `agent-browser screenshot "$EVIDENCE_DIR/VU-30-save-reviews.png"`

### VU-32: Category Stats Chart (P2 smoke, 30s)

- **Page:** `/content-review`
- **Interaction:**
  1. `agent-browser snapshot -i` — look for a bar chart element (SVG-based chart with category labels). Use `snapshot -i` to discover available refs rather than relying on CSS selectors like `.recharts-bar`.
  2. If a chart area is found, `agent-browser scrollintoview @ref` to ensure it is visible
- **Verify:** Bar chart renders with category labels from the timeline data. If no chart is visible but the page loads without error, mark as N/A (chart may require minimum data).
- **Evidence:** `agent-browser screenshot "$EVIDENCE_DIR/VU-32-category-chart.png"`

### VU-31: Delete Summary Cascade (P1 e2e, 30s)

- **Page:** `/content-review`
- **Interaction:**
  1. `agent-browser snapshot -i` — note the current tab count
  2. Locate the Delete button ref (button with "Delete" text or trash icon)
  3. `agent-browser click @ref` on the Delete button
  4. Check for a confirmation dialog: `agent-browser dialog status`
     - If a dialog is open: `agent-browser dialog accept`
  5. `agent-browser wait --load networkidle`
  6. `agent-browser snapshot -i` — verify tab was removed
- **Verify:**
  - Tab disappears from the tab bar
  - Tab count decreased by 1
  - The deleted video's data is no longer accessible
- **Note:** This is destructive. Run after all other Content Review tests.
- **Evidence:** `agent-browser screenshot "$EVIDENCE_DIR/VU-31-delete-cascade.png"`

### VU-40: Settings Page (P2 smoke, 30s)

- **Page:** `/settings`
- **Interaction:**
  1. `agent-browser open "$BASE_URL/settings"`
  2. `agent-browser wait --load networkidle`
  3. `agent-browser snapshot -i` — locate bucket name input, prompt text areas, parameter displays
- **Verify:** Bucket name, prompts (caption/summarization/aggregation), and default parameters (model, chunk_duration) are displayed with non-empty values
- **Evidence:** `agent-browser screenshot "$EVIDENCE_DIR/VU-40-settings.png"`

### VU-50: Analytics Placeholder (P2 smoke, 30s)

- **Page:** `/analytics`
- **Interaction:**
  1. `agent-browser open "$BASE_URL/analytics"`
  2. `agent-browser wait --load networkidle`
  3. `agent-browser snapshot -i` — look for "Coming soon" or similar placeholder text
- **Verify:** Page loads without error; placeholder text visible
- **Evidence:** `agent-browser screenshot "$EVIDENCE_DIR/VU-50-analytics.png"`

---

## Teardown

```bash
agent-browser --session $SESSION close
echo "Evidence screenshots saved to: $EVIDENCE_DIR"
ls -la "$EVIDENCE_DIR"
```
