# Enterprise RAG Infrastructure Tests

10 tests executed via `kubectl` and OCI CLI. Execute in order.

**MANDATORY:** Execute ALL tests. If a test fails, record the failure and continue.

**Note:** Enterprise RAG is deployed via Helm (NOT Corrino blueprint). All pods run in the `rag` namespace. Use `-n rag` on all kubectl commands.

---

## Execution Order

| # | ID | Test | Tool | P | Type |
|---|---|---|---|---|---|
| 1 | EI-1 | Frontend pod Running | kubectl | P0 | smoke |
| 2 | EI-2 | RAG Server pod Running | kubectl | P0 | smoke |
| 3 | EI-3 | Ingestor Server pod Running | kubectl | P0 | smoke |
| 4 | EI-4 | NIM LLM pod Running | kubectl | P0 | smoke |
| 5 | EI-5 | Embedding NIM pod Running | kubectl | P0 | smoke |
| 6 | EI-6 | Reranking NIM pod Running | kubectl | P1 | smoke |
| 7 | EI-7 | Milvus pod Running | kubectl | P0 | smoke |
| 8 | EI-8 | All rag namespace pods Running | kubectl | P0 | smoke |
| 9 | EI-9 | Ingress configured | kubectl | P1 | regression |
| 10 | EI-10 | GPU allocation verified | kubectl | P1 | smoke |

---

## Test Details

### EI-1: Frontend Pod Running (P0 smoke)

- **Command:** `kubectl get pods -n rag -l app.kubernetes.io/name=rag-frontend -o wide`
- **Alternative:** `kubectl get pods -n rag | grep frontend`
- **Verify:** At least one pod with STATUS = `Running`, READY = `1/1`
- **Image:** `iad.ocir.io/iduyx1qnmway/enterprise-rag-frontend:v0.0.2`
- **Failure hint:** If not found, check `helm list -n rag` for Helm release status. The frontend is part of the RAG Helm chart.

### EI-2: RAG Server Pod Running (P0 smoke)

- **Command:** `kubectl get pods -n rag | grep rag-server`
- **Verify:** At least one pod with STATUS = `Running`
- **Image:** `nvcr.io/nvidia/blueprint/rag-server:2.3.0`
- **Port:** 8081
- **Failure hint:** If `CrashLoopBackOff`, check logs: `kubectl logs -n rag -l app.kubernetes.io/name=rag-server --tail=50`. Common cause: Milvus or NIM services not ready yet.

### EI-3: Ingestor Server Pod Running (P0 smoke)

- **Command:** `kubectl get pods -n rag | grep ingestor`
- **Verify:** At least one pod with STATUS = `Running`
- **Image:** `nvcr.io/nvidia/blueprint/ingestor-server:2.3.0`
- **Port:** 8082
- **Note:** Ingestor server has a 50Gi PVC for document storage. If pod is `Pending`, check PVC status.
- **Failure hint:** Check PVC: `kubectl get pvc -n rag | grep ingestor`

### EI-4: NIM LLM Pod Running (P0 smoke)

- **Command:** `kubectl get pods -n rag | grep nim-llm`
- **Verify:** At least one pod with STATUS = `Running` (may show as StatefulSet pod: `rag-nim-llm-0`)
- **Image:** `nvcr.io/nim/nvidia/llama-3.3-nemotron-super-49b-v1.5:1.14.0`
- **Port:** 8000
- **Startup time:** 15-30 minutes for model loading
- **Note:** This is the critical GPU pod. If it's not Running, all chat/generate endpoints will fail.
- **Failure hint:** If `Pending`, GPU nodes may not be ready. Check node pool: `kubectl get nodes -o wide`. If `CrashLoopBackOff`, check logs: `kubectl logs -n rag rag-nim-llm-0 --tail=100`. Common issues: NGC credentials, insufficient GPU memory.

### EI-5: Embedding NIM Pod Running (P0 smoke)

