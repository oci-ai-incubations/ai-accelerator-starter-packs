# Enterprise RAG Helm v2.5.0 Upgrade Notes

## Branch: `feature/erag-helm-v2.5.0-upgrade`

## Summary

Upgrading the NVIDIA RAG Blueprint helm chart from v2.3.0 to v2.5.0 for the `enterprise_rag` and `enterprise_rag_aiq` starter packs. This is a significant architectural change — v2.5.0 deploys NIMs via the **NIM Operator** (CRDs: NIMCache/NIMService) instead of helm subcharts.

## Current Status

**Infrastructure: WORKING** — All 13 pods Running 1/1 on OKE cluster in ap-osaka-1.

**Ingestion: BLOCKED** — nv-ingest client library version mismatch prevents document processing.

## What Changed in v2.5.0

### 1. NIM Operator (NEW)
- NIMs are now deployed via `apps.nvidia.com/v1alpha1` CRDs (NIMCache, NIMService)
- Requires `k8s-nim-operator` helm chart installed (pinned to v3.1.0)
- NIMCache downloads and caches model weights to PVCs
- NIMService creates inference deployments after cache is ready
- Added `helm_release.nim_operator` in `helm.tf`

### 2. nemoretriever → nemotron Rebranding
- All NIM images renamed (e.g., `llama-3.2-nv-embedqa-1b-v2` → `llama-nemotron-embed-1b-v2`)
- K8s service names renamed (e.g., `nemoretriever-embedding-ms` → `nemotron-embedding-ms`)
- Model names renamed (e.g., `nvidia/llama-3.2-nv-embedqa-1b-v2` → `nvidia/llama-nemotron-embed-1b-v2`)
- `RERANKER_CONFIDENCE_THRESHOLD` → `RERANKER_SCORE_THRESHOLD`

### 3. Helm Values Key Gotchas
The v2.5.0 chart **kept the old top-level YAML keys** but changed the images inside:

| YAML Key (UNCHANGED) | Image (CHANGED) |
|---|---|
| `nvidia-nim-llama-32-nv-embedqa-1b-v2` | `llama-nemotron-embed-1b-v2:1.13.0` |
| `nvidia-nim-llama-32-nv-rerankqa-1b-v2` | `llama-nemotron-rerank-1b-v2:1.10.0` |

NIM configs must be under the `nimOperator:` key with NIMCache/NIMService structure (storage.pvc, expose.service, tolerations).

### 4. NV-Ingest Sub-NIM Key Changes
nv-ingest subchart keys changed from dash-style to underscore-style:

| v2.3.0 Key | v2.5.0 Key |
|---|---|
| `nemoretriever-graphic-elements-v1` | `graphic_elements` |
| `nemoretriever-page-elements-v2` | `page_elements` |
| `nemoretriever-table-structure-v1` | `table_structure` |
| `paddleocr-nim` + `nemoretriever-ocr` | `nemoretriever_ocr_v1` |
| `nim-vlm-text-extraction` | `nemotron_parse` |

### 5. NV-Ingest Service Names
NIM Operator creates K8s services named after the NIMService CR names:
- `nemoretriever-page-elements-v3` (NOT `nemotron-page-elements-v3`)
- `nemoretriever-graphic-elements-v1` (NOT `nemotron-graphic-elements-v1`)
- `nemoretriever-table-structure-v1` (NOT `nemotron-table-structure-v1`)
- `nemoretriever-ocr-v1` (NOT `nv-ingest-ocr`)

The nv-ingest YOLOX/OCR env vars must match these actual service names.

## LLM Model: nemotron-3-super-120b-a12b

### Configuration for A100-40GB
- **Tensor Parallelism: 8** (all 8 GPUs on one node)
- **Engine: vllm, Precision: fp8**
- **NIM_MAX_MODEL_LEN: 32768** (128K context OOMs on A100-40GB)
- **PVC: 500Gi** (model is ~240GB, 300Gi insufficient with temp files)

### What Didn't Work
| Config | Result |
|---|---|
| TP2, 128K context | CUDA OOM — 37GB/GPU, only 408MB free |
| TP4, 128K context | CUDA OOM — 29GB/GPU, KV cache profiling needs 1GB more |
| TP8, 128K context | CUDA OOM — same KV cache issue |
| TP8, 32K context | **WORKS** — 29GB/GPU with room for KV cache |

