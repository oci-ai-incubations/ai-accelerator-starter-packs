# vss Pack — Backend API Contract

Companion document to `BACKEND_API_CONTRACT.md`. That file is the multi-pack
reference organized around skin-access *mechanisms* (ingress paths vs env
vars). This file is the vss-pack-specific deep dive organized around
*backend services and their API surface* — what a skin author can actually
call.

Scope: `starter_pack_category = "vss"`. For cuopt, see
`BACKEND_API_CONTRACT_CUOPT.md`. For paas_rag / enterprise_rag /
enterprise_rag_aiq, see `BACKEND_API_CONTRACT.md` §3.3–§3.5.

---

## 1. Deployment Group Composition

The vss pack deploys a **Corrino blueprint deployment group**
(`vss-deployment-group`) to OKE, plus three Oracle-added Kubernetes
resources that live outside the Corrino group. The deployment group's
composition varies across the three implemented sizes.

Source of truth: `ai-accelerator-tf/blueprint_files.tf` —
`local._vss_poc_blueprint`, `local._vss_small_blueprint`,
`local._vss_medium_blueprint`.

### Corrino deployment group — service matrix

| Service         | POC | SMALL | MEDIUM | Container image                                                  | Container port(s)                                 |
|-----------------|-----|-------|--------|------------------------------------------------------------------|---------------------------------------------------|
| `vss`           | ✓   | ✓     | ✓      | See "VSS engine image by size" below                             | 8000 (backend API), 9000 (engine built-in UI; internal) |
| `llamastack`    | ✓   | —     | —      | `iad.ocir.io/.../llama-stack-oci:v0.0.3`                         | 8321                                              |
| `nim-llm`       | —   | ✓     | ✓      | `nvcr.io/nim/meta/llama-3.1-8b-instruct:1.13.1`                  | 8000                                              |
| `embedding`     | ✓   | ✓     | ✓      | `nvcr.io/nim/nvidia/llama-3.2-nv-embedqa-1b-v2:1.9.0`           | 8000                                              |
| `rerank`        | ✓   | ✓     | ✓      | `nvcr.io/nim/nvidia/llama-3.2-nv-rerankqa-1b-v2:1.7.0`          | 8000                                              |
| `riva`          | ✓   | —     | ✓      | `nvcr.io/nim/nvidia/parakeet-0-6b-ctc-en-us:2.0.0`              | HTTP 9000, gRPC 50051                             |
| `elasticsearch` | ✓   | ✓     | ✓      | `docker.io/elasticsearch:9.1.2`                                  | 9200 (REST), 9300 (transport)                     |
| `neo4j`         | ✓   | ✓     | ✓      | `docker.io/neo4j:5.26.4`                                         | 7687 (Bolt)                                       |

### VSS engine image by size

| Size   | Image                                                          | GPU count | Worker shape           |
|--------|----------------------------------------------------------------|-----------|------------------------|
| POC    | `iad.ocir.io/.../vss-engine:2.4.0-poc-custom` (Oracle custom) | 1         | `VM.GPU.A10.2`         |
| SMALL  | `nvcr.io/nvidia/blueprint/vss-engine:2.4.0` (NVIDIA stock)    | 2         | `BM.GPU4.8`            |
| MEDIUM | `iad.ocir.io/.../vss-engine:2.4.0-custom` (Oracle custom)     | 2         | `BM.GPU.L40S-NC.4`     |

POC and MEDIUM ship custom engine builds because those sizes route VLM / LLM
calls differently than the stock image expects (see §2).

### Oracle-added Kubernetes resources (outside the Corrino group)

Created directly by Terraform, not by Corrino:

| Resource               | Service name          | Port | Role                                                                       | Source                                       |
|------------------------|-----------------------|------|----------------------------------------------------------------------------|----------------------------------------------|
| `vss-oracle-ux`        | `vss-oracle-ux`       | 80   | User-facing frontend skin (Next.js). One deployment per enabled skin.     | `ai-accelerator-tf/app-vss-oracle-ux.tf`     |
| `vss-download-service` | `vss-download-service`| 8080 | Async OCI Object Storage → FSS downloader.                                 | `ai-accelerator-tf/app-vss-download-service.tf` |
| `vss-postgres`         | `vss-postgres`        | 5432 | Postgres 14 — skin metadata store (consumed via Prisma).                   | `ai-accelerator-tf/vss_postgres_db.tf`       |

