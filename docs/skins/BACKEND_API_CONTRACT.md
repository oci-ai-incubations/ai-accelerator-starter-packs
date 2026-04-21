# Backend API Contract for Skin Authors

> Status: under construction. Sections are being filled in.

## 1. Orientation

A **skin** is a frontend container you build and run inside an AI Accelerator
starter pack. This document specifies what the pack exposes to your skin and
how your skin reaches the pack's backend services. Read `README.md` for the
skin catalog and `ARCHITECTURE.md` for how the selection system works; read
this document when you are writing frontend code.

### What the pack guarantees

- Your skin's container starts with the image URI and tag you declare in
  `ai-accelerator-tf/schemas/frontend_skins.yaml`.
- Your skin must listen on the `container_port` you declared. Ingress
  routes HTTPS traffic from `https://<subdomain>.<fqdn>` to that port
  inside your container. The ingress host is assigned by the pack —
  `<fqdn>` is `local.fqdn.name` in Terraform (either the generated
  nip.io / corrino domain or your Custom DNS domain).

### How your skin reaches the backend

Two mechanisms are in play across the five packs. A given pack uses one of
them per backend; you pick the call style your frontend code uses based on
what the pack provides.

- **Pattern 1 — Same-host ingress path routing.** The pack attaches
  additional path prefixes (for example `/v1/models`) to your skin's
  ingress, so a call to `fetch('/v1/models')` from the browser reaches a
  backend service. Your browser calls your own origin; nginx does the
  internal routing. Browser-safe — same origin, so CORS and auth cookies
  are free.
- **Pattern 2 — In-cluster service endpoints via env vars.** The pack
  injects environment variables (`CUOPT_ENDPOINT`, `VSS_API_BASE_URL`,
  etc.) whose values are `http://<service>:<port>` URLs reachable from
  inside the cluster. Use these for server-side code (a Node API route,
  an SSR handler). These URLs resolve only inside the cluster — the
  user's browser cannot reach them.

### How to use this document

- **Building a new skin from scratch:** read this page top-to-bottom.
  §2 shows the two fetch patterns with code. §3 has your pack-specific
  details.
- **Looking up a specific endpoint:** jump to your pack in §3. Each pack
  has two lookup tables (ingress paths and env vars) plus a worked
  example.

## 2. Common Patterns

### Pattern 1 — Same-host ingress path routing

Your skin calls its own origin with a path prefix that the pack routes to a
backend service.

```js
// Browser-side fetch — works in any skin that has matching ingress paths.
const r = await fetch('/v1/models');
const models = await r.json();
```

The URL is **relative** (no protocol, no host). Works because the pack
stitched `/v1/models` onto the skin's own ingress subdomain (same origin,
so CORS and auth cookies are free). Example skin: paas_rag. See §3 for
the full path set each pack publishes.

### Pattern 2 — In-cluster service endpoints via env vars

Your skin reads an env var set by the pack at container start, whose value
is an internal service URL.

```js
// Server-side (Node API route, SSR handler) — NOT reachable from the browser.
const r = await fetch(`${process.env.LLAMASTACK_ENDPOINT}/v1/models`);
const models = await r.json();
```

The URL is **absolute** (`http://<service>:<port>`), has no TLS, and
resolves only inside the cluster. Env vars in Pattern 2 never point at
`https://...` external endpoints. Example skin: cuopt. See §3 for the
full env var set each pack injects.

### Which mechanism does each pack use?

| Pack               | Ingress paths | Env vars              |
|--------------------|---------------|-----------------------|
| cuopt              | ✓             | ✓                     |
| vss                | —             | ✓                     |
| paas_rag           | ✓             | —                     |
| enterprise_rag     | — (Helm)      | ✓ (Helm chart values) |
| enterprise_rag_aiq | — (Helm)      | — (chart-internal)    |

"(Helm)" means the mechanism is wired by a Helm chart, not by
Terraform-declared `recipe_additional_ingress_ports` or
`recipe_container_env`. Helm packs do not stitch API paths onto the
frontend subdomain; the frontend reaches backends only via in-cluster
service DNS names.

