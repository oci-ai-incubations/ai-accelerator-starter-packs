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

(to be written)

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
