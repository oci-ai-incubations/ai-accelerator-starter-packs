# Agent Observability — Infrastructure Tests

12 tests executed via `kubectl` and the OCI CLI. Execute in order.

**MANDATORY:** Execute ALL tests. If a test fails, record the failure and continue.

**Setup:** export `KUBECONFIG` (OKE public endpoint) and `OCI_CLI_PROFILE`. Blueprint pods land in the `default` namespace; ClickHouse lives in the `clickhouse` namespace. The langfuse-web pods are named `recipe-agent-observability-<hex>-*` (the primary ingress recipe uses `DEPLOY_NAME`); worker/llamastack are `recipe-langfuse-worker-*` / `recipe-llamastack-*`.

---

## Execution Order

| # | ID | Test | Tool | P | Type |
|---|---|---|---|---|---|
| 1 | AOI-1 | langfuse-web pods Running | kubectl | P0 | smoke |
| 2 | AOI-2 | langfuse-worker pod Running | kubectl | P0 | smoke |
| 3 | AOI-3 | llamastack pod Running (correct image) | kubectl | P0 | smoke |
| 4 | AOI-4 | ClickHouse operator Running | kubectl | P0 | smoke |
| 5 | AOI-5 | ClickHouse CHI replicas + Keeper Running | kubectl | P0 | smoke |
| 6 | AOI-6 | ClickHouse replication works | kubectl/exec | P1 | regression |
| 7 | AOI-7 | OCI Database with PostgreSQL ACTIVE | OCI CLI | P0 | smoke |
| 8 | AOI-8 | OCI Cache (Redis) ACTIVE | OCI CLI | P0 | smoke |
| 9 | AOI-9 | Object Storage bucket exists | OCI CLI | P1 | smoke |
| 10 | AOI-10 | GenAI endpoint ACTIVE (create mode) | OCI CLI | P0 | smoke |
| 11 | AOI-11 | langfuse-secrets secret complete | kubectl | P1 | regression |
| 12 | AOI-12 | Ingress routes configured (TLS) | kubectl | P1 | regression |

---

## Test Details

### AOI-1: langfuse-web Pods Running (P0 smoke)
- **Command:** `kubectl get pods -n default | grep recipe-agent-observability`
- **Verify:** `langfuse_web_replicas` pods (small=2, medium=3), STATUS `Running`, READY `1/1`.
- **Note:** Image `docker.io/langfuse/langfuse:3`, port 3000. One restart during startup (waiting on ClickHouse migrations) is normal.
- **Failure hint:** `CrashLoopBackOff` → `kubectl logs <pod> -n default --tail=60`. Common: DB/ClickHouse/Redis unreachable, or `langfuse-secrets` missing keys (see AOI-11).

### AOI-2: langfuse-worker Pod Running (P0 smoke)
- **Command:** `kubectl get pods -n default | grep recipe-langfuse-worker`
- **Verify:** 1 pod, `Running`, `1/1`. Image `langfuse/langfuse-worker:3`, port 3030, no ingress.

### AOI-3: llamastack Pod Running with Correct Image (P0 smoke)
- **Command:** `kubectl get pods -n default | grep recipe-llamastack` and
  `kubectl get pod <llamastack-pod> -n default -o jsonpath='{.spec.containers[0].image}'`
- **Verify:** 1 pod `Running` `1/1`; image is `ord.ocir.io/iduyx1qnmway/corrino-devops-repository/llama-stack-oci:pr-d74b10d` (the v0.0.3 image does NOT serve the DAC model).
- **Note:** Reads its config via `RUN_CONFIG_PATH=/config/config.yaml` (inline configmap `llamastack-config`); entrypoint runs `ogx stack run`.
- **Failure hint:** Config-parse errors → check the configmap is block-style YAML; `ogx ... unrecognized arguments` → wrong image/entrypoint.

### AOI-4: ClickHouse Operator Running (P0 smoke)
- **Command:** `kubectl get pods -n clickhouse | grep clickhouse-operator`
- **Verify:** `clickhouse-operator-altinity-clickhouse-operator-*` `2/2 Running`. **It must run in the `clickhouse` namespace** (it watches only its own namespace by default).
- **Failure hint:** `ImageInspectError`/`ImagePullBackOff` → cri-o short-name or a dead tag; images must be fully-qualified (`operator.image.registry=docker.io`, crdHook `docker.io/alpine/kubectl:1.35.4`).