- **Command:** `kubectl get pods -n rag | grep embedding`
- **Verify:** At least one pod with STATUS = `Running`
- **Image:** NemoRetriever embedding model (Llama 3.2 NV-embedqa 1B)
- **Port:** 8000
- **Startup time:** 10-15 minutes
- **Failure hint:** If not running, document ingestion will fail (can't generate embeddings).

### EI-6: Reranking NIM Pod Running (P1 smoke)

- **Command:** `kubectl get pods -n rag | grep ranking`
- **Verify:** At least one pod with STATUS = `Running`
- **Image:** NemoRetriever ranking model (Llama 3.2 NV-rerankqa 1B)
- **Port:** 8000
- **Note:** Reranking is optional (can be disabled in settings). But if deployed, it should be Running.
- **Failure hint:** Check logs: `kubectl logs -n rag $(kubectl get pods -n rag -o name | grep ranking | head -1) --tail=50`

### EI-7: Milvus Pod Running (P0 smoke)

- **Command:** `kubectl get pods -n rag | grep milvus`
- **Verify:** Milvus pods are Running (may be multiple components: standalone, etcd, minio)
- **Port:** 19530
- **Note:** Milvus is the vector database. If it's not Running, collection creation and RAG retrieval will fail.
- **Failure hint:** Check all milvus-related pods: `kubectl get pods -n rag | grep -i milvus`

### EI-8: All RAG Namespace Pods Running (P0 smoke)

- **Command:** `kubectl get pods -n rag -o wide`
- **Verify:** All pods in the `rag` namespace are Running or Completed. Expected pods include:
  - `rag-frontend-*` — Frontend
  - `rag-server-*` — RAG Server
  - `ingestor-server-*` — Ingestor
  - `rag-nim-llm-0` — LLM NIM (StatefulSet)
  - `*-embedding-*` — Embedding NIM
  - `*-ranking-*` — Reranking NIM
  - `*-milvus-*` — Milvus vector DB
  - `rag-minio-*` — MinIO object storage
  - `rag-redis-*` — Redis cache
  - `*-nv-ingest-*` — NV-Ingest document processor
- **Total expected:** 10+ pods (varies based on Helm chart configuration)
- **Note:** Some pods may be in `Completed` state (init jobs). Only Running pods matter for ongoing services. NIM pods take 15-30 minutes to start.
- **Failure hint:** If any critical pod is not Running after 30 minutes, report with pod name, status, and logs snippet.

### EI-9: Ingress Configured (P1 regression)

- **Command:** `kubectl get ingress -n rag -o wide`
- **Verify:**
  - An ingress resource exists for the RAG frontend
  - Host matches the expected pattern (e.g., `frontend-erag.<ip>.nip.io` or custom domain)
  - TLS is configured (cert-manager annotation or TLS section present)
- **Additional check:**
  ```bash
  kubectl get ingress -n rag -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.rules[0].host}{"\n"}{end}'
  ```
- **Failure hint:** If no ingress, check the `enterprise-rag-frontend-ingress` resource in `ingress.tf`. The ingress is created by Terraform, not by the Helm chart.

### EI-10: GPU Allocation Verified (P1 smoke)

- **Command:**
  ```bash
  kubectl describe pod -n rag rag-nim-llm-0 | grep -A5 'nvidia.com/gpu'
  ```
- **Verify:**
  - The NIM LLM pod has GPU resources allocated
  - `nvidia.com/gpu` shows the expected count (typically 1-2 for Nemotron 49B)
- **Additional check:** Verify GPU nodes exist:
  ```bash
  kubectl get nodes -o json | python3 -c "
  import json,sys
  data = json.load(sys.stdin)
  for n in data['items']:
    gpu = n.get('status',{}).get('allocatable',{}).get('nvidia.com/gpu','0')
    if int(gpu) > 0:
      print(n['metadata']['name'], '- GPUs:', gpu)
  "
  ```
- **Expected:** 2 worker nodes with 8 GPUs each (BM.GPU4.8 = 16 total GPUs)
- **Failure hint:** If no GPU nodes, the OKE node pool may still be provisioning. Check `kubectl get nodes` and OCI console for node pool status.
