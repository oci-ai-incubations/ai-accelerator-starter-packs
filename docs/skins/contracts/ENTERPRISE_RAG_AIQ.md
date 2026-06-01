# enterprise_rag_aiq Pack — Backend API Contract

Companion document to [`BACKEND_API_CONTRACT.md`](../BACKEND_API_CONTRACT.md). That file is the multi-pack
reference organized around skin-access *mechanisms* (ingress paths vs env
vars). This file is the enterprise_rag_aiq-pack-specific deep dive
organized around *backend services and their API surface* — what a skin
author can actually call.

Scope: `starter_pack_category = "enterprise_rag_aiq"`. For other packs, see
[`CUOPT.md`](CUOPT.md), [`VSS.md`](VSS.md),
[`PAAS_RAG.md`](PAAS_RAG.md),
[`ENTERPRISE_RAG.md`](ENTERPRISE_RAG.md),
[`WAREHOUSE_PICK_PATH.md`](WAREHOUSE_PICK_PATH.md).

---

## 1. Deployment Mechanism — Two Helm Releases, Not Corrino

**The single most important fact about this pack:** enterprise_rag_aiq
installs **two distinct Helm releases** at Terraform apply time. Neither
is a Corrino recipe.

1. **`helm_release.rag`** — the same NVIDIA RAG Blueprint chart that
   `enterprise_rag` uses, installed in the app namespace
   (`local.starter_pack_config.app_namespace`, default `rag`). Supplies
   `rag-server`, `ingestor-server`, the vector store, NIMs, `nv-ingest`,
   and the rest of the RAG stack.
2. **`helm_release.aiq`** — the NVIDIA AI-Q chart (`aiq2-web` v2.0.0,
   renamed from the v1.x `aiq-aira` chart), installed in a separate
   namespace (`local.starter_pack_config.aiq_namespace`, default `aiq`).
   Supplies the `aiq-frontend` (UI), `aiq-agent` (orchestration backend),
   and a bundled `aiq-postgres` (job store / checkpoint DB). The v2.0.0
   chart does **not** ship Phoenix tracing or a bundled `instruct-llm`
   NIM — both were removed from v1.x. Intent classification is driven by
   the FRAG workflow against the `rag` release's `nim-llm` instead.

Source of truth: `ai-accelerator-tf/helm.tf:467-576` (rag) and
`helm.tf:709-767` (aiq).

| Concern                                  | `rag` release                                                                                            | `aiq` release                                                                                                                                                                  |
|------------------------------------------|----------------------------------------------------------------------------------------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Terraform resource                       | `helm_release.rag` (`helm.tf:467`)                                                                       | `helm_release.aiq` (`helm.tf:709`)                                                                                                                                              |
| Release name                             | `rag`                                                                                                     | `aiq`                                                                                                                                                                            |
| Namespace                                | `local.starter_pack_config.app_namespace` (default `rag`)                                                 | `local.starter_pack_config.aiq_namespace` (default `aiq`; `helm.tf:711`)                                                                                                          |
| Chart                                    | `nvidia-blueprint-rag` chart (NGC)                                                                       | `aiq2-web-2.0.0.tgz` (`helm.tf:720`) — **renamed** from v1.x `aiq-aira-v1.2.1.tgz`                                                                                                 |
| Chart auth                               | NGC `$oauthtoken` + `NGC_API_KEY`                                                                         | NGC `$oauthtoken` + `NGC_API_KEY` (`helm.tf:722-723`)                                                                                                                              |
| Values file                              | `helm-values/enterprise-rag-aiq-values.yaml`                                                              | `helm-values/aiq-aira-values.yaml` (`helm.tf:729`) — filename retained for backwards compatibility; contents are v2.0.0 values                                                    |
| Release timeout                          | NIM pulls — see RAG release definition                                                                    | 3600 s (60 min) (`helm.tf:725`)                                                                                                                                                   |
| Gating                                   | `local.deploy_app_rag ? 1 : 0` — both enterprise_rag and enterprise_rag_aiq (`helm.tf:570`)               | `local.deploy_app_rag_aiq ? 1 : 0` — enterprise_rag_aiq only (`helm.tf:756`)                                                                                                      |
| Frontend image skin override             | `frontend.image.{repository,tag}` from the selected skin (`helm.tf:549-556`) — **not user-facing here**   | `aiq.apps.frontend.image.{repository,tag}` from the selected skin (`helm.tf:746-753`) — **the one that reaches the user**. Note the chart-specific nested key path (v2.0.0 shape). |
| Backend URL overrides                    | (chart owns its own wiring)                                                                               | `aiq.apps.backend.env.{RAG_SERVER_URL, RAG_INGEST_URL}` → cross-namespace FQDNs with `/v1` suffix (`helm.tf:735-742`)                                                              |
| Oracle 26ai credentials                  | Injected for `enterprise_rag` only via `envVars.ORACLE_CS` and `ingestor-server.envVars.ORACLE_CS` (`helm.tf:559-568`); AIQ pack uses Milvus instead | n/a                                                                                                                                                                              |
| Pre-created secret dependency            | NGC secret                                                                                                | `aiq-credentials` secret pre-created by Terraform (`kubernetes_secret_v1.aiq_credentials` at `helm.tf:687-701`) — wires `NVIDIA_API_KEY`, `TAVILY_API_KEY`, `DB_USER_NAME`, `DB_USER_PASSWORD` into chart-level `aiq.sharedSecrets.autoMount` |
| `depends_on` chain                       | ingress-nginx, cert-manager, NGC secret job                                                               | `helm_release.rag`, NIM service-selector patches, AIQ-namespace configure job, `aiq-credentials` secret (`helm.tf:760-766`)                                                       |

**BUG-020 invariant.** The `skin_enterprise_rag_aiq` ORM dropdown must
override the frontend image set entries on **both** releases, even
though only the `aiq` release's frontend is user-facing. The override on
the `rag` release is a harmless no-op here but is kept for symmetry with
`enterprise_rag`, and the pair is locked by
`ai-accelerator-tf/schemas/tests/test_helm_skin_override.py`. As of the
v2.0.0 upgrade, the expected `set` key path differs per release — the
test's `RELEASES_REQUIRING_SKIN_OVERRIDE` dict maps each release name to
the chart-appropriate `(repository_key, tag_key)` tuple
(`rag → frontend.image.*`, `aiq → aiq.apps.frontend.image.*`). If you add
another Helm pack in the future, extend that mapping.

**Consequences of being Helm-deployed:**

- There is no `blueprint_files.tf` entry for this pack — both charts
  bring their own Services, Deployments, PVCs, ConfigMaps, and internal
  wiring.
- There is no `recipe_additional_ingress_ports` stitching API paths onto
  the frontend's subdomain (see §6.3).
