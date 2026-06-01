# Enterprise RAG AIQ — UI Test Checklist

Agent-browser walkthrough of the AIRA research frontend. Execute in order. Screenshot at every step. If a step fails, record the failure, screenshot, and continue.

**Session setup:**
```bash
EVIDENCE_DIR="/tmp/aiq-evidence-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$EVIDENCE_DIR"
SESSION="aiq-test-$(date +%s)"
agent-browser --headed --session-name $SESSION --ignore-https-errors open "$STARTER_PACK_URL"
agent-browser --session-name $SESSION wait --load networkidle
agent-browser --session-name $SESSION wait 3000
```

---

## Checklist

### QU-1: Main page loads (P0, 30s)

- [ ] Page loads without error (no 502, no connection refused)
- [ ] "AI-Q Blueprint" or similar heading visible
- [ ] "Collections" button visible
- [ ] "Conduct Research" option visible
- [ ] Screenshot: `$EVIDENCE_DIR/QU-01-main-page.png`

### QU-2: Open Collections and select Financial Dataset (P0, 30s)

- [ ] Click "Collections" button — panel opens
- [ ] Screenshot: `$EVIDENCE_DIR/QU-02-collections-panel.png`
- [ ] "Financial Dataset" (or "Financial Data Set") is listed
- [ ] Click Financial Dataset to select it
- [ ] Close the Collections panel (click close/X button or click outside)
- [ ] Screenshot: `$EVIDENCE_DIR/QU-02-financial-selected.png`

### QU-3: Confirm Financial Dataset is selected (P0, 30s)

- [ ] Main page shows Financial Dataset as the active collection
- [ ] Collection name visible in the UI (badge, label, or text)
- [ ] Screenshot: `$EVIDENCE_DIR/QU-03-collection-confirmed.png`

### QU-4: Click Conduct Research (P0, 30s)

- [ ] "Conduct Research" is visible in the center of the page
- [ ] Click it
- [ ] New view appears (research workflow or topic entry)
- [ ] Screenshot: `$EVIDENCE_DIR/QU-04-conduct-research.png`

### QU-5: Click Begin Researching (P0, 30s)

- [ ] "Begin Researching" button is visible
- [ ] Click it
- [ ] Workflow advances to next stage
- [ ] Screenshot: `$EVIDENCE_DIR/QU-05-begin-researching.png`

### QU-6: Select Sources — verify Web Search (P0, 30s)

- [ ] "Select Sources" button or section is visible
- [ ] Click it if needed
- [ ] "Web Search" is listed as a source option
- [ ] "Web Search" is checked/enabled (Tavily configured)
- [ ] If Web Search is disabled: note as conditional (Tavily key missing) — still PASS
- [ ] Screenshot: `$EVIDENCE_DIR/QU-06-select-sources.png`

### QU-7: Experience Chat — planning phase (P0, 3min timeout)

- [ ] After source selection, the chat/experience window becomes active
- [ ] System shows planning activity (text streaming, "Planning...", sections appearing)
- [ ] Screenshot early: `$EVIDENCE_DIR/QU-07-chat-planning-1.png`
- [ ] Wait 30s, screenshot again: `$EVIDENCE_DIR/QU-07-chat-planning-2.png`
- [ ] Content is being generated (not empty, not stuck)
- [ ] Report Topic and Report Structure sections populate

### QU-8: Execute Plan (P0, 5min timeout)

- [ ] "Execute Plan" button is visible
- [ ] Screenshot BEFORE pressing: `$EVIDENCE_DIR/QU-08-before-execute.png`
- [ ] Click "Execute Plan"
- [ ] New window/panel opens or view transitions to execution mode
- [ ] Screenshot: `$EVIDENCE_DIR/QU-08-execution-started.png`
- [ ] Execution activity visible (progress indicators, section tabs, text generation)

### QU-9: RAG Answer (P0, 3min timeout)

