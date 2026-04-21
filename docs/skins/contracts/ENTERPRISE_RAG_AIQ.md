# enterprise_rag_aiq Pack — Backend API Contract

Companion document to [`BACKEND_API_CONTRACT.md`](../BACKEND_API_CONTRACT.md). That file is the multi-pack
reference organized around skin-access *mechanisms* (ingress paths vs env
vars). This file is the enterprise_rag_aiq-pack-specific deep dive
organized around *backend services and their API surface* — what a skin
author can actually call.

Scope: `starter_pack_category = "enterprise_rag_aiq"`. For other packs, see
[`CUOPT.md`](CUOPT.md), [`VSS.md`](VSS.md),
[`PAAS_RAG.md`](PAAS_RAG.md),
[`ENTERPRISE_RAG.md`](ENTERPRISE_RAG.md).

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
2. **`helm_release.aiq`** — the NVIDIA AI-Q Research Assistant (AIRA)
   chart, installed in a separate namespace
   (`local.starter_pack_config.aiq_namespace`, default `aiq`). Supplies
   `aira-backend`, `aira-frontend`, an `instruct-llm` NIM, and Arize
   Phoenix tracing.

Source of truth: `ai-accelerator-tf/helm.tf:581-673` (rag) and
`helm.tf:736-810` (aiq).

| Concern                                  | `rag` release                                                                                            | `aiq-aira` release                                                                                               |
|------------------------------------------|----------------------------------------------------------------------------------------------------------|-------------------------------------------------------------------------------------------------------------------|
| Terraform resource                       | `helm_release.rag` (`helm.tf:581`)                                                                       | `helm_release.aiq` (`helm.tf:736`)                                                                                |
| Release name                             | `rag`                                                                                                     | `aiq-aira`                                                                                                         |
| Namespace                                | `local.starter_pack_config.app_namespace` (default `rag`)                                                 | `local.starter_pack_config.aiq_namespace` (default `aiq`; `helm.tf:738`)                                           |
| Chart                                    | `nvidia-blueprint-rag-v2.3.0.tgz` (`helm.tf:586`)                                                         | `aiq-aira-v1.2.1.tgz` (`helm.tf:741`)                                                                              |
| Chart auth                               | NGC `$oauthtoken` + `NGC_API_KEY` (`helm.tf:588-589`)                                                    | NGC `$oauthtoken` + `NGC_API_KEY` (`helm.tf:743-744`)                                                              |
| Values file                              | `helm-values/enterprise-rag-aiq-values.yaml` (`helm.tf:597`)                                              | `helm-values/aiq-aira-values.yaml` (`helm.tf:750`)                                                                 |
| Release timeout                          | 5400 s (90 min) — NIM pulls (`helm.tf:591`)                                                               | 3600 s (60 min) — instruct-llm NIM pull (`helm.tf:746`)                                                            |
| Gating                                   | `local.deploy_app_rag ? 1 : 0` — both enterprise_rag and enterprise_rag_aiq (`helm.tf:668`)               | `local.deploy_app_rag_aiq ? 1 : 0` — enterprise_rag_aiq only (`helm.tf:800`)                                       |
| Frontend image skin override             | `frontend.image.{repository,tag}` from the selected skin (`helm.tf:647-654`) — **not user-facing here**   | `frontend.image.{repository,tag}` from the selected skin (`helm.tf:790-797`) — **the one that reaches the user**   |
| Backend URL overrides                    | (chart owns its own wiring)                                                                               | `backendEnvVars.{RAG_SERVER_URL, RAG_INGEST_URL, NEMOTRON_BASE_URL}` → cross-namespace FQDNs (`helm.tf:771-783`)   |
| Oracle 26ai credentials                  | **Not injected** (`helm.tf:612-614`, `656-658` gate on `enterprise_rag` only; for AIQ, Milvus is used)    | n/a                                                                                                                |
| NIM LLM image pin                        | `nvcr.io/nim/nvidia/llama-3.3-nemotron-super-49b-v1.5:1.14.0` (`helm.tf:639-646`)                         | n/a (chart ships its own NIM pin)                                                                                  |
| `depends_on` chain                       | ingress-nginx, cert-manager, NGC secret job                                                               | `helm_release.rag`, NIM service-selector patch, AIQ-namespace configure job (`helm.tf:804-809`)                   |

