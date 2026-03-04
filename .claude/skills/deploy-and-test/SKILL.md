---
name: deploy-and-test
description: Full deployment workflow - GPU capacity check across regions, region selection, ORM stack deploy, pod verification, and pack-specific testing (API + UI) via Playwright sub-agent.
user-invocable: true
allowed-tools: Bash, Read, Grep, Glob, Edit, Write, AskUserQuestion, WebFetch, Agent
argument-hint: [category] [size]
---

## CRITICAL: User interaction rules

Some steps in this skill require user input. Follow these rules strictly:

1. **Always use `AskUserQuestion`** for every question that needs user input. Do NOT skip questions or assume defaults.
2. **Verify the response is non-empty.** After `AskUserQuestion` returns, check that the `answers` field contains an actual selection. If the answer text after "User has answered your questions:" is empty or blank, the user was NOT actually asked. In that case:
   - **Output the question as plain text** in your response message (e.g., "Which OCI CLI profile should I use? Options: DEFAULT, SANJOSE") and **STOP and WAIT** for the user to reply in their next message.
   - Do NOT proceed with an assumed answer. Do NOT continue to the next step.
3. **Never assume a default answer.** If the user doesn't respond or the tool fails silently, halt and ask again via text output.
4. **One question at a time.** Don't batch unrelated questions — ask, wait for a real answer, then proceed.

---

# Deploy and Test

Full end-to-end deployment workflow: check GPU availability across regions, let the user pick a region, deploy the ORM stack, verify pods and outputs, run pack-specific API + UI tests via Playwright, then optionally destroy.

> **MANDATORY COMPLIANCE — READ BEFORE PROCEEDING**
>
> Every step in this skill **MUST** be executed **consecutively in order**. Do NOT skip, reorder, or combine steps. Do NOT assume a step's outcome — execute it and verify the result before moving to the next step.
>
> If you are confused, stuck, or unsure how to proceed at any step: **stop and ask the user for guidance.** Do NOT guess, improvise, or silently skip steps. The user must be informed of any deviation.
>
> Step 12b (asking the user for a test matrix) is **mandatory** — you must always ask the user whether they have additional tests, even if a base coverage spec exists. Never skip this prompt.

## Arguments

- `$0` - Starter pack category: `paas_rag`, `cuopt`, `vss`, `enterprise_rag`, `enterprise_rag_aiq`
- `$1` - Starter pack size: `poc`, `small`, `medium` (category-dependent)

If no arguments are provided, ask the user.

---

## Phase 0: Load Sandbox Environment

All temporary files, packages, and state live in an isolated sandbox created by `/setup`. **Nothing goes into the repo working tree.**

### Step 0a: Source sandbox env

```bash
# Find the most recent sandbox, or use the one already set
if [ -z "${DAT_SANDBOX}" ]; then
  DAT_SANDBOX=$(ls -td /tmp/dat-sandbox-* 2>/dev/null | head -1)
fi

if [ -z "${DAT_SANDBOX}" ] || [ ! -f "${DAT_SANDBOX}/env.sh" ]; then
  echo "ERROR: No sandbox found. Run /setup first."
  exit 1
fi

source "${DAT_SANDBOX}/env.sh"
echo "Sandbox: ${DAT_SANDBOX}"
```

This loads all environment variables into the session:

| Variable | Source | Used in |
|---|---|---|
| `DAT_SANDBOX` | Setup Step 1 | All phases — root for temp files |
| `OCI_CLI_PROFILE` | Setup Step 4 | All OCI CLI commands |
| `CORRINO_USERNAME` | Extracted from tfvars | Phase 3 login tests |
| `CORRINO_PASSWORD` | Extracted from tfvars | Phase 3 login tests |
| `COMPARTMENT_OCID` | Extracted from tfvars | Phase 2 stack creation |
| `STARTER_PACK_CATEGORY` | Extracted from tfvars | Phase 1 (can be overridden by arguments) |
| `STARTER_PACK_SIZE` | Extracted from tfvars | Phase 1 (can be overridden by arguments) |
| `PLAYWRIGHT_BROWSERS_PATH` | Setup Step 6 | Phase 3 UI tests |
| `VSS_BUCKET_NAME`, etc. | Setup Step 8 | Phase 3 pack-specific tests |

Sandbox sub-directories:

| Sub-directory | Contents |
|---|---|
| `api-results/` | curl response bodies (`VA-1.json`, `VA-5b.json`, etc.) |
| `ui-recordings/` | Continuous `.webm` video recordings from Playwright |
| `logs/` | ORM job logs, kubectl output, test reports |
| `zips/` | `lifecycle.zip` for ORM upload |
| `packages/` | npm packages, Playwright browsers |
| `venv/` | Python virtual environment |

### Step 0b: Quick prerequisite check

```bash
for tool in oci kubectl zip curl python3; do
  which "$tool" > /dev/null 2>&1 || echo "MISSING: $tool — run /setup"
done
```

If anything is missing, stop and tell the user: *"Run `/setup` first."*

---

## Phase 1: Pre-Flight — GPU Capacity & Region Selection

### Step 1: Get category and size from user

If not provided as arguments, ask:
- Category: `paas_rag`, `cuopt`, `vss`, `enterprise_rag`, `enterprise_rag_aiq`
- Size (valid options per category):
  - `cuopt`: `poc`, `small`, `medium`
  - `vss`: `small`, `medium`
  - `paas_rag`: `small`, `medium`
  - `enterprise_rag`: `small`
  - `enterprise_rag_aiq`: `small`

Also ask for `OCI_CLI_PROFILE` (common values: `SANJOSE`, `DEFAULT`) and any PR-specific testing requirements.

### Step 2: Look up required GPU shape

| Category | Size | GPU Shape | Nodes Needed |
|---|---|---|---|
| `cuopt` | `poc` | `VM.GPU.A10.2` | 1 |
| `cuopt` | `small` | `BM.GPU4.8` | 1 |
| `cuopt` | `medium` | `BM.GPU.A100-v2.8` | 1 |
| `vss` | `small` | `BM.GPU4.8` | 1 |
| `vss` | `medium` | `BM.GPU.L40S-NC.4` | 2 |
| `enterprise_rag` | `small` | `BM.GPU4.8` | 2 |
| `enterprise_rag_aiq` | `small` | `BM.GPU4.8` | 2 |
| `paas_rag` | `small` | *(no GPU required)* | 0 |
| `paas_rag` | `medium` | *(no GPU required)* | 0 |

For `paas_rag`, skip Steps 3–5 and ask the user to select any region.

### Step 3: Fetch GPU capacity dashboard

Use WebFetch to retrieve live capacity data:

```
URL: https://gpu-capacity.ai-apps-ord.oci-incubations.com/
```

Filter all rows where:
- **Shape** matches the required GPU shape
- **Status** is `AVAILABLE`
- **Available** count >= nodes needed

### Step 4: Present qualifying regions to user

Group filtered results by **Region**. A region qualifies if at least one Availability Domain meets the criteria.

Present as a numbered list:

```
Available regions for BM.GPU4.8 (need 2 nodes):
1. us-ashburn-1     — AD-1: 4 available
2. eu-frankfurt-1   — AD-2: 3 available
3. ap-tokyo-1       — AD-1: 2 available
```

If no regions qualify, report to the user and stop.

### Step 5: User selects region

Ask the user to choose a region. Record:
- **Region** (e.g., `us-ashburn-1`) → use as `region` in deployment
- **Availability Domain** (e.g., `AD-1`) → use as `worker_node_availability_domain`

---

## Phase 2: Deploy

### Step 6: Generate schema

```bash
cd /Users/sankaza/ai-accelerator-starter-packs
source venv/bin/activate
python3 create_final_schema.py -c $0
```

### Step 7: Create zip

```bash
rm -rf ai-accelerator-tf/.terraform ai-accelerator-tf/.terraform.lock.hcl
cd ai-accelerator-tf && zip -r "${DAT_SANDBOX}/zips/lifecycle.zip" . -x '.terraform/*' '.terraform.lock.hcl'
```

### Step 8: Create ORM stack

```bash
export OCI_CLI_PROFILE=<profile>
oci resource-manager stack create \
  --compartment-id ocid1.compartment.oc1..aaaaaaaa5rwhi5wj3grdiqzvz244gwzycpfl2ctlb4nvl7vi7wu55tqi375a \
  --config-source "${DAT_SANDBOX}/zips/lifecycle.zip" \
  --terraform-version "1.5.x" \
  --display-name "deploy-and-test-$0-$1" \
  --variables "{\"region\": \"<selected-region>\"}"
```