- [ ] Wait for RAG Answer section to finish (spinner stops, content appears)
- [ ] RAG Answer contains text (not empty)
- [ ] Content relates to the Financial Dataset topic
- [ ] No error banners or "failed to generate" messages
- [ ] Content quality: reads as a coherent answer with cited sources
- [ ] Screenshot: `$EVIDENCE_DIR/QU-09-rag-answer.png`
- [ ] If errors: screenshot the error, note what you see, hypothesize the cause

### QU-10: Relevancy Checker (P1, 2min timeout)

- [ ] Wait for any spinning/loading to stop
- [ ] Click "Relevancy Checker" tab/section
- [ ] Output appears with relevancy analysis
- [ ] Content has structured output (scores, assessments, or similar)
- [ ] No error messages
- [ ] Screenshot: `$EVIDENCE_DIR/QU-10-relevancy-checker.png`

### QU-11: Web Answer (P1, 2min timeout)

- [ ] Click "Web Answer" tab/section
- [ ] If Tavily configured: web-sourced answer content appears — PASS
- [ ] If Tavily NOT configured: "not available" or error is expected — conditional PASS
- [ ] No unhandled exceptions (no blank page, no 500 errors)
- [ ] Screenshot: `$EVIDENCE_DIR/QU-11-web-answer.png`
- [ ] If errors: screenshot immediately, diagnose — is `TAVILY_SEARCH_API_KEY` set in the pod env?

### QU-12: Summarized Sources (P1, 60s)

- [ ] Click "Summarized Sources" tab/section
- [ ] Source documents or references are listed
- [ ] Sources include document names, excerpts, or relevancy info
- [ ] No error messages
- [ ] Content quality: sources look reasonable and related to the topic
- [ ] Screenshot: `$EVIDENCE_DIR/QU-12-summarized-sources.png`

### QU-13: Reporting Summary (P1, 60s)

- [ ] Click "Reporting Summary" tab/section
- [ ] A synthesized report or summary is displayed
- [ ] Content is coherent and relates to the financial research topic
- [ ] Not garbled, not truncated mid-sentence
- [ ] Quality assessment: would a human find this useful?
- [ ] Screenshot: `$EVIDENCE_DIR/QU-13-reporting-summary.png`

---

## Teardown & Evidence Upload

```bash
agent-browser --session-name $SESSION screenshot "$EVIDENCE_DIR/QU-final-state.png"
agent-browser --session-name $SESSION close

# Upload to OCI Object Storage (optional — requires EVIDENCE_BUCKET set)
if [ -n "${EVIDENCE_BUCKET:-}" ]; then
  bash .claude/skills/testing-pack/scripts/upload_evidence.sh \
    "$EVIDENCE_DIR" "$EVIDENCE_BUCKET" "${EVIDENCE_NAMESPACE:-}" \
    "aiq-evidence/$(date +%Y%m%d)"
fi
```

## Results Template

```
AIQ UI TEST RESULTS — enterprise_rag_aiq
Date:  <YYYY-MM-DD>
URL:   <STARTER_PACK_URL>

QU-1:  Main page loads              — PASS/FAIL
QU-2:  Collections — Financial      — PASS/FAIL
QU-3:  Collection confirmed         — PASS/FAIL
QU-4:  Conduct Research             — PASS/FAIL
QU-5:  Begin Researching            — PASS/FAIL
QU-6:  Select Sources / Web Search  — PASS/FAIL/CONDITIONAL
QU-7:  Planning phase               — PASS/FAIL
QU-8:  Execute Plan                 — PASS/FAIL
QU-9:  RAG Answer                   — PASS/FAIL
QU-10: Relevancy Checker            — PASS/FAIL
QU-11: Web Answer                   — PASS/FAIL/CONDITIONAL
QU-12: Summarized Sources           — PASS/FAIL
QU-13: Reporting Summary            — PASS/FAIL

Evidence: <EVIDENCE_DIR or bucket path>
Issues:
  - <description, screenshot reference, suspected cause>
```
