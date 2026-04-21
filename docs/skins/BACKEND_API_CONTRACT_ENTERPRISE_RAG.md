# enterprise_rag Pack — Backend API Contract

Companion document to `BACKEND_API_CONTRACT.md`. That file is the multi-pack
reference organized around skin-access *mechanisms* (ingress paths vs env
vars). This file is the enterprise_rag-pack-specific deep dive organized
around *backend services and their API surface* — what a skin author can
actually call.

Scope: `starter_pack_category = "enterprise_rag"`. For cuopt see
`BACKEND_API_CONTRACT_CUOPT.md`; for vss / paas_rag / enterprise_rag_aiq
see `BACKEND_API_CONTRACT.md` §3.2, §3.3, §3.5.

---

## 1. Deployment Mechanism — Helm, Not Corrino

**The single most important fact about this pack:** enterprise_rag does
*not* deploy through Corrino recipes. It is installed as a Helm release
of the NVIDIA RAG Blueprint chart, pulled from NGC at Terraform apply
time.

Source of truth: `ai-accelerator-tf/helm.tf:581-673`.

| Concern                     | Value                                                                                                                             |
|-----------------------------|-----------------------------------------------------------------------------------------------------------------------------------|
| Terraform resource          | `helm_release.rag` (`helm.tf:581`)                                                                                                |
| Chart                       | `https://helm.ngc.nvidia.com/nvidia/blueprint/charts/nvidia-blueprint-rag-v2.3.0.tgz` (`helm.tf:586`)                             |
| Chart auth                  | NGC `$oauthtoken` + `NGC_API_KEY` from the `ngc-api-secret` Kubernetes Secret (`helm.tf:588-589`)                                 |
| Values file                 | `ai-accelerator-tf/helm-values/enterprise-rag-values.yaml` (selected at `helm.tf:594-599`)                                        |
| Release timeout             | 5400 s (90 min) — NIM pods take a long time to pull and initialize (`helm.tf:591`)                                                |
| Namespace                   | `local.starter_pack_config.app_namespace` — created by `kubernetes_namespace_v1.app_namespace` (`helm.tf:443-448`)                |
| Gating                      | `count = local.deploy_app_rag ? 1 : 0` — requires `starter_pack_category ∈ {"enterprise_rag", "enterprise_rag_aiq"}` (`helm.tf:668`) |
| Frontend image override     | `frontend.image.{repository,tag}` split from the selected skin's `image_uri` (`helm.tf:647-654`)                                  |
| Oracle 26ai credentials     | `envVars.ORACLE_{USER,PASSWORD,CS}` and `ingestor-server.envVars.ORACLE_*` — enterprise_rag only (`helm.tf:612-630, 656-666`)     |
| NIM LLM image pin           | `nvcr.io/nim/nvidia/llama-3.3-nemotron-super-49b-v1.5:1.14.0` (`helm.tf:639-646`)                                                 |

**Consequences of being Helm-deployed, not recipe-deployed:**

- There is no `blueprint_files.tf` entry for this pack's backends. The
  chart brings its own Services, Deployments, PVCs, ConfigMaps, and
  internal wiring.
- There is no `recipe_additional_ingress_ports` stitching API paths onto
  the frontend's subdomain. The starter pack cannot add or remove paths
  without editing either the chart or the starter pack's `ingress.tf`.
- There is no `recipe_container_env` injection into the frontend at
  Terraform apply time. Frontend env vars come from the chart's
  `frontend.envVars` block (see §6.2).
- Corrino's REST API (`/deployment/`, `/deploy/`, `/validate/`,
  `/workspace/`, …) has no record of the RAG workload. A skin must
  never attempt to call Corrino.

**Version note.** The chart tarball is pinned to `nvidia-blueprint-rag-v2.3.0`.
The `rag-server` and `ingestor-server` container images are Oracle
custom builds (`ord.ocir.io/.../nvidia-rag-retrieval-oci:v0.0.5` and
`.../nvidia-rag-ingestion-oci:v0.0.3`; see `enterprise-rag-values.yaml`
lines 37–40 and 235–238) whose source is the `nvidia-rag-oci` repo at
`VERSION = v0.0.5`. The endpoint tables in §3 and §4 reflect that code.

---

## 2. Deployment Group Composition

What the `rag` Helm release creates on the cluster for this pack. Names
are the in-cluster Kubernetes DNS names (ClusterIP, same namespace as
the release unless noted). The image column shows the **defaults that
`enterprise-rag-values.yaml` sets** for this pack, which often override
the upstream chart.

### 2.1 Backend services (always deployed)