- For **enterprise_rag**, those DNS names are in `frontend.envVars` in
  `helm-values/enterprise-rag-values.yaml` (Pattern 2, documented in §3.4).
- For **enterprise_rag_aiq**, the user-facing frontend is shipped by the
  `aiq-aira` chart with no `frontend.envVars` list in the values file —
  endpoints are chart-internal. See §3.5.

## 3. Per-Pack Contract

### 3.1 cuopt (Vehicle Delivery Route Optimizer)

#### Catalog summary

cuopt ships two skins; either or both may be enabled simultaneously. Each
enabled skin runs as its own container with its own subdomain.

| Skin                | `variable_name`       | `container_port` | `subdomain`             |
|---------------------|-----------------------|------------------|-------------------------|
| Core App            | `skin_cuopt_core`     | 3001             | `demo-cuopt`            |
| Partner Contributed | `skin_cuopt_partner`  | 80               | `demo-cuopt-partner`    |

Ingress host: `https://<subdomain>.<fqdn>`. Catalog source:
`ai-accelerator-tf/schemas/frontend_skins.yaml`.

#### Outbound — ingress paths (Pattern 1)

Every enabled skin's ingress has these additional path prefixes. All
`path_type: Prefix`.

| Path prefix | Backend service   | Port | Notes                                         |
|-------------|-------------------|------|-----------------------------------------------|
| `/cuopt`    | cuopt solver      | 5000 | NVIDIA cuOpt Vehicle Routing API.             |
| `/v1`       | llamastack        | 8321 | LlamaStack base URL — `/v1/models`, etc.     |

#### Outbound — env vars (Pattern 2)

| Env var                 | Value format                  | Points to                                  |
|-------------------------|-------------------------------|--------------------------------------------|
| `CUOPT_ENDPOINT`        | `http://<cuopt-svc>:80`       | cuopt solver, inside-cluster.              |
| `LLAMASTACK_ENDPOINT`   | `http://<llamastack-svc>:80`  | llamastack, inside-cluster.                |
| `LLAMASTACK_MODEL`      | empty string (`""`)           | Model name override; left empty by default.|
| `GOOGLE_MAPS_API_KEY`   | user-supplied                 | Map rendering; pass-through from ORM.      |
| `ADMIN_USERNAME`        | user-supplied                 | UI admin user.                             |
| `ADMIN_PASSWORD`        | user-supplied                 | UI admin password.                         |
| `NODE_ENV`              | `production`                  | Standard Node env flag.                    |
| `PORT`                  | matches `container_port`      | For Node apps that read `process.env.PORT`.|

The `<cuopt-svc>` and `<llamastack-svc>` placeholders resolve to the
Corrino-generated in-cluster K8s service names at container start.

#### Worked example

```js
// Browser — list LLM models via the pack's llamastack (Pattern 1).
const models = await fetch('/v1/models').then(r => r.json());

// Browser — submit a routing problem to cuopt (Pattern 1).
const resp = await fetch('/cuopt', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify(payload),
});

// Server-side (Next.js API route) — same call via env var (Pattern 2).
const resp = await fetch(`${process.env.CUOPT_ENDPOINT}/v1/solve`, {
  method: 'POST',
  body: JSON.stringify(payload),
});
```

#### Source of truth

`ai-accelerator-tf/blueprint_files.tf` — `local._cuopt_frontend_deployments`
list comprehension defines both the env vars and the ingress path set.

### 3.2 vss (Video Search and Summarization)

#### Catalog summary

vss ships one skin.

| Skin     | `variable_name`  | `container_port` | `subdomain`     |
|----------|------------------|------------------|-----------------|
| Core App | `skin_vss_core`  | 3000             | `vss-frontend`  |

Ingress host: `https://vss-frontend.<fqdn>`. Catalog source:
`ai-accelerator-tf/schemas/frontend_skins.yaml`.

#### Outbound — ingress paths (Pattern 1)

**This pack uses only Pattern 2; see below.** VSS is the one blueprint
pack whose frontend runs as a vanilla `kubernetes_deployment_v1` (not a
Corrino blueprint), with a single ingress rule at `/` only — no
`recipe_additional_ingress_ports`.

