# Naming Unification Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Align all starter pack display names and descriptions in the repo with the canonical names used in the OCI Console.

**Architecture:** Update user-facing text (docs, release skills, CLAUDE.md) to use canonical display names. Create a new `NAMING.md` reference doc at the repo root. Leave all internal Terraform identifiers unchanged.

**Tech Stack:** Markdown documentation, YAML skill definitions

**Spec:** `docs/superpowers/specs/2026-04-07-naming-unification-design.md`

---

## Name Reference

| Category Key | Full Canonical Name | Short Name |
|---|---|---|
| `cuopt` | Vehicle Delivery Route Optimizer | Vehicle Route Optimizer |
| `vss` | Video Search and Summarization | Video Search and Summarization |
| `enterprise_rag` | Enterprise Knowledge Chat Agent - Self-Hosted AI Models | Self-Hosted Enterprise Chat Agent |
| `paas_rag` | Enterprise Knowledge Chat Agent - Managed AI Models | Managed Enterprise Chat Agent |
| `enterprise_rag_aiq` | Enterprise Agentic AI Starter Kit | Agentic AI Starter Kit |

**Usage rule:** Full canonical name in stakeholder-facing contexts. Short name in developer docs and inline references. Never use bare code names (`cuOpt`, `VSS`, `PaaS RAG`) as the sole identifier in docs a stakeholder might read.

---

### Task 1: Create NAMING.md Reference Document

**Files:**
- Create: `NAMING.md`

- [ ] **Step 1: Create NAMING.md**

```markdown
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
```

- [ ] **Step 2: Commit**

```bash
git add NAMING.md
git commit -m "docs: add NAMING.md as single source of truth for pack display names"
```

---

### Task 2: Update README.md

**Files:**
- Modify: `README.md:13-19` (starter packs table)
- Modify: `README.md:69-73` (informal mapping)

- [ ] **Step 1: Update the starter packs table (lines 13-19)**

Replace the table body with short names and canonical descriptions:

```markdown
| Pack | Category Key | Description | GPU Required |
|------|-------------|-------------|--------------|
| **Vehicle Route Optimizer** | `cuopt` | GPU-accelerated fleet route optimization using NVIDIA cuOpt NIM | Yes |
| **Video Search and Summarization** | `vss` | AI video moderation — ingest, index, search, and summarize video content | Yes |
| **Managed Enterprise Chat Agent** | `paas_rag` | Enterprise RAG chat with document upload, vector search, and cited answers — powered by OCI GenAI PaaS + Oracle 26ai | No |
| **Self-Hosted Enterprise Chat Agent** | `enterprise_rag` | Enterprise RAG chat — auto-crawls web + internal data, builds a vector index, answers business questions with citations on OCI NVIDIA GPUs | Yes |
| **Agentic AI Starter Kit** | `enterprise_rag_aiq` | Full-stack agentic AI environment powered by NVIDIA AIQ — reasoning models, vector DB, observability, and application layer | Yes |
```

- [ ] **Step 2: Update the informal mapping (lines 69-73)**

Replace with canonical names:

```markdown
- cuopt == Vehicle Delivery Route Optimizer
- vss == Video Search and Summarization
- paas_rag == Enterprise Knowledge Chat Agent - Managed AI Models
- enterprise_rag == Enterprise Knowledge Chat Agent - Self-Hosted AI Models
- enterprise_rag_aiq == Enterprise Agentic AI Starter Kit
```

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs: align README starter pack names with OCI Console canonical names"
```

---

### Task 3: Update docs/about.md

**Files:**
- Modify: `docs/about.md:10` (cuopt section header)
- Modify: `docs/about.md:45` (vss section header)
- Modify: `docs/about.md:70` (enterprise_rag section header)
- Modify: `docs/about.md:87` (paas_rag section header)

- [ ] **Step 1: Update section headers**

Make these replacements:

Line 10: `## Delivery Vehicle Route Optimizer` → `## Vehicle Delivery Route Optimizer`

Line 45: `## Video Search & Summarization (VSS)` → `## Video Search and Summarization`

Line 70: `## AI-Q: Enterprise Reasoning Chat Agent IaaS Self-Hosted` → `## Enterprise Knowledge Chat Agent - Self-Hosted AI Models`

Line 87: `## Oracle-Net: Enterprise Reasoning Chat Agent With Shared Services` → `## Enterprise Knowledge Chat Agent - Managed AI Models`

- [ ] **Step 2: Add Enterprise Agentic AI Starter Kit section**

Append at end of file (after the paas_rag section):