| K8s Service                         | Default image (this pack)                                                                              | Port  | GPU   | Role                                                                                         |
|-------------------------------------|--------------------------------------------------------------------------------------------------------|-------|-------|----------------------------------------------------------------------------------------------|
| `rag-frontend`                      | overridden by skin — default `iad.ocir.io/iduyx1qnmway/enterprise-rag-frontend:v0.0.2`                 | 3000  | —     | User-facing Vite SPA container. **The only service exposed via ingress.** `ClusterIP` (starter pack overrides upstream `NodePort` default). |
| `rag-server`                        | `ord.ocir.io/iduyx1qnmway/corrino-devops-repository/nvidia-rag-retrieval-oci:v0.0.5`                   | 8081  | —     | Main chat / search / summary FastAPI. Orchestrates NIMs, reflection, guardrails, citations. |
| `ingestor-server`                   | `ord.ocir.io/iduyx1qnmway/corrino-devops-repository/nvidia-rag-ingestion-oci:v0.0.3`                   | 8082  | —     | Document ingestion FastAPI. Fronts NV-Ingest + the vector store for writes and collection CRUD. |
| `nim-llm`                           | `nvcr.io/nim/nvidia/llama-3.3-nemotron-super-49b-v1.5:1.14.0`                                          | 8000  | 8     | Nemotron LLM. Tainted node (`workload=nim-llm:NoSchedule`) — see `nim-llm.nodeSelector` / `tolerations`. |
| `nemoretriever-embedding-ms`        | `nvcr.io/nim/nvidia/llama-3.2-nv-embedqa-1b-v2:1.10.1`                                                 | 8000  | 1     | Text + multimodal embeddings.                                                                |
| `nemoretriever-ranking-ms`          | `nvcr.io/nim/nvidia/llama-3.2-nv-rerankqa-1b-v2:1.8.0`                                                 | 8000  | 1     | Reranker. `ENABLE_RERANKER=True` (rag-server envVars line 141).                             |
| `rag-nv-ingest`                     | `nvcr.io/nvidia/nemo-microservices/nv-ingest:26.1.2`                                                   | 7670 / 7671 / 8265 | 0     | Ray-based extraction orchestrator. Ports: 7670 HTTP, 7671 broker, 8265 Ray dashboard. All internal. |
| `rag-redis-master`                  | `redis:8.2.1`                                                                                          | 6379  | —     | Task queue used by ingestor-server for async ingestion (`APP_NVINGEST_MESSAGECLIENTHOSTNAME=rag-nv-ingest`, `REDIS_HOST=rag-redis-master`). |
| `nv-ingest-ocr` (PaddleOCR)         | `nvcr.io/nim/baidu/paddleocr:1.5.0`                                                                    | 8000 / 8001 | 1     | NV-Ingest sub-NIM. Default OCR for this pack.                                                |
| `nemoretriever-page-elements-v2`    | `nvcr.io/nim/nvidia/nemoretriever-page-elements-v2:1.5.0`                                              | 8000 / 8001 | 1     | YOLOX page element detection.                                                                |
| `nemoretriever-graphic-elements-v1` | `nvcr.io/nim/nvidia/nemoretriever-graphic-elements-v1:1.5.0`                                           | 8000 / 8001 | 1     | YOLOX graphic element detection.                                                             |
| `nemoretriever-table-structure-v1`  | `nvcr.io/nim/nvidia/nemoretriever-table-structure-v1:1.5.0`                                            | 8000 / 8001 | 1     | Table structure recognition.                                                                 |

Source for service names, images, and GPU counts:
`ai-accelerator-tf/helm-values/enterprise-rag-values.yaml:551-928`.

### 2.2 Vector store

enterprise_rag does **not** use the chart's Milvus. The starter pack's
Zilliztech-based `helm_release "milvus"` (`helm.tf:385-441`) is gated on
`deploy_app_vss` — it runs for the `vss` pack only, not for
`enterprise_rag`. Inside this chart, `nv-ingest.milvusDeployed: False`
(`enterprise-rag-values.yaml:666`) likewise disables the sub-chart's
Milvus.

| Dependency         | Source                                                                                       | Purpose for this pack                                                        |
|--------------------|----------------------------------------------------------------------------------------------|------------------------------------------------------------------------------|
| Oracle 26ai ADB    | `oci_database_autonomous_database.oracle_26ai` (`ai-accelerator-tf/26ai.tf`)                 | Active vector store. Terraform injects `ORACLE_{USER,PASSWORD,CS}` into `rag-server` and `ingestor-server` envVars (`helm.tf:612-630, 656-666`). `APP_VECTORSTORE_NAME: "oracle"` (values `:99, :267`). |

### 2.3 Not deployed in this pack

Explicit absences — calling code that assumes these exist will fail:

| Thing                                                         | Why it's not deployed                                                                                             |
|---------------------------------------------------------------|-------------------------------------------------------------------------------------------------------------------|
| Milvus (`milvus:19530`)                                       | The chart's `nv-ingest.milvusDeployed: False` (`values:666`). The starter pack's separate `helm_release "milvus"` is VSS-only (`helm.tf:439`). |
| MinIO                                                         | `ENABLE_MINIO: "false"` on both rag-server (`values:94`) and ingestor-server (`values:274`). Multimodal storage flows through Oracle instead. |
| `nim-vlm` (vision-language model)                             | `nim-vlm.enabled: false` (`values:647`); `ENABLE_VLM_INFERENCE: "false"` in rag-server envVars (`values:146`).    |
| `nemoretriever-vlm-embedding-ms` (VLM embedding)              | `nvidia-nim-llama-32-nemoretriever-1b-vlm-embed-v1.enabled: false` (`values:613`).                                |
| Elasticsearch                                                 | `eck-elasticsearch.enabled: false` (upstream) / `elasticsearch.enabled: false` (starter-pack values `:397`). Oracle replaces it. |
| `opentelemetry-collector`, `zipkin`, `kube-prometheus-stack`  | All `enabled: false` in chart values. Tracing is off.                                                             |
| `nemo-guardrails-microservice`                                | `ENABLE_GUARDRAILS: "False"` (`values:168`). The rag-server env still carries `NEMO_GUARDRAILS_URL: "nemo-guardrails:7331"` (`values:207`), but no deployment serves it — a request with `enable_guardrails=true` will fail at runtime. |
| `nv-ingest-ocr` (NeMo Retriever OCR)                          | `nv-ingest.nemoretriever-ocr.deployed: false` (`values:789`). Paddle OCR is used instead.                         |
| `nim-vlm-text-extraction` (NeMo Retriever Parse)              | `nv-ingest.nim-vlm-text-extraction.deployed: false` (`values:925`).                                               |

---

## 3. Backend Service — `rag-server`

Main RAG API: chat, search, document summary, and an OpenAI-shaped
vector-store search. FastAPI, served by uvicorn under gunicorn with
`server.workers: 8` (`values:74`).

