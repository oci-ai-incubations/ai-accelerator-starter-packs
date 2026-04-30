# Backend API Contract for Skin Authors

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

Two mechanisms are in play across the six packs. A given pack uses one of
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

| Pack                | Ingress paths | Env vars              |
|---------------------|---------------|-----------------------|
| cuopt               | ✓             | ✓                     |
| vss                 | —             | ✓                     |
| paas_rag            | ✓             | —                     |
| enterprise_rag      | — (Helm)      | ✓ (Helm chart values) |
| enterprise_rag_aiq  | — (Helm)      | — (chart-internal)    |
| warehouse_pick_path | ✓             | —                     |

"(Helm)" means the mechanism is wired by a Helm chart, not by
Terraform-declared `recipe_additional_ingress_ports` or
`recipe_container_env`. Helm packs do not stitch API paths onto the
frontend subdomain; the frontend reaches backends only via in-cluster
service DNS names.

- For **enterprise_rag**, those DNS names are in `frontend.envVars` in
  `helm-values/enterprise-rag-values.yaml` (Pattern 2, documented in §3.4).
- For **enterprise_rag_aiq**, the user-facing frontend is shipped by the
  `aiq2-web` v2.0.0 chart. The chart's `aiq.apps.frontend.env` block sets
  one backend-locating variable on the frontend container
  (`BACKEND_URL: http://aiq-backend:8000`) — a limited Pattern-2 surface,
  not the chart-internal-only setup that v1.x had. See §3.5.

## 3. Per-Pack Contract

Each pack has its own detailed contract document in [`contracts/`](contracts/):

| Pack | Contract | Patterns | Summary |
|---|---|---|---|
| cuopt | [`CUOPT.md`](contracts/CUOPT.md) | 1 + 2 | Ingress paths `/cuopt`, `/v1`; env vars `CUOPT_ENDPOINT`, `LLAMASTACK_ENDPOINT`, etc. |
| vss | [`VSS.md`](contracts/VSS.md) | 2 only | Env vars `VSS_API_BASE_URL`, `DATABASE_URL`, FSS mount; no ingress path routing. |
| paas_rag | [`PAAS_RAG.md`](contracts/PAAS_RAG.md) | 1 only | Ingress paths `/v1/models`, `/v1/responses`, `/v1/files`, etc.; no env vars. |
| enterprise_rag | [`ENTERPRISE_RAG.md`](contracts/ENTERPRISE_RAG.md) | 2 (Helm) | Helm chart `frontend.envVars`: `VITE_API_CHAT_URL`, `VITE_API_VDB_URL`, `VITE_MILVUS_URL`. |
| enterprise_rag_aiq | [`ENTERPRISE_RAG_AIQ.md`](contracts/ENTERPRISE_RAG_AIQ.md) | chart-internal | Two Helm releases; frontend endpoints are chart-internal, no skin-accessible env vars. |
| warehouse_pick_path | [`WAREHOUSE_PICK_PATH.md`](contracts/WAREHOUSE_PICK_PATH.md) | 1 only | Ingress path `/api`; backend has own JWT auth (httpOnly cookies). |

Each per-pack doc covers: deployment group composition, full endpoint surface per backend service, catalog summary, worked code examples, and the Terraform source of truth.

## 4. Updating This Doc

This document is **manually maintained**. There is no drift-check test
against the Terraform; keeping the contract accurate is part of the PR
that changes the source.

### When to edit

Update this doc or the relevant per-pack contract in `contracts/` whenever you change any of these files:

- `ai-accelerator-tf/blueprint_files.tf` — any edit to
  `local._cuopt_frontend_deployments`, `local._paas_rag_frontend_deployments`,
  or `local._wpp_frontend_deployments` (env vars, ingress paths, container port).
- `ai-accelerator-tf/app-vss-oracle-ux.tf` — any `env { ... }` block
  change on the VSS frontend deployment, any addition/removal in the
  `vss-oracle-ux-config` ConfigMap, or any new Secret reference the
  deployment consumes.
- `ai-accelerator-tf/helm-values/enterprise-rag-values.yaml` and
  `enterprise-rag-aiq-values.yaml` — changes to the `frontend:` block
  (envVars, port, image defaults).
- `ai-accelerator-tf/helm-values/aiq-aira-values.yaml` — changes to the
  `aiq.apps.frontend` block that drives the AIQ user-facing frontend.
  (Filename retains the `aiq-aira` prefix for backwards compatibility,
  but the file holds v2.0.0 values for the renamed `aiq2-web` chart.)
- `ai-accelerator-tf/schemas/frontend_skins.yaml` — changes to
  `container_port`, `subdomain`, or any new skin entries.
- `ai-accelerator-tf/ingress.tf` — changes to Helm-pack ingress rules
  (enterprise_rag / enterprise_rag_aiq).
- `ai-accelerator-tf/helm.tf` — changes to the `rag` or `aiq`
  helm_release `set` blocks, especially the chart-specific frontend
  image overrides wired to `local.frontend_skin_image_uri` (BUG-020
  invariant). `rag` uses flat `frontend.image.{repository,tag}`; `aiq`
  uses nested `aiq.apps.frontend.image.{repository,tag}` under the
  `aiq2-web` v2.0.0 chart.

### Where the source of truth lives

- Pattern 1 tables come from `recipe_additional_ingress_ports` arrays in
  `blueprint_files.tf`.
- Pattern 2 tables come from `recipe_container_env` arrays (blueprint
  packs), `env { ... }` blocks and ConfigMap data (VSS), or Helm chart
  values (Helm packs).
- Catalog summary tables come from `schemas/frontend_skins.yaml`.

### Known correctness tests

Two pytest structural checks lock claims that this doc depends on:

- `ai-accelerator-tf/schemas/tests/test_helm_skin_override.py` — asserts
  both the `rag` and `aiq` Helm releases carry their chart-specific
  frontend image set entries wired via
  `split(":", local.frontend_skin_image_uri)` (BUG-020 invariant). The
  expected key path is per-release: `rag` → `frontend.image.*`, `aiq`
  → `aiq.apps.frontend.image.*`. If a future Helm pack is added, add an
  entry to `RELEASES_REQUIRING_SKIN_OVERRIDE` (release name → expected
  key tuple) at the top of the test file.
- `ai-accelerator-tf/schemas/tests/test_blueprint_structure.py::test_every_backend_recipe_has_annotation`
  — keeps every backend recipe carrying the bearer-token annotation
  (see `docs/API_TOKENS.md`).

### "When in doubt" rule

> Would a skin author need to read it to wire their frontend? If yes,
> document it.
