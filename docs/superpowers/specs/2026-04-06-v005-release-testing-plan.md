# v0.0.5 Release Testing Plan

## Overview

Test all 5 starter packs from the v0.0.5 GitHub release using the two-stack (infra + app) model. Three parallel tracks minimize total wall-clock time by sharing GPU infrastructure within each track and running independent GPU shapes concurrently.

## Prerequisites

- v0.0.5 release published at: https://github.com/oci-ai-incubations/ai-accelerator-starter-packs/releases/tag/v0.0.5
- Working OCI CLI profile with access to target compartment(s)
- Agent-browser available for ORM UI interactions

## Step 0: Download Release Zips

```bash
mkdir -p release_test_matrix
gh release download v0.0.5 --dir release_test_matrix/
```

Expected files:
- `v0.0.5_enterprise_rag.zip`
- `v0.0.5_enterprise_rag_aiq.zip`
- `v0.0.5_paas_rag.zip`
- `v0.0.5_cuopt.zip`
- `v0.0.5_vss.zip`

## Step 1: Capacity Check + Region Selection

Before launching tracks, check GPU capacity for each shape needed:

| Shape | Packs | Min Instances |
|-------|-------|---------------|
| BM.GPU4.8 | enterprise_rag, enterprise_rag_aiq | 2 |
| VM.GPU.A10.2 | vss, cuopt | 2 (vss needs 2, cuopt needs 1) |

Run `/checking-capacity` for each shape. Select regions with both hardware availability AND quota. Tracks using different shapes can run in different regions if needed.

paas_rag needs no GPU — any region works.

## Parallel Execution

```
Time -->
Track 1 (BM.GPU4.8):  [==== erag infra ====][= erag app/test =][destroy app][reapply infra][= erag_aiq app/test =][destroy all ======]
Track 2 (VM.A10.2):   [== vss infra ==][= vss app/test =][destroy app][reapply infra][= cuopt app/test =][destroy all]
Track 3 (CPU):         [= paas infra =][= paas app/test =][destroy all]
                       ^ all three start simultaneously
```

Each track runs as a separate agent invocation. Use unique agent-browser session names to avoid conflicts.

---

## Track 1: BM.GPU4.8 — Enterprise RAG then Enterprise RAG AIQ

**GPU shape:** BM.GPU4.8 x2 workers (both packs use identical GPU infra)
**Packs tested:** enterprise_rag/small, enterprise_rag_aiq/small

### 1a. Deploy enterprise_rag infra

- Use `/testing-pack enterprise_rag small`
- Upload `v0.0.5_enterprise_rag.zip` to ORM
- Create infra stack with `deploy_application = false`
- Apply and wait for OKE cluster + 2x BM.GPU4.8 nodes + ADB to provision
- Extract outputs: `cluster_id`, `autonomous_db_subnet_id`, `node_subnet_id`, `vcn_id`, `node_pool_id`

### 1b. Deploy enterprise_rag app + test

- Create app stack with `v0.0.5_enterprise_rag.zip`
- Set `existing_cluster_id` from 1a outputs
- Set `existing_autonomous_db_subnet_id` from 1a outputs
- Set `deploy_application = true`
- Apply and run smoke tests via `/enterprise-rag-test-coverage`

### 1c. Destroy enterprise_rag app stack

- ORM Destroy on the app stack only
- Verify blueprint workloads cleaned up (undeploy script runs)
- GPU nodes and cluster remain running

### 1d. Re-apply infra with enterprise_rag_aiq

- **Update the existing infra stack** — upload `v0.0.5_enterprise_rag_aiq.zip`
- Set `deploy_application = false`
- Re-apply: infra adjusts to enterprise_rag_aiq config (ADB removed since enterprise_rag_aiq has 0 database storage; GPU nodes unchanged since same BM.GPU4.8 x2)
- Extract updated outputs

### 1e. Deploy enterprise_rag_aiq app + test

- Create new app stack with `v0.0.5_enterprise_rag_aiq.zip`
- Set `existing_cluster_id` from updated infra outputs
- Set `deploy_application = true`
- Apply and run smoke tests via `/enterprise-rag-test-coverage`
- Note: enterprise_rag_aiq requires `tavily_api_key` — ask user for the real API key

### 1f. Cleanup

