# dox_pack Pack — Backend API Contract

Companion document to [`BACKEND_API_CONTRACT.md`](../BACKEND_API_CONTRACT.md). That file is the multi-pack
reference organized around skin-access *mechanisms* (ingress paths vs env
vars). This file is the dox_pack-pack-specific deep dive organized around
*backend services and their API surface* — what a skin author can actually
call.

Scope: `starter_pack_category = "dox_pack"`. For other packs, see
[`CUOPT.md`](CUOPT.md), [`VSS.md`](VSS.md),
[`ENTERPRISE_RAG.md`](ENTERPRISE_RAG.md),
[`ENTERPRISE_RAG_AIQ.md`](ENTERPRISE_RAG_AIQ.md),
[`PAAS_RAG.md`](PAAS_RAG.md),
[`WAREHOUSE_PICK_PATH.md`](WAREHOUSE_PICK_PATH.md).

---

## 1. Deployment Group Composition

dox_pack deploys a **Corrino blueprint deployment group** to OKE,
composed of one backend inference service (`llamastack`), one contract
extraction/chat backend (`dox-backend`), and one frontend
(`dox-frontend`). The group inherits paas_rag's LlamaStack
deployment and removes the OracleNet frontend, replacing it with the
contract-specific services.

Source of truth: `ai-accelerator-tf/blueprint_files.tf`.

Unlike enterprise_rag or vss, there are **no GPU workers on the OKE
cluster**: vision-language inference is delegated to the OCI GenAI
Dedicated AI Cluster (DAC) running Qwen3-VL-235B, and text LLM
inference goes through the managed OCI Generative AI service via
LlamaStack. Everything on the cluster is CPU-only.

| Service              | Container image                                                          | Container port | GPU | Role                                                                                                |
|----------------------|--------------------------------------------------------------------------|----------------|-----|-----------------------------------------------------------------------------------------------------|
| `llamastack`         | `iad.ocir.io/iduyx1qnmway/corrino-devops-repository/llama-stack-oci:v0.0.3` | 8321           | --  | Llama Stack server with OCI GenAI inference (Maverick LLM) + Oracle 26ai vector store + OCI Object Storage file store. OpenAI-compatible API. |
| `dox-backend`   | document extractor FastAPI image                                          | 8000           | --  | 3-pass document extraction pipeline (Qwen3-VL OCR, Maverick expansion, validation) + RAG chat over extracted data. |
| `dox-frontend`  | document extractor Next.js image                                          | 80             | --  | User-facing UI for uploading contracts, viewing extractions, downloading CSV/JSON, and chatting with contract data. |

**Resource shapes:**

- `llamastack`: 8 OCPU / 64 GB RAM on the CPU worker node pool, 1 replica, plus
  a 500 GB PVC (`ls-sqlite`) mounted at `/sqlite-store` for the embedded
  metadata / KV / SQL stores.
- `dox-backend`: 4 OCPU / 32 GB RAM, 1 replica, shared CPU worker node pool.
- `dox-frontend`: 4 OCPU / 32 GB RAM, 1 replica, shared CPU worker node pool.

**Infrastructure (no GPU on cluster):**

- 2x VM.Standard.E5.Flex (6 OCPU, 48 GB) — control plane nodes
- 1x VM.Standard.E5.Flex (12 OCPU, 96 GB) — CPU worker node

---

## 2. Managed Dependencies

External services wired in by Terraform — these run outside the OKE
cluster and are accessed over the network.

| Dependency                       | How it is reached                                                                                       | Purpose                                                       |
|----------------------------------|---------------------------------------------------------------------------------------------------------|---------------------------------------------------------------|
| OCI GenAI Dedicated AI Cluster   | DAC endpoint URL passed as `QWEN_URL` env var to `dox-backend`. REST inference API.                | Qwen3-VL-235B vision-language model for PDF page OCR (Pass 1) |
| OCI Generative AI (Maverick LLM) | `remote::oci` inference provider in LlamaStack. Auth = OKE instance principal.                          | Text LLM for Pass 2 expansion and RAG chat                    |
| Oracle 26ai Autonomous DB        | `ORACLE_DSN` env var to `dox-backend`; `OCI26AI_*` env vars to `llamastack`.                       | Extraction history storage + vector embeddings for RAG         |
| OCI Object Storage (S3-compat)   | `remote::s3` files provider in LlamaStack; S3-compat API from `dox-backend` for document uploads.  | Document file storage (uploaded PDFs, extracted artifacts)     |

---

## 3. Backend Service — `dox-backend`

FastAPI application (uvicorn, port 8000) implementing a 3-pass contract
rate card extraction pipeline plus RAG chat over extracted contract data.

