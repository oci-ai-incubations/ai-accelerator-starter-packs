# enterprise_rag Pack — Backend API Contract

Companion document to `BACKEND_API_CONTRACT.md`. That file is the multi-pack
reference organized around skin-access *mechanisms* (ingress paths vs env
vars). This file is the enterprise_rag-pack-specific deep dive organized
around *backend services and their API surface* — what a skin author can
actually call.

Scope: `starter_pack_category = "enterprise_rag"`. For cuopt see
`BACKEND_API_CONTRACT_CUOPT.md`; for vss / paas_rag / enterprise_rag_aiq see
`BACKEND_API_CONTRACT.md` §3.2, §3.3, §3.5.

---

## 1. Deployment Mechanism — Helm, Not Corrino

**The single most important fact about this pack:** enterprise_rag does
*not* deploy through Corrino recipes. It is installed as a vanilla Helm
release of the NVIDIA RAG Blueprint chart, pulled from NGC at Terraform
apply time.

Source of truth: `ai-accelerator-tf/helm.tf:581-673`.

| Concern                         | Value                                                                                                         |
|---------------------------------|---------------------------------------------------------------------------------------------------------------|
| Terraform resource              | `helm_release.rag` (`helm.tf:581`)                                                                            |
| Chart                           | `https://helm.ngc.nvidia.com/nvidia/blueprint/charts/nvidia-blueprint-rag-v2.3.0.tgz` (`helm.tf:586`)         |
| Chart auth                      | NGC `$oauthtoken` + `NGC_API_KEY` from the `ngc-api-secret` K8s Secret (`helm.tf:588-589`)                    |
| Values file                     | `ai-accelerator-tf/helm-values/enterprise-rag-values.yaml` (selected at `helm.tf:594-599`)                    |
| Release timeout                 | 5400 s (90 min) — NIM pods take a long time to pull and initialize (`helm.tf:591`)                            |
| Gating                          | `count = local.deploy_app_rag ? 1 : 0` — requires `starter_pack_category ∈ {"enterprise_rag", "enterprise_rag_aiq"}` (`helm.tf:668`) |
| Frontend image override         | `frontend.image.{repository,tag}` set from the selected skin's `image_uri` (`helm.tf:647-654`)                |
| Oracle 26ai credentials         | Injected via `envVars.ORACLE_{USER,PASSWORD,CS}` and `ingestor-server.envVars.ORACLE_*` — enterprise_rag only (`helm.tf:612-630, 656-666`) |
| NIM LLM image pin               | `nvcr.io/nim/nvidia/llama-3.3-nemotron-super-49b-v1.5:1.14.0` (`helm.tf:639-646`)                             |

**Consequences of being Helm-deployed, not recipe-deployed:**

- There is no `blueprint_files.tf` entry for this pack's backends — the
  chart brings its own Services, Deployments, PVCs, ConfigMaps, and
  internal wiring.
- There is no `recipe_additional_ingress_ports` stitching API paths onto
  the frontend's subdomain. The starter pack cannot add or remove paths
  without editing the chart.
- There is no `recipe_container_env` injection into the frontend at
  deploy time. Frontend env vars come from the chart's `frontend.envVars`
  block (see §6.2) and are baked into the Vite bundle at chart build
  time, not at Terraform apply time.
- Corrino's REST API (`/deployment/`, `/deploy/`, `/validate/`,
  `/workspace/`, …) has no record of the RAG workload. A skin must never
  attempt to call Corrino.

---

## 2. Deployment Group Composition

What the Helm release creates on the cluster. Service names are the
in-cluster Kubernetes DNS names (ClusterIP, same namespace as the release).

