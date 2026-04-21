# warehouse_pick_path Pack — Backend API Contract

Pack-specific companion to [`BACKEND_API_CONTRACT.md`](../BACKEND_API_CONTRACT.md). Scope: every
backend the warehouse_pick_path pack exposes, the endpoints each backend
serves, and how a skin (or an external integrator) reaches them.

The parent doc is organized by skin-access *mechanism* (ingress paths vs.
env vars) across all packs. This file is organized by *backend service*
for the warehouse_pick_path pack only, and documents the full endpoint
surface that a frontend or external client can call.

---

## 1. Deployment Group

Every warehouse_pick_path-pack apply produces a single Corrino deployment
group containing one backend service and one or more skins.

Source: `ai-accelerator-tf/blueprint_files.tf` —
`local._warehouse_pick_path_small_blueprint` and
`local._wpp_frontend_deployments`.

| Role     | Corrino sub-deployment | Container image                                                                    | Container port | GPUs |
|----------|------------------------|------------------------------------------------------------------------------------|----------------|------|
| Backend  | `backend`              | `iad.ocir.io/.../warehouse-pick-path-optimizer-be:2d2a008`                         | 8000           | 1    |
| Frontend | `skin_wpp_core`        | `iad.ocir.io/.../warehouse-pick-path-optimizer-fe:2d2a008`                         | 3000           | 0    |

**Execution order.** The `backend` deployment has no `depends_on` and
deploys first. Each skin declares `depends_on = ["backend"]`, so skins
deploy only after the backend reaches `ACTIVE`.

**Mutability.** Blueprints are immutable — changing any backend field in
`blueprint_files.tf` requires an undeploy/redeploy of the affected
sub-deployment. See `docs/BLUEPRINT_LIFECYCLE.md`.

**GPU usage.** The backend container is based on `nvidia/cuopt:26.6.0a-cuda13.0-py3.13`.
cuOpt is imported at startup and uses the GPU for VRP solving. If cuOpt
fails to load (no GPU / CUDA error), the optimizer falls back to a
nearest-neighbour CPU heuristic.

---

## 2. Backend Service — `backend`

FastAPI application: Warehouse Pick Path Optimizer. Accepts warehouse
layouts and order batches as CSV uploads, persists them in Oracle 26ai,
then runs pick path optimization using the NVIDIA cuOpt GPU solver (with
CPU nearest-neighbour fallback).

The backend has its own JWT-based authentication system. All `/api/*`
routes (except auth endpoints and health probes) require a valid
`access_token` cookie. The first-run setup creates an admin account.

#### Deployment facts

| Field                | Value                                                                                         |
|----------------------|-----------------------------------------------------------------------------------------------|
| Image                | `iad.ocir.io/iduyx1qnmway/corrino-devops-repository/warehouse-pick-path-optimizer-be:2d2a008` |
| Container port       | `8000`                                                                                        |
| K8s Service          | ClusterIP, port `80` → targetPort `8000`                                                      |
| Container command    | `uvicorn app.main:app --host 0.0.0.0 --port 8000 --log-config /app/logging.json`              |
| Container env        | `OCI26AI_CONNECTION_STRING`, `OCI26AI_USER`, `OCI26AI_PASSWORD` (Oracle 26ai creds from Terraform vars) |
| Auth to Oracle 26ai  | Direct connection string with username/password (not instance principal)                       |
| Liveness probe       | `GET /healthz`, `initialDelaySeconds=60`                                                      |
| Readiness probe      | `GET /readyz`, `initialDelaySeconds=30` (checks Oracle DB connectivity)                       |
| CORS                 | Explicit origins only, never wildcard; `GET` and `POST` methods; `Content-Type` and `Authorization` headers |
| Rate limiting        | `60/minute` default; `10/minute` for uploads                                                  |

#### Endpoints

All endpoints below are verified against
`oci-ai-incubations/oci-warehouse-pick-path-optimizer` —
`backend/app/api/routes/*.py` and `backend/app/main.py`.

**Health** (no auth required — outside `/api/` prefix)

| Method | Path       | Purpose                                                                  |
|--------|------------|--------------------------------------------------------------------------|
| GET    | `/healthz` | Liveness probe — returns `{"status": "ok"}`.                             |
| GET    | `/readyz`  | Readiness probe — checks Oracle DB pool. Returns 503 if DB unreachable.  |

**Authentication** (no `access_token` cookie required)

