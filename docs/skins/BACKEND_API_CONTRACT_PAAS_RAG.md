# paas_rag Pack — Backend API Contract

Companion document to `BACKEND_API_CONTRACT.md`. That file is the multi-pack
reference organized around skin-access *mechanisms* (ingress paths vs env
vars). This file is the paas_rag-pack-specific deep dive organized around
*backend services and their API surface* — what a skin author can actually
call.

Scope: `starter_pack_category = "paas_rag"`. For cuopt see
`BACKEND_API_CONTRACT_CUOPT.md`; for enterprise_rag see
`BACKEND_API_CONTRACT_ENTERPRISE_RAG.md`; for vss /
enterprise_rag_aiq see `BACKEND_API_CONTRACT.md` §3.2, §3.5.

---

## 1. Deployment Group Composition

paas_rag deploys a single **Corrino blueprint deployment group** to OKE,
composed of one backend service (`llamastack`) plus one frontend skin.
Source of truth: `ai-accelerator-tf/blueprint_files.tf` —
`local._paas_rag_small_blueprint` and `local._paas_rag_frontend_deployments`.

Unlike cuopt, there is **no GPU solver** in this pack: inference is
delegated to the managed OCI Generative AI service over the network, and
vector storage goes to a managed Oracle 26ai Autonomous Database
provisioned in parallel by Terraform. Everything that runs on the cluster
is CPU-only.

| Service          | Container image                                                               | Container port | GPU | Role                                                                                    |
|------------------|-------------------------------------------------------------------------------|----------------|-----|-----------------------------------------------------------------------------------------|
| `llamastack`     | `iad.ocir.io/iduyx1qnmway/corrino-devops-repository/llama-stack-oci:v0.0.3`   | 8321           | —   | Llama Stack server with OCI GenAI inference + Oracle 26ai vector store + OCI Object Storage file store. OpenAI-compatible API. |
| Skin             | Per entry in `schemas/frontend_skins.yaml` (default `oracle-net-frontend`)    | Per skin       | —   | User-facing HTTP frontend. One subdomain; adds `/v1/*` ingress prefixes back onto `llamastack`. |

**Resource shape (small and medium both resolve to `_paas_rag_small_blueprint`):**

- `llamastack`: 8 OCPU / 64 GB RAM on the CPU worker node pool, 1 replica, plus
  a 500 GB PVC (`ls-sqlite`) mounted at `/sqlite-store` for the embedded
  metadata / KV / SQL stores.
- Skin: 4 OCPU / 32 GB RAM, 1 replica, shared CPU worker node pool.

**Managed dependencies wired in by Terraform (outside the deployment group):**

| Dependency                 | How it is reached from `llamastack`                                                                            | Declared in                                             |
|----------------------------|-----------------------------------------------------------------------------------------------------------------|---------------------------------------------------------|
| OCI Generative AI (models) | `remote::oci` inference provider. Auth = OKE node's instance principal. Region = `var.genai_region`.           | `files/llamastack_paas_config.yaml:14-22`; env at `blueprint_files.tf:1486-1488` |
| Oracle 26ai Autonomous DB  | `remote::oci` vector_io provider. `OCI26AI_*` env vars carry the HIGH connection string + admin credentials.    | `files/llamastack_paas_config.yaml:23-34`; env at `blueprint_files.tf:1483-1485` |
| OCI Object Storage (S3-compat) | `remote::s3` files provider. S3-compat host, region, key ID, secret key, bucket.                           | `files/llamastack_paas_config.yaml:97-108`; env at `blueprint_files.tf:1490-1496` |

**Key facts:**

- The container image is built from this starter pack's companion repo
  (`oracle/oraclenet-llama-stack`). The image `ENTRYPOINT` is
  `llama stack run` and Corrino passes `["/config/config.yaml"]` as argv,
  which selects the config file mounted from the K8s Secret
  `llamastack-paas-config` at `/config` (see `recipe_secret_mounts` at
  `blueprint_files.tf:1507-1509`).
- **The runtime config is NOT the one baked into the image.** The image
  carries `src/llama_stack/distributions/oci/config.yaml` (inline::faiss,
  inline::localfs, llama-guard) as a default. The paas_rag deployment
  overrides it by mounting `ai-accelerator-tf/files/llamastack_paas_config.yaml`
  (remote::oci vector_io, remote::s3 files, safety disabled) as the
  `/config/config.yaml` the server actually reads.
- `llamastack` is a Kubernetes `ClusterIP` service at
  `port 80` → container `targetPort 8321`. External traffic reaches it via
  either (a) the frontend skin's stitched `/v1/*` ingress paths (Pattern 1),
  or (b) `llamastack`'s own Corrino-rendered ingress at
  `<canonical-name>.<fqdn>` (optionally API-key-gated — see §5.3).
- Enabled llama-stack APIs at runtime:
  `agents, datasetio, eval, files, inference, safety, scoring, tool_runtime, vector_io`
  (declared at `files/llamastack_paas_config.yaml:3-12`). Safety is listed
  in `apis:` but the safety provider block is commented out, so
  `/v1/safety/*` and `/v1/moderations` will return 501 / empty.