**BUG-020 invariant.** The `skin_enterprise_rag_aiq` ORM dropdown must
override the `frontend.image.*` set entries on **both** releases, even
though only the `aiq-aira` release's frontend is user-facing. The
override on the `rag` release is a harmless no-op here but is kept for
symmetry with `enterprise_rag`, and the pair is locked by
`ai-accelerator-tf/schemas/tests/test_helm_skin_override.py`
(`RELEASES_REQUIRING_SKIN_OVERRIDE = ["rag", "aiq"]`). If you add another
Helm pack in the future, extend that constant.

**Consequences of being Helm-deployed:**

- There is no `blueprint_files.tf` entry for this pack — both charts
  bring their own Services, Deployments, PVCs, ConfigMaps, and internal
  wiring.
- There is no `recipe_additional_ingress_ports` stitching API paths onto
  the frontend's subdomain (see §6.3).
- There is no `recipe_container_env` injection into the frontend
  container at deploy time. The `aiq-aira` chart does **not** publish a
  `frontend.envVars` list at all (see §6.2 — this is the key difference
  from enterprise_rag).
- The Corrino REST API has no record of either release. A skin must
  never attempt to call Corrino.

---

## 2. Deployment Group Composition

The pack creates **two groups of services**. Services in the app
namespace belong to the `rag` release and are identical to what
`enterprise_rag` deploys — see
[`ENTERPRISE_RAG.md`](ENTERPRISE_RAG.md) §2 for the full table. Services
in the AIQ namespace belong to the `aiq-aira` release and are listed
below.

### 2.1 AIQ-namespace services (`helm_release.aiq`)

| K8s Service                   | Container image (default)                                                       | Port                  | GPU | Role                                                                                                 |
|-------------------------------|---------------------------------------------------------------------------------|-----------------------|-----|------------------------------------------------------------------------------------------------------|
| `aiq-aira-aira-frontend`      | Overridden by skin — default `nvcr.io/nvidia/blueprint/aira-frontend:v1.2.0`    | 3000 (NodePort 30080) | —   | User-facing frontend container. **Only service exposed via ingress.** Name confirmed at `ingress.tf:223`. |
| `aiq-aira-aira-backend`       | `nvcr.io/nvidia/blueprint/aira-backend:v1.2.0`                                  | 3838                  | —   | AIRA orchestration FastAPI. Talks to `rag-server`, `ingestor-server`, `nim-llm`, and `instruct-llm`. Image + port verified at `aiq-aira-values.yaml:31-39`; service name inferred from the frontend service's `aiq-aira-aira-*` convention — confirm with `kubectl get svc -n <aiq_namespace>` after deploy. |
| `instruct-llm`                | `nvcr.io/nim/meta/llama-3.1-8b-instruct:latest`                                 | 8000                  | 1   | Lightweight instruction-tuned LLM for intent classification and tool routing. `aiq-aira-values.yaml:56-72` pins the service name explicitly. |
| Phoenix (optional)            | `docker.io/arizephoenix/phoenix:latest`                                         | chart-default         | —   | Arize Phoenix tracing (`phoenix.enabled: true` at `aiq-aira-values.yaml:88`). **Service name and exposed ports come from the upstream sub-chart and are not set in the pack's values file — open question until the chart is rendered.** |

### 2.2 App-namespace services (`helm_release.rag`)

Same chart as the `enterprise_rag` pack — see
[`ENTERPRISE_RAG.md`](ENTERPRISE_RAG.md) §2 for the full service list
— but configured differently by
`ai-accelerator-tf/helm-values/enterprise-rag-aiq-values.yaml`. The
AIQ-specific differences that matter for this contract:

- **`rag-server` image and tag:** `nvcr.io/nvidia/blueprint/rag-server:2.3.0`
  (`enterprise-rag-aiq-values.yaml:35-38`). Port `8081`
  (`values.yaml:41-43`). The `enterprise_rag` pack pins a different
  registry path and tag — this is the AIQ branch's baseline.
- **`ingestor-server` image and tag:** `nvcr.io/nvidia/blueprint/ingestor-server:2.3.0`
  (`enterprise-rag-aiq-values.yaml:238-241`). Port `8082`
  (`values.yaml:244-246`).
- **Vector store is Milvus**, not Oracle 26ai.
  `enterprise-rag-aiq-values.yaml:97-99` sets
  `APP_VECTORSTORE_URL: "http://milvus:19530"` and
  `APP_VECTORSTORE_NAME: "milvus"`;
  `enterprise-rag-aiq-values.yaml:267-268` does the same for the
  ingestor. `helm.tf:612-614` and `656-658` gate the Oracle credential
  injection on `enterprise_rag` only.