#### Outbound — env vars (Pattern 2)

Grouped by where the value comes from:

**From the per-skin `vss-oracle-ux-config` ConfigMap:**

| Env var                 | Value                                                           |
|-------------------------|-----------------------------------------------------------------|
| `VSS_API_BASE_URL`      | `http://<vss-backend-svc>:8000/` (dynamically resolved)         |
| `FILE_STORAGE_PATH`     | `/mnt/fss/cache` (FSS mount inside the pod)                     |
| `DOWNLOAD_SERVICE_URL`  | `http://vss-download-service:8080`                              |
| `VSS_BACKEND_DEPLOYMENT`| The Corrino deployment name of the VSS backend.                 |

**From the shared `corrino-configmap`** (present on every pack):

| Env var            | Notes                                                          |
|--------------------|----------------------------------------------------------------|
| `REGION_NAME`      | OCI region for this deployment.                                |
| `COMPARTMENT_ID`   | OCI compartment OCID.                                          |
| `TENANCY_ID`       | OCI tenancy OCID.                                              |
| `TENANCY_NAMESPACE`| OCI object-storage tenancy namespace.                          |

**Literal values** on the deployment:

| Env var             | Value                                                          |
|---------------------|----------------------------------------------------------------|
| `LOCAL`             | `false`                                                        |
| `NEXT_DEPLOYMENT_ID`| sha256 of the blueprint content (Next.js cache-buster).       |

**From the `vss-db-url` K8s Secret** (not a ConfigMap):

| Env var        | Value                                                                |
|----------------|----------------------------------------------------------------------|
| `DATABASE_URL` | Prisma connection string to the VSS Postgres database.               |

#### Worked example

```js
// Server-side — query the VSS backend for uploaded videos.
const videos = await fetch(
  `${process.env.VSS_API_BASE_URL}videos`
).then(r => r.json());

// Server-side — read a cached file off the FSS mount.
import { readFile } from 'node:fs/promises';
const bytes = await readFile(
  `${process.env.FILE_STORAGE_PATH}/my-video.mp4`
);

// Server-side — write via the Prisma client using DATABASE_URL.
// (Your ORM client reads process.env.DATABASE_URL on init.)
```

#### Source of truth

`ai-accelerator-tf/app-vss-oracle-ux.tf` — `env { ... }` blocks on the
`kubernetes_deployment_v1` resource, plus the per-skin `vss-oracle-ux-config`
ConfigMap and the `vss_db_url` K8s Secret declared in the same file.

### 3.3 paas_rag (Managed Enterprise Chat Agent)

#### Catalog summary

paas_rag ships one skin.

| Skin     | `variable_name`         | `container_port` | `subdomain`        |
|----------|-------------------------|------------------|--------------------|
| Core App | `skin_paas_rag_core`    | 3000             | `frontend-paas`    |

Ingress host: `https://frontend-paas.<fqdn>`. Catalog source:
`ai-accelerator-tf/schemas/frontend_skins.yaml`.

#### Outbound — ingress paths (Pattern 1)

All paths `path_type: Prefix`, all routed to the llamastack service at
port 8321. The more-specific paths are listed before `/v1` in the
Terraform source; with `Prefix` matching, the most-specific match wins, so
requests like `/v1/models` go to the `models` entry and other `/v1/*`
calls fall through to the catch-all `/v1` entry.

| Path prefix         | Backend service | Port | Notes                                |
|---------------------|-----------------|------|--------------------------------------|
| `/v1/models`        | llamastack      | 8321 | List models.                         |
| `/v1/health`        | llamastack      | 8321 | Health check endpoint.               |
| `/v1/responses`     | llamastack      | 8321 | OpenAI-compatible responses API.     |
| `/v1/vector_stores` | llamastack      | 8321 | Vector store CRUD.                   |
| `/v1/files`         | llamastack      | 8321 | File upload / list / delete.         |
| `/v1`               | llamastack      | 8321 | Catch-all for any other `/v1/*` path.|

#### Outbound — env vars (Pattern 2)