Record the returned stack OCID.

### Step 9: Plan

Create a plan job, poll until completion, check logs for errors. Stop and report to user if plan fails.

### Step 10: Apply

Create an apply job with `AUTO_APPROVED`, poll until completion. Stop and report to user if apply fails.

### Step 11: Configure kubectl

Extract cluster OCID from apply logs:

```bash
oci ce cluster create-kubeconfig --cluster-id <cluster-ocid> --kube-endpoint PUBLIC_ENDPOINT
```

---

## Phase 3: Pack-Specific Testing (API + UI)

This phase executes tests against the live deployment. Tests come from **two sources** that are merged together:

1. **Base coverage file** — a pack-specific SKILL.md with the known API endpoints, UI pages, and infra checks for the pack.
2. **User-provided test matrix** — additional tests the user wants to run (e.g., PR-specific regressions, custom endpoints, one-off checks).

Both are tested when both are present.

### Step 12: Locate base coverage spec + ask for user test matrix

#### 12a. Check for the base coverage file

```
.claude/skills/<category>-test-coverage/SKILL.md
```

For example: `.claude/skills/vss-test-coverage/SKILL.md`, `.claude/skills/paas-rag-test-coverage/SKILL.md`, etc.

- **If found:** Read the file. It contains the full test matrix with API endpoints, UI tests (including end-to-end flows), and infrastructure checks — each with IDs, verification criteria, priorities, and timeouts.
- **If not found:** Note it — the user-provided matrix (Step 12b) becomes the only source.

#### 12b. Ask the user for a test matrix (MANDATORY — DO NOT SKIP)

**You MUST ask this question every time, even if a base coverage spec was found in Step 12a.** Do not proceed to Step 13 without asking. Always ask:

> *"Do you have a test matrix or additional tests to run for this deployment? This can be:*
> - *A list of API endpoints to hit (method + URL + expected response)*
> - *UI pages/flows to verify*
> - *Infrastructure checks (kubectl commands, OCI CLI queries)*
> - *Or a file/URL containing the matrix*
>
> *If not, I'll proceed with the base coverage spec only."*

If the user provides a test matrix:

1. **Categorize each item** as `API`, `Infra`, or `UI` based on what it tests.
2. **Assign temporary IDs** using the pattern `UT-1`, `UT-2`, ... (User Test) to distinguish from base spec IDs.
3. **Merge with the base spec** — user tests run in addition to (not instead of) base tests.

#### 12c. Determine test sources

| Base spec found? | User matrix provided? | Action |
|---|---|---|
| Yes | Yes | Run both — base spec tests + user tests |
| Yes | No | Run base spec tests only |
| No | Yes | Run user tests only |
| No | No | Run basic smoke tests (subdomain resolution, health endpoint, frontend loads) |

### Step 13: Ask user for test scope

Present the **combined** test inventory and ask:

> Tests available for `<category>`:
>
> **Base coverage spec** (if present):
> - API tests: N items
> - Infra tests: N items
> - UI tests: N items (includes end-to-end flows)
>
> **User-provided tests** (if present):
> - API: N items
> - Infra: N items
> - UI: N items
>
> Which should I run?
> 1. All tests (recommended for fresh deploys)
> 2. P0 only from base spec + all user tests
> 3. API + UI only (skip infra)
> 4. Custom selection

Also ask if the user has any **additional test parameters** (e.g., bucket names, object keys, credentials beyond the standard Corrino admin).

### Step 14: Gather test inputs

From Phase 2 outputs and the coverage spec, collect:

| Input | Source |
|---|---|
| `FRONTEND_URL` | `starter_pack_url` Terraform output from Phase 2 apply |
| `CORRINO_USERNAME` | `corrino_admin_username` from `terraform.tfvars` (if pack requires login) |
| `CORRINO_PASSWORD` | `corrino_admin_password` from `terraform.tfvars` (if pack requires login) |
| Pack-specific vars | Coverage spec "Environment Variables" section (e.g., `VSS_BUCKET_NAME`, `VSS_OBJECT_KEY`) — ask user for values |

### Step 15: Execute API tests

For every test row in the coverage spec's **API test matrix** (IDs like `VA-*`, `PA-*`, etc.) that matches the chosen scope:

1. Read the endpoint, method, request body, and expected response from the spec.
2. Execute via `curl` (responses saved to sandbox):

