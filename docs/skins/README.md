# Frontend Skins

Each starter pack category has a catalog of "skins" — alternative frontend UIs for the same backend. Skins are defined in `ai-accelerator-tf/schemas/frontend_skins.yaml`.

## Blueprint packs (`cuopt`, `vss`, `paas_rag`, `warehouse_pick_path`) — multi-select

These packs support **multi-skin**: enable one or more skins simultaneously from ORM. Each enabled skin deploys its own frontend container on its own ingress subdomain. You can compare UIs side-by-side without redeploying the backend.

- **At least one skin is required** per blueprint pack (enforced by a Terraform precondition). Unchecking every skin produces a plan-time error.
- The ORM wizard shows per-skin checkboxes in a dedicated **"Frontend Skins"** variableGroup (inserted right after Deployment Configuration).
- The `frontend_skin_urls` output maps each enabled skin's display name to its HTTPS URL.

## Helm packs (`enterprise_rag`, `enterprise_rag_aiq`) — single-select dropdown

These packs deploy a single frontend at a time via Helm (`nvidia-blueprint-rag`) and expose a **single-select dropdown** in the same "Frontend Skins" variableGroup. Users pick one skin from the pack's catalog; multi-skin isn't supported here because the Helm chart's frontend sub-chart only deploys one frontend image.

- The ORM wizard shows a `Frontend Skin` enum variable (named `skin_enterprise_rag` / `skin_enterprise_rag_aiq`) with the catalog's skin keys as choices.
- Default is the catalog's top-level `default:` key.
- `frontend_skin_urls` is intentionally empty for Helm packs; the user-facing URL is `starter_pack_url`.

---

> **Writing a skin?** For the outbound API contract — what backends a skin
> can call, what ports/paths are routed via ingress, and what env vars the
> container receives — see [BACKEND_API_CONTRACT.md](BACKEND_API_CONTRACT.md).

## Adding a new skin

The checklist depends on which pack type you're adding to.

### Blueprint pack skin (multi-select)

1. `ai-accelerator-tf/schemas/frontend_skins.yaml` — add the catalog entry (key, image_uri, provider, container_port, subdomain, `variable_name`, `default_enabled`).
2. `ai-accelerator-tf/vars.tf` — declare `variable "skin_<name>" { type = bool, default = <bool> }`.
3. `ai-accelerator-tf/frontend-skins.tf` — add the variable to `local.skin_enabled_map`.

### Helm pack skin (single-select enum)

1. `ai-accelerator-tf/schemas/frontend_skins.yaml` — add the catalog entry (key, image_uri, provider, container_port, subdomain). **Omit** `variable_name` and `default_enabled` — the dropdown is one pack-level variable, not per-skin.
2. If the pack already has a `skin_<category>` enum variable in `vars.tf` (it does, for `enterprise_rag` and `enterprise_rag_aiq`), no vars.tf change needed — the enum list is auto-populated from the catalog at schema-generation time.
3. If this is the first skin for a new Helm pack, declare `variable "skin_<category>" { type = string, default = "" }` in `vars.tf` AND add `"<category>" = var.skin_<category>` to `local.helm_skin_enum_map` in `frontend-skins.tf`.

### In both cases

Regenerate schemas (`python create_final_schema.py --all`) and run tests (`terraform test` + `pytest ai-accelerator-tf/schemas/tests/`). The structural tests catch forgotten steps:

- `test_skin_catalog_matches_terraform` — blueprint pack drift
- `test_helm_packs_expose_single_skin_enum` — Helm pack drift
- `test_blueprint_structure.py::test_every_backend_recipe_has_annotation` — ensures new backend recipes carry the bearer-token annotation

## Core App vs Partner Contributed

Each skin is labeled as either **Core App** or **Partner Contributed** in the ORM UI to help you make an informed choice.

**Core App** skins are built and maintained by Oracle. These frontends are fully tested against the underlying AI infrastructure, receive regular updates, and are supported as part of the AI Accelerator Pack. Oracle stands behind the quality and reliability of Core App skins.

**Partner Contributed** skins are built by third-party partners and the open-source community around the same core AI infrastructure that Oracle deploys. These frontends may offer additional functionality, features, or alternative workflows not found in the Core App. However, they have not been tested to the same degree as Core App skins, and Oracle does not take responsibility for their behavior, reliability, or security. Use Partner Contributed skins at your own discretion — they are provided as-is.

When in doubt, enable the Core App skin for a fully supported experience.