| K8s Service                   | Container image (default)                                                          | Port  | GPU     | Role                                                                                  |
|-------------------------------|------------------------------------------------------------------------------------|-------|---------|---------------------------------------------------------------------------------------|
| `rag-frontend`                | Overridden by skin (`frontend-erag`) — default `iad.ocir.io/.../enterprise-rag-frontend:v0.0.2` | 3000  | —       | User-facing Vite SPA container. **Only service exposed via ingress.**                 |
| `rag-server`                  | `nvcr.io/nvstaging/blueprint/rag-server:2.4.0`                                     | 8081  | —       | Main chat / search / summary FastAPI. Orchestrates NIMs, guardrails, reflection.      |
| `ingestor-server`             | `nvcr.io/nvstaging/blueprint/ingestor-server:2.4.0`                                | 8082  | —       | Document ingestion FastAPI. Fronts `nv-ingest`, vector store writes, collection CRUD. |
| `nim-llm`                     | `nvcr.io/nim/nvidia/llama-3.3-nemotron-super-49b-v1.5:1.14.0`                      | 8000  | 8       | Nemotron LLM for response generation.                                                 |
| `nemoretriever-embedding-ms`  | `nvcr.io/nim/nvidia/llama-3.2-nv-embedqa-1b-v2:1.10.1`                             | 8000  | 1       | Text + multimodal embeddings.                                                         |
| `nemoretriever-ranking-ms`    | `nvcr.io/nim/nvidia/llama-3.2-nv-rerankqa-1b-v2:1.8.0`                             | 8000  | 1       | Reranker. Enabled by default.                                                         |
| `nv-ingest` (sub-chart)       | `nvcr.io/nvidia/nemo-microservices/nv-ingest:26.1.2` + YOLOX / OCR sub-NIMs        | 7670 / 7671 / 8265 | Ray headless + 3× YOLOX (1 GPU each) + OCR (1 GPU) | Ray-based extraction pipeline (page, graphic, table, OCR).                            |
| `rag-redis-master`            | Redis (sub-chart)                                                                   | 6379  | —       | Task queue backing the async ingestion pipeline.                                      |
| `milvus` (enterprise_rag) / `oracle-26ai` (via ADB) | Milvus or Oracle Autonomous Database                              | 19530 / 1521 | 0 (GPU-accel Milvus) | Vector store. For `enterprise_rag` the Helm chart deploys Milvus and Terraform provisions an Oracle 26ai ADB in parallel; `APP_VECTORSTORE_NAME: "oracle"` routes writes to Oracle. |
| `minio`                       | MinIO (sub-chart)                                                                   | 9010 / 9011 | — | S3-compatible blob store for multimodal content (images, charts).                     |
| `nim-vlm`                     | —                                                                                   | —     | —       | **Disabled by default** (`enabled: false`).                                            |
| `elasticsearch`               | —                                                                                   | —     | —       | **Disabled by default** (Oracle 26ai used instead).                                    |
| `opentelemetry-collector`     | —                                                                                   | —     | —       | **Disabled by default**.                                                               |

**Key facts:**

- **Only `rag-frontend` is reachable from outside the cluster.** Every
  other Service is `ClusterIP` with no ingress rule. Backends are
  discovered by short K8s DNS names (`rag-server`, `ingestor-server`,
  `nim-llm`, etc.).
- **`nim-llm` runs on a reserved tainted node.** The starter pack labels
  and taints a worker node with `workload=nim-llm` so the 8-GPU LLM lands
  there exclusively. See `helm.tf` `depends_on` chain.
- **The vector DB for enterprise_rag is Oracle 26ai, not Milvus**, even
  though both services are present. `rag-server`'s `APP_VECTORSTORE_NAME`
  env var (`enterprise-rag-values.yaml:80-213`) points the code at Oracle
  and the `ingestor-server` writes there.
- **The chart also installs `ingestor-server`, `nv-ingest`, and Redis as
  sub-charts.** See `deploy/helm/nvidia-blueprint-rag/Chart.yaml` in the
  upstream NVIDIA RAG repo for the exact dependency graph.

---

## 3. Backend Service — `rag-server`

The main RAG API: chat, search, document summarization, and an
OpenAI-compatible surface for vector store search. FastAPI, served by
uvicorn under gunicorn with 8 workers by default.

- **In-cluster address:** `http://rag-server:8081`
- **URL prefix:** all routes are mounted under `/v1` (the root path is
  set to `/v1` in `rag_server/server.py`, with a sibling `/v2` router for
  OpenAI-compatible endpoints).
- **Streaming format:** Server-Sent Events (`text/event-stream`), one
  JSON object per `data:` line, terminated by `[DONE]`.