```markdown
## Enterprise Agentic AI Starter Kit

### Deployment Sizes & Services Required

| Deployment Size | Component                               | Requirements                   | SKU                                | Specs              | Quantity |
| --------------- | --------------------------------------- | ------------------------------ | ---------------------------------- | ------------------ | -------- |
| **SMALL**       | OCI Core Compute                        | Nvidia A100 40 GB GPU          | BM.GPU4.8                          | 8 GPUs             | 2        |
|                 |                                         | CPU VM Flex                    | VM.Standard.E5.Flex                | ocpus=4, memory=32 | 2        |
|                 | OCI Boot Volume                         | Boot Block Volume              | NA                                 | 300 GB             | 2        |
|                 | OCI Services                            | Oracle Kubernetes Engine (OKE) | NA                                 | NA                 | 1        |
|                 | NVIDIA AI Enterprise License & Software | NVIDIA NIMs                    | OCI Billed (attached to # of GPUs) | NA                 | 16       |
|                 | OCI Software                            | OCI AI Blueprints              | Free                               | 1                  |

Other necessary VNET, public IP, load balancers and subnets are required.
```

- [ ] **Step 3: Commit**

```bash
git add docs/about.md
git commit -m "docs: align about.md section headers with canonical pack names"
```

---

### Task 4: Update docs/packs/*.md Headers

**Files:**
- Modify: `docs/packs/delivery_optimizer.md:1,3`
- Modify: `docs/packs/enterprise_rag.md:1,3`
- Modify: `docs/packs/vss.md:1,3`
- Modify: `docs/packs/oraclenet-paas-rag.md:1,3-5`
- Modify: `docs/packs/aiq_research_assistant.md:1,3`

- [ ] **Step 1: Update delivery_optimizer.md**

Line 1: `# Vehicle Route Optimizer Accelerator Pack` → `# Vehicle Delivery Route Optimizer`

Line 3: `The **Vehicle Route Optimizer Starter Pack**` → `The **Vehicle Delivery Route Optimizer**`

- [ ] **Step 2: Update enterprise_rag.md**

Line 1: `# Enterprise RAG Starter Pack` → `# Enterprise Knowledge Chat Agent - Self-Hosted AI Models`

Line 3: `The Enterprise RAG Starter Pack packages` → `The **Self-Hosted Enterprise Chat Agent** (Enterprise Knowledge Chat Agent - Self-Hosted AI Models) packages`

- [ ] **Step 3: Update vss.md**

Line 1: `# VSS Starter Pack` → `# Video Search and Summarization`

Line 3: `The **VSS Starter Pack**` → `The **Video Search and Summarization** pack`

- [ ] **Step 4: Update oraclenet-paas-rag.md**

Line 1: `# OracleNet RAG on OCI` → `# Enterprise Knowledge Chat Agent - Managed AI Models`

Line 3: `#### Advanced AI-Powered Interface for Retrieval Augmented Generation` → remove or update to match canonical description

Line 5: `Deploy OracleNet on OCI to leverage` → `Deploy the **Managed Enterprise Chat Agent** on OCI to leverage`

- [ ] **Step 5: Update aiq_research_assistant.md**

Line 1: `# AI-Q Research Assistant Accelerator Pack` → `# Enterprise Agentic AI Starter Kit`

Line 3: `The **AI-Q Research Assistant Accelerator Pack**` → `The **Enterprise Agentic AI Starter Kit**`

- [ ] **Step 6: Commit**

```bash
git add docs/packs/
git commit -m "docs: align pack doc headers with canonical display names"
```

---

### Task 5: Update docs/updating.md

**Files:**
- Modify: `docs/updating.md:11-14`

- [ ] **Step 1: Update zip descriptions**

Replace lines 11-14 with:

```markdown
- aiQEnterpriseSearch.zip - Enterprise Knowledge Chat Agent - Self-Hosted AI Models
- vehicleRouteOptimizer.zip - Vehicle Delivery Route Optimizer
- videoSearchSummarization.zip - Video Search and Summarization
- aiQGenAIPowered.zip - Enterprise Knowledge Chat Agent - Managed AI Models
- enterpriseAgenticAIStarterKit.zip - Enterprise Agentic AI Starter Kit
```

- [ ] **Step 2: Commit**

```bash
git add docs/updating.md
git commit -m "docs: align updating.md zip descriptions with canonical names"
```

---

### Task 6: Update SOFTWARE_VERSIONS.md

**Files:**
- Modify: `SOFTWARE_VERSIONS.md:5,7,8,23,25,39,50,62,64,65,71,72,78,80`

- [ ] **Step 1: Update section headers**

Line 5: `## cuOpt Starter Pack` → `## Vehicle Route Optimizer`

Line 7: `### cuOpt Small` → `### Vehicle Route Optimizer Small`

Line 16: `### cuOpt Medium` → `### Vehicle Route Optimizer Medium`

Line 23: `## VSS Starter Pack` → `## Video Search and Summarization`

Line 25: `### VSS POC` → `### Video Search and Summarization POC`

Line 39: `### VSS Small` → `### Video Search and Summarization Small`

