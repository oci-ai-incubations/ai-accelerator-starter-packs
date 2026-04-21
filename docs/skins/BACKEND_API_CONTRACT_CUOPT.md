# cuopt Pack — Backend API Contract

Companion document to `BACKEND_API_CONTRACT.md`. That file is the multi-pack
reference organized around skin-access *mechanisms* (ingress paths vs env
vars). This file is the cuopt-pack-specific deep dive organized around
*backend services and their API surface* — what a skin author can actually
call.

Scope: `starter_pack_category = "cuopt"`. For vss / paas_rag / enterprise_rag
/ enterprise_rag_aiq, see `BACKEND_API_CONTRACT.md` §3.2–§3.5.

---

## 1. Deployment Group Composition

The cuopt pack deploys a single **Corrino blueprint deployment group** to
OKE, composed of three or four services depending on how many frontend
skins are enabled. Source of truth:
`ai-accelerator-tf/blueprint_files.tf` — `local._cuopt_blueprint` and
`local._cuopt_frontend_deployments`.

| Service        | Container image                                          | Container port | GPU    | Role                                                                       |
|----------------|----------------------------------------------------------|----------------|--------|----------------------------------------------------------------------------|
| `cuopt`        | `nvcr.io/nvidia/cuopt/cuopt:25.10.0-cuda12.9-py3.13`     | 5000           | 2 / 8  | NVIDIA cuOpt NIM — GPU-accelerated VRP / LP / MILP solver.                 |
| `llamastack`   | `iad.ocir.io/.../llama-stack-oci:v0.0.3`                 | 8321           | —      | Llama Stack with the OCI GenAI inference adapter. OpenAI-compatible API.   |
| Skin(s)        | Per entry in `schemas/frontend_skins.yaml`               | Per skin       | —      | User-facing HTTP frontend(s); each has its own subdomain and ingress host. |

**Key facts:**

- GPU count for `cuopt`: **2** on `poc`, **8** on `small` / `medium`.
- Deployment order: `llamastack` → `cuopt` → skins. Skins declare
  `depends_on = ["cuopt", "llamastack"]` so they deploy last and so their
  ingress rules can reference the already-resolved backend service names.
- `cuopt`'s readiness probe has a **20-minute** `initialDelaySeconds` — cuOpt
  NIM does CUDA init and loads kernels on first boot; shorter delays will
  kill the pod mid-startup.
- Both backends run as Kubernetes `ClusterIP` services exposed at `port 80`
  that targets the container's actual port (`targetPort` = `5000` or `8321`).
  Nothing external talks to the solver or llamastack directly — external
  traffic always lands on a skin's ingress first.

---

## 2. Backend Service — `cuopt` (NVIDIA cuOpt NIM)

The cuopt container is a FastAPI server that accepts VRP, LP, and MILP
problems on a single endpoint and returns results asynchronously via a
request-id / polling pattern.

- **In-cluster address:** `http://<cuopt.service_name>:80` (Service
  `port 80` → container `targetPort 5000`).
- **Container command:** `python -m cuopt_server.cuopt_service -p 5000 -g N`
  where `N` is the GPU count.