- **In-cluster base URL:** `http://rag-server:8081/v1` (ClusterIP).
- **Path scheme.** Every endpoint in §3.1–§3.3 is registered both at
  the bare path (e.g. `/generate`) and under `/v1/` (e.g. `/v1/generate`)
  via `v1_router.add_api_route(...)` plus `app.include_router(v1_router)`
  at the end of `src/nvidia_rag/rag_server/server.py`. The chart's
  `frontend.envVars` hardcodes the `/v1` form, so the tables below use
  that prefix.
- **Streaming.** `/v1/generate` and `/v1/chat/completions` return
  `text/event-stream` (Server-Sent Events) via
  FastAPI's `StreamingResponse`. Parse as SSE; payload format is
  determined by the server's `response_generator` module — treat it as
  opaque JSON chunks until consumed by a known client.
- **Auth.** Optional `Authorization: Bearer <token>` is extracted by
  `_extract_vdb_auth_token` (`server.py:166-173`) and passed through to
  the vector store layer. Not enforced at ingress.
- **CORS.** `allow_origins=["*"]`, `allow_credentials=False` (`server.py:121-128`).
- **Swagger UI / OpenAPI:** `GET /v1/docs`, `GET /v1/openapi.json`,
  `GET /v2/docs`, `GET /v2/openapi.json`. Root `/docs` and `/openapi.json`
  redirect to the `/v1` variants.
- **Source of truth for routes:** `nvidia-rag-oci` —
  `src/nvidia_rag/rag_server/server.py`.

### 3.1 Chat and search

| Method | Path                                          | Purpose                                                                                            |
|--------|-----------------------------------------------|----------------------------------------------------------------------------------------------------|
| POST   | `/v1/generate`                                | Core RAG generation. Retrieves from the vector store, optionally reranks/reflects/guards, calls the LLM, returns an SSE stream. |
| POST   | `/v1/chat/completions`                        | Alias for `/v1/generate` exposed for OpenAI-style clients. Accepts the same `Prompt` body — **not** a literal OpenAI ChatCompletion request; `messages`, `model`, `temperature`, `top_p`, `max_tokens`, and `stop` carry over, but RAG-specific fields (`collection_names`, `use_knowledge_base`, `enable_reranker`, etc.) are required for non-default behavior. |
| POST   | `/v1/search`                                  | Retrieval + reranking only, no LLM. Body is a `DocumentSearch` (`query`, `collection_names`, `reranker_top_k`, `vdb_top_k`, `filter_expr`, etc.). Returns `Citations` JSON.                     |
| POST   | `/v2/vector_stores/{vector_store_id}/search`  | OpenAI Vector Stores API shape. `{vector_store_id}` = collection name. **Available in `/v2` only — not mirrored on `/v1`.** Internally translates OpenAI filter DSL to Milvus/Elasticsearch format; for this pack (Oracle backend) verify the specific filter shape works end-to-end. |

**`POST /v1/generate` — key `Prompt` fields** (`server.py:374-582`). All
optional unless noted.

| Field                              | Type                                | Default (server-side)                                                                           | Notes                                                                                                                 |
|------------------------------------|-------------------------------------|-------------------------------------------------------------------------------------------------|-----------------------------------------------------------------------------------------------------------------------|
| `messages` (required)              | `list[Message]`                     | —                                                                                               | `{ role, content }`. `content` may be a string or a list of `TextContent` / `ImageContent`. Last message must have `role="user"`. |
| `use_knowledge_base`               | `bool`                              | `true`                                                                                          | If `false`, server skips retrieval and calls the LLM directly.                                                        |
| `collection_names`                 | `list[str]`                         | `["multimodal_data"]`                                                                           | Vector store collections to search. Legacy `collection_name` (singular string) is coerced to this list.               |
| `temperature` (0.0–1.0)            | `float`                             | `0`                                                                                             | Same meaning as OpenAI.                                                                                               |
| `top_p` (0.1–1.0)                  | `float`                             | `1.0`                                                                                           |                                                                                                                       |
| `max_tokens` (0–128000)            | `int`                               | `16384`                                                                                         |                                                                                                                       |
| `min_tokens`, `ignore_eos`, `stop` | various                             | server default                                                                                  | Standard sampling knobs.                                                                                              |
| `min_thinking_tokens`, `max_thinking_tokens` | `int | None`              | `null`                                                                                          | Reasoning-budget knobs; setting either enables thinking mode on Nemotron.                                             |
| `vdb_top_k` (0–400)                | `int`                               | `100`                                                                                           | Chunks retrieved from the vector store before reranking.                                                              |
| `reranker_top_k` (0–25)            | `int`                               | `10`                                                                                            | Chunks kept after reranking and fed into the LLM.                                                                     |
| `enable_reranker`                  | `bool`                              | `true`                                                                                          | Skip with `false` for latency-sensitive retrieval.                                                                    |
| `enable_citations`                 | `bool`                              | `true`                                                                                          | Return citation metadata alongside generated text.                                                                    |
| `enable_guardrails`                | `bool`                              | `false`                                                                                         | **Setting `true` in this pack will fail** — guardrails microservice is not deployed (§2.3).                           |
| `enable_query_rewriting`           | `bool`                              | `false`                                                                                         | Adds an LLM call before retrieval.                                                                                    |
| `enable_filter_generator`          | `bool`                              | `false`                                                                                         | Natural-language → filter-expression conversion.                                                                      |
| `confidence_threshold` (0.0–1.0)   | `float`                             | `0.0`                                                                                           | Minimum reranker score; requires `enable_reranker=true` to take effect.                                               |
| `filter_expr`                      | `str` or `list[dict]`               | `""`                                                                                            | Vector-DB-specific filter DSL; passed through to the backend (Oracle for this pack).                                  |
| `enable_vlm_inference`, `vlm_*`    | various                             | `false` / server defaults                                                                       | **Setting `true` will fail** — `nim-vlm` is not deployed (§2.3).                                                      |

### 3.2 Document summaries