- There is no `recipe_container_env` injection into the frontend
  container at deploy time. The chart's `aiq.apps.frontend.env` block in
  `aiq-aira-values.yaml:285-293` does set a small fixed set of variables
  (`BACKEND_URL`, `NODE_ENV`, `REQUIRE_AUTH`, `FILE_UPLOAD_*`,
  `NEXT_PUBLIC_DATADOG_ENABLED`) — see §6.2. This is a narrower
  Pattern-2 surface than `enterprise_rag` (which lets users add arbitrary
  `frontend.envVars`), but it is no longer empty as it was in v1.x.
- The Corrino REST API has no record of either release. A skin must
  never attempt to call Corrino.

---

## 2. Deployment Group Composition

The pack creates **two groups of services**. Services in the app
namespace belong to the `rag` release and are identical to what
`enterprise_rag` deploys — see
[`ENTERPRISE_RAG.md`](ENTERPRISE_RAG.md) §2 for the full table. Services
in the AIQ namespace belong to the `aiq` release (chart `aiq2-web`
v2.0.0) and are listed below.

### 2.1 AIQ-namespace services (`helm_release.aiq`)

> **TODO: verify against v2.0.0 cluster.** The exact rendered K8s
> Service names below (`aiq-frontend`, `aiq-backend`, `aiq-postgres`)
> are the short names that the chart's own internal references use
> (`aiq-aira-values.yaml:286` — `BACKEND_URL: http://aiq-backend:8000`;
> `:95-96` — `aiq-postgres:5432`) and the name that
> `ingress.tf:223` routes the user URL to (`aiq-frontend:3000`). The
> chart's templated Service-name pattern under `aiq2-web` v2.0.0 has not
> been confirmed end-to-end against a deployed cluster — confirm with
> `kubectl get svc -n <aiq_namespace>` after the next deploy and update
> any divergent rows here.

| K8s Service       | Container image (default)                                                  | Port    | GPU | Role                                                                                                                                                       |
|-------------------|---------------------------------------------------------------------------|---------|-----|-------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `aiq-frontend`    | Overridden by skin — default `nvcr.io/nvidia/blueprint/aiq-frontend:2.0.0`| 3000    | —   | User-facing frontend container. **Only service exposed via ingress.** Routed to at `ingress.tf:223`. Image default at `aiq-aira-values.yaml:240-242`.        |
| `aiq-backend`     | `nvcr.io/nvidia/blueprint/aiq-agent:2.0.0`                                | 8000    | —   | AI-Q orchestration FastAPI (formerly `aira-backend`, now renamed `aiq-agent`). Talks to `rag-server`, `ingestor-server`, and `nim-llm` cross-namespace, plus the bundled Postgres locally. Image + port at `aiq-aira-values.yaml:51-61`. The chart's `BACKEND_URL` at `:286` confirms the Service short name `aiq-backend`. |
| `aiq-postgres`    | `docker.io/bitnami/postgresql:latest`                                     | 5432    | —   | Bundled PostgreSQL — backs `aiq_jobs` (NAT job store) and `aiq_checkpoints` (agent checkpoints). New in v2.0.0; replaces v1.x's chart-internal store. Backed by a 10 Gi PVC on `oci-bv` (`aiq-aira-values.yaml:193-198`). Init script at `:170-192` creates the additional `aiq_checkpoints` DB and grants. |

**Removed from v1.x.** The v1.2.1 chart (`aiq-aira`) shipped two
additional services that are **not present** in v2.0.0:

- `instruct-llm` (`nvcr.io/nim/meta/llama-3.1-8b-instruct:latest`,
  GPU=1) — bundled NIM for intent classification. v2.0.0 routes
  intent / tool selection through the FRAG workflow against the `rag`
  release's `nim-llm` instead (see `aiq-aira-values.yaml:91`,
  `CONFIG_FILE: configs/config_web_frag.yml`).
- Arize Phoenix tracing sub-chart. Not deployed in v2.0.0.

The cumulative GPU footprint for `enterprise_rag_aiq` therefore drops
versus v1.x — this pack now consumes the same GPU resources as
`enterprise_rag` plus zero additional GPUs from the `aiq` release.

### 2.2 App-namespace services (`helm_release.rag`)

Same chart as the `enterprise_rag` pack — see
[`ENTERPRISE_RAG.md`](ENTERPRISE_RAG.md) §2 for the full service list
— but configured differently by
`ai-accelerator-tf/helm-values/enterprise-rag-aiq-values.yaml`. The
AIQ-specific differences that matter for this contract:

- **`rag-server` and `ingestor-server` images, tags, and ports** are
  defined in `enterprise-rag-aiq-values.yaml`. v2.0.0 of the AIQ chart
  requires **`/v1` suffix** on both backend URLs — Terraform sets this
  in the `aiq` release's `set` block (`helm.tf:735-742`):
  `RAG_SERVER_URL: http://rag-server.<app_ns>.svc.cluster.local:8081/v1`
  and
  `RAG_INGEST_URL: http://ingestor-server.<app_ns>.svc.cluster.local:8082/v1`.
- **Vector store is Milvus**, not Oracle 26ai. The Oracle 26ai
  credentials are injected only for `enterprise_rag`
  (`helm.tf:559-568`); AIQ uses Milvus.
- **No Oracle 26ai ADB is provisioned in parallel** for AIQ (Terraform
  module gating).
- **`rag-frontend` is deployed but dormant.** The RAG chart still
  renders a `rag-frontend` Service at port `3000`, but no ingress
  routes to it in this pack. Users reach the AIQ frontend, not the
  RAG one. The `rag-frontend` env vars are not a contract surface for
  AIQ skin authors.

### 2.3 Key facts across both releases

- **Only `aiq-frontend` is reachable from outside the cluster.** Every
  other Service (both namespaces) is `ClusterIP`. The
  `kubernetes_ingress_v1.enterprise_rag_aiq_frontend_ingress` rule
  (`ingress.tf:193-234`) publishes the single path `/` →
  `aiq-frontend:3000` on the pack's public host.
- **Cross-namespace DNS is used by the backend.** The `aiq-backend`
  reaches `rag-server` and `ingestor-server` via FQDNs that include
  the app namespace, set by `helm.tf:735-742` (with the v2.0.0 `/v1`
  suffix). The values-file defaults (`aiq-aira-values.yaml:99-100`)
  use the short names `rag-server:8081` and `ingestor-server:8082`,
  which only resolve when the AIQ namespace happens to equal the app
  namespace — Terraform always overrides at apply time.
- **`nim-llm` runs on a reserved tainted node**
  (`workload=nim-llm:NoSchedule`, applied by post-deploy patches in
  `helm.tf:584-681`). This applies to the rag stack deployed for the
  AIQ pack too.
