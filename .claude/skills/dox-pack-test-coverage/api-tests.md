# Document Extractor API Tests

10 tests executed via `curl` against `${STARTER_PACK_URL}`. Execute in order — some tests depend on prior results.

**MANDATORY:** Execute ALL tests in order by ascending ID. If a test fails, record the failure and continue. Do NOT skip any test.

**No authentication required.**

**Note:** The frontend at `${STARTER_PACK_URL}` proxies `/api/*` requests to the dox-backend (port 8000). All API paths use the `/api/` prefix.

---

## Execution Order

| # | ID | Test | Method | Endpoint | P | Type | Timeout | Preconditions |
|---|---|---|---|---|---|---|---|---|
| 1 | CA-1 | Health check | GET | `/api/health` | P0 | smoke | 30s | Backend pod Running |
| 2 | CA-2 | List contracts | GET | `/api/contracts` | P0 | smoke | 30s | Backend pod Running |
| 3 | CA-3 | Upload PDF and start extraction | POST | `/api/extract` | P0 | e2e | 60s | Test PDF available |
| 4 | CA-4 | Poll extraction status | GET | `/api/jobs/{job_id}` | P0 | e2e | **15min** | CA-3 returned job_id |
| 5 | CA-5 | Download extracted CSV | GET | `/api/jobs/{job_id}/download` | P0 | e2e | 30s | CA-4 status = complete |
| 6 | CA-6 | Download preliminary JSON | GET | `/api/jobs/{job_id}/download/json` | P1 | e2e | 30s | CA-4 status = complete |
| 7 | CA-7 | RAG chat over contract | POST | `/api/chat` | P0 | e2e | 2min | CA-4 extraction complete |
| 8 | CA-8 | Get prompt config | GET | `/api/config/prompt` | P1 | smoke | 10s | Backend pod Running |
| 9 | CA-9 | Extraction history | GET | `/api/history` | P0 | smoke | 10s | Backend pod Running |
| 10 | CA-10 | History CSV download | GET | `/api/history/{id}/download/csv` | P1 | e2e | 30s | CA-9 returned history with entries |

> **Note:** CA-4 (extraction polling) takes 10-15 minutes due to the Qwen3-VL vision OCR pipeline. Do NOT timeout early.

---

## Test Details

### CA-1: Health Check (P0 smoke)

- **Endpoint:** `GET /api/health`
- **Request:** None
- **Verification:**
  - HTTP 200
  - `status === "ok"`
  - `extraction_model` is present (e.g., `"Qwen3-VL-235B"`)
  - `chat_model` is present (e.g., `"oci/meta.llama-4-maverick-17b-128e-instruct-fp8"`)
  - `approach` is present (e.g., `"generic-few-shot"`)
- **Note:** If this returns 502/503, the backend pod is still starting. Wait and retry.
- **curl:**
  ```bash
  curl -sk -o "${DAT_SANDBOX}/api-results/CA-1.json" -w '%{http_code}' \
    "${STARTER_PACK_URL}/api/health"
  ```

### CA-2: List Contracts (P0 smoke)

- **Endpoint:** `GET /api/contracts`
- **Request:** None
- **Verification:**
  - HTTP 200
  - Response has `contracts` array
  - Array may be empty on fresh deployment (valid)
  - If non-empty, each entry has `id`, `name`, `uploaded_at`, `ingestion_status`
- **curl:**
  ```bash
  curl -sk -o "${DAT_SANDBOX}/api-results/CA-2.json" -w '%{http_code}' \
    "${STARTER_PACK_URL}/api/contracts"
  ```

### CA-3: Upload PDF and Start Extraction (P0 e2e)

- **Endpoint:** `POST /api/extract`
- **Request:** `multipart/form-data` with a PDF file
- **Verification:**
  - HTTP 200
  - `job_id` is a non-empty string (8-char hex)
  - `contract_id` is present
  - `status === "processing"`
- **Test PDF:** Use a small contract PDF (5-10 pages) for reasonable extraction time. If no test PDF is available, create a minimal one:
  ```bash
  # Create a minimal test PDF if none is provided
  if [ -z "${TEST_PDF_PATH}" ]; then
    TEST_PDF_PATH="${DAT_SANDBOX}/api-results/test-contract.pdf"
    python3 -c "
  # Minimal PDF with text content
  import struct
  content = b'''%PDF-1.4
  1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj
  2 0 obj<</Type/Pages/Kids[3 0 R]/Count 1>>endobj
  3 0 obj<</Type/Page/MediaBox[0 0 612 792]/Parent 2 0 R/Contents 4 0 R/Resources<</Font<</F1 5 0 R>>>>>>endobj
  4 0 obj<</Length 178>>stream
  BT /F1 12 Tf 72 720 Td (GROUND HANDLING SERVICES AGREEMENT) Tj 0 -20 Td (Service: Turnaround Handling) Tj 0 -20 Td (Rate: 5000 SAR per turnaround) Tj 0 -20 Td (Aircraft Type: A320) Tj 0 -20 Td (Effective Date: 2025-01-01) Tj ET
  endstream endobj
  5 0 obj<</Type/Font/Subtype/Type1/BaseFont/Helvetica>>endobj
  xref
  0 6
  0000000000 65535 f 
  0000000009 00000 n 
  0000000058 00000 n 
  0000000115 00000 n 
  0000000266 00000 n 
  0000000496 00000 n 
  trailer<</Size 6/Root 1 0 R>>
  startxref
  574
  %%EOF'''
  with open('${TEST_PDF_PATH}', 'wb') as f:
      f.write(content)
  "
  fi
  ```
