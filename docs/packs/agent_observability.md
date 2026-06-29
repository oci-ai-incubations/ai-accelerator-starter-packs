# Agent Observability (Langfuse)

The **Agent Observability** pack is an AI Accelerator Pack that deploys an enterprise-grade [Langfuse](https://langfuse.com) stack — LLM/agent tracing, evals, prompt management, and analytics — on Oracle Cloud Infrastructure (OCI). Unlike a single-pod developer setup, it is backed by **managed OCI services** and a **highly-available ClickHouse** cluster, with all secrets generated at deploy time, optional OIDC single sign-on, and TLS ingress. It also ships an optional **agentic model** served by OCI Generative AI so teams have an inference endpoint to instrument out of the box.

## What You Get

- **Hardware:** CPU-only Oracle Kubernetes Engine (OKE) cluster (`VM.Standard.E5.Flex`). No GPUs run on the cluster — the optional agentic model is hosted on an OCI GenAI **Dedicated AI Cluster** (managed GPUs), not on OKE.
- **Software:**
  - **Langfuse Web + Worker** (`langfuse/langfuse:3`) deployed as an OCI AI Blueprints deployment-group. The web tier runs multiple replicas behind a TLS ingress; the worker handles async event processing.
  - **LlamaStack gateway** — an OpenAI-compatible endpoint wired to the agentic model so you can point SDKs/agents at it and see traces land in Langfuse immediately.
  - **HA ClickHouse** (OLAP store) managed by the [Altinity clickhouse-operator](https://github.com/Altinity/clickhouse-operator): a single shard with 2 replicas plus a 3-node ClickHouse Keeper ensemble for replication.
- **Managed OCI backing services** (provisioned in Terraform, injected into the blueprint):
  - **OCI Object Storage** (S3-compatible) for Langfuse event/media blob storage.
  - **OCI Database with PostgreSQL** (HA, multi-instance) for the transactional store.
  - **OCI Cache** (managed Redis, TLS) for the event queue.
- **Agentic model (optional):** bring an existing OCI GenAI endpoint OCID, **or** create a new Dedicated AI Cluster and import a model from Hugging Face (default `Qwen/Qwen3.6-35B-A3B` on `H100_X2`).
- **Security:** all application secrets (`NEXTAUTH_SECRET`, `SALT`, `ENCRYPTION_KEY`, DB/ClickHouse passwords) are generated at deploy time and stored as Kubernetes secrets — never written into the blueprint. Sign-up is disabled with an admin bootstrapped at deploy; optional **OIDC SSO** integrates with OCI IAM Identity Domains (IDCS) config-only (no custom image).

## Use Case

As teams move from LLM prototypes to production agents, they need to see what their agents actually did — every prompt, tool call, token, latency, and cost — and to run evals and manage prompts. Langfuse is the leading open-source platform for this, but a credible production deployment needs durable storage, a real OLAP backend with replication, managed databases, secret management, SSO, and TLS — not the single-pod dev recipe.

The Agent Observability pack delivers that production posture in one click:

- Stand up Langfuse backed by managed OCI Object Storage, PostgreSQL, and Cache, with HA ClickHouse for analytics.
- Log in via the bootstrapped admin (or wire OIDC SSO to your identity domain) — public sign-up is off by default.
- Point any Langfuse SDK (or the bundled LlamaStack OpenAI-compatible gateway) at the instance and watch traces, sessions, scores, and dashboards populate.
- Optionally serve an agentic model on a managed OCI GenAI Dedicated AI Cluster and instrument it end-to-end.

## Specs, Additional References, and Architecture

> **Deep dive:** For a component-by-component breakdown — deployment footprint, the role of
> each component, how they wire together, and the separation of concerns (what is managed by
> OCI vs. the Altinity operator vs. Corrino vs. Terraform) — see
> [**Advanced Architecture**](./agent_observability/architecture.md).

**Deployment Architecture on OCI**

```
┌───────────────────────────────────────────────────────────────────────────────┐
│  OCI Tenancy                                                                    │
│                                                                                 │
│  ┌───────────────────────────────────────────────────────────────────────────┐ │
│  │  VCN                                                                        │ │
│  │                                                                            │ │
│  │  ┌──────────────────────────────────────────────────────────────────────┐ │ │
│  │  │  OKE Cluster (CPU-only, VM.Standard.E5.Flex)                          │ │ │
│  │  │                                                                        │ │ │
│  │  │  ┌──────────────────────────────────────────────────────────────────┐ │ │ │
│  │  │  │  Corrino blueprint deployment-group                               │ │ │ │
│  │  │  │   • langfuse-web (N replicas, ingress: langfuse.<fqdn>)           │ │ │ │
│  │  │  │   • langfuse-worker (async events)                               │ │ │ │
│  │  │  │   • llamastack (OpenAI-compatible gateway → GenAI endpoint)       │ │ │ │
│  │  │  └───────────┬───────────────┬───────────────┬──────────────────────┘ │ │ │
│  │  │              │               │               │                         │ │ │
│  │  │  ┌───────────▼───────────────────────────────────────────────────────┐ │ │ │
│  │  │  │  ClickHouse (Altinity operator, namespace: clickhouse)            │ │ │ │
│  │  │  │   • 1 shard × 2 replicas (ReplicatedMergeTree)                    │ │ │ │
│  │  │  │   • 3-node ClickHouse Keeper ensemble                             │ │ │ │
│  │  │  └───────────────────────────────────────────────────────────────────┘ │ │ │
│  │  │                                                                        │ │ │
│  │  │  ┌──────────────┐   ┌──────────────┐                                   │ │ │
│  │  │  │  Ingress /   │   │  Blueprints  │                                   │ │ │
│  │  │  │ Load Balancer│   │  Portal      │                                   │ │ │
│  │  │  │ (TLS, LE)    │   │              │                                   │ │ │
│  │  │  └──────┬───────┘   └──────────────┘                                   │ │ │
│  │  └─────────┼──────────────────────────────────────────────────────────────┘ │ │
│  └────────────┼────────────────────────────────────────────────────────────────┘ │
│               │                managed OCI services (TLS, private subnet)          │
│   ┌───────────┼──────────────┬─────────────────────┬───────────────────────────┐ │
│   ▼           ▼              ▼                     ▼                           │ │
│ ┌────────────────┐ ┌──────────────────┐ ┌──────────────────┐ ┌───────────────────┐ │
│ │ OCI Object     │ │ OCI Database     │ │ OCI Cache        │ │ OCI Generative AI │ │
│ │ Storage (S3)   │ │ PostgreSQL (HA)  │ │ Redis (TLS)      │ │ Dedicated AI      │ │
│ │ events + media │ │ transactional DB │ │ event queue      │ │ Cluster + endpoint│ │
│ └────────────────┘ └──────────────────┘ └──────────────────┘ │ (existing or      │ │
│                                                                │  create: Qwen3.6) │ │
│                                                                └───────────────────┘ │
└───────────────────────────────────────────────────────────────────────────────┘
                │
                ▼
        Langfuse Web UI (https://langfuse.<fqdn>)
   (traces, sessions, evals, prompts, dashboards;
    OIDC SSO optional, sign-up disabled)
```

### Backing services

| Service | Implementation | Purpose |
|---|---|---|
| Blob storage | OCI Object Storage (S3-compatible) + customer secret key | Langfuse event/media uploads (`events/`, `media/` prefixes) |
| Transactional DB | OCI Database with PostgreSQL (`E5.Flex`, multi-instance) | Langfuse core relational store |
| Cache / queue | OCI Cache (managed Redis, TLS `rediss://`) | Langfuse event queue |
| OLAP | ClickHouse via Altinity operator (1 shard × 2 replicas + 3 keepers) | Langfuse analytics/traces store |
| Agentic model | OCI GenAI endpoint (existing OCID) or new Dedicated AI Cluster + imported model | Inference endpoint for agents (OpenAI-compatible via LlamaStack) |

### Key Tunables

| Control | Default | Notes |
|---|---|---|
| Deployment size | `small` | `small` / `medium` — scales worker nodes, PostgreSQL/Cache sizing, ClickHouse resources & PVC. |
| Agentic model mode | `existing` | `existing` (reference an OCI GenAI endpoint OCID) / `create` (provision a Dedicated AI Cluster + import the model — billed hourly). |
| Model (create mode) | `Qwen/Qwen3.6-35B-A3B` | Hugging Face model id to import; requires `H100_X2` for the default model. |
| OIDC SSO | disabled | Set issuer/client-id/client-secret to enable. Works with OCI IAM Identity Domains; the domain must emit a domain-specific issuer and register the redirect URI `https://<langfuse-host>/api/auth/callback/custom`. |

## Deployment and Access

You can deploy the Agent Observability pack from Terraform directly, or by following the steps below from the base level of this repository:

```bash
python3 -m venv venv
source venv/bin/activate
pip3 install -r requirements.txt

python3 create_final_schema.py -c agent_observability

zip -r agent_observability.zip ai-accelerator-tf
```

Then, go to "stacks" in the console and upload the generated zip. Fill out the fields, click next, and select to run the apply job.

After deployment you get:

- **OCI AI Blueprints Portal** — URL exposed by the stack; manages blueprint lifecycle.
- **Langfuse UI** (`https://langfuse.<fqdn>`) — sign in with the bootstrapped admin (the Administrator email/password you supplied), or via OIDC SSO if configured. Public sign-up is disabled.
- **Agentic model inference URL** — an OpenAI-compatible endpoint (via LlamaStack) wired to your OCI GenAI endpoint, ready to instrument with Langfuse.

## Further Reading

- [**Advanced Architecture**](./agent_observability/architecture.md) — deployment footprint, component roles, how everything ties together, and separation of concerns.
- [**Connect an Agent**](./agent_observability/connect-an-agent.md) — point an agent at the DAC model via LlamaStack and see traces land in Langfuse (includes a runnable local script).
