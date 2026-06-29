# Agent Observability Pack — Advanced Architecture

This document describes how the Agent Observability (Langfuse) pack is assembled: what
gets deployed, what each component does, how the pieces wire together, and which layer
owns which responsibility.

The pack is a **hybrid** deployment. Stateful backing stores run on **OCI managed
services** wherever a managed equivalent exists (Postgres, Cache/Redis, Object Storage,
Generative AI); the **application tier** (Langfuse web/worker + the LlamaStack gateway)
runs on OKE through a **Corrino blueprint**; and the one store with no OCI managed
equivalent — **ClickHouse** — runs in-cluster under the Altinity operator. Everything is
provisioned and wired by Terraform in a single `apply`.

---

## 1. Deployment footprint

### A. OCI managed services (control plane = OCI, *outside* the OKE cluster)

| Service | Terraform resource | Purpose | Key settings |
|---|---|---|---|
| **OCI Database with PostgreSQL** | `oci_psql_db_system.langfuse_pg` | Langfuse transactional store | `PostgreSQL.VM.Standard.E5.Flex`, `db_version 14`, **2 instances** (HA primary + reader), regionally-durable optimized storage, on the **private DB subnet**, TLS (`sslmode=require`) on **5432** |
| **OCI Cache (Redis)** | `oci_redis_redis_cluster.langfuse_redis` | Ingestion queue + cache | `REDIS_7_0`, 2 nodes, on the private DB subnet, **TLS mandatory** → `rediss://…:6379` |
| **OCI Object Storage** | `oci_objectstorage_bucket.paas_rag_bucket` + `oci_identity_customer_secret_key` | Trace event blobs + media | `NoPublicAccess`, `Standard`, **versioning enabled**, S3-compat access via a customer secret key; `events/` and `media/` prefixes |
| **OCI Generative AI** *(create mode)* | `oci_generative_ai_imported_model` → `oci_generative_ai_dedicated_ai_cluster` → `oci_generative_ai_endpoint` | The model agents call | HF model import, `HOSTING` DAC (`unit_shape` e.g. `H100_X2`, billed hourly), OpenAI-compatible inference endpoint in `genai_region` |

> In **existing** GenAI mode (`agent_obs_genai_mode = "existing"`, the default) nothing is
> provisioned — the pack just references an existing endpoint OCID.

### B. In-cluster, managed by the Altinity operator (Terraform → Helm + CRs)

| Component | Source | Purpose |
|---|---|---|
| **clickhouse-operator** | `helm_release.clickhouse_operator` (chart `0.27.1`) in the `clickhouse` namespace | Reconciles the ClickHouse CRs into StatefulSets/PVCs/Services |
| **ClickHouse servers** (`chi-langfuse-default-0-*`) | `ClickHouseInstallation` CR | The OLAP store for traces/observations/scores — **1 shard × 2–3 replicas** |
| **ClickHouse Keeper** (`chk-langfuse-keeper-0-*`) | `ClickHouseKeeperInstallation` CR | Raft consensus that keeps the ClickHouse replicas in sync |
| **`clickhouse-apply` Job** + RBAC + ConfigMap | `kubernetes_job_v1` etc. | Applies the CRs (ORM-safe; avoids a plan-time CRD dependency) |

### C. In-cluster, managed by the Corrino blueprint (the application tier)

| Deployment | Image | Ingress | Purpose |
|---|---|---|---|
| **langfuse-web** (pod shows as `agent-observability-<hex>`) | `langfuse/langfuse:3` | `langfuse.<fqdn>` | Dashboard UI + public API + auth + synchronous trace ingest |
| **langfuse-worker** | `langfuse/langfuse-worker:3` | none | Async queue drain → durable ClickHouse writes + background jobs |
| **llamastack** | `llama-stack-oci:pr-d74b10d` | `llamastack.<fqdn>` | OpenAI-compatible gateway exposing the OCI GenAI DAC model |

### D. Shared platform (provisioned by the rest of the stack)

OKE cluster + CPU shared node pool · ingress-nginx (public LB) · cert-manager (TLS) ·
the Corrino control plane (`corrino-cp`) that consumes the blueprint · the
`langfuse-secrets` Kubernetes Secret that bridges the managed-service credentials into the
blueprint pods.

---

## 2. Role of each component

**OCI Postgres** — Langfuse's *source of truth* for everything transactional: organizations,
projects, users, API keys, dashboards, prompt configs, and the run-time settings. Small,
relational, consistency-critical data. Runs HA (2 instances) because losing it logs everyone
out and stalls ingestion.

