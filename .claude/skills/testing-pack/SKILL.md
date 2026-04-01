---
name: testing-pack
description: Deploys and tests a starter pack using the two-stack preserve-infrastructure model via agent-browser. Validates ORM UI schema screens, uploads and applies infra then app stacks, monitors deployment health, and runs application smoke tests. Use when the user says 'test this pack', 'deploy and test', or 'run the two-stack test.'
user-invocable: true
allowed-tools: Bash, Read, Edit, Write, AskUserQuestion, Glob, Grep, Agent
argument-hint: [category] [size]
---

# Testing Pack

End-to-end two-stack testing orchestrator. Manages the full lifecycle: discover/create ORM stacks, validate schema UI, upload zips via CDP, apply infra then app, monitor deployment, run smoke tests, and report results.

**Two-stack model:** `deploy_application=false` creates infra-only (VCN, OKE, GPU nodes). `existing_cluster_id` creates app-only (Corrino, blueprints, Helm) on the existing cluster. App stack can be destroyed independently — GPU nodes are preserved.

## CRITICAL RULES

1. **ALL stack operations MUST use agent-browser.** Do NOT fall back to OCI CLI for stack creation, updates, or applies. The entire point of this skill is to test the user experience through the browser. OCI CLI bypasses ORM's UI validation (required fields, schema visibility) and misses bugs that real users would hit.

2. **On Step 2 (Configure Variables), check for required field validation errors** before clicking Next. Look for "This variable is required" text. If any required fields are empty, fill them via agent-browser (or ask the user for values). Do NOT skip past validation errors.

3. **OCI CLI is ONLY used for:** listing stacks (Phase 1 discovery), resolving compartment OCIDs, and kubectl/helm commands. Never for stack create/update/apply.

4. **Use a unique agent-browser session name** to avoid conflicts with other Claude sessions. Generate one at the start:
   ```bash
   SESSION_NAME="oci-$(date +%s)"
   ```
   Use `--session-name $SESSION_NAME` on ALL agent-browser commands. Close the session when done: `agent-browser --session-name $SESSION_NAME close`

## Arguments

- `$0` - Category: `paas_rag`, `enterprise_rag`, `enterprise_rag_aiq`, `cuopt`, `vss`
- `$1` - Size: `poc`, `small`, `medium` (category-dependent)

---

## Phase -1: Create Isolated Worktree

Create a git worktree based on the **current branch** (not main, unless the current branch IS main). This isolates the test run from the working directory so concurrent work doesn't interfere.

```bash
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
WORKTREE_NAME="testing-pack-$(date +%s)"
WORKTREE_PATH="/tmp/${WORKTREE_NAME}"
# Use --detach to avoid "already checked out" error when the branch is in use
git worktree add --detach "${WORKTREE_PATH}" HEAD
cd "${WORKTREE_PATH}"
echo "Working in worktree: ${WORKTREE_PATH} (detached at ${CURRENT_BRANCH})"
```

All subsequent commands in this skill run from `${WORKTREE_PATH}`. At the end of the test (Phase 7), clean up:

```bash
cd /tmp  # exit the worktree first
git worktree remove "${WORKTREE_PATH}" --force 2>/dev/null
```

---

## Phase 0: Gather Parameters

Always collect before proceeding. Use `AskUserQuestion` for each.

### 0a. Category and size

If not provided as arguments, ask. Valid sizes per category:

| Category | Sizes |
|---|---|
| `cuopt` | `poc`, `small`, `medium` |
| `vss` | `small`, `medium` |
| `paas_rag` | `small`, `medium` |
| `enterprise_rag` | `small` |
| `enterprise_rag_aiq` | `small` |

### 0b. OCI CLI profile

Show available profiles:

```bash
grep '^\[' ~/.oci/config | tr -d '[]'
```

Ask user to select one. Common values: `SANJOSE`, `DEFAULT`.

### 0c. Region

Ask which region to use. Default: `us-sanjose-1`.

### 0d. Compartment

Ask for compartment name. Resolve OCID:

```bash
export OCI_CLI_PROFILE=<profile>
oci iam compartment list --compartment-id-in-subtree true --all \
  --query "data[?name=='<compartment-name>'].id | [0]" --raw-output
```

### 0e. PR-specific requirements

Ask: "Any PR-specific testing requirements or variables I should know about?"

### 0f. Pack-specific required variables

Generate random values for credentials that ORM requires but are only used at apply time. These will be filled into the ORM UI on Step 2:

```bash
# Generate random admin credentials (used for all packs)
ADMIN_USER="admin"
ADMIN_PASS=$(openssl rand -base64 12 | tr -d '/+=' | head -c 16)
ADMIN_EMAIL="test@example.com"
# DB password must be 12+ chars with uppercase, lowercase, number, and special char
DB_PASS="Aa1!$(openssl rand -base64 16 | tr -d '/+=' | head -c 12)"
echo "Admin: $ADMIN_USER / $ADMIN_PASS / $ADMIN_EMAIL / DB: $DB_PASS"
```

Pack-specific credentials to generate:

| Category | Additional required variables |
|---|---|
| `cuopt` | `cuopt_frontend_admin_username`, `cuopt_frontend_admin_password` |
| `enterprise_rag` | `ngc_secret`, `ngc_api_secret` (ask user — these are real API keys) |
| `enterprise_rag_aiq` | `ngc_secret`, `ngc_api_secret`, `tavily_api_key` (ask user) |
| `paas_rag` | None beyond admin/db |
| `vss` | `ngc_secret`, `ngc_api_secret` (ask user) |

**For NGC/Tavily API keys:** ask the user — these are real credentials, not random values.

### 0g. ADB packs

If category is `paas_rag`, `enterprise_rag`, or `enterprise_rag_aiq`, note that it requires `autonomous_db_subnet`. Confirm the schema includes ADB-specific fields.

---

## Phase 1: Discover Existing Stacks

List ORM stacks in the compartment:

```bash
oci resource-manager stack list -c <compartment-ocid> --all \
  --lifecycle-state ACTIVE --region <region> \
  --query "data[].{id:id, name:\"display-name\", time:\"time-created\"}"
```

Classify stacks by name pattern:
- **Infra stack:** name contains `infra` or `infrastructure`
- **App stack:** name contains `app` or `application`

Report findings to user. Ask to confirm which stacks to use. Determine action:

| Infra exists? | App exists? | Action |
|---|---|---|
| Yes | Yes | Update both with new zip |
| Yes | No | Update infra, create new app stack |
| No | Yes | Create new infra, update app stack |
| No | No | Create both stacks |

Record stack OCIDs for later phases.

---

## Phase 2: Zip

### 2a. Set category in auto.tfvars

```bash
echo 'starter_pack_category = "<category>"' > ai-accelerator-tf/starter_pack_category.auto.tfvars
```

### 2b. Regenerate schema

```bash
cd "$(git rev-parse --show-toplevel)"
source venv/bin/activate
python3 create_final_schema.py -c <category>
```

### 2c. Create zip

Same exclusion logic as `/zip-tf`:

```bash
rm -rf ai-accelerator-tf/.terraform ai-accelerator-tf/.terraform.lock.hcl
cd ai-accelerator-tf && zip -r /tmp/testing-pack.zip . \
  -x '.terraform/*' '.terraform.lock.hcl' '*.tfvars' \
  '*__pycache__/*' '*.pytest_cache/*' 'tests/*'
zip /tmp/testing-pack.zip starter_pack_category.auto.tfvars
```

### 2d. Verify zip

```bash
unzip -l /tmp/testing-pack.zip | head -30
# Confirm: schema.yaml present, no .tfvars (except auto.tfvars), TF files at root
```

Same zip is used for both infra and app stacks.

---

## Phase 3: ORM UI Schema Validation

All ORM interactions use `agent-browser` in headed mode (`--headed --session-name oci`).

### 3a. Authenticate to OCI Console

Open the OCI Console and check if authenticated. See [orm-browser-nav.md](references/orm-browser-nav.md) for the full login flow.