- **curl:**
  ```bash
  curl -sk -X POST \
    -F "pdf=@${TEST_PDF_PATH}" \
    -o "${DAT_SANDBOX}/api-results/CA-3.json" -w '%{http_code}' \
    "${STARTER_PACK_URL}/api/extract"
  ```
- **Output:** Save `job_id` and `contract_id` from response for CA-4 through CA-7.

### CA-4: Poll Extraction Status (P0 e2e, 15min timeout)

- **Endpoint:** `GET /api/jobs/{job_id}`
- **Request:** None (use job_id from CA-3)
- **Verification:**
  - HTTP 200
  - `status` transitions: `"processing"` -> `"complete"` (or `"error"`)
  - When `"complete"`: `row_count` is a positive number, `filename` is present
  - When `"error"`: `error` string describes the failure
- **CRITICAL:** Extraction takes 10-15 minutes due to per-page Qwen3-VL vision OCR. Do NOT timeout early. Poll every 30 seconds.
- **Polling:**
  ```bash
  JOB_ID=$(python3 -c "import json; print(json.load(open('${DAT_SANDBOX}/api-results/CA-3.json'))['job_id'])")
  for i in $(seq 1 30); do
    HTTP_CODE=$(curl -sk -o "${DAT_SANDBOX}/api-results/CA-4.json" -w '%{http_code}' \
      "${STARTER_PACK_URL}/api/jobs/${JOB_ID}")
    STATUS=$(python3 -c "import json; print(json.load(open('${DAT_SANDBOX}/api-results/CA-4.json')).get('status',''))" 2>/dev/null)
    ROW_COUNT=$(python3 -c "import json; print(json.load(open('${DAT_SANDBOX}/api-results/CA-4.json')).get('row_count','n/a'))" 2>/dev/null)
    echo "Attempt $i (${i}x30s = $((i*30))s elapsed): status=$STATUS, rows=$ROW_COUNT"
    if [ "$STATUS" = "complete" ] || [ "$STATUS" = "error" ]; then
      break
    fi
    sleep 30
  done
  ```

### CA-5: Download Extracted CSV (P0 e2e)

- **Endpoint:** `GET /api/jobs/{job_id}/download`
- **Request:** None
- **Verification:**
  - HTTP 200
  - `Content-Type` is `text/csv`
  - Response body is non-empty CSV with header row and data rows
  - `Content-Disposition` header has a filename ending in `.csv`
- **Precondition:** CA-4 status = `"complete"`. If CA-4 failed, skip this test.
- **curl:**
  ```bash
  JOB_ID=$(python3 -c "import json; print(json.load(open('${DAT_SANDBOX}/api-results/CA-3.json'))['job_id'])")
  curl -sk -o "${DAT_SANDBOX}/api-results/CA-5.csv" -w '%{http_code}' \
    -D "${DAT_SANDBOX}/api-results/CA-5-headers.txt" \
    "${STARTER_PACK_URL}/api/jobs/${JOB_ID}/download"
  ```
- **Validate CSV:**
  ```bash
  # Verify CSV has content
  wc -l "${DAT_SANDBOX}/api-results/CA-5.csv"
  # Show first 3 lines
  head -3 "${DAT_SANDBOX}/api-results/CA-5.csv"
  ```

### CA-6: Download Preliminary JSON (P1 e2e)

- **Endpoint:** `GET /api/jobs/{job_id}/download/json`
- **Request:** None
- **Verification:**
  - HTTP 200
  - `Content-Type` is `application/json`
  - Response body is valid JSON
  - `Content-Disposition` header has a filename ending in `.json`
- **Note:** Preliminary JSON may not be available for all extractions (returns 404 if not generated). Treat 404 as acceptable, not a failure.
- **curl:**
  ```bash
  JOB_ID=$(python3 -c "import json; print(json.load(open('${DAT_SANDBOX}/api-results/CA-3.json'))['job_id'])")
  curl -sk -o "${DAT_SANDBOX}/api-results/CA-6.json" -w '%{http_code}' \
    "${STARTER_PACK_URL}/api/jobs/${JOB_ID}/download/json"
  ```

