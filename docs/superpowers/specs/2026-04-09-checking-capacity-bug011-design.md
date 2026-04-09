# BUG-011 Fix: Extend /checking-capacity to Check All Pack Resource Quotas

**Date:** 2026-04-09
**Status:** Approved
**Bug:** BUG-011 — /checking-capacity only checks GPU, misses FSS, ADB, and other resource quotas

## Problem

`/checking-capacity` only validates GPU hardware capacity and tenancy GPU quota. It does not check quotas for other resources each pack requires (FSS mount targets for VSS, ADB instances for paas_rag/enterprise_rag). This caused a deployment failure when the skill recommended us-sanjose-1 for VSS but FSS mount target quota was exhausted (2/2 used).

## Correction to BUG-011

The original bug description listed `enterprise_rag_aiq` as needing ADB. This is incorrect. Per `vars.tf:1023`: `needs_26ai = contains(["paas_rag", "enterprise_rag"], var.starter_pack_category)` — `enterprise_rag_aiq` is excluded.

## Design Decision: Approach 2 — Pack Resource Manifest + Unified Check Loop

Define a per-pack resource manifest dynamically from the Terraform code, then scan all manifest resources in a single region loop. A region is READY only if ALL required resources pass.

Rejected alternatives:
- **Approach 1 (Inline expansion):** Adding checks inline to existing phases would make the 170-line skill harder to follow.
- **Approach 3 (Separate /checking-quota skill):** Splits a single "can I deploy here?" answer across two tools. YAGNI.

## Scope

- Fix the `/checking-capacity` skill only (`.claude/skills/checking-capacity/SKILL.md`)
- No changes to `capacity_check.tf` (Terraform preconditions)
- Pack-aware only — no standalone service quota checking mode
- Raw shape mode (`/checking-capacity BM.GPU4.8`) unchanged — skips audit, GPU only

## Phase 1: Full Repo Audit & Build Manifest

Every invocation starts by auditing the Terraform code to build the resource manifest dynamically. This ensures the manifest stays in sync with the codebase.

### Steps

1. Grep all `*.tf` files in `ai-accelerator-tf/` for `resource "oci_` to find every OCI resource.
2. For each resource, extract:
   - Resource type (e.g., `oci_file_storage_mount_target`)
   - Count/for_each condition (e.g., `local.deploy_app_vss ? 1 : 0`)
   - Which pack categories trigger it (trace the condition back to `starter_pack_category`)
3. Filter to quota-critical resource types. Known OCI resource type to service limit mapping:
   - `oci_file_storage_file_system` → service: `filesystem`, limit: `file-system-count`
   - `oci_file_storage_mount_target` → service: `filesystem`, limit: `mount-target-count`
   - `oci_database_autonomous_database` → service: `database`, limits: `adw-ecpu-count` + `adw-total-storage-tb` (for default LH/DW workload; no `--availability-domain`!)
   - `oci_objectstorage_bucket` → service: `objectstorage`, limit: `bucket-count` (paas_rag only; high default limit ~1000, excluded from checks but tracked to suppress untracked warnings)
   - `oci_identity_customer_secret_key` → per-user IAM limit of 2 (paas_rag only; checked via `oci iam customer-secret-key list --user-id $USER_OCID` — count must be < 2)
   - `oci_containerengine_cluster` → service: `container-engine`, limit: `cluster-count` (all packs; high default limit ~20, low-priority — check only if other resources pass)
   - `oci_core_vcn` / `oci_core_virtual_network` → service: `vcn`, limit: `vcn-count` (all packs; high default limit ~50, low-priority — check only if other resources pass)
   - Any new `oci_*` resource type not in this map → flag as "untracked — verify if quota-gated"
4. Cross-reference with `vars.tf` `local.starter_pack_configs` to get per-category/size GPU shape, node count, database compute count, and storage size.
5. Build and print the manifest table for the requested category/size.
6. If any new untracked resource types are found, warn the user but proceed with known checks.

### Expected manifest output (example for vss/poc)

```
Resource Manifest for vss/poc:
  GPU:  VM.GPU.A10.2 x 2 nodes
  FSS:  1 file system, 1 mount target
  ADB:  none
```

## Phase 2: Gather Parameters

Unchanged from current skill:

1. Resolve category/size from arguments (or ask the user).
2. Get OCI CLI profile (discover from `~/.oci/config` if not known).
3. Get tenancy OCID.
4. List all subscribed regions.

For `paas_rag`, report "No GPU required" but continue to check ADB quotas (do not exit early like current skill does).

## Phase 3: Scan Regions

For each subscribed region, check every resource in the manifest:

### GPU checks (if pack needs GPU)

Same as current skill:
- `oci compute compute-capacity-report create` — hardware availability per AD
- `oci limits resource-availability get --service-name compute --limit-name <gpu-limit>` — quota check

Only check the AD where GPU hardware is AVAILABLE.

### FSS checks (if pack needs FSS — currently only vss)

```bash
oci limits resource-availability get \
  --service-name filesystem \
  --limit-name mount-target-count \
  --compartment-id $TENANCY_OCID \
  --availability-domain "$AD" \
  --region $region \
  --query 'data.{available:available,used:used,quota:"effective-quota-value"}'
```

Also check `file-system-count` with the same pattern. FSS is AD-scoped.

Need: 1 mount target, 1 file system. Fail if `available < 1` for either.

### ADB checks (if pack needs ADB — paas_rag, enterprise_rag)

