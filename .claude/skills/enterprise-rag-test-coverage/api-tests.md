# Enterprise RAG API Tests

10 tests executed via `curl` against `${STARTER_PACK_URL}`. Execute in order — some tests depend on prior results.

**MANDATORY:** Execute ALL tests in order by ascending ID. If a test fails, record the failure and continue. Do NOT skip any test.

**No authentication required.**

**Note:** The frontend proxies `/api/*` requests to backend services:
- `/api/generate` → RAG Server (port 8081)
- All other `/api/*` → Ingestor Server (port 8082)

---

## Execution Order

| # | ID | Test | Method | Endpoint | P | Type | Timeout | Preconditions |
|---|---|---|---|---|---|---|---|---|
| 1 | EA-1 | Health check | GET | `/api/health?check_dependencies=true` | P0 | smoke | 30s | Frontend pod Running |
| 2 | EA-2 | List collections | GET | `/api/collections` | P0 | smoke | 30s | Ingestor pod Running |
| 3 | EA-3 | Create collection | POST | `/api/collection` | P0 | e2e | 30s | Milvus Running |
| 4 | EA-4 | Upload documents | POST | `/api/documents?blocking=false` | P0 | e2e | 60s | EA-3 collection created |
| 5 | EA-5 | Poll ingestion status | GET | `/api/status?task_id={id}` | P0 | e2e | 5min | EA-4 returned task_id |
| 6 | EA-6 | List documents | GET | `/api/documents?collection_name={name}` | P1 | smoke | 30s | EA-5 ingestion complete |
| 7 | EA-7 | RAG chat (streaming) | POST | `/api/generate` | P0 | e2e | 2min | NIM LLM Running + EA-3 collection exists |
| 8 | EA-8 | Chat without knowledge base | POST | `/api/generate` | P1 | e2e | 2min | NIM LLM Running |
| 9 | EA-9 | Delete documents | DELETE | `/api/documents?collection_name={name}` | P1 | regression | 30s | EA-6 documents exist |
| 10 | EA-10 | Delete collection | DELETE | `/api/collections` | P1 | regression | 30s | EA-3 collection exists |

---

## Test Details

### EA-1: Health Check (P0 smoke)

- **Endpoint:** `GET /api/health?check_dependencies=true`
- **Request:** None
- **Verification:**
  - HTTP 200
  - Response has `message` field
  - `databases` array has entries with `service`, `status` fields
  - `nim` array has entries showing NIM service status (LLM, embedding, ranking)
  - At least one NIM service has `status: "available"` or `"ready"`
- **Note:** This endpoint checks all backend dependencies (Milvus, NIMs, MinIO, Redis). Some may show "unavailable" during startup — that's expected. The critical check is that the endpoint itself responds.
- **curl:**
  ```bash
  curl -sk -o "${DAT_SANDBOX}/api-results/EA-1.json" -w '%{http_code}' \
    "${STARTER_PACK_URL}/api/health?check_dependencies=true"
  ```

### EA-2: List Collections (P0 smoke)

- **Endpoint:** `GET /api/collections`
- **Request:** None
- **Verification:**
  - HTTP 200
  - Response has `collections` array (can be empty on fresh deploy)
  - Each collection has `collection_name` (string) and `num_entities` (number)
- **curl:**
  ```bash
  curl -sk -o "${DAT_SANDBOX}/api-results/EA-2.json" -w '%{http_code}' \
    "${STARTER_PACK_URL}/api/collections"
  ```

### EA-3: Create Collection (P0 e2e)

- **Endpoint:** `POST /api/collection`
- **Request:**
  ```json
  {
    "collection_name": "test_collection",
    "embedding_dimension": 2048,
    "metadata_schema": [
      { "name": "source", "type": "string", "required": false, "description": "Document source" }
    ]
  }
  ```
- **Verification:**
  - HTTP 200 or 201
  - No error in response
  - Subsequent GET `/api/collections` includes `test_collection`
