# Two-Stack Testing Skills Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Three composable Claude Code skills (`testing-pack`, `monitoring-deployment`, `diagnosing-stack`) that automate the two-stack ORM deployment workflow via agent-browser.

**Architecture:** Each skill is a SKILL.md under `.claude/skills/<name>/` with reference files for shared patterns (CDP upload, kubeconfig patching). Skills are independently invocable. `testing-pack` orchestrates the other two.

**Tech Stack:** Claude Code skills (markdown), agent-browser (CDP), Python websocket-client, OCI CLI, kubectl, helm

**Spec:** `docs/superpowers/specs/2026-04-01-two-stack-testing-skills-design.md`

---

## File Structure

```
.claude/skills/
├── testing-pack/
│   ├── SKILL.md                        # Main orchestrator (<500 lines)
│   └── references/
│       ├── cdp-file-upload.md          # CDP file upload workaround
│       ├── kubeconfig-patching.md      # OCI CLI profile patching
│       └── orm-browser-nav.md          # Region/compartment/iframe patterns
│
├── monitoring-deployment/
│   ├── SKILL.md                        # Continuous health polling (<500 lines)
│   └── references/
│       └── kubeconfig-patching.md      # Copy of patching reference
│
└── diagnosing-stack/
    ├── SKILL.md                        # Failure investigation (<500 lines)
    └── references/
        ├── error-catalog.md            # Known error → fix mappings
        └── kubeconfig-patching.md      # Copy of patching reference
```

Also creates:
- `.claude/skills/testing-pack/scripts/cdp_upload.py` — reusable CDP file upload script

---

### Task 1: Create shared reference files

These reference files capture the fragile, low-freedom patterns discovered during this session. They're duplicated into each skill that needs them to keep skills self-contained.

**Files:**
- Create: `.claude/skills/testing-pack/references/cdp-file-upload.md`
- Create: `.claude/skills/testing-pack/references/kubeconfig-patching.md`
- Create: `.claude/skills/testing-pack/references/orm-browser-nav.md`
- Create: `.claude/skills/testing-pack/scripts/cdp_upload.py`

- [ ] **Step 1: Create the CDP file upload reference**

Create `.claude/skills/testing-pack/references/cdp-file-upload.md`:

```markdown
# CDP File Upload for ORM

ORM's file input is a hidden `<input type="file">` inside an iframe wrapped in a custom button. `agent-browser upload` does not work on it. Use CDP directly.

## Prerequisites

- `agent-browser` running with a page open to an ORM Edit Stack wizard
- Python `websocket-client` package available

## Steps

1. Get the CDP port:
   ```bash
   CDP_URL=$(agent-browser get cdp-url)
   CDP_PORT=$(echo "$CDP_URL" | sed -n 's|.*127.0.0.1:\([0-9]*\).*|\1|p')
   ```

2. Get the page WebSocket URL:
   ```bash
   PAGE_WS=$(curl -s "http://127.0.0.1:${CDP_PORT}/json" | python3 -c "
   import sys, json
   targets = json.load(sys.stdin)
   for t in targets:
       if 'Oracle Cloud' in t.get('title', '') or 'Stack' in t.get('title', ''):
           print(t['webSocketDebuggerUrl'])
           break
   ")
   ```

3. Run the upload script:
   ```bash
   python3 .claude/skills/testing-pack/scripts/cdp_upload.py "${PAGE_WS}" "/path/to/file.zip"
   ```

## Why this works

- `suppress_origin=True` bypasses Chrome's origin check on the DevTools WebSocket
- `DOM.getDocument(depth=-1, pierce=True)` traverses into iframe content documents
- `DOM.setFileInputFiles` sets the file directly on the hidden input, bypassing the native file dialog
```

- [ ] **Step 2: Create the CDP upload Python script**

Create `.claude/skills/testing-pack/scripts/cdp_upload.py`:

```python
#!/usr/bin/env python3
"""Upload a file to an ORM stack's hidden file input via CDP.

Usage: python3 cdp_upload.py <websocket_url> <file_path>
"""
import sys
import json
import websocket


def main():
    if len(sys.argv) != 3:
        print(f"Usage: {sys.argv[0]} <websocket_url> <file_path>", file=sys.stderr)
        sys.exit(1)

    ws_url, file_path = sys.argv[1], sys.argv[2]
    ws = websocket.create_connection(ws_url, suppress_origin=True)
    msg_id = 0

    def send(method, params=None):
        nonlocal msg_id
        msg_id += 1
        payload = {"id": msg_id, "method": method}
        if params:
            payload["params"] = params
        ws.send(json.dumps(payload))
        while True:
            result = json.loads(ws.recv())
            if result.get("id") == msg_id:
                if "error" in result:
                    raise RuntimeError(f"{method}: {result['error']}")
                return result.get("result", {})

    def find_file_inputs(node):
        results = []
        if node.get("nodeName", "").lower() == "input":
            attrs = node.get("attributes", [])
            for i in range(0, len(attrs), 2):
                if attrs[i] == "type" and attrs[i + 1] == "file":
                    results.append(node)
        for child in node.get("children", []):
            results.extend(find_file_inputs(child))
        if "contentDocument" in node:
            results.extend(find_file_inputs(node["contentDocument"]))
        return results

    send("DOM.enable")
    doc = send("DOM.getDocument", {"depth": -1, "pierce": True})
    inputs = find_file_inputs(doc["root"])

    if not inputs:
        print("ERROR: No file input found in DOM", file=sys.stderr)
        ws.close()
        sys.exit(1)

    send("DOM.setFileInputFiles", {
        "files": [file_path],
        "backendNodeId": inputs[0]["backendNodeId"],
    })
    print(f"SUCCESS: {file_path}")
    ws.close()


if __name__ == "__main__":
    main()
```

- [ ] **Step 3: Create the kubeconfig patching reference**

Create `.claude/skills/testing-pack/references/kubeconfig-patching.md`:

```markdown
# Kubeconfig Profile Patching

`oci ce cluster create-kubeconfig` generates a kubeconfig that does NOT include `--profile` in the exec args. Without patching, `oci ce cluster generate-token` falls back to the DEFAULT profile, which may not have access to the cluster's tenancy.

## Symptom

```
error: You must be logged in to the server (the server has asked for the client to provide credentials)
```

## Fix

After generating the kubeconfig, use the Edit tool to add two lines before `env: []`:

```yaml
      - --region
      - <region>
      - --profile          # ADD THIS
      - <profile_name>     # ADD THIS
      env: []
```

## Generate + Patch sequence

```bash
export OCI_CLI_PROFILE=<profile>
oci ce cluster create-kubeconfig \
  --cluster-id <cluster_ocid> \
  --file $HOME/.kube/config-<short_name> \
  --region <region> \
  --token-version 2.0.0 --overwrite
```

Then use the Edit tool on `$HOME/.kube/config-<short_name>` to insert `- --profile` and `- <profile>` before `env: []`.

Verify: `KUBECONFIG=$HOME/.kube/config-<short_name> kubectl get nodes`
```

- [ ] **Step 4: Create the ORM browser navigation reference**

Create `.claude/skills/testing-pack/references/orm-browser-nav.md`:

```markdown
# ORM Browser Navigation Patterns

## Region verification

Check current region from the region menu button text:
```bash
agent-browser snapshot -i | grep "Region menu"
```
If wrong, click the region button, wait for menu, click the target region menuitem.

## Compartment selection

On the Stacks list page, click the compartment dropdown button, type the compartment name in the search field, then click the matching treeitem:
```bash
agent-browser snapshot -i -s "iframe"
# Find and click compartment selector button
agent-browser click @<selector-ref>
agent-browser wait 1000
# Type compartment name in search
agent-browser fill @<search-ref> "<compartment>"
agent-browser wait 2000
# Click the matching treeitem
agent-browser click @<compartment-ref>
agent-browser wait --load networkidle
```

## Iframe scoping

OCI Console content is inside `<iframe>` titled "Content body". Key patterns:
- `agent-browser snapshot -i -s "iframe"` — scope snapshot to iframe content
- Refs from the main snapshot work on iframe elements (auto-inlined)
- `agent-browser eval` runs in the main frame; access iframe DOM via:
  ```javascript
  var iframe = document.querySelector('iframe');
  var doc = iframe.contentDocument || iframe.contentWindow.document;
  ```

## Edit Stack wizard navigation

After clicking "Upload new zip file link", the wizard opens:
1. Step 1 (Stack information) — upload file, click Next (`@<next-ref>`)
2. Step 2 (Configure variables) — verify/fill variables, click Next
3. Step 3 (Review) — scroll down, check "Run apply", click "Save changes"

Wait for `networkidle` + 3-5 seconds between steps (ORM UI is slow).
```

- [ ] **Step 5: Commit**

```bash
git add .claude/skills/testing-pack/references/ .claude/skills/testing-pack/scripts/
git commit -m "feat: add shared reference files for two-stack testing skills

CDP file upload, kubeconfig patching, and ORM browser navigation
patterns extracted from manual testing session.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Create `monitoring-deployment` skill

Simplest skill — no dependency on other skills. Build this first.

**Files:**
- Create: `.claude/skills/monitoring-deployment/SKILL.md`
- Create: `.claude/skills/monitoring-deployment/references/kubeconfig-patching.md` (copy from Task 1)

- [ ] **Step 1: Copy kubeconfig reference**

```bash
mkdir -p .claude/skills/monitoring-deployment/references
cp .claude/skills/testing-pack/references/kubeconfig-patching.md \
   .claude/skills/monitoring-deployment/references/
```

- [ ] **Step 2: Create SKILL.md**

Create `.claude/skills/monitoring-deployment/SKILL.md`:

```markdown
---
name: monitoring-deployment
description: Continuously polls ORM job status and logs, scans cluster health across all namespaces (nodes, pods, PVCs, Helm releases), and reports structured status tables. Checks everything every cycle, not just errors. Use when monitoring a running deployment or when the user says "check what's running" or "monitor the deploy."
user-invocable: true
allowed-tools: Bash, Read, Edit, AskUserQuestion, Glob
argument-hint: [cluster-ocid] [job-or-stack-ocid]
---

# Monitoring Deployment

Continuously poll ORM job status + full cluster health. Reports everything every cycle.

## Arguments

- `$0` — Cluster OCID (optional — ask if not provided)
- `$1` — ORM job or stack OCID (optional — skip ORM monitoring if not provided)

If not provided, ask for: cluster OCID, region, OCI CLI profile.

## Phase 1: Connect to cluster

Generate kubeconfig and patch with profile. See [kubeconfig-patching.md](references/kubeconfig-patching.md) for the exact procedure — this is critical, auth fails silently without the profile patch.

```bash
export OCI_CLI_PROFILE=<profile>
oci ce cluster create-kubeconfig \
  --cluster-id <cluster_ocid> \
  --file $HOME/.kube/config-monitor \
  --region <region> \
  --token-version 2.0.0 --overwrite
```

Then patch the kubeconfig and verify: `KUBECONFIG=$HOME/.kube/config-monitor kubectl get nodes`

## Phase 2: Poll cycle (repeat every 30 seconds)

Each cycle collects and reports all of the following:

### 2a. ORM Job status + logs

If tracking a job, check state and tail logs:

```bash
# Via OCI CLI:
export OCI_CLI_PROFILE=<profile>
oci resource-manager job get --job-id <job_ocid> --query 'data.{status:"lifecycle-state",type:"operation"}' --output table
oci resource-manager job get-job-logs --job-id <job_ocid> --all --query 'data[-20:].[message]' --output table
```

Or via agent-browser eval if a browser session is active:
```javascript
var iframe = document.querySelector('iframe');
var doc = iframe.contentDocument || iframe.contentWindow.document;
var statusEl = doc.querySelector('[role="status"]');
statusEl ? statusEl.textContent.trim() : 'unknown';
```

Filter out "Still creating..." spam. Surface resource completions and errors.

### 2b. Node health

```bash
export KUBECONFIG=$HOME/.kube/config-monitor
kubectl get nodes -o custom-columns='NAME:.metadata.name,STATUS:.status.conditions[-1].type,TYPE:.metadata.labels.beta\.kubernetes\.io/instance-type,CPU:.status.capacity.cpu,MEM:.status.capacity.memory,GPU:.status.capacity.nvidia\.com/gpu'
```

### 2c. Pod status — all namespaces

```bash
kubectl get pods --all-namespaces --no-headers | awk '{ns=$1; name=$2; ready=$3; status=$4; print ns, name, ready, status}'
```

Classify every pod: Running (ready), Running (not ready), Pending, CrashLoopBackOff, Error, Completed.

### 2d. Investigate non-healthy pods

For each Pending pod — extract scheduling failure reason:
```bash
kubectl describe pod <name> -n <ns> | grep -A 5 "Events:"
```

For each CrashLoopBackOff pod — get recent logs:
```bash
kubectl logs <name> -n <ns> --tail=20
```

### 2e. PVC status

```bash
kubectl get pvc --all-namespaces --no-headers
```

Flag any Pending PVCs.

### 2f. Helm releases

```bash
helm list --all-namespaces --all
```

Flag any `failed` or `pending-install` releases.

## Output format

```
=== Cycle N (elapsed: Xm) ===
ORM Job: <id> | <type> | <state> (<elapsed>)
  <last meaningful log lines>

Nodes: X/X Ready
Pods:  X Running | X Pending | X CrashLoop | X Completed

Issues:
  [PENDING] <ns>/<pod> — <reason>
  [CRASH]   <ns>/<pod> — <last log line>
  [PVC]     <ns>/<pvc> — <reason>
  [HELM]    <release> — <status>

Healthy: <ns> (X/X), <ns> (X/X), ...
```

## Termination

Stop polling when:
- ORM job reaches terminal state (Succeeded or Failed)
- All pods Running/Completed and stable for 2 consecutive cycles
- User interrupts

Final summary on termination. If failures found, suggest: "Run `/diagnosing-stack <stack-ocid>` for detailed investigation."
```

- [ ] **Step 3: Verify skill appears in skill list**

```bash
# The skill should appear when you type /monitoring-deployment
# Verify the SKILL.md is valid by checking frontmatter
head -5 .claude/skills/monitoring-deployment/SKILL.md
```

- [ ] **Step 4: Commit**

```bash
git add .claude/skills/monitoring-deployment/
git commit -m "feat: add monitoring-deployment skill

Continuous ORM job + cluster health polling across all namespaces.
Reports structured status tables every 30s.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Create `diagnosing-stack` skill

**Files:**
- Create: `.claude/skills/diagnosing-stack/SKILL.md`
- Create: `.claude/skills/diagnosing-stack/references/error-catalog.md`
- Create: `.claude/skills/diagnosing-stack/references/kubeconfig-patching.md` (copy)

- [ ] **Step 1: Create directory and copy kubeconfig reference**

```bash
mkdir -p .claude/skills/diagnosing-stack/references
cp .claude/skills/testing-pack/references/kubeconfig-patching.md \
   .claude/skills/diagnosing-stack/references/
```

- [ ] **Step 2: Create the error catalog**

Create `.claude/skills/diagnosing-stack/references/error-catalog.md`:

```markdown
# Error Catalog

Known ORM/Kubernetes failure patterns with recommended fixes. Extend this file when new patterns are discovered.

## Helm Lifecycle

| Pattern | Root Cause | Fix |
|---|---|---|
| `cannot re-use a name that is still in use` | Stale Helm release from previous failed apply | `helm uninstall <name> -n <namespace>` then re-apply |
| `context deadline exceeded` on helm_release | Chart timed out waiting for pods | Check pod status — scheduling, image pull, or dependency issue |
| `installation failed` on helm_release | Helm install error (not timeout) | Check pod logs for the failing container |

## OCI / Terraform

| Pattern | Root Cause | Fix |
|---|---|---|
| `Private Endpoint Subnet Ocids cannot be null` | ADB subnet OCID missing in app stack | Set `existing_autonomous_db_subnet_id` from infra stack output |
| `400-InvalidParameter` | Incorrect OCI API parameter | Check the parameter name — often a missing or malformed OCID |
| `404-NotAuthorizedOrNotFound` | Missing IAM policy or wrong compartment | Verify IAM policies and compartment OCID |

## Kubernetes Scheduling

| Pattern | Root Cause | Fix |
|---|---|---|
| `FailedScheduling: Insufficient cpu/memory` | Pod requests exceed node capacity | Larger node shape, fewer replicas, or lower resource requests |
| `FailedScheduling: untolerated taint` | Pod missing toleration (e.g., `workload: nim-llm`) | Add toleration or ensure enough non-tainted nodes |
| `ImagePullBackOff` | Bad image URI or missing pull secret | Verify image exists, check NGC credentials |
| `CrashLoopBackOff` | Container crashing on startup | Check logs — often missing dependency, bad config, or OOM |
| `PVC Pending (WaitForFirstConsumer)` | Volume waiting for pod scheduling | Fix the pod scheduling issue first — PVC binds after placement |
```

- [ ] **Step 3: Create SKILL.md**

Create `.claude/skills/diagnosing-stack/SKILL.md`:

```markdown
---
name: diagnosing-stack
description: Investigates failed ORM stack deployments by analyzing job logs, cluster state, pod events, and Helm releases. Maps errors to known patterns with specific recommended fixes. Reports only, never acts autonomously. Use when a stack apply failed or when the user says "why did this fail" or "diagnose this stack."
user-invocable: true
allowed-tools: Bash, Read, Edit, AskUserQuestion, Glob
argument-hint: <stack-ocid-or-name> [region]
---

# Diagnosing Stack

Deep investigation of failed ORM stack deployments. Reports findings with recommended fixes. **Never acts — only diagnoses.**

## Arguments

- `$0` — Stack OCID or stack name (required)
- `$1` — Region (optional, ask if not provided)

Also ask for: compartment name, OCI CLI profile.

## Phase 1: Stack state assessment

Use OCI CLI to get the stack and its jobs:

```bash
export OCI_CLI_PROFILE=<profile>
# If given a name, list stacks and find it
oci resource-manager stack list --compartment-id <ocid> --region <region> --all \
  --query "data[?contains(\"display-name\", '<name>')]"

# Get jobs for the stack
oci resource-manager job list --stack-id <stack_ocid> --all \
  --query 'data[].{name:"display-name",type:operation,state:"lifecycle-state",time:"time-created"}' --output table
```

If no failed jobs, report stack is healthy and exit.

## Phase 2: ORM job log analysis

Get logs from the latest failed job:

```bash
oci resource-manager job get-job-logs --job-id <job_ocid> --all \
  --query 'data[].message' --output table
```

Or use agent-browser if a browser session is active — navigate to the job page, scroll through logs.

Extract:
- All error lines and surrounding context
- Which Terraform resource failed
- The specific error message and file/line reference

## Phase 3: Cluster investigation

If the cluster is reachable (get OCID from stack outputs or variables, ask user for kubeconfig):

Connect using the procedure in [kubeconfig-patching.md](references/kubeconfig-patching.md).

Then run:

```bash
export KUBECONFIG=<path>

# Full pod status
kubectl get pods --all-namespaces

# Failing pods — events and logs
kubectl describe pod <name> -n <ns> | tail -20
kubectl logs <name> -n <ns> --tail=30

# PVC status
kubectl get pvc --all-namespaces

# Helm releases (check for stale/failed)
kubectl get pvc --all-namespaces
helm list --all-namespaces --all

# Recent events
kubectl get events --sort-by=.lastTimestamp --all-namespaces | tail -30

# Node resource allocation
kubectl describe nodes | grep -A 20 "Allocated resources"
```

## Phase 4: Error matching

Match the failure against known patterns in [error-catalog.md](references/error-catalog.md).

If the error matches a catalog entry, use the recommended fix verbatim.

If no match, provide:
- The exact error text
- The resource and file/line that failed
- Cluster state observations
- Your best assessment of root cause and suggested fix

## Output format

```
=== Diagnosis: <stack name> ===
Stack: <ocid>
Region: <region> | Compartment: <compartment>
Failed job: <job_id> (<type>, failed after <duration>)

ROOT CAUSE: <one-line summary>
  Error: <exact error text>
  Resource: <terraform resource> (<file>:<line>)
  Category: <error catalog category>

CLUSTER STATE:
  Nodes: X/X Ready
  <any stale Helm releases, pending PVCs, failing pods>

RECOMMENDED FIX:
  <numbered steps with exact commands>

ADDITIONAL OBSERVATIONS:
  <anything else noteworthy>
```
```

- [ ] **Step 4: Commit**

```bash
git add .claude/skills/diagnosing-stack/
git commit -m "feat: add diagnosing-stack skill

Post-failure investigation for ORM stacks. Analyzes job logs,
cluster state, and maps errors to known fix patterns.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: Create `testing-pack` skill

The main orchestrator. References the other two skills and the shared reference files.

**Files:**
- Create: `.claude/skills/testing-pack/SKILL.md`

- [ ] **Step 1: Create SKILL.md**

Create `.claude/skills/testing-pack/SKILL.md`:

```markdown
---
name: testing-pack
description: Deploys and tests a starter pack using the two-stack preserve-infrastructure model via agent-browser. Validates ORM UI schema screens, uploads and applies infra then app stacks, monitors deployment health, and runs application smoke tests. Use when the user says "test this pack", "deploy and test", or "run the two-stack test."
user-invocable: true
allowed-tools: Bash, Read, Edit, Write, AskUserQuestion, Glob, Grep, Agent
argument-hint: [category] [size]
---

# Testing Pack

End-to-end user acceptance test for a starter pack using the two-stack model. Simulates the full customer journey: ORM UI validation, deploy via browser, monitor health, test application.

**All ORM interactions use agent-browser** — visual, exactly as a customer would do it.

## Arguments

- `$0` — Pack category: `paas_rag`, `enterprise_rag`, `enterprise_rag_aiq`, `cuopt`, `vss`
- `$1` — Size: `poc`, `small`, `medium` (optional, ask if not provided)

## Phase 0: Gather parameters

**Always ask, never assume defaults:**

1. Pack category + size (if not from args)
2. OCI CLI profile: `grep '^\[' ~/.oci/config`
3. Region (e.g., `ap-osaka-1`, `us-ashburn-1`)
4. Compartment name — resolve OCID: `oci iam compartment list --compartment-id-in-subtree true --all --query "data[?name=='<name>'].id" --output table`
5. PR-specific testing requirements

## Phase 1: Discover existing stacks

```bash
export OCI_CLI_PROFILE=<profile>
oci resource-manager stack list \
  --compartment-id <compartment_ocid> \
  --region <region> --lifecycle-state ACTIVE --all \
  --query 'data[].{name:"display-name",id:id,time:"time-created"}' --output table
```

Classify by name pattern:
- **Infra**: name contains pack keyword + "Infra"
- **App**: name contains pack keyword + "App"

Report findings. Ask user to confirm which stacks to use.

Determine action:
- Both exist, infra healthy → update both, apply infra first then app
- Both exist, infra failed → re-apply infra, then app
- Only infra exists → apply infra, ask about app
- No stacks → ask user to create or provide OCIDs
- App without infra → warn, ask how to proceed

## Phase 2: Zip latest code

1. Update `starter_pack_category.auto.tfvars`:
   ```bash
   sed -i '' 's/starter_pack_category = ".*"/starter_pack_category = "<category>"/' \
     ai-accelerator-tf/starter_pack_category.auto.tfvars
   ```

2. Regenerate schema:
   ```bash
   source venv/bin/activate && python3 create_final_schema.py -c <category>
   ```

3. Create zip:
   ```bash
   TIMESTAMP=$(date +"%Y-%m-%d-%H%M")
   ZIP_NAME="zipped/<category>-${TIMESTAMP}.zip"
   zip -r "${ZIP_NAME}" ai-accelerator-tf/ \
     -x 'ai-accelerator-tf/.terraform/*' -x 'ai-accelerator-tf/.terraform.lock.hcl' \
     -x '*.tfvars' -x '*__pycache__/*' -x '*.pytest_cache/*'
   zip "${ZIP_NAME}" ai-accelerator-tf/starter_pack_category.auto.tfvars
   ```

4. Verify zip (no `.terraform/`, no sensitive `.tfvars`, has `starter_pack_category.auto.tfvars`)

## Phase 3: ORM UI schema validation

Launch agent-browser if not running: `agent-browser --headed open https://cloud.oracle.com`

If not logged in (login form visible), ask user to enter credentials manually.

1. **Verify region** — check region menu button, switch if needed. See [orm-browser-nav.md](references/orm-browser-nav.md).
2. **Verify compartment** — navigate to stacks, check compartment heading, switch if needed.
3. **Validate infra stack wizard:**
   - Navigate to infra stack URL
   - Click Edit → Edit stack
   - Screenshot Step 1, click Next
   - Screenshot Step 2 — verify fields visible/hidden for category, defaults correct
   - Cancel out
4. **Validate app stack wizard:**
   - Same process, verify app-specific fields:
     - `Deploy Application` visible and checked
     - `Existing Cluster OCID` visible and populated
     - `Existing Autonomous DB Subnet OCID` visible (for ADB packs: `paas_rag`, `enterprise_rag`, `enterprise_rag_aiq`)
   - Cancel out

Report schema issues.

## Phase 4: Upload and apply

For each stack (**infra first, then app**):

1. Navigate to stack in agent-browser
2. Click "Upload new zip file link"
3. Upload via CDP — see [cdp-file-upload.md](references/cdp-file-upload.md). Run the script:
   ```bash
   CDP_URL=$(agent-browser get cdp-url)
   CDP_PORT=$(echo "$CDP_URL" | sed -n 's|.*127.0.0.1:\([0-9]*\).*|\1|p')
   PAGE_WS=$(curl -s "http://127.0.0.1:${CDP_PORT}/json" | python3 -c "
   import sys, json
   for t in json.load(sys.stdin):
       if 'Oracle Cloud' in t.get('title',''):
           print(t['webSocketDebuggerUrl']); break
   ")
   python3 .claude/skills/testing-pack/scripts/cdp_upload.py "${PAGE_WS}" "${ZIP_NAME}"
   ```
4. Click Next through wizard steps
5. On app stack Step 2: verify infra outputs populated (cluster OCID, ADB subnet)
6. Check "Run apply" → Save changes

**After infra succeeds:**
- Extract outputs from Application Information tab (cluster OCID, ADB subnet OCID)
- Ensure these values are set in app stack variables

## Phase 5: Monitor

Invoke `/monitoring-deployment` with cluster OCID, ORM job OCID, region, and profile.

If job fails, invoke `/diagnosing-stack` with the stack OCID. Report findings to user. **Stop and wait for user direction — do not auto-remediate.**

## Phase 6: Application testing

Once all pods healthy:

1. Get output URLs from stack Application Information tab
2. Navigate to app URL in agent-browser
3. Run pack-specific smoke tests:
   - Page loads (check for expected content)
   - Key UI elements render
   - Reference `/<pack>-test-coverage` skills for detailed matrices
4. Take screenshots of key screens

## Phase 7: Report

```
=== Test Report: <pack> (<size>) ===
Region: <region> | Compartment: <compartment>
Duration: <total>

Schema Validation: Infra [PASS/FAIL] | App [PASS/FAIL]
Deployment: Infra [Succeeded/<duration>] | App [Succeeded/<duration>]
Cluster: X/X nodes Ready | X pods Running | X issues
App Tests: <results>
Issues: <any issues with fixes>
```
```

- [ ] **Step 2: Verify skill appears and references are accessible**

```bash
# Check skill frontmatter is valid
head -5 .claude/skills/testing-pack/SKILL.md

# Check all reference files exist
ls .claude/skills/testing-pack/references/
ls .claude/skills/testing-pack/scripts/

# Check SKILL.md line count is under 500
wc -l .claude/skills/testing-pack/SKILL.md
```

- [ ] **Step 3: Commit**

```bash
git add .claude/skills/testing-pack/
git commit -m "feat: add testing-pack skill

End-to-end two-stack test orchestrator. Validates ORM UI schemas,
uploads and applies via browser, monitors health, runs app tests.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: Clean up superseded skills

The new `testing-pack` skill replaces the prototype skills created earlier in this session (`orm-browser`, `kubectl`). Remove them to avoid confusion.

**Files:**
- Delete: `.claude/skills/orm-browser/SKILL.md`
- Delete: `.claude/skills/kubectl/SKILL.md`

- [ ] **Step 1: Remove prototype skills**

```bash
rm -rf .claude/skills/orm-browser
rm -rf .claude/skills/kubectl
```

- [ ] **Step 2: Commit**

```bash
git add -A .claude/skills/orm-browser .claude/skills/kubectl
git commit -m "chore: remove prototype orm-browser and kubectl skills

Superseded by testing-pack, monitoring-deployment, and
diagnosing-stack skills which incorporate these patterns.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

### Task 6: Smoke test all three skills

Verify each skill loads correctly and the descriptions trigger appropriately.

- [ ] **Step 1: Verify skill discovery**

In Claude Code, check that all three skills appear in the skill list:
- `/testing-pack` — should appear
- `/monitoring-deployment` — should appear
- `/diagnosing-stack` — should appear

Check that the removed skills no longer appear:
- `/orm-browser` — should NOT appear
- `/kubectl` — should NOT appear

- [ ] **Step 2: Verify SKILL.md line counts**

```bash
echo "testing-pack:" && wc -l .claude/skills/testing-pack/SKILL.md
echo "monitoring-deployment:" && wc -l .claude/skills/monitoring-deployment/SKILL.md
echo "diagnosing-stack:" && wc -l .claude/skills/diagnosing-stack/SKILL.md
```

All should be under 500 lines.

- [ ] **Step 3: Verify reference files are one level deep**

```bash
# No references should link to other reference files
grep -r "references/" .claude/skills/*/references/ 2>/dev/null | grep -v "^Binary" || echo "OK: no nested references"
```

- [ ] **Step 4: Quick invocation test**

Invoke `/monitoring-deployment` without arguments — it should ask for cluster OCID, region, and profile. Verify the AskUserQuestion flow works.

- [ ] **Step 5: Commit any fixes**

If any issues found during testing, fix and commit.