| Method | Path                    | Purpose                                                                                        |
|--------|-------------------------|------------------------------------------------------------------------------------------------|
| GET    | `/api/auth/setup-status`| Returns `{"needs_setup": true/false}` — frontend checks this to show setup vs login screen.    |
| POST   | `/api/auth/setup`       | Create first admin account. Body: `{"username": "...", "password": "..."}`. Returns 409 if already configured. Sets auth cookies. |
| POST   | `/api/auth/login`       | Authenticate. Body: `{"username": "...", "password": "..."}`. Sets `access_token` and `refresh_token` httpOnly cookies. |
| POST   | `/api/auth/refresh`     | Rotate tokens from `refresh_token` cookie. Returns new auth cookies.                           |
| POST   | `/api/auth/logout`      | Clear auth cookies.                                                                            |
| GET    | `/api/auth/me`          | Return `{"username": "..."}` from current access token. 401 if not authenticated.              |

**Data upload** (requires `access_token` cookie)

| Method | Path                                              | Purpose                                                                  |
|--------|---------------------------------------------------|--------------------------------------------------------------------------|
| POST   | `/api/upload/warehouse-layout`                    | Upload warehouse layout CSV. Required columns: `location_id`, `oracle_loc_type_code`, `area`, `aisle`, `bay`, `level`, `pick_sequence`. Max 50 MB. |
| GET    | `/api/upload/warehouse-layouts`                   | List all uploaded warehouse layouts (most recent first).                  |
| GET    | `/api/upload/warehouse-layout/{upload_id}/download`| Download a warehouse layout as CSV.                                      |
| DELETE | `/api/upload/warehouse-layout/{upload_id}`        | Delete a warehouse layout and all its locations.                         |
| POST   | `/api/upload/order-batch`                         | Upload order batch CSV. Required columns: `order_id`, `order_line_id`, `sku`, `qty`, `priority`, `order_created_ts`, `requested_ship_ts`. |
| GET    | `/api/upload/order-batches`                       | List all uploaded order batches.                                         |
| GET    | `/api/upload/order-batch/{upload_id}/download`    | Download an order batch as CSV.                                          |
| DELETE | `/api/upload/order-batch/{upload_id}`             | Delete an order batch and all its lines.                                 |
| POST   | `/api/upload/inventory-snapshot`                  | Upload inventory snapshot CSV. Required columns: `sku`, `location_id`, `available_qty`.  |
| GET    | `/api/upload/inventory-snapshots`                 | List all uploaded inventory snapshots.                                    |
| GET    | `/api/upload/inventory-snapshot/{upload_id}/download`| Download an inventory snapshot as CSV.                                 |
| DELETE | `/api/upload/inventory-snapshot/{upload_id}`      | Delete an inventory snapshot.                                            |
| POST   | `/api/upload/sku-master`                          | Upload SKU master CSV. Required columns: `sku`, `weight_kg`.             |
| GET    | `/api/upload/sku-masters`                         | List all uploaded SKU masters.                                           |
| GET    | `/api/upload/sku-master/{upload_id}/download`     | Download a SKU master as CSV.                                            |
| DELETE | `/api/upload/sku-master/{upload_id}`              | Delete a SKU master.                                                     |

**Optimization** (requires `access_token` cookie)

| Method | Path                  | Purpose                                                                                      |
|--------|-----------------------|----------------------------------------------------------------------------------------------|
| POST   | `/api/optimize`       | Run synchronous pick path optimization. Returns full `OptimizationResult` with pick paths, KPI metrics. |
| POST   | `/api/optimize/stream`| SSE endpoint streaming step-by-step progress then final result. Events: `step`, `result`, `error`. |

`POST /api/optimize` and `/api/optimize/stream` request body:

| Field                    | Type   | Required | Purpose                                                         |
|--------------------------|--------|----------|-----------------------------------------------------------------|
| `warehouse_upload_id`    | string | yes      | UUID of a previously uploaded warehouse layout.                  |
| `order_batch_upload_id`  | string | yes      | UUID of a previously uploaded order batch.                       |
| `inventory_upload_id`    | string | no       | UUID of an inventory snapshot (for pick location resolution).    |
| `sku_master_upload_id`   | string | no       | UUID of a SKU master (for weight-based capacity constraints).    |
| `num_pickers`            | int    | yes      | Number of pickers to assign routes to.                           |
| `time_limit_seconds`     | int    | no       | cuOpt solver time limit.                                         |
| `wave_mode`              | string | no       | Wave grouping strategy.                                          |
| `direction`              | string | no       | Pick direction preference.                                       |
| `solver_climbers`        | int    | no       | Number of parallel solver climbers (cuOpt parameter).            |

**Batch** (requires `access_token` cookie; async jobs — not yet fully implemented)

| Method | Path                  | Purpose                                                        |
|--------|-----------------------|----------------------------------------------------------------|
| POST   | `/api/batch`          | Submit an async optimization job. Returns immediately with `job_id`. |
| GET    | `/api/batch/{job_id}` | Poll job status. Returns `OptimizationResult` with status field.  |

**Content negotiation.** All endpoints accept and return `application/json`.
File uploads use `multipart/form-data`. CSV downloads return `text/csv`.

---

## 3. How Skins and External Clients Reach the Backend