- **No Oracle 26ai ADB is provisioned in parallel** for AIQ (Terraform
  module gating).
- **`rag-frontend` is deployed but dormant.** The chart still renders a
  `rag-frontend` Service at port `3000` driven by
  `enterprise-rag-aiq-values.yaml:365-392` (`VITE_API_CHAT_URL`,
  `VITE_API_VDB_URL`, `VITE_MILVUS_URL` env vars baked into the image),
  but **no Ingress routes to it** in this pack. The `rag-frontend`
  envVars are not a contract surface for AIQ skin authors; they govern
  the unused `rag-frontend` only.

### 2.3 Key facts across both releases

- **Only `aiq-aira-aira-frontend` is reachable from outside the
  cluster.** Every other Service (both namespaces) is `ClusterIP` (the
  frontend's NodePort is internal and unused by the Ingress path). The
  `kubernetes_ingress_v1.enterprise_rag_aiq_frontend_ingress` rule
  (`ingress.tf:193-234`) publishes the single path `/` →
  `aiq-aira-aira-frontend:3000` on the pack's public host.
- **Cross-namespace DNS is used by the backend.** The aiq-aira backend
  in the AIQ namespace reaches `rag-server`, `ingestor-server`, and
  `nim-llm` via FQDNs that include the app namespace, injected by
  `helm.tf:771-783`. The defaults in the values file
  (`aiq-aira-values.yaml:50-53`) assume the namespace is `rag`;
  Terraform overrides them at apply time to match
  `local.starter_pack_config.app_namespace`.
- **`nim-llm` runs on a reserved tainted node** (`workload=nim-llm:NoSchedule`,
  applied by `terraform_data.label_nim_llm_node` at `helm.tf:463-505`).
  This applies to the rag stack deployed for the AIQ pack too.
- **`instruct-llm` requires one additional GPU** beyond the rag stack
  (`aiq-aira-values.yaml:64-68`, `nvidia.com/gpu: 1`). Sizing of the
  full rag stack's GPU requirements is documented in
  [`ENTERPRISE_RAG.md`](ENTERPRISE_RAG.md) §2.
- **Tavily search key.** The `aiq-aira` chart mounts
  `tavilyApiSecret.password` (`helm.tf:764-769`) from
  `var.tavily_api_key`; when that var changes, Terraform rolls all
  deployments in the AIQ namespace
  (`terraform_data.aiq_restart_on_tavily_change*`, `helm.tf:815-845`)
  so the backend picks up the new key.

---

## 3. Backend Service — `aira-backend`

The AIRA orchestration layer. Built from the same open-source `aiq` repo
(`NVIDIA-AI-Blueprints/aiq` — `src/aiq_agent/`, `frontends/aiq_api/`;
linked from `docs/skins/README.md` §Enterprise Agentic AI Starter Kit)
and packaged by NVIDIA as the `aira-backend:v1.2.0` container image. A
FastAPI app built on NVIDIA's NeMo Agent Toolkit (NAT).

- **In-cluster address:** `http://aiq-aira-aira-backend.<aiq_namespace>.svc.cluster.local:3838`
  (short name `aiq-aira-aira-backend:3838` from within the AIQ
  namespace). Port verified at `aiq-aira-values.yaml:37-39`; service
  name inferred from the chart's `aiq-aira-aira-*` pattern (the
  frontend's name at `ingress.tf:223` is the anchor — confirm the
  backend service name with `kubectl get svc` after deploy).
- **URL prefix:** no global prefix. Routes sit at `/health`, `/chat`,
  `/v1/...`, `/generate/...`, `/websocket`.
- **Framework:** FastAPI; the app is constructed by the `AIQAPIWorker`
  plugin at `aiq` repo
  `frontends/aiq_api/src/aiq_api/plugin.py:294-309`.
- **Source for route list:** upstream `aiq` repo —
  `frontends/aiq_api/src/aiq_api/routes/{collections,documents,jobs}.py`
  for AIQ-specific routes, plus NAT's `FastApiFrontEndPlugin` for
  `/chat`, `/chat/stream`, `/v1/chat/completions`, `/generate/*`, and
  `/websocket`.
- **OpenAPI / Swagger:** `GET /docs`, `GET /redoc`, `GET /openapi.json`
  (FastAPI auto-generated). These are developer introspection endpoints
  and are reachable only from inside the cluster.
