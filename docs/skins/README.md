# Frontend Skins

Each starter pack category has a catalog of "skins" — alternative frontend UIs for the same backend. Skins are defined in `ai-accelerator-tf/schemas/frontend_skins.yaml`.

## Blueprint packs (`cuopt`, `vss`, `paas_rag`)

These packs support **multi-skin**: enable one or more skins simultaneously from ORM. Each enabled skin deploys its own frontend container on its own ingress subdomain. You can compare UIs side-by-side without redeploying the backend.

- **At least one skin is required** per blueprint pack (enforced by a Terraform precondition). Unchecking every skin produces a plan-time error.
- The ORM wizard shows per-skin checkboxes in the Deployment Configuration group.
- The `frontend_skin_urls` output maps each enabled skin's display name to its HTTPS URL.

## Helm packs (`enterprise_rag`, `enterprise_rag_aiq`)

These packs remain **single-skin** — each catalog entry has one skin. Multi-skin is out of scope for the Helm-driven deployments because their ingresses are managed by their Helm charts.

## Adding a new skin (3-file checklist)

1. `ai-accelerator-tf/schemas/frontend_skins.yaml` — add the catalog entry (key, image_uri, provider, container_port, subdomain, variable_name, default_enabled).
2. `ai-accelerator-tf/vars.tf` — declare the matching boolean variable.
3. `ai-accelerator-tf/frontend-skins.tf` — add the variable to `local.skin_enabled_map`.

Regenerate schemas (`python create_final_schema.py -c <category>`) and run tests (`terraform test` + `pytest ai-accelerator-tf/schemas/tests/`). The bidirectional drift test `test_skin_catalog_matches_terraform` catches any forgotten step.

## Core App vs Partner Contributed

Each skin is labeled as either **Core App** or **Partner Contributed** in the ORM UI to help you make an informed choice.

**Core App** skins are built and maintained by Oracle. These frontends are fully tested against the underlying AI infrastructure, receive regular updates, and are supported as part of the AI Accelerator Pack. Oracle stands behind the quality and reliability of Core App skins.

**Partner Contributed** skins are built by third-party partners and the open-source community around the same core AI infrastructure that Oracle deploys. These frontends may offer additional functionality, features, or alternative workflows not found in the Core App. However, they have not been tested to the same degree as Core App skins, and Oracle does not take responsibility for their behavior, reliability, or security. Use Partner Contributed skins at your own discretion — they are provided as-is.

When in doubt, enable the Core App skin for a fully supported experience.

## Vehicle Delivery Route Optimizer (`cuopt`)

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