Plus shared infrastructure:

- **`vss-fss-pvc`** — 1 TiB nominal (FSS is elastic) `ReadWriteMany` PVC
  backed by OCI File Storage Service. Mounted at `/mnt/fss` inside
  `vss-oracle-ux` and `vss-download-service`. NFS export source is
  restricted to the OKE node subnet CIDR. (`app-vss-fss.tf`.)
- **`vss-db-url`** — Kubernetes Secret carrying `DATABASE_URL` for Prisma.

### Key facts

- **GPU allocation.** VSS engine takes 1 GPU on POC, 2 on SMALL and MEDIUM.
  Supporting NIMs (`embedding`, `rerank`, `riva` where present) each take 1
  GPU. `nim-llm` takes 4 GPUs on SMALL, 3 on MEDIUM. All supporting NIMs
  run under `recipe_use_shared_node_pool = true`.
- **Deployment order (DAG via `depends_on`).**
  `elasticsearch` and (POC only) `llamastack` have no deps; `neo4j` →
  `elasticsearch`; `embedding` → `neo4j`; `rerank` → `embedding`;
  `riva` → `rerank` where present; `nim-llm` → `rerank` where present; the
  `vss` engine depends on every other service in its size's group. The
  Oracle-added `vss-oracle-ux` deployment depends on the `vss` pod being
  ready, enforced by the `null_resource.wait_for_deployment` gate in
  `blueprint-readiness.tf`.
- **VLM / LLM routing differs by size.** On **POC**, both the VLM
  (`VIA_VLM_ENDPOINT`) and LLM (`LLM_BASE_URL`) calls go through
  `llamastack` on to OCI GenAI (`oci/openai.gpt-4o` for the VLM,
  `oci/openai.gpt-5.2` for the LLM). On **SMALL** and **MEDIUM**, the VLM
  runs locally (`cosmos-reason1-7b` — SMALL pulls it from NGC at
  `ngc:nim/nvidia/cosmos-reason1-7b:1.1-fp8-dynamic`; MEDIUM pulls from
  Hugging Face at `git:https://huggingface.co/nvidia/Cosmos-Reason1-7B`)
  and the LLM runs locally on the `nim-llm` service (LLaMA 3.1 8B). This
  difference is why only the stock NVIDIA engine image works for SMALL,
  while POC and MEDIUM both require Oracle custom engine builds.
- **Audio transcription** (Riva ASR) runs on POC and MEDIUM
  (`ENABLE_AUDIO=true`). SMALL disables it (`ENABLE_AUDIO=false`, no
  `riva` deployment).
- **Engine readiness is slow.** The Corrino startup probe on port 8000
  `/health/ready` is `failure_threshold: 360 × period_seconds: 10 ≈ 1
  hour` — skins must tolerate the engine taking tens of minutes to become
  ready after a fresh deploy or rollout.
- **Shared FSS mount.** VSS engine, `vss-oracle-ux`, and
  `vss-download-service` all mount the same FSS volume. The engine mounts
  it at `/mnt/fss` (so it can read files the download service has
  fetched); the skin and download service both expose it as
  `FILE_STORAGE_PATH=/mnt/fss/cache`.
- **Engine model cache** is a separate 1 TiB `vss-ngc-model-cache` PVC
  mounted at `/tmp/via-ngc-model-cache` on the VSS engine pod only.

---

## 2. Backend Service — `vss` (VSS Engine)

Primary backend for every frontend skin. The VSS engine is a FastAPI
server exposing media ingestion, summarization, Q&A, live-stream
management, and alerts on port 8000.

- **In-cluster address:** `http://<vss_backend_service_name>:8000/`. The
  service name is Corrino-generated from the blueprint's canonical name;
  the pack resolves it at apply time via the Corrino workspace API and
  surfaces the resolved URL to skins as `VSS_API_BASE_URL` (see §6).
  Always use the env var — do not hardcode the service name.
- The engine also listens on **port 9000** for its built-in UI, which is
  replaced by the `vss-oracle-ux` skin in the Oracle pack. Skins must not
  call port 9000.