- **Auth, CORS, and bearer-token handling:** not part of this contract.
  See `docs/API_TOKENS.md` for the starter pack's overall
  bearer-token story; the `aiq` repo's
  `frontends/aiq_api/src/aiq_api/auth/middleware.py` owns backend
  middleware behavior.

**Scope caveat.** The `aira-backend:v1.2.0` image is a binary built by
NVIDIA from some snapshot of the `aiq` repo. The route tables below are
drawn from the `aiq` repo's current `main` branch and are the most
concrete reference available to skin authors. They are informational —
the starter pack does not expose `aira-backend` externally, and skin
authors should integrate via the frontend's `/api/*` surface (§6.4),
not by hard-coding backend paths.

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
`docs/API_TOKENS.md` for the starter pack's overall auth story; the
backend-side implementation lives in the `aiq` repo under
`frontends/aiq_api/src/aiq_api/auth/` and `jobs/access.py`.

### 3.3 Knowledge management (AIQ's own wrappers around `ingestor-server`)

These routes are how the upstream `aira-frontend` uploads documents and
lists collections through the `aira-backend`, which in turn talks to
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
- Direct cross-origin browser traffic to `aira-backend:3838`. The
  backend's default CORS policy in the `aiq` repo is locked to
  `http://localhost(:\d+)?|http://127.0.0.1(:\d+)?`
  (`configs/config_web_default_llamaindex.yml:36-47`). The intended
  integration point is a server-side BFF inside the skin container
  (§6).

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
in the shipped `aira-backend:v1.2.0` image depending on how it's
configured; verify with the deployed build.

---

## 4. Backend Services — `rag-server` and `ingestor-server`

The AIQ pack also deploys the full RAG Blueprint stack in the app
namespace. From a skin author's perspective these services are
**transitive dependencies of `aira-backend`**, not a primary contract
surface:

- The `aira-backend` reaches `rag-server` via `RAG_SERVER_URL` and
  `ingestor-server` via `RAG_INGEST_URL` (both overridden by
  `helm.tf:771-783` to cross-namespace FQDNs on ports 8081 and 8082).
- The `aira-frontend` never reaches `rag-server` or `ingestor-server`
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
`ingestor-server` (for instance to bypass `aira-backend`'s orchestration
and query Milvus directly), the skin must do the same in-container proxy
work described in §6 — and must cross the namespace boundary, since the
RAG services live in `<app_namespace>` (default `rag`) while the skin
runs in `<aiq_namespace>` (default `aiq`). Use the FQDNs
`rag-server.<app_namespace>.svc.cluster.local:8081` and
`ingestor-server.<app_namespace>.svc.cluster.local:8082`.

---

## 5. Frontend Skins (Catalog)

enterprise_rag_aiq ships one skin. The `skin_enterprise_rag_aiq` ORM
variable is an enum dropdown; its sole option today is the NVIDIA AIRA
Core App skin. Source:
`ai-accelerator-tf/schemas/frontend_skins.yaml:53-60`.

| Skin     | Enum variable              | `container_port` | `subdomain` | Default image                                              |
|----------|----------------------------|------------------|-------------|------------------------------------------------------------|
| Core App | `skin_enterprise_rag_aiq`  | 3000             | `aiq`       | `nvcr.io/nvidia/blueprint/aira-frontend:v1.2.0`            |

Ingress host: `https://aiq.<fqdn>`. `<fqdn>` resolves to the generated
`nip.io` domain (default) or a user-supplied FQDN if
`use_custom_dns = true`. The resolved host is
`local.public_endpoint.starter_pack` as referenced by
`ingress.tf:212,216`.

**Skin image override.** The selected skin's `image_uri` is split on
`:` and fed into **both** Helm releases'
`frontend.image.{repository,tag}` set blocks — `rag` (`helm.tf:647-654`)
and `aiq-aira` (`helm.tf:790-797`). Only the `aiq-aira` override is
user-facing; the `rag` override is kept in lockstep for symmetry with
`enterprise_rag` and is locked together with the AIQ override by
`test_helm_skin_override.py`.

---

## 6. How a Skin Reaches the Backends