| Method | Path           | Purpose                                                                                              |
|--------|----------------|------------------------------------------------------------------------------------------------------|
| GET    | `/v1/summary`  | Retrieve a per-document summary that was generated during ingestion. Supports blocking or polling.   |

**Query parameters** (`server.py:2070-2207`):

| Param               | Type    | Default | Notes                                                                                         |
|---------------------|---------|---------|-----------------------------------------------------------------------------------------------|
| `collection_name`   | `str`   | —       | Required.                                                                                     |
| `file_name`         | `str`   | —       | Required.                                                                                     |
| `blocking`          | `bool`  | `false` | If `true`, server waits for generation; if `false`, returns current status immediately.       |
| `timeout`           | `float` | `300`   | Integer seconds. Only used when `blocking=true`. Negative values → `400`.                     |

**Response body** is `SummaryResponse` with fields
`{ message, status, summary, file_name, collection_name, error, started_at, completed_at, updated_at, progress }`.

**Status-code mapping** (derived from the response `status` field):

| `status`          | HTTP |
|-------------------|------|
| `SUCCESS`         | 200  |
| `PENDING` / `IN_PROGRESS` | 202 |
| `NOT_FOUND`       | 404  |
| `FAILED` + `"timeout"` in `error` | 408 |
| `FAILED` (other)  | 500  |
| (invalid `timeout` query) | 400 |
| client disconnect | 499  |

Summaries are only produced when the upload request set
`generate_summary: true` (§4.1).

### 3.3 Health, defaults, metrics

| Method | Path                | Purpose                                                                                           |
|--------|---------------------|---------------------------------------------------------------------------------------------------|
| GET    | `/v1/health`        | Liveness. Optional `check_dependencies=true` query param extends the check to downstream NIMs / VDB. Returns `RAGHealthResponse`. |
| GET    | `/v1/configuration` | Server-side defaults used to initialize UI sliders, selectors, and feature toggles.               |
| GET    | `/v1/metrics`       | Prometheus exposition (multi-worker aggregated). Scrape target, not a UI contract.                |

`/v1/configuration` response shape (`ConfigurationResponse`,
`server.py:854-875`):

```
{
  "rag_configuration": {
    "temperature", "top_p", "max_tokens",
    "vdb_top_k", "reranker_top_k", "confidence_threshold"
  },
  "feature_toggles": {
    "enable_reranker", "enable_citations", "enable_guardrails",
    "enable_query_rewriting", "enable_vlm_inference",
    "enable_filter_generator"
  },
  "models": { "llm_model", "embedding_model", "reranker_model", "vlm_model" },
  "endpoints": {
    "llm_endpoint", "embedding_endpoint", "reranker_endpoint",
    "vlm_endpoint", "vdb_endpoint"
  }
}
```

Note: the `endpoints.*` values are **in-cluster service URLs**
(`nim-llm:8000`, `nemoretriever-embedding-ms:8000/v1`, …). Useful for
display and debugging; do not attempt to call them from the browser.

### 3.4 Endpoints a skin should not rely on

- `POST /v2/vector_stores/{id}/search` is available for OpenAI-SDK
  compatibility, but the filter-translation path to Oracle is less
  exercised than the native `/v1/search` — prefer `/v1/search` unless
  you specifically need the OpenAI shape.
- Anything under `/v2` other than the one vector-stores endpoint — the
  `/v2` namespace is reserved for OpenAI-shaped additions and may grow.
- `/v1/metrics` — Prometheus scrape target, not a UI contract.

---

## 4. Backend Service — `ingestor-server`

Document ingestion and collection management. Fronts NV-Ingest for
extraction and the vector store for writes. FastAPI, single worker by
default (`values:246`); throughput comes from NV-Ingest's Ray-based
parallelism.

- **In-cluster base URL:** `http://ingestor-server:8082/v1`.
  (The app sets `root_path="/v1"` — `server.py:89` — so paths in the
  tables below are written relative to that root.)
- **Auth.** `Authorization: Bearer <token>` is extracted by
  `_extract_vdb_auth_token` (`server.py:139-149`) and passed to the VDB
  layer. Returns empty string when no/empty token.
- **CORS.** `allow_origins=["*"]`, `allow_credentials=False`
  (`server.py:99-106`).
- **Swagger UI / Redoc:** `GET /v1/docs`, `GET /v1/redoc`,
  `GET /v1/openapi.json` (FastAPI built-ins rooted at `/v1`).
- **Source of truth for routes:** `nvidia-rag-oci` —
  `src/nvidia_rag/ingestor_server/server.py`.

### 4.1 Document lifecycle

The canonical upload flow is:

1. `POST /v1/documents` with `blocking=false` → `200 OK` with
   `IngestionTaskResponse { message, task_id }`.
2. Poll `GET /v1/status?task_id=<id>` until `state` is `FINISHED` or
   `FAILED`.
3. Optionally `GET /v1/documents?collection_name=...` to confirm the
   new document is present.

| Method | Path              | Purpose                                                                                                                                                       |
|--------|-------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------|
| POST   | `/v1/documents`   | Multipart upload. Form parts: `documents` (one or more `UploadFile`) + `payload` (JSON string matching `DocumentUploadRequest`). Returns `UploadDocumentResponse` when `blocking=true`, `IngestionTaskResponse` when `blocking=false`. **Both return HTTP 200 on success**; the body shape differs. |
| GET    | `/v1/documents`   | List documents in a collection. Query: `collection_name`. (`vdb_endpoint` is also accepted but hidden from the OpenAPI schema — reserved for internal use.)   |
| PATCH  | `/v1/documents`   | Replace documents. Same multipart form as `POST`.                                                                                                             |
| DELETE | `/v1/documents`   | Delete by name. Body: `document_names: list[str]`. Query: `collection_name`.                                                                                  |
| GET    | `/v1/status`      | Poll async ingestion state. Query: `task_id`. Returns `IngestionTaskStatusResponse { state, result, nv_ingest_status }`. `state ∈ {PENDING, FINISHED, FAILED, UNKNOWN}`; `UNKNOWN` is returned when the task id is not found. |

