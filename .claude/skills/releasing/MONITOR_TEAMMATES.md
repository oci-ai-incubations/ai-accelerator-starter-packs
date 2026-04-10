# Monitoring Teammates During Release Testing

Guide for the monitoring agent that observes testing teammates during Phase 4 of the release. The monitor verifies skill compliance, independently cross-checks OCI state, and reports deviations to the team lead.

## Role

The monitor is a **read-only observer**. It does NOT:
- Create or modify ORM stacks
- Deploy infrastructure
- Fix issues directly
- Interact with teammates' browser sessions (except to observe)

It DOES:
- Periodically check in with teammates via SendMessage
- Independently verify OCI state via CLI
- Compare teammate actions against the `/testing-pack` skill
- Report deviations to team-lead immediately
- **Log deviations as bugs in `BUGS.md`** via `/bug-tracker log` when a teammate deviates from the skill or team-lead expectations

## Tools Available

| Tool | Use For |
|---|---|
| SendMessage | Ask teammates for status, report to team-lead |
| OCI CLI (`OCI_CLI_PROFILE=<profile>`) | Verify stack variables, job status, resource state |
| agent-browser (own session only) | Check ORM Console state; **MUST use unique session name** (e.g., `--session monitor-session`) |
| context7 MCP | Research OCI documentation if needed |

## What to Monitor

### 1. Zip Path Isolation (Critical)

Each teammate MUST use the pre-built release zip from `release_test_matrix/<VERSION>_<category>.zip`. Verify via:

```bash
# Ask teammate directly
SendMessage: "What zip file path are you uploading to ORM?"
```

**Anti-pattern:** Shared `/tmp/testing-pack.zip` path. When parallel tracks use the same temp path, one track's zip overwrites another's, causing the wrong schema to be deployed (e.g., VSS wizard appearing for enterprise_rag).

### 2. Starter Pack Size (Critical)

The ORM schema defaults `starter_pack_size` to `small`. Teammates MUST explicitly set the correct size for each pack. Verify via:

```bash
# Independent verification via OCI CLI
OCI_CLI_PROFILE=<profile> oci resource-manager stack get \
  --stack-id <stack_ocid> \
  --query 'data.variables' 2>/dev/null | python3 -c "
import json, sys
v = json.load(sys.stdin)
print('starter_pack_size:', v.get('starter_pack_size', 'NOT SET (defaults to small)'))
"
```

**Expected sizes:**
- enterprise_rag: `small`
- enterprise_rag_aiq: `small`
- paas_rag: `small`
- cuopt: `poc`
- vss: `poc`

If `starter_pack_size` is absent from the variables, ORM uses the schema default (`small`). This is CORRECT for enterprise_rag/enterprise_rag_aiq/paas_rag but WRONG for cuopt/vss (should be `poc`).

### 3. Two-Stack Model Compliance

#### BM Tracks (back-to-back)
- Between rounds: destroy app stack ONLY, preserve infra
- Infra stack should remain ACTIVE between rounds
- App stack should be DESTROYED before creating new one

#### VM Tracks (fresh each round)
- Between rounds: destroy BOTH stacks (app first, then infra)
- Clean up orphaned resources (customer secret keys, ADB instances)
- New infra + app stacks from scratch for each pack
- Reusing VM infra causes BUG-012 (stale images) and BUG-009 (stale taints)

Verify via:
```bash
# List stacks in compartment to check what exists
OCI_CLI_PROFILE=<profile> oci resource-manager stack list \
  --compartment-id <compartment_ocid> \
  --region <region> \
  --query 'data[].{"name":"display-name","state":"lifecycle-state","id":"id"}' \
  --output table
```

### 4. Destroy Ordering (BUG-013)

App stack MUST be destroyed and SUCCEEDED before infra destroy starts. If app destroy FAILS, the teammate must NOT proceed to infra destroy.

Verify via:
```bash
# Check job history on a stack
OCI_CLI_PROFILE=<profile> oci resource-manager job list \
  --stack-id <stack_ocid> \
  --query 'data[].{"operation":"operation","status":"lifecycle-state","time":"time-created"}' \
  --output table --sort-by timeCreated --sort-order DESC
```

**Red flag:** An infra destroy job created shortly after a FAILED app destroy job.

### 5. Required Variables for App Stacks

App stacks in the two-stack model require these variables from the infra stack outputs:
- `existing_cluster_id` (always required)
- `existing_node_subnet_id` (required for packs using shared_node_pool — paas_rag, vss)
- `existing_autonomous_db_subnet_id` (required for packs using ADB — paas_rag, enterprise_rag)

Verify via:
```bash
OCI_CLI_PROFILE=<profile> oci resource-manager stack get \
  --stack-id <app_stack_ocid> \
  --query 'data.variables.{cluster: existing_cluster_id, node_subnet: existing_node_subnet_id, adb_subnet: existing_autonomous_db_subnet_id}'
```