- **Auth:** optional `Authorization: Bearer <token>` header is passed
  through to the vector store layer. Not enforced at the ingress. Treat
  auth as an application concern.
- **Source for route list:** upstream repo `nvidia-rag-oci` —
  `src/nvidia_rag/rag_server/server.py` (and `main.py`).
- **OpenAPI / Swagger:** `GET /v1/docs`, `GET /v1/openapi.json`,
  `GET /v2/docs`, `GET /v2/openapi.json`.

### 3.1 Chat and search

| Method | Path                                          | Purpose                                                                                            |
|--------|-----------------------------------------------|----------------------------------------------------------------------------------------------------|
| POST   | `/v1/generate`                                | Core RAG chat completion. Retrieves from the vector store, optionally reranks, calls the LLM, optionally applies guardrails/reflection, returns an SSE stream. |
| POST   | `/v1/chat/completions`                        | Alias for `/v1/generate` that matches the OpenAI Chat Completions request/response shape. Same streaming semantics. |
| POST   | `/v1/search`                                  | Retrieval + reranking only, no LLM. Returns a JSON list of ranked chunks with citations metadata.  |
| POST   | `/v2/vector_stores/{vector_store_id}/search`  | OpenAI Vector Stores API shape, for drop-in use with the OpenAI SDK's `vectorStores.search(...)`. Internally translates filter DSL for Milvus / Elasticsearch / Oracle. |

**Primary `POST /v1/generate` request body (abbreviated):**

| Field                    | Type          | Default     | Notes                                                                                      |
|--------------------------|---------------|-------------|--------------------------------------------------------------------------------------------|
| `messages`               | `Message[]`   | —           | `{ role, content }`. `content` may be a string or a list of `TextContent` / `ImageContent`.|
| `use_knowledge_base`     | `bool`        | `true`      | If `false`, the server skips retrieval and just calls the LLM.                              |
| `collection_names`       | `string[]`    | `["multimodal_data"]` | Vector store collections to search.                                                |
| `temperature`, `top_p`, `max_tokens`, `min_tokens` | numbers | server default | Standard LLM sampling knobs.                                                 |
| `vdb_top_k`, `reranker_top_k` | `int`    | server default | Chunks fetched from the VDB and kept after reranking.                                      |
| `enable_reranker`        | `bool`        | `true`      | Set `false` to skip the reranker for latency-sensitive calls.                              |
| `enable_citations`       | `bool`        | `true`      | Annotate response chunks with citation indices pointing back into the retrieval list.      |
| `enable_guardrails`      | `bool`        | `false`     | Route request/response through NeMo Guardrails (only when guardrails deployment is installed). |
| `enable_filter_generator`, `confidence_threshold`, `filter_expr` | mixed | — | Advanced filter-expression support; `filter_expr` format is vector-DB-specific.     |

**Status codes:** `200` (stream), `400` (bad request), `499` (client
disconnect mid-stream), `500` (server error).

### 3.2 Document summaries

| Method | Path                                     | Purpose                                                                                                                                              |
|--------|------------------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------|
| GET    | `/v1/summary`                            | Fetch a pre-generated document summary. Query params identify the collection + document. Blocking or non-blocking depending on server config.        |

Summaries are generated during document ingestion when the upload request
sets `generate_summary: true`. The endpoint returns `200` when the
summary is ready, `202` when still being produced, `404` when no
summary exists for the document, and `408` if a blocking wait timed out.

### 3.3 Health, metadata, metrics

| Method | Path                     | Purpose                                                                                           |
|--------|--------------------------|---------------------------------------------------------------------------------------------------|
| GET    | `/v1/health`             | Liveness / dependency check. Returns 200 when rag-server and its downstream dependencies respond. |
| GET    | `/v1/configuration`      | Server-side defaults (LLM params, model names, endpoint names, feature toggles). UIs call this at load time to populate sliders and model-selector dropdowns. |
| GET    | `/v1/metrics`            | Prometheus exposition (multi-worker aggregated). Not intended for UI consumption.                 |

### 3.4 Endpoints not to call from a skin