- **Container command:** `bash /opt/scripts/start.sh` (loads secrets from
  `/var/secrets/secrets.json` if present, substitutes LLM / embedding /
  rerank / riva DNS names into config templates, then execs
  `/opt/nvidia/via/start_via.sh`).
- **Image pull:** `ngc-secret` (dockerconfigjson) for the stock NVIDIA
  image on SMALL; POC and MEDIUM pull from Oracle OCIR under ambient OKE
  credentials.
- **Readiness / liveness / startup probes:** all hit port 8000 at
  `/health/ready` or `/health/live`.
- **Authoritative OpenAPI spec:** the engine is a stock FastAPI app
  (`src/vss-engine/src/via_server.py:166`) with no `docs_url` override, so
  Swagger UI is live at `/docs` and the raw schema at `/openapi.json` —
  reach both via the in-cluster address above.
- **Source of truth for the route list:**
  `NVIDIA/video-search-and-summarization` —
  `src/vss-engine/src/via_server.py` (routes use `@self._app.<method>(...)`
  decorators). Canonical detailed spec for `POST /files` lives alongside
  at `POST_FILES_API_SPEC.md` in the VSS repo.

### 2.1 Health & metadata

| Method | Path             | Purpose                                                           |
|--------|------------------|-------------------------------------------------------------------|
| GET    | `/metrics`       | VIA metrics in Prometheus text format.                            |
| GET    | `/health/ready`  | Readiness — target of the Corrino startup and readiness probes.   |
| GET    | `/health/live`   | Liveness — target of the Corrino liveness probe.                  |

### 2.2 Files lifecycle

Media file management. The canonical detailed spec is
`POST_FILES_API_SPEC.md` in the VSS repo; the table below is the contract
("these endpoints exist at these paths") — consult the canonical spec for
request/response schemas, error codes, and field-level validation.