**`DocumentUploadRequest` key fields** (`server.py:307-376`):

| Field                          | Type                    | Default                | Notes                                                                                              |
|--------------------------------|-------------------------|------------------------|----------------------------------------------------------------------------------------------------|
| `collection_name`              | `str`                   | `"multimodal_data"`    | Target collection.                                                                                 |
| `blocking`                     | `bool`                  | `false`                | `true` → wait for completion and return `UploadDocumentResponse`; `false` → return `task_id` now. |
| `split_options`                | `SplitOptions`          | server default         | `{ chunk_size, chunk_overlap }`.                                                                   |
| `custom_metadata`              | `list[CustomMetadata]`  | `[]`                   | `{ filename, metadata }` per doc.                                                                  |
| `documents_catalog_metadata`   | `list[…]`               | `[]`                   | Per-doc description and tags for the catalog.                                                      |
| `generate_summary`             | `bool`                  | `false`                | Triggers summary generation (retrievable via `rag-server /v1/summary`).                            |
| `summary_options`              | `SummaryOptions \| null`| `null`                 | Page filter, strategy. Only valid when `generate_summary=true`.                                    |
| `enable_pdf_split_processing`, `pdf_split_processing_options` | various | server default | PDF chunking behavior.                                                                             |
| `vdb_endpoint`                 | `str`                   | from `APP_VECTORSTORE_URL` env | Hidden from the OpenAPI schema (`exclude=True`). Reserved for internal overrides.         |

### 4.2 Collection lifecycle

| Method  | Path                                                                      | Purpose                                                                                                     |
|---------|---------------------------------------------------------------------------|-------------------------------------------------------------------------------------------------------------|
| GET     | `/v1/collections`                                                         | List all collections.                                                                                       |
| POST    | `/v1/collection`                                                          | Create a collection with catalog metadata (`CreateCollectionRequest`: `collection_name`, `description`, `tags`, `owner`, `created_by`, `business_domain`, `status`, `metadata_schema`). Returns `CreateCollectionResponse`. |
| POST    | `/v1/collections`                                                         | **Deprecated** (`deprecated=True` in the route decorator, `server.py:1044`). Bulk create without catalog metadata. Do not wire new code. |
| PATCH   | `/v1/collections/{collection_name}/metadata`                              | Update collection catalog fields (`description`, `tags`, `owner`, `business_domain`, `status`).             |
| PATCH   | `/v1/collections/{collection_name}/documents/{document_name}/metadata`    | Update per-document `description` / `tags`.                                                                 |
| DELETE  | `/v1/collections`                                                         | Delete one or more collections. Query: `collection_names: list[str]`. (Hidden `vdb_endpoint` query.)         |

### 4.3 Health

| Method | Path           | Purpose                                                                                             |
|--------|----------------|-----------------------------------------------------------------------------------------------------|
| GET    | `/v1/health`   | Liveness. Optional `check_dependencies=true` extends to NV-Ingest, the vector store, and storage.   |

---

## 5. Frontend Skins (Catalog)

enterprise_rag ships one skin. `skin_enterprise_rag` is an enum
dropdown; its sole option today is the Core App skin. Source:
`ai-accelerator-tf/schemas/frontend_skins.yaml:44-51`.

| Skin     | Enum variable         | `container_port` | `subdomain`     | Default `image_uri`                                                  |
|----------|-----------------------|------------------|-----------------|----------------------------------------------------------------------|
| Core App | `skin_enterprise_rag` | 3000             | `frontend-erag` | `iad.ocir.io/iduyx1qnmway/enterprise-rag-frontend:v0.0.2`            |

Ingress host: `https://frontend-erag.<fqdn>`. `<fqdn>` is the generated
`nip.io` domain by default or a user-supplied FQDN when
`use_custom_dns = true`.

**Skin image override.** The selected `image_uri` is split on `:` and
fed into the Helm release's `frontend.image.{repository,tag}` set blocks
(`helm.tf:647-654`). The split invariant (for both `rag` and `aiq-aira`
releases) is locked by
`ai-accelerator-tf/schemas/tests/test_helm_skin_override.py`.

---

## 6. How a Skin Reaches the Backends

> **Critically different from cuopt / paas_rag.** Those packs stitch
> API paths onto the frontend's subdomain via
> `recipe_additional_ingress_ports` so a browser-side `fetch('/v1/models')`
> reaches the backend directly. **enterprise_rag does not do this.** The
> only ingress rule is `/` → `rag-frontend:3000`. A skin must bring its
> own mechanism for forwarding requests to `rag-server` and
> `ingestor-server`.

### 6.1 Ingress — what is and isn't published

Source: `ai-accelerator-tf/ingress.tf:150-191`.

| Ingress resource                      | Host                        | Path rules      | Backend              | TLS                                |
|---------------------------------------|-----------------------------|-----------------|----------------------|------------------------------------|
| `enterprise_rag_frontend_ingress`     | `frontend-erag.<fqdn>`      | `/` (Prefix)    | `rag-frontend:3000`  | `letsencrypt-prod` (cert-manager)  |

Relevant nginx annotations:

- `nginx.ingress.kubernetes.io/proxy-body-size: 2g` — multi-megabyte
  document uploads work end-to-end through the frontend ingress.
- `nginx.ingress.kubernetes.io/proxy-{read,send,connect}-timeout: 600` —
  10-minute timeouts for long-running RAG generations and ingestion
  operations proxied back to the user.
- `nginx.ingress.kubernetes.io/rewrite-target: /` — preserves path
  rewriting shape; functionally a no-op with only `/` published.

No auth annotation. No backend services have their own ingress rules.
`rag-server`, `ingestor-server`, `nim-llm`, etc. are **not** reachable
from the browser.