## Vehicle Delivery Route Optimizer (`cuopt`)

**Backend repository:** [NVIDIA/cuopt](https://github.com/NVIDIA/cuopt) — the GPU-accelerated vehicle routing solver that all cuopt skins connect to.

| Skin Name | Type | Provider | Default Enabled |
|---|---|---|---|
| Vehicle Route Optimizer Frontend (Core App) | Core App | Oracle | Yes |
| Oracle Interactive - Route visualization (Partner Contributed) | Partner Contributed | Oracle | No |

### Vehicle Route Optimizer Frontend (Core App)

| Field | Value |
|---|---|
| Type | Core App |
| Provider | Oracle |
| Image | `iad.ocir.io/iduyx1qnmway/corrino-devops-repository:cuopt-interactive-frontend-v0.0.2` |
| Version | v0.0.2 |
| Container Port | 3000 |
| Repository | [vehicle_route_optimizer_frontend](https://github.com/oci-ai-incubations/vehicle_route_optimizer_frontend) |

Oracle's core frontend for the Vehicle Delivery Route Optimizer. Provides the primary interface for interacting with the NVIDIA cuOpt GPU-accelerated solver, submitting vehicle routing optimization problems, and viewing results. This is the fully tested, Oracle-supported frontend for this pack.

### Oracle Interactive - Route visualization (Partner Contributed)

| Field | Value |
|---|---|
| Type | Partner Contributed |
| Provider | Oracle |
| Image | `iad.ocir.io/iduyx1qnmway/corrino-devops-repository:cuopt-interactive-frontend-v0.0.3` |
| Version | v0.0.3 |
| Container Port | 80 |
| Repository | [cuopt-ev-routing-frontend](https://github.com/oci-ai-incubations/cuopt-ev-routing-frontend) |

Partner-contributed interactive route visualization UI for fleet delivery optimization. Supports Google Maps and Leaflet map rendering, drag-and-drop route editing, vehicle fleet configuration, and real-time optimization result display. Includes an admin login for managing optimization sessions and a chat-powered natural language interface for building and modifying route constraints via OCI GenAI. This frontend offers additional features beyond the Core App but has not been tested to the same standard.

## Video Search and Summarization (`vss`)

**Backend repository:** [NVIDIA-AI-Blueprints/video-search-and-summarization](https://github.com/NVIDIA-AI-Blueprints/video-search-and-summarization/releases/tag/v2.4.1) (v2.4.1) — the NVIDIA blueprint for video ingestion, scene detection, and semantic search that all vss skins connect to. **Note:** We pin to v2.4.1. The 3.0.0 release introduces significant breaking changes to the repo structure and APIs.

| Skin Name | Type | Provider | Default Enabled |
|---|---|---|---|
| Oracle Custom - Enhanced search (Core App) | Core App | Oracle | Yes |

### Oracle Custom - Enhanced search (Core App)

| Field | Value |
|---|---|
| Type | Core App |
| Provider | Oracle |
| Image | `iad.ocir.io/iduyx1qnmway/corrino-devops-repository:vss-oracle-ux-dev-0.0.4` |
| Version | 0.0.4 |
| Container Port | 3000 |
| Repository | [vss-oracle-ux](https://github.com/oci-ai-incubations/vss-oracle-ux) |

Oracle-built frontend for video search and summarization. Upload videos, search across ingested content using natural language queries, view AI-generated scene summaries with timestamps, and play back flagged segments directly in the browser. Includes a video timeline with scene markers and a document-style download service for exporting analysis results.

## Enterprise Knowledge Chat Agent - Self-Hosted AI Models (`enterprise_rag`)

**Backend repository:** [oci-ai-incubations/nvidia-rag-oci](https://github.com/oci-ai-incubations/nvidia-rag-oci) — the OCI-adapted NVIDIA RAG pipeline (ingestor server, rag server, NIM microservices) that the enterprise_rag skin connects to.

| Skin Name | Type | Provider | Default Enabled |
|---|---|---|---|
| Oracle RAG - Document chat (Core App) | Core App | Oracle | Yes |

### Oracle RAG - Document chat (Core App)

| Field | Value |
|---|---|
| Type | Core App |
| Provider | Oracle |
| Image | `iad.ocir.io/iduyx1qnmway/enterprise-rag-frontend:v0.0.2` |
| Version | v0.0.2 |
| Container Port | 3000 |
| Repository | [enterprise-rag-frontend](https://github.com/oci-ai-incubations/enterprise-rag-frontend) |

Chat-based document Q&A interface for the self-hosted enterprise RAG pipeline. Upload documents (PDF, DOCX, TXT), ask questions in natural language, and receive cited answers grounded in your uploaded content. The UI displays source citations with page references, supports multi-turn conversations, and provides document management for uploading, listing, and deleting ingested files.

## Enterprise Knowledge Chat Agent - Managed AI Models (`paas_rag`)

**Backend repository:** [oci-ai-incubations/oraclenet-llama-stack](https://github.com/oci-ai-incubations/oraclenet-llama-stack) — the Llama Stack-based RAG backend using OCI GenAI PaaS and Oracle 26ai that the paas_rag skin connects to.

| Skin Name | Type | Provider | Default Enabled |
|---|---|---|---|
| Oracle Net - Chat interface (Core App) | Core App | Oracle | Yes |

### Oracle Net - Chat interface (Core App)

| Field | Value |
|---|---|
| Type | Core App |
| Provider | Oracle |
| Image | `iad.ocir.io/iduyx1qnmway/corrino-devops-repository/oracle-net-frontend:v0.0.3` |
| Version | v0.0.3 |
| Container Port | 3000 |
| Repository | [oraclenet-frontend](https://github.com/oci-ai-incubations/oraclenet-frontend) |

Oracle Net chat interface for the managed enterprise RAG pipeline. Provides document upload, vector-search-powered Q&A with cited answers, and multi-turn conversation support. Powered by OCI GenAI PaaS for LLM inference and Oracle 26ai for vector storage, requiring no GPU infrastructure. Includes model selection for choosing between available OCI GenAI models.

## Enterprise Agentic AI Starter Kit (`enterprise_rag_aiq`)

**Backend repository:** [NVIDIA-AI-Blueprints/aiq](https://github.com/NVIDIA-AI-Blueprints/aiq) — the NVIDIA AIQ toolkit for agentic AI workflows that the enterprise_rag_aiq skin connects to.

| Skin Name | Type | Provider | Default Enabled |
|---|---|---|---|
| NVIDIA AIRA - Agentic workflows (Core App) | Core App | NVIDIA | Yes |

### NVIDIA AIRA - Agentic workflows (Core App)

| Field | Value |
|---|---|
| Type | Core App |
| Provider | NVIDIA |
| Image | `nvcr.io/nvidia/blueprint/aira-frontend:v1.2.0` |
| Version | v1.2.0 |
| Container Port | 3000 |
| Repository | [NVIDIA AIQ Frontends](https://github.com/NVIDIA-AI-Blueprints/aiq/tree/develop/frontends/ui) |

NVIDIA AIRA (AI Research Assistant) frontend for the agentic AI starter kit. Provides a chat-based interface for interacting with AI agents that can reason over documents, execute multi-step workflows, and use tools. Includes observability integration with Phoenix for tracing agent execution, viewing tool call chains, and debugging agentic reasoning paths.

## Warehouse Pick Path Optimizer (`warehouse_pick_path`)

**Backend repository:** [oci-ai-incubations/oci-warehouse-pick-path-optimizer](https://github.com/oci-ai-incubations/oci-warehouse-pick-path-optimizer) — FastAPI backend with NVIDIA cuOpt GPU solver for warehouse pick path optimization, backed by Oracle 26ai for data persistence.

| Skin Name | Type | Provider | Default |
|---|---|---|---|
| Warehouse Pick Path Optimizer Frontend (Core App) | Core App | Oracle | Yes |

### Warehouse Pick Path Optimizer Frontend (Core App)

| Field | Value |
|---|---|
| Type | Core App |
| Provider | Oracle |
| Image | `iad.ocir.io/iduyx1qnmway/corrino-devops-repository/warehouse-pick-path-optimizer-fe` |
| Version | Tracks the same short-SHA tag as the backend; see `SOFTWARE_VERSIONS.md` |
| Container Port | 3000 |
| Repository | [oci-warehouse-pick-path-optimizer](https://github.com/oci-ai-incubations/oci-warehouse-pick-path-optimizer) |

Oracle's core frontend for the Warehouse Pick Path Optimizer. Provides CSV uploads for warehouse layout / SKU master / inventory snapshot / order batch, a form for configuring picker count, solver time, wave mode, and direction (inbound vs outbound), and an interactive results view with a 2D route map, per-picker tables, and CSV export of the solution. This is the fully tested, Oracle-supported frontend for this pack.