```bash
# Example: GET endpoint
curl -sk -o "${DAT_SANDBOX}/api-results/VA-1.json" -w '%{http_code}' \
  "${FRONTEND_URL}/api/vss/config"

# Example: POST endpoint
curl -sk -X POST -H 'Content-Type: application/json' \
  -d '{"bucketName":"test-bucket"}' \
  -o "${DAT_SANDBOX}/api-results/VA-5b.json" -w '%{http_code}' \
  "${FRONTEND_URL}/api/list-bucket-files"
```

3. Compare HTTP status code and response body against the spec's verification criteria.
4. Record result per test ID.

**API Test Report:**

| ID | Endpoint | Expected | Actual Status | Pass? | Response Preview |
|---|---|---|---|---|---|
| (from spec) | (from spec) | (from spec) | (actual) | Y/N | first 200 chars |

### Step 16: Execute Infra tests (if selected)

For infrastructure test rows (IDs like `VI-*`):

- Run `kubectl` or OCI CLI commands as specified in the coverage spec.
- Record pass/fail per test ID.

### Step 17: Execute UI tests

**Before writing any UI test code**, merge the base coverage spec UI tests and user-provided UI tests into a single sequential flow:

1. List all UI tests from the base spec (by ID, in order).
2. List all UI tests from the user's test matrix.
3. If any user test overlaps with a base test (same page, same interaction), **use the user's version** — it may have different or additional verification criteria. Do not run both.
4. Combine the deduplicated tests into **one ordered list** that forms a logical user journey (e.g., Home → file selection → batch process → Content Review → editing → delete → Settings → Analytics).
5. This merged list is the single flow you will execute.

> **ONE `browser_run_code` CALL. ONE RECORDING. ONE FLOW.** All UI tests — base spec and user-provided — go into a **single** `mcp__playwright__browser_run_code` call that produces a **single** `.webm` video recording. Do NOT split UI tests across multiple `browser_run_code` calls. Do NOT create multiple browser contexts. The entire UI test session is one sequential flow in one function.

> **NO SCREENSHOTS.** The continuous video recording with banner overlay captures everything — screenshots are redundant and clutter the sandbox.

**How to build the single `browser_run_code` block:**

1. Take the merged, ordered test list from the planning step above.
2. Build a single async function that:
   - Creates ONE browser context with video recording: `browser.newContext({ recordVideo: { dir: '${DAT_SANDBOX}/ui-recordings', size: { width: 1280, height: 800 } } })`
   - Injects the banner overlay helper (see below)
   - Executes each test sequentially: navigate → interact → verify → record result → update banner → next test
   - Collects results into a `results` object keyed by test ID
   - Closes context in `finally` block — this finalizes the `.webm` video file
3. The function must handle the **entire** test flow — smoke checks, e2e operations (batch processing, long summarizations), content review editing, deletion, navigation — all in one run.

**Banner helper pattern** (inject once at the top of the function):
```javascript
var banner = async function(label) {
  await p.evaluate(function(t) {
    var el = document.getElementById('__ci__');
    if (!el) {
      el = document.createElement('div');
      el.id = '__ci__';
      el.style.cssText = 'position:fixed;top:0;left:0;right:0;z-index:2147483647;' +
        'background:#0d1117;color:#58a6ff;font:bold 14px/38px monospace;' +
        'padding:0 16px;border-bottom:2px solid #1f6feb;letter-spacing:.5px';
      document.documentElement.prepend(el);
    }
    el.textContent = '\u25B6  ' + t;
  }, label).catch(function() {});
  await p.waitForTimeout(600);
};
```

**Rules for the `browser_run_code` block:**
- Use `var` (not `const`/`let`) and string concatenation (not template literals) to avoid escaping issues
- Wrap everything in `try/catch/finally` — `finally` must close the recording context
- Use the spec's "Selector Hint" column to find elements; fall back to generic selectors if needed
- For packs requiring login (check spec for auth requirements): fill credentials before navigating to protected pages
- **Do NOT call `p.screenshot()`** — the continuous video recording captures everything; the banner labels each check
- **NEVER skip a test because it takes a long time.** Some operations (video summarization, batch processing) take 30+ minutes — that is expected. Use the Timeout column from the coverage spec to set `page.setDefaultTimeout()` and `page.setDefaultNavigationTimeout()` appropriately. Wait patiently for progress indicators, status changes, and page navigations to complete. Use `page.waitForURL()`, `page.waitForSelector()`, or polling loops with generous timeouts instead of skipping.
- When a test involves a long-running operation, update the banner overlay periodically (e.g., "VU-9: Summarizing... 5min elapsed") so the video recording shows progress.
- **Batch queue completion = UI queue empty.** When a batch operation (e.g., "Upload & Analyze" for multiple videos) shows a processing queue in the UI, the operation is complete as soon as the queue clears (no more "Processing..." or "Queued" items visible). Do NOT poll the API separately or add extra wait logic — just watch the UI queue. Once it's empty, proceed to the next test.

