---
name: checking-capacity
description: Checks GPU hardware capacity and tenancy quota across OCI regions for a given shape or starter pack category/size. Reports which regions have both available hardware AND sufficient quota. Use when the user says "check capacity", "is there GPU availability", "which regions have capacity", or before deploying GPU workloads.
user-invocable: true
allowed-tools: Bash, Read, AskUserQuestion
argument-hint: [shape-or-category] [size]
---

# Checking Capacity

Check GPU hardware availability and tenancy quota across OCI regions. Reports which regions can actually deploy the requested shape — both hardware AND quota must pass.

## Arguments

- `$0` — GPU shape (e.g., `BM.GPU4.8`) OR pack category (`cuopt`, `vss`, `enterprise_rag`, `enterprise_rag_aiq`)
- `$1` — Size (if category given): `poc`, `small`, `medium`

If not provided, ask the user.

## Phase 1: Resolve shape

Map category/size to GPU shape:

The authoritative category/size → shape mapping is in `ai-accelerator-tf/vars.tf` under `local.starter_pack_configs`. Look up `worker_node_shape` for the given category/size. Common mappings (verify against `vars.tf` if in doubt):

| Category | Size | Shape | GPUs/Node | Nodes |
|---|---|---|---|---|
| `cuopt` | `poc` | `VM.GPU.A10.2` | 2 | 1 |
| `cuopt` | `small` | `BM.GPU4.8` | 8 | 1 |
| `cuopt` | `medium` | `BM.GPU.A100-v2.8` | 8 | 1 |
| `vss` | `poc` | `VM.GPU.A10.2` | 2 | 2 |
| `vss` | `small` | `BM.GPU4.8` | 8 | 1 |
| `vss` | `medium` | `BM.GPU.L40S-NC.4` | 4 | 2 |
| `enterprise_rag` | `small` | `BM.GPU4.8` | 8 | 2 |
| `enterprise_rag_aiq` | `small` | `BM.GPU4.8` | 8 | 2 |
| `paas_rag` | any | *(no GPU)* | 0 | 0 |

If `paas_rag`, report "No GPU required" and exit.

If a raw shape is given (e.g., `BM.GPU4.8`), use it directly.

## Phase 2: Gather parameters

Ask for OCI CLI profile if not already known:
```bash
grep '^\[' ~/.oci/config | tr -d '[]'
```

## Phase 3: Check hardware capacity across regions

List all subscribed regions, then check capacity in each:

```bash
export OCI_CLI_PROFILE=<profile>
TENANCY_OCID=$(grep tenancy ~/.oci/config | head -1 | cut -d= -f2 | tr -d ' ')

# Get subscribed regions
REGIONS=$(oci iam region-subscription list \
  --tenancy-id $TENANCY_OCID \
  --query 'data[].{"region-name":"region-name"}' \
  --output json | python3 -c "import json,sys; [print(r['region-name']) for r in json.load(sys.stdin)]")

# Check capacity in each region
for region in $REGIONS; do
  AD=$(oci iam availability-domain list \
    --compartment-id $TENANCY_OCID \
    --region $region \
    --query 'data[0].name' --raw-output 2>/dev/null)
  
  if [ -z "$AD" ]; then continue; fi
  
  STATUS=$(oci compute compute-capacity-report create \
    --compartment-id $TENANCY_OCID \
    --region $region \
    --availability-domain "$AD" \
    --shape-availabilities "[{\"instanceShape\": \"$SHAPE\", \"faultDomain\": \"FAULT-DOMAIN-1\"}]" \
    --query 'data."shape-availabilities"[0]."availability-status"' \
    --raw-output 2>/dev/null)
  
  echo "$region ($AD): $STATUS"
done
```

## Phase 4: Check quota in regions with capacity

For regions where capacity is AVAILABLE, check tenancy quota:

```bash
# Map shape to limit name
# BM.GPU4.8 -> gpu4-count
# BM.GPU.A100-v2.8 -> gpu-a100-v2-8-count  
# VM.GPU.A10.2 -> gpu-a10-count
# BM.GPU.L40S-NC.4 -> gpu-l40s-nc-count

# If unsure of limit name, discover it:
oci limits definition list \
  --service-name compute \
  --compartment-id $TENANCY_OCID \
  --region $region --all \
  --query "data[?contains(name, 'gpu')].{name:name,description:description}" \
  --output table

# Get quota value
oci limits value list \
  --service-name compute \
  --compartment-id $TENANCY_OCID \
  --region $region --all \
  --scope-type AD \
  --availability-domain "$AD" \
  --query "data[?name=='$LIMIT_NAME'].value | [0]" \
  --raw-output

# Get current usage via capacity report
oci compute compute-capacity-report create \
  --compartment-id $TENANCY_OCID \
  --region $region \
  --availability-domain "$AD" \
  --shape-availabilities "[{\"instanceShape\": \"$SHAPE\"}]" \
  --query 'data."shape-availabilities"[0]' \
  --output json
```

**Best approach — get effective availability in one call:**

```bash
oci limits resource-availability get \
  --service-name compute \
  --limit-name $LIMIT_NAME \
  --compartment-id $TENANCY_OCID \
  --availability-domain "$AD" \
  --region $region \
  --query 'data.{available:available,used:used,quota:"effective-quota-value"}' 2>/dev/null
```

This returns `available` (quota minus used), `used`, and `quota` in one call. Use `available` directly.

**Quota check:** GPUs needed = nodes_needed * gpus_per_node. If `available` < needed, flag it.

## Phase 5: Report

```
=== GPU Capacity Report: <shape> ===
Pack: <category> <size> (if applicable)
Nodes needed: N (N GPUs each)

Region                  Hardware         Quota    Status
───────────────────────────────────────────────────────
us-sanjose-1 (AD-1)    AVAILABLE        64       ✓ READY
ap-tokyo-1 (AD-1)      AVAILABLE        32       ✓ READY
ap-sydney-1 (AD-1)     OUT_OF_CAPACITY  64       ✗ No hardware
ap-osaka-1 (AD-1)      NOT_SUPPORTED    —        ✗ Shape not available
us-ashburn-1 (AD-1)    NOT_SUPPORTED    —        ✗ Shape not available
...

Recommended: us-sanjose-1 (highest quota headroom)
```

## Shape-to-Limit Name Mapping

| Shape | OCI Limit Name |
|---|---|
| `VM.GPU.A10.2` | `gpu-a10-count` |
| `BM.GPU4.8` | `gpu4-count` |
| `BM.GPU.A100-v2.8` | `gpu-a100-v2-8-count` |
| `BM.GPU.L40S-NC.4` | `gpu-l40s-nc-count` |

If the limit name returns empty results, discover it:
```bash
oci limits definition list --service-name compute --compartment-id $TENANCY_OCID --region $region --all \
  --query "data[?contains(name, '<keyword>')].name" --output table
```
Replace `<keyword>` with `gpu4`, `a10`, `a100`, or `l40s`.