- Anything under `/v2` other than `/v2/vector_stores/{id}/search` — the
  `/v2` router is reserved for OpenAI-compatible endpoints and may grow
  over minor versions.
- `/v1/metrics` — Prometheus scrape target, not a UI contract.

---

## 4. Backend Service — `ingestor-server`

Document ingestion and collection management. Fronts `nv-ingest` for
extraction and the vector store for writes. FastAPI, single worker by
default (throughput comes from nv-ingest's Ray-based parallelism).

- **In-cluster address:** `http://ingestor-server:8082`
- **URL prefix:** `/v1`.
- **Auth:** optional `Authorization: Bearer <token>` passed through to
  the vector store layer, same semantics as rag-server.
- **CORS:** the server enables CORS for all origins.
- **Source for route list:** upstream repo `nvidia-rag-oci` —
  `src/nvidia_rag/ingestor_server/server.py`.
- **OpenAPI / Swagger:** `GET /v1/docs`, `GET /v1/openapi.json`.

### 4.1 Document lifecycle

The canonical upload flow is:

1. `POST /v1/documents` with `blocking=false` → receive `{ task_id }`.
2. Poll `GET /v1/status?task_id=<id>` until `state` is `FINISHED` or
   `FAILED`.
3. (If `FINISHED`) optionally call `GET /v1/documents` to confirm the new
   document is present in the collection.

| Method  | Path                  | Purpose                                                                                                                                                  |
|---------|-----------------------|----------------------------------------------------------------------------------------------------------------------------------------------------------|
| POST    | `/v1/documents`       | Multipart upload. `documents` = one or more files; `payload` = JSON with `collection_name`, `blocking`, `split_options`, `custom_metadata`, `generate_summary`, `summary_options`, `enable_pdf_split_processing`. |
| GET     | `/v1/documents`       | List documents in a collection. Query param `collection_name`.                                                                                            |
| PATCH   | `/v1/documents`       | Replace one or more documents (same multipart form as POST).                                                                                              |
| DELETE  | `/v1/documents`       | Delete documents by name within a collection.                                                                                                             |
| GET     | `/v1/status`          | Poll async ingestion state. Returns `{ state, result, nv_ingest_status }`. `state ∈ {PENDING, FINISHED, FAILED, UNKNOWN}`.                                |

**`POST /v1/documents` form parts:**

- `documents` — one or more `UploadFile` parts (PDFs, DOCX, images, etc.).
- `payload` — a JSON blob with at minimum `{ "collection_name": "<name>" }`.

**Status codes:** `200` (blocking, complete), `202` (non-blocking,
task queued), `400` (bad input), `499` (client disconnect), `500` (server
error).

### 4.2 Collection lifecycle

| Method  | Path                                                                 | Purpose                                                                                                   |
|---------|----------------------------------------------------------------------|-----------------------------------------------------------------------------------------------------------|
| GET     | `/v1/collections`                                                    | List all collections in the vector store.                                                                  |
| POST    | `/v1/collection`                                                     | Create a collection with catalog metadata (`description`, `tags`, `owner`, `created_by`, `business_domain`, `status`, `metadata_schema`). |
| POST    | `/v1/collections`                                                    | **Deprecated** bulk-create form. Prefer `/v1/collection` for new code.                                    |
| PATCH   | `/v1/collections/{collection_name}/metadata`                         | Update collection-level catalog metadata.                                                                  |
| PATCH   | `/v1/collections/{collection_name}/documents/{document_name}/metadata`| Update per-document metadata (description, tags).                                                         |
| DELETE  | `/v1/collections`                                                    | Delete one or more collections.                                                                            |

### 4.3 Health

| Method | Path           | Purpose                                                                                           |
|--------|----------------|---------------------------------------------------------------------------------------------------|
| GET    | `/v1/health`   | Liveness. `?check_dependencies=true` extends the check to nv-ingest, the vector store, and MinIO. |

### 4.4 Endpoints not to call from a skin

- `/v1/collections` (POST) — deprecated alias for `/v1/collection`; do not
  wire new code to it.

---

## 5. Frontend Skins (Catalog)

enterprise_rag ships one skin. The `skin_enterprise_rag` ORM variable is
an enum dropdown; its sole option today is the Core App skin. Source:
`ai-accelerator-tf/schemas/frontend_skins.yaml:44-51`.

| Skin     | Enum variable         | `container_port` | `subdomain`     | Default image                                                        |
|----------|-----------------------|------------------|-----------------|----------------------------------------------------------------------|
| Core App | `skin_enterprise_rag` | 3000             | `frontend-erag` | `iad.ocir.io/iduyx1qnmway/enterprise-rag-frontend:v0.0.2`            |

Ingress host: `https://frontend-erag.<fqdn>`. `<fqdn>` resolves to the
generated `nip.io` domain (default) or a user-supplied FQDN if
`use_custom_dns = true`.

**Skin image override.** The selected skin's `image_uri` is split on `:`
and fed into the Helm release's `frontend.image.{repository,tag}` set
blocks (`helm.tf:647-654`). The split invariant (applies to both the
`rag` release and the `aiq-aira` release for the AIQ pack) is locked by
`ai-accelerator-tf/schemas/tests/test_helm_skin_override.py`.

---

## 6. How a Skin Reaches the Backends

> **Critically different from cuopt / paas_rag.** Those packs stitch API
> paths onto the frontend's subdomain via `recipe_additional_ingress_ports`
> so a browser-side `fetch('/v1/models')` reaches the backend directly.
> **enterprise_rag does not do this.** The only ingress rule is `/` →
> `rag-frontend:3000`. A skin must bring its own mechanism for forwarding
> requests to `rag-server` and `ingestor-server`.

### 6.1 Ingress — what is and isn't published

Source: `ai-accelerator-tf/ingress.tf:150-191`.

| Ingress resource                         | Host                                 | Path rules      | Backend              | TLS                        |
|------------------------------------------|--------------------------------------|-----------------|----------------------|----------------------------|
| `enterprise_rag_frontend_ingress`        | `frontend-erag.<fqdn>`               | `/` (Prefix)    | `rag-frontend:3000`  | `letsencrypt-prod` (cert-manager) |

Relevant nginx annotations on the ingress:

- `nginx.ingress.kubernetes.io/proxy-body-size: 2g` — multi-megabyte
  document uploads work through the frontend ingress.
- `nginx.ingress.kubernetes.io/proxy-{read,send,connect}-timeout: 600` —
  10-minute timeouts to accommodate long-running RAG generations and
  ingestion operations that proxy back to the user's browser.
- `nginx.ingress.kubernetes.io/rewrite-target: /` — the rewrite is a
  no-op here since only `/` is published. It is present so that a future
  chart revision or skin design can rely on the same annotation shape.

No auth annotation. No backend services have their own ingress rules.
The rag-server and ingestor-server ports are **not** reachable from the
browser.

### 6.2 Pattern 2 — In-chart env vars (the only mechanism the pack provides)

The NVIDIA RAG Helm chart bakes three environment variables into the
frontend container via its `frontend.envVars` block. Source:
`ai-accelerator-tf/helm-values/enterprise-rag-values.yaml:384-392`.

| Env var              | Value                                | Purpose                                     |
|----------------------|--------------------------------------|---------------------------------------------|
| `VITE_API_CHAT_URL`  | `http://rag-server:8081/v1`          | rag-server, in-cluster base URL.            |
| `VITE_API_VDB_URL`   | `http://ingestor-server:8082/v1`     | ingestor-server, in-cluster base URL.       |
| `VITE_MILVUS_URL`    | `http://milvus:19530`                | Milvus direct address. See caveat below.    |

**These are in-cluster K8s DNS names.** They resolve only from inside the
cluster — a browser cannot connect to `http://rag-server:8081/v1`.
Treat them the way cuopt's `CUOPT_ENDPOINT` / `LLAMASTACK_ENDPOINT` are
treated: server-side only.

**Vite `import.meta.env.*` vs OS env vars.** The shipped `rag-frontend` is
built by the chart's container as a Vite bundle. Vite embeds
`import.meta.env.VITE_*` constants at *build time* — the container does
not read `process.env.VITE_API_CHAT_URL` at runtime. If your skin
container also uses Vite, you have two choices:

1. **Re-bake at skin build time.** Embed the same URLs as build
   constants in your skin's Vite build (run `vite build` with the env
   vars set).