### AOI-5: ClickHouse CHI Replicas + Keeper Running (P0 smoke)
- **Command:** `kubectl get pods,chi,chk -n clickhouse`
- **Verify:**
  - CHI `langfuse` STATUS `Completed`, `chi-langfuse-default-0-0-0` and `chi-langfuse-default-0-1-0` `1/1 Running` (2 replicas, small).
  - CHK `langfuse`, `chk-langfuse-keeper-0-{0,1,2}-0` `1/1 Running` (3 keepers).
  - Services `clickhouse-langfuse` (8123/9000) and `keeper-langfuse` (2181) present.
- **Failure hint:** Keeper `CrashLoopBackOff` with `Unknown setting 'use_xid_64'` → keeper image must be ≥ 25.8.

### AOI-6: ClickHouse Replication Works (P1 regression)
- **Commands:** exec into `chi-langfuse-default-0-0-0` (`-c clickhouse`, user `langfuse`):
  `CREATE TABLE default.repl_test ON CLUSTER '{cluster}' (id UInt64) ENGINE=ReplicatedMergeTree ORDER BY id`, `INSERT INTO default.repl_test VALUES (42)`; then read `SELECT id FROM default.repl_test` from `chi-langfuse-default-0-1-0`.
- **Verify:** the row `42` is readable on replica `0-1` (ON CLUSTER DDL hit both hosts). Drop the table after.
- **Note:** Requires the CHI `Completed` (remote_servers propagated to both replicas) and Keeper quorum.

### AOI-7: OCI Database with PostgreSQL ACTIVE (P0 smoke)
- **Command:** `oci search resource structured-search --query-text "query PostgresqlDbSystem resources where compartmentId='<compartment>'"`
- **Verify:** a `langfuse-pg-*` db system `lifecycle-state = ACTIVE`. Shape `PostgreSQL.VM.Standard.E5.Flex` (E4 has 0 quota), `instance_count` ≥ 2.
- **Failure hint:** `400-LimitExceeded(dbsystem-count)` at deploy → shape must be E5 (uses `dbsystem-e5-count`).

### AOI-8: OCI Cache (Redis) ACTIVE (P0 smoke)
- **Command:** `oci search resource structured-search --query-text "query RedisCluster resources where compartmentId='<compartment>'"`
- **Verify:** `langfuse-redis-*` `ACTIVE`. TLS-only (Langfuse connects via `rediss://`).

### AOI-9: Object Storage Bucket Exists (P1 smoke)
- **Command:** `oci os object list -bn agent-obs-<hex>-bucket -ns <namespace> --query 'length(data)'`
- **Verify:** bucket exists (versioning Enabled). After traffic, `events/` (and `media/`) prefixes populate.
- **Note:** Bucket name prefix is `agent-obs-<deploy_id>-bucket`.

### AOI-10: GenAI Endpoint ACTIVE (P0 smoke)
- **Command (create mode):** `oci generative-ai endpoint get --endpoint-id <agent_obs_endpoint_ocid output>`
- **Verify:** `lifecycle-state = ACTIVE`; `model-id` is the imported model; `dedicated-ai-cluster-id` is the DAC (unit_shape `H100_X2` for the default model). In `existing` mode, verify the referenced endpoint OCID is ACTIVE.
- **Failure hint:** imported-model create `400-InvalidParameter "cannot have special characters"` → model display name must be sanitized (no `.`).

### AOI-11: langfuse-secrets Secret Complete (P1 regression)
- **Command:** `kubectl get secret langfuse-secrets -n default -o jsonpath='{.data}' | tr ',' '\n'`
- **Verify:** keys present: `DATABASE_URL`, `REDIS_CONNECTION_STRING`, `CLICKHOUSE_URL`, `CLICKHOUSE_MIGRATION_URL`, `CLICKHOUSE_USER`, `CLICKHOUSE_PASSWORD`, `S3_ACCESS_KEY_ID`, `S3_SECRET_ACCESS_KEY`, `NEXTAUTH_SECRET`, `SALT`, `ENCRYPTION_KEY`, `LANGFUSE_INIT_USER_PASSWORD`, `LANGFUSE_INIT_PROJECT_SECRET_KEY`.
- **Note:** All generated at deploy time; the blueprint references these via `recipe_environment_secrets` (no plaintext secrets in the blueprint).

### AOI-12: Ingress Routes Configured / TLS (P1 regression)
- **Command:** `kubectl get ingress -A`
- **Verify:** an ingress `recipe-agent-observability-*` with host `langfuse.<fqdn>` (langfuse-web) and one with host `llamastack.<fqdn>` (llamastack), both with `cert-manager.io/cluster-issuer: letsencrypt-prod`.
- **Note:** The langfuse-web ingress canonical-name must start with `agent-observability-` (so the blueprint readiness check matches it).
