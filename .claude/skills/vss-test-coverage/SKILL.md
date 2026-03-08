---
name: vss-test-coverage
description: Authoritative test specification for the VSS (Video Summary Service) starter pack. Split into phase-specific files for optimal agent execution.
user-invocable: true
allowed-tools: Bash, Read, Grep, Glob, WebFetch, Write, Edit
argument-hint: [section] (optional — "api", "ui", "infra", or omit for overview)
---

# VSS Starter Pack — Test Coverage Specification

Source of truth for what to test on a deployed VSS stack. Covers the VSS Oracle UX frontend (Next.js), the VSS engine backend (NVIDIA Blueprint), supporting services (download-service, PostgreSQL, FSS), and OCI infrastructure.

**Frontend repo:** `grantneumanoracle/vss-oracle-ux` (Next.js 16, React 19, Prisma, Radix UI, Tailwind)
**Backend:** NVIDIA VSS Engine 2.4.0 — multi-NIM pipeline (embedding, reranking, LLM) + Elasticsearch + Neo4j
**Deployment:** Terraform → OKE → Corrino Blueprint + Kubernetes resources in `app-vss-oracle-ux.tf`

---

## Test Files

Each file is **self-contained** — it has everything needed to execute its tests without reading any other file. Load only the file for the phase you're executing.

| File | Tests | Count | Executor |
|---|---|---|---|
| `api-tests.md` | VA-1 through VA-14 | 16 | Main agent via `curl` |
| `ui-tests.md` | VU-1 through VU-50 | 16 | Playwright sub-agent |
| `infra-tests.md` | VI-1 through VI-7 | 7 | Main agent via `kubectl` / OCI CLI |

**Total: 39 tests** (16 API + 16 UI + 7 Infra)

---

## Environment Variables for Testing

| Variable | Required | Description |
|---|---|---|
| `STARTER_PACK_URL` | Yes | Base URL of the deployed VSS frontend (e.g. `https://vss-frontend.1-2-3-4.nip.io`) |
| `VSS_BUCKET_NAME` | For bucket tests | OCI Object Storage bucket containing test video files |
| `VSS_OBJECT_KEY` | For summarize tests | Object key of a test video file in the bucket |

---

## Architecture Components

| Component | Port | Purpose |
|---|---|---|
| VSS Oracle UX (Next.js) | 3000 | Frontend — pages + API routes proxying to backend |
| VSS Backend (recipe pod) | 8000 | Summarization engine — `/summarize`, `/health/ready`, `/health/live` |
| Download Service | 8080 | Downloads from OCI Object Storage to FSS cache |
| Elasticsearch | — | Search index for VSS engine |
| Neo4j | — | Graph database for VSS engine |
| Embedding NIM | — | Embedding model (GPU) |
| Reranking NIM | — | Reranking model (GPU) |
| LLM NIM (cosmos-reason1) | — | LLM model (GPU) |
| PostgreSQL (Prisma) | — | Persistence: videos, summaries, row_reviews, jobs |
| FSS (File Storage) | — | Shared cache for downloaded videos |

**API route mapping:**
- `/api/vss/config` → K8s API or direct HTTP to backend
- `/api/vss/summarize` → VSS backend `/summarize`
- `/api/vss/video-stream` → FSS cache `/mnt/fss/cache`
- `/api/download-and-upload` → download-service:8080
- `/api/list-bucket-files` → OCI Object Storage SDK
- `/api/jobs/*`, `/api/videos/*` → PostgreSQL (Prisma)

**Pages:** `/` (Home), `/content-review`, `/settings`, `/analytics`

---

## Known Issues & Stability Notes

| Issue | Impact | Mitigation |
|---|---|---|
| NIM model startup takes 15-30 min | `/health/ready` fails until all loaded; summarize fails | Wait for all blueprint pods Running before testing API |
| FSS mount may fail if mount target not ready | Download service errors; video-stream 404s | Check `kubectl get pvc` bound status first |
| 30-minute timeout on summarize | Long-running POST can timeout nginx or client | Ingress has `proxy-read-timeout: 1800`; test should set matching timeout |
| Cosmos-reason1 model cold start | First summarize request after deploy may be slow | Allow 5-10 min extra on first summarize call |
| OCI Object Storage auth | Bucket listing fails if Instance Principal not configured | Verify `COMPARTMENT_ID` and `TENANCY_NAMESPACE` in configmap |
| PostgreSQL not ready | All /api/videos/* and /api/jobs endpoints fail | Check `vss-db-url` secret exists and Prisma migration ran |

---

## Maintenance

- Re-run this skill when `app-vss-oracle-ux.tf` or `blueprint_files.tf` changes for VSS
- Update API inventory if `vss-oracle-ux` frontend image version changes (new routes may be added)
- IDs (VA-*, VU-*, VI-*) are stable — never renumber, only append. VF-* IDs are retired (merged into VU-*).
- If an endpoint is removed, mark `DEPRECATED` — do not delete from this spec
