# cuopt Pack — Backend API Contract

Pack-specific companion to [`BACKEND_API_CONTRACT.md`](../BACKEND_API_CONTRACT.md). Scope: every backend
the cuopt pack exposes, the endpoints each backend serves, and how a skin
(or an external integrator) reaches them.

The parent doc is organized by skin-access *mechanism* (ingress paths vs.
env vars) across all five packs. This file is organized by *backend
service* for the cuopt pack only, and documents the full endpoint surface
that a frontend or external client can call.

---

## 1. Deployment Group

Every cuopt-pack apply produces a single Corrino deployment group containing
two backend services and one or two skins.

Source: `ai-accelerator-tf/blueprint_files.tf` — `local._cuopt_blueprint`
and `local._cuopt_frontend_deployments`.

| Role     | Corrino sub-deployment | Container image                                            | Container port | GPUs (poc / small / medium) |
|----------|------------------------|------------------------------------------------------------|----------------|-----------------------------|
| Backend  | `llamastack`           | `iad.ocir.io/.../llama-stack-oci:v0.0.3`                   | 8321           | 0 / 0 / 0                   |
| Backend  | `cuopt`                | `nvcr.io/nvidia/cuopt/cuopt:25.10.0-cuda12.9-py3.13`       | 5000           | 2 / 8 / 8                   |
| Frontend | `skin_cuopt_core`      | `iad.ocir.io/.../cuopt-interactive-frontend-v0.0.2`        | 3000           | 0                           |
| Frontend | `skin_cuopt_partner`   | `iad.ocir.io/.../cuopt-interactive-frontend-v0.0.3`        | 80             | 0                           |

**Execution order.** `llamastack` and `cuopt` have no `depends_on` entries
and run concurrently. Each skin declares `depends_on = ["cuopt",
"llamastack"]`, so skins deploy only after both backends reach `ACTIVE`.

**Mutability.** Blueprints are immutable — changing any backend field in
`blueprint_files.tf` requires an undeploy/redeploy of the affected
sub-deployment. See `docs/BLUEPRINT_LIFECYCLE.md`.

---

## 2. Backend Service — `cuopt`

NVIDIA cuOpt NIM. GPU-accelerated solver for Vehicle Routing (VRP), Linear
Programming (LP), and Mixed-Integer Linear Programming (MILP). FastAPI
server; accepts payloads in JSON, msgpack, or zlib.

#### Deployment facts

| Field                     | Value                                                                             |
|---------------------------|-----------------------------------------------------------------------------------|
| Image                     | `nvcr.io/nvidia/cuopt/cuopt:25.10.0-cuda12.9-py3.13`                              |
| Container port            | `5000`                                                                            |
| K8s Service               | ClusterIP, port `80` → targetPort `5000`                                          |
| Container command         | `python -m cuopt_server.cuopt_service -p 5000 -g <N>` (`N` = `recipe_nvidia_gpu_count`) |
| Image pull secret         | `ngc-secret` (dockerconfigjson)                                                   |
| Env secret                | `NVIDIA_API_KEY` injected from Secret `nvidia-api-secret`                         |
| Shared memory (`/dev/shm`)| 16 GB (`recipe_shared_memory_volume_size_limit_in_mb = 16384`)                    |
| Ephemeral storage         | 200 GB (`recipe_ephemeral_storage_size = 200`)                                    |
| Liveness probe            | `GET /v2/health/live`, `initialDelaySeconds=1200` (cuOpt NIM warms up slowly)     |
| Readiness probe           | `GET /v2/health/ready`, `initialDelaySeconds=20`                                  |

#### Endpoints

All endpoints below are verified against
`cuopt/python/cuopt_server/cuopt_server/webserver.py`.

**Health**

| Method | Path                    | Purpose                                                     |
|--------|-------------------------|-------------------------------------------------------------|
| GET    | `/`                     | Ping — returns `{"status": "RUNNING", "version": "<v>"}`.   |
| GET    | `/cuopt/health`         | Same handler; standard cuOpt spelling.                      |
| GET    | `/v2/health/live`       | Same handler; NIM-style liveness (used by the probe).       |
| GET    | `/v2/health/ready`      | Same handler; NIM-style readiness (used by the probe).      |

**Request lifecycle**

| Method | Path                    | Purpose                                                                                                                                             |
|--------|-------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------|
| POST   | `/cuopt/request`        | Submit a VRP / LP / MILP payload. Returns `{"reqId": "<uuid>"}`.                                                                                    |
| GET    | `/cuopt/request/{id}`   | Poll request status. Response statuses: `queued`, `running`, `done`, `error`.                                                                       |
| DELETE | `/cuopt/request/{id}`   | Cancel. `id = "*"` cancels all; query flags `running`, `queued`, `cached` scope which queues get cleared.                                           |