The pack wires two distinct ingress surfaces.

#### Frontend-proxied paths (Pattern 1)

Every enabled warehouse_pick_path skin's ingress carries one
`pathType: Prefix` rule, injected by `local._wpp_frontend_deployments`
in `blueprint_files.tf`:

| Path prefix on the skin host | Backend  | Target port | Notes                                                             |
|------------------------------|----------|-------------|-------------------------------------------------------------------|
| `/api` (Prefix)              | backend  | 8000        | Forwards the full URL path unchanged. `fetch('/api/optimize')` → backend's `/api/optimize`. |

No `rewrite-target` annotation is set on the skin ingress, so nginx
forwards the full path unchanged. Because the backend's API routes
already start with `/api/...`, the ingress prefix aligns with the
backend paths — there is no double-nesting.

The frontend itself is a static React SPA served by `serve`. In
production on the cluster, the `/api` prefix routes are handled by the
nginx ingress (proxied to the backend); all other paths serve the SPA's
`dist/` files.

Skin hosts from `schemas/frontend_skins.yaml`:

| Skin       | `variable_name` | `container_port` | Ingress host              |
|------------|-----------------|------------------|---------------------------|
| Core App   | `skin_wpp_core` | 3000             | `https://wpp.<fqdn>`      |

Browser-safe: same origin, so CORS and auth cookies are free.

#### Dedicated backend ingress (external clients)

The backend's Corrino `recipe_mode = service` deployment gets its own
auto-generated Ingress with a dedicated hostname separate from the skin
subdomain. Exact host format depends on the per-deploy canonical name
(see §5 Open Questions); pattern is `wpp-backend-<id>.<lb-ip>.nip.io`.

**Bearer-token gate (opt-in).** When the stack is deployed with
`add_api_key_to_ingress = true`, the backend recipe's ingress carries:

```
nginx.ingress.kubernetes.io/auth-url:    http://ingress-api-key-validator.cluster-tools.svc.cluster.local/auth
nginx.ingress.kubernetes.io/auth-method: GET
```

…and external calls must send `Authorization: Bearer <token>`. The token
appears in the ORM stack outputs as **"Ingress API Key"**. Note that
this gate is *in addition to* the backend's own JWT auth — external
clients must pass both the bearer token (ingress layer) and have a
valid `access_token` cookie (application layer).

The gate applies **only** to the dedicated backend hostname. It does
**not** apply to `/api` paths on a skin subdomain (the skin ingress is
unprotected by design — the backend's own JWT auth handles access
control) or to in-cluster pod-to-pod traffic.

Injection is done by the blueprint — the `backend` recipe sets
`recipe_additional_ingress_annotations =
local.backend_ingress_annotations_corrino`
(`ai-accelerator-tf/app-ingress-auth.tf` builds the annotation list, and
`test_every_backend_recipe_has_annotation` keeps every backend recipe
from drifting).

**Proxy body size.** All Corrino-generated ingresses carry
`nginx.ingress.kubernetes.io/proxy-body-size: 2000m`. CSV uploads
(max 50 MB default) ride this limit comfortably.

**TLS.** Every Corrino ingress terminates TLS via cert-manager with the
`letsencrypt-prod` cluster issuer. In-cluster traffic is cleartext HTTP.

---

## 4. Worked Examples

```js
// Browser on the skin subdomain — check if first-run setup is needed.
const { needs_setup } = await fetch('/api/auth/setup-status').then(r => r.json());

// Browser — create admin account on first run.
await fetch('/api/auth/setup', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({ username: 'admin', password: 'SecureP@ss1' }),
});

// Browser — log in (sets httpOnly cookies automatically).
await fetch('/api/auth/login', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({ username: 'admin', password: 'SecureP@ss1' }),
});

// Browser — upload a warehouse layout CSV.
const formData = new FormData();
formData.append('file', warehouseFile);
const layout = await fetch('/api/upload/warehouse-layout', {
  method: 'POST',
  body: formData,
}).then(r => r.json());

// Browser — upload an order batch CSV.
const orderForm = new FormData();
orderForm.append('file', orderFile);
const batch = await fetch('/api/upload/order-batch', {
  method: 'POST',
  body: orderForm,
}).then(r => r.json());

// Browser — run optimization with SSE streaming progress.
const evtSource = new EventSource('/api/optimize/stream', { /* POST not supported by EventSource */ });
// Instead, use fetch with ReadableStream:
const response = await fetch('/api/optimize/stream', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({
    warehouse_upload_id: layout.upload_id,
    order_batch_upload_id: batch.upload_id,
    num_pickers: 4,
  }),
});
const reader = response.body.getReader();
// Read SSE events: {"type":"step",...}, {"type":"result",...}
```