> **Critically different from both cuopt and enterprise_rag.** Like
> `enterprise_rag`, AIQ does not stitch API paths onto the frontend
> subdomain — the only ingress rule is `/` →
> `aiq-aira-aira-frontend:3000`. **Unlike `enterprise_rag`**, the
> `aiq-aira` chart does **not** publish a `frontend.envVars` list, so
> there are no `VITE_API_*` env vars baked into the frontend container.
> The pack offers zero external mechanism for reaching the backends;
> everything is chart-internal.

### 6.1 Ingress — what is and isn't published

Source: `ai-accelerator-tf/ingress.tf:193-234`.

| Ingress resource                             | Host                                       | Path rules   | Backend                         | TLS                                  |
|----------------------------------------------|--------------------------------------------|--------------|---------------------------------|--------------------------------------|
| `enterprise_rag_aiq_frontend_ingress`        | `local.public_endpoint.starter_pack` (`aiq.<fqdn>`) | `/` (Prefix) | `aiq-aira-aira-frontend:3000`   | `letsencrypt-prod` (cert-manager)    |

Relevant nginx annotations (`ingress.tf:200-207`):

- `nginx.ingress.kubernetes.io/proxy-body-size: 2g` — multi-megabyte
  document uploads work through the frontend ingress.
- `nginx.ingress.kubernetes.io/proxy-{read,send,connect}-timeout: 600` —
  10-minute timeouts for long-running deep-research jobs and streaming
  chat responses.
- `nginx.ingress.kubernetes.io/rewrite-target: /` — no-op here since
  only `/` is published.

No auth annotation. `aira-backend:3838`, `rag-server:8081`,
`ingestor-server:8082`, `nim-llm:8000`, `instruct-llm:8000`, Milvus,
MinIO, NIMs — none of these have ingress rules. They are not reachable
from the browser.

### 6.2 Pattern 2 — Not available

Unlike `enterprise_rag`, the `aiq-aira` chart's `frontend:` block
(`helm-values/aiq-aira-values.yaml:73-85`) deliberately omits an
`envVars` list. The backend env vars in `backendEnvVars`
(`aiq-aira-values.yaml:41-53`, overridden by `helm.tf:771-783`) —
`INSTRUCT_BASE_URL`, `INSTRUCT_API_KEY`, `INSTRUCT_MODEL_NAME`,
`INSTRUCT_MODEL_TEMP`, `INSTRUCT_MAX_TOKENS`, `NEMOTRON_BASE_URL`,
`NEMOTRON_MODEL_NAME`, `NEMOTRON_MODEL_TEMP`, `NEMOTRON_MAX_TOKENS`,
`AIRA_APPLY_GUARDRAIL`, `RAG_SERVER_URL`, `RAG_INGEST_URL` — are
injected into the **backend** pod, not the frontend.

**The practical consequence:** a replacement skin container gets **no
backend URLs from the chart**. If the skin's code wants to reach
`aira-backend`, `rag-server`, or `ingestor-server`, the skin is
responsible for either (a) hard-coding the cluster DNS names, (b)
templating a `config.js` from a pod-level `downward API` mount, or (c)
reading them from its own chart values that a maintainer remembers to
set. There is no Pattern-2 contract from the pack.

### 6.3 Pattern 1 — Not available

There is no `recipe_additional_ingress_ports` equivalent for Helm packs.
To expose backend paths on the frontend subdomain you would need to
either (a) add a second ingress resource in `ingress.tf` that routes
paths like `/api/chat/*` to `aira-backend:3838/*` with the appropriate
rewrite, or (b) have the skin container itself proxy those paths
internally. Option (b) is the path a skin author can take without
editing the starter pack — see §7.2.

### 6.4 What a drop-in skin must mirror

The upstream `aira-frontend:v1.2.0` image is built from the `aiq` repo's
`frontends/ui/` (Next.js 16; see `docs/skins/README.md` §Enterprise
Agentic AI Starter Kit). It acts as a same-origin BFF: the browser
calls `/api/*` paths, each Next.js handler reads a server-side
`BACKEND_URL` env var and forwards to the corresponding `aira-backend`
route; WebSocket upgrades on `/websocket` are proxied to
`aira-backend:3838/websocket`. The `aiq-aira` chart does **not**
publish `BACKEND_URL` via `frontend.envVars` — it is chart-internal to
the shipped image.

A drop-in skin has two supported integration paths:

