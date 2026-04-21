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

(to be written)

### 3.2 vss (Video Search and Summarization)

(to be written)

### 3.3 paas_rag (Managed Enterprise Chat Agent)

(to be written)

### 3.4 enterprise_rag (Self-Hosted Enterprise Chat Agent)

(to be written)

### 3.5 enterprise_rag_aiq (Enterprise Agentic AI Starter Kit)

(to be written)

## 4. Updating This Doc

(to be written)
