# VSS Infrastructure Tests

7 tests executed via `kubectl` and OCI CLI. Execute in order.

**MANDATORY:** Execute ALL tests. If a test fails, record the failure and continue.

---

## Execution Order

| # | ID | Test | Tool | P | Type |
|---|---|---|---|---|---|
| 1 | VI-1 | Frontend pod Running | kubectl | P0 | smoke |
| 2 | VI-2 | Download service pod Running | kubectl | P0 | smoke |
| 3 | VI-3 | Blueprint pods Running | kubectl | P0 | smoke |
| 4 | VI-4 | FSS PVC bound | kubectl | P0 | smoke |
| 5 | VI-5 | ConfigMap data correct | kubectl | P1 | regression |
| 6 | VI-6 | Ingress has TLS cert | kubectl | P1 | smoke |
| 7 | VI-7 | DB Secret exists | kubectl | P0 | smoke |

---

## Test Details

### VI-1: Frontend Pod Running (P0 smoke)

- **Command:** `kubectl get pods -l app=vss-oracle-ux -o wide`
- **Verify:** At least one pod with STATUS = `Running`, READY = `1/1`
- **Failure hint:** If pod is `CrashLoopBackOff`, check logs with `kubectl logs -l app=vss-oracle-ux --tail=50`. Common cause: DATABASE_URL secret missing or PostgreSQL not ready.

### VI-2: Download Service Pod Running (P0 smoke)

- **Command:** `kubectl get pods -l app=vss-download-service -o wide`
- **Verify:** At least one pod with STATUS = `Running`, READY = `1/1`
- **Failure hint:** If not found, check if `app-vss-oracle-ux.tf` deployed the download-service deployment.

### VI-3: Blueprint Pods Running (P0 smoke)

- **Command:** `kubectl get pods | grep recipe-vss-deployment`
- **Verify:** All 6 blueprint pods are Running:
  - `recipe-vss-deployment-*-vss-engine-*` — VSS engine (GPU, 10-15 min startup)
  - `recipe-vss-deployment-*-elasticsearch-*` — Elasticsearch (2-5 min startup)
  - `recipe-vss-deployment-*-neo4j-*` — Neo4j (2-3 min startup)
  - `recipe-vss-deployment-*-embedding-*` — Embedding NIM (GPU, 15-20 min startup)
  - `recipe-vss-deployment-*-reranking-*` — Reranking NIM (GPU, 10-15 min startup)
  - `recipe-vss-deployment-*-nim-llm-*` — LLM NIM / cosmos-reason1 (GPU, 15-30 min startup)
- **Note:** NIM pods take 15-30 minutes to start after apply. If pods are in `Init` or `ContainerCreating`, wait and recheck every 2 minutes. If pods are in `CrashLoopBackOff` or `Error`, check logs and report — do not wait indefinitely.

### VI-4: FSS PVC Bound (P0 smoke)

- **Command:** `kubectl get pvc | grep vss-fss`
- **Verify:** `vss-fss-pvc` shows STATUS = `Bound`
- **Failure hint:** If `Pending`, the FSS mount target may not be ready. Check `kubectl describe pvc vss-fss-pvc` for events.

### VI-5: ConfigMap Data Correct (P1 regression)

- **Command:** `kubectl get cm vss-oracle-ux-config -o json`
- **Verify:** ConfigMap `.data` contains all three required keys with non-empty values:
  - `VSS_API_BASE_URL` — URL to VSS backend (e.g., `http://recipe-vss-deployment-...:8000`)
  - `DOWNLOAD_SERVICE_URL` — URL to download service (e.g., `http://vss-download-service:8080`)
  - `FILE_STORAGE_PATH` — FSS mount path (e.g., `/mnt/fss/cache`)
- **Failure hint:** If keys are missing, check `app-vss-oracle-ux.tf` configmap resource definition.

### VI-6: Ingress Has TLS Cert (P1 smoke)

- **Command:** `kubectl get ingress vss-oracle-ux-ingress -o jsonpath='{.spec.tls[0].secretName}'`
- **Verify:** Output is `vss-oracle-ux-tls`
- **Additional check:** `kubectl get secret vss-oracle-ux-tls` exists (cert-manager should have created it)
- **Failure hint:** If secret doesn't exist, cert-manager may not have issued the certificate yet. Check `kubectl describe certificate` for status.

### VI-7: DB Secret Exists (P0 smoke)

- **Command:** `kubectl get secret vss-db-url -o jsonpath='{.data.DATABASE_URL}'`
- **Verify:** Output is non-empty (base64-encoded PostgreSQL connection string)
- **Additional check:** Decode and verify it's a valid postgres:// URL:
  ```bash
  kubectl get secret vss-db-url -o jsonpath='{.data.DATABASE_URL}' | base64 -d
  ```
- **Failure hint:** If missing, the PostgreSQL provisioning in Terraform may have failed. Check `app-vss-oracle-ux.tf` secret resource.