- **No additional GPU is required for the AIQ release in v2.0.0.** The
  v1.x bundled `instruct-llm` (GPU=1) was removed; AIQ v2.0.0 reuses
  the rag stack's `nim-llm` for intent / tool routing via the FRAG
  workflow. Sizing of the full rag stack's GPU requirements is
  documented in [`ENTERPRISE_RAG.md`](ENTERPRISE_RAG.md) §2.
- **Pre-created `aiq-credentials` secret.** The v2.0.0 chart requires
  a `Secret/aiq-credentials` in the AIQ namespace with `NVIDIA_API_KEY`,
  `TAVILY_API_KEY`, `DB_USER_NAME`, and `DB_USER_PASSWORD` populated;
  the chart's `aiq.sharedSecrets.autoMount` wires them in via `envFrom`.
  Terraform pre-creates this secret at `helm.tf:687-701` and generates
  the DB password locally (`random_password.aiq_db_password`).
- **Tavily search key.** Provided through the `aiq-credentials` secret
  above (`TAVILY_API_KEY` keyed from `var.tavily_api_key`). When that
  var changes, Terraform rolls all Deployments in the AIQ namespace
  (`terraform_data.aiq_restart_on_tavily_change*`, `helm.tf:772-806`)
  so the backend picks up the new key.

---

## 3. Backend Service — `aiq-backend` (formerly `aira-backend`)