Line 50: `### VSS Medium` → `### Video Search and Summarization Medium`

Line 62: `## PaaS RAG Starter Pack` → `## Managed Enterprise Chat Agent`

Line 64: `### PaaS RAG Small` → `### Managed Enterprise Chat Agent Small`

Line 71: `### PaaS RAG Medium` → `### Managed Enterprise Chat Agent Medium`

Line 78: `## Enterprise RAG Starter Pack` → `## Self-Hosted Enterprise Chat Agent`

Line 80: `### Enterprise RAG Small` → `### Self-Hosted Enterprise Chat Agent Small`

- [ ] **Step 2: Commit**

```bash
git add SOFTWARE_VERSIONS.md
git commit -m "docs: align SOFTWARE_VERSIONS.md headers with canonical short names"
```

---

### Task 7: Update Release Skills

**Files:**
- Modify: `.claude/skills/releasing/RELEASE_PUBLISH.md:102-106`
- Modify: `.claude/skills/archive/old-release-push/SKILL.md:110-114`
- Modify: `.claude/skills/cuopt-test-coverage/SKILL.md:3`

- [ ] **Step 1: Update RELEASE_PUBLISH.md Slack names**

Replace lines 102-106:

```markdown
| `paas_rag`           | Enterprise Knowledge Chat Agent - Managed AI Models   |
| `enterprise_rag`     | Enterprise Knowledge Chat Agent - Self-Hosted AI Models |
| `enterprise_rag_aiq` | Enterprise Agentic AI Starter Kit                     |
| `cuopt`              | Vehicle Delivery Route Optimizer                      |
| `vss`                | Video Search and Summarization                        |
```

- [ ] **Step 2: Update archived SKILL.md Slack names**

Replace lines 110-114 with the same table content as Step 1.

- [ ] **Step 3: Update cuopt-test-coverage description**

Line 3: `description: Authoritative test specification for the cuOpt (Vehicle Route Optimizer) starter pack.` → `description: Authoritative test specification for the cuOpt (Vehicle Delivery Route Optimizer) starter pack.`

- [ ] **Step 4: Commit**

```bash
git add .claude/skills/releasing/RELEASE_PUBLISH.md .claude/skills/archive/old-release-push/SKILL.md .claude/skills/cuopt-test-coverage/SKILL.md
git commit -m "chore: align release skill display names with canonical pack names"
```

---

### Task 8: Update CLAUDE.md

**Files:**
- Modify: `CLAUDE.md:7`

- [ ] **Step 1: Add naming reference to project overview**

Replace line 7:

```
AI Accelerator Starter Packs — a Terraform-based infrastructure-as-code project that deploys AI workloads on Oracle Cloud Infrastructure (OCI) using Oracle Kubernetes Engine (OKE). It provisions networking, compute, Kubernetes clusters, Helm charts, and application services (Corrino platform) for multiple "starter pack" categories: `enterprise_rag`, `enterprise_rag_aiq`, `paas_rag`, `cuopt`, and `vss`.
```

With:

```
AI Accelerator Starter Packs — a Terraform-based infrastructure-as-code project that deploys AI workloads on Oracle Cloud Infrastructure (OCI) using Oracle Kubernetes Engine (OKE). It provisions networking, compute, Kubernetes clusters, Helm charts, and application services (Corrino platform) for multiple "starter pack" categories: `cuopt` (Vehicle Route Optimizer), `vss` (Video Search and Summarization), `enterprise_rag` (Self-Hosted Enterprise Chat Agent), `paas_rag` (Managed Enterprise Chat Agent), and `enterprise_rag_aiq` (Agentic AI Starter Kit). See `NAMING.md` for the full name mapping.
```

- [ ] **Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: add short names and NAMING.md reference to CLAUDE.md project overview"
```

---

### Task 9: Verify and Final Review

- [ ] **Step 1: Grep for stale names across the repo**

Run these searches to catch any remaining stale references:

```bash
# Check for old names that should no longer appear
grep -ri "Delivery Vehicle Route Optimizer" --include="*.md" --include="*.yaml" .
grep -ri "Oracle-Net" --include="*.md" .
grep -ri "AI-Q:" --include="*.md" .
grep -ri "PaaS RAG" --include="*.md" . | grep -v "category\|paas_rag\|NAMING"
grep -ri "Enterprise RAG" --include="*.md" . | grep -v "category\|enterprise_rag\|NAMING\|specs/"
```

- [ ] **Step 2: Fix any remaining stale references found in Step 1**

- [ ] **Step 3: Run terraform fmt to ensure no TF files were accidentally modified**

```bash
cd ai-accelerator-tf && terraform fmt -check -diff -recursive
```

- [ ] **Step 4: Final commit if any fixes were needed**

```bash
git add -A
git commit -m "docs: fix remaining stale pack name references"
```