### 6.2 Chart-baked frontend env vars

The chart injects three environment variables into the frontend
container via its `frontend.envVars` block (`enterprise-rag-values.yaml:384-392`):

| Env var              | Value                                | Purpose                                     |
|----------------------|--------------------------------------|---------------------------------------------|
| `VITE_API_CHAT_URL`  | `http://rag-server:8081/v1`          | rag-server base URL, in-cluster only.       |
| `VITE_API_VDB_URL`   | `http://ingestor-server:8082/v1`     | ingestor-server base URL, in-cluster only.  |
| `VITE_MILVUS_URL`    | `http://milvus:19530`                | **Dead URL for this pack** (§2.3 — Milvus is not deployed). |

These values are **Kubernetes in-cluster DNS names**. A browser cannot
resolve or reach them. They must be consumed by server-side code or an
in-container proxy inside the skin (see §6.4).

**`VITE_MILVUS_URL` warning.** For this pack Milvus is not deployed at
all — the value is baked in because the upstream chart's sample SPA
expects it, but for enterprise_rag it points to a service that does
not exist. A replacement skin must not depend on it; use
`ingestor-server` `/v1/collections` and `/v1/documents` for catalog
operations.

**Open question: runtime vs build-time consumption.** The `frontend.envVars`
comment in the values file labels these "Runtime environment variables for
Vite frontend". In pure Vite, `import.meta.env.VITE_*` is a build-time
constant. If the upstream `enterprise-rag-frontend` image reads these at
runtime (e.g. via an `/env.js` bootstrap), a skin that does the same
will work unchanged; if it reads them at build time, a skin must re-bake
its own bundle with equivalent values. Inspect the shipped image or
upstream source to confirm the model used.

### 6.3 Pattern 1 — Not available

There is no `recipe_additional_ingress_ports` equivalent for Helm
packs. To expose backend paths on the frontend subdomain a skin author
must either (a) add a second `kubernetes_ingress_v1` resource in
`ingress.tf` that routes `/api/rag/* → rag-server:8081/*` etc., or
(b) have the skin container itself proxy those paths internally.
Option (b) is the path a skin author can take without editing the
starter pack — see §6.4 and §7.3.

### 6.4 What your skin container must do

1. Listen on port **3000** (`container_port` in `frontend_skins.yaml`).
   The container receives plain HTTP from nginx-ingress; TLS is
   terminated upstream.
2. Publish the UI on any paths you like — everything under
   `frontend-erag.<fqdn>/` routes to your container.
3. Implement one of:
   - **Server-side route layer.** Your container runs Node (or similar)
     and exposes API routes (e.g. `/api/chat`, `/api/documents`) that
     are called by the browser over the same origin. Those routes read
     `VITE_API_CHAT_URL` / `VITE_API_VDB_URL` and call the backends
     server-side. No CORS, no mixed-content, no direct browser exposure
     of `http://rag-server:8081`.
   - **In-container reverse proxy.** The container fronts an nginx (or
     equivalent) that rewrites selected paths to the backend URLs. For
     example, `/api/rag/* → http://rag-server:8081/v1/*` and
     `/api/vdb/* → http://ingestor-server:8082/v1/*`. The browser
     calls same-origin `/api/rag/*` paths.

Both patterns work. SSR gives you room to reshape responses, inject
headers, and hide backend shapes; the reverse proxy is simpler and
matches what the upstream `rag-frontend` does in practice.

---

## 7. Worked Examples

### 7.1 Browser — streaming chat against a same-origin server route

Assumes the skin runs a Node server with an `/api/chat/completions`
route that proxies to `rag-server`. Browser code is origin-relative.

```js
async function streamChat(messages, onDelta) {
  const resp = await fetch('/api/chat/completions', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      messages,
      use_knowledge_base: true,
      collection_names: ['multimodal_data'],
      enable_reranker: true,
      enable_citations: true,
      temperature: 0.1,
      max_tokens: 512,
    }),
  });
  if (!resp.ok) throw new Error(`rag-server ${resp.status}`);

  const reader = resp.body.getReader();
  const decoder = new TextDecoder();
  let buffer = '';
  while (true) {
    const { value, done } = await reader.read();
    if (done) return;
    buffer += decoder.decode(value, { stream: true });
    const lines = buffer.split('\n');
    buffer = lines.pop();                         // keep partial line
    for (const line of lines) {
      if (!line.startsWith('data: ')) continue;
      const data = line.slice(6).trim();
      if (!data) continue;
      try { onDelta(JSON.parse(data)); } catch { /* partial frame */ }
    }
  }
}
```

### 7.2 Server — the Node API route (SSR pattern)

```js
// /api/chat/completions — Next.js / Express-style route handler.
export default async function handler(req, res) {
  const backend = process.env.VITE_API_CHAT_URL;    // http://rag-server:8081/v1
  const upstream = await fetch(`${backend}/chat/completions`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(req.body),
  });
  res.status(upstream.status);
  res.setHeader('Content-Type', 'text/event-stream');
  for await (const chunk of upstream.body) res.write(chunk);   // pipe SSE
  res.end();
}
```

### 7.3 nginx reverse proxy (drop-in alternative to SSR)

Minimal `nginx.conf` the skin container can use. Browser calls
`/api/rag/*` and `/api/vdb/*`; nginx forwards them in-cluster.

```nginx
server {
  listen 3000;

  # Static bundle for the SPA.
  root /usr/share/nginx/html;
  try_files $uri /index.html;

  # rag-server (chat, search, summary, configuration).
  location /api/rag/ {
    proxy_pass         http://rag-server:8081/v1/;
    proxy_http_version 1.1;
    proxy_set_header   Host $host;
    proxy_set_header   Connection '';
    proxy_buffering    off;                         # critical for SSE
    proxy_read_timeout 600s;
  }

  # ingestor-server (documents, collections, status).
  location /api/vdb/ {
    proxy_pass         http://ingestor-server:8082/v1/;
    proxy_http_version 1.1;
    client_max_body_size 2g;                        # matches ingress annotation
    proxy_read_timeout   600s;
  }
}
```