## Issues Discovered and Resolved

### 1. Subchart Key Mismatch (RESOLVED)
**Symptom:** NIM pods never created.
**Cause:** Renamed helm values keys didn't match chart's actual subchart keys.
**Fix:** Reverted to chart's actual key names, moved NIMs under `nimOperator:` section.

### 2. NIMCache Tolerations Not Passed (RESOLVED via kubectl patch)
**Symptom:** Cache pods stuck Pending — `untolerated taint nvidia.com/gpu`.
**Cause:** v2.5.0 chart templates don't map `tolerations` from values to NIMCache CR spec.
**Fix:** Manual `kubectl patch nimcache <name> -p '{"spec":{"tolerations":[...]}}'` after deploy.
**TODO:** Need Terraform post-deploy provisioner to automate this.

### 3. workload=nim-llm Taint (RESOLVED)
**Symptom:** Cache/inference pods couldn't schedule.
**Cause:** Custom taint from old subchart approach. NIM Operator doesn't set tolerations for it.
**Fix:** Removed `terraform_data.label_nim_llm_node` resources and the taint.

### 4. NGC CDN Timeouts from Osaka (RESOLVED via auto-retry)
**Symptom:** LLM model cache downloads fail mid-transfer.
**Cause:** Unreliable connection from `ap-osaka-1` to `xfiles.ngc.nvidia.com`.
**Fix:** NIM Operator auto-retries; previously downloaded shards persist on PVC across retries.

### 5. Cross-Node Volume Attach (RESOLVED)
**Symptom:** Embedding/reranking inference pods stuck in ContainerCreating.
**Cause:** PVCs created on cache node, inference pods on different node. OCI BV `ReadWriteOnce`.
**Fix:** Deleted stale PVCs, recreated NIMCache CRs. Fresh PVCs bound to correct node.

### 6. LLM NIMCache Engine Mismatch (RESOLVED)
**Symptom:** `no profiles are selected for caching`.
**Cause:** Chart defaults to `tensorrt_llm` engine but `nemotron-3-super-120b-a12b` needs `vllm`.
**Fix:** Patched NIMCache with `model.engine: vllm, precision: fp8, tensorParallelism: "8"`.

### 7. PVC Size Too Small (RESOLVED)
**Symptom:** `No space left on device` during model download.
**Cause:** 120Gi (then 300Gi) insufficient for 240GB model + temp files.
**Fix:** Increased to 500Gi.

### 8. nv-ingest MILVUS_ENDPOINT (RESOLVED)
**Symptom:** nv-ingest pipeline setup hangs.
**Cause:** `MILVUS_ENDPOINT=http://milvus:19530` set but no Milvus service (enterprise_rag uses Oracle 26AI).
**Fix:** Set to `http://localhost:19530` (dummy, fails fast).

### 9. OTEL Collector Not Deployed (RESOLVED)
**Symptom:** gRPC goaway errors in nv-ingest logs.
**Cause:** OTEL exporters configured but collector not deployed.
**Fix:** Set `OTEL_TRACES_EXPORTER=none`, `OTEL_METRICS_EXPORTER=none`, endpoint to `http://localhost:4317`.

## BLOCKER: nv-ingest Client Library Mismatch

### Symptom
Document upload creates a task, nv-ingest API returns 200 on submit and 202 on poll, but job stays SUBMITTED forever. Pipeline worker never picks up the job.

### Root Cause
The internal OCI images (`nvidia-rag-ingestion-oci:v0.0.5`, `nvidia-rag-retrieval-oci:v0.0.5`) from the `nvidia-rag-oci` fork pin:
- `nv-ingest-api==25.9.0`
- `nv-ingest-client==25.9.0`

But nv-ingest server is 26.1.2. The v2 API dispatch mechanism changed — the 25.9.0 client submits jobs via HTTP to the nv-ingest API, which stores the job state as SUBMITTED, but the internal dispatch to the pipeline's Redis queue changed between versions. The job payload never reaches the pipeline worker.

