# Two-Stack Testing Skills Design

## Problem

The preserve-infrastructure feature introduces a two-stack deployment model (infra + app), but the existing testing skills (`/deploy-and-test`, `/integration-test`) only handle single-stack workflows. Testing the two-stack model today requires extensive manual orchestration: switching categories, zipping, navigating the OCI console, uploading files, monitoring jobs, connecting to clusters, diagnosing failures. A fresh context window has no idea how to do any of this.

## Goal

Three composable skills that let a user say "go test this pack" and have the agent autonomously:
1. Validate the ORM UI experience (schema-driven forms)
2. Deploy via browser (exactly as a customer would)
3. Monitor jobs and cluster health continuously
4. Diagnose failures with specific recommended fixes
5. Run application-level tests

All via agent-browser for visual observability. Works with fresh context — skills are self-contained.

## Skills Overview

| Skill Name | Slash Command | Purpose | Standalone? |
|---|---|---|---|
| `testing-pack` | `/testing-pack` | End-to-end orchestrator: ORM UI validation, zip, upload, apply, monitor, app tests | Yes |
| `monitoring-deployment` | `/monitoring-deployment` | Continuous ORM job + full cluster health polling | Yes |
| `diagnosing-stack` | `/diagnosing-stack` | Post-failure deep investigation, reports with recommended fixes | Yes |

`/testing-pack` calls `/monitoring-deployment` after each apply and `/diagnosing-stack` on failure. Each skill is independently useful.

## Skill Authoring Constraints