**OCI Cache (Redis)** — the *buffer* between fast ingest and slow durable writes. `langfuse-web`
pushes incoming trace events onto a Redis queue and returns `200` immediately; `langfuse-worker`
consumes from it. Redis also serves as Langfuse's general-purpose cache. TLS is enforced by the
service, so Langfuse connects with `rediss://`.

**OCI Object Storage** — *blob storage* for the raw, potentially large payloads: the full event
bodies (`events/`) that web stages on ingest, and multimodal `media/` attachments. ClickHouse
stores the structured, queryable projection; Object Storage holds the originals. Versioning is on
so writes are never silently lost.

**ClickHouse (servers + Keeper + operator)** — the *analytical engine*. All trace
analytics — traces, observations, scores, token/cost/latency aggregates that the dashboard
charts — live here as columnar `ReplicatedMergeTree` data. HA comes from **replicas** (Langfuse
supports a single shard); **Keeper** is the consensus layer that keeps those replicas consistent;
the **operator** builds and maintains the whole thing from the CR. (See
[`architecture` notes in the build files] — `langfuse_clickhouse.tf`.)

**OCI Generative AI (DAC + endpoint)** — the *model being observed*. A dedicated, single-tenant
endpoint serving the agentic model (e.g. `Qwen3.6-35B-A3B`) over an OpenAI-compatible API.

**LlamaStack** — the *gateway/adapter*. It exposes a standard `/v1` OpenAI surface to agents and,
via its `remote::oci` provider, **enumerates and routes to** the GenAI endpoint(s) in the
configured compartment. Agents speak plain OpenAI to LlamaStack and never touch OCI auth.

**langfuse-web** — the *front door*: serves the UI and the `/api/public/*` API, owns auth
(bootstrapped admin via `LANGFUSE_INIT_*`, optional OIDC/IDCS SSO), validates inbound traces and
enqueues them, and reads Postgres + ClickHouse to render dashboards. It also seeds the org/project
and the **auto-provisioned API key** on first boot.

**langfuse-worker** — the *engine*: drains the Redis queue, pulls event blobs from Object Storage,
writes the durable rows into ClickHouse, and runs scheduled jobs (evals, batch exports, retention
cleanup, metrics rollups). No user ever talks to it.

---

## 3. How it all ties together

### Provisioning order (Terraform)

```
random_* secrets ─┐
OCI Postgres ──────┤
OCI Cache  ────────┼──▶ langfuse-secrets (k8s Secret) ──▶ Corrino blueprint ──▶ web / worker / llamastack
OCI Object Storage ┤                                          ▲
GenAI endpoint ────┘                                          │
clickhouse-operator ▶ CRs (apply Job) ▶ ClickHouse servers ───┘  (reachable via in-cluster DNS)
```

Terraform generates all credentials, stands up the four managed services + ClickHouse, writes
every connection string into the **`langfuse-secrets`** Secret, and *only then* submits the
blueprint (the blueprint job `depends_on` the Secret). The blueprint pods mount those secrets as
env via `recipe_environment_secrets` — **no credential is ever written into the blueprint JSON**.

### Runtime data flow

```
 agent ──OpenAI──▶ llamastack ──remote::oci──▶ OCI GenAI DAC endpoint
   │                                                (model inference)
   │ Langfuse SDK (client-side tracing)
   ▼
 langfuse-web  ──enqueue──▶  OCI Cache (Redis)
   │  └─ stage raw event ──▶ OCI Object Storage (events/)
   │                              │
   │                          consume│           read blob
   │                              ▼   ▼
   │                        langfuse-worker ──write──▶ ClickHouse (servers ⇄ Keeper)
   │
   └─ reads ──▶ OCI Postgres (projects/users/keys)  +  ClickHouse (trace analytics)  ──▶ dashboard
```

1. An agent calls **LlamaStack**, which routes to the **GenAI endpoint** and returns the
   completion.
2. The agent's **Langfuse SDK** posts the trace to **langfuse-web** `/api/public/ingestion`.
3. Web stages the raw event in **Object Storage**, drops a job on **Redis**, returns `200`.
4. **langfuse-worker** consumes the job, reads the blob, and writes structured rows to
   **ClickHouse** (replicated via **Keeper**).
5. A user opens **langfuse-web**, which reads **Postgres** (who/what/keys) and **ClickHouse**
   (the analytics) to render the dashboard.

### Connection wiring (what points at what)

