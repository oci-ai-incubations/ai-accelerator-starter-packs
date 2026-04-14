# Frontend Skins

Frontend skins let you choose which UI is deployed for each AI Accelerator Pack. During stack creation in OCI Resource Manager, the **Frontend Skin** dropdown in the Deployment Configuration section lets you select from available options for your chosen pack. Each skin is a container image that provides a different frontend experience.

Only one skin is active per deployment. To switch skins, update the selection and re-apply the stack.

## Core App vs Partner Contributed

Each skin is labeled as either **Core App** or **Partner Contributed** in the ORM dropdown to help you make an informed choice.

**Core App** skins are built and maintained by Oracle. These frontends are fully tested against the underlying AI infrastructure, receive regular updates, and are supported as part of the AI Accelerator Pack. Oracle stands behind the quality and reliability of Core App skins.

**Partner Contributed** skins are built by third-party partners and the open-source community around the same core AI infrastructure that Oracle deploys. These frontends may offer additional functionality, features, or alternative workflows not found in the Core App. However, they have not been tested to the same degree as Core App skins, and Oracle does not take responsibility for their behavior, reliability, or security. Use Partner Contributed skins at your own discretion — they are provided as-is.

When in doubt, select the Core App skin for a fully supported experience.

## Vehicle Delivery Route Optimizer (`cuopt`)

| Skin Name | Type | Provider | Default |
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
| Repository | [vehicle_route_optimizer_frontend](https://github.com/oci-ai-incubations/vehicle_route_optimizer_frontend) |

Oracle's core frontend for the Vehicle Delivery Route Optimizer. Provides the primary interface for interacting with the NVIDIA cuOpt GPU-accelerated solver, submitting vehicle routing optimization problems, and viewing results. This is the fully tested, Oracle-supported frontend for this pack.

### Oracle Interactive - Route visualization (Partner Contributed)

| Field | Value |
|---|---|
| Type | Partner Contributed |
| Provider | Oracle |
| Image | `iad.ocir.io/iduyx1qnmway/corrino-devops-repository:cuopt-interactive-frontend-v0.0.3` |
| Version | v0.0.3 |
| Repository | [cuopt-ev-routing-frontend](https://github.com/oci-ai-incubations/cuopt-ev-routing-frontend) |

Partner-contributed interactive route visualization UI for fleet delivery optimization. Supports Google Maps and Leaflet map rendering, drag-and-drop route editing, vehicle fleet configuration, and real-time optimization result display. Includes an admin login for managing optimization sessions and a chat-powered natural language interface for building and modifying route constraints via OCI GenAI. This frontend offers additional features beyond the Core App but has not been tested to the same standard.

## Video Search and Summarization (`vss`)

| Skin Name | Type | Provider | Default |
|---|---|---|---|
| Oracle Custom - Enhanced search (Core App) | Core App | Oracle | Yes |

### Oracle Custom - Enhanced search (Core App)

| Field | Value |
|---|---|
| Type | Core App |
| Provider | Oracle |
| Image | `iad.ocir.io/iduyx1qnmway/corrino-devops-repository:vss-oracle-ux-dev-0.0.4` |
| Version | 0.0.4 |
| Repository | [vss-oracle-ux](https://github.com/oci-ai-incubations/vss-oracle-ux) |

Oracle-built frontend for video search and summarization. Upload videos, search across ingested content using natural language queries, view AI-generated scene summaries with timestamps, and play back flagged segments directly in the browser. Includes a video timeline with scene markers and a document-style download service for exporting analysis results.

## Enterprise Knowledge Chat Agent - Self-Hosted AI Models (`enterprise_rag`)

| Skin Name | Type | Provider | Default |
|---|---|---|---|
| Oracle RAG - Document chat (Core App) | Core App | Oracle | Yes |

### Oracle RAG - Document chat (Core App)

| Field | Value |
|---|---|
| Type | Core App |
| Provider | Oracle |
| Image | `iad.ocir.io/iduyx1qnmway/enterprise-rag-frontend:v0.0.2` |
| Version | v0.0.2 |
| Repository | [enterprise-rag-frontend](https://github.com/oci-ai-incubations/enterprise-rag-frontend) |

Chat-based document Q&A interface for the self-hosted enterprise RAG pipeline. Upload documents (PDF, DOCX, TXT), ask questions in natural language, and receive cited answers grounded in your uploaded content. The UI displays source citations with page references, supports multi-turn conversations, and provides document management for uploading, listing, and deleting ingested files.

## Enterprise Knowledge Chat Agent - Managed AI Models (`paas_rag`)

| Skin Name | Type | Provider | Default |
|---|---|---|---|
| Oracle Net - Chat interface (Core App) | Core App | Oracle | Yes |

### Oracle Net - Chat interface (Core App)

| Field | Value |
|---|---|
| Type | Core App |
| Provider | Oracle |
| Image | `iad.ocir.io/iduyx1qnmway/corrino-devops-repository/oracle-net-frontend:v0.0.3` |
| Version | v0.0.3 |
| Repository | [oraclenet-frontend](https://github.com/oci-ai-incubations/oraclenet-frontend) |

Oracle Net chat interface for the managed enterprise RAG pipeline. Provides document upload, vector-search-powered Q&A with cited answers, and multi-turn conversation support. Powered by OCI GenAI PaaS for LLM inference and Oracle 26ai for vector storage, requiring no GPU infrastructure. Includes model selection for choosing between available OCI GenAI models.

## Enterprise Agentic AI Starter Kit (`enterprise_rag_aiq`)

| Skin Name | Type | Provider | Default |
|---|---|---|---|
| NVIDIA AIRA - Agentic workflows (Core App) | Core App | NVIDIA | Yes |

### NVIDIA AIRA - Agentic workflows (Core App)

| Field | Value |
|---|---|
| Type | Core App |
| Provider | NVIDIA |
| Image | `nvcr.io/nvidia/blueprint/aira-frontend:v1.2.0` |
| Version | v1.2.0 |
| Repository | [NVIDIA AIQ Frontends](https://github.com/NVIDIA-AI-Blueprints/aiq/tree/develop/frontends/ui) |

NVIDIA AIRA (AI Research Assistant) frontend for the agentic AI starter kit. Provides a chat-based interface for interacting with AI agents that can reason over documents, execute multi-step workflows, and use tools. Includes observability integration with Phoenix for tracing agent execution, viewing tool call chains, and debugging agentic reasoning paths.