### CA-7: RAG Chat Over Contract (P0 e2e, 2min timeout)

- **Endpoint:** `POST /api/chat`
- **Request:**
  ```json
  {
    "contract_ids": ["<contract_id_from_CA-3>"],
    "message": "What services and rates are described in this contract?",
    "history": []
  }
  ```
- **Verification:**
  - HTTP 200
  - `answer` is a non-empty string containing relevant information from the contract
  - `sources` is an array of objects with `page` and `score` fields
  - Answer should reference content from the uploaded PDF (services, rates, terms)
- **Note:** RAG chat requires the extraction to be complete (CA-4) so the contract data has been ingested into the vector store.
- **curl:**
  ```bash
  CONTRACT_ID=$(python3 -c "import json; print(json.load(open('${DAT_SANDBOX}/api-results/CA-3.json'))['contract_id'])")
  curl -sk -X POST -H 'Content-Type: application/json' --max-time 120 \
    -d "{\"contract_ids\":[\"${CONTRACT_ID}\"],\"message\":\"What services and rates are described in this contract?\",\"history\":[]}" \
    -o "${DAT_SANDBOX}/api-results/CA-7.json" -w '%{http_code}' \
    "${STARTER_PACK_URL}/api/chat"
  ```
- **Validate response:**
  ```bash
  python3 -c "
  import json
  data = json.load(open('${DAT_SANDBOX}/api-results/CA-7.json'))
  print('Answer length:', len(data.get('answer','')))
  print('Sources count:', len(data.get('sources',[])))
  print('Answer preview:', data.get('answer','')[:200])
  "
  ```

### CA-8: Get Prompt Config (P1 smoke)

- **Endpoint:** `GET /api/config/prompt`
- **Request:** None
- **Verification:**
  - HTTP 200
  - `prompt` is a non-empty string (the extraction prompt template)
  - `csv_header` is a non-empty string (the CSV column header)
- **curl:**
  ```bash
  curl -sk -o "${DAT_SANDBOX}/api-results/CA-8.json" -w '%{http_code}' \
    "${STARTER_PACK_URL}/api/config/prompt"
  ```

### CA-9: Extraction History (P0 smoke)

- **Endpoint:** `GET /api/history`
- **Request:** `?limit=50&offset=0` (optional query params)
- **Verification:**
  - HTTP 200
  - Response is an array of extraction records
  - If CA-3 succeeded, at least one record should exist
  - Each record has `id`, `pdf_filename`, `csv_filename`, `status`, `uploaded_at`
- **curl:**
  ```bash
  curl -sk -o "${DAT_SANDBOX}/api-results/CA-9.json" -w '%{http_code}' \
    "${STARTER_PACK_URL}/api/history?limit=50&offset=0"
  ```
- **Output:** Save an extraction `id` from the response for CA-10.

### CA-10: History CSV Download (P1 e2e)

- **Endpoint:** `GET /api/history/{extraction_id}/download/csv`
- **Request:** None (use extraction id from CA-9)
- **Verification:**
  - HTTP 200
  - `Content-Type` is `text/csv`
  - Response body is non-empty CSV data
  - `Content-Disposition` header has a filename ending in `.csv`
- **Note:** Use the first extraction ID from CA-9 history list. If CA-9 returned an empty array, skip this test.
- **curl:**
  ```bash
  EXTRACTION_ID=$(python3 -c "
  import json
  data = json.load(open('${DAT_SANDBOX}/api-results/CA-9.json'))
  records = data if isinstance(data, list) else data.get('data', [])
  print(records[0]['id'] if records else '')
  " 2>/dev/null)
  if [ -n "${EXTRACTION_ID}" ]; then
    curl -sk -o "${DAT_SANDBOX}/api-results/CA-10.csv" -w '%{http_code}' \
      "${STARTER_PACK_URL}/api/history/${EXTRACTION_ID}/download/csv"
  else
    echo "SKIP: No extraction history available"
  fi
  ```

---

## Error Response Reference

All error responses follow FastAPI conventions:

| HTTP Status | Meaning | Example |
|---|---|---|
| 400 | Bad request (e.g., non-PDF file, job not complete) | `{"detail": "File must be a PDF"}` |
| 404 | Resource not found (job, extraction, file) | `{"detail": "Job not found"}` |
| 502 | Upstream model inference failed | `{"detail": "Model inference failed: ..."}` |

---

## Extraction Timing Reference

| Contract Size | Approximate Extraction Time | Notes |
|---|---|---|
| 1-5 pages | 3-5 minutes | Minimal test case |
| 5-15 pages | 8-15 minutes | Typical contract |
| 15-50 pages | 20-40 minutes | Large contract — avoid for smoke tests |
| 50+ pages | 40+ minutes | Very large — not recommended for automated testing |
