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

(to be written)

### 3.4 enterprise_rag (Self-Hosted Enterprise Chat Agent)

(to be written)

### 3.5 enterprise_rag_aiq (Enterprise Agentic AI Starter Kit)

(to be written)

## 4. Updating This Doc

(to be written)