- **In-cluster address:** `http://dox-backend:8000`
- **Not externally exposed** — the frontend proxies API calls to the backend
  via `BACKEND_SVC` env var.

### 3.1 Extraction Pipeline (3-Pass)

| Pass | Model            | Purpose                                                                 |
|------|------------------|-------------------------------------------------------------------------|
| 1    | Qwen3-VL-235B   | Vision OCR — renders each PDF page as an image, sends to DAC endpoint for structured extraction |
| 2    | Maverick LLM     | Text expansion — enriches Pass 1 output with additional context and inferred fields via LlamaStack chat completions |
| 3    | Validation        | Cross-references Pass 1 and Pass 2 outputs, resolves conflicts, produces final CSV |

### 3.2 API Endpoints

All routes are prefixed with `/api/`.

| ID    | Endpoint                                  | Method | Request                         | Response (200)                                                     | Purpose                                                     |
|-------|-------------------------------------------|--------|---------------------------------|--------------------------------------------------------------------|-------------------------------------------------------------|
| CA-1  | `/api/health`                             | GET    | --                              | `{ status: "ok", extraction_model, chat_model, approach }`         | Health check with model info                                |
| CA-2  | `/api/contracts`                          | GET    | --                              | `{ contracts: [{ id, name, uploaded_at, ingestion_status, ingestion_progress }] }` | List all contracts with ingestion status                    |
| CA-3  | `/api/extract`                            | POST   | `multipart/form-data` (pdf file)| `{ job_id, contract_id, status: "processing" }`                    | Upload PDF and start 3-pass extraction job                  |
| CA-4  | `/api/jobs/{job_id}`                      | GET    | --                              | `{ job_id, status, filename, error?, row_count? }`                 | Check extraction job progress                               |
| CA-5  | `/api/jobs/{job_id}/download`             | GET    | --                              | CSV file download                                                  | Download extracted rate card CSV                            |
| CA-6  | `/api/jobs/{job_id}/download/json`        | GET    | --                              | JSON file download                                                 | Download preliminary JSON (raw Pass 2 output)               |
| CA-7  | `/api/chat`                               | POST   | `{ contract_ids, message, history }` | `{ answer, sources: [{ page, score }] }`                     | RAG chat over extracted contract data via LlamaStack        |
| CA-8  | `/api/config/prompt`                      | GET    | --                              | `{ prompt, csv_header }`                                           | Get current extraction prompt and CSV header config         |
| CA-9  | `/api/config/prompt`                      | PUT    | `{ prompt, csv_header }`        | `{ status: "saved" }`                                              | Save custom extraction prompt and CSV header                |
| CA-10 | `/api/config/prompt/reset`                | POST   | --                              | `{ prompt, csv_header }`                                           | Reset prompt config to built-in defaults                    |
| CA-11 | `/api/history`                            | GET    | `?limit=50&offset=0`           | Array of extraction records                                        | List extraction history with pagination                     |
| CA-12 | `/api/history/{id}/csv-preview`           | GET    | `?max_rows=50`                 | Array of row objects                                               | Preview first N rows of extracted CSV                       |
| CA-13 | `/api/history/{id}/download/csv`          | GET    | --                              | CSV file download                                                  | Download historical extraction CSV                          |
| CA-14 | `/api/history/{id}/download/json`         | GET    | --                              | JSON file download                                                 | Download historical preliminary JSON                        |
| CA-15 | `/api/history/{id}/download/pdf`          | GET    | --                              | PDF file download                                                  | Download original uploaded PDF                              |

### 3.3 Environment Variables

| Variable          | Source                      | Purpose                                               |
|-------------------|-----------------------------|-------------------------------------------------------|
| `QWEN_URL`        | DAC inference endpoint      | Qwen3-VL-235B vision model endpoint for Pass 1 OCR    |
| `LLAMASTACK_URL`  | In-cluster LlamaStack URL  | Maverick LLM via LlamaStack for Pass 2 and RAG chat   |
| `ORACLE_DSN`      | Oracle 26ai connection string | Database for extraction history + vector storage      |
| `CHAT_MODEL`      | Terraform variable          | Model ID for RAG chat (e.g., `oci/meta.llama-4-maverick-17b-128e-instruct-fp8`) |
| `CHAT_ENDPOINT`   | Derived from LLAMASTACK_URL | Full URL for chat completions endpoint                |
| `OUTPUT_DIR`      | Temp directory path         | Working directory for extraction artifacts            |

---

## 4. Backend Service — `llamastack`

Same LlamaStack deployment as paas_rag. See [`PAAS_RAG.md`](PAAS_RAG.md)
section 2 for full details on the LlamaStack backend.