Browser:

```js
await fetch('/api/rag/chat/completions', { method: 'POST', body: ... });
const status = await fetch(`/api/vdb/status?task_id=${taskId}`).then(r => r.json());
```

### 7.4 Uploading a document with async status polling

```js
async function uploadAndWait(file, collectionName) {
  const form = new FormData();
  form.append('documents', file);
  form.append('payload', JSON.stringify({
    collection_name: collectionName,
    blocking: false,
    generate_summary: true,
  }));

  // POST /v1/documents with blocking=false returns 200 with a task_id body.
  const { task_id } = await fetch('/api/vdb/documents', {
    method: 'POST',
    body: form,
  }).then(r => r.json());

  while (true) {
    const st = await fetch(`/api/vdb/status?task_id=${task_id}`)
      .then(r => r.json());
    if (st.state === 'FINISHED') return st.result;
    if (st.state === 'FAILED')   throw new Error('ingestion failed');
    await new Promise(res => setTimeout(res, 2000));
  }
}
```

### 7.5 Initializing the UI from `/v1/configuration`

```js
const config = await fetch('/api/rag/configuration').then(r => r.json());
// config.rag_configuration — default temperature, top_p, max_tokens, …
// config.feature_toggles   — enable_reranker, enable_citations, …
// config.models            — model names in use
// config.endpoints         — in-cluster URLs (display / debugging only;
//                            not reachable from the browser)
```

---

## 8. What Is Not in the Contract

Internal to this pack. A skin must not hard-code assumptions against
any of these; chart revisions can change names, ports, and shapes
without notice.

| Surface                                                                  | Why it is internal                                                                                                    |
|--------------------------------------------------------------------------|-----------------------------------------------------------------------------------------------------------------------|
| `nim-llm:8000`, `nemoretriever-embedding-ms:8000`, `nemoretriever-ranking-ms:8000` | NIM microservices called by `rag-server`. Bypassing it skips guardrails, citations, reflection, and metrics. |
| `rag-nv-ingest:7670` / `:7671` / `:8265`                                 | Ray extraction pipeline. `ingestor-server` is the abstraction; `:8265` is a developer Ray dashboard, not a product API. |
| `nv-ingest-ocr:8000/8001`, `nemoretriever-page-elements-v2:8000/8001`, `nemoretriever-graphic-elements-v1:8000/8001`, `nemoretriever-table-structure-v1:8000/8001` | NV-Ingest sub-NIMs (Paddle OCR, YOLOX element detectors). Called by `rag-nv-ingest`, not by clients. |
| `rag-redis-master:6379`                                                  | Task queue for async ingestion. Poll via `/v1/status`, not Redis directly.                                            |
| Oracle 26ai ADB (vector store)                                           | Accessed through `rag-server` / `ingestor-server`. The ADB connection string is terraform-injected.                   |
| `VITE_MILVUS_URL=http://milvus:19530`                                    | **Dead pointer** in this pack — Milvus is not deployed. See §2.3 and §6.2.                                            |
| `rag-minio:9000` / MinIO console                                         | Not deployed in this pack (`ENABLE_MINIO=false`).                                                                     |
| `nemo-guardrails:7331`                                                   | Not deployed in this pack. `NEMO_GUARDRAILS_URL` is configured, but `ENABLE_GUARDRAILS=False`.                        |
| `nim-vlm:8000`, `nemoretriever-vlm-embedding-ms`, `nim-vlm-text-extraction`, `nemoretriever-ocr` | Disabled in the chart values. See §2.3.                                                                    |
| Corrino REST API (`/deployment/`, `/deploy/`, `/validate/`, `/workspace/`) | Control-plane API for recipe-based packs. Not involved in Helm packs.                                               |
| `corrino-configmap` values (`REGION_NAME`, `COMPARTMENT_ID`, `TENANCY_ID`, `TENANCY_NAMESPACE`) | Exist in the cluster for recipe-based packs (see vss doc). The `rag` chart does not mount them into the frontend. |
| OpenTelemetry / Prometheus / Grafana / Zipkin                            | Observability infra. Disabled by default; `APP_TRACING_ENABLED: "False"` (`values:181`).                              |
| `rag-server /v1/metrics`, `ingestor-server` Prometheus scrape            | Metric scrape targets, not UI contracts.                                                                              |

If a skin finds it needs one of these, the right move is to file a chart
issue upstream or add the capability to `rag-server` / `ingestor-server`
— not to call the internal service directly.

---

## 9. Source of Truth

