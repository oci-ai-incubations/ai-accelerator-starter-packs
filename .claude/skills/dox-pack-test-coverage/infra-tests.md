# Document Extractor Infrastructure Tests

7 tests executed via `kubectl` and OCI CLI. Execute in order.

**MANDATORY:** Execute ALL tests. If a test fails, record the failure and continue.

**Note:** Document Extractor uses a Corrino blueprint deployment group with 3 services: llamastack (CPU), dox-backend (CPU), and dox-frontend (CPU). There are NO GPU workers on the OKE cluster. Vision-language inference runs on the OCI GenAI Dedicated AI Cluster (DAC), which is a managed OCI service.

---

## Execution Order

| # | ID | Test | Tool | P | Type |
|---|---|---|---|---|---|
| 1 | CI-1 | Frontend pod Running | kubectl | P0 | smoke |
| 2 | CI-2 | Backend pod Running | kubectl | P0 | smoke |
| 3 | CI-3 | LlamaStack pod Running | kubectl | P0 | smoke |
| 4 | CI-4 | All blueprint pods Running | kubectl | P0 | smoke |
| 5 | CI-5 | Ingress routes configured | kubectl | P1 | regression |
| 6 | CI-6 | Corrino deployment active | kubectl | P1 | smoke |
| 7 | CI-7 | GenAI DAC endpoint reachable | curl / OCI CLI | P0 | smoke |

---

## Test Details

### CI-1: Frontend Pod Running (P0 smoke)

- **Command:** `kubectl get pods | grep dox-frontend`
- **Verify:** At least one pod matching `recipe-*-dox-frontend-*` with STATUS = `Running`, READY = `1/1`
- **Note:** The frontend pod runs the Next.js UI. It is a CPU-only pod (4 OCPU, 32GB RAM) on a shared node pool.
- **Startup time:** 1-2 minutes.
- **Failure hint:** If not found, check if the Corrino blueprint deployment completed. Run `kubectl get pods` to see all pods and `kubectl get jobs` for deployment job status.

### CI-2: Backend Pod Running (P0 smoke)

- **Command:** `kubectl get pods | grep dox-backend`
- **Verify:** At least one pod matching `recipe-*-dox-backend-*` with STATUS = `Running`, READY = `1/1`
- **Note:** The backend pod runs the FastAPI extraction + chat service. It is a CPU-only pod (4 OCPU, 32GB RAM). It connects to Oracle 26ai (ORACLE_DSN), Qwen3-VL DAC (QWEN_URL), and LlamaStack (LLAMASTACK_URL).
- **Startup time:** 1-3 minutes. Depends on database connectivity.
- **Failure hint:** If `CrashLoopBackOff`, check logs: `kubectl logs $(kubectl get pods -o name | grep dox-backend | head -1) --tail=50`. Common causes: ORACLE_DSN connection string incorrect, QWEN_URL not set, LLAMASTACK_URL unreachable.

### CI-3: LlamaStack Pod Running (P0 smoke)

- **Command:** `kubectl get pods | grep llamastack`
- **Verify:** At least one pod matching `recipe-*-llamastack-*` with STATUS = `Running`, READY = `1/1`
- **Note:** LlamaStack is a CPU-only pod (8 OCPU, 64GB RAM). It connects to Oracle 26ai database and OCI Object Storage. It has a 500Gi PVC (`ls-sqlite`) for SQLite store.
- **Startup time:** 2-5 minutes. Depends on database connectivity.
- **Failure hint:** If `CrashLoopBackOff`, check logs: `kubectl logs $(kubectl get pods -o name | grep llamastack | head -1) --tail=50`. Common causes: database connection string incorrect, OCI Object Storage credentials invalid.

### CI-4: All Blueprint Pods Running (P0 smoke)

- **Command:** `kubectl get pods | grep recipe-`
- **Verify:** All pods in the dox_pack deployment group are Running:
  - `recipe-*-llamastack-*` — LlamaStack backend (CPU, 2-5 min startup)
  - `recipe-*-dox-backend-*` — Contract extraction backend (CPU, 1-3 min startup)
  - `recipe-*-dox-frontend-*` — Contract frontend (CPU, 1-2 min startup)
- **Total expected:** 3 pods
- **Failure hint:** If any pod is in `Init` or `ContainerCreating`, wait and recheck every 2 minutes. If pods are in `CrashLoopBackOff` or `Error`, check logs and report.

### CI-5: Ingress Routes Configured (P1 regression)

- **Command:** `kubectl get ingress -o json | python3 -c "import json,sys; data=json.load(sys.stdin); [print(r['metadata']['name'], [p.get('path','') for p in i.get('http',{}).get('paths',[])]) for i in [rule for r in data['items'] for rule in r.get('spec',{}).get('rules',[])] for p in [i]]" 2>/dev/null || kubectl get ingress -o wide`
- **Verify:** Ingress exists with routes for:
  - `dox-frontend.<fqdn>` — frontend service (port 80)
  - `llamastack.<fqdn>` — llamastack service (port 8321)
- **Simpler check:** `kubectl get ingress -o yaml | grep -E 'host:|path:|serviceName:|servicePort:'`
- **Failure hint:** If routes are missing, the Corrino blueprint deployment may not have completed. Check `kubectl get jobs` for the blueprint deployment job status.

### CI-6: Corrino Deployment Active (P1 smoke)

- **Command:** Check deployment status via Corrino API:
  ```bash
  CORRINO_API=$(kubectl get ingress -o jsonpath='{.items[?(@.metadata.name=="corrino-cp-ingress")].spec.rules[0].host}' 2>/dev/null)
  if [ -n "$CORRINO_API" ]; then
    curl -sk "https://${CORRINO_API}/api/v1/deployments" | python3 -c "
  import json,sys
  data = json.load(sys.stdin)
  for d in data:
    if 'contract' in d.get('deployment_name','').lower():
      print('Name:', d['deployment_name'])
      print('Status:', d.get('deployment_status','unknown'))
  "
  fi
  ```
- **Verify:**
  - A deployment with "contract" in the name exists
  - Deployment status is `active` or `monitoring`
- **Failure hint:** If deployment shows `deploying` or `error`, the blueprint may still be initializing. Wait for pods to stabilize first.

### CI-7: GenAI DAC Endpoint Reachable (P0 smoke)

- **Command:** Verify the Dedicated AI Cluster endpoint is accessible from the cluster:
  ```bash
  # Get the DAC endpoint URL from Terraform outputs or pod env vars
  DAC_URL=$(kubectl exec $(kubectl get pods -o name | grep dox-backend | head -1) -- printenv QWEN_URL 2>/dev/null)
  echo "DAC endpoint: ${DAC_URL}"

  # Test reachability from within the cluster (exec into backend pod)
  if [ -n "$DAC_URL" ]; then
    kubectl exec $(kubectl get pods -o name | grep dox-backend | head -1) -- \
      curl -sk --max-time 10 -o /dev/null -w '%{http_code}' "${DAC_URL}/v1/models" 2>/dev/null
  fi
  ```
- **Verify:**
  - `QWEN_URL` environment variable is set and non-empty in the dox-backend pod
  - The DAC endpoint responds (HTTP 200 or 401/403 — any response means the endpoint is reachable)
  - If the endpoint returns 000 or connection timeout, the DAC may not be provisioned yet
- **Failure hint:** If `QWEN_URL` is empty, check the blueprint configuration in `blueprint_files.tf`. If the endpoint is unreachable, verify the DAC was provisioned in the OCI console under AI Services > Dedicated AI Clusters. DAC provisioning can take 30-60 minutes.
