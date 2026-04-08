# Naming Unification Design

**Date:** 2026-04-07
**Author:** Grant (driven by Vishnu's PM feedback)
**Branch:** `unify_naming`

## Problem

Starter pack names across the repo are inconsistent with the canonical names used in the OCI Console. This causes confusion with stakeholders. Examples: docs say "Delivery Vehicle Route Optimizer" (wrong word order), "AI-Q: Enterprise Reasoning Chat Agent IaaS Self-Hosted" (stale name), "Oracle-Net" (stale name), while the console uses "Vehicle Delivery Route Optimizer", "Enterprise Knowledge Chat Agent - Self-Hosted AI Models", etc.

## Canonical Names (Source of Truth)

From the OCI Console:

| Category Key | Full Canonical Name | Description |
|---|---|---|
| `cuopt` | Vehicle Delivery Route Optimizer | GPU-accelerated fleet route optimization on OCI using NVIDIA cuOpt NIM -- deploy in minutes and get a ready API endpoint to cut miles, time, and cost. |
| `vss` | Video Search and Summarization | OCI accelerator pack for AI video moderation: ingest video, index scenes, then search/summarize to flag nudity, violence, weapons, drugs, alcohol -- no more manual review. |
| `enterprise_rag` | Enterprise Knowledge Chat Agent - Self-Hosted AI Models | Enterprise RAG chat: auto-crawls web + internal data, builds a vector index, answers business questions with citations -- all on OCI NVIDIA GPUs. |
| `paas_rag` | Enterprise Knowledge Chat Agent - Managed AI Models | Fully managed, no GPU infrastructure required. Enterprise RAG chat with document upload, vector search, and cited answers -- powered by OCI GenAI PaaS + Oracle 26ai. |
| `enterprise_rag_aiq` | Enterprise Agentic AI Starter Kit | Full-stack agentic AI environment on OCI powered by NVIDIA AIQ. Deploys reasoning models, vector DB, observability, application layer, and more in minutes. Customize and extend to build your own agentic workflows. |

## Short Names

For developer-facing docs and internal references where the full canonical name is too heavy. These are recognizable to stakeholders without needing a lookup table.

| Category Key | Short Name |
|---|---|
| `cuopt` | Vehicle Route Optimizer |
| `vss` | Video Search and Summarization |
| `enterprise_rag` | Self-Hosted Enterprise Chat Agent |
| `paas_rag` | Managed Enterprise Chat Agent |
| `enterprise_rag_aiq` | Agentic AI Starter Kit |

**Rule:** Use the full canonical name in stakeholder-facing contexts (ORM UI, release notes, Slack announcements). Use the short name in developer docs, README tables, and inline references. Never use bare code names (e.g., "cuOpt", "VSS", "PaaS RAG") as the sole identifier in any document a stakeholder might read.

## Approach

**Approach A: Display Names Only** -- change only user-facing display names and descriptions. Leave all internal Terraform identifiers untouched.

## What Changes

### 1. New File: `NAMING.md` (repo root)

A reference document mapping internal identifiers to canonical names. Contains:
- Full mapping table: Category Key, Console Variable, Full Canonical Name, Short Name, Description
- Usage guidance (when to use full vs short)
- Note that internal identifiers are stable code identifiers

### 2. Documentation Updates

**`README.md`:**
- Lines 14-19: Replace old shorthand ("cuOpt", "VSS", "PaaS RAG", etc.) with short names
- Lines 69-73: Replace informal mapping with canonical names

**`docs/about.md`:**
- "Delivery Vehicle Route Optimizer" -> "Vehicle Delivery Route Optimizer"
- "Video Search & Summarization (VSS)" -> "Video Search and Summarization"
- "AI-Q: Enterprise Reasoning Chat Agent IaaS Self-Hosted" -> "Enterprise Knowledge Chat Agent - Self-Hosted AI Models"
- "Oracle-Net: Enterprise Reasoning Chat Agent With Shared Services" -> "Enterprise Knowledge Chat Agent - Managed AI Models"
- Add Enterprise Agentic AI Starter Kit section if missing

**`docs/packs/*.md`:**
- `delivery_optimizer.md`: "Vehicle Route Optimizer" -> "Vehicle Delivery Route Optimizer"
- `enterprise_rag.md`: "Enterprise RAG Starter Pack" -> canonical name
- `vss.md`: "VSS Starter Pack" -> canonical name
- `oraclenet-paas-rag.md`: "OracleNet RAG on OCI" -> canonical name
- `aiq_research_assistant.md`: "AI-Q Research Assistant" -> canonical name

**`docs/updating.md`:**
- Lines 11-14: Update zip file descriptions to use canonical names

**`SOFTWARE_VERSIONS.md`:**
- Section headers: Replace old shorthand with short names

### 3. Release Skill Updates

**`.claude/skills/releasing/RELEASE_PUBLISH.md`:**
- Slack display names table: align all names with canonical names

**`.claude/skills/archive/old-release-push/SKILL.md`:**
- Same Slack name table update (archived but may be referenced)

**`.claude/skills/cuopt-test-coverage/SKILL.md`:**
- Description: "cuOpt (Vehicle Route Optimizer)" -> "cuOpt (Vehicle Delivery Route Optimizer)"

### 4. CLAUDE.md

- Add brief note referencing `NAMING.md` for display name mapping

## What Does NOT Change

- **Schema YAML files** -- already have the correct canonical names
- **Terraform variable names, locals, category keys** -- stable internal identifiers
- **`deployment_name` and `frontend_url` values** -- infrastructure identifiers
- **Test files** -- reference internal identifiers only
- **Zip rename mapping** -- console artifact names (separate concern)
- **Python scripts** -- reference category keys only
- **`outputs.tf` / `vars.tf` variable names** -- code identifiers, not display names