- Registered tool groups at boot:
  - `builtin::websearch` → Tavily (requires `TAVILY_SEARCH_API_KEY`, not
    set by default).
  - `builtin::rag` → inline rag-runtime.

---

## 2. Backend Service — `llamastack`

Llama Stack server (FastAPI, uvicorn) built with the OCI GenAI inference
adapter, the Oracle 26ai vector_io adapter, and the S3-compatible files
adapter. Because Llama Stack speaks the **OpenAI API schema** at `/v1/*`,
a skin author can treat it as an OpenAI-compatible server whose `baseURL`
is the frontend's own origin (Pattern 1, see §5.1).

- **In-cluster address:** `http://<llamastack.service_name>:80` (Service
  `port 80` → container `targetPort 8321`).
- **External address (via skin):** `https://frontend-paas.<fqdn>/v1/...`
  (Pattern 1; see §5.1).
- **External address (backend's own ingress):** `https://<llamastack-canonical>.<fqdn>/`
  (optionally API-key-gated; see §5.3).
- **URL prefix:** all routes are mounted under `/v1` (legacy `@webmethod`
  routes) or `/v1alpha` / `/v1beta` for experimental endpoints.
- **Container command args:** `["/config/config.yaml"]` (reads its provider
  config from the mounted Secret at `/config`).
- **Authoritative spec:** [OpenAI API reference](https://platform.openai.com/docs/api-reference)
  for the `/v1/{chat/completions, completions, embeddings, responses, files,
  vector_stores}` subset; Llama Stack project docs at
  [llama-stack.readthedocs.io](https://llama-stack.readthedocs.io/) for the
  non-OpenAI extensions (agents, tool_runtime, eval, scoring, …).
- **Source for route list (in this pack's companion repo):**
  - `src/llama_stack_api/inference/fastapi_routes.py`
  - `src/llama_stack_api/files/fastapi_routes.py`
  - `src/llama_stack_api/vector_io/fastapi_routes.py`
  - `src/llama_stack_api/agents/fastapi_routes.py`
  - `src/llama_stack_api/openai_responses.py`
  - `src/llama_stack_api/safety/fastapi_routes.py`
- **OpenAPI / Swagger:** `GET /v1/docs`, `GET /v1/openapi.json` (served by
  the FastAPI app at runtime; reachable through the skin's `/v1` catch-all).

### 2.1 OpenAI-compatible inference

The primary LLM surface. Backed by `remote::oci` → OCI Generative AI. The
set of usable `model` values is whatever OCI GenAI exposes in the region
selected by `var.genai_region` — the pack does not pre-register any models
(`registered_resources.models: []`), so `GET /v1/models` returns the
provider's live listing.

| Method | Path                                      | Purpose                                                                                                                        |
|--------|-------------------------------------------|--------------------------------------------------------------------------------------------------------------------------------|
| POST   | `/v1/chat/completions`                    | OpenAI-shaped chat completion. Streams when `"stream": true` via Server-Sent Events (`text/event-stream`).                      |
| GET    | `/v1/chat/completions`                    | List past chat completions recorded by the server (see the `inference_store` entry in `files/llamastack_paas_config.yaml:122-126`). |
| GET    | `/v1/chat/completions/{completion_id}`    | Retrieve a past chat completion by id.                                                                                          |
| POST   | `/v1/completions`                         | Legacy text completion. Streaming semantics identical to chat.                                                                  |
| POST   | `/v1/embeddings`                          | OpenAI-shaped embeddings.                                                                                                       |
| GET    | `/v1/models`                              | List models available to this llamastack (pass-through to OCI GenAI).                                                           |
| GET    | `/v1/models/{model_id}`                   | Describe a specific model.                                                                                                      |
| POST   | `/v1alpha/inference/rerank`               | Rerank documents by relevance. Experimental (`v1alpha`) — not stitched onto the frontend ingress (see §2.6).                    |

Streaming format is SSE, one `data: <json>` line per chunk, terminated by
`data: [DONE]`. The stitched frontend ingress has no special nginx
annotations for SSE — Corrino's default `proxy_buffering: off` on its
backend ingresses works for SSE, but if a skin relies on browser SSE it
should test under load.

### 2.2 Files (S3-backed storage)

Upload, list, retrieve, and delete files that can later be attached to a
vector store. Backed by `remote::s3` against OCI Object Storage
(`S3_ENDPOINT_URL` is the per-region S3-compat host; `S3_BUCKET_NAME` is
the bucket Terraform provisions in `object_storage.tf`).

| Method | Path                            | Purpose                                                                                                |
|--------|---------------------------------|--------------------------------------------------------------------------------------------------------|
| POST   | `/v1/files`                     | Upload a file (multipart form, field name `file`). Returns an `OpenAIFileObject` with an `id`.          |
| GET    | `/v1/files`                     | List files. Query: `limit`, `order`, `after`, `before`, `purpose`.                                      |
| GET    | `/v1/files/{file_id}`           | Retrieve file metadata.                                                                                 |
| DELETE | `/v1/files/{file_id}`           | Delete a file.                                                                                          |
| GET    | `/v1/files/{file_id}/content`   | Download raw file content.                                                                              |

Files metadata lives in the `files_metadata` SQL table on the
llamastack-local SQLite store (`db_path = /sqlite-store/sql_store.db`,
set via `SQLITE_STORE_DIR`). Object bytes live in the OCI Object Storage
bucket.

### 2.3 Vector stores (Oracle 26ai)

OpenAI Vector Stores API, implemented by the `remote::oci` vector_io
provider against Oracle 26ai Autonomous Database. The primary RAG ingest
path for a skin is: `POST /v1/files` → `POST /v1/vector_stores` → `POST
/v1/vector_stores/{id}/files` → `POST /v1/vector_stores/{id}/search` (or
attach the vector store to a Responses API call for retrieval-augmented
generation).

| Method | Path                                                         | Purpose                                                                                                        |
|--------|--------------------------------------------------------------|----------------------------------------------------------------------------------------------------------------|
| POST   | `/v1/vector_stores`                                          | Create a vector store.                                                                                         |
| GET    | `/v1/vector_stores`                                          | List vector stores. Query: `limit`, `order`, `after`, `before`.                                                |
| GET    | `/v1/vector_stores/{vector_store_id}`                        | Retrieve a vector store.                                                                                       |
| POST   | `/v1/vector_stores/{vector_store_id}`                        | Update a vector store (`name`, `expires_after`, `metadata`).                                                   |
| DELETE | `/v1/vector_stores/{vector_store_id}`                        | Delete a vector store.                                                                                         |
| POST   | `/v1/vector_stores/{vector_store_id}/search`                 | Search a vector store. Supports `query`, `filters`, `max_num_results`, `ranking_options`, `rewrite_query`, `search_mode`. |
| POST   | `/v1/vector_stores/{vector_store_id}/files`                  | Attach a previously uploaded file (by `file_id`) to the vector store — this triggers chunking + embedding.     |
| GET    | `/v1/vector_stores/{vector_store_id}/files`                  | List files attached to a vector store. Query: `limit`, `order`, `after`, `before`, `filter` (by status).       |
| GET    | `/v1/vector_stores/{vector_store_id}/files/{file_id}`        | Retrieve a specific vector-store file (includes status, error info, chunking strategy).                        |
| GET    | `/v1/vector_stores/{vector_store_id}/files/{file_id}/content`| Retrieve the raw chunks + optional embeddings / metadata. Query: `include_embeddings`, `include_metadata`.     |
| POST   | `/v1/vector_stores/{vector_store_id}/files/{file_id}`        | Update a vector-store file (e.g. attributes).                                                                  |
| DELETE | `/v1/vector_stores/{vector_store_id}/files/{file_id}`        | Detach a file from a vector store.                                                                             |
| POST   | `/v1/vector_stores/{vector_store_id}/file_batches`           | Batch-attach files. Honors `max_concurrent_files_per_batch` and `file_batch_chunk_size` from the config.       |

Chunking, retrieval, and citation behavior is tuned in the
`vector_stores:` block of the runtime config
(`files/llamastack_paas_config.yaml:146-192`): default chunk size 512 tokens,
overlap 128, RRF reranker with impact factor 60, max context 4000 tokens,
citations enabled with `<|file-id|filename|>` format.

Low-level chunk API exists (`/v1/vector-io/insert`, `/v1/vector-io/query`)
but is *not* stitched onto the frontend ingress and should not be called
by a skin — see §2.7.

### 2.4 Responses API (primary chat-with-retrieval surface)

The OpenAI Responses API is the pack's advertised primary chat endpoint,
and it is the path-stitched one the skin's frontend should prefer. It
supports tool calling (including the file-search tool that queries a
vector store), built-in toolgroups (`builtin::websearch`, `builtin::rag`),
and streaming.

| Method | Path                                 | Purpose                                                                       |
|--------|--------------------------------------|-------------------------------------------------------------------------------|
| POST   | `/v1/responses`                      | Create a response (optionally streaming, with tools).                         |
| GET    | `/v1/responses`                      | List responses on the server (from the `responses` SQL table).                |
| GET    | `/v1/responses/{response_id}`        | Retrieve a response by id.                                                    |
| DELETE | `/v1/responses/{response_id}`        | Delete a response.                                                            |
| GET    | `/v1/responses/{response_id}/input_items` | Retrieve the input items that produced a response.                        |

Persistence: the `responses` SQL table in the llamastack-local SQL store
(`files/llamastack_paas_config.yaml:45-49`).

### 2.5 Health and metadata

| Method | Path              | Purpose                                                                                          |
|--------|-------------------|--------------------------------------------------------------------------------------------------|
| GET    | `/v1/health`      | Liveness. Returned as a plain OK response; no auth. Public route (`PUBLIC_ROUTE_KEY = x-public`).|
| GET    | `/v1/version`     | Server version.                                                                                  |
| GET    | `/v1/inspect/routes` | Registered routes (introspection).                                                            |
| GET    | `/v1/providers`   | List provider instances (inference, vector_io, files, agents, ...).                              |
| GET    | `/v1/providers/{provider_id}` | Provider details.                                                                   |

### 2.6 Additional Llama Stack endpoints under `/v1`

Llama Stack also exposes non-OpenAI routes that are reachable through the
frontend skin's `/v1` catch-all prefix. These are not explicitly
listed in `_paas_rag_frontend_deployments`, but because the last ingress
entry is `path = "/v1", path_type = "Prefix"`, every `/v1/*` path the
llamastack server registers is forwarded. The core extras (not exhaustive —
see `src/llama_stack_api/*/fastapi_routes.py`):

| Namespace                       | Representative routes                                                     | Notes                                                       |
|---------------------------------|---------------------------------------------------------------------------|-------------------------------------------------------------|
| Conversations                   | `POST /v1/conversations`, `GET /v1/conversations/{id}`                    | Persisted in the `openai_conversations` SQL table.          |
| Agents                          | `POST /v1/agents`, `POST /v1/agents/{id}/sessions`                        | `meta-reference` provider; state in `agents` KV.            |
| Tool runtime                    | `POST /v1/tool-runtime/invoke`, `GET /v1/tool-runtime/list-tools`         | Deprecated `/v1/toolgroups` and `/v1/tools` also still present (see `src/llama_stack_api/tools.py`). |
| Eval                            | `POST /v1/eval/benchmarks/{benchmark_id}/jobs`, `GET /v1/eval/...`        | Dev/test surface, not intended for production UIs.          |
| Scoring                         | `POST /v1/scoring/score`, `POST /v1/scoring/score-batch`                  | Dev/test surface.                                           |
| Shields                         | `GET /v1/shields`, `POST /v1/shields`, `DELETE /v1/shields/{id}`          | Safety provider is disabled in paas_rag — routes resolve but no shields run. |
| Safety                          | `POST /v1/safety/run-shield`, `POST /v1/moderations`                      | Same caveat as above.                                       |
| Batches                         | `POST /v1/batches`, `GET /v1/batches`, `GET /v1/batches/{id}`             | Experimental.                                               |

A skin that sticks to the explicitly stitched paths (`/v1/models`,
`/v1/health`, `/v1/responses`, `/v1/vector_stores`, `/v1/files`) plus the
`/v1` catch-all is future-proof against the ordering quirk noted in §5.1.

### 2.7 Endpoints not to call from a skin

- **`/v1/vector-io/insert`, `/v1/vector-io/query`** — low-level chunk
  insert / query. Bypasses file-based chunking, attribute filters, and
  citation formatting. Use `/v1/vector_stores/{id}/files` and
  `/v1/vector_stores/{id}/search` instead.
- **`/v1alpha/*` and `/v1beta/*`** — experimental surfaces. Not stitched
  onto the frontend ingress and may change without notice. `/v1alpha/inference/rerank`
  is the only one likely to tempt skin authors; if you need reranking,
  rely on the vector store's built-in reranker
  (`files/llamastack_paas_config.yaml:186-188`) rather than calling the
  endpoint directly.
- **`/v1/metrics`** (if enabled in a future release) — Prometheus scrape
  target, not a UI contract.
- **`/v1/safety/*`, `/v1/moderations`, `/v1/shields/*`** — the safety
  provider is commented out in the paas_rag config, so these routes
  return empty / error. Do not wire a skin to expect them.
- **`/v1/eval/*`, `/v1/scoring/*`, `/v1/datasets/*`, `/v1/datasetio/*`,
  `/v1/post_training/*`, `/v1/benchmarks/*`** — developer / research
  surfaces. They work, but they are not a product contract for a
  user-facing skin.

---

## 3. Frontend Skins (Catalog)

paas_rag ships one skin (default enabled).

| Skin     | `variable_name`       | `container_port` | `subdomain`      | Image                                                                                      |
|----------|-----------------------|------------------|------------------|--------------------------------------------------------------------------------------------|
| Core App | `skin_paas_rag_core`  | 3000             | `frontend-paas`  | `iad.ocir.io/iduyx1qnmway/corrino-devops-repository/oracle-net-frontend:v0.0.3`            |

Ingress host: `https://frontend-paas.<fqdn>`. `<fqdn>` resolves to the
generated `nip.io` domain (default) or a user-supplied FQDN if
`use_custom_dns = true`. Source:
`ai-accelerator-tf/schemas/frontend_skins.yaml:33-42`.

---

## 4. Managed Dependencies (Provisioned Alongside the Blueprint)

These are *not* deployments in the Corrino blueprint group, but a skin
cannot be reasoned about without them.

| Resource                       | Provisioned by                                           | How `llamastack` reaches it                                                                                |
|--------------------------------|----------------------------------------------------------|-------------------------------------------------------------------------------------------------------------|
| Oracle 26ai Autonomous DB      | `ai-accelerator-tf/26ai.tf` (ADB resource + HIGH wallet) | `OCI26AI_CONNECTION_STRING` (HIGH TNS alias), `OCI26AI_USER = var.db_username`, `OCI26AI_PASSWORD = var.db_password`. Walletless via `oracledb` thick client defaults. |
| OCI Object Storage bucket      | `ai-accelerator-tf/object_storage.tf`                    | `S3_ENDPOINT_URL` = regional S3-compat host, `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` = customer secret keys, `S3_BUCKET_NAME` = bucket name. |
| OCI Generative AI service      | Managed by OCI; selected via `var.genai_region`          | `OCI_COMPARTMENT_OCID`, `OCI_REGION`, `OCI_AUTH_TYPE=instance_principal` — llamastack pod uses the OKE node's instance-principal identity. |

Environment variables reaching `llamastack` at deploy time:
`blueprint_files.tf:1482-1497`. Mounted Secret carrying the runtime
config: `blueprint_files.tf:1507-1509`, declared in
`llamastack_config.tf:6-18`.

**None of the above managed dependencies is advertised to a skin.** A
skin never calls Oracle 26ai, OCI Object Storage, or OCI GenAI directly.
All access flows through `llamastack`'s `/v1/*` endpoints.

---

## 5. How a Skin Reaches the Backend

Only Pattern 1 (ingress path routing) is wired. Pattern 2 (env-var
injection) is not used for this pack — the `_paas_rag_frontend_deployments`
list comprehension declares no `recipe_container_env`.

### 5.1 Pattern 1 — Same-host ingress path routing (browser-safe)

The skin's own ingress has these additional `pathType: Prefix` rules
stitched onto it. A **relative** `fetch()` from the browser is routed
in-cluster by nginx — same origin, no CORS headers required.

| Path prefix on skin host | Backend service | Port | Notes                                                                            |
|--------------------------|-----------------|------|----------------------------------------------------------------------------------|
| `/v1/models`             | `llamastack`    | 8321 | List models available to this llamastack.                                        |
| `/v1/health`             | `llamastack`    | 8321 | Liveness; public route (no auth).                                                |
| `/v1/responses`          | `llamastack`    | 8321 | OpenAI Responses API (primary chat surface).                                     |
| `/v1/vector_stores`      | `llamastack`    | 8321 | Vector-store CRUD + search + file attachment.                                    |
| `/v1/files`              | `llamastack`    | 8321 | File upload / list / retrieve / delete / content download.                       |
| `/v1`                    | `llamastack`    | 8321 | Catch-all for any other `/v1/*` path (chat/completions, completions, embeddings, conversations, agents, …). |

Source: `ai-accelerator-tf/blueprint_files.tf:1449-1456`.

**Path ordering.** The more-specific paths are listed before `/v1` in the
Terraform source. With `pathType: Prefix` matching, nginx-ingress uses the
longest-match rule, so `/v1/models` goes to the `models` entry and every
other `/v1/*` call falls through to the `/v1` catch-all entry. There is
**no double-nesting** — the path is forwarded unchanged.

No `rewrite-target` annotation is applied — the full URL path is forwarded
to the backend.

### 5.2 Pattern 2 — Not available

Unlike cuopt, paas_rag does not inject `LLAMASTACK_ENDPOINT` (or anything
else) into the skin container. The skin has no server-side in-cluster URL
to call; everything must go through the browser's same-origin
`fetch('/v1/...')` via the paths in §5.1. If the skin needs to reach
`llamastack` from a server-side Node / SSR handler, it can reach the
in-cluster DNS name directly (`http://<llamastack.service_name>:80`), but
that name has to be discovered at runtime — a skin typically shouldn't
need to.

### 5.3 Optional API-key gating on the backend's own ingress

Each Corrino recipe is rendered into its own Kubernetes Ingress keyed on
the recipe's canonical name (see
`corrino/api/manifests/templates/recipe_ingress_template.yaml`;
`corrino/api/control_plane/digest.py:860-898` for subdomain resolution
when `service_endpoint_subdomain` is not set). That means `llamastack`
has a standalone HTTPS host of the form
`https://<llamastack-canonical>.<fqdn>/` in addition to its in-cluster
ClusterIP. The `_paas_rag_frontend_deployments` list does not declare a
subdomain for the backend, so the subdomain defaults to the canonical
name Corrino assigns at deploy time.

When `var.add_api_key_to_ingress = true`, the `llamastack` recipe inherits
two nginx annotations threaded in via
`local.backend_ingress_annotations_corrino`
(`blueprint_files.tf:1472`):

| Annotation                                   | Value                                                                                     |
|----------------------------------------------|-------------------------------------------------------------------------------------------|
| `nginx.ingress.kubernetes.io/auth-url`       | `http://ingress-api-key-validator.cluster-tools.svc.cluster.local/auth`                   |
| `nginx.ingress.kubernetes.io/auth-method`    | `GET`                                                                                     |

The validator (`ai-accelerator-tf/app-ingress-auth.tf`) is a minimal
nginx pod that returns 200 when the inbound request carries
`Authorization: Bearer <var.ingress_api_key>` and 401 otherwise. This
protects the backend's own hostname but **does not** protect the
stitched `/v1/*` paths on the frontend host — the frontend is classified
as an "open" ingress in `app-ingress-auth.tf:6-13`. Skin authors
consuming via Pattern 1 should therefore not expect Bearer-token auth on
`/v1/*` calls made from the skin's subdomain.

Frontend ingress (`frontend-paas.<fqdn>`): no auth annotation, no API
key. Backend ingress (`<llamastack-canonical>.<fqdn>`): API-key-gated
when the flag is on. See `docs/API_TOKENS.md` for the token model.

---

## 6. Worked Examples

All examples assume the skin is running behind `frontend-paas.<fqdn>` and
that the browser calls its own origin (Pattern 1).

### 6.1 Browser — list models and get a chat response

```js
// Health probe; public, no auth.
const ok = await fetch('/v1/health').then(r => r.ok);

// Model list.
const models = await fetch('/v1/models').then(r => r.json());
const modelId = models.data[0].id;

// One-shot chat completion (OpenAI-shaped).
const reply = await fetch('/v1/chat/completions', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({
    model: modelId,
    messages: [{ role: 'user', content: 'Summarize our onboarding docs.' }],
  }),
}).then(r => r.json());
```

### 6.2 Browser — streaming chat via the Responses API

The Responses API is the advertised primary chat surface. Streaming uses
SSE, one JSON object per `data:` line, terminated by `[DONE]`.

```js
async function streamResponse(input, onDelta) {
  const resp = await fetch('/v1/responses', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      model: 'cohere.command-r-plus',   // whatever GET /v1/models returns
      input,
      stream: true,
    }),
  });
  if (!resp.ok) throw new Error(`llamastack ${resp.status}`);

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

### 6.3 Browser — upload a file and attach it to a vector store

```js
// Step 1: upload the file.
const form = new FormData();
form.append('file', file);
form.append('purpose', 'assistants');
const uploaded = await fetch('/v1/files', { method: 'POST', body: form })
  .then(r => r.json());
const fileId = uploaded.id;

// Step 2: create (or reuse) a vector store.
const store = await fetch('/v1/vector_stores', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({ name: 'onboarding-docs' }),
}).then(r => r.json());

// Step 3: attach the file — this triggers chunking + embedding.
await fetch(`/v1/vector_stores/${store.id}/files`, {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({ file_id: fileId }),
});

// Step 4: poll until status is 'completed'.
async function waitReady(storeId, fileId) {
  while (true) {
    const f = await fetch(`/v1/vector_stores/${storeId}/files/${fileId}`)
      .then(r => r.json());
    if (f.status === 'completed') return f;
    if (f.status === 'failed')    throw new Error(f.last_error?.message ?? 'failed');
    await new Promise(res => setTimeout(res, 2000));
  }
}
await waitReady(store.id, fileId);
```

### 6.4 Browser — retrieve chunks (direct search) and RAG (via Responses)

```js
// (a) Direct vector-store search — returns ranked chunks.
const hits = await fetch(`/v1/vector_stores/${storeId}/search`, {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({
    query: 'password reset procedure',
    max_num_results: 5,
  }),
}).then(r => r.json());

// (b) RAG via Responses — llamastack retrieves, composes context, generates.
const answer = await fetch('/v1/responses', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({
    model: modelId,
    input: 'How does a user reset their password?',
    tools: [{ type: 'file_search', vector_store_ids: [storeId] }],
  }),
}).then(r => r.json());
```

### 6.5 OpenAI SDK (browser) — point `baseURL` at the same origin

Because the pack stitches `/v1/*` onto the skin's host, an unmodified
OpenAI SDK works with `baseURL: '/v1'`. Key caveat: the `apiKey` is
ignored by llamastack for Pattern 1 traffic, but the SDK requires *some*
non-empty string.

```js
import OpenAI from 'openai';

const client = new OpenAI({
  baseURL: '/v1',
  apiKey: 'unused',
  dangerouslyAllowBrowser: true,
});

// Works — hits llamastack via the /v1/chat/completions stitch.
const reply = await client.chat.completions.create({
  model: 'cohere.command-r-plus',
  messages: [{ role: 'user', content: 'Hello, world.' }],
});

// Works — hits /v1/vector_stores/.../search.
const res = await client.vectorStores.search(storeId, {
  query: 'onboarding',
  max_num_results: 3,
});
```

### 6.6 curl — verify from an admin workstation via the backend's own hostname

Assumes `var.add_api_key_to_ingress = true` and the deployer has the
effective key.

```bash
LLAMA=https://<llamastack-canonical>.<fqdn>      # from deploy output / kubectl get ing
KEY=<effective ingress_api_key>

# Protected by the API-key validator (§5.3).
curl -s -H "Authorization: Bearer $KEY" $LLAMA/v1/health
# Public route inside llamastack — but the ingress auth-url still applies.

curl -s -H "Authorization: Bearer $KEY" $LLAMA/v1/models | jq .
```

When `var.add_api_key_to_ingress = false` the `Authorization` header is
unnecessary; the backend hostname is then open (within network ACLs).

---

## 7. What Is Not in the Contract

A skin must treat the following as internal and must not hard-code
assumptions against them. They exist in the deployment but are not part
of the pack's advertised frontend surface.

| Surface                                                                             | Why it is internal                                                                                             |
|-------------------------------------------------------------------------------------|-----------------------------------------------------------------------------------------------------------------|
| Oracle 26ai Autonomous DB (TNS / sqlnet directly)                                   | Vector store. Goes through `llamastack`'s `/v1/vector_stores` and `/v1/files` endpoints.                         |
| OCI Object Storage (S3-compat API, `customer-oci.com` host)                         | Blob store for uploaded files. Goes through `/v1/files`. `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` live only on the pod. |
| OCI Generative AI service (direct `GenerativeAI` API calls)                         | Upstream inference provider. `llamastack` fronts it; skins use `/v1/chat/completions`, `/v1/embeddings`, etc.    |
| `llamastack` ClusterIP (`<llamastack.service_name>:80`)                             | In-cluster only. Nothing external should be wired to the service name.                                          |
| `llamastack` backend ingress (`<llamastack-canonical>.<fqdn>`)                      | Operational / admin surface — API-key-gated when enabled. Skins should not cross-origin it; use Pattern 1 paths. |
| `/v1/vector-io/insert`, `/v1/vector-io/query`                                       | Low-level chunk API. Use the OpenAI Vector Stores API instead.                                                   |
| `/v1alpha/*`, `/v1beta/*`                                                           | Experimental endpoints. Not stitched onto the frontend ingress.                                                  |
| `/v1/safety/*`, `/v1/moderations`, `/v1/shields/*`                                  | Safety provider is disabled in the runtime config. Routes exist but do nothing meaningful.                       |
| `/v1/eval/*`, `/v1/scoring/*`, `/v1/datasets/*`, `/v1/datasetio/*`, `/v1/post_training/*`, `/v1/benchmarks/*` | Developer / research surfaces. Not a product contract for a user-facing skin.                            |
| `/v1/metrics` (if enabled in a future release)                                      | Prometheus scrape target. Not a UI contract.                                                                     |
| The `llamastack-paas-config` K8s Secret (`/config/config.yaml`)                     | Provider configuration. Read-only from the pod; edited only by Terraform.                                        |
| The 500 GB `ls-sqlite` PVC at `/sqlite-store`                                       | Persistent metadata / KV / SQL store. No API exposes it directly; retained only between rolling restarts (`retain_after_undeploy = false`). |
| Corrino REST API (`/deployment/`, `/deploy/`, `/validate/`, `/workspace/`)          | Control-plane API for the starter pack. Not exposed on the pack's public domain.                                 |
| `corrino-configmap` values (`REGION_NAME`, `COMPARTMENT_ID`, `TENANCY_ID`, `TENANCY_NAMESPACE`) | Exist in the cluster for other packs (vss). The paas_rag skin does not mount them.                       |
| Tavily / Brave search API keys                                                      | The `builtin::websearch` toolgroup is registered but has no default key (`TAVILY_SEARCH_API_KEY` / `BRAVE_SEARCH_API_KEY` are unset unless the operator sets them). Don't document web-search as a contract. |

If a skin finds itself needing one of these, the right move is to add the
capability to `llamastack` (chart PR upstream, new provider, new route),
not to call the internal service directly.

---

## 8. Source of Truth

| Concern                                               | File                                                                                                                         |
|-------------------------------------------------------|------------------------------------------------------------------------------------------------------------------------------|
| Deployment group definition (llamastack + skin)       | `ai-accelerator-tf/blueprint_files.tf` — `local._paas_rag_small_blueprint` (lines 1462–1518) and `local._paas_rag_frontend_deployments` (lines 1433–1460) |
| Size → blueprint mapping                              | `ai-accelerator-tf/blueprint_files.tf:20-24`                                                                                 |
| Ingress path stitching                                | `ai-accelerator-tf/blueprint_files.tf:1449-1456`                                                                             |
| Runtime llamastack config (mounted as Secret)         | `ai-accelerator-tf/files/llamastack_paas_config.yaml`                                                                         |
| Secret resource                                       | `ai-accelerator-tf/llamastack_config.tf:6-18`                                                                                 |
| Container env wiring                                  | `ai-accelerator-tf/blueprint_files.tf:1482-1497`                                                                             |
| Oracle 26ai provisioning                              | `ai-accelerator-tf/26ai.tf`                                                                                                  |
| OCI Object Storage bucket                             | `ai-accelerator-tf/object_storage.tf`                                                                                        |
| Skin catalog                                          | `ai-accelerator-tf/schemas/frontend_skins.yaml:33-42`                                                                        |
| Backend ingress API-key annotations                   | `ai-accelerator-tf/app-ingress-auth.tf`                                                                                      |
| Pack schema (ORM form)                                | `ai-accelerator-tf/schemas/paas_rag_schema.yaml`                                                                             |
| Llama-stack container image source                    | `oracle/oraclenet-llama-stack` — `Dockerfile`, `src/llama_stack/distributions/oci/config.yaml` (baked default, overridden at deploy) |
| Container build pipeline                              | `oracle/oraclenet-llama-stack` — `.github/workflows/build-push-main.yml` (main → `:VERSION`), `build-push-pr.yml` (PR → `:pr-<shortsha>`) |
| Llama-stack FastAPI route implementations             | `oracle/oraclenet-llama-stack` — `src/llama_stack_api/{inference,files,vector_io,agents,safety,eval,scoring}/fastapi_routes.py`; `src/llama_stack_api/openai_responses.py`; `src/llama_stack_api/tools.py` |
| Corrino ingress template (per-recipe)                 | `corrino/api/manifests/templates/recipe_ingress_template.yaml`                                                               |
| Corrino subdomain-resolution logic                    | `corrino/api/control_plane/digest.py:859-898`                                                                                |
| OpenAI API schema reference                           | https://platform.openai.com/docs/api-reference                                                                               |
| Llama Stack docs                                      | https://llama-stack.readthedocs.io/                                                                                          |
| Swagger (reachable through the skin's `/v1` catch-all)| `/v1/docs`, `/v1/openapi.json`                                                                                               |

---

## 9. When to Update This Doc

Manually maintained. No drift-check test against Terraform. Update
whenever you change any of:

- `ai-accelerator-tf/blueprint_files.tf` — any edit to
  `local._paas_rag_small_blueprint` (image tag, env vars, container port,
  secret mounts, PVC size) or
  `local._paas_rag_frontend_deployments` (ingress path set,
  `container_port`, `depends_on`).
- `ai-accelerator-tf/files/llamastack_paas_config.yaml` — any change to
  the `apis:`, `providers:`, `tool_groups:`, or `vector_stores:` blocks
  that adds, removes, or renames a route a skin can call.
- `ai-accelerator-tf/llamastack_config.tf` — changes to the Secret
  structure (e.g. mounting a second config file at a new path).
- `ai-accelerator-tf/schemas/frontend_skins.yaml` — changes to the
  paas_rag skin entries (`container_port`, `subdomain`, `image_uri`,
  new skin keys).
- `ai-accelerator-tf/26ai.tf` or `ai-accelerator-tf/object_storage.tf` —
  changes to how the managed dependencies are reachable that flip an
  env var the llamastack pod depends on.
- The upstream `oracle/oraclenet-llama-stack` `VERSION` — when this bumps,
  the image tag on `blueprint_files.tf:1480` has to move in lockstep;
  spot-check `src/llama_stack_api/*/fastapi_routes.py` against the tables
  in §2 for any route renames.

### "When in doubt" rule

> Would a skin author need this to wire their frontend to `/v1/*` on
> `frontend-paas.<fqdn>`? If yes, document it here.

---

## 10. Open Questions

Two things in this document are grounded in code but cannot be verified
all the way down to the wire without deploying the pack. They are flagged
here so that future edits can close them when a concrete deployment is at
hand.

1. **Exact hostname of `llamastack`'s own backend ingress.** §5.3 claims
   the llamastack recipe gets a standalone `https://<canonical>.<fqdn>/`
   host because Corrino's digest
   (`corrino/api/control_plane/digest.py:859-898`) falls back to the
   canonical name when `service_endpoint_subdomain` is absent, and
   `_paas_rag_small_blueprint` does not set that field. What the
   canonical name actually resolves to (probably `llamastack` or a
   Corrino-derived variant) can only be confirmed by inspecting a live
   `kubectl get ingress` after deploy. If an operator wants to pin the
   host, add `service_endpoint_subdomain = "llamastack"` to the recipe
   in `blueprint_files.tf:1467-1512`.

2. **Behavior of the `/v1/safety/*`, `/v1/moderations`, `/v1/shields/*`
   routes when the safety provider is disabled.** The paas_rag runtime
   config (`files/llamastack_paas_config.yaml:35-39`) has the safety
   provider block commented out, but the `safety` API is still listed
   under `apis:`. Whether the routes return `501 Not Implemented`,
   `404 Not Found`, an empty success, or a server error depends on llama-stack
   internals that vary by release. §2.7 documents the safe rule
   ("do not wire a skin to expect them") without pinning the exact
   status. If the behavior matters for a skin, test it against the
   deployed build rather than inferring from the config alone.