1. **Same-shape replacement.** Ship a frontend that speaks the same
   relative `/api/*` paths as the upstream `aira-frontend`
   (`/api/chat`, `/api/generate[/respond]`, `/api/jobs/async/[...]`,
   `/api/v1/[...]`, `/api/health`, `/api/auth/[...nextauth]`,
   `/api/generate-pdf`, plus a same-origin `ws://.../websocket`
   upgrade). Internally the skin container runs its own BFF (Node,
   Go, nginx, …) that forwards those paths to `aira-backend:3838`.
   This is the low-friction path.
2. **Chart modification.** Fork `aiq-aira` (or propose an upstream PR)
   to add a `frontend.envVars` list so the skin can read backend URLs
   at runtime the way `enterprise_rag` skins read `VITE_API_CHAT_URL`.
   Higher friction; warranted only when (1) isn't sufficient.

### 6.5 What your skin container must do

Summary of the skin contract:

1. Listen on port **3000** (from the catalog `container_port`). Your
   container receives plain HTTP from nginx-ingress; TLS is terminated
   upstream.
2. Publish the UI on any paths you like — everything under
   `aiq.<fqdn>/` routes to your container.
3. Implement a server-side relay (SSR, API routes, or an in-container
   reverse proxy) for every backend call the browser makes, because
   `aira-backend`'s CORS locks out cross-origin browser traffic and the
   Ingress does not route any backend paths directly.
4. Do **not** rely on environment variables from the chart to locate
   `aira-backend`. The chart does not inject any. Your skin's image or
   your own custom Helm values are responsible for knowing where
   `aira-backend` lives (default cluster DNS:
   `aiq-aira-aira-backend.<aiq_namespace>.svc.cluster.local:3838`;
   short name within the AIQ namespace:
   `aiq-aira-aira-backend:3838`).

---

## 7. Worked Examples

### 7.1 Browser — streaming chat through a same-origin server route

Assumes the skin runs a Node BFF with an `/api/chat` route that proxies
to `aira-backend`. Identical to the upstream `aira-frontend`'s own
wiring.