```bash
# External integrator against the dedicated backend ingress with API-key gate on.
TOKEN="<value from ORM output 'Ingress API Key'>"
HOST="https://wpp-backend-<id>.<lb-ip>.nip.io"

# Health check (no auth cookies needed for /healthz).
curl -s -H "Authorization: Bearer $TOKEN" $HOST/healthz

# Log in to get auth cookies (needed for all /api/* calls).
curl -s -c cookies.txt -X POST $HOST/api/auth/login \
  -H 'Content-Type: application/json' \
  -d '{"username":"admin","password":"SecureP@ss1"}'

# Upload a warehouse layout.
curl -s -b cookies.txt -H "Authorization: Bearer $TOKEN" \
  -F file=@warehouse.csv $HOST/api/upload/warehouse-layout

# Run optimization.
curl -s -b cookies.txt -H "Authorization: Bearer $TOKEN" \
  -X POST $HOST/api/optimize \
  -H 'Content-Type: application/json' \
  -d '{"warehouse_upload_id":"<uuid>","order_batch_upload_id":"<uuid>","num_pickers":4}'
```

---

## 5. Open Questions

These require runtime introspection of a live deployment or a version of
the source not present in this repo to resolve; until then they are
flagged rather than guessed.

- **Exact hostname format of the dedicated backend ingress.**
  `docs/API_TOKENS.md` gives the shape `<deployment_name>-<id>.<lb-ip>.nip.io`,
  but the `<id>` suffix is derived from the Corrino canonical name
  (`deployment_name` post-`DEPLOY_NAME` substitution, truncated to 32
  chars). The authoritative list is `kubectl get ingress -n default`
  after apply.
- **Batch endpoint implementation status.** `POST /api/batch` and
  `GET /api/batch/{job_id}` are defined but the Celery task dispatch
  is stubbed (`TODO: dispatch Celery task`). Jobs are tracked in-memory
  only. This endpoint should not be relied upon until the Celery
  integration is completed.
- **Wallet-based TLS auth to Oracle 26ai.** The backend config supports
  `OCI26AI_EWALLET_PWD` and `OCI26AI_TNSNAMES_LOC` environment
  variables for wallet-based connections, but the blueprint does not
  inject these. Currently uses connection string + username/password
  only.

---

## 6. Source of Truth

| Concern                                                      | File                                                                                 |
|--------------------------------------------------------------|--------------------------------------------------------------------------------------|
| Deployment group JSON (backend recipe)                       | `ai-accelerator-tf/blueprint_files.tf` — `local._warehouse_pick_path_small_blueprint`|
| Skin deployments, ingress path-prefix rules                  | `ai-accelerator-tf/blueprint_files.tf` — `local._wpp_frontend_deployments`           |
| Skin catalog (image URI, port, subdomain)                    | `ai-accelerator-tf/schemas/frontend_skins.yaml`                                      |
| Bearer-token gate annotations + validator                    | `ai-accelerator-tf/app-ingress-auth.tf`, `docs/API_TOKENS.md`                        |
| Bearer-token-annotation invariant test                       | `ai-accelerator-tf/schemas/tests/test_blueprint_structure.py::test_every_backend_recipe_has_annotation` |
| `DEPLOY_NAME` placeholder + deployment immutability          | `docs/BLUEPRINT_LIFECYCLE.md`, `ai-accelerator-tf/vars.tf`                           |
| Backend API implementation (routes, auth, optimizer)         | `oci-ai-incubations/oci-warehouse-pick-path-optimizer` — `backend/app/`              |
| Frontend SPA + proxy config                                  | `oci-ai-incubations/oci-warehouse-pick-path-optimizer` — `frontend/`                 |
| Backend repo                                                 | https://github.com/oci-ai-incubations/oci-warehouse-pick-path-optimizer              |
| Corrino manifest templates (Deployment / Service / Ingress)  | `corrino/api/manifests/templates/recipe_{deployment,service,ingress}_template.yaml`   |

---

## 7. Updating This Doc

Manually maintained; no drift-check test. Update whenever:

- `ai-accelerator-tf/blueprint_files.tf` changes
  `local._warehouse_pick_path_small_blueprint` (backend recipe fields) or
  `local._wpp_frontend_deployments` (ingress path rules, `container_port`).
- `ai-accelerator-tf/schemas/frontend_skins.yaml` changes the
  warehouse_pick_path skin catalog (subdomain, container_port, new skins).
- `ai-accelerator-tf/app-ingress-auth.tf` changes the bearer-token
  annotation shape.
- `recipe_image_uri` bumps the backend or frontend to a new release —
  spot-check `backend/app/api/routes/*.py` against §2's endpoint tables.
- New routes are added to the backend API.

### "When in doubt" rule

> Would a skin author or external integrator need this to call the pack's
> backend correctly? If yes, document it. If the answer depends on
> runtime state not visible in source, add it to §5 Open Questions rather
> than guessing.