### Fix Required (Phase 1: nvidia-rag-oci Fork)
1. Bump `nv-ingest-api` and `nv-ingest-client` from `25.9.0` to `26.1.2` in `pyproject.toml`
2. Test page numbering (now 1-based instead of 0-based in 26.1.2)
3. Test V2 API compatibility
4. Verify Oracle 26AI vector store integration still works
5. Build new images: `nvidia-rag-ingestion-oci:v0.0.6` and `nvidia-rag-retrieval-oci:v0.0.6`
6. Update helm values with new image tags

## Files Changed

### ai-accelerator-tf/helm.tf
- Chart URL: `v2.3.0` → `v2.5.0`
- Added `helm_release.nim_operator` (k8s-nim-operator v3.1.0)
- Removed `terraform_data.label_nim_llm_node` and `label_nim_llm_node_via_operator`
- Removed nim-llm image overrides from `set` block (now in nimOperator values)

### ai-accelerator-tf/helm-values/enterprise-rag-values.yaml
- Internal OCI images: `ord.ocir.io/...:v0.0.3` → `iad.ocir.io/...:v0.0.5`
- All `nemoretriever-*` → `nemotron-*` service URLs and model names
- `RERANKER_CONFIDENCE_THRESHOLD` → `RERANKER_SCORE_THRESHOLD`
- Added `APP_NVINGEST_EXTRACTTABLESMETHOD: "yolox"`
- NIM section restructured under `nimOperator:` with NIMCache/NIMService config
- NV-ingest sub-NIM keys: dash → underscore style
- YOLOX/OCR endpoints: match actual NIM Operator service names (`nemoretriever-*`)
- LLM: `nemotron-3-super-120b-a12b`, TP8, 8 GPUs, 500Gi PVC, 32K context

### ai-accelerator-tf/helm-values/enterprise-rag-aiq-values.yaml
- Same renames as enterprise-rag-values.yaml
- rag-server/ingestor-server: `2.3.0` → `2.5.0`
- nv-ingest: `25.9.0` → `26.1.2`

## Test Environment
- **Region:** ap-osaka-1
- **Cluster:** AI-Accel-OKE-z9t9Oq
- **GPU Nodes:** 2x BM.GPU.A100-v2.8 (8x A100-SXM4-40GB each)
- **Stack:** ocid1.ormstack.oc1.ap-osaka-1.amaaaaaam3augwaau2wn5hg446lnk5vssi2ksvckiknolehio667syosx44q

## Post-Deploy Manual Steps Required
Until the chart templates are fixed upstream, these kubectl patches are needed after each deploy:

```bash
# 1. Patch NIMCache CRs with GPU tolerations
for cache in nim-llm-cache nemotron-embedding-ms-cache nemotron-ranking-ms-cache \
  nemoretriever-graphic-elements-v1 nemoretriever-ocr-v1 \
  nemoretriever-page-elements-v3 nemoretriever-table-structure-v1; do
  kubectl patch nimcache "$cache" -n rag --type=merge \
    -p '{"spec":{"tolerations":[{"key":"nvidia.com/gpu","operator":"Exists","effect":"NoSchedule"}]}}'
done

# 2. Patch LLM NIMCache with correct engine
kubectl patch nimcache nim-llm-cache -n rag --type=merge \
  -p '{"spec":{"source":{"ngc":{"model":{"engine":"vllm","precision":"fp8","tensorParallelism":"8"}}}}}'

# 3. Delete cache pods to trigger recreation with tolerations
kubectl delete pods -n rag -l app.kubernetes.io/managed-by=nim-operator

# 4. Patch NIMService CRs with tolerations
for svc in nim-llm nemotron-embedding-ms nemotron-ranking-ms \
  nemoretriever-graphic-elements-v1 nemoretriever-ocr-v1 \
  nemoretriever-page-elements-v3 nemoretriever-table-structure-v1; do
  kubectl patch nimservice "$svc" -n rag --type=merge \
    -p '{"spec":{"tolerations":[{"key":"nvidia.com/gpu","operator":"Exists","effect":"NoSchedule"}]}}'
done

# 5. Remove stale workload taint if present
for NODE in $(kubectl get nodes -l 'nvidia.com/gpu.present=true' -o jsonpath='{.items[*].metadata.name}'); do
  kubectl taint node "$NODE" workload=nim-llm:NoSchedule- 2>/dev/null || true
done
```