- **curl:**
  ```bash
  curl -sk -X POST -H 'Content-Type: application/json' \
    -d '{"collection_name":"test_collection","embedding_dimension":2048,"metadata_schema":[{"name":"source","type":"string","required":false,"description":"Document source"}]}' \
    -o "${DAT_SANDBOX}/api-results/EA-3.json" -w '%{http_code}' \
    "${STARTER_PACK_URL}/api/collection"
  ```

### EA-4: Upload Documents (P0 e2e)

- **Endpoint:** `POST /api/documents?blocking=false`
- **Request:** `multipart/form-data` with:
  - `documents`: a test text file
  - `data`: JSON string `{"collection_name":"test_collection","blocking":false,"custom_metadata":[{"filename":"test.txt","metadata":{"source":"api-test"}}]}`
- **Verification:**
  - HTTP 200 or 202
  - Response has `task_id` (string)
- **Output:** Save `task_id` for EA-5.
- **Note:** Create a small test file first, then upload it.
- **curl:**
  ```bash
  # Create test file
  echo "This is a test document for Enterprise RAG API testing. It contains information about vehicle routing optimization and AI-powered document analysis." > "${DAT_SANDBOX}/api-results/test-doc.txt"

  curl -sk -X POST \
    -F "documents=@${DAT_SANDBOX}/api-results/test-doc.txt" \
    -F 'data={"collection_name":"test_collection","blocking":false,"custom_metadata":[{"filename":"test-doc.txt","metadata":{"source":"api-test"}}]}' \
    -o "${DAT_SANDBOX}/api-results/EA-4.json" -w '%{http_code}' \
    "${STARTER_PACK_URL}/api/documents?blocking=false"
  ```

### EA-5: Poll Ingestion Status (P0 e2e, 5min timeout)

- **Endpoint:** `GET /api/status?task_id=${TASK_ID}`
- **Request:** None (use `task_id` from EA-4)
- **Verification:**
  - HTTP 200
  - `state` transitions: `PENDING` → `FINISHED` (or `FAILED`)
  - When `FINISHED`: `result.total_documents` >= 1, `result.documents` array has entries
  - `result.failed_documents` should be empty array (no failures)
- **Polling:** Check every 5 seconds, up to 60 attempts (5 min).
- **curl:**
  ```bash
  TASK_ID=$(python3 -c "import json; print(json.load(open('${DAT_SANDBOX}/api-results/EA-4.json'))['task_id'])")
  for i in $(seq 1 60); do
    HTTP_CODE=$(curl -sk -o "${DAT_SANDBOX}/api-results/EA-5.json" -w '%{http_code}' \
      "${STARTER_PACK_URL}/api/status?task_id=${TASK_ID}")
    STATE=$(python3 -c "import json; print(json.load(open('${DAT_SANDBOX}/api-results/EA-5.json')).get('state',''))" 2>/dev/null)
    echo "Attempt $i: state=$STATE"
    if [ "$STATE" = "FINISHED" ] || [ "$STATE" = "FAILED" ]; then
      break
    fi
    sleep 5
  done
  ```

### EA-6: List Documents (P1 smoke)

- **Endpoint:** `GET /api/documents?collection_name=test_collection`
- **Request:** None
- **Verification:**
  - HTTP 200
  - `total_documents` >= 1
  - `documents` array has entries with `document_name` fields
- **curl:**
  ```bash
  curl -sk -o "${DAT_SANDBOX}/api-results/EA-6.json" -w '%{http_code}' \
    "${STARTER_PACK_URL}/api/documents?collection_name=test_collection"
  ```

### EA-7: RAG Chat — Streaming (P0 e2e, 2min timeout)

- **Endpoint:** `POST /api/generate`
- **Request:**
  ```json
  {
    "messages": [{ "role": "user", "content": "What information is in the test document?" }],
    "use_knowledge_base": true,
    "collection_names": ["test_collection"],
    "temperature": 0.7,
    "top_p": 0.9,
    "max_tokens": 512,
    "vdb_top_k": 10,
    "reranker_top_k": 5,
    "enable_citations": true,
    "enable_reranker": true,
    "enable_guardrails": false,
    "enable_query_rewriting": false
  }
  ```