`POST /cuopt/request` query parameters:

| Param             | Type        | Purpose                                                                                        |
|-------------------|-------------|------------------------------------------------------------------------------------------------|
| `cache`           | `bool`      | Cache the body and return a `reqId` without solving; reuse via the `reqId` param on a later POST. |
| `reqId`           | `str`       | Reuse cached data from a prior `cache=true` upload instead of resending the body.              |
| `initialId[]`     | `list[str]` | Routing only — solution ids to seed the solver as initial solutions.                            |
| `warmstartId`     | `str`       | Single-LP only — reuse PDLP warmstart data from a prior solution id.                            |
| `validation_only` | `bool`      | Validate the payload and return; do not solve.                                                  |

**Solution lifecycle**

| Method | Path                                   | Purpose                                                                                                                        |
|--------|----------------------------------------|--------------------------------------------------------------------------------------------------------------------------------|
| GET    | `/cuopt/solution/{id}`                 | Fetch the completed solution. While still running, returns the `reqId` again so the client keeps polling.                      |
| POST   | `/cuopt/solution`                      | Upload a solution to reuse as a warmstart / initial solution for a later request. Returns its own `reqId`.                     |
| DELETE | `/cuopt/solution/{id}`                 | Delete a cached solution.                                                                                                      |
| GET    | `/cuopt/solution/{id}/incumbents`      | MIP only. Drain incumbent solutions produced since the last poll. Sentinel `[{"solution": [], "cost": null, "bound": null}]` means no more will arrive. |

**Solver logs** (only populated when the original request set `solver_logs: true`)

| Method | Path                | Purpose                                                                      |
|--------|---------------------|------------------------------------------------------------------------------|
| GET    | `/cuopt/log/{id}`   | Fetch log content. Query `frombyte=<offset>` for incremental reads.          |
| DELETE | `/cuopt/log/{id}`   | Delete the log file for a request.                                           |

**Content negotiation.** All POSTs and GETs accept and return
`application/json` (default), `application/vnd.msgpack`, or
`application/zlib` via the `Accept` and `Content-Type` headers. Mismatched
`Accept` returns `415`.

**CLIENT-VERSION header.** Optional. When present and the major.minor
matches the server, no action. When missing or mismatched, the server adds
a warning to the response but does **not** reject the request. Set
`CLIENT-VERSION: custom` to suppress the warning from non-standard clients
(browsers, bespoke code). Behavior source: `check_client_version()` in
`cuopt/python/cuopt_server/cuopt_server/utils/job_queue.py`.

**Do not call**

| Path                               | Reason                                                                                             |
|------------------------------------|----------------------------------------------------------------------------------------------------|
| `POST /cuopt/cuopt`                | Managed-service sync endpoint (`include_in_schema=False`). Per its own docstring: "users will never call this API directly." Self-hosted clients must use `POST /cuopt/request`. |
| `GET /cuopt/solution/{id}/warmstart` | Internal — returns binary msgpack warmstart data consumed by the solver, not by clients. Hidden from the OpenAPI spec. |