**VERIFIED:** ADB limits are regional — do NOT pass `--availability-domain` (API errors: "Parameter 'availabilityDomain' should be null for this limit's scope type"). Also, there is no generic `autonomous-database-count` limit. ADB quotas are split by workload type. Default workload is `LH` (Lakehouse) which falls under ADW.

| db_workload_type | ECPU Limit | Storage Limit |
|---|---|---|
| `LH` (default), `DW` | `adw-ecpu-count` | `adw-total-storage-tb` |
| `OLTP` | `atp-ecpu-count` | `atp-total-storage-tb` |
| `AJD` | `ajd-ecpu-count` | `ajd-total-storage-tb` |

```bash
# ECPU availability (no --availability-domain!)
oci limits resource-availability get \
  --service-name database \
  --limit-name adw-ecpu-count \
  --compartment-id $TENANCY_OCID \
  --region $region \
  --query 'data.{available:available,used:used,quota:"effective-quota-value"}'

# Storage availability
oci limits resource-availability get \
  --service-name database \
  --limit-name adw-total-storage-tb \
  --compartment-id $TENANCY_OCID \
  --region $region \
  --query 'data.{available:available,used:used,quota:"effective-quota-value"}'
```

Need: `database_compute_count` ECPUs AND `database_storage_size_in_tbs` TB from `starter_pack_configs`. Fail if `available` is less than required for either.

### Customer secret key check (if pack needs Object Storage S3 compat — currently only paas_rag)

```bash
KEY_COUNT=$(oci iam customer-secret-key list \
  --user-id $USER_OCID \
  --all \
  --query 'data | length(@)' \
  --raw-output 2>/dev/null)
KEY_COUNT=${KEY_COUNT:-0}
```

Hard limit of 2 per user. This is a user-level check (not region-scoped), so it only runs once before the region scan, not per-region. The API returns `{"data": []}` when empty — the `--query` returns the count. If count >= 2 and the user hasn't pre-provided `aws_access_key_id`, the deploy will fail. Fail if `count >= 2`.

### Error handling

- If an `oci limits` call fails (permissions, service not available), mark that resource as `UNKNOWN` with the error message. Do not mark the region as READY.
- If a region has no ADs listed, skip it.

## Phase 4: Report

### Format

```
=== Capacity Report: vss poc ===
GPU Shape: VM.GPU.A10.2 (2 nodes)
Additional Resources: FSS (1 file system, 1 mount target)

Region              GPU HW          GPU Quota  FSS MT   Status
--------------------------------------------------------------
us-sanjose-1        AVAILABLE       4/8        0/2      x NOT READY
  +-- mount-target-count: 0 available (2 used, quota 2) [QUOTA - request increase]
ap-tokyo-1          AVAILABLE       8/8        2/2      v READY
ap-osaka-1          OUT_OF_CAPACITY 0/8        1/2      x NOT READY
  +-- GPU VM.GPU.A10.2: no hardware capacity in AD-1 [CAPACITY - try different region]
uk-london-1         NOT_SUPPORTED   --         --       x NOT READY
  +-- GPU VM.GPU.A10.2: shape not available in region [CAPACITY - try different region]

Recommended: ap-tokyo-1
```

### Rules

- A region is **READY** only if ALL resources in the manifest pass (hardware available AND quota sufficient).
- Failure lines appear indented below the region row showing:
  - Resource name (OCI limit name)
  - Available count, used count, quota
  - Whether it's a hardware issue (no capacity) or quota issue (need to request increase)
- GPU failures distinguish hardware capacity (`OUT_OF_CAPACITY` / `NOT_SUPPORTED`) from quota exhaustion.
- Non-GPU failures show the OCI limit name + available/used/quota numbers.
- The "Recommended" line picks the READY region with the most quota headroom across all resources. If no region is READY, say "No regions ready" and the failure breakdown shows what to fix.
- For `paas_rag` (no GPU), GPU columns are omitted entirely. Only ADB columns shown.
- Columns are dynamic based on the manifest — only show columns for resources the pack needs.

## Edge Cases

- `paas_rag`: No GPU. Skip GPU checks entirely. Only check ADB.
- Raw shape mode (`/checking-capacity BM.GPU4.8`): Skip Phase 1 audit. GPU only. Same as current behavior.
- Region with no ADs: Skip region.
- OCI API permission error: Mark resource as UNKNOWN, don't mark region READY.
- Phase 1 finds untracked `oci_*` resource types: Warn user, proceed with known checks.
- `enterprise_rag_aiq`: GPU only, no ADB (despite what BUG-011 originally stated).

## Known Gaps

- **`oci_identity_customer_secret_key`** (paas_rag): Hard limit of 2 per user. Checked via `oci iam customer-secret-key list` (see Phase 3). This is a user-level check, not region-scoped, so it runs once before the region scan.
- **Object Storage buckets** (`oci_objectstorage_bucket`, paas_rag): Default limit ~1000. Extremely unlikely to be exhausted. Tracked in the mapping to suppress untracked warnings but not actively checked.
- **VCN/OKE cluster quotas**: High default limits (50 VCNs, 20+ clusters). Low-priority checks — included in the mapping but only checked if higher-priority resources (GPU, FSS, ADB) pass. These have never caused a deployment failure.

## Files Changed

- `.claude/skills/checking-capacity/SKILL.md` — rewrite with new 4-phase structure
- `BUGS.md` — correct BUG-011 entry: remove `enterprise_rag_aiq` from the ADB row in the resource table, fix the resolution text

## Files NOT Changed

- `ai-accelerator-tf/capacity_check.tf` — Terraform preconditions remain GPU-only (out of scope)
- `.claude/skills/releasing/SKILL.md` — continues to call `/checking-capacity`, benefits automatically
