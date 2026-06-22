# agent_observability Pack — Backend API Contract

Companion document to [`BACKEND_API_CONTRACT.md`](../BACKEND_API_CONTRACT.md). That file is the multi-pack
reference organized around skin-access *mechanisms* (ingress paths vs env
vars). This file is the agent_observability-pack-specific deep dive organized
around *backend services and their API surface*.

Scope: `starter_pack_category = "agent_observability"`. For other packs, see
[`CUOPT.md`](CUOPT.md), [`VSS.md`](VSS.md),
[`ENTERPRISE_RAG.md`](ENTERPRISE_RAG.md),
[`ENTERPRISE_RAG_AIQ.md`](ENTERPRISE_RAG_AIQ.md),
[`PAAS_RAG.md`](PAAS_RAG.md),
[`WAREHOUSE_PICK_PATH.md`](WAREHOUSE_PICK_PATH.md),
[`DOX_PACK.md`](DOX_PACK.md).

---

## 1. Deployment Group Composition

agent_observability deploys a **Corrino blueprint deployment group** to OKE
plus a set of **managed OCI backing services provisioned in Terraform**.
The deployment group itself is CPU-only; there are no GPU workers on the OKE
cluster (the optional agentic model is hosted on an OCI GenAI Dedicated AI
Cluster, not on OKE).

Source of truth: `ai-accelerator-tf/agent_observability_blueprint.tf` (blueprint)
and `ai-accelerator-tf/langfuse_*.tf` (backing services).

| Service           | Container image                          | Container port | Role                                                                 |
|-------------------|------------------------------------------|----------------|---------------------------------------------------------------------|
| `langfuse-web`    | `docker.io/langfuse/langfuse:3`          | 3000           | Langfuse UI + public ingestion/API. SSO (OIDC) optional. Admin bootstrapped at deploy. |
| `langfuse-worker` | `docker.io/langfuse/langfuse-worker:3`   | 3030           | Async event processing (no ingress).                                |
| `llamastack`      | `iad.ocir.io/iduyx1qnmway/corrino-devops-repository/llama-stack-oci:v0.0.3` | 8321 | OpenAI-compatible gateway to the OCI GenAI agentic model endpoint.   |

### Managed backing services (Terraform, outside the blueprint)

| Service                         | Resource                              | Purpose                                  |
|---------------------------------|---------------------------------------|------------------------------------------|
| OCI Object Storage (S3-compat)  | `oci_objectstorage_bucket` + customer secret key | Langfuse event/media blob storage (`events/`, `media/` prefixes). |
| OCI Database with PostgreSQL    | `oci_psql_db_system`                  | Transactional store (HA, 2 instances).   |
| OCI Cache (Redis, TLS)          | `oci_redis_redis_cluster`             | Event queue (`rediss://`).               |
| ClickHouse (Altinity operator)  | helm + `ClickHouseInstallation` CR    | OLAP store; sharding/replication per size. |
| OCI Generative AI endpoint      | `oci_generative_ai_*` (create mode) or existing OCID | Agentic model (default `Qwen/Qwen3.6-35B-A3B`). |

All secrets (DB/Redis/ClickHouse credentials, S3 keys, `NEXTAUTH_SECRET`,
`SALT`, `ENCRYPTION_KEY`, admin password) are generated at deploy time in
Terraform and injected into the blueprint via the `langfuse-secrets`
Kubernetes secret (`recipe_environment_secrets`) — never as plaintext in the
blueprint JSON.

---

## 2. Public API Surface

`langfuse-web` exposes the standard Langfuse surface on the `langfuse`
subdomain:

- `GET  /api/public/health` — health/readiness probe.
- `POST /api/public/ingestion` — trace/observation ingestion (SDK target).
- `/api/public/*` — public REST API (projects, traces, scores, prompts…).
- `/` — Langfuse web UI (dashboards, traces, evals, prompt management).

`llamastack` exposes an OpenAI-compatible API on the `llamastack` subdomain
(`/v1/*`), backed by the OCI GenAI endpoint (`agent_obs_inference_url`).

---

## 3. Authentication

- **Admin bootstrap:** `corrino_admin_email` / `corrino_admin_username` /
  `corrino_admin_password` seed the initial Langfuse user via `LANGFUSE_INIT_*`.
- **Signup disabled:** `AUTH_DISABLE_SIGNUP=true` (no open registration).
- **SSO (optional, config-only):** set `agent_obs_oidc_issuer`,
  `agent_obs_oidc_client_id`, `agent_obs_oidc_client_secret`,
  `agent_obs_oidc_name`. Works with OCI IAM Identity Domains (IDCS) provided the
  identity domain emits a **domain-specific issuer** matching its discovery
  document, and the confidential app registers redirect URI
  `https://<langfuse-host>/api/auth/callback/custom`.

---

## 4. Agentic Model

Two modes (`agent_obs_genai_mode`):

- `existing` (default): wire to an existing OCI GenAI endpoint OCID
  (`agent_obs_existing_endpoint_ocid`).
- `create`: provision a Dedicated AI Cluster, import `dac_model_id` from
  HuggingFace, and create an endpoint (requires `dac_billing_acknowledgement`;
  billed hourly).

The resolved OpenAI-compatible inference URL is exposed as the
`agent_obs_inference_url` output and injected into `llamastack`.