Missing `existing_node_subnet_id` causes BUG-006/BUG-016 (subnetId validation error).

### 6. Region and AD Consistency

Each track should deploy in the region/AD assigned during Phase 3. Verify the stack is in the correct region:

```bash
# Stack OCID contains the region: ocid1.ormstack.oc1.<region>.aaa...
echo "<stack_ocid>" | sed 's/.*oc1\.\([^.]*\)\..*/\1/'
```

AD format must be the full fault-domain-prefixed format (e.g., `TrcQ:AP-MELBOURNE-1-AD-1`), not the short form (`AP-MELBOURNE-1-AD-1`).

## Monitoring Cadence

- **Every 5-10 minutes** during active deploys: check teammate status
- **At phase transitions** (infra done → app start, round 1 → round 2): verify compliance
- **After any failure**: check if the teammate is handling it correctly
- **Don't be annoying** — brief pings, not interrogations

## Bug Tracking (CRITICAL)

**Every deviation MUST be logged in `BUGS.md`.** This is not optional. The monitor exists to build institutional knowledge — if a deviation is only reported via SendMessage and not logged, it will be lost and the same mistake will happen in the next release.

### When to log a bug

Log a bug via `/bug-tracker log` whenever:
- A teammate deploys with the wrong configuration (wrong size, wrong region, wrong zip)
- A teammate skips a required skill step (size verification, pod checks, schema validation)
- A teammate violates the two-stack model (VM track preserving infra, BM track destroying infra)
- A teammate breaks destroy ordering (infra before app)
- A teammate's deployment fails due to a missing or incorrect variable
- An OCI CLI cross-check reveals a mismatch between what the teammate reported and what's actually deployed
- Any unexpected infrastructure behavior occurs (GPU not detected, taint persistence, LB orphaned)

### What to include in the bug

Use this format when invoking `/bug-tracker log`:
- **Title:** Short, specific (e.g., "Track 2 deployed vss with wrong size — small instead of poc")
- **Found by:** "Monitor agent during v<VERSION> release testing"
- **Symptoms:** What went wrong and how it was detected
- **Root cause:** Why it happened (skill gap? schema default? agent error? code bug?)
- **Classification:** Is this a **code bug** (needs a code fix), a **skill gap** (needs a skill update), or an **agent error** (needs better instructions)?

### Bug logging flow

```
1. Detect deviation (via SendMessage or OCI CLI cross-check)
2. Log in BUGS.md immediately via /bug-tracker log  ← DO THIS FIRST
3. Report to team-lead via SendMessage with the BUG-NNN ID
4. Continue monitoring
```

Do NOT wait until the end to batch-log bugs. Log them as they are found. The team-lead and future release sessions depend on `BUGS.md` being complete and up-to-date.

## Reporting Format

When a deviation is found, message team-lead with:

```
**DEVIATION: <teammate-name> — <short description> (BUG-NNN)**
- What happened: <what the teammate did>
- What should have happened: <skill phase/step reference>
- Impact: <what could go wrong>
- Status: <FIXED / NEEDS ACTION / WATCHING>
- Evidence: <OCI CLI output or teammate message>
- Bug logged: BUG-NNN in BUGS.md
```

## Checklist Per Teammate

Run through this for each testing teammate:

- [ ] Using correct pre-built release zip (not /tmp or worktree path)
- [ ] Correct `starter_pack_size` set in ORM (not relying on default for poc packs)
- [ ] Deploying in correct region and AD
- [ ] Infra stack created with `deploy_application=false`
- [ ] App stack has `existing_cluster_id` and `existing_node_subnet_id` set
- [ ] Correct two-stack model for track type (BM = back-to-back, VM = fresh)
- [ ] Destroy ordering correct (app before infra)
- [ ] All resources cleaned up after testing complete

## Known Pitfalls from v0.0.6

These were caught by the monitor during this release:

1. **Size mismatch on Track 2** — ORM defaults `starter_pack_size` to `small`, but vss/cuopt should be `poc`. Track 2 deployed with wrong size and had to destroy + re-create. Cost: ~40 minutes.

2. **Missing existing_node_subnet_id** — Track 1 and Track 3 both missed this field in the app stack. Track 3 (paas_rag) failed with subnetId validation error. Track 1 (enterprise_rag) was unaffected because it uses Helm, not blueprints.

3. **BUG-009 taint persistence** — After enterprise_rag Round 1, the nim-llm taint persisted on GPU nodes despite the destroy provisioner. Root cause: provisioner's node selector depends on NFD labels that can't be set when NFD is blocked by the taint. Required manual taint removal.

4. **AD format mismatch** — Track 2 used `UK-LONDON-1-AD-1` instead of `TrcQ:UK-LONDON-1-AD-1`. The capacity check precondition failed.