| From | To | Via |
|---|---|---|
| web + worker | OCI Postgres | `DATABASE_URL` (`postgresql://…:5432/postgres?sslmode=require`) |
| web + worker | OCI Cache | `REDIS_CONNECTION_STRING` (`rediss://…:6379`) |
| web + worker | OCI Object Storage | `LANGFUSE_S3_*` + S3 access key (`*.compat.objectstorage.<region>.oci.customer-oci.com`) |
| web + worker | ClickHouse | `CLICKHOUSE_URL` (`http://clickhouse-langfuse.clickhouse.svc:8123`) + migration URL (`:9000`) |
| ClickHouse servers | Keeper | CHI `zookeeper.nodes` → `keeper-langfuse.clickhouse.svc:2181` |
| llamastack | GenAI endpoint | `remote::oci` provider, scoped to `OCI_COMPARTMENT_OCID` / `OCI_REGION` |
| agent | llamastack | OpenAI API at `https://llamastack.<fqdn>/v1` |

---

## 4. Separation of concerns — what is managed by what

| Layer | Owner | What it manages | Failure-domain note |
|---|---|---|---|
| **Managed data plane** | **OCI** (you only set size) | Postgres, Cache/Redis, Object Storage durability/patching/backups/HA | OCI handles node failure, patching, storage durability. You manage *sizing* and *credentials* only. |
| **Analytical store** | **Altinity operator** (in-cluster) | ClickHouse StatefulSets, PVCs, replication, Keeper quorum | You own this: capacity (PVC `oci-bv`), operator upgrades, replica count. No OCI managed fallback. |
| **Application tier** | **Corrino** (blueprint) | langfuse-web/worker + llamastack lifecycle, ingress, TLS, probes, replicas, secret mounts | Immutable deployments — change = undeploy/redeploy. Corrino reconciles to the blueprint. |
| **Credentials / wiring** | **Terraform** | Generates every secret, provisions managed services, writes `langfuse-secrets`, submits the blueprint | Single source of truth for the topology; no plaintext secrets in the blueprint JSON. |
| **Model serving** | **OCI Generative AI** | DAC capacity + endpoint for the agentic model | In *create* mode you own the DAC (hourly billing); in *existing* mode OCI/you own it out of band. |
| **Model access** | **LlamaStack** (blueprint) | OpenAI-compatible surface + OCI auth (instance principal) + endpoint discovery | Stateless adapter; re-enumerates endpoints on (re)start. |
| **Identity / auth** | **langfuse-web** + optional **OCI IAM Identity Domain** | Admin bootstrap, optional OIDC SSO, signup disabled | SSO app is customer-provisioned; the pack only consumes issuer/client-id/secret. |
| **Platform** | **OKE / stack** | Cluster, node pools, ingress-nginx, cert-manager, networking | DB subnet is private; security-list rules open 5432/6379 from nodes only. |

### Boundary rules worth remembering

- **Managed services are external to the blueprint.** Corrino never "knows" about Postgres/Redis/
  Object Storage/GenAI — it only sees env vars and the `langfuse-secrets` Secret. This keeps the
  blueprint portable and secret-free.
- **State lives off the application pods.** web/worker/llamastack are effectively stateless; all
  durable state is in Postgres, ClickHouse, Object Storage, or Redis. Pods can be rescheduled or
  redeployed freely.
- **ClickHouse is the only stateful thing you operate yourself** — because OCI has no managed
  ClickHouse. Everything else stateful is OCI's responsibility.
- **Networking**: the three managed data services sit on the **private DB subnet**; only the
  application ingresses (`langfuse.<fqdn>`, `llamastack.<fqdn>`) are public, fronted by
  ingress-nginx + cert-manager TLS.

---

## Source map

| Concern | File |
|---|---|
| Managed Postgres + sizing map | `ai-accelerator-tf/langfuse_postgres.tf` |
| Managed Cache/Redis | `ai-accelerator-tf/langfuse_redis.tf` |
| Object Storage bucket + S3 key | `ai-accelerator-tf/object_storage.tf` |
| ClickHouse operator + CHI/CHK | `ai-accelerator-tf/langfuse_clickhouse.tf` |
| Generated secrets + `langfuse-secrets` | `ai-accelerator-tf/langfuse_secrets.tf` |
| GenAI DAC / endpoint (+ modes) | `ai-accelerator-tf/langfuse_genai.tf` |
| Corrino blueprint (web/worker/llamastack) | `ai-accelerator-tf/agent_observability_blueprint.tf` |
| Connect an agent (hands-on) | `docs/packs/agent_observability/connect-an-agent.md` |
</content>
</invoke>