- **Environment:** `NVIDIA_API_KEY` (injected from the `nvidia-api-secret`
  Kubernetes Secret via the blueprint's `recipe_environment_secrets`).
- **Image pull:** `ngc-secret` (dockerconfigjson).
- **Authoritative OpenAPI spec:**
  [docs.nvidia.com/cuopt/user-guide/latest/open-api.html](https://docs.nvidia.com/cuopt/user-guide/latest/open-api.html).
- **Source of truth for route list:** `NVIDIA/cuopt` —
  `python/cuopt_server/cuopt_server/webserver.py`.

### 2.1 Health & metadata

| Method | Path                  | Purpose                                                                             |
|--------|-----------------------|-------------------------------------------------------------------------------------|
| GET    | `/`                   | Ping — returns `{"status": "RUNNING", "version": "<v>"}`.                           |
| GET    | `/cuopt/health`       | Standard cuOpt health check (same handler as `/`).                                  |
| GET    | `/v2/health/live`     | NIM-style liveness — used by the blueprint's liveness probe.                        |
| GET    | `/v2/health/ready`    | NIM-style readiness — used by the blueprint's readiness probe.                      |

All four paths resolve to the same implementation via stacked FastAPI
decorators — use any of them interchangeably.

### 2.2 Request lifecycle — the primary flow

The canonical pattern for solving a problem is:

1. `POST /cuopt/request` → receive `{"reqId": "..."}`.
2. Poll `GET /cuopt/solution/{reqId}` until you get a solution body instead
   of another `reqId` echo.
3. (Optional) `GET /cuopt/log/{reqId}` if you asked for solver logs.

| Method | Path                        | Purpose                                                                                                                 |
|--------|-----------------------------|-------------------------------------------------------------------------------------------------------------------------|
| POST   | `/cuopt/request`            | Submit a VRP / LP / MILP payload. Returns `{"reqId": "<uuid>"}`.                                                        |
| GET    | `/cuopt/request/{id}`       | Poll status. Returns one of `queued`, `running`, `done`, `error`.                                                       |
| DELETE | `/cuopt/request/{id}`       | Cancel. `id = "*"` targets every request; query flags `running`, `queued`, `cached` scope which queues get cleared.     |

**`POST /cuopt/request` query parameters:**

| Param             | Type                | Purpose                                                                                                     |
|-------------------|---------------------|-------------------------------------------------------------------------------------------------------------|
| `cache`           | `bool`              | If `true`, caches the input data and returns a `reqId` without solving; reuse it via the `reqId` param.     |
| `reqId`           | `str`               | Reuse cached input from a prior `cache=true` upload instead of sending the body again.                      |
| `initialId[]`     | `list[str]`         | Routing only — pre-existing solution ids to seed the solver as initial solutions.                           |
| `warmstartId`     | `str`               | Single-LP only — reuse PDLP warmstart data from a prior solution id.                                        |
| `validation_only` | `bool`              | If `true`, validate the payload and return — do not solve. Useful for skin-side payload checks before commit.|

**Request body content types:** `application/json` (default),
`application/vnd.msgpack`, or `application/zlib`. Use msgpack or zlib for
large routing payloads — zlib on a ~100MB VRP body is dramatically faster to
upload than JSON.

### 2.3 Solution lifecycle

| Method | Path                                     | Purpose                                                                                                                                              |
|--------|------------------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------|
| GET    | `/cuopt/solution/{id}`                   | Fetch a completed solution. If the request is still running, returns the `reqId` again (client keeps polling).                                        |
| POST   | `/cuopt/solution`                        | Upload a routing solution to use as a warmstart or initial solution for a later request. Returns its own `reqId` that can be passed via `initialId`. |
| DELETE | `/cuopt/solution/{id}`                   | Delete a cached solution (reclaim server memory).                                                                                                     |
| GET    | `/cuopt/solution/{id}/incumbents`        | MIP only — drain incumbent solutions produced since the last poll. Empty list = none new yet. Sentinel `[{"solution": [], "cost": null, "bound": null}]` = solver will produce no more incumbents. |

### 2.4 Solver logs

Only useful when the original `POST /cuopt/request` set `solver_logs: true`
in the payload.

| Method | Path                | Purpose                                                                              |
|--------|---------------------|--------------------------------------------------------------------------------------|
| GET    | `/cuopt/log/{id}`   | Fetch accumulated solver log text. Query `frombyte=<offset>` for incremental reads.  |
| DELETE | `/cuopt/log/{id}`   | Delete the log file for a request.                                                   |

### 2.5 Endpoints to avoid

- `POST /cuopt/cuopt` (line 1220 of `webserver.py`) — a sync endpoint for
  NVIDIA's *managed* cuOpt service. Hidden from the OpenAPI spec
  (`include_in_schema=False`). Calling it from a self-hosted deployment
  bypasses the request queue and logs, which is almost never what you want.
  Use `POST /cuopt/request` instead.
- `GET /cuopt/solution/{id}/warmstart` (line 826) — internal PDLP warmstart
  data in msgpack. Hidden from the OpenAPI spec. Only the solver itself
  consumes this via the `warmstartId` query param.

### 2.6 Content negotiation

All GETs and the POST endpoints accept and return:

- `application/json` (default)
- `application/vnd.msgpack`
- `application/zlib`

Set via the `Accept` request header. Standard wildcards (`*/*`,
`application/*`) fall back to the request's `Content-Type`. Mismatched
accept values return `415 Unsupported Media Type`.

---

## 3. Backend Service — `llamastack`

Llama Stack built with the OCI GenAI inference adapter. Llama Stack exposes
its endpoints under the **OpenAI API schema**, so a skin author can treat it
as a drop-in OpenAI-compatible server whose `baseURL` is
`http://<llamastack.service_name>:80/v1` (in-cluster) or `/v1` through the
skin's ingress.

- **In-cluster address:** `http://<llamastack.service_name>:80` (Service
  `port 80` → container `targetPort 8321`).
- **Container command args:** `["/config/config.yaml"]` (Llama Stack reads
  its provider config from a mounted Secret at `/config`).
- **Environment:** `OCI_COMPARTMENT_OCID`, `OCI_REGION` (from
  `var.genai_region`), `OCI_AUTH_TYPE=instance_principal`. Llama Stack uses
  the instance-principal credentials of the OKE node to call OCI GenAI.
- **Authoritative spec:** [OpenAI API reference](https://platform.openai.com/docs/api-reference)
  (Llama Stack speaks this schema); Llama Stack project docs at
  [llama-stack.readthedocs.io](https://llama-stack.readthedocs.io/).

### 3.1 OpenAI-compatible endpoints

All under the `/v1` prefix:

| Method | Path                              | Purpose                                                             |
|--------|-----------------------------------|---------------------------------------------------------------------|
| GET    | `/v1/models`                      | List models available to this llamastack.                           |
| GET    | `/v1/models/{model_id}`           | Describe a specific model.                                          |
| POST   | `/v1/chat/completions`            | Chat completions. Accepts `messages`, `model`, `tools`, `stream`.   |
| POST   | `/v1/completions`                 | Text completions (legacy).                                          |
| POST   | `/v1/embeddings`                  | Embeddings.                                                         |
| POST   | `/v1/responses`                   | OpenAI Responses API — the cuopt frontend's primary tool-calling surface. |
| GET    | `/v1/health`                      | Health check.                                                       |

Streaming (`"stream": true` in the request body) works across chat,
completions, and responses — llamastack forwards the SSE stream from OCI
GenAI to the caller.

> **Any standard OpenAI SDK works.** Point the SDK at base URL `/v1` (or
> `${LLAMASTACK_ENDPOINT}/v1` for server-side code) and it will behave as if
> talking to OpenAI directly, modulo whatever the underlying OCI GenAI
> model supports.

### 3.2 Additional Llama Stack endpoints

Llama Stack also exposes non-OpenAI routes (vector stores, files, agents,
memory, safety) under `/v1`. The cuopt pack routes the entire `/v1`
namespace as a catch-all, so these are reachable if a skin wants them —
but they are not wired or expected by the shipped Core App frontend.

---

## 4. Frontend Skins (Catalog)

cuopt ships two skins. Either or both may be enabled simultaneously via the
ORM form (`skin_cuopt_core`, `skin_cuopt_partner`); each enabled skin runs
as its own Corrino sub-deployment and gets its own subdomain.

Source: `ai-accelerator-tf/schemas/frontend_skins.yaml`.

| Skin                | `variable_name`       | `container_port` | `subdomain`             | Image                                                                    |
|---------------------|-----------------------|------------------|-------------------------|--------------------------------------------------------------------------|
| Core App            | `skin_cuopt_core`     | 3001             | `demo-cuopt`            | `iad.ocir.io/.../cuopt-interactive-frontend-v0.0.2`                      |
| Partner Contributed | `skin_cuopt_partner`  | 80               | `demo-cuopt-partner`    | `iad.ocir.io/.../cuopt-interactive-frontend-v0.0.3`                      |

Ingress host: `https://<subdomain>.<fqdn>`. `<fqdn>` resolves to the
generated `nip.io` domain (default) or a user-supplied FQDN if
`use_custom_dns = true`.

---

## 5. How a Skin Reaches the Backends

Two complementary mechanisms — both are wired automatically for every
enabled cuopt skin. Pick whichever fits the code path:

### Pattern 1 — Same-host ingress path routing (browser-safe)

The skin's own ingress has these additional `pathType: Prefix` rules
stitched onto it. A **relative** `fetch()` from the browser is routed
in-cluster by nginx — same origin, no CORS headers required.

| Path prefix on skin host | Backend service  | Port | Notes                                                                          |
|--------------------------|------------------|------|--------------------------------------------------------------------------------|
| `/cuopt`                 | cuopt solver     | 5000 | All cuopt endpoints (`/cuopt/request`, `/cuopt/solution/...`, `/cuopt/health`).|
| `/v1`                    | llamastack       | 8321 | All Llama Stack endpoints (`/v1/models`, `/v1/chat/completions`, …).           |

No `rewrite-target` annotation is applied — the full URL path is forwarded
to the backend. Because cuopt's own routes all start with `/cuopt/...` and
llamastack's with `/v1/...`, the ingress prefixes align naturally with the
backend paths. **There is no double-nesting.**

```js
await fetch('/cuopt/request', { method: 'POST', body: ... });   // → cuopt
await fetch('/v1/models');                                      // → llamastack
```

### Pattern 2 — In-cluster env vars (server-side only)

Injected into every skin container at boot. These URLs are absolute,
HTTP (no TLS), and reachable only from inside the cluster — do not attempt
to expose them to the browser.

| Env var                 | Value format                  | Points to                                               |
|-------------------------|-------------------------------|---------------------------------------------------------|
| `CUOPT_ENDPOINT`        | `http://<cuopt-svc>:80`       | cuopt solver.                                           |
| `LLAMASTACK_ENDPOINT`   | `http://<llamastack-svc>:80`  | llamastack.                                             |
| `LLAMASTACK_MODEL`      | `""`                          | Optional default model override for llamastack calls.   |
| `GOOGLE_MAPS_API_KEY`   | user-supplied                 | Map rendering (passthrough from `var.google_maps_api_key`). |
| `ADMIN_USERNAME`        | user-supplied                 | Skin UI admin user.                                     |
| `ADMIN_PASSWORD`        | user-supplied                 | Skin UI admin password.                                 |
| `NODE_ENV`              | `production`                  | Standard Node env flag.                                 |
| `PORT`                  | matches `container_port`      | For Node apps reading `process.env.PORT`.               |

The `<cuopt-svc>` / `<llamastack-svc>` placeholders are resolved at blueprint
deploy time — the `$${cuopt.service_name}` / `$${llamastack.service_name}`
tokens in Terraform become literal Kubernetes Service names after Corrino's
`ServiceNameExporter` runs.

---

## 6. Worked Examples

### 6.1 Browser — submit a routing problem and poll

```js
// Step 1: Submit. The solver enqueues the problem and returns a reqId.
const { reqId } = await fetch('/cuopt/request', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify(routingPayload),   // VRP / LP / MILP body
}).then(r => r.json());

// Step 2: Poll. `/cuopt/solution/{id}` returns the reqId again while running
// and the actual solution once complete.
async function waitForSolution(reqId, intervalMs = 2000) {
  while (true) {
    const body = await fetch(`/cuopt/solution/${reqId}`).then(r => r.json());
    if (body.reqId) {          // IdModel — still running
      await new Promise(res => setTimeout(res, intervalMs));
      continue;
    }
    return body;               // SolutionModel — done
  }
}
const solution = await waitForSolution(reqId);
```

### 6.2 Browser — stream MIP incumbents as they improve

```js
async function* streamIncumbents(reqId, pollMs = 1000) {
  while (true) {
    const batch = await fetch(`/cuopt/solution/${reqId}/incumbents`).then(r => r.json());
    if (batch.length && batch[0].solution.length === 0 && batch[0].cost === null) {
      return;                  // sentinel — solver is done producing incumbents
    }
    for (const inc of batch) yield inc;
    await new Promise(res => setTimeout(res, pollMs));
  }
}
for await (const inc of streamIncumbents(reqId)) {
  console.log(`new incumbent: cost=${inc.cost} bound=${inc.bound}`);
}
```

### 6.3 Browser — chat completion through llamastack (OpenAI client)

```js
import OpenAI from 'openai';

// Point the SDK at the same-host prefix; no API key needed inside the pack.
const client = new OpenAI({
  baseURL: '/v1',
  apiKey: 'unused',
  dangerouslyAllowBrowser: true,
});
const reply = await client.chat.completions.create({
  model: 'meta.llama-3.1-70b-instruct',
  messages: [{ role: 'user', content: 'Re-plan route for driver 42' }],
  tools: [/* tool-calling spec that edits the cuopt dataset */],
});
```

### 6.4 Server-side (Node / Next.js API route) — Pattern 2 equivalents

```js
// Solve via the in-cluster env var.
const { reqId } = await fetch(`${process.env.CUOPT_ENDPOINT}/cuopt/request`, {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify(routingPayload),
}).then(r => r.json());

// Cancel an in-flight request.
await fetch(`${process.env.CUOPT_ENDPOINT}/cuopt/request/${reqId}`, { method: 'DELETE' });

// Chat via llamastack using the OpenAI SDK.
const client = new OpenAI({
  baseURL: `${process.env.LLAMASTACK_ENDPOINT}/v1`,
  apiKey: 'unused',
});
```

### 6.5 curl — quick verification from an admin workstation with cluster access

```bash
# Tunneled or in-cluster. Substitute the real service name from `kubectl get svc`.
CUOPT=http://cuopt-xxxxx:80

curl -s $CUOPT/cuopt/health
# {"status":"RUNNING","version":"25.10.0"}

REQ=$(curl -s -X POST $CUOPT/cuopt/request \
  -H 'Content-Type: application/json' \
  -d @vrp.json | jq -r .reqId)

curl -s $CUOPT/cuopt/solution/$REQ | jq .
```

---

## 7. Source of Truth

| Concern                                           | File                                                                                       |
|---------------------------------------------------|--------------------------------------------------------------------------------------------|
| Deployment group definition (llamastack + cuopt)  | `ai-accelerator-tf/blueprint_files.tf` — `local._cuopt_blueprint`                          |
| Frontend skin deployments, env vars, ingress paths| `ai-accelerator-tf/blueprint_files.tf` — `local._cuopt_frontend_deployments`               |
| Skin catalog                                      | `ai-accelerator-tf/schemas/frontend_skins.yaml`                                            |
| cuopt REST endpoint implementation                | `NVIDIA/cuopt` — `python/cuopt_server/cuopt_server/webserver.py`                           |
| cuopt OpenAPI spec                                | https://docs.nvidia.com/cuopt/user-guide/latest/open-api.html                              |
| OpenAI API schema (llamastack)                    | https://platform.openai.com/docs/api-reference                                             |
| Llama Stack project                               | https://llama-stack.readthedocs.io/                                                        |
| Corrino manifest templates (ingress / service)    | `corrino/api/manifests/templates/recipe_{ingress,service,deployment}_template.yaml`        |

---

## 8. When to Update This Doc

This document is manually maintained. There is no drift-check test against
the Terraform. Update whenever you change any of:

- `ai-accelerator-tf/blueprint_files.tf` — any edit to
  `local._cuopt_blueprint` (cuopt or llamastack recipe fields) or
  `local._cuopt_frontend_deployments` (env vars, ingress paths,
  `container_port`).
- `ai-accelerator-tf/schemas/frontend_skins.yaml` — changes to the cuopt
  skin entries (`container_port`, `subdomain`, new skin keys).
- The upstream cuopt image tag (`recipe_image_uri`) — new cuopt releases
  occasionally add or rename endpoints; spot-check `webserver.py` against
  this table.

### "When in doubt" rule

> Would a skin author need this to wire their frontend? If yes, document it.