The AI-Q orchestration layer. Built from the open-source
`NVIDIA-AI-Blueprints/aiq` repo (linked from `docs/skins/README.md`
§Enterprise Agentic AI Starter Kit) and packaged by NVIDIA as the
`aiq-agent:2.0.0` container image (renamed from v1.x's `aira-backend`).
A FastAPI app built on NVIDIA's NeMo Agent Toolkit (NAT).

- **In-cluster address:** `http://aiq-backend.<aiq_namespace>.svc.cluster.local:8000`
  (short name `aiq-backend:8000` from within the AIQ namespace).
  **Port changed in v2.0.0 from 3838 to 8000.** Image at
  `aiq-aira-values.yaml:51-53`; port at `:59-61`. The Service short
  name `aiq-backend` is inferred from `:286`
  (`BACKEND_URL: http://aiq-backend:8000` set on the frontend container,
  pointing at the backend Service).
  **TODO: verify against v2.0.0 cluster** with `kubectl get svc -n <aiq_namespace>`.
- **URL prefix:** no global prefix. Routes sit at `/health`, `/chat`,
  `/v1/...`, `/generate/...`, `/websocket`.
- **Framework:** FastAPI; the app is constructed by the `AIQAPIWorker`
  plugin at `aiq` repo
  `frontends/aiq_api/src/aiq_api/plugin.py`.
- **Source for route list:** upstream `aiq` repo —
  `frontends/aiq_api/src/aiq_api/routes/{collections,documents,jobs}.py`
  for AIQ-specific routes, plus NAT's `FastApiFrontEndPlugin` for
  `/chat`, `/chat/stream`, `/v1/chat/completions`, `/generate/*`, and
  `/websocket`. **TODO: verify the v2.0.0 binary's route surface**
  against the v2.0.0 release tag (https://github.com/NVIDIA-AI-Blueprints/aiq/releases/tag/2.0.0)
  rather than current `main` — the AI-Q rename may have shifted some
  internal route module paths even when the externally observed routes
  are unchanged.
- **OpenAPI / Swagger:** `GET /docs`, `GET /redoc`, `GET /openapi.json`
  (FastAPI auto-generated). These are developer introspection endpoints
  and are reachable only from inside the cluster.
- **Auth, CORS, and bearer-token handling:** not part of this contract.
  See `docs/integrations/oci-idcs.md` for the starter pack's overall
  auth story; the `aiq` repo's
  `frontends/aiq_api/src/aiq_api/auth/middleware.py` owns backend
  middleware behavior.
- **Job-store database (new in v2.0.0):** the backend persists NAT job
  state and agent checkpoints in the bundled `aiq-postgres` Service.
  Connection strings are wired through `aiq.apps.backend.env` at
  `aiq-aira-values.yaml:95-97`:
  `NAT_JOB_STORE_DB_URL`, `AIQ_CHECKPOINT_DB`, and `AIQ_SUMMARY_DB` —
  all pointing at `aiq-postgres:5432/aiq_jobs` with credentials drawn
  from the `aiq-credentials` secret. Skins do not interact with this
  database directly.

**Scope caveat.** The `aiq-agent:2.0.0` image is a binary built by
NVIDIA from a v2.0.0 snapshot of the `aiq` repo. The route tables below
are drawn from the `aiq` repo's `main` branch (and were originally
written against v1.x); they remain the most concrete reference
available to skin authors. They are informational — the starter pack
does not expose `aiq-backend` externally, and skin authors should
integrate via the frontend's `/api/*` surface (§6.4), not by hard-coding
backend paths.

### 3.1 Chat and agent orchestration

| Method | Path                          | Purpose                                                                                                                                        |
|--------|-------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------|
| POST   | `/chat`                       | Chat entry point. Route listed in the external allowlist (`middleware.py:113`); provided by NAT's FastAPI frontend plugin.                     |
| POST   | `/chat/stream`                | Streaming chat. The upstream frontend's `/api/chat` proxies here (`aiq` repo — `frontends/ui/src/app/api/chat/route.ts`). Returns SSE.          |
| POST   | `/v1/chat/completions`        | OpenAI-compatible chat completions (`middleware.py:115`). Provided by NAT's plugin.                                                            |
| POST   | `/generate/stream`            | Agent generation with intermediate `thinking` / `prompt` / `status` SSE events. Upstream frontend proxies `/api/generate` here (`generate/route.ts:46`). |
| POST   | `/generate/respond`           | Human-in-the-loop reply endpoint, paired with a prior `/generate/stream` call that raised a `prompt` event (`generate/respond/route.ts:35`).    |
| WS     | `/websocket`                  | Real-time agent session with HITL support. Upstream frontend's gateway proxies here (`frontends/ui/server.js:161-162`).                        |

### 3.2 Async deep-research jobs

The canonical deep-research flow is:

1. `POST /v1/jobs/async/submit` → `{ job_id, status, agent_type }`.
2. `GET /v1/jobs/async/job/{job_id}/stream[/{last_event_id}]` → resumable SSE.
3. (Optional) `POST /v1/jobs/async/job/{job_id}/cancel` to interrupt.
4. `GET /v1/jobs/async/job/{job_id}/report` once the job finishes.

| Method | Path                                              | Purpose                                                                                                              |
|--------|---------------------------------------------------|----------------------------------------------------------------------------------------------------------------------|
| GET    | `/v1/jobs/async/agents`                           | Enumerate the agent kinds this deployment supports (`{agent_type, description}`).                                    |
| POST   | `/v1/jobs/async/submit`                           | Submit a new async job. Body: `JobSubmitRequest(agent_type, input, job_id?, expiry_seconds?)`. |
| GET    | `/v1/jobs/async/job/{job_id}`                     | Status: `submitted \| running \| success \| failure \| interrupted \| not_found`.           |
| GET    | `/v1/jobs/async/job/{job_id}/stream`              | SSE event stream from event 0. Resumable via the `last_event_id` path variant.              |
| GET    | `/v1/jobs/async/job/{job_id}/stream/{last_event_id}` | Resume SSE after network interruption.                                                   |
| POST   | `/v1/jobs/async/job/{job_id}/cancel`              | Request cancellation; marks the job INTERRUPTED.                                             |
| GET    | `/v1/jobs/async/job/{job_id}/state`               | Artifact bundle: tool calls, outputs, citations.                                             |
| GET    | `/v1/jobs/async/job/{job_id}/report`              | Extract the final research report from the job's last output.                                |

**SSE semantics:** `Content-Type: text/event-stream`,
`Cache-Control: no-cache`, `X-Accel-Buffering: no`. Event payloads use
NAT message types (`WebSocketSystemResponseTokenMessage`,
`WebSocketSystemIntermediateStepMessage`, etc.).

**Ownership.** Job-ownership enforcement (write on submit, check on
subsequent calls) is driven by the backend's auth configuration. See
`docs/integrations/oci-idcs.md` for the starter pack's overall auth
story; the backend-side implementation lives in the `aiq` repo under
`frontends/aiq_api/src/aiq_api/auth/` and `jobs/access.py`.

### 3.3 Knowledge management (AI-Q's own wrappers around `ingestor-server`)

These routes are how the upstream `aiq-frontend` uploads documents and
lists collections through the `aiq-backend`, which in turn talks to
`ingestor-server`. A skin should reach them through the frontend's
`/api/v1/collections/...` paths rather than directly.

| Method | Path                                            | Purpose                                                                     |
|--------|-------------------------------------------------|-----------------------------------------------------------------------------|
| POST   | `/v1/collections`                               | Create a collection. Returns `CollectionInfo`.                              |
| GET    | `/v1/collections`                               | List collections.                                                            |
| GET    | `/v1/collections/{name}`                        | Fetch a single collection.                                                   |
| DELETE | `/v1/collections/{name}`                        | Delete a collection.                                                         |
| POST   | `/v1/collections/{name}/documents`              | Multipart upload. Returns `UploadResponse(job_id, file_ids, message)`.      |
| GET    | `/v1/collections/{name}/documents`              | List documents in a collection.                                              |
| DELETE | `/v1/collections/{name}/documents`              | Delete documents by ID.                                                      |
| GET    | `/v1/documents/{job_id}/status`                 | Poll ingestion job status.                                                   |
| GET    | `/v1/knowledge/health`                          | Knowledge backend health (e.g. can the backend reach `ingestor-server`).    |

### 3.4 Data sources and health

| Method | Path                | Purpose                                                                                                                                                                |
|--------|---------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| GET    | `/v1/data_sources`  | List enabled data sources (web search, paper search, knowledge, etc.) with `requires_auth`.                                                                            |
| GET    | `/health`           | Liveness + readiness. Returns `{status, dask_available, db}`; HTTP 503 when DB is unreachable. Verified against the aiq repo at `frontends/aiq_api/src/aiq_api/routes/jobs.py:244-270`. |

### 3.5 Endpoints not to call from a skin

- `/docs`, `/redoc`, `/openapi.json` — developer introspection only;
  reachable only inside the cluster (useful for port-forwarding during
  debugging, not a published contract).
- Direct cross-origin browser traffic to `aiq-backend:8000`. The
  backend's default CORS policy in the `aiq` repo is locked to
  `http://localhost(:\d+)?|http://127.0.0.1(:\d+)?`. The intended
  integration point is a server-side BFF inside the skin container
  (§6). **TODO: verify against v2.0.0 cluster** that the CORS allowlist
  was not relaxed in the v2.0.0 release — the v1.x source path was
  `configs/config_web_default_llamaindex.yml`, but v2.0.0 uses
  `configs/config_web_frag.yml` (`aiq-aira-values.yaml:91`) which has
  not been inspected for this doc.

### 3.6 External-facing path allowlist (`aiq` repo)

Independent of the CORS rule, the `aiq` repo's auth middleware enforces
an `EXTERNAL_ALLOWED_PATHS` list
(`frontends/aiq_api/src/aiq_api/auth/middleware.py:108-120`). If a
request's `Host` header matches `AIQ_EXTERNAL_HOSTNAMES`, only these
paths are reachable; everything else returns 404:

`/health`, `/docs`, `/redoc`, `/openapi.json`, `/chat`, `/chat/stream`,
`/v1/chat/completions`, `/v1/data_sources`, `/v1/jobs/async/agents`,
`/v1/jobs/async/submit`, and any path under the `/v1/jobs/async/job/`
prefix.

Paths outside this allowlist — `/v1/collections/*`, `/v1/documents/*`,
`/generate/stream`, `/generate/respond`, `/websocket`,
`/v1/knowledge/health` — are reachable only from in-cluster
(non-external) callers. A skin that proxies them through its own BFF
inside the cluster is unaffected; a skin that tried to publish them on
an external hostname would see 404s. This may or may not be enforced
in the shipped `aiq-agent:2.0.0` image depending on how it's configured;
**TODO: verify against v2.0.0 cluster** with the deployed build.

---

## 4. Backend Services — `rag-server` and `ingestor-server`

The AIQ pack also deploys the full RAG Blueprint stack in the app
namespace. From a skin author's perspective these services are
**transitive dependencies of `aiq-backend`**, not a primary contract
surface:

- The `aiq-backend` reaches `rag-server` via `RAG_SERVER_URL` and
  `ingestor-server` via `RAG_INGEST_URL` (both overridden by
  `helm.tf:735-742` to cross-namespace FQDNs on ports 8081 and 8082,
  with the **v2.0.0-required `/v1` suffix**).
- The `aiq-frontend` never reaches `rag-server` or `ingestor-server`
  directly (unlike in the `enterprise_rag` pack where
  `VITE_API_CHAT_URL` and `VITE_API_VDB_URL` point the frontend at
  them).
- Full route documentation for `rag-server` (`/v1/generate`,
  `/v1/chat/completions`, `/v1/search`, `/v2/vector_stores/.../search`,
  `/v1/summary`, `/v1/configuration`, `/v1/health`, `/v1/metrics`) and
  `ingestor-server` (`/v1/documents`, `/v1/status`, `/v1/collections`,
  `/v1/collection`, `/v1/health`) lives in
  [`ENTERPRISE_RAG.md`](ENTERPRISE_RAG.md) §3–§4 and applies unchanged
  here.

If a replacement skin needs direct access to `rag-server` or
`ingestor-server` (for instance to bypass `aiq-backend`'s orchestration
and query Milvus directly), the skin must do the same in-container proxy
work described in §6 — and must cross the namespace boundary, since the
RAG services live in `<app_namespace>` (default `rag`) while the skin
runs in `<aiq_namespace>` (default `aiq`). Use the FQDNs
`rag-server.<app_namespace>.svc.cluster.local:8081` and
`ingestor-server.<app_namespace>.svc.cluster.local:8082` — append `/v1`
when calling the v2.0.0 chart's expected route surface.

---

## 5. Frontend Skins (Catalog)

enterprise_rag_aiq ships one skin. The `skin_enterprise_rag_aiq` ORM
variable is an enum dropdown; its sole option today is the NVIDIA AI-Q
Core App skin. Source:
`ai-accelerator-tf/schemas/frontend_skins.yaml:53-60`.

| Skin     | Enum variable              | `container_port` | `subdomain` | Default image                                       |
|----------|----------------------------|------------------|-------------|------------------------------------------------------|
| Core App | `skin_enterprise_rag_aiq`  | 3000             | `aiq`       | `nvcr.io/nvidia/blueprint/aiq-frontend:2.0.0`        |

Ingress host: `https://aiq.<fqdn>`. `<fqdn>` resolves to the generated
`nip.io` domain (default) or a user-supplied FQDN if
`use_custom_dns = true`. The resolved host is
`local.public_endpoint.starter_pack` as referenced by
`ingress.tf:212,216`.

**Skin image override.** The selected skin's `image_uri` is split on
`:` and fed into **both** Helm releases — but at chart-specific value
paths because the two releases use different chart shapes:

- `rag` release: flat `frontend.image.{repository,tag}` (`helm.tf:549-556`).
- `aiq` release: nested `aiq.apps.frontend.image.{repository,tag}`
  (`helm.tf:746-753`) — the `aiq2-web` v2.0.0 chart is a parent chart
  that includes the workload as a sub-chart, so all values are
  namespaced under `aiq.apps.<component>`.

Only the `aiq` override is user-facing; the `rag` override is kept in
lockstep for symmetry with `enterprise_rag` and is locked together with
the AIQ override by `test_helm_skin_override.py` (which now keys
expected paths per release).

---

## 6. How a Skin Reaches the Backends

> **Critically different from both cuopt and enterprise_rag.** Like
> `enterprise_rag`, AIQ does not stitch API paths onto the frontend
> subdomain — the only ingress rule is `/` → `aiq-frontend:3000`.
> **Unlike v1.x**, the v2.0.0 chart **does** set a small fixed env-var
> set on the frontend container, including a `BACKEND_URL` pointing at
> `aiq-backend:8000`. That gives skins a narrow Pattern-2 surface where
> v1.x had none — but it is **not** a user-extensible `envVars` list
> like `enterprise_rag`'s.

### 6.1 Ingress — what is and isn't published

Source: `ai-accelerator-tf/ingress.tf:193-234`.

| Ingress resource                             | Host                                       | Path rules   | Backend                  | TLS                                  |
|----------------------------------------------|--------------------------------------------|--------------|--------------------------|--------------------------------------|
| `enterprise_rag_aiq_frontend_ingress`        | `local.public_endpoint.starter_pack` (`aiq.<fqdn>`) | `/` (Prefix) | `aiq-frontend:3000`      | `letsencrypt-prod` (cert-manager)    |

Relevant nginx annotations (`ingress.tf:200-207`):

- `nginx.ingress.kubernetes.io/proxy-body-size: 2g` — multi-megabyte
  document uploads work through the frontend ingress.
- `nginx.ingress.kubernetes.io/proxy-{read,send,connect}-timeout: 600` —
  10-minute timeouts for long-running deep-research jobs and streaming
  chat responses.
- `nginx.ingress.kubernetes.io/rewrite-target: /` — no-op here since
  only `/` is published.

No auth annotation. `aiq-backend:8000`, `aiq-postgres:5432`,
`rag-server:8081`, `ingestor-server:8082`, `nim-llm:8000`, Milvus,
MinIO, NIMs — none of these have ingress rules. They are not reachable
from the browser.

### 6.2 Pattern 2 — Limited (chart-fixed env vars on the frontend)

The v2.0.0 chart's `aiq.apps.frontend.env` block sets a fixed set of
env vars on the frontend container
(`aiq-aira-values.yaml:285-293`):

| Env var                              | Value                            | Purpose                                                                  |
|--------------------------------------|----------------------------------|--------------------------------------------------------------------------|
| `BACKEND_URL`                        | `http://aiq-backend:8000`        | Same-namespace short URL for the AI-Q orchestration backend (`aiq-agent`).|
| `NODE_ENV`                           | `production`                     | Standard Node runtime mode.                                              |
| `REQUIRE_AUTH`                       | `"false"`                        | Controls whether the frontend requires the bundled auth flow.            |
| `FILE_UPLOAD_ACCEPTED_TYPES`         | `.pdf,.docx,.txt,.md`            | Accepted file extensions for document upload.                            |
| `FILE_UPLOAD_MAX_SIZE_MB`            | `"100"`                          | Max upload size per file.                                                |
| `FILE_UPLOAD_MAX_FILE_COUNT`         | `"10"`                           | Max files per upload batch.                                              |
| `FILE_EXPIRATION_CHECK_INTERVAL_HOURS`| `"0"`                            | Disable expiration sweep.                                                |
| `NEXT_PUBLIC_DATADOG_ENABLED`        | `"false"`                        | Disable Datadog client telemetry.                                        |

`BACKEND_URL` is the only one a replacement skin would normally read
from the env. It points at the bundled backend service inside the AIQ
namespace and resolves only inside the cluster.

The backend env vars under `aiq.apps.backend.env`
(`aiq-aira-values.yaml:87-103`, overridden by `helm.tf:735-742` for
`RAG_SERVER_URL` / `RAG_INGEST_URL`) — `APP_ENV`, `LOG_LEVEL`,
`CONFIG_FILE`, `DASK_NWORKERS`, `DASK_NTHREADS`, the three Postgres
connection strings, `RAG_SERVER_URL`, `RAG_INGEST_URL`,
`COLLECTION_NAME`, `AIQ_CHROMA_DIR`, `MODE` — are injected into the
**backend** pod, not the frontend.

**Practical consequence:** a replacement skin container gets one
backend URL from the chart (`BACKEND_URL`) and that's it. If the skin
needs anything beyond `aiq-backend` (for instance to call `rag-server`
or `ingestor-server` directly across namespaces), the skin must either
hard-code the cluster DNS names or template a `config.js` from its own
chart values. There is no `frontend.envVars` extension point in this
chart.

### 6.3 Pattern 1 — Not available

There is no `recipe_additional_ingress_ports` equivalent for Helm packs.
To expose backend paths on the frontend subdomain you would need to
either (a) add a second ingress resource in `ingress.tf` that routes
paths like `/api/chat/*` to `aiq-backend:8000/*` with the appropriate
rewrite, or (b) have the skin container itself proxy those paths
internally. Option (b) is the path a skin author can take without
editing the starter pack — see §7.2.

### 6.4 What a drop-in skin must mirror

The upstream `aiq-frontend:2.0.0` image is built from the `aiq` repo's
`frontends/ui/` (Next.js; see `docs/skins/README.md` §Enterprise
Agentic AI Starter Kit). It acts as a same-origin BFF: the browser
calls `/api/*` paths, each Next.js handler reads the chart-injected
`BACKEND_URL` env var, and forwards to the corresponding `aiq-backend`
route; WebSocket upgrades on `/websocket` are proxied to
`aiq-backend:8000/websocket`.

A drop-in skin has two supported integration paths:

1. **Same-shape replacement.** Ship a frontend that speaks the same
   relative `/api/*` paths as the upstream `aiq-frontend`
   (`/api/chat`, `/api/generate[/respond]`, `/api/jobs/async/[...]`,
   `/api/v1/[...]`, `/api/health`, `/api/auth/[...nextauth]`,
   `/api/generate-pdf`, plus a same-origin `ws://.../websocket`
   upgrade). Internally the skin container runs its own BFF (Node,
   Go, nginx, …) that forwards those paths to `aiq-backend:8000`.
   The skin's BFF can read `BACKEND_URL` from the env to keep the
   target service-DNS portable. This is the low-friction path.
   **TODO: verify against v2.0.0 cluster** that the upstream
   `aiq-frontend` still calls the same `/api/*` route shapes; the
   v2.0.0 release notes mention frontend rewrites in addition to the
   image rename, so a skin author should sanity-check the actual
   browser → frontend traffic before assuming the v1.x table holds
   verbatim.
2. **Chart modification.** Fork `aiq2-web` (or propose an upstream PR)
   to add a `frontend.envVars` list so the skin can read additional
   backend URLs at runtime the way `enterprise_rag` skins read
   `VITE_API_CHAT_URL`. Higher friction; warranted only when (1) isn't
   sufficient (e.g., the skin needs to address `rag-server` or
   `ingestor-server` across the namespace boundary without
   hard-coding their DNS names).

### 6.5 What your skin container must do

Summary of the skin contract:

1. Listen on port **3000** (from the catalog `container_port`). Your
   container receives plain HTTP from nginx-ingress; TLS is terminated
   upstream.
2. Publish the UI on any paths you like — everything under
   `aiq.<fqdn>/` routes to your container.
3. Implement a server-side relay (SSR, API routes, or an in-container
   reverse proxy) for every backend call the browser makes, because
   `aiq-backend`'s CORS locks out cross-origin browser traffic and the
   Ingress does not route any backend paths directly.
4. Read **`BACKEND_URL`** from the environment to locate `aiq-backend`
   (the chart sets `http://aiq-backend:8000` on the frontend container).
   For anything beyond `aiq-backend` — e.g., direct cross-namespace
   calls to `rag-server` or `ingestor-server` — your skin's image or
   your own custom Helm values must own the DNS names. The chart does
   not inject `RAG_SERVER_URL` / `RAG_INGEST_URL` on the frontend.

---

## 7. Worked Examples

### 7.1 Browser — streaming chat through a same-origin server route

Assumes the skin runs a Node BFF with an `/api/chat` route that proxies
to `aiq-backend`. Identical to the upstream `aiq-frontend`'s own
wiring.

```js
// Browser-side chat with SSE streaming.
async function streamChat(messages, onDelta) {
  const resp = await fetch('/api/chat', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      messages,
      // aiq-backend decides RAG / search / no-KB routing from the
      // configured workflow; the frontend passes the user prompt and
      // whatever UX toggles it exposes.
    }),
  });
  if (!resp.ok) throw new Error(`aiq-backend ${resp.status}`);

  const reader = resp.body.getReader();
  const decoder = new TextDecoder();
  let buffer = '';
  while (true) {
    const { value, done } = await reader.read();
    if (done) return;
    buffer += decoder.decode(value, { stream: true });
    const lines = buffer.split('\n');
    buffer = lines.pop();                        // keep partial line
    for (const line of lines) {
      if (!line.startsWith('data: ')) continue;
      const data = line.slice(6).trim();
      if (data === '[DONE]') return;
      try { onDelta(JSON.parse(data)); } catch { /* ignore partial frame */ }
    }
  }
}
```

### 7.2 nginx reverse proxy (drop-in alternative to SSR)

A minimal `nginx.conf` that the skin container can use instead of an
SSR layer. Browser calls `/api/*`; nginx forwards in-cluster. The
backend hostname is the chart-injected `BACKEND_URL` (`http://aiq-backend:8000`),
so the skin can keep this hostname soft via a templated config rather
than baking it in — but for clarity the example below shows it
hard-coded.

```nginx
server {
  listen 3000;

  # Static bundle for the SPA.
  root /usr/share/nginx/html;
  try_files $uri /index.html;

  # All aiq-backend routes under /api/*.
  location /api/ {
    proxy_pass         http://aiq-backend:8000/;
    proxy_http_version 1.1;
    proxy_set_header   Host $host;
    proxy_set_header   Connection '';
    proxy_buffering    off;                         # critical for SSE
    proxy_read_timeout 600s;
    client_max_body_size 2g;                        # matches ingress annotation
  }

  # WebSocket passthrough for agent / HITL sessions.
  location /websocket {
    proxy_pass         http://aiq-backend:8000/websocket;
    proxy_http_version 1.1;
    proxy_set_header   Upgrade $http_upgrade;
    proxy_set_header   Connection "upgrade";
    proxy_read_timeout 600s;
  }
}
```

Then from the browser:

```js
await fetch('/api/chat', { method: 'POST', body: ... });
const status = await fetch(`/api/v1/documents/${jobId}/status`).then(r => r.json());
const ws = new WebSocket(`wss://${location.host}/websocket`);
```

### 7.3 Submitting an async deep-research job and streaming it

```js
// Browser — submit, then tail the SSE stream until completion.
async function runDeepResearch(prompt) {
  const submit = await fetch('/api/v1/jobs/async/submit', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      agent_type: 'deep_researcher',
      input: prompt,
      expiry_seconds: 86400,
    }),
  }).then(r => r.json());

  const jobId = submit.job_id;
  const es = new EventSource(`/api/v1/jobs/async/job/${jobId}/stream`);

  es.onmessage = (ev) => {
    const msg = JSON.parse(ev.data);
    // NAT message types: WebSocketSystemResponseTokenMessage,
    // WebSocketSystemIntermediateStepMessage, etc.
    switch (msg.type) {
      case 'system_response_token':     appendToken(msg.token); break;
      case 'system_intermediate_step':  appendStep(msg);         break;
      case 'system_response_message':   finalize(msg); es.close(); break;
    }
  };

  // Later, when the user clicks "Cancel":
  await fetch(`/api/v1/jobs/async/job/${jobId}/cancel`, { method: 'POST' });
}
```

### 7.4 Uploading a document into a collection

```js
// Browser — upload through the frontend's /api/* proxy.
// aiq-backend → ingestor-server:8082 handles the real work.
async function uploadToCollection(file, collectionName) {
  const form = new FormData();
  form.append('files', file);

  const { job_id } = await fetch(
    `/api/v1/collections/${encodeURIComponent(collectionName)}/documents`,
    { method: 'POST', body: form }
  ).then(r => r.json());

  while (true) {
    const st = await fetch(`/api/v1/documents/${job_id}/status`)
      .then(r => r.json());
    if (st.state === 'FINISHED') return st.result;
    if (st.state === 'FAILED')   throw new Error('ingestion failed');
    await new Promise(res => setTimeout(res, 2000));
  }
}
```

### 7.5 Resuming an SSE stream after a network blip

The stream endpoint supports a `last_event_id` path variant for
resumption. Drive it from the browser when `EventSource` reconnects.

```js
let lastId = null;
function openStream(jobId) {
  const url = lastId == null
    ? `/api/v1/jobs/async/job/${jobId}/stream`
    : `/api/v1/jobs/async/job/${jobId}/stream/${lastId}`;

  const es = new EventSource(url);
  es.onmessage = (ev) => { lastId = ev.lastEventId; handleEvent(ev); };
  es.onerror = () => { es.close(); setTimeout(() => openStream(jobId), 1000); };
}
```

---

## 8. What Is Not in the Contract

A skin must treat the following as internal and must not hard-code
assumptions against them. They exist in the cluster but are not part of
the pack's advertised surface, and they can change between chart
versions without notice.

| Surface                                                                   | Why it is internal                                                                                                        |
|---------------------------------------------------------------------------|---------------------------------------------------------------------------------------------------------------------------|
| `aiq-backend` direct HTTP access from the browser                         | CORS is locked to `localhost`/`127.0.0.1`; the intended consumer is a BFF inside the skin container.                      |
| `aiq-backend` route list (`§3`) as a stable contract                      | The route list is documented from the upstream `aiq` repo; NVIDIA's `aiq-agent:2.0.0` image may add or rename routes between releases. Use the frontend's `/api/*` shape as the stable integration point. |
| `aiq-postgres:5432` (bundled job/checkpoint store, new in v2.0.0)         | Backs the AI-Q backend's NAT job store and agent checkpoints. Connection strings are wired into the backend container only (`aiq-aira-values.yaml:95-97`). Skins must not connect to Postgres directly; use the agent API (`§3.2`) for job lifecycle. |
| `rag-frontend` from the `rag` release                                     | Deployed but intentionally **not user-facing** for this pack; no ingress routes to it. The `frontend.image.*` override on `rag` is a BUG-020 lockstep no-op.          |
| `rag-server:8081`, `ingestor-server:8082`                                 | Transitive backend for `aiq-backend`; reach them through `/api/v1/collections/...`, `/api/v1/documents/...`, or the agent endpoints, not directly. v2.0.0 calls them with a `/v1` suffix. |
| `nim-llm:8000`, `nemoretriever-embedding-ms:8000`, `nemoretriever-ranking-ms:8000`, `nim-vlm:8000` | NIM microservices called by `aiq-backend` / `rag-server`. Talking to them directly bypasses orchestration, guardrails, and metrics. The v1.x bundled `instruct-llm:8000` is **not present** in v2.0.0. |
| `rag-nv-ingest:7670` (and related nv-ingest sub-services)                 | Ray extraction pipeline (`enterprise-rag-aiq-values.yaml`). `ingestor-server` is the abstraction layer.                    |
| `milvus:19530`, `milvus:9091`                                             | Vector-store wire protocol. AIQ uses Milvus (set in `enterprise-rag-aiq-values.yaml`); reach it via the ingestor.          |
| `rag-minio:9000`                                                          | S3-compatible blob store for multimodal content (configured in `enterprise-rag-aiq-values.yaml`).                          |
| `rag-redis-master:6379`                                                   | Task queue. Poll via the ingestor's `/v1/status`, not Redis directly (configured in `enterprise-rag-aiq-values.yaml`).     |
| `nemo-guardrails:7331` (when enabled)                                      | Optional content-safety filter (configured in `enterprise-rag-aiq-values.yaml`).                                          |
| Corrino REST API (`/deployment/`, `/deploy/`, `/validate/`, `/workspace/`) | Control-plane API for recipe-based packs. Not involved here.                                                              |
| `corrino-configmap` values (`REGION_NAME`, `COMPARTMENT_ID`, …)            | Exist in the cluster for recipe-based packs. The `aiq2-web` chart does not mount them.                                    |
| OpenTelemetry / Prometheus / Grafana / Zipkin                              | Observability infrastructure, operator-level. The v1.x bundled Arize Phoenix tracing sub-chart is **not present** in v2.0.0; tracing must be wired externally if needed. |
| `aiq-backend /docs`, `/redoc`, `/openapi.json`, `/metrics`                 | Developer / scrape targets, reachable only inside the cluster.                                                             |

If a skin finds itself needing one of these, the right move is to file
a chart issue upstream (NVIDIA `aiq2-web` / `aiq` repo) or extend
`aiq-backend` — not to call the internal service directly.

---

## 9. Source of Truth

| Concern                                                        | File / URL                                                                                                       |
|----------------------------------------------------------------|------------------------------------------------------------------------------------------------------------------|
| Terraform helm_release for the `rag` chart                     | `ai-accelerator-tf/helm.tf:467-576`                                                                              |
| Values file selector for the `rag` release (enterprise_rag_aiq branch) | `ai-accelerator-tf/helm.tf` (`file("helm-values/enterprise-rag-aiq-values.yaml")`)                       |
| Terraform helm_release for the `aiq` chart (`aiq2-web` v2.0.0) | `ai-accelerator-tf/helm.tf:709-767`                                                                              |
| Cross-namespace backend URL overrides (with `/v1` suffix)      | `ai-accelerator-tf/helm.tf:735-742`                                                                              |
| Frontend image skin override (both releases, BUG-020)          | `ai-accelerator-tf/helm.tf:549-556` (rag, flat path), `helm.tf:746-753` (aiq, nested path under `aiq2-web` v2.0.0)|
| `aiq-credentials` secret pre-creation (NGC + Tavily + DB creds)| `ai-accelerator-tf/helm.tf:687-701`                                                                              |
| Random DB password generator                                   | `ai-accelerator-tf/helm.tf:703-707`                                                                              |
| Tavily-key change → AIQ namespace rollout                      | `ai-accelerator-tf/helm.tf:772-806`                                                                              |
| AIQ namespace creation                                         | `ai-accelerator-tf/helm.tf:453-456`                                                                              |
| `rag` release values (AIQ-specific overrides — Milvus, no Oracle) | `ai-accelerator-tf/helm-values/enterprise-rag-aiq-values.yaml`                                              |
| `aiq` release values (`aiq2-web` v2.0.0 full chart config)     | `ai-accelerator-tf/helm-values/aiq-aira-values.yaml` (filename retained from v1.x)                               |
| — `aiq.appname` / `aiq.project` chart-level identifiers        | `helm-values/aiq-aira-values.yaml:8-29`                                                                          |
| — `aiq.sharedSecrets.autoMount` (envFrom → `aiq-credentials`)  | `helm-values/aiq-aira-values.yaml:33-37`                                                                         |
| — `aiq.apps.backend` (image, port 8000, env, init container)   | `helm-values/aiq-aira-values.yaml:42-143`                                                                        |
| — `aiq.apps.postgres` (bundled job/checkpoint DB, init SQL)    | `helm-values/aiq-aira-values.yaml:145-230`                                                                       |
| — `aiq.apps.frontend` (image, port 3000, fixed env vars)       | `helm-values/aiq-aira-values.yaml:232-299`                                                                       |
| Frontend ingress rule                                          | `ai-accelerator-tf/ingress.tf:193-234`                                                                           |
| Skin catalog entry                                             | `ai-accelerator-tf/schemas/frontend_skins.yaml:53-60`                                                            |
| Skin-override invariant test                                   | `ai-accelerator-tf/schemas/tests/test_helm_skin_override.py`                                                     |
| Upstream `rag` chart (NGC)                                     | https://helm.ngc.nvidia.com/nvidia/blueprint/charts/nvidia-blueprint-rag-v2.3.0.tgz                              |
| Upstream `aiq2-web` chart (NGC, v2.0.0)                        | https://helm.ngc.nvidia.com/nvidia/blueprint/charts/aiq2-web-2.0.0.tgz                                           |
| Upstream AI-Q release notes                                    | https://github.com/NVIDIA-AI-Blueprints/aiq/releases/tag/2.0.0                                                   |
| `aiq-backend` upstream repo (backend image source)             | `NVIDIA-AI-Blueprints/aiq` — linked from `docs/skins/README.md` §Enterprise Agentic AI Starter Kit               |
| `aiq-backend` FastAPI app construction                         | `aiq` repo — `frontends/aiq_api/src/aiq_api/plugin.py` (line numbers shift between releases)                     |
| `aiq-backend` AIQ-specific route definitions                   | `aiq` repo — `frontends/aiq_api/src/aiq_api/routes/{collections,documents,jobs}.py` (TODO: re-verify against the v2.0.0 release tag) |
| `aiq-backend` NAT-provided routes (`/chat`, `/v1/chat/completions`, `/generate/*`, `/websocket`) | NAT's `FastApiFrontEndPlugin` (TODO: re-verify against v2.0.0 image)        |
| `aiq-backend` external path allowlist                          | `aiq` repo — `frontends/aiq_api/src/aiq_api/auth/middleware.py` (TODO: re-verify against v2.0.0)                |
| `aiq-backend` deploy docs                                      | `aiq` repo — `docs/source/deployment/kubernetes.md`, `docs/source/deployment/docker-compose.md`                  |
| `rag-server` / `ingestor-server` route reference               | [`ENTERPRISE_RAG.md`](ENTERPRISE_RAG.md) §3–§4                                                                   |
| Pack-wide auth story (RS256 + JWKS + SSO)                      | `docs/integrations/oci-idcs.md`                                                                                  |
| Swagger UIs (reachable only via port-forward into the cluster) | `aiq-backend` `/docs`, `/openapi.json`; `rag-server` `/v1/docs`, `/v2/docs`; `ingestor-server` `/v1/docs`        |

---

## 10. When to Update This Doc

Manually maintained. No drift-check test against Terraform. Update
whenever you change any of:

- `ai-accelerator-tf/helm.tf` — either `helm_release` block (`rag` or
  `aiq`), especially the chart-specific `set` entries that wire the
  frontend image override (BUG-020 invariant — `frontend.image.*` for
  `rag`, `aiq.apps.frontend.image.*` for `aiq`), the
  `aiq.apps.backend.env.RAG_*` overrides, or the chart URL / version in
  the `chart` argument.
- `ai-accelerator-tf/helm-values/aiq-aira-values.yaml` — any change to
  the `aiq.apps.backend.env` block, the `aiq.apps.frontend.env` block
  (particularly if a future chart version exposes a user-extensible
  `envVars` list — that is a doc-affecting event, because it widens the
  Pattern-2 surface), the bundled `aiq.apps.postgres` sub-chart, the
  `aiq.sharedSecrets` mount config, or the chart's parent name (e.g.,
  if NVIDIA renames `aiq2-web` again in a future major).
- `ai-accelerator-tf/helm-values/enterprise-rag-aiq-values.yaml` — the
  AIQ-specific overrides of the `rag` stack (vector store choice, Oracle
  vs Milvus, NIM selection).
- `ai-accelerator-tf/ingress.tf` — the
  `enterprise_rag_aiq_frontend_ingress` rule (host, path, annotations,
  backend service — currently `aiq-frontend:3000`).
- `ai-accelerator-tf/schemas/frontend_skins.yaml` — the
  `enterprise_rag_aiq` entry (`container_port`, `subdomain`,
  `image_uri`, any new skin keys).
- The upstream `aiq2-web` chart version — new releases occasionally
  rename or relocate the backend Service, restructure the
  `aiq.apps.<component>` sub-chart values, or add new env keys.
  Spot-check the chart's `values.yaml` and `templates/` against the
  tables in §2.1, §3, and §6.2.
- The upstream `aiq` repo — when the `aiq-agent` image is rebuilt
  from a new release, re-read
  `frontends/aiq_api/src/aiq_api/routes/*.py` (or wherever those have
  been relocated in v2.0.0+) to confirm the routes in §3 still match.

### "When in doubt" rule

> Would a skin author need this to wire their frontend to
> `aiq-backend` (and, through it, `rag-server` / `ingestor-server`)?
> If yes, document it here.