**Authoritative OpenAPI spec:** [docs.nvidia.com/cuopt/user-guide/latest/open-api.html](https://docs.nvidia.com/cuopt/user-guide/latest/open-api.html)

---

## 3. Backend Service — `llamastack`

Oracle-packaged Llama Stack v0.0.3 with the OCI GenAI inference adapter.
Served on the Llama Stack native HTTP API, which also exposes an
OpenAI-compatible surface under `/v1` for chat, completions, embeddings,
models, and responses.

#### Deployment facts

| Field                | Value                                                                          |
|----------------------|--------------------------------------------------------------------------------|
| Image                | `iad.ocir.io/iduyx1qnmway/corrino-devops-repository/llama-stack-oci:v0.0.3`    |
| Container port       | `8321` (server port, from `llamastack_inference_config.yaml` `server.port`)    |
| K8s Service          | ClusterIP, port `80` → targetPort `8321`                                       |
| Container command    | `/config/config.yaml` (command args — Llama Stack reads its provider config from this path) |
| Config secret        | `llamastack-inference-config` (Opaque), mounted at `/config/`                  |
| Container env        | `OCI_COMPARTMENT_OCID`, `OCI_REGION = var.genai_region`, `OCI_AUTH_TYPE = instance_principal` |
| Auth to OCI GenAI    | Instance principal of the OKE worker node                                      |

#### Enabled APIs

From `ai-accelerator-tf/files/llamastack_inference_config.yaml`:

```yaml
apis: [agents, datasetio, eval, files, inference, safety, scoring, tool_runtime, vector_io]
providers:
  inference:   [{ provider_id: oci, provider_type: remote::oci }]
  vector_io:   [{ provider_id: faiss, provider_type: inline::faiss }]
  agents:      [{ provider_id: meta-reference, provider_type: inline::meta-reference }]
  tool_runtime:[{ provider_id: tavily-search }, { provider_id: brave-search }, { provider_id: rag-runtime }, { provider_id: model-context-protocol }]
  files:       [{ provider_id: meta-reference-files, provider_type: inline::localfs }]
  # eval, scoring, datasetio also wired; safety provider is commented out.
```

#### Endpoint surface

Llama Stack exposes both its native API and an OpenAI-compatible layer
under `/v1`. The table below is the set documented for the same container
in [`PAAS_RAG.md`](PAAS_RAG.md) plus the core
OpenAI-compat routes that are standard across Llama Stack releases. All
are reachable through the cuopt skin's `/v1` catch-all.

| Path prefix                 | Purpose                                                                   |
|-----------------------------|---------------------------------------------------------------------------|
| `GET  /v1/models`           | List available models.                                                    |
| `GET  /v1/health`           | Health check (listed in paas_rag §3.3 for the same container).            |
| `POST /v1/chat/completions` | OpenAI-compatible chat completions — primary inference interface.         |
| `POST /v1/embeddings`       | OpenAI-compatible embeddings.                                             |
| `POST /v1/responses`        | OpenAI Responses API.                                                     |
| `*    /v1/vector_stores`    | Vector store CRUD (faiss provider).                                       |
| `*    /v1/files`            | File upload / list / delete.                                              |

The inference config also enables the Llama Stack native APIs for
`agents`, `datasetio`, `eval`, `safety` (no provider registered),
`scoring`, and `tool_runtime`. Exact HTTP paths for those API groups
shift across Llama Stack releases — consult the shipped container's
OpenAPI document at runtime rather than assuming a specific path. See
§6 Open Questions.

---

## 4. How Skins and External Clients Reach the Backends

The pack wires three distinct ingress surfaces. Pick the one that fits
the caller.

#### Frontend-proxied paths (Pattern 1)

Every enabled cuopt skin's ingress carries these additional
`pathType: Prefix` rules, injected by `local._cuopt_frontend_deployments`
in `blueprint_files.tf`:

| Path prefix on the skin host       | Backend     | Target port | Notes                                                                                    |
|------------------------------------|-------------|-------------|------------------------------------------------------------------------------------------|
| `/cuopt` (Prefix)                  | cuopt       | 5000        | Forwards the full URL path unchanged. `fetch('/cuopt/request')` → cuopt's `/cuopt/request`. |
| `/v1` (Prefix)                     | llamastack  | 8321        | Catch-all for every Llama Stack route.                                                   |

No `rewrite-target` annotation is set on the skin ingress, so nginx
forwards the full path unchanged. Because cuopt's own routes already
start with `/cuopt/...` and Llama Stack's with `/v1/...`, the ingress
prefixes align with the backend paths — there is no double-nesting.

Skin hosts from `schemas/frontend_skins.yaml`:

| Skin                 | `variable_name`      | `container_port` | Ingress host                       |
|----------------------|----------------------|------------------|------------------------------------|
| Core App             | `skin_cuopt_core`    | 3000             | `https://demo-cuopt.<fqdn>`        |
| Partner Contributed  | `skin_cuopt_partner` | 80               | `https://demo-cuopt-partner.<fqdn>`|

Browser-safe: same origin, so CORS and auth cookies are free.

#### In-cluster env vars (Pattern 2)

Injected into every enabled skin container at boot by
`local._cuopt_frontend_deployments.recipe_container_env`. URLs are
absolute, cleartext HTTP, and reachable only from inside the cluster.
Do not attempt to expose them to a browser.

| Env var               | Value format                          | Points to                                                   |
|-----------------------|---------------------------------------|-------------------------------------------------------------|
| `CUOPT_ENDPOINT`      | `http://<cuopt-svc-name>:80`          | cuopt backend — Service port 80 → container port 5000.      |
| `LLAMASTACK_ENDPOINT` | `http://<llamastack-svc-name>:80`     | llamastack backend — Service port 80 → container port 8321. |
| `LLAMASTACK_MODEL`    | `""`                                  | Optional model override consumed by the skin code.          |
| `GOOGLE_MAPS_API_KEY` | user-supplied (`var.google_maps_api_key`) | Map-rendering key passed through to the skin.           |
| `ADMIN_USERNAME`      | user-supplied                         | Skin UI admin username.                                     |
| `ADMIN_PASSWORD`      | user-supplied                         | Skin UI admin password.                                     |
| `NODE_ENV`            | `production`                          | Standard Node flag.                                         |

The cuopt blueprint does not inject `PORT`. The core image already defaults to
its pod-facing listener on 3000, while the partner image must leave `PORT`
unset so its internal Express server defaults to 3001 behind nginx on 80.

The `<cuopt-svc-name>` and `<llamastack-svc-name>` placeholders resolve to
the Corrino-generated K8s Service names at container start (via the
`ServiceNameExporter`; the `$${cuopt.service_name}` / `$${llamastack.service_name}`
tokens in Terraform become literal names at blueprint deploy time).

#### Dedicated backend ingresses (external clients)

Every Corrino `recipe_mode = service` deployment gets its own auto-
generated Ingress. For this pack that means `cuopt` and `llamastack` each
have a dedicated hostname separate from the skin subdomain. Exact host
format depends on the per-deploy canonical name (see §6 Open Questions);
`docs/API_TOKENS.md` gives the shapes `cuopt-<id>.<lb-ip>.nip.io` and
`llamastack-<id>.<lb-ip>.nip.io`.

**Bearer-token gate (opt-in).** When the stack is deployed with
`add_api_key_to_ingress = true`, every backend-recipe ingress carries:

```
nginx.ingress.kubernetes.io/auth-url:    http://ingress-api-key-validator.cluster-tools.svc.cluster.local/auth
nginx.ingress.kubernetes.io/auth-method: GET
```

…and external calls must send `Authorization: Bearer <token>`. The token
appears in the ORM stack outputs as **"Ingress API Key"**. Rotate by
changing `var.ingress_api_key`; toggle on/off by flipping
`var.add_api_key_to_ingress` (toggling requires a blueprint redeploy, per
`docs/API_TOKENS.md`).

The gate applies **only** to the dedicated backend hostnames. It does
**not** apply to `/cuopt` or `/v1` paths on a skin subdomain (the skin
ingress is unprotected by design) or to in-cluster pod-to-pod traffic via
the env-var URLs.

Injection is done by the blueprint — both the `cuopt` and `llamastack`
recipes set `recipe_additional_ingress_annotations =
local.backend_ingress_annotations_corrino`
(`ai-accelerator-tf/app-ingress-auth.tf` builds the annotation list, and
`test_every_backend_recipe_has_annotation` keeps every backend recipe
from drifting).

**Proxy body size.** All Corrino-generated ingresses carry
`nginx.ingress.kubernetes.io/proxy-body-size: 2000m` (default from
`recipe_ingress_proxy_body_size` in `corrino/api/control_plane/digest.py`).
Large routing payloads ride this limit comfortably.

**TLS.** Every Corrino ingress terminates TLS via cert-manager with the
`letsencrypt-prod` cluster issuer. In-cluster traffic (env-var path) is
cleartext HTTP.

---

## 5. Worked Examples

```js
// Browser on a skin subdomain — submit a routing problem (Pattern 1).
const { reqId } = await fetch('/cuopt/request', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json', 'CLIENT-VERSION': 'custom' },
  body: JSON.stringify(routingPayload),
}).then(r => r.json());

// Browser — poll until the solver is done.
async function waitForSolution(reqId, intervalMs = 2000) {
  while (true) {
    const body = await fetch(`/cuopt/solution/${reqId}`).then(r => r.json());
    if (body.reqId) {                   // IdModel — still running
      await new Promise(res => setTimeout(res, intervalMs));
      continue;
    }
    return body;                        // SolutionModel — done
  }
}

// Browser on the skin subdomain — list models via Llama Stack catch-all.
const models = await fetch('/v1/models').then(r => r.json());

// Server-side (Next.js API route) — same solve via the in-cluster env var.
const resp = await fetch(`${process.env.CUOPT_ENDPOINT}/cuopt/request`, {
  method: 'POST',
  headers: { 'Content-Type': 'application/json', 'CLIENT-VERSION': 'custom' },
  body: JSON.stringify(routingPayload),
});
```

```bash
# External integrator against a dedicated backend ingress with the API-key gate on.
TOKEN="<value from ORM output 'Ingress API Key'>"
HOST="https://cuopt-<id>.<lb-ip>.nip.io"

curl -s -H "Authorization: Bearer $TOKEN" $HOST/v2/health/ready

REQ=$(curl -s -X POST $HOST/cuopt/request \
  -H 'Content-Type: application/json' \
  -H 'CLIENT-VERSION: custom' \
  -H "Authorization: Bearer $TOKEN" \
  -d @vrp.json | jq -r .reqId)

curl -s -H "Authorization: Bearer $TOKEN" $HOST/cuopt/solution/$REQ | jq .
```

---

## 6. Open Questions

These require runtime introspection of a live deployment or a version of
the source not present in this repo to resolve; until then they are
flagged rather than guessed.

- **Exact hostname format of the dedicated backend ingresses.**
  `docs/API_TOKENS.md` gives the shapes `cuopt-<id>.<lb-ip>.nip.io` and
  `llamastack-<id>.<lb-ip>.nip.io`, but the `<id>` suffix is derived from
  the Corrino canonical name (`deployment_name` post-`DEPLOY_NAME`
  substitution, truncated to 32 chars). The authoritative list is
  `kubectl get ingress -n default` after apply.
- **Exact Llama Stack v0.0.3 route paths.** The shipped config enables
  nine API groups (`agents`, `datasetio`, `eval`, `files`, `inference`,
  `safety`, `scoring`, `tool_runtime`, `vector_io`), but the HTTP paths
  Llama Stack publishes for each group have shifted across releases.
  Verify against the container's OpenAPI spec at runtime.
- **Streaming support for `POST /v1/chat/completions` / `/v1/responses`.**
  Standard in upstream Llama Stack and the OpenAI-compat layer; not
  verified against this specific OCI-adapter build.
- **Safety provider.** Commented out in
  `llamastack_inference_config.yaml`. The `safety` API is listed in
  `apis:` so the routes exist, but calls will fail until a provider
  (e.g. `llama-guard`) is registered.

---

## 7. Source of Truth

| Concern                                               | File                                                                                 |
|-------------------------------------------------------|--------------------------------------------------------------------------------------|
| Deployment group JSON (`cuopt` + `llamastack` recipes)| `ai-accelerator-tf/blueprint_files.tf` — `local._cuopt_blueprint`                    |
| Skin deployments, env vars, ingress path-prefix rules | `ai-accelerator-tf/blueprint_files.tf` — `local._cuopt_frontend_deployments`         |
| Skin catalog (image URI, port, subdomain)             | `ai-accelerator-tf/schemas/frontend_skins.yaml`                                      |
| Llama Stack provider config                           | `ai-accelerator-tf/files/llamastack_inference_config.yaml`                           |
| Bearer-token gate annotations + validator             | `ai-accelerator-tf/app-ingress-auth.tf`, `docs/API_TOKENS.md`                        |
| Bearer-token-annotation invariant test                | `ai-accelerator-tf/schemas/tests/test_blueprint_structure.py::test_every_backend_recipe_has_annotation` |
| `DEPLOY_NAME` placeholder + deployment immutability   | `docs/BLUEPRINT_LIFECYCLE.md`, `ai-accelerator-tf/vars.tf`                           |
| cuopt REST route implementation                       | `NVIDIA/cuopt` — `python/cuopt_server/cuopt_server/webserver.py`                     |
| cuopt CLIENT-VERSION handling                         | `NVIDIA/cuopt` — `python/cuopt_server/cuopt_server/utils/job_queue.py`               |
| cuopt OpenAPI spec                                    | https://docs.nvidia.com/cuopt/user-guide/latest/open-api.html                        |
| Llama Stack project docs                              | https://llama-stack.readthedocs.io/                                                  |
| Corrino manifest templates (Deployment / Service / Ingress) | `corrino/api/manifests/templates/recipe_{deployment,service,ingress}_template.yaml` |

---

## 8. Updating This Doc

Manually maintained; no drift-check test. Update whenever:

- `ai-accelerator-tf/blueprint_files.tf` changes `local._cuopt_blueprint`
  (cuopt or llamastack recipe fields) or `local._cuopt_frontend_deployments`
  (env vars, ingress path rules, `container_port`).
- `ai-accelerator-tf/schemas/frontend_skins.yaml` changes the cuopt skin
  catalog (subdomain, container_port, new skins).
- `ai-accelerator-tf/files/llamastack_inference_config.yaml` changes the
  `apis:` list, providers, or server port.
- `ai-accelerator-tf/app-ingress-auth.tf` changes the bearer-token
  annotation shape.
- `recipe_image_uri` bumps cuopt to a new NIM release — spot-check
  `webserver.py` against §2's endpoint tables.

### "When in doubt" rule

> Would a skin author or external integrator need this to call the pack's
> backends correctly? If yes, document it. If the answer depends on
> runtime state not visible in source, add it to §6 Open Questions rather
> than guessing.