Every endpoint accepts either a binary upload (`file` multipart field)
or a server-side file reference (`filename` pointing at a path already on
the engine pod's filesystem, including the FSS mount at `/mnt/fss`).
Supplying both is a `422`; supplying neither is a `422`.

| Method | Path                            | Purpose                                                                                                                       |
|--------|---------------------------------|-------------------------------------------------------------------------------------------------------------------------------|
| POST   | `/files`                        | Upload a media file. Form fields: `purpose=vision`, `media_type=video\|image`, `file` or `filename`, optional `camera_id`.    |
| GET    | `/files`                        | List uploaded files. Filter with `?purpose=vision`.                                                                           |
| GET    | `/files/{file_id}`              | Get metadata for a specific file.                                                                                             |
| GET    | `/files/{file_id}/content`      | Download the raw bytes.                                                                                                       |
| DELETE | `/files/{file_id}`              | Delete a file and any derived assets.                                                                                         |

**Oracle-specific usage note.** In the `vss-oracle-ux` flow, the skin
typically does *not* stream bytes via `file`. Instead, it asks
`vss-download-service` (§3) to fetch an OCI Object Storage object into
`/mnt/fss/cache/<name>`, then calls `POST /files` with
`filename=/mnt/fss/cache/<name>` — the engine reads the file directly off
its FSS mount, avoiding a round trip through the skin.

### 2.3 Summarization and Q&A

| Method | Path                       | Purpose                                                                                                                          |
|--------|----------------------------|----------------------------------------------------------------------------------------------------------------------------------|
| POST   | `/summarize`               | Run video summarization. Accepts a file id (for stored files) or a live-stream id. Streams partial summaries via Server-Sent Events. |
| POST   | `/chat/completions`        | OpenAI-compatible interactive Q&A over a media file. Accepts the standard `messages` + `model` shape plus media-id binding.      |
| POST   | `/generate_vlm_captions`   | Generate VLM captions only, without the summarization pass that normally follows.                                                |
| POST   | `/recommended_config`      | Return recommended summarization parameters for a given file (chunk length, prompt overrides, etc.).                            |

### 2.4 Live stream management

| Method | Path                            | Purpose                                        |
|--------|---------------------------------|------------------------------------------------|
| POST   | `/live-stream`                  | Register an RTSP/camera live stream.           |
| GET    | `/live-stream`                  | List configured live streams.                  |
| DELETE | `/live-stream/{stream_id}`      | Remove a live stream.                          |

### 2.5 Alerts

Alerts are natural-language triggers tied to a live stream. On match the
engine emits an alert to an internal callback; skins surface alerts by
polling `GET /alerts/recent`.

| Method | Path                        | Purpose                                                                                                                                   |
|--------|-----------------------------|-------------------------------------------------------------------------------------------------------------------------------------------|
| POST   | `/alerts`                   | Add a natural-language alert trigger. Returns `405 Alert functionality not enabled` if the engine was started with alerts disabled.       |
| GET    | `/alerts`                   | List configured alerts.                                                                                                                   |
| DELETE | `/alerts/{alert_id}`        | Delete an alert.                                                                                                                          |
| GET    | `/alerts/recent`            | Fetch recently-generated alerts. Supports `?live_stream_id=` filter.                                                                      |
| POST   | `/reviewAlert`              | Review an external alert. Produces a dense-caption response or a boolean for a caller-supplied prompt / system prompt. Advanced use only. |

The internal callback at `http://127.0.0.1:60000/via-alert-callback` is an
engine-local SSE publisher — **do not** attempt to call it from a skin.
Use `GET /alerts/recent`.

### 2.6 Models discovery

| Method | Path       | Purpose                                                                                               |
|--------|------------|-------------------------------------------------------------------------------------------------------|
| GET    | `/models`  | List available VLM/LLM models with owner and availability info, OpenAI-compatible response shape.     |

### 2.7 API versioning

By default every path above is unprefixed. Setting
`VSS_API_ENABLE_VERSIONING=true` (or `=1`) on the engine container adds a
`/v1` prefix to every route — `/files` becomes `/v1/files`, etc. Source:
`via_server.py:97` — `API_PREFIX = "/v1" if ... else ""`.

The vss pack does **not** set this env var, so skins should call the
unprefixed paths.

---

## 3. Backend Service — `vss-download-service`

Oracle-added service that fetches files from OCI Object Storage and
writes them to the shared FSS cache, letting the VSS engine consume them
by filesystem path. Source:
`ai-accelerator-tf/app-vss-download-service.tf`.

- **In-cluster address:** `http://vss-download-service:8080` (stable;
  hardcoded service name, no Corrino resolution involved).
- **Container image:**
  `iad.ocir.io/iduyx1qnmway/corrino-devops-repository:vss-download-service-prod-0.0.4`.
- **Container command:** image default entrypoint.
- **Environment:** `FILE_STORAGE_PATH=/mnt/fss/cache`,
  `MAX_CONCURRENT_DOWNLOADS=3`, `REGION_NAME` (from `corrino-configmap`),
  `VSS_ORACLE_UX_URL=http://vss-oracle-ux`.
- **Probes:** liveness and readiness both target `GET /health`.
- **Authoritative spec:** this service's source lives in
  [`oci-ai-incubations/vss-oracle-ux`](https://github.com/oci-ai-incubations/vss-oracle-ux)
  (same repo as the skin), not in `ai-accelerator-starter-packs`.

### 3.1 Health

| Method | Path       | Purpose                                        |
|--------|------------|------------------------------------------------|
| GET    | `/health`  | Liveness / readiness — 200 when ready.         |

### 3.2 Download management — **open question**

The remaining endpoints (to enqueue a download from Object Storage, poll
status, list downloads, cancel) are not derivable from this repo. They
live in the `oci-ai-incubations/vss-oracle-ux` source tree.

Until that source is added to the workspace, a skin author needing these
endpoints should either (a) read `/openapi.json` off a live instance, or
(b) inspect the upstream repo directly. This section will be filled in
once verified.

---

## 4. Supporting Services in the Deployment Group

The VSS engine's dependencies. None of these services has a dedicated env
var on the `vss-oracle-ux` skin today, so every entry below is either
**⚠ cluster-DNS-only** or **✗ internal-use only**.

### Tier legend

- **⚠ Cluster-DNS-only.** The Kubernetes Service exists and is resolvable
  from a skin pod via cluster DNS, but the service name is
  Corrino-generated and the skin contract does not guarantee its stability
  across pack versions. Skin code that hardcodes these names will break
  on upgrades. Discover at runtime with
  `kubectl get svc -l corrino-deployment-group=vss-deployment-group`.
- **✗ Internal-use only.** Even though DNS resolves, the service's schema
  and state are owned by the VSS engine. Direct reads race with engine
  writes; direct writes corrupt state. Do not call from a skin.

### 4.1 `llamastack` (POC only) — ⚠ Cluster-DNS-only

Llama Stack built with the OCI GenAI inference adapter. Exposes
OpenAI-compatible API. On POC, the VSS engine routes both its VLM
(`VIA_VLM_ENDPOINT`) and LLM (`LLM_BASE_URL`) calls through this service
on to OCI GenAI.

- **Image:** `iad.ocir.io/iduyx1qnmway/corrino-devops-repository:llama-stack-oci:v0.0.3`.
- **Port:** 8321.
- **Notable endpoints (OpenAI-compatible under `/v1`):** `GET /v1/models`,
  `POST /v1/chat/completions`, `POST /v1/completions`,
  `POST /v1/embeddings`, `POST /v1/responses`, `GET /v1/health`.
- **Upstream:** [Llama Stack](https://llama-stack.readthedocs.io/),
  [OpenAI API reference](https://platform.openai.com/docs/api-reference).

### 4.2 `nim-llm` (SMALL and MEDIUM only) — ⚠ Cluster-DNS-only

NVIDIA NIM hosting LLaMA 3.1 8B Instruct locally on GPU. On SMALL and
MEDIUM the VSS engine calls this via `LLM_HOST:LLM_PORT` (cluster DNS on
port 8000).

- **Image:** `nvcr.io/nim/meta/llama-3.1-8b-instruct:1.13.1`.
- **Port:** 8000. GPU count: 4 (SMALL) or 3 (MEDIUM).
- **Notable endpoints (OpenAI-compatible under `/v1`):** `GET /v1/models`,
  `POST /v1/chat/completions`, `POST /v1/completions`,
  `GET /v1/health/ready`, `GET /v1/health/live`.
- **Upstream:** [NIM large language models](https://docs.nvidia.com/nim/large-language-models/latest/).

### 4.3 `embedding` (all sizes) — ⚠ Cluster-DNS-only

NVIDIA NIM providing embedding generation for the VSS engine's
Context-Aware RAG pipeline. OpenAI-compatible.

- **Image:** `nvcr.io/nim/nvidia/llama-3.2-nv-embedqa-1b-v2:1.9.0`.
- **Port:** 8000. GPU count: 1 (shared node pool).
- **Notable endpoints:** `POST /v1/embeddings`, `GET /v1/models`,
  `GET /v1/health/ready`.
- **Upstream:** [NeMo Retriever text embedding](https://docs.nvidia.com/nim/nemo-retriever/text-embedding/latest/).

### 4.4 `rerank` (all sizes) — ⚠ Cluster-DNS-only

NVIDIA NIM providing re-ranking of retrieval candidates before LLM
ingestion.

- **Image:** `nvcr.io/nim/nvidia/llama-3.2-nv-rerankqa-1b-v2:1.7.0`.
- **Port:** 8000. GPU count: 1 (shared node pool).
- **Notable endpoints:** `POST /v1/ranking`, `GET /v1/models`,
  `GET /v1/health/ready`.
- **Upstream:** [NeMo Retriever text reranking](https://docs.nvidia.com/nim/nemo-retriever/text-reranking/latest/).

### 4.5 `riva` (POC and MEDIUM only) — ⚠ Cluster-DNS-only

NVIDIA Riva ASR NIM. Only deployed when `ENABLE_AUDIO=true`. Speaks both
HTTP (NIM-style `/v1/...`) and gRPC (`RivaSpeechRecognition`).

- **Image:** `nvcr.io/nim/nvidia/parakeet-0-6b-ctc-en-us:2.0.0`.
- **Ports:** HTTP 9000, gRPC 50051.
- **Upstream:** [NVIDIA Riva ASR](https://docs.nvidia.com/deeplearning/riva/user-guide/docs/asr/).

### 4.6 `elasticsearch` (all sizes) — ✗ Internal-use only

Single-node Elasticsearch cluster. VSS owns the schema and uses it for
log and event indexing.

- **Image:** `docker.io/elasticsearch:9.1.2`.
- **Ports:** 9200 (REST), 9300 (transport).
- **Why skins must not call directly:** direct writes corrupt VSS state;
  direct reads race with engine writes. Use the VSS engine's
  `/alerts/recent` and related endpoints instead.

### 4.7 `neo4j` (all sizes) — ✗ Internal-use only

Knowledge-graph backing store for the VSS engine's Context-Aware RAG
pipeline (entities, relationships, temporal reasoning).

- **Image:** `docker.io/neo4j:5.26.4`.
- **Port:** 7687 (Bolt). The Neo4j Browser port 7474 is not exposed in
  this pack.
- **Why skins must not call directly:** same consistency argument as
  Elasticsearch — use the engine's summarization and Q&A endpoints, which
  consult Neo4j internally.

---

## 5. Frontend Skins (Catalog)

The vss pack ships one skin today. Source:
`ai-accelerator-tf/schemas/frontend_skins.yaml`.

| Skin                              | `variable_name`  | `container_port` | `subdomain`     | Image                                                                       |
|-----------------------------------|------------------|------------------|-----------------|-----------------------------------------------------------------------------|
| Oracle Custom — Enhanced search   | `skin_vss_core`  | 3000             | `vss-frontend`  | `iad.ocir.io/.../vss-oracle-ux-dev-0.0.4`                                    |

Ingress host: `https://vss-frontend.<fqdn>`. `<fqdn>` resolves to the
generated `nip.io` domain (default) or the user-supplied FQDN when
`use_custom_dns = true`. The skin's source lives at
[`oci-ai-incubations/vss-oracle-ux`](https://github.com/oci-ai-incubations/vss-oracle-ux).

---

## 6. How a Skin Reaches the Backends

### Pattern 1 — Same-host ingress path routing

**Not used by the vss pack.** The skin's ingress has a single rule
(`/` → `vss-oracle-ux:80`) with no additional path prefixes stitched on.
All backend calls go through Pattern 2.

### Pattern 2 — In-cluster env vars (server-side only)

Injected into every `vss-oracle-ux` container at boot. These URLs are
absolute, HTTP (no TLS), and reachable only from inside the cluster — do
not expose them to the browser.

Source: `ai-accelerator-tf/app-vss-oracle-ux.tf` — `env {}` blocks on
`kubernetes_deployment_v1.vss_oracle_ux_deployment`, the per-skin
`vss-oracle-ux-config` ConfigMap, the shared `corrino-configmap`, and the
`vss-db-url` Kubernetes Secret.

#### From the per-skin `vss-oracle-ux-config` ConfigMap

| Env var                  | Value                                                              | Points to                                                    |
|--------------------------|--------------------------------------------------------------------|--------------------------------------------------------------|
| `VSS_API_BASE_URL`       | `http://<vss_backend_service_name>:8000/` (resolved at apply time) | VSS engine backend API (§2). Trailing slash is intentional.  |
| `FILE_STORAGE_PATH`      | `/mnt/fss/cache`                                                    | Shared FSS cache directory.                                  |
| `DOWNLOAD_SERVICE_URL`   | `http://vss-download-service:8080`                                  | vss-download-service (§3).                                   |
| `VSS_BACKEND_DEPLOYMENT` | `recipe-vss-deployment`                                             | Corrino deployment name — diagnostic use.                    |

#### From the shared `corrino-configmap`

| Env var            | Required? | Purpose                                                 |
|--------------------|-----------|---------------------------------------------------------|
| `REGION_NAME`      | Yes       | OCI region of the deployment.                           |
| `COMPARTMENT_ID`   | Yes       | OCI compartment OCID.                                   |
| `TENANCY_ID`       | Optional  | OCI tenancy OCID. Marked `optional: true` in Terraform. |
| `TENANCY_NAMESPACE`| Optional  | OCI Object Storage tenancy namespace.                   |

#### Literal values on the Deployment

| Env var              | Value                                                  | Purpose                                                        |
|----------------------|--------------------------------------------------------|----------------------------------------------------------------|
| `LOCAL`              | `"false"`                                              | Tells the skin it is running in OKE, not local dev.           |
| `NEXT_DEPLOYMENT_ID` | `sha256(<blueprint JSON + skin configmap data>)`       | Next.js cache buster — changes when the deployed topology or configmap does. |

#### From the `vss-db-url` Kubernetes Secret

| Env var        | Value                                                                                                          |
|----------------|----------------------------------------------------------------------------------------------------------------|
| `DATABASE_URL` | `postgresql://<user>:<password>@vss-postgres:5432/<db_name>?schema=public` — Prisma connection string to `vss-postgres`. |

#### Filesystem mount

| Mount                | Backing                                                                                      |
|----------------------|----------------------------------------------------------------------------------------------|
| `/mnt/fss`           | FSS `vss-fss-pvc` (1 TiB nominal, `ReadWriteMany`). Shared with `vss-download-service`.      |

### Reaching §4 services

Stable, safe-to-hardcode service names (Oracle-owned):

- `vss-oracle-ux` — the skin itself.
- `vss-download-service` — see §3.
- `vss-postgres` — reach only via Prisma / `DATABASE_URL`, not directly.

Corrino-generated service names for the §4 services are **not part of
the skin contract** and may change across pack versions. If you must
call one at runtime, discover the name with:

```bash
kubectl get svc -l corrino-deployment-group=vss-deployment-group
```

---

## 7. Worked Examples

Server-side Node / Next.js context for every example. Pattern 2 is the
only mechanism, so none of these work from the browser.

### 7.1 Register an Object Storage file and summarize it

```js
// Step 1 — the skin has asked vss-download-service to fetch
// 'warehouse.mp4' from an OCI bucket into /mnt/fss/cache.
// (See §3.2 — exact download endpoint pending verification.)

// Step 2 — register the file with the VSS engine by filesystem path.
// No bytes are streamed; the engine reads directly off the FSS mount.
const upload = new FormData();
upload.append('purpose', 'vision');
upload.append('media_type', 'video');
upload.append('filename', `${process.env.FILE_STORAGE_PATH}/warehouse.mp4`);
const { id: fileId } = await fetch(
  `${process.env.VSS_API_BASE_URL}files`,
  { method: 'POST', body: upload }
).then(r => r.json());

// Step 3 — summarize. The engine streams partial summaries via SSE.
const sse = await fetch(`${process.env.VSS_API_BASE_URL}summarize`, {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({ id: fileId, stream: true }),
});
for await (const chunk of sse.body) {
  // process each SSE event
}
```

### 7.2 Interactive Q&A on an uploaded video

```js
const reply = await fetch(`${process.env.VSS_API_BASE_URL}chat/completions`, {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({
    id: fileId,
    messages: [{ role: 'user', content: 'Were any workers without PPE?' }],
  }),
}).then(r => r.json());
```

### 7.3 Register a live-stream alert

Alerts are feature-flagged on the VSS engine. If the engine was started
with alerts disabled, `POST /alerts` returns `405 Alert functionality
not enabled` — handle this case before wiring UI that depends on it. The
specific env var that gates this is not re-verified here; inspect
`via_server.py:/alerts` and the `_vss_*_blueprint`'s `recipe_container_env`
if you need to confirm which sizes have alerts enabled.

```js
// Register the stream.
const { id: streamId } = await fetch(
  `${process.env.VSS_API_BASE_URL}live-stream`,
  {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      liveStreamUrl: 'rtsp://camera/feed1',
      description: 'aisle-4',
    }),
  }
).then(r => r.json());

// Register the alert trigger.
await fetch(`${process.env.VSS_API_BASE_URL}alerts`, {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({
    live_stream_id: streamId,
    name: 'no-ppe',
    events: ['worker not wearing PPE'],
  }),
});

// Poll for fired alerts.
const recent = await fetch(
  `${process.env.VSS_API_BASE_URL}alerts/recent?live_stream_id=${streamId}`
).then(r => r.json());
```

### 7.4 Read a cached file from the FSS mount

```js
import { readFile } from 'node:fs/promises';

const bytes = await readFile(
  `${process.env.FILE_STORAGE_PATH}/warehouse.mp4`
);
```

### 7.5 Database access via Prisma

```js
import { PrismaClient } from '@prisma/client';

// Prisma reads DATABASE_URL from the environment automatically.
const prisma = new PrismaClient();
const scans = await prisma.scan.findMany({ where: { userId } });
```

---

## 8. Source of Truth

| Concern                                                             | File / URL                                                                                                |
|---------------------------------------------------------------------|-----------------------------------------------------------------------------------------------------------|
| Corrino deployment-group definition (POC / SMALL / MEDIUM)          | `ai-accelerator-tf/blueprint_files.tf` — `local._vss_poc_blueprint`, `._vss_small_blueprint`, `._vss_medium_blueprint` |
| Worker shape / GPU pool sizes per deployment size                   | `ai-accelerator-tf/vars.tf` — `local.starter_pack_configs["vss"]`                                         |
| Oracle-added K8s resources (skin, download service, postgres, FSS)  | `app-vss-oracle-ux.tf`, `app-vss-download-service.tf`, `vss_postgres_db.tf`, `app-vss-fss.tf`              |
| Skin catalog                                                        | `ai-accelerator-tf/schemas/frontend_skins.yaml` — `vss:` key                                              |
| VSS backend route implementations                                   | `NVIDIA/video-search-and-summarization` — `src/vss-engine/src/via_server.py`                              |
| VSS `POST /files` canonical spec                                    | `NVIDIA/video-search-and-summarization` — `POST_FILES_API_SPEC.md`                                        |
| VSS blueprint docs                                                  | https://docs.nvidia.com/vss/latest/                                                                       |
| `vss-download-service` source                                       | `oci-ai-incubations/vss-oracle-ux` (subdirectory pending verification — §3.2 open question)                |
| NIM embedding docs                                                  | https://docs.nvidia.com/nim/nemo-retriever/text-embedding/latest/                                         |
| NIM reranking docs                                                  | https://docs.nvidia.com/nim/nemo-retriever/text-reranking/latest/                                         |
| NIM LLM docs                                                        | https://docs.nvidia.com/nim/large-language-models/latest/                                                 |
| Riva ASR docs                                                       | https://docs.nvidia.com/deeplearning/riva/user-guide/docs/asr/                                            |
| Llama Stack docs                                                    | https://llama-stack.readthedocs.io/                                                                       |
| OpenAI API schema                                                   | https://platform.openai.com/docs/api-reference                                                            |
| Corrino manifest templates (ingress / service / deployment shapes)  | `corrino/api/manifests/templates/recipe_{ingress,service,deployment}_template.yaml`                       |

---

## 9. When to Update This Doc

This document is manually maintained. There is no drift-check test
against the Terraform — keeping this accurate is part of any PR that
touches the sources below.

### When to edit

- `ai-accelerator-tf/blueprint_files.tf` — any edit to
  `_vss_poc_blueprint`, `_vss_small_blueprint`, or `_vss_medium_blueprint`
  (service list, images, env vars, probes, ingress ports, `depends_on`).
- `ai-accelerator-tf/app-vss-oracle-ux.tf` — any `env {}` change on the
  skin deployment; any addition or removal in the `vss-oracle-ux-config`
  ConfigMap; any new Secret reference.
- `ai-accelerator-tf/app-vss-download-service.tf` — port, env var, or
  probe changes.
- `ai-accelerator-tf/vss_postgres_db.tf` — changes that affect the
  `DATABASE_URL` shape.
- `ai-accelerator-tf/app-vss-fss.tf` — FSS topology, mount path, or PVC
  size.
- `ai-accelerator-tf/vars.tf` — `local.starter_pack_configs["vss"]`
  worker-shape or GPU-count changes.
- `ai-accelerator-tf/schemas/frontend_skins.yaml` — the `vss:` entry
  (`container_port`, `subdomain`, new skins).
- The upstream VSS engine image tag (`vss-engine:2.4.0`, `:2.4.0-poc-custom`,
  `:2.4.0-custom`) — new releases occasionally add or rename endpoints;
  spot-check `via_server.py` against the §2 tables.
- The `oci-ai-incubations/vss-oracle-ux` repo — `vss-download-service`
  route changes affect §3.

### "When in doubt" rule

> Would a skin author need this to wire their frontend? If yes, document
> it.