Key points for dox_pack:

- **In-cluster address:** `http://<llamastack.service_name>:80` (Service
  `port 80` -> container `targetPort 8321`).
- **External address (backend's own ingress):** `https://llamastack.<fqdn>/`
- dox-backend connects to LlamaStack at `LLAMASTACK_URL` for:
  - `POST /v1/chat/completions` — Pass 2 text expansion and RAG chat
  - `GET /v1/models` — model discovery
- LlamaStack connects to Oracle 26ai for vector storage (Cohere embeddings)
  and OCI Object Storage for file storage.
- Auth is disabled (no Authorization header required).
- Enabled APIs: agents, datasetio, eval, files, inference, safety, scoring,
  tool_runtime, vector_io.

---

## 5. Network Topology & Ingress

```
                     Internet
                        |
                  ┌─────▼──────┐
                  │  Ingress    │
                  │  Controller │
                  └──┬──────┬──┘
                     │      │
     ┌───────────────▼┐  ┌──▼──────────────┐
     │dox-frontend│  │  llamastack     │
     │  :80            │  │  :8321          │
     │  Next.js UI     │  │  OpenAI API     │
     └───────┬─────────┘  └──▲──────────────┘
             │                │
     ┌───────▼─────────┐     │
     │dox-backend  │─────┘  (LLAMASTACK_URL)
     │  :8000           │
     │  FastAPI         │──────────────────┐
     └───────┬──────────┘                  │
             │                             │
     ┌───────▼─────────┐        ┌──────────▼──────┐
     │  Oracle 26ai    │        │ OCI GenAI DAC   │
     │  (ORACLE_DSN)   │        │ Qwen3-VL-235B   │
     │  history +      │        │ (QWEN_URL)      │
     │  vectors        │        └─────────────────┘
     └─────────────────┘
```

**Ingress hostnames:**

| Hostname                           | Target Service       | Port | Purpose                           |
|------------------------------------|----------------------|------|-----------------------------------|
| `dox-frontend.<fqdn>`        | dox-frontend    | 80   | User-facing UI (starter_pack_url) |
| `llamastack.<fqdn>`               | llamastack           | 8321 | LlamaStack API (optional direct access) |

**Internal cluster routing:**

- `dox-frontend` -> `dox-backend` via `BACKEND_SVC` env var
  (e.g., `http://dox-backend:8000`)
- `dox-backend` -> `llamastack` via `LLAMASTACK_URL` env var
  (e.g., `http://llamastack:80`)
- `dox-backend` -> DAC via `QWEN_URL` env var (external OCI endpoint)
- `dox-backend` -> Oracle 26ai via `ORACLE_DSN` (TCP connection string)

---

## 6. Frontend Environment Variables

| Variable       | Value                             | Purpose                                       |
|----------------|-----------------------------------|-----------------------------------------------|
| `BACKEND_SVC`  | `http://dox-backend:8000`    | In-cluster address of dox-backend service |

The frontend is a Next.js application that proxies all `/api/*` requests
to the dox-backend. It provides:
- PDF upload interface with drag-and-drop
- Real-time extraction progress monitoring
- Extraction results table with CSV/JSON download
- RAG chat interface for querying extracted contract data
- Extraction history browser
- Prompt configuration editor

---

## 7. Extraction Job Lifecycle

```
Upload PDF ──> POST /api/extract ──> job_id returned (status: "processing")
                    │
                    ▼
         Pass 1: Qwen3-VL OCR (DAC endpoint)
           - Each PDF page rendered as image
           - Sent to Qwen3-VL-235B for structured extraction
           - Returns preliminary JSON per page
                    │
                    ▼
         Pass 2: Maverick Expansion (LlamaStack)
           - Preliminary JSON enriched via text LLM
           - Additional fields inferred from context
           - Returns expanded JSON
                    │
                    ▼
         Pass 3: Validation
           - Cross-reference Pass 1 and Pass 2
           - Resolve conflicts
           - Produce final CSV
                    │
                    ▼
         status: "complete" ──> row_count set
           - CSV stored in database
           - Preliminary JSON stored in database
           - PDF transcription ingested into vector store for RAG
           - CSV data ingested into vector store for pricing queries
                    │
                    ▼
         GET /api/jobs/{job_id}/download ──> CSV file
         GET /api/jobs/{job_id}/download/json ──> preliminary JSON
         POST /api/chat ──> RAG queries over extracted data
```

**Typical extraction time:** 10-15 minutes per contract PDF (depends on
page count and DAC queue depth).

**Error handling:** If extraction fails at any pass, job status becomes
`"error"` with a descriptive error message. The PDF is still stored and
can be re-extracted with different prompt configuration.