- **Verification:**
  - HTTP 200
  - Response is SSE stream (`text/event-stream` or chunked)
  - Stream contains `data:` lines with JSON objects
  - At least one chunk has `choices[0].delta.content` with non-empty text
  - Final chunk has `choices[0].finish_reason: "stop"`
  - Citations may be present in final chunks (`citations.results` array)
- **Note:** This is a streaming endpoint. Use `curl` with no buffering to capture the full stream.
- **curl:**
  ```bash
  curl -sk -X POST -H 'Content-Type: application/json' -N \
    -d '{"messages":[{"role":"user","content":"What information is in the test document?"}],"use_knowledge_base":true,"collection_names":["test_collection"],"temperature":0.7,"top_p":0.9,"max_tokens":512,"vdb_top_k":10,"reranker_top_k":5,"enable_citations":true,"enable_reranker":true,"enable_guardrails":false,"enable_query_rewriting":false}' \
    -o "${DAT_SANDBOX}/api-results/EA-7.txt" -w '%{http_code}' \
    "${STARTER_PACK_URL}/api/generate"
  ```
- **Validate stream:**
  ```bash
  # Check stream has content
  grep -c 'data:' "${DAT_SANDBOX}/api-results/EA-7.txt"
  # Check for finish_reason
  grep 'finish_reason' "${DAT_SANDBOX}/api-results/EA-7.txt"
  ```

### EA-8: Chat Without Knowledge Base (P1 e2e, 2min timeout)

- **Endpoint:** `POST /api/generate`
- **Request:**
  ```json
  {
    "messages": [{ "role": "user", "content": "What is retrieval augmented generation?" }],
    "use_knowledge_base": false,
    "temperature": 0.7,
    "max_tokens": 256
  }
  ```
- **Verification:**
  - HTTP 200
  - SSE stream with content (LLM responds without RAG retrieval)
  - Response discusses RAG concepts
  - No citations expected (knowledge base disabled)
- **curl:**
  ```bash
  curl -sk -X POST -H 'Content-Type: application/json' -N \
    -d '{"messages":[{"role":"user","content":"What is retrieval augmented generation?"}],"use_knowledge_base":false,"temperature":0.7,"max_tokens":256}' \
    -o "${DAT_SANDBOX}/api-results/EA-8.txt" -w '%{http_code}' \
    "${STARTER_PACK_URL}/api/generate"
  ```

### EA-9: Delete Documents (P1 regression)

- **Endpoint:** `DELETE /api/documents?collection_name=test_collection`
- **Request:** `["test-doc.txt"]` (array of document names)
- **Verification:**
  - HTTP 200
  - Subsequent GET `/api/documents?collection_name=test_collection` shows reduced count
- **curl:**
  ```bash
  curl -sk -X DELETE -H 'Content-Type: application/json' \
    -d '["test-doc.txt"]' \
    -o "${DAT_SANDBOX}/api-results/EA-9.json" -w '%{http_code}' \
    "${STARTER_PACK_URL}/api/documents?collection_name=test_collection"
  ```

### EA-10: Delete Collection (P1 regression) — DESTRUCTIVE, RUN LAST

- **Endpoint:** `DELETE /api/collections`
- **Request:** `["test_collection"]` (array of collection names)
- **Verification:**
  - HTTP 200
  - Subsequent GET `/api/collections` no longer includes `test_collection`
- **Note:** Only delete the test collection — do NOT delete user-created collections.
- **curl:**
  ```bash
  curl -sk -X DELETE -H 'Content-Type: application/json' \
    -d '["test_collection"]' \
    -o "${DAT_SANDBOX}/api-results/EA-10.json" -w '%{http_code}' \
    "${STARTER_PACK_URL}/api/collections"
  ```
