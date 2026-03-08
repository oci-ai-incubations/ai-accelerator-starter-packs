# PaaS RAG Infrastructure Tests

5 tests executed via `kubectl` and OCI CLI. Execute in order.

**MANDATORY:** Execute ALL tests. If a test fails, record the failure and continue.

**Note:** PaaS RAG uses a Corrino blueprint deployment group with 2 services: llamastack (CPU) and frontend (CPU). There are NO GPU workers. The backend connects to Oracle 26ai Autonomous Database and OCI Object Storage.

---

## Execution Order

| # | ID | Test | Tool | P | Type |
|---|---|---|---|---|---|
| 1 | PI-1 | Frontend pod Running | kubectl | P0 | smoke |
| 2 | PI-2 | LlamaStack pod Running | kubectl | P0 | smoke |
| 3 | PI-3 | All blueprint pods Running | kubectl | P0 | smoke |
| 4 | PI-4 | Ingress routes configured | kubectl | P1 | regression |
| 5 | PI-5 | Corrino deployment active | kubectl | P1 | smoke |

---

## Test Details

### PI-1: Frontend Pod Running (P0 smoke)

- **Command:** `kubectl get pods | grep frontend`
- **Verify:** At least one pod matching `recipe-paas-*-frontend-*` with STATUS = `Running`, READY = `1/1`
- **Note:** The frontend pod runs the OracleNet React SPA. It's a CPU-only pod (4 OCPU, 32GB RAM) on a shared node pool.
- **Startup time:** 1-2 minutes.
- **Failure hint:** If not found, check if the Corrino blueprint deployment completed. Run `kubectl get pods` to see all pods and `kubectl get jobs` for deployment job status.

### PI-2: LlamaStack Pod Running (P0 smoke)

- **Command:** `kubectl get pods | grep llamastack`
- **Verify:** At least one pod matching `recipe-paas-*-llamastack-*` with STATUS = `Running`, READY = `1/1`
- **Note:** LlamaStack is a CPU-only pod (8 OCPU, 64GB RAM). It connects to Oracle 26ai database and OCI Object Storage. It has a 500Gi PVC (`ls-sqlite`) for SQLite store.
- **Startup time:** 2-5 minutes. Depends on database connectivity.
- **Failure hint:** If `CrashLoopBackOff`, check logs: `kubectl logs $(kubectl get pods -o name | grep llamastack | head -1) --tail=50`. Common causes: database connection string incorrect, wallet mount missing, OCI Object Storage credentials invalid.

### PI-3: All Blueprint Pods Running (P0 smoke)

- **Command:** `kubectl get pods | grep recipe-paas`
- **Verify:** All pods in the paas_rag deployment group are Running:
  - `recipe-paas-*-llamastack-*` — LlamaStack backend (CPU, 2-5 min startup)
  - `recipe-paas-*-frontend-*` — OracleNet frontend (CPU, 1-2 min startup)
- **Total expected:** 2 pods
- **Failure hint:** If any pod is in `Init` or `ContainerCreating`, wait and recheck every 2 minutes. If pods are in `CrashLoopBackOff` or `Error`, check logs and report.

### PI-4: Ingress Routes Configured (P1 regression)

- **Command:** `kubectl get ingress -o json | python3 -c "import json,sys; data=json.load(sys.stdin); [print(r['metadata']['name'], [p.get('path','') for p in i.get('http',{}).get('paths',[])]) for i in [rule for r in data['items'] for rule in r.get('spec',{}).get('rules',[])] for p in [i]]" 2>/dev/null || kubectl get ingress -o wide`
- **Verify:** Ingress exists with routes for:
  - `/` → frontend service (port 3000)
  - `/v1` or `/v1/*` → llamastack service (port 8321) — includes sub-routes: models, health, responses, vector_stores, files
- **Simpler check:** `kubectl get ingress -o yaml | grep -E 'path:|serviceName:|servicePort:'`
- **Failure hint:** If routes are missing, the Corrino blueprint deployment may not have completed. Check `kubectl get jobs` for the blueprint deployment job status.

### PI-5: Corrino Deployment Active (P1 smoke)

- **Command:** Check deployment status via Corrino API:
  ```bash
  CORRINO_API=$(kubectl get ingress -o jsonpath='{.items[?(@.metadata.name=="corrino-cp-ingress")].spec.rules[0].host}' 2>/dev/null)
  if [ -n "$CORRINO_API" ]; then
    curl -sk "https://${CORRINO_API}/api/v1/deployments" | python3 -c "
  import json,sys
  data = json.load(sys.stdin)
  for d in data:
    if 'paas' in d.get('deployment_name','').lower():
      print('Name:', d['deployment_name'])
      print('Status:', d.get('deployment_status','unknown'))
  "
  fi
  ```
- **Verify:**
  - A deployment with "paas" in the name exists
  - Deployment status is `active` or `monitoring`
- **Failure hint:** If deployment shows `deploying` or `error`, the blueprint may still be initializing. Wait for pods to stabilize first.
