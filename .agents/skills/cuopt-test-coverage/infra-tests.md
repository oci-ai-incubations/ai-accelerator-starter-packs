# cuOpt Infrastructure Tests

7 tests executed via `kubectl` and OCI CLI. Execute in order.

**MANDATORY:** Execute ALL tests. If a test fails, record the failure and continue.

**Note:** cuOpt uses a Corrino blueprint deployment group with 3 services: cuopt (GPU), llamastack (CPU), demo frontend (CPU). The blueprint creates ingress routes for all three.

---

## Execution Order

| # | ID | Test | Tool | P | Type |
|---|---|---|---|---|---|
| 1 | CI-1 | Frontend pod Running | kubectl | P0 | smoke |
| 2 | CI-2 | cuOpt solver pod Running | kubectl | P0 | smoke |
| 3 | CI-3 | LlamaStack pod Running | kubectl | P0 | smoke |
| 4 | CI-4 | All blueprint pods Running | kubectl | P0 | smoke |
| 5 | CI-5 | Ingress routes configured | kubectl | P1 | regression |
| 6 | CI-6 | GPU allocation verified | kubectl | P1 | smoke |
| 7 | CI-7 | Corrino deployment active | kubectl | P1 | smoke |

---

## Test Details

### CI-1: Frontend Pod Running (P0 smoke)

- **Command:** `kubectl get pods | grep demo`
- **Verify:** At least one pod matching `recipe-cuopt-*-demo-*` with STATUS = `Running`, READY = `1/1`
- **Note:** The frontend pod is the `demo` service in the blueprint deployment group. It's a CPU-only pod (1 OCPU, 8GB RAM).
- **Failure hint:** If not found, check that at least one frontend skin is enabled in terraform.tfvars (e.g. `cuopt_delivery_optimizer_enabled = true`). Check `frontend_skin_urls` in the Terraform outputs to see which skins were deployed.

### CI-2: cuOpt Solver Pod Running (P0 smoke)

- **Command:** `kubectl get pods | grep cuopt`
- **Verify:** At least one pod matching `recipe-cuopt-*-cuopt-*` with STATUS = `Running`
- **Note:** This is the GPU pod running NVIDIA cuOpt. It requires GPU nodes (A10/GPU4.8/A100 depending on size).
- **Startup time:** 5-15 minutes for GPU model loading.
- **Failure hint:** If `Pending`, check GPU node pool is provisioned. If `CrashLoopBackOff`, check logs: `kubectl logs -l app=cuopt --tail=50` — common cause is insufficient GPU memory or NGC credential issues.

### CI-3: LlamaStack Pod Running (P0 smoke)

- **Command:** `kubectl get pods | grep llamastack`
- **Verify:** At least one pod matching `recipe-cuopt-*-llamastack-*` with STATUS = `Running`, READY = `1/1`
- **Note:** LlamaStack is a CPU-only pod (1 OCPU, 8GB RAM). It provides the OpenAI-compatible LLM endpoint.
- **Startup time:** 2-5 minutes.
- **Failure hint:** If not found, check that at least one frontend skin is enabled in terraform.tfvars. LlamaStack is only deployed when at least one frontend skin is enabled.

### CI-4: All Blueprint Pods Running (P0 smoke)

- **Command:** `kubectl get pods | grep recipe-cuopt`
- **Verify:** All pods in the cuopt deployment group are Running:
  - `recipe-cuopt-*-cuopt-*` — cuOpt solver (GPU, 5-15 min startup)
  - `recipe-cuopt-*-llamastack-*` — LlamaStack LLM (CPU, 2-5 min startup)
  - `recipe-cuopt-*-demo-*` — Frontend (CPU, 1-2 min startup)
- **Total expected:** cuopt solver + llamastack + one `demo` pod per enabled frontend skin. With one skin enabled, expect 3 pods; with multiple skins, expect 2 + N pods.
- **Note:** Consult `frontend_skin_urls` in the Terraform outputs to confirm which skins were deployed.
- **Failure hint:** If any pod is in `Init` or `ContainerCreating`, wait and recheck every 2 minutes. NIM/GPU pods take longer. If pods are in `CrashLoopBackOff` or `Error`, check logs and report.

### CI-5: Ingress Routes Configured (P1 regression)

- **Command:** `kubectl get ingress -o json | python3 -c "import json,sys; data=json.load(sys.stdin); [print(r['metadata']['name'], [p.get('path','') for p in i.get('http',{}).get('paths',[])]) for i in [rule for r in data['items'] for rule in r.get('spec',{}).get('rules',[])] for p in [i]]" 2>/dev/null || kubectl get ingress -o wide`
- **Verify:** Ingress exists with routes for:
  - `/` → demo frontend service (port 3000)
  - `/cuopt` or `/cuopt/*` → cuopt service (port 5000)
  - `/v1` or `/v1/*` → llamastack service (port 8321)
- **Simpler check:** `kubectl get ingress -o yaml | grep -E 'path:|serviceName:|servicePort:'`
- **Failure hint:** If routes are missing, the Corrino blueprint deployment may not have completed. Check `kubectl get jobs` for the blueprint deployment job status.

### CI-6: GPU Allocation Verified (P1 smoke)

- **Command:** `kubectl describe pod $(kubectl get pods -o name | grep 'recipe-cuopt.*cuopt' | head -1) | grep -A5 'nvidia.com/gpu'`
- **Verify:**
  - The cuopt solver pod has GPU resources allocated
  - `nvidia.com/gpu` shows the expected count:
    - PoC: 2 GPUs (VM.GPU.A10.2)
    - Small: 8 GPUs (BM.GPU4.8)
    - Medium: 8 GPUs (BM.GPU.A100-v2.8)
- **Alternative check:** `kubectl top pod $(kubectl get pods -o name | grep 'recipe-cuopt.*cuopt' | head -1)` (if metrics-server is running)
- **Failure hint:** If no GPU allocated, the node pool may not have GPU nodes ready, or the pod may be scheduled on a non-GPU node.

### CI-7: Corrino Deployment Active (P1 smoke)

- **Command:** Check deployment status via Corrino API:
  ```bash
  CORRINO_API=$(kubectl get ingress -o jsonpath='{.items[?(@.metadata.name=="corrino-cp-ingress")].spec.rules[0].host}' 2>/dev/null)
  if [ -n "$CORRINO_API" ]; then
    curl -sk "https://${CORRINO_API}/api/v1/deployments" | python3 -c "
  import json,sys
  data = json.load(sys.stdin)
  for d in data:
    if 'cuopt' in d.get('deployment_name','').lower():
      print('Name:', d['deployment_name'])
      print('Status:', d.get('deployment_status','unknown'))
  "
  fi
  ```
- **Verify:**
  - A deployment with "cuopt" in the name exists
  - Deployment status is `active` or `monitoring`
- **Failure hint:** If deployment shows `deploying` or `error`, the blueprint may still be initializing. Wait for pods to stabilize first.