**This pack uses only Pattern 1; no env vars are injected into the frontend
container.** The `_paas_rag_frontend_deployments` list comprehension in the
Terraform source declares no `recipe_container_env`.

#### Worked example

```js
// Browser — health check.
const health = await fetch('/v1/health').then(r => r.json());

// Browser — list available models.
const models = await fetch('/v1/models').then(r => r.json());

// Browser — upload a file to the vector store pipeline.
const body = new FormData();
body.append('file', file);
await fetch('/v1/files', { method: 'POST', body });

// Browser — send a chat completion.
const reply = await fetch('/v1/responses', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({ model, input: prompt }),
}).then(r => r.json());
```

#### Source of truth

`ai-accelerator-tf/blueprint_files.tf` —
`local._paas_rag_frontend_deployments` list comprehension.

### 3.4 enterprise_rag (Self-Hosted Enterprise Chat Agent)

#### Catalog summary

enterprise_rag is a Helm-based pack. It ships one skin; the
`skin_enterprise_rag` ORM variable is an enum dropdown whose sole option
is the Core App skin today.

| Skin     | Enum variable          | `container_port` | `subdomain`         |
|----------|------------------------|------------------|---------------------|
| Core App | `skin_enterprise_rag`  | 3000             | `frontend-erag`     |

Ingress host: `https://frontend-erag.<fqdn>`. Catalog source:
`ai-accelerator-tf/schemas/frontend_skins.yaml`.

The catalog's `image_uri` is split into `frontend.image.{repository,tag}`
overrides applied to the `rag` Helm release by Terraform
(`ai-accelerator-tf/helm.tf` lines 647–654). For enterprise_rag, the
`rag` release's `rag-frontend` service IS the user-facing frontend —
ingress routes `https://<starter_pack_url>/` directly to it — so this
single override is what the user sees.

#### Outbound — ingress paths (Pattern 1)

**This pack does not stitch API paths onto the frontend subdomain.** The
only ingress rule is `/` → `rag-frontend:3000`. The frontend uses
Pattern 2 env vars to reach the backend services.

#### Outbound — env vars (Pattern 2)

Set by the `frontend.envVars` block in
`ai-accelerator-tf/helm-values/enterprise-rag-values.yaml` (lines 384–392).
Defaults:

| Env var              | Value                                |
|----------------------|--------------------------------------|
| `VITE_API_CHAT_URL`  | `http://rag-server:8081/v1`          |
| `VITE_API_VDB_URL`   | `http://ingestor-server:8082/v1`     |
| `VITE_MILVUS_URL`    | `http://milvus:19530`                |

These are in-cluster service DNS names. The frontend is a Vite-built SPA
served by the chart's `rag-frontend` container. Env vars are baked in at
build time by the chart, not injected by Terraform. If NVIDIA ships new
env vars in a future chart version, they will appear in the same
`frontend.envVars` block.

#### Worked example

```js
// Browser — chat completion against the rag-server.
// Note: this call is made from inside the frontend's Node/Vite runtime,
// which reads VITE_API_CHAT_URL at build time and embeds it.
const reply = await fetch(`${import.meta.env.VITE_API_CHAT_URL}/chat`, {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({ messages, model }),
});

// Server-side (Vite's SSR path, if used) — upload a document.
const body = new FormData();
body.append('file', file);
await fetch(`${import.meta.env.VITE_API_VDB_URL}/documents`, {
  method: 'POST',
  body,
});
```

#### Source of truth

- `ai-accelerator-tf/helm-values/enterprise-rag-values.yaml` — the
  `frontend.envVars` block and the chart's `frontend.*` defaults.
- `ai-accelerator-tf/helm.tf` — the `rag` helm_release with the skin
  image override.
- Upstream chart for advanced config:
  `https://helm.ngc.nvidia.com/nvidia/blueprint/charts/nvidia-blueprint-rag-v2.3.0.tgz`.

### 3.5 enterprise_rag_aiq (Enterprise Agentic AI Starter Kit)

#### Catalog summary

enterprise_rag_aiq is a Helm-based pack. It ships one skin; the
`skin_enterprise_rag_aiq` ORM variable is an enum dropdown whose sole
option is the NVIDIA AIRA skin today.