| Concern                                                     | File / URL                                                                                                      |
|-------------------------------------------------------------|-----------------------------------------------------------------------------------------------------------------|
| Terraform helm_release for the `rag` chart                  | `ai-accelerator-tf/helm.tf:581-673`                                                                             |
| Values file selector                                        | `ai-accelerator-tf/helm.tf:594-599`                                                                             |
| Frontend image skin override                                | `ai-accelerator-tf/helm.tf:647-654`                                                                             |
| Oracle 26ai credential injection (enterprise_rag only)      | `ai-accelerator-tf/helm.tf:612-630`, `:656-666`                                                                 |
| NIM LLM image pin                                           | `ai-accelerator-tf/helm.tf:639-646`                                                                             |
| `app_namespace` creation                                    | `ai-accelerator-tf/helm.tf:443-448` (default value lives under `local.starter_pack_config`)                     |
| Chart values (full stack config)                            | `ai-accelerator-tf/helm-values/enterprise-rag-values.yaml`                                                      |
| — `rag-server` envVars (vector store, models, feature flags)| `enterprise-rag-values.yaml:80-213`                                                                             |
| — `ingestor-server` envVars                                 | `enterprise-rag-values.yaml:258-342`                                                                            |
| — `frontend.envVars` (VITE_*)                               | `enterprise-rag-values.yaml:384-392`                                                                            |
| — `nim-llm`, embed / rank NIMs, VLM (disabled), `nv-ingest` | `enterprise-rag-values.yaml:551-928`                                                                            |
| VSS-only Milvus helm_release (not used here)                | `ai-accelerator-tf/helm.tf:385-441` (`count = local.deploy_app_vss`)                                            |
| Frontend ingress rule                                       | `ai-accelerator-tf/ingress.tf:150-191`                                                                          |
| Skin catalog                                                | `ai-accelerator-tf/schemas/frontend_skins.yaml:44-51`                                                           |
| Skin-override invariant test                                | `ai-accelerator-tf/schemas/tests/test_helm_skin_override.py`                                                    |
| Upstream chart (NGC; pulled at apply time)                  | https://helm.ngc.nvidia.com/nvidia/blueprint/charts/nvidia-blueprint-rag-v2.3.0.tgz                             |
| Chart endpoints reference (operator-level)                  | `nvidia-rag-oci` — `deploy/helm/nvidia-blueprint-rag/endpoints.md` (covers upstream v2.4.0; use with the version caveat in §10) |
| `rag-server` FastAPI routes                                 | `nvidia-rag-oci` — `src/nvidia_rag/rag_server/server.py`, `main.py`                                             |
| `rag-server` API reference                                  | `nvidia-rag-oci` — `docs/api-rag.md`, `docs/api_reference/openapi_schema_rag_server.json`                       |
| `ingestor-server` FastAPI routes                            | `nvidia-rag-oci` — `src/nvidia_rag/ingestor_server/server.py`, `main.py`                                        |
| `ingestor-server` API reference                             | `nvidia-rag-oci` — `docs/api-ingestor.md`, `docs/api_reference/openapi_schema_ingestor_server.json`             |
| Deployed image version                                      | `nvidia-rag-oci` — `VERSION` (`v0.0.5`)                                                                         |

---

## 10. Open Questions and Caveats

Items we can't fully confirm from the repo and starter pack alone:

- **Chart version vs on-disk code.** The starter pack pins chart
  `v2.3.0` (`helm.tf:586`); the on-disk chart in `nvidia-rag-oci`
  (`deploy/helm/nvidia-blueprint-rag/Chart.yaml`) is `v2.4.0`. The
  deployed backend images are **Oracle custom builds** at version
  `v0.0.5` (image tags in `enterprise-rag-values.yaml` lines 37–40 and
  235–238, and `nvidia-rag-oci/VERSION`), so the FastAPI endpoint
  tables in §3 and §4 — derived from the `v0.0.5` source on disk —
  match what runs. Chart-level details (templates, services,
  sub-chart defaults) come from v2.3.0 in production, which may
  differ in small ways from the v2.4.0 on-disk chart used as a
  reference.
- **Vite env-var consumption model.** §6.2 — whether `VITE_API_CHAT_URL`
  and `VITE_API_VDB_URL` are consumed at build time or runtime depends
  on the upstream `enterprise-rag-frontend:v0.0.2` image's
  implementation, which is not in this repo. Verify by inspecting the
  shipped image before shipping a skin that relies on a specific model.
- **`POST /v2/vector_stores/{id}/search` on Oracle backend.** The
  OpenAI-filter-translation path is implemented for Milvus and
  Elasticsearch (`server.py:176-371`). For Oracle (the active VDB in
  this pack) the translation is not explicitly shown; end-to-end
  behavior with non-trivial filters should be verified before relying
  on this endpoint.
- **`enable_guardrails=true` and `enable_vlm_inference=true` requests.**
  `rag-server` will attempt to reach `nemo-guardrails:7331` and
  `nim-vlm:8000` respectively; neither service is deployed in this pack
  (§2.3). These flags default to `false`; a skin must not enable them
  without either deploying the missing services or accepting runtime
  errors.
- **Exact SSE framing.** `rag-server` returns `text/event-stream` via
  FastAPI's `StreamingResponse`; the payload format is produced by
  `nvidia_rag.rag_server.response_generator` and is not exhaustively
  documented here. The example parser in §7.1 handles the observed
  shape (newline-delimited `data: <json>` frames); more exotic framing
  (event types, retry directives) would need the upstream client as a
  reference.

---

## 11. When to Update This Doc

Manually maintained. No drift-check test against Terraform. Update
whenever you change any of:

- `ai-accelerator-tf/helm.tf` — the `rag` `helm_release` block,
  especially the `chart` URL, the `set` entries for `frontend.image.*`
  or any `envVars.*` / `ingestor-server.envVars.*` injection.
- `ai-accelerator-tf/helm-values/enterprise-rag-values.yaml` — any
  change to `frontend.envVars`, `rag-server.envVars`,
  `ingestor-server.envVars`, the `nim-llm` / `nv-ingest` sub-chart
  defaults, or the enabled/disabled toggles for NIMs and observability
  sub-charts (changes to §2 service inventory).
- `ai-accelerator-tf/ingress.tf` — the `enterprise_rag_frontend_ingress`
  rule.
- `ai-accelerator-tf/schemas/frontend_skins.yaml` — the `enterprise_rag`
  entry.
- The upstream chart version — new chart releases can rename endpoints,
  rename services, or change the `frontend.envVars` list. Re-verify
  §3 and §4 against `src/nvidia_rag/*/server.py` and §2 against the
  chart's `values.yaml` when bumping.
- The deployed image version (`nvidia-rag-oci/VERSION`) — spot-check §3
  and §4 routes against the new source when the Oracle fork advances.

### "When in doubt" rule

> Would a skin author need this to wire their frontend to rag-server or
> ingestor-server? If yes, document it here.