These skills must follow the [Anthropic skill authoring best practices](https://docs.anthropic.com/en/docs/agents-and-tools/agent-skills/skill-authoring):

- **SKILL.md body under 500 lines** — use progressive disclosure, split reference content into separate files
- **Descriptions in third person** — "Deploys and tests...", not "I deploy..." or "Use this to deploy..."
- **Concise** — only include context Claude doesn't already have. Don't explain what Terraform, Helm, or kubectl are.
- **Gerund naming** — `testing-pack`, `monitoring-deployment`, `diagnosing-stack`
- **One-level-deep references** — SKILL.md links to reference files, reference files don't link to other reference files
- **Appropriate freedom** — high freedom for investigation/diagnosis, low freedom for CDP upload and kubeconfig patching (fragile operations)

### File Structure Per Skill

```
testing-pack/
├── SKILL.md                    # Main instructions (<500 lines)
├── references/
│   ├── cdp-file-upload.md      # CDP workaround pattern (shared)
│   ├── kubeconfig-patching.md  # Profile patching pattern (shared)
│   └── orm-browser-nav.md      # Region/compartment/iframe patterns
└── scripts/
    └── cdp_upload.py           # Reusable CDP upload script

monitoring-deployment/
├── SKILL.md                    # Main instructions (<500 lines)
└── references/
    └── kubeconfig-patching.md  # Profile patching pattern (shared)

diagnosing-stack/
├── SKILL.md                    # Main instructions (<500 lines)
├── references/
│   ├── error-catalog.md        # Known error → fix mappings (extensible)
│   └── kubeconfig-patching.md  # Profile patching pattern (shared)
└── scripts/
    └── cdp_upload.py           # If needed for browser interaction
```

Shared reference files (`cdp-file-upload.md`, `kubeconfig-patching.md`) are duplicated across skills rather than cross-referenced to keep each skill self-contained.

## Interaction Model

- **Always ask, never assume** for: region, compartment, OCI CLI profile, pack category/size
- **Diagnosis is report-only** — the agent identifies issues and recommends fixes but never acts autonomously on fixes. The user must approve any remediation action.
- **All ORM interactions use agent-browser** — visual, exactly as a user would do it

---

## Skill 1: `testing-pack`

**Description:** Deploys and tests a starter pack using the two-stack model via agent-browser. Validates ORM UI schema screens, uploads and applies infra then app stacks, monitors deployment health, and runs application smoke tests. Use when testing a pack end-to-end or when the user says "test this pack."

### Arguments
- `$0` — Pack category: `paas_rag`, `enterprise_rag`, `enterprise_rag_aiq`, `cuopt`, `vss`
- `$1` — Size: `poc`, `small`, `medium` (optional, ask if not provided)

### Phase 0: Gather parameters

Always ask (never assume defaults):

1. Pack category + size (if not provided as args)
2. OCI CLI profile — list available profiles: `grep '^\[' ~/.oci/config`
3. Region (e.g., `ap-osaka-1`, `us-ashburn-1`)
4. Compartment name — resolve to OCID via OCI CLI: `oci iam compartment list`
5. PR-specific testing requirements

### Phase 1: Discover existing stacks

Use OCI CLI to list stacks in the compartment:

```bash
export OCI_CLI_PROFILE=<profile>
oci resource-manager stack list \
  --compartment-id <compartment_ocid> \
  --region <region> \
  --lifecycle-state ACTIVE \
  --all
```

Classify stacks by name pattern:
- Infra stack: name contains pack name + "Infra"
- App stack: name contains pack name + "App"

Report what was found. If no stacks exist, ask user if they want to create them. If stacks exist, ask user to confirm which ones to use.

Determine what needs to happen:
- **Both stacks exist, infra succeeded** → update both, apply infra first then app
- **Both stacks exist, infra failed** → update and re-apply infra, then app
- **Only infra exists** → update and apply infra, ask about app stack
- **No stacks exist** → ask user to create via ORM console or provide stack OCIDs
- **App stack exists but infra doesn't** → warn user, ask how to proceed

### Phase 2: Zip latest code

1. Set `starter_pack_category.auto.tfvars` to target category
2. Regenerate schema: `source venv/bin/activate && python3 create_final_schema.py -c <category>`
3. Create zip (same exclusion pattern as `/zip-tf`):
   ```bash
   TIMESTAMP=$(date +"%Y-%m-%d-%H%M")
   ZIP_NAME="zipped/${CATEGORY}-${TIMESTAMP}.zip"
   zip -r "${ZIP_NAME}" ai-accelerator-tf/ \
     -x 'ai-accelerator-tf/.terraform/*' \
     -x 'ai-accelerator-tf/.terraform.lock.hcl' \
     -x '*.tfvars' -x '*__pycache__/*' -x '*.pytest_cache/*'
   zip "${ZIP_NAME}" ai-accelerator-tf/starter_pack_category.auto.tfvars
   ```
4. Verify zip (no secrets, required files present)

Same zip is used for both stacks.

### Phase 3: ORM UI schema validation

Using agent-browser:

1. **Verify region** — check region menu button text, switch if needed
2. **Verify compartment** — check compartment heading, switch if needed
3. **Validate infra stack Edit wizard:**
   - Open Edit Stack → screenshot Step 1 (name, description, TF version)
   - Click Next → screenshot Step 2 (Configure Variables)
   - Verify correct fields visible/hidden for this category
   - Verify default values are correct
   - Verify variable groups are organized properly
   - Cancel out (don't save yet)
4. **Validate app stack Edit wizard:**
   - Same process, but verify app-specific expectations:
     - `Deploy Application` visible and checked
     - `Existing Cluster OCID` visible and populated
     - `Existing Autonomous DB Subnet OCID` visible (for packs using ADB)
     - Infrastructure variables hidden
   - Cancel out

Report any schema issues found.

### Phase 4: Upload and apply

For each stack that needs updating (**infra first, then app**):

1. Navigate to stack in agent-browser (verify region + compartment)
2. Click "Upload new zip file link"
3. Upload zip via CDP workaround:
   - Get CDP port from `agent-browser get cdp-url`
   - Get page WebSocket URL from `curl http://127.0.0.1:<port>/json`
   - Use Python `websocket-client` with `suppress_origin=True`
   - `DOM.enable` → `DOM.getDocument(depth=-1, pierce=True)` → find `input[type="file"]` → `DOM.setFileInputFiles`
4. Click Next through wizard
5. On app stack Step 2: verify infra outputs are populated:
   - `Existing Cluster OCID` — from infra stack outputs
   - `Existing Autonomous DB Subnet OCID` — from infra stack outputs (for ADB packs)
6. Check "Run apply" → Save changes
7. Verify job page appears with In Progress status

**Infra must succeed before app apply starts.**

After infra apply completes:
- Extract outputs (cluster OCID, ADB subnet OCID, etc.) from Application Information tab via agent-browser
- Ensure these values are set in app stack variables before applying

### Phase 5: Monitor deployments

Invoke `/monitoring-deployment` with:
- Cluster OCID (from infra outputs)
- ORM job OCID (from the apply job page)
- Region and OCI CLI profile

Wait for `/monitoring-deployment` to report completion.

If the job fails, invoke `/diagnosing-stack` and report findings to user. Stop and wait for user direction — do not auto-remediate.

### Phase 6: Application testing

Once `/monitoring-deployment` reports all healthy:

1. Get output URLs from the stack's Application Information tab via agent-browser
2. Navigate to the application URL in agent-browser
3. Run pack-specific smoke tests:
   - Verify page loads (200 response, expected content)
   - Check key UI elements render
   - For RAG packs: verify chat interface loads
   - For VSS: verify video upload interface
   - For cuOpt: verify route optimization interface
4. Reference pack-specific test coverage skills (`/enterprise-rag-test-coverage`, `/paas-rag-test-coverage`, etc.) for detailed test matrices

### Phase 7: Report

Structured summary:

```
=== Test Report: <pack> (<size>) ===
Region: <region> | Compartment: <compartment>
Duration: <total time>

Schema Validation:
  Infra stack: [PASS/FAIL] — <details>
  App stack:   [PASS/FAIL] — <details>

Deployment:
  Infra apply: Succeeded (duration)
  App apply:   Succeeded (duration)

Cluster Health:
  Nodes: X/X Ready
  Pods:  X Running | X Completed | X Issues

Application Tests:
  <test results>

Issues Found:
  <any issues with recommended fixes>
```

---

## Skill 2: `monitoring-deployment`

**Description:** Continuously polls ORM job status and logs, scans cluster health across all namespaces (nodes, pods, PVCs, Helm releases), and reports structured status tables. Checks everything every cycle, not just errors. Use when monitoring a running deployment or when the user says "check what's running."

### Arguments
- `$0` — Cluster OCID (to connect via kubectl)
- `$1` — ORM job OCID or stack OCID (optional — also monitors ORM job if provided)

If not provided, ask for: cluster OCID, region, OCI CLI profile.

### Connection setup

1. Generate kubeconfig:
   ```bash
   export OCI_CLI_PROFILE=<profile>
   oci ce cluster create-kubeconfig \
     --cluster-id <cluster_ocid> \
     --file $HOME/.kube/config-<short_name> \
     --region <region> \
     --token-version 2.0.0 --overwrite
   ```
2. **Patch kubeconfig with `--profile`** — the generated kubeconfig does NOT include `--profile` in the exec args. Use the Edit tool to add `- --profile` and `- <profile_name>` before `env: []`. Without this, auth fails silently.
3. Verify: `kubectl get nodes`

### Poll cycle (every 30 seconds)

Each cycle produces a structured status report covering:

**1. ORM Job status + logs** (if tracking a job)
- Check state via agent-browser eval or OCI CLI
- Tail ORM job logs — scroll to bottom of logs in agent-browser, or use `oci resource-manager job get-job-logs`
- Filter out "Still creating..." spam, surface resource creation/completion events and errors
- Report: job state, elapsed time, last meaningful log lines

Example:
```
ORM Job: ormjob20260401... | Apply | In progress (12m elapsed)
  Latest: helm_release.rag[0]: Still creating... [8m20s elapsed]
  Completed: kubernetes_job_v1.corrino_migration_job[0] (16s)
  Completed: null_resource.success_registration[0] (1s)
```

**2. Node health**
```bash
kubectl get nodes -o wide
```
Report: node count, Ready/NotReady, instance types, CPU/memory capacity

**3. Pod status — all namespaces**
```bash
kubectl get pods --all-namespaces
```
Classify every pod: Running (ready), Running (not ready), Pending, CrashLoopBackOff, Error, Completed. Report counts per namespace + list any non-healthy pods with age.

**4. Pending pod investigation**
For each Pending pod:
```bash
kubectl describe pod <name> -n <namespace>
```
Extract Events section. Classify reason: insufficient CPU/memory, taint not tolerated, PVC pending, image pull issue.

**5. CrashLoopBackOff investigation**
For each crashing pod:
```bash
kubectl logs <name> -n <namespace> --tail=20
```
Report last 20 lines of logs.

**6. PVC/PV status**
```bash
kubectl get pvc --all-namespaces
```
Flag any Pending PVCs with reason.

**7. Helm release status**
```bash
helm list --all-namespaces --all
```
Flag any failed or pending-install releases.

### Output format

```
=== Cycle 3 (elapsed: 1m30s) ===
ORM Job: ormjob20260401... | Apply | In progress (2m elapsed)
  Latest: helm_release.rag[0]: Creating... [30s elapsed]

Nodes: 4/4 Ready
Pods:  28 Running | 8 Pending | 1 CrashLoopBackOff | 2 Completed

Issues:
  [PENDING] rag/milvus-standalone — 0/4 nodes: 2 Insufficient cpu, 2 taint {workload: nim-llm}
  [CRASH]   rag/rag-server — Exit code 1, log: "ConnectionRefusedError: milvus:19530"
  [PVC]     rag/milvus — Pending (WaitForFirstConsumer, pod not scheduled)

Healthy namespaces: cluster-tools (9/9), default (5/5), gpu-operator (4/4), kube-system (16/16)
```

### Termination conditions

- ORM job reaches terminal state (Succeeded or Failed)
- All pods are Running/Completed and stable for 2 consecutive cycles
- User interrupts

On termination, produce a final summary. If anything failed, suggest invoking `/diagnosing-stack`.

---

## Skill 3: `diagnosing-stack`

**Description:** Investigates failed ORM stack deployments by analyzing job logs, cluster state, pod events, and Helm releases. Maps errors to known patterns with specific recommended fixes. Reports only — never acts autonomously. Use when a stack apply has failed or when the user says "why did this fail."

### Arguments
- `$0` — Stack OCID or stack name (required)
- `$1` — Region (optional, ask if not provided)

Also asks for: compartment, OCI CLI profile.

### Phase 1: Stack state assessment

1. Navigate to stack via agent-browser (verify region + compartment first)
2. List all jobs — identify the latest failed job
3. If no failed jobs, report stack is healthy and exit

### Phase 2: ORM job log analysis

1. Open the failed job in agent-browser
2. Scroll through logs, extract:
   - All error lines and surrounding context
   - Which Terraform resource failed
   - The specific error message
   - The file and line number
3. Classify the error against the Error Catalog (Phase 4)

### Phase 3: Cluster investigation

If the cluster is reachable (try to get kubeconfig from stack outputs or ask user):

1. **Pod status**: `kubectl get pods --all-namespaces`
2. **Failing pods**: `kubectl describe pod <name> -n <ns>` + `kubectl logs --tail=30`
3. **PVC status**: `kubectl get pvc --all-namespaces` — check for stuck volumes
4. **Helm releases**: `helm list --all-namespaces --all` — check for stale/failed releases
5. **Recent events**: `kubectl get events --sort-by=.lastTimestamp --all-namespaces | tail -30`
6. **Node resources**: `kubectl describe nodes | grep -A 20 "Allocated resources"` — check capacity

### Phase 4: Error catalog

Map failures to known patterns with specific fixes:

| Error Pattern | Root Cause | Recommended Fix |
|---|---|---|
| `cannot re-use a name that is still in use` | Stale Helm release from previous failed apply | `helm uninstall <name> -n <namespace>` then re-apply |
| `Private Endpoint Subnet Ocids cannot be null` | ADB subnet OCID not passed to app stack | Set `existing_autonomous_db_subnet_id` from infra stack output `autonomous_db_subnet_id` |
| `context deadline exceeded` on helm_release | Helm chart timed out waiting for pods to become healthy | Check pod status — likely image pull, scheduling, or dependency issue. Increase `timeout` if pods are progressing but slow. |
| `installation failed` on helm_release | Helm install errored (not timeout) | Check pod logs for the specific container that failed |
| `FailedScheduling: Insufficient cpu/memory` | Pod can't fit on available nodes | Check node capacity vs pod requests. Consider larger node shapes or reducing replica count. |
| `FailedScheduling: untolerated taint` | Pod missing toleration for GPU node taint (`workload: nim-llm`) | Add toleration to pod spec, or ensure enough CPU-only nodes for non-GPU workloads |
| `ImagePullBackOff` | Bad image reference or missing pull secret | Verify image URI exists, check NGC credentials in pull secret |
| `CrashLoopBackOff` | Container keeps crashing on startup | Check pod logs — often a missing dependency (e.g., milvus not reachable), bad config, or OOM |
| `PVC Pending (WaitForFirstConsumer)` | Volume waiting for pod to be scheduled first | Fix the pod scheduling issue — PVC will bind once pod is placed on a node |
| `Terraform 400-InvalidParameter` | Incorrect OCI API parameter | Check the specific parameter name in the error — often a missing or malformed OCID |
| `Terraform 404-NotAuthorizedOrNotFound` | Missing IAM policy or wrong compartment | Verify IAM policies exist for the resource type. Check compartment OCID. |

This catalog is extensible — new error patterns discovered during testing should be added.

### Output format

```
=== Diagnosis: Enterprise RAG AIQ - App Only ===
Stack: ocid1.ormstack...
Region: ap-osaka-1 | Compartment: Grant-Compartment
Failed job: ormjob20260401181856 (Apply, failed after 2m14s)

ROOT CAUSE: Stale Helm release "rag" in namespace "rag"
  Error: cannot re-use a name that is still in use
  Resource: helm_release.rag[0] (helm.tf:511)
  Category: Helm lifecycle issue

CLUSTER STATE:
  Nodes: 4/4 Ready
  Stale Helm releases: rag (namespace: rag, status: failed, revision: 1)
  Pending PVCs: rag/milvus (WaitForFirstConsumer — blocked by pod scheduling)
  Pod summary: 6 Running, 8 Pending, 1 CrashLoopBackOff, 2 Completed

RECOMMENDED FIX:
  1. Connect to cluster:
     export KUBECONFIG=~/.kube/config-osaka-aiq
  2. Remove stale release:
     helm uninstall rag -n rag
  3. Re-apply the App Only stack from ORM

ADDITIONAL OBSERVATIONS:
  - 8 pods Pending due to insufficient CPU on VM.Standard.E5.Flex nodes (6 vCPU each)
  - GPU nodes (BM.GPU4.8, 128 vCPU) have capacity but taint blocks non-NIM pods
  - Consider adding tolerations to supporting services or using larger CPU node shapes
```

---

## Cross-Cutting Concerns

### CDP file upload pattern

All three skills may need to upload zips to ORM via agent-browser. The pattern:

1. `agent-browser get cdp-url` → parse port
2. `curl -s http://127.0.0.1:<port>/json` → find page WebSocket URL
3. Python script with `websocket-client`:
   - `websocket.create_connection(<url>, suppress_origin=True)`
   - `DOM.enable`
   - `DOM.getDocument(depth=-1, pierce=True)`
   - Recursively find `input[type="file"]` across iframe boundaries
   - `DOM.setFileInputFiles` with the file path

This should be documented once and referenced by `/testing-pack` and `/orm-browser`.

### Kubeconfig profile patching

`oci ce cluster create-kubeconfig` does NOT include `--profile` in the exec args. Every skill that connects to kubectl must patch the kubeconfig to add `--profile <name>` before `env: []`. Without this, auth fails with "the server has asked for the client to provide credentials."

### Agent-browser iframe navigation

OCI Console renders content inside `<iframe>` with title "Content body". Key patterns:
- Use `-s "iframe"` with `agent-browser snapshot` to scope to iframe content
- Refs from the main snapshot work on iframe elements (auto-inlined)
- Use `agent-browser eval` to reach DOM elements not exposed in the accessibility tree
- Always verify region and compartment before any ORM operation

### Skill dependencies

```
/testing-pack
  ├── /zip-tf pattern (inline, not invoked as skill)
  ├── /orm-browser pattern (CDP upload, inline)
  ├── /monitoring-deployment (invoked after each apply)
  ├── /diagnosing-stack (invoked on failure)
  └── /<pack>-test-coverage (referenced for test matrices)

/monitoring-deployment
  └── /kubectl pattern (kubeconfig setup, inline)

/diagnosing-stack
  └── /kubectl pattern (kubeconfig setup, inline)
```

## Out of Scope

- Automatic remediation of failures (skills diagnose and recommend only)
- Stack creation from scratch (skills work with existing stacks)
- Destroying stacks (use existing `/destroy-stack`)
- OCI CLI-only mode (all ORM interactions use agent-browser)
- GPU capacity checking / region selection (use existing `/deploy-and-test` Phase 1 for this)