2. **Switch to runtime configuration.** Read the URLs from
   `process.env` (or from a templated `/config.js` served by your
   container's nginx) and pass them into your SPA at runtime.

Either way, these URLs are consumed by *server-side code or an
in-container reverse proxy inside the skin*, never by the browser.

**`VITE_MILVUS_URL` caveat.** The upstream sample frontend reads
`VITE_MILVUS_URL` for niche admin views (collection/catalog stats). A
replacement skin should prefer `ingestor-server`'s `/v1/collections` and
`/v1/documents` endpoints and treat Milvus as internal. The env var is
present for parity with the upstream bundle; new skins should not
depend on it. (Additionally, for the `enterprise_rag` pack the active
vector store is Oracle 26ai, not Milvus — Milvus is deployed but idle
for routing-through-rag-server purposes.)

### 6.3 Pattern 1 — Not available

There is no `recipe_additional_ingress_ports` equivalent for Helm packs.
To expose backend paths on the frontend subdomain you would need to
either (a) add a second ingress resource in `ingress.tf` that routes
paths like `/api/chat/*` to `rag-server:8081/*` with the appropriate
rewrite, or (b) have the skin container itself proxy those paths
internally. Option (b) is the path a skin author can take without
editing the starter pack — see §7.3.

### 6.4 What your skin container must do

Summary of the skin contract:

1. Listen on port **3000** (from the catalog `container_port`). Your
   container receives plain HTTP from nginx-ingress; TLS is terminated
   upstream.
2. Publish the UI on any paths you like — everything under
   `frontend-erag.<fqdn>/` routes to your container.
3. Implement one of:
   - **Server-side route layer.** Your container runs Node (or similar)
     and exposes API routes (e.g. `/api/chat`, `/api/documents`) that
     are called by the browser over the same origin. Those routes read
     `VITE_API_CHAT_URL` / `VITE_API_VDB_URL` and call the backends
     server-side. No CORS, no mixed-content, no direct browser exposure
     of `http://rag-server:8081`.
   - **In-container reverse proxy.** Your container fronts an nginx (or
     equivalent) that rewrites selected paths to the backend URLs. For
     example, `/api/rag/* → http://rag-server:8081/v1/*` and
     `/api/vdb/* → http://ingestor-server:8082/v1/*`. The browser calls
     same-origin `/api/rag/*` paths.

Both patterns work. The SSR layer gives you the flexibility to reshape
responses, inject headers, and hide backend contracts from the browser;
the reverse proxy is simpler and matches what the upstream `rag-frontend`
effectively does internally.

---

## 7. Worked Examples

### 7.1 Browser — streaming chat against a same-origin server route

Assumes the skin runs a Node server with an `/api/chat/completions`
route that proxies to `rag-server`. The browser code is origin-relative
and works identically in production and dev.

```js
// Browser-side chat with SSE streaming.
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
      if (data === '[DONE]') return;
      try { onDelta(JSON.parse(data)); } catch { /* ignore partial frame */ }
    }
  }
}
```

### 7.2 Server — the Node API route (SSR pattern)

Runs inside the skin container, reads `VITE_API_CHAT_URL` at startup,
and streams the response back to the browser unchanged.

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
  // Pipe SSE stream straight through.
  for await (const chunk of upstream.body) res.write(chunk);
  res.end();
}
```

### 7.3 nginx reverse proxy (drop-in alternative to SSR)

A minimal `nginx.conf` that the skin container can use instead of an SSR
layer. Browser calls `/api/rag/*` and `/api/vdb/*`; nginx forwards them
in-cluster.

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

Then from the browser:

```js
await fetch('/api/rag/chat/completions', { method: 'POST', body: ... });
const status = await fetch(`/api/vdb/status?task_id=${taskId}`).then(r => r.json());
```

### 7.4 Uploading a document with async status polling

```js
// Browser — fire and poll. `/api/vdb/*` → ingestor-server.
async function uploadAndWait(file, collectionName) {
  const form = new FormData();
  form.append('documents', file);
  form.append('payload', JSON.stringify({
    collection_name: collectionName,
    blocking: false,
    generate_summary: true,
  }));

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
// Pull server defaults once at app start so sliders, model selectors,
// and feature toggles reflect what this deployment actually supports.
const config = await fetch('/api/rag/configuration').then(r => r.json());
// config.rag_configuration   — default temperature, top_p, max_tokens, …
// config.feature_toggles     — enable_reranker, enable_citations, …
// config.models              — model names in use (LLM, embedder, reranker)
// config.endpoints           — in-cluster URLs of upstream services (metadata only)
```

### 7.6 OpenAI SDK against `/v2/vector_stores/.../search`

Works because `/v1/chat/completions` is OpenAI-shaped and
`/v2/vector_stores/{id}/search` matches the OpenAI Vector Stores API.

```js
import OpenAI from 'openai';

const client = new OpenAI({
  baseURL: '/api/rag',                 // → http://rag-server:8081/v1 via proxy
  apiKey: 'unused',
  dangerouslyAllowBrowser: true,
});

const reply = await client.chat.completions.create({
  model: 'meta/llama-3.3-nemotron-super-49b',
  messages: [{ role: 'user', content: 'Summarize today\'s onboarding doc.' }],
  stream: true,
});

// Vector-store search through the /v2 surface.
const hits = await fetch('/api/rag/../v2/vector_stores/multimodal_data/search', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({ query: 'embedding latency', max_num_results: 5 }),
}).then(r => r.json());
```

---

## 8. What Is Not in the Contract

A skin must treat the following as internal and must not hard-code
assumptions against them. They exist in the cluster but are not part of
the pack's advertised surface, and they can change between chart
versions without notice.

| Surface                                                   | Why it is internal                                                                             |
|-----------------------------------------------------------|------------------------------------------------------------------------------------------------|
| `nim-llm:8000`, `nemoretriever-embedding-ms:8000`, `nemoretriever-ranking-ms:8000`, `nim-vlm:8000` | NIM microservices called by `rag-server`. Talking to them directly bypasses guardrails, citations, reflection, and metrics. |
| `nv-ingest-ms-runtime:7670`, `:7671`, `:8265`             | Ray extraction pipeline. `ingestor-server` is the abstraction layer; `:8265` is a developer Ray dashboard, not a product API. |
| `milvus:19530`, `milvus:9091`                             | Vector-store wire protocol. `VITE_MILVUS_URL` is exported for the upstream sample SPA only.    |
| `oracle-26ai:1521` (Autonomous DB)                        | Underlying Oracle vector store for `enterprise_rag`. Goes through `ingestor-server`.           |
| `minio:9010`, `:9011`                                     | S3-compatible blob store for multimodal content. Internal.                                     |
| `rag-redis-master:6379`                                   | Task queue for async ingestion. Poll via `/v1/status`, not Redis directly.                     |
| `nemo-guardrails-microservice:7331`                       | Optional content-safety filter. Invoked by `rag-server` when `enable_guardrails=true`.         |
| Corrino REST API (`/deployment/`, `/deploy/`, `/validate/`, `/workspace/`) | Control-plane API for recipe-based packs. Not involved in Helm packs; not exposed on the pack's public domain. |
| `corrino-configmap` values (`REGION_NAME`, `COMPARTMENT_ID`, `TENANCY_ID`, `TENANCY_NAMESPACE`) | Exist in the cluster for recipe-based packs (vss references them). The enterprise_rag Helm chart does not mount them into the frontend. |
| OpenTelemetry / Prometheus / Grafana / Zipkin             | Observability infrastructure. Disabled by default in the chart values.                         |
| `rag-server /v1/metrics`, `ingestor-server /v1/metrics`   | Prometheus scrape targets. Not a UI contract.                                                  |

If a skin finds itself needing one of these, the right move is to file a
chart issue upstream or add the capability to `rag-server` /
`ingestor-server` — not to call the internal service directly.

---

## 9. Source of Truth

| Concern                                                   | File / URL                                                                                                                  |
|-----------------------------------------------------------|-----------------------------------------------------------------------------------------------------------------------------|
| Terraform helm_release for the `rag` chart                | `ai-accelerator-tf/helm.tf:581-673`                                                                                         |
| Values file selector                                      | `ai-accelerator-tf/helm.tf:594-599`                                                                                         |
| Frontend image skin override                              | `ai-accelerator-tf/helm.tf:647-654`                                                                                         |
| Oracle 26ai credential injection (enterprise_rag only)    | `ai-accelerator-tf/helm.tf:612-630`, `656-666`                                                                              |
| Chart values (full stack config)                          | `ai-accelerator-tf/helm-values/enterprise-rag-values.yaml`                                                                  |
| — `rag-server` env vars                                   | `enterprise-rag-values.yaml:80-213`                                                                                         |
| — `ingestor-server` env vars                              | `enterprise-rag-values.yaml:258-342`                                                                                        |
| — `frontend.envVars` (VITE_*)                             | `enterprise-rag-values.yaml:384-392`                                                                                        |
| — `nim-llm`, `nv-ingest`, sub-NIM configs                 | `enterprise-rag-values.yaml:551-929`                                                                                        |
| Frontend ingress rule                                     | `ai-accelerator-tf/ingress.tf:150-191`                                                                                      |
| Skin catalog                                              | `ai-accelerator-tf/schemas/frontend_skins.yaml:44-51`                                                                       |
| Skin-override invariant test                              | `ai-accelerator-tf/schemas/tests/test_helm_skin_override.py`                                                                |
| Upstream Helm chart (NGC)                                 | https://helm.ngc.nvidia.com/nvidia/blueprint/charts/nvidia-blueprint-rag-v2.3.0.tgz                                         |
| Upstream chart endpoints reference (operator-level)       | `deploy/helm/nvidia-blueprint-rag/endpoints.md` (in the `nvidia-rag-oci` repo)                                              |
| `rag-server` FastAPI routes (implementation)              | `nvidia-rag-oci` — `src/nvidia_rag/rag_server/server.py`, `main.py`                                                         |
| `rag-server` API docs                                     | `nvidia-rag-oci` — `docs/api-rag.md`, `docs/api_reference/openapi_schema_rag_server.json`                                   |
| `ingestor-server` FastAPI routes (implementation)         | `nvidia-rag-oci` — `src/nvidia_rag/ingestor_server/server.py`, `main.py`                                                    |
| `ingestor-server` API docs                                | `nvidia-rag-oci` — `docs/api-ingestor.md`, `docs/api_reference/openapi_schema_ingestor_server.json`                         |
| Service/port/GPU reference (compose-level)                | `nvidia-rag-oci` — `docs/service-port-gpu-reference.md`                                                                     |
| Swagger UIs (reachable once a skin proxies `rag-server` / `ingestor-server`) | `rag-server` `/v1/docs`, `/v2/docs`; `ingestor-server` `/v1/docs`                                        |

---

## 10. When to Update This Doc

Manually maintained. No drift-check test against Terraform. Update
whenever you change any of:

- `ai-accelerator-tf/helm.tf` — the `rag` `helm_release` block,
  especially the `set` entries for `frontend.image.*` or any
  `envVars.*` / `ingestor-server.envVars.*` injection, or the chart URL
  / version in the `chart` argument.
- `ai-accelerator-tf/helm-values/enterprise-rag-values.yaml` — any
  change to `frontend.envVars`, `rag-server.envVars`,
  `ingestor-server.envVars`, or the `nim-llm` / `nv-ingest` sub-chart
  defaults that affects what the UI can call or rely on.
- `ai-accelerator-tf/ingress.tf` — the `enterprise_rag_frontend_ingress`
  rule (host, path, annotations, backend service).
- `ai-accelerator-tf/schemas/frontend_skins.yaml` — the `enterprise_rag`
  entry (`container_port`, `subdomain`, `image_uri`, any new skin keys).
- The upstream chart version — new NVIDIA chart releases occasionally
  rename endpoints, add query parameters, or change the
  `frontend.envVars` list. Spot-check `src/nvidia_rag/*/server.py` and
  `values.yaml` in the new chart against the tables in §3, §4, and §6.2.

### "When in doubt" rule

> Would a skin author need this to wire their frontend to rag-server or
> ingestor-server? If yes, document it here.
