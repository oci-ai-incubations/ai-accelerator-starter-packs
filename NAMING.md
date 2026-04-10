# Accelerator Pack Naming Reference

This document is the single source of truth for starter pack naming. Use it to map between internal code identifiers and the official display names shown in the OCI Console.

## Name Mapping

| Category Key | Console Zip Name | Full Display Name | Short Name | GPU Required |
|---|---|---|---|---|
| `cuopt` | `vehicleRouteOptimizer.zip` | Vehicle Delivery Route Optimizer | Vehicle Route Optimizer | Yes |
| `vss` | `videoSearchSummarization.zip` | Video Search and Summarization | Video Search and Summarization | Yes |
| `enterprise_rag` | `aiQEnterpriseSearch.zip` | Enterprise Knowledge Chat Agent - Self-Hosted AI Models | Self-Hosted Enterprise Chat Agent | Yes |
| `paas_rag` | `aiQGenAIPowered.zip` | Enterprise Knowledge Chat Agent - Managed AI Models | Managed Enterprise Chat Agent | No |
| `enterprise_rag_aiq` | `enterpriseAgenticAIStarterKit.zip` | Enterprise Agentic AI Starter Kit | Agentic AI Starter Kit | Yes |

## Descriptions

| Category Key | Description |
|---|---|
| `cuopt` | GPU-accelerated fleet route optimization on OCI using NVIDIA cuOpt NIM — deploy in minutes and get a ready API endpoint to cut miles, time, and cost. |
| `vss` | OCI accelerator pack for AI video moderation: ingest video, index scenes, then search/summarize to flag nudity, violence, weapons, drugs, alcohol — no more manual review. |
| `enterprise_rag` | Enterprise RAG chat: auto-crawls web + internal data, builds a vector index, answers business questions with citations — all on OCI NVIDIA GPUs. |
| `paas_rag` | Fully managed, no GPU infrastructure required. Enterprise RAG chat with document upload, vector search, and cited answers — powered by OCI GenAI PaaS + Oracle 26ai. |
| `enterprise_rag_aiq` | Full-stack agentic AI environment on OCI powered by NVIDIA AIQ. Deploys reasoning models, vector DB, observability, application layer, and more in minutes. Customize and extend to build your own agentic workflows. |

## When to Use Which Name

- **Full Display Name:** ORM UI schemas, release notes, Slack announcements, stakeholder-facing documents.
- **Short Name:** README tables, developer docs, inline references where the full name is too heavy.
- **Category Key:** Terraform code, variable names, CLI arguments, test files. These are stable internal identifiers and intentionally differ from display names.

The console zip names (e.g., `vehicleRouteOptimizer.zip`) are artifact identifiers used in GitHub Releases — they are not display names.