| Skin     | Enum variable                | `container_port` | `subdomain` |
|----------|------------------------------|------------------|-------------|
| Core App | `skin_enterprise_rag_aiq`    | 3000             | `aiq`       |

Ingress host: `https://aiq.<fqdn>`. Catalog source:
`ai-accelerator-tf/schemas/frontend_skins.yaml`.

#### Two Helm releases, not one

Terraform deploys **both** the main `rag` Helm release (using
`helm-values/enterprise-rag-aiq-values.yaml`) AND a separate `aiq-aira`
Helm release (chart `aiq-aira-v1.2.1.tgz`, values in
`helm-values/aiq-aira-values.yaml`). The user-facing URL `https://aiq.<fqdn>`
routes to the `aiq-aira-aira-frontend` service from the `aiq-aira`
release (see `ai-accelerator-tf/ingress.tf` lines 193–234). The main
`rag` release's `rag-frontend` is also deployed but is **not** the
user-facing UI for this pack — skin authors who want to customize the
AIQ frontend must modify the `aiq-aira` chart values, not the `rag`
chart values.

Terraform emits the catalog's `frontend.image.{repository,tag}` override
on **both** releases — on `rag` (`helm.tf` lines 647–654) for symmetry
with enterprise_rag, and on `aiq-aira` (`helm.tf` lines 771–797) to
actually reach the user-facing frontend for this pack. The `aiq-aira`
override is the one that matters for AIQ users; the `rag` override is a
harmless no-op here. This invariant is locked by
`ai-accelerator-tf/schemas/tests/test_helm_skin_override.py`.

#### Outbound — ingress paths (Pattern 1)

**This pack does not stitch API paths onto the frontend subdomain.** The
only ingress rule is `/` → `aiq-aira-aira-frontend:3000`.

#### Outbound — env vars (Pattern 2)

The `aiq-aira` chart's `frontend:` block in
`helm-values/aiq-aira-values.yaml` does **not** define an `envVars` list
(unlike the rag chart). The AIQ backend's `backendEnvVars` block
(`RAG_SERVER_URL`, `RAG_INGEST_URL`, `NEMOTRON_BASE_URL`) reaches the
backend pod, **not** the frontend container — do not document them as
frontend-reachable.

**In practice, the frontend's backend endpoints are chart-internal.** A
drop-in AIQ skin must replicate the upstream `aira-frontend`'s
assumptions about the backend surface; modifying the backend surface
requires Helm chart changes, not catalog changes.

#### Worked example

```js
// The upstream aira-frontend already does its own backend wiring,
// driven by chart-internal defaults. A drop-in skin has two choices:
//
// 1. Ship a frontend that speaks the same internal API as the upstream
//    aira-frontend (same relative paths the chart already routes).
// 2. Propose a chart fork / PR upstream that exposes frontend env vars
//    like enterprise_rag does.
//
// Option 1 looks like:
const resp = await fetch('/api/chat', { method: 'POST', body: ... });
// where /api/chat is whatever path the aiq-aira chart's internal
// networking already routes to the AIQ backend.
```

#### Source of truth

- `ai-accelerator-tf/helm-values/enterprise-rag-aiq-values.yaml` — the
  main `rag` release's values (backend-side components for the AIQ stack).
- `ai-accelerator-tf/helm-values/aiq-aira-values.yaml` — the user-facing
  frontend's values.
- `ai-accelerator-tf/helm.tf` — both `rag` and `aiq-aira` helm_release
  blocks with the skin image override (BUG-020 fix).
- `ai-accelerator-tf/ingress.tf` — the `enterprise_rag_aiq_frontend_ingress`
  rule that routes `aiq.<fqdn>` to `aiq-aira-aira-frontend:3000`.
- Upstream charts for advanced config:
  - `https://helm.ngc.nvidia.com/nvidia/blueprint/charts/nvidia-blueprint-rag-v2.3.0.tgz`
  - `https://helm.ngc.nvidia.com/nvidia/blueprint/charts/aiq-aira-v1.2.1.tgz`

## 4. Updating This Doc

(to be written)