```js
// Browser-side chat with SSE streaming.
async function streamChat(messages, onDelta) {
  const resp = await fetch('/api/chat', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      messages,
      // aira-backend decides RAG / search / no-KB routing from the
      // configured workflow; the frontend passes the user prompt and
      // whatever UX toggles it exposes.
    }),
  });
  if (!resp.ok) throw new Error(`aira-backend ${resp.status}`);

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
SSR layer. Browser calls `/api/*`; nginx forwards in-cluster. Note the
hard-coded hostname — the `aiq-aira` chart does not inject a backend
URL, so the skin owns this value.

```nginx
server {
  listen 3000;

  # Static bundle for the SPA.
  root /usr/share/nginx/html;
  try_files $uri /index.html;

  # All aira-backend routes under /api/*.
  location /api/ {
    proxy_pass         http://aiq-aira-aira-backend:3838/;
    proxy_http_version 1.1;
    proxy_set_header   Host $host;
    proxy_set_header   Connection '';
    proxy_buffering    off;                         # critical for SSE
    proxy_read_timeout 600s;
    client_max_body_size 2g;                        # matches ingress annotation
  }

  # WebSocket passthrough for agent / HITL sessions.
  location /websocket {
    proxy_pass         http://aiq-aira-aira-backend:3838/websocket;
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
// aira-backend → ingestor-server:8082 handles the real work.
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
| `aira-backend` direct HTTP access from the browser                        | CORS is locked to `localhost`/`127.0.0.1`; the intended consumer is a BFF inside the skin container.                      |
| `aira-backend` route list (`§3`) as a stable contract                     | The route list is documented from the upstream `aiq` repo; NVIDIA's `aira-backend:v1.2.0` image may add or rename routes between releases. Use the frontend's `/api/*` shape as the stable integration point. |
| `rag-frontend` from the `rag` release                                     | Deployed but intentionally **not user-facing** for this pack; no ingress routes to it. The `frontend.image.*` override on `rag` is a BUG-020 lockstep no-op.          |
| `rag-server:8081`, `ingestor-server:8082`                                 | Transitive backend for `aira-backend`; reach them through `/api/v1/collections/...`, `/api/v1/documents/...`, or the agent endpoints, not directly. |
| `nim-llm:8000`, `instruct-llm:8000`, `nemoretriever-embedding-ms:8000`, `nemoretriever-ranking-ms:8000`, `nim-vlm:8000` | NIM microservices called by `aira-backend` / `rag-server`. Talking to them directly bypasses orchestration, guardrails, and metrics. |
| `rag-nv-ingest:7670` (and related nv-ingest sub-services)                 | Ray extraction pipeline (`enterprise-rag-aiq-values.yaml:290-291`). `ingestor-server` is the abstraction layer.             |
| `milvus:19530`, `milvus:9091`                                             | Vector-store wire protocol. AIQ uses Milvus (`enterprise-rag-aiq-values.yaml:97-99, 267-268`); reach it via the ingestor. |
| `rag-minio:9000`                                                          | S3-compatible blob store for multimodal content (`enterprise-rag-aiq-values.yaml:91, 275, 698`).                            |
| `rag-redis-master:6379`                                                   | Task queue. Poll via the ingestor's `/v1/status`, not Redis directly (`enterprise-rag-aiq-values.yaml:331-332, 695-696`).   |
| `nemo-guardrails:7331` (when enabled)                                      | Optional content-safety filter (`enterprise-rag-aiq-values.yaml:173, 213`).                                                |
| Arize Phoenix tracing (collector + UI)                                     | Operator-facing; not a skin contract. Service names and ports are owned by the upstream Phoenix sub-chart and are not set in `aiq-aira-values.yaml`. |
| Any database backing `aira-backend` (job store, ownership tables, etc.)    | **Open question for this pack.** `aiq-aira-values.yaml` does not configure a database or reference one via env vars; whether the shipped image uses SQLite, a chart-internal sub-chart, or an in-memory store is not visible from the starter-pack sources. Skin authors must not assume any particular store. |
| Corrino REST API (`/deployment/`, `/deploy/`, `/validate/`, `/workspace/`) | Control-plane API for recipe-based packs. Not involved here.                                                              |
| `corrino-configmap` values (`REGION_NAME`, `COMPARTMENT_ID`, …)            | Exist in the cluster for recipe-based packs. The `aiq-aira` chart does not mount them.                                    |
| OpenTelemetry / Prometheus / Grafana / Zipkin                              | Observability infrastructure. Phoenix is enabled by default; the rest are operator-level.                                  |
| `aira-backend /docs`, `/redoc`, `/openapi.json`, `/metrics`                | Developer / scrape targets, reachable only inside the cluster.                                                             |

If a skin finds itself needing one of these, the right move is to file
a chart issue upstream (NVIDIA `aiq-aira`) or extend `aira-backend` —
not to call the internal service directly.

---

## 9. Source of Truth

| Concern                                                        | File / URL                                                                                                       |
|----------------------------------------------------------------|------------------------------------------------------------------------------------------------------------------|
| Terraform helm_release for the `rag` chart                     | `ai-accelerator-tf/helm.tf:581-673`                                                                              |
| Values file selector for the `rag` release (enterprise_rag_aiq branch) | `ai-accelerator-tf/helm.tf:594-599` (`file("helm-values/enterprise-rag-aiq-values.yaml")`)              |
| Terraform helm_release for the `aiq-aira` chart                | `ai-accelerator-tf/helm.tf:736-810`                                                                              |
| Cross-namespace backend URL overrides                          | `ai-accelerator-tf/helm.tf:771-783`                                                                              |
| Frontend image skin override (both releases, BUG-020)          | `ai-accelerator-tf/helm.tf:647-654` (rag), `helm.tf:790-797` (aiq-aira)                                          |
| Tavily secret wiring                                           | `ai-accelerator-tf/helm.tf:764-769`, `815-845`                                                                   |
| AIQ namespace creation                                         | `ai-accelerator-tf/helm.tf:453-456`                                                                              |
| `rag` release values (AIQ-specific overrides — Milvus, no Oracle) | `ai-accelerator-tf/helm-values/enterprise-rag-aiq-values.yaml`                                              |
| `aiq-aira` release values (full chart config)                  | `ai-accelerator-tf/helm-values/aiq-aira-values.yaml`                                                             |
| — `backendEnvVars` (RAG + Nemotron + Instruct URLs)            | `helm-values/aiq-aira-values.yaml:41-53`                                                                         |
| — `nim-llm` (instruct-llm) sub-chart config                    | `helm-values/aiq-aira-values.yaml:56-71`                                                                         |
| — `frontend` block (no `envVars`)                              | `helm-values/aiq-aira-values.yaml:73-85`                                                                         |
| — `phoenix` tracing sub-chart                                  | `helm-values/aiq-aira-values.yaml:87-100`                                                                        |
| Frontend ingress rule                                          | `ai-accelerator-tf/ingress.tf:193-234`                                                                           |
| Skin catalog entry                                             | `ai-accelerator-tf/schemas/frontend_skins.yaml:53-60`                                                            |
| Skin-override invariant test                                   | `ai-accelerator-tf/schemas/tests/test_helm_skin_override.py`                                                     |
| Upstream `rag` chart (NGC)                                     | https://helm.ngc.nvidia.com/nvidia/blueprint/charts/nvidia-blueprint-rag-v2.3.0.tgz                              |
| Upstream `aiq-aira` chart (NGC)                                | https://helm.ngc.nvidia.com/nvidia/blueprint/charts/aiq-aira-v1.2.1.tgz                                          |
| `aira-backend` upstream repo (backend image source)            | `NVIDIA-AI-Blueprints/aiq` — linked from `docs/skins/README.md` §Enterprise Agentic AI Starter Kit               |
| `aira-backend` FastAPI app construction                        | `aiq` repo — `frontends/aiq_api/src/aiq_api/plugin.py:294-309`                                                   |
| `aira-backend` AIQ-specific route definitions                  | `aiq` repo — `frontends/aiq_api/src/aiq_api/routes/{collections,documents,jobs}.py`                              |
| `aira-backend` NAT-provided routes (`/chat`, `/v1/chat/completions`, `/generate/*`, `/websocket`) | NAT's `FastApiFrontEndPlugin`; entry-point confirmed via `aiq` repo `frontends/ui/server.js:146-197` and `frontends/ui/src/app/api/{chat,generate}/route.ts` |
| `aira-backend` external path allowlist                         | `aiq` repo — `frontends/aiq_api/src/aiq_api/auth/middleware.py:108-120` (`EXTERNAL_ALLOWED_PATHS`, `AUTH_EXEMPT_PATHS`) |
| `aira-backend` deploy docs                                     | `aiq` repo — `docs/source/deployment/kubernetes.md`, `docs/source/deployment/docker-compose.md`                  |
| `rag-server` / `ingestor-server` route reference               | [`ENTERPRISE_RAG.md`](ENTERPRISE_RAG.md) §3–§4                                                                   |
| Bearer-token auth story across the pack                        | `docs/API_TOKENS.md`                                                                                              |
| Swagger UIs (reachable only via port-forward into the cluster) | `aira-backend` `/docs`, `/openapi.json`; `rag-server` `/v1/docs`, `/v2/docs`; `ingestor-server` `/v1/docs`       |

---

## 10. When to Update This Doc

Manually maintained. No drift-check test against Terraform. Update
whenever you change any of:

- `ai-accelerator-tf/helm.tf` — either `helm_release` block (`rag` or
  `aiq`), especially the `set` entries for `frontend.image.*` (BUG-020
  invariant), the `backendEnvVars.*` overrides, or the chart URL /
  version in the `chart` argument.
- `ai-accelerator-tf/helm-values/aiq-aira-values.yaml` — any change to
  `backendEnvVars`, the `frontend:` block (particularly if a future
  chart version adds a `frontend.envVars` list — that is a doc-affecting
  event, because it changes whether Pattern 2 is available), or the
  `nim-llm` / `phoenix` sub-chart defaults.
- `ai-accelerator-tf/helm-values/enterprise-rag-aiq-values.yaml` — the
  AIQ-specific overrides of the `rag` stack (vector store choice, Oracle
  vs Milvus, NIM selection).
- `ai-accelerator-tf/ingress.tf` — the
  `enterprise_rag_aiq_frontend_ingress` rule (host, path, annotations,
  backend service).
- `ai-accelerator-tf/schemas/frontend_skins.yaml` — the
  `enterprise_rag_aiq` entry (`container_port`, `subdomain`,
  `image_uri`, any new skin keys).
- The upstream `aiq-aira` chart version — new releases occasionally
  rename the backend Service, add `frontend.envVars`, or restructure
  the `backendEnvVars` list. Spot-check the chart's `values.yaml` and
  `templates/` against the tables in §2.1, §3, and §6.2.
- The upstream `aiq` repo — when the `aira-backend` image is rebuilt
  from a new release, re-read
  `frontends/aiq_api/src/aiq_api/routes/*.py` to confirm the routes in
  §3 still match.

### "When in doubt" rule

> Would a skin author need this to wire their frontend to
> `aira-backend` (and, through it, `rag-server` / `ingestor-server`)?
> If yes, document it here.