- Destroy enterprise_rag_aiq app stack
- Destroy infra stack
- Clean up customer secret keys (quota of 2 per user)
- Verify ADB terminated (if not cleaned by destroy)

**Time saved by sharing:** Avoids a 2nd BM.GPU4.8 infra deploy (~45 min) and a 2nd BM destroy cycle (up to 6 hours for bare-metal GPU host recycling).

---

## Track 2: VM.GPU.A10.2 — VSS then cuOpt

**GPU shape:** VM.GPU.A10.2 (vss needs 2, cuopt needs 1)
**Packs tested:** vss/poc, cuopt/poc

### 2a. Deploy vss infra

- Use `/testing-pack vss poc`
- Upload `v0.0.5_vss.zip` to ORM
- Create infra stack with `deploy_application = false`
- Apply and wait for OKE cluster + 2x VM.GPU.A10.2 + 1x CPU worker
- Extract outputs: `cluster_id`, `node_subnet_id`, `vcn_id`, `node_pool_id`

### 2b. Deploy vss app + test

- Create app stack with `v0.0.5_vss.zip`
- Set `existing_cluster_id` from 2a outputs
- Set `deploy_application = true`
- Apply and run smoke tests via `/vss-test-coverage`

### 2c. Destroy vss app stack

- ORM Destroy on the app stack only
- GPU nodes and cluster remain running

### 2d. Re-apply infra with cuopt

- **Update the existing infra stack** — upload `v0.0.5_cuopt.zip`
- Set `deploy_application = false`
- Re-apply: instance pool scales down from 2 to 1 GPU worker (extra VM.GPU.A10.2 terminated), CPU worker pool adjusts per cuopt config
- Extract updated outputs

### 2e. Deploy cuopt app + test

- Create new app stack with `v0.0.5_cuopt.zip`
- Set `existing_cluster_id` from updated infra outputs
- Set `deploy_application = true`
- Apply and run smoke tests via `/cuopt-test-coverage`

### 2f. Cleanup

- Destroy cuopt app stack
- Destroy infra stack

**Time saved by sharing:** Avoids full VCN + OKE cluster + control plane re-creation for cuopt. Only the GPU node pool adjusts (2→1 instance).

---

## Track 3: CPU-only — PaaS RAG

**GPU shape:** None (CPU only + ADB)
**Pack tested:** paas_rag/small

### 3a. Deploy paas_rag infra

- Use `/testing-pack paas_rag small`
- Upload `v0.0.5_paas_rag.zip` to ORM
- Create infra stack with `deploy_application = false`
- Apply and wait for OKE cluster + 1x CPU worker + ADB (2TB)

### 3b. Deploy paas_rag app + test

- Create app stack with `v0.0.5_paas_rag.zip`
- Set `existing_cluster_id` from 3a outputs
- Set `existing_autonomous_db_subnet_id` from 3a outputs
- Set `deploy_application = true`
- Apply and run smoke tests via `/paas-rag-test-coverage`

### 3c. Cleanup

- Destroy app stack, then destroy infra stack
- Clean up customer secret keys and ADB if needed

---

## Per-Pack Test Coverage Skills

| Pack | Test Skill | Key Tests |
|------|-----------|-----------|
| enterprise_rag | `/enterprise-rag-test-coverage` | API endpoints, UI, doc ingestion, RAG chat |
| enterprise_rag_aiq | `/enterprise-rag-test-coverage` | API endpoints, UI, doc ingestion, RAG chat, AIQ agents |
| cuopt | `/cuopt-test-coverage` | API endpoints, UI, route optimization |
| vss | `/vss-test-coverage` | API endpoints, UI, video processing |
| paas_rag | `/paas-rag-test-coverage` | API endpoints, UI, doc management, RAG chat |

## Variables to Collect Before Starting

| Variable | Scope | Source |
|----------|-------|--------|
| OCI CLI profile | All tracks | Ask user |
| Compartment name/OCID | All tracks | Ask user |
| Region(s) | Per track | `/checking-capacity` results |
| `tavily_api_key` | Track 1 (enterprise_rag_aiq only) | Ask user — real API key |
| Admin credentials | All tracks | Auto-generated per `/testing-pack` |

## Post-Testing

After all tracks complete successfully:
1. Update the v0.0.5 GitHub release from "pending" to "latest"
2. Run `/release-push v0.0.5` for Slack announcement, PR merge, and tagging