### Step 18: Compile test report

Save the report to `${DAT_SANDBOX}/logs/test-report.txt` and display it:

```
═══════════════════════════════════════════════════
  TEST REPORT — <category> <size>
  Date:          <YYYY-MM-DD>
  Sandbox:       ${DAT_SANDBOX}
═══════════════════════════════════════════════════

  BASE SPEC (.claude/skills/<category>-test-coverage/SKILL.md):
    API Tests:     X/Y passed
    Infra Tests:   X/Y passed
    UI Tests:      X/Y passed

  USER-PROVIDED TESTS:
    API Tests:     X/Y passed   (UT-1, UT-3, ...)
    Infra Tests:   X/Y passed   (UT-2, ...)
    UI Tests:      X/Y passed   (UT-4, ...)

  COMBINED:  X/Y total passed

  FAILED:
  - <ID>: <description>
    Actual:   <what happened>
    Expected: <what should have happened>
    Proposed fix: <concrete diagnosis and suggested fix — e.g., "Pod vss-engine
      is in CrashLoopBackOff due to OOM; increase memory limit in
      blueprint_files.tf from 16Gi to 32Gi" or "Ingress returns 502; backend
      pod not ready — wait for NIM model loading to complete">

  API responses: ${DAT_SANDBOX}/api-results/
  UI recording:  ${DAT_SANDBOX}/ui-recordings/*.webm
  Full report:   ${DAT_SANDBOX}/logs/test-report.txt
═══════════════════════════════════════════════════
```

Omit the "USER-PROVIDED TESTS" section if the user did not provide a matrix. Omit "BASE SPEC" section if no base coverage file exists.

**For every failed test**, include a "Proposed fix" that:
1. Diagnoses the root cause based on the error, logs, pod status, or response body.
2. Suggests a concrete action (code change, config change, wait for readiness, retry, or escalate to user).
3. References the specific file, resource, or config that needs attention.

If any P0 test fails, flag it prominently. Do NOT auto-retry. Let the user decide whether to investigate before proceeding to Phase 4.

### Step 19: Copy artifacts to repo

Before destroy, copy test artifacts from the sandbox into the repo so they persist after the sandbox is deleted:

```bash
# Create artifacts directory in repo
mkdir -p .claude/test-artifacts

# Copy report
cp "${DAT_SANDBOX}/logs/test-report.txt" \
   ".claude/test-artifacts/<category>-<size>-test-report-<YYYY-MM-DD>.txt"

# Copy UI recordings
cp ${DAT_SANDBOX}/ui-recordings/*.webm \
   ".claude/test-artifacts/" 2>/dev/null || true
```

The `.claude/test-artifacts/` directory is gitignored — artifacts are for local review only, not committed.

---

## Phase 4: User Confirmation & Destroy

### Step 20: Prompt user

Show all test results. Ask if any additional manual verification is needed.

Tell the user: *"Test artifacts have been copied to `.claude/test-artifacts/`. The sandbox `${DAT_SANDBOX}/` will persist until you delete it."*

### Step 21: Destroy (on user confirmation)

```bash
oci resource-manager job create-destroy-job \
  --stack-id <stack-id> \
  --execution-plan-strategy AUTO_APPROVED
```

Poll until complete. Verify logs are clean.

---

## Error Handling

| Situation | Action |
|---|---|
| No qualifying regions | Report capacity unavailability, stop |
| Plan fails | Show logs, stop for user input |
| Apply fails | Show logs, stop for user input |
| Pods in CrashLoopBackOff | Check logs, report to user (wait and retry once) |
| Destroy fails on k8s provider | Update stack to Terraform 1.5.x and retry |
| UI tests FAIL | Report to user — user decides whether to investigate before destroy |