1. `agent-browser --headed --session-name oci open "https://cloud.oracle.com"`
2. Take a snapshot — if login form visible (User Name / Password fields, or redirected to sign-in page), ask the user to enter credentials in the browser window. **Wait for user confirmation before proceeding.**
3. If Console home page visible, continue.

### 3b. Verify region

Take a screenshot. Check the region menu button text. If it does not match the target region, switch:

1. Click the region menu button
2. Select the target region
3. Wait for page reload
4. Screenshot to confirm

### 3c. Verify compartment

Check the compartment heading/breadcrumb. If wrong, switch using the compartment picker:

1. Click compartment dropdown
2. Type compartment name to filter
3. Click the matching treeitem
4. Wait for page reload

See `references/orm-browser-nav.md` for selector patterns.

### 3c. Validate infra stack Edit wizard

Navigate to the infra stack detail page. Click "Edit".

**Step 1 (Stack Information):** Screenshot. Verify stack name and description.

**Step 2 (Configure Variables):** Click "Next". Screenshot. Validate:
- `deploy_infrastructure` is checked / true
- `deploy_application` is unchecked / false
- GPU/node pool fields are visible
- `existing_cluster_id` is empty or hidden
- For ADB packs: `autonomous_db_subnet` field is visible

**Cancel** the wizard after validation (do not save).

### 3d. Validate app stack Edit wizard

Navigate to the app stack detail page. Click "Edit".

**Step 2 (Configure Variables):** Click through to Step 2. Screenshot. Validate:
- `deploy_application` is checked / true
- `deploy_infrastructure` is unchecked / false
- `existing_cluster_id` is populated with the infra cluster OCID
- For ADB packs: `autonomous_db_subnet` field is visible and populated

**Cancel** the wizard after validation.

### 3e. Report schema validation results

Summarize which fields were correct/incorrect. If any field is wrong, stop and report to user before proceeding to Phase 4.

---

## Phase 4: Create and Apply Infra Stack

**Do NOT create or fill in the app stack yet.** The app stack needs infra outputs (cluster OCID, ADB subnet OCID) which don't exist until infra apply succeeds.

### 4a. Create infra stack via browser

Navigate to the Create Stack page in agent-browser. Upload the zip via CDP (see `references/cdp-file-upload.md`), fill in the stack name, and click through the wizard:

- Step 1: Upload zip, set name (e.g., `<pack> Infra`), click Next
- Step 2: Fill variables — uncheck `Deploy Application`, check `Skip Capacity Check`, fill admin/DB credentials. Validate no required field errors before clicking Next.
- Step 3: Check "Run apply", click Create

See `references/orm-browser-nav.md` for checkbox toggling, password validation, and React Select patterns.

### 4b. Monitor infra apply

Record the job OCID. Invoke `/monitoring-deployment` or poll via agent-browser eval until the job reaches a terminal state.

**If infra fails:** invoke `/diagnosing-stack`, report to user, stop.

### 4c. Extract infra outputs

After infra succeeds, navigate to the stack's "Application Information" tab and extract:
- **Cluster OCID** — needed for `existing_cluster_id` in app stack
- **ADB Subnet OCID** — needed for `existing_autonomous_db_subnet_id` (for ADB packs)

Use agent-browser eval to get the values:
```bash
agent-browser --session-name $SESSION_NAME eval --stdin <<'EVALEOF'
var iframe = document.querySelector('iframe');
var doc = iframe.contentDocument || iframe.contentWindow.document;
var text = doc.body.innerText;
var cluster = text.match(/OKE Cluster OCID:\s*(ocid1\.\S+)/);
var subnet = text.match(/Autonomous DB Subnet OCID:\s*(ocid1\.\S+)/);
JSON.stringify({cluster: cluster ? cluster[1] : null, subnet: subnet ? subnet[1] : null});
EVALEOF
```

---

## Phase 5: Create and Apply App Stack

**Only proceed after infra outputs are available.**

### 5a. Create app stack via browser

Navigate to Create Stack page. Upload the same zip via CDP. Click through the wizard:

- Step 1: Upload zip, set name (e.g., `<pack> App`), click Next
- Step 2: Fill variables:
  - `Deploy Application` = checked
  - `Skip Capacity Check` = checked
  - `Existing Cluster OCID` = cluster OCID from Phase 4c
  - `Existing Autonomous DB Subnet OCID` = subnet OCID from Phase 4c (for ADB packs)
  - Fill admin/DB credentials (same as infra stack)
  - Validate no required field errors
- Step 3: Check "Run apply", click Create

### 5b. Monitor app apply

Record the job OCID. Invoke `/monitoring-deployment` with cluster OCID and job OCID.

**If app fails:** invoke `/diagnosing-stack`, report to user, stop.

### 5c. Extract app outputs

After app succeeds, extract output URLs from "Application Information" tab:
- `starter_pack_url` / `starter_pack_frontend_url`
- Cluster OCID (for kubectl connection)

---

## Phase 6: Application Testing

### 6a. Get output URLs

From the app stack's "Application Information" tab in agent-browser, extract:
- Frontend URL
- API URL (if separate)

### 6b. Navigate to app

Open the frontend URL in agent-browser. Verify the page loads.

### 6c. Run pack-specific smoke tests

Invoke the appropriate test coverage skill:

| Category | Skill |
|---|---|
| `paas_rag` | `/paas-rag-test-coverage` |
| `enterprise_rag` | `/enterprise-rag-test-coverage` |
| `enterprise_rag_aiq` | `/enterprise-rag-test-coverage` |
| `cuopt` | `/cuopt-test-coverage` |
| `vss` | `/vss-test-coverage` |

Pass the frontend URL and any credentials (Corrino admin username/password from `terraform.tfvars`).

If no pack-specific coverage skill exists, run basic smoke tests:
1. Frontend loads (HTTP 200)
2. Login succeeds (if applicable)
3. Main page renders without errors
4. At least one API health endpoint returns 200

---

## Phase 7: Cleanup and Report

### 7a. Cleanup worktree

```bash
cd /tmp
git worktree remove "${WORKTREE_PATH}" --force 2>/dev/null
agent-browser --session-name $SESSION_NAME close 2>/dev/null
```

### 7b. Report

Present a structured summary:

```
=============================================
  TWO-STACK TEST REPORT - <category> <size>
  Date:   <YYYY-MM-DD>
  Region: <region>
=============================================

SCHEMA VALIDATION:
  Infra stack wizard:  PASS/FAIL
  App stack wizard:    PASS/FAIL
  Field issues:        <list any>

DEPLOYMENT:
  Infra stack apply:   PASS/FAIL  (<duration>)
  App stack apply:     PASS/FAIL  (<duration>)
  Pod status:          X/Y Running

CLUSTER HEALTH:
  Nodes:    <count> Ready
  Core pods: corrino-cp, postgres, portal — <status>
  Pack pods: <list> — <status>

APPLICATION TESTS:
  <test-id>: <description> — PASS/FAIL
  ...

ISSUES:
  - <issue description, affected resource, severity>
  ...

STACK IDs:
  Infra: <ocid>
  App:   <ocid>
=============================================
```

---

## Error Handling

| Situation | Action |
|---|---|
| Schema validation fails | Stop, report to user, do not proceed to apply |
| CDP upload fails | Retry once; if still fails, report and stop |
| Infra apply fails | Show logs, invoke `/diagnosing-stack`, stop for user |
| App apply fails | Show logs, invoke `/diagnosing-stack`, stop for user |
| Pods not healthy after 15min | Invoke `/diagnosing-stack`, report, stop for user |
| App smoke tests fail | Report results, stop for user decision |
| Browser navigation fails | Take screenshot, report current page state, retry once |

**Never auto-remediate.** Always stop and wait for user guidance on failures.

---

## Notes

- ADB packs (`paas_rag`, `enterprise_rag`, `enterprise_rag_aiq`) need `autonomous_db_subnet` visible in both stacks.
- The same zip is used for both infra and app stacks — the schema and variables control which resources are created.
- `deploy_infrastructure` and `deploy_application` are the count-gating variables that separate the two stacks.
- After testing, the user decides whether to destroy the app stack (preserving infra) or both. Use `/destroy-stack` when ready.
