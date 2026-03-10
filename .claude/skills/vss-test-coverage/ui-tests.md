# VSS UI Tests

16 tests executed via Playwright in a **single browser context** with **continuous video recording**. Execute in order — batch processing (VU-10) must complete before Content Review tests.

**MANDATORY:** Execute ALL tests in order. If a test fails, record the failure, refresh the page, and continue. Do NOT skip any test. Do NOT skip VU-10 because it takes a long time — 60-90 minutes is expected.

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
- **Selector:** `text="AI Broadcast Compliance"` or Oracle logo image
- **Interaction:** None (visual check)
- **Verify:** Title text or logo image is visible after page load

### VU-3: Bucket Configured in Settings (P0 smoke, 30s)

- **Page:** `/settings`
- **Selector:** Input field containing bucket name
- **Interaction:** Navigate to `/settings`, locate the bucket name field
- **Verify:** Bucket name field is populated (not empty). This confirms the deployment configured the bucket correctly.
- **Note:** This is checked on the Settings page, NOT the Home page.

### VU-2: Sidebar Navigation (P1 smoke, 30s)

- **Page:** Start from any page
- **Selector:** Navigation links: Home, Content Review, Analytics, Settings
- **Interaction:** Click each of the 4 navigation links
- **Verify:** Each click navigates to the correct URL:
  - Home → `/`
  - Content Review → `/content-review`
  - Analytics → `/analytics`
  - Settings → `/settings`
  - Each page renders without error (no blank white screen, no 500)

### VU-4: File List Loads on Refresh (P0 e2e, 60s)

- **Page:** `/`
- **Selector:** Refresh button (icon button near file list area), file list table/grid
- **Interaction:** Navigate to Home page, click the **refresh button**
- **Verify:** File list populates with files from the configured bucket (>=1 file visible with name, size, date)
- **CRITICAL:** If an error appears saying "bucket does not exist in compartment" or similar, **STOP the test run and ask the user** to create the bucket before continuing. Do not proceed to further tests.

### VU-6: File Selection (P1 smoke, 30s)

- **Page:** `/`
- **Selector:** Table rows or cards showing file names/sizes/dates
- **Interaction:** Click a file row
- **Verify:** Selected file gets a visual highlight/selection indicator; action buttons become enabled

### VU-7: Parameter Sections Toggle (P2 smoke, 30s)

- **Page:** `/`
- **Selector:** Accordion/collapsible sections for VLM, RAG, Summarize parameters
- **Interaction:** Click section headers to expand/collapse
- **Verify:** Section content toggles visibility on click
- **Note:** Current UI may show a simplified batch mode without exposed parameter accordion — mark N/A if no collapsible parameter sections are visible. This is acceptable.

### VU-10: Batch Upload & Analyze — Multi-Video (P0 e2e, 90min timeout)

- **Page:** `/`
- **Selector:** File checkboxes, button with text containing "Analyze"
- **Interaction:**
  1. Select >=2 video files via checkboxes in the file list
  2. Click "Upload & Analyze" button
  3. Verify jobs are queued (job count in UI matches selected files)
  4. Watch jobs process consecutively — each transitions PENDING → PROCESSING → COMPLETED in order
  5. Wait until ALL jobs reach COMPLETED status (queue UI empties)
  6. Navigate to `/content-review`
- **Verify:** A new tab exists in Content Review for each processed video
- **CRITICAL — DO NOT SKIP THIS TEST.** Multi-video batch processing takes 60-90 minutes. That is expected. Set `page.setDefaultTimeout(5400000)` (90 min). Update the banner overlay periodically during processing (e.g., "VU-10: Processing... 15min elapsed, 2/3 jobs complete"). Verify entirely through the UI — do NOT use API calls to poll `/api/jobs`.

### VU-20: Content Review Tabs (P0 smoke, 30s)

- **Page:** `/content-review`
- **Selector:** Tab bar (Radix UI tabs) — one per summarized video
- **Interaction:** Click a tab
- **Verify:** Tab bar shows >=1 tab per processed video; clicking a tab loads that video's summary

### VU-23: Timeline Table Renders (P0 smoke, 30s)

- **Page:** `/content-review`
- **Selector:** Table with columns: Time Range, Categories, Event, Status
- **Interaction:** Scroll/read table
- **Verify:** >=1 row with timestamp range (e.g., "120.0 - 125.0"), category tags, event text

### VU-28/29: Approve/Reject Rows (P1 e2e, 30s)

- **Page:** `/content-review`
- **Selector:** Approve button (checkmark/green), Reject button (X/red) per row
- **Interaction:**
  1. Click Approve on a row → verify visual indicator changes (green/check)
  2. Click Reject on a different row → verify visual indicator changes (red/X)
- **Verify:** Row visual state reflects the approval/rejection action

### VU-30: Save & Verify Reviews (P1 e2e, 30s)

- **Page:** `/content-review`
- **Selector:** Save/persist button
- **Interaction:**
  1. Click Save button (triggers PUT `/api/videos/summary/[id]/reviews`)
  2. Refresh the page (`page.reload()`)
  3. Navigate back to the same video tab
- **Verify:** Previously approved/rejected rows still show their saved state after refresh (edits persisted to DB)

### VU-32: Category Stats Chart (P2 smoke, 30s)

- **Page:** `/content-review`
- **Selector:** Recharts bar chart element (SVG with `.recharts-bar` or similar)
- **Interaction:** Visual check
- **Verify:** Bar chart renders with category labels from the timeline data. If no chart is visible but the page loads without error, mark as N/A (chart may require minimum data).

### VU-31: Delete Summary Cascade (P1 e2e, 30s)

- **Page:** `/content-review`
- **Selector:** Delete button (button with "Delete" text or trash icon)
- **Interaction:**
  1. Note the current tab count
  2. Click Delete on a summary
  3. If a confirmation dialog appears, confirm it. **Dismiss any dialog after the action.**
- **Verify:**
  - Tab disappears from the tab bar
  - Tab count decreased by 1
  - The deleted video's data is no longer accessible
- **Note:** This is destructive. Run after all other Content Review tests.

### VU-40: Settings Page (P2 smoke, 30s)

- **Page:** `/settings`
- **Selector:** Bucket name input, prompt text areas, parameter displays
- **Interaction:** Navigate to `/settings`
- **Verify:** Bucket name, prompts (caption/summarization/aggregation), and default parameters (model, chunk_duration) are displayed with non-empty values

### VU-50: Analytics Placeholder (P2 smoke, 30s)

- **Page:** `/analytics`
- **Selector:** Text containing "Coming soon" or similar placeholder
- **Interaction:** Navigate to `/analytics`
- **Verify:** Page loads without error; placeholder text visible
