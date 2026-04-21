# PaaS RAG API Tests

10 tests executed via `curl` against `${STARTER_PACK_URL}`. Execute in order — some tests depend on prior results.

**MANDATORY:** Execute ALL tests in order by ascending ID. If a test fails, record the failure and continue. Do NOT skip any test.

**No authentication required.**

**Note:** The frontend proxies `/v1/*` requests to the LlamaStack backend (port 8321). All API paths use the `/v1/` prefix.

---

## Execution Order

| # | ID | Test | Method | Endpoint | P | Type | Timeout | Preconditions |
|---|---|---|---|---|---|---|---|---|
| 1 | PA-1 | Health check | GET | `/v1/health` | P0 | smoke | 30s | LlamaStack pod Running |
| 2 | PA-2 | List models | GET | `/v1/models` | P0 | smoke | 30s | LlamaStack pod Running |
| 3 | PA-3 | List vector stores | GET | `/v1/vector_stores` | P0 | smoke | 30s | LlamaStack pod Running |
| 4 | PA-4 | Create vector store | POST | `/v1/vector_stores` | P0 | e2e | 30s | PA-2 returned embedding model |
| 5 | PA-5 | Upload file | POST | `/v1/files` | P0 | e2e | 60s | LlamaStack pod Running |
| 6 | PA-6 | Attach file to vector store | POST | `/v1/vector_stores/{id}/files` | P0 | e2e | 60s | PA-4 + PA-5 completed |
| 7 | PA-7 | Poll file indexing status | GET | `/v1/vector_stores/{id}/files/{fileId}` | P0 | e2e | 3min | PA-6 returned file attachment |
| 8 | PA-8 | RAG chat (streaming) | POST | `/v1/responses` | P0 | e2e | 2min | PA-7 indexing complete |
| 9 | PA-9 | Delete file from vector store | DELETE | `/v1/vector_stores/{id}/files/{fileId}` | P1 | regression | 30s | PA-6 file exists |
| 10 | PA-10 | Delete vector store | DELETE | `/v1/vector_stores/{id}` | P1 | regression | 30s | PA-4 vector store exists |
| 11 | PA-11 | Delete uploaded file + bucket objects (cleanup hook) | DELETE | `/v1/files/{fileId}` + OCI CLI | P0 | cleanup | 60s | PA-5 file ID available |

> **Cleanup discipline:** PA-11 MUST run at the end of the test suite. The `POST /v1/files` call in PA-5 uploads the file into the paas_rag Object Storage bucket (`<deployment-name>-bucket`). Without cleanup, orphaned objects will block `terraform destroy` with a `409-BucketNotEmpty` error, forcing manual cleanup later. Even if earlier tests fail, run PA-11 unconditionally as a teardown step.

---

## Test Details

### PA-1: Health Check (P0 smoke)

- **Endpoint:** `GET /v1/health`
- **Request:** None
- **Verification:**
  - HTTP 200
  - Response indicates healthy status
- **Note:** This endpoint checks LlamaStack backend health. If it returns 502/503, the pod is still starting.
- **curl:**
  ```bash
  curl -sk -o "${DAT_SANDBOX}/api-results/PA-1.json" -w '%{http_code}' \
    "${STARTER_PACK_URL}/v1/health"
  ```

### PA-2: List Models (P0 smoke)

- **Endpoint:** `GET /v1/models`
- **Request:** None
- **Verification:**
  - HTTP 200
  - Response has `data` array with model objects
  - Each model has `identifier` (or `id`), `model_type` fields
  - At least one model with `model_type === "llm"` exists
  - At least one model with `model_type === "embedding"` exists
- **Output:** Save an embedding model identifier for PA-4.
- **curl:**
  ```bash
  curl -sk -o "${DAT_SANDBOX}/api-results/PA-2.json" -w '%{http_code}' \
    "${STARTER_PACK_URL}/v1/models"
  ```

### PA-3: List Vector Stores (P0 smoke)

- **Endpoint:** `GET /v1/vector_stores`
- **Request:** None
- **Verification:**
  - HTTP 200
  - Response has `data` array (can be empty on fresh deploy)
  - Each vector store has `id`, `name`, `status` fields
- **Note:** System collections (`metadata_schema`, `meta`) may appear in the API response but are filtered in the UI.
- **curl:**
  ```bash
  curl -sk -o "${DAT_SANDBOX}/api-results/PA-3.json" -w '%{http_code}' \
    "${STARTER_PACK_URL}/v1/vector_stores"
  ```

### PA-4: Create Vector Store (P0 e2e)

- **Endpoint:** `POST /v1/vector_stores`
- **Request:**
  ```json
  {
    "name": "test_collection",
    "embedding_model": "<embedding_model_id_from_PA-2>",
    "embedding_dimension": 2048,
    "metadata": {
      "purpose": "api-test",
      "source": "automated-testing"
    }
  }
  ```
- **Verification:**
  - HTTP 200 or 201
  - Response has `id` field (vector store ID)
  - Response has `name` matching "test_collection"
  - Subsequent GET `/v1/vector_stores` includes the new store
- **Output:** Save the vector store `id` for PA-5 through PA-10.
- **curl:**
  ```bash
  EMBEDDING_MODEL=$(python3 -c "
  import json
  data = json.load(open('${DAT_SANDBOX}/api-results/PA-2.json'))
  models = data.get('data', data) if isinstance(data, dict) else data
  for m in models:
    if m.get('model_type') == 'embedding':
      print(m.get('identifier', m.get('id', ''))); break
  ")
  curl -sk -X POST -H 'Content-Type: application/json' \
    -d "{\"name\":\"test_collection\",\"embedding_model\":\"${EMBEDDING_MODEL}\",\"embedding_dimension\":2048,\"metadata\":{\"purpose\":\"api-test\",\"source\":\"automated-testing\"}}" \
    -o "${DAT_SANDBOX}/api-results/PA-4.json" -w '%{http_code}' \
    "${STARTER_PACK_URL}/v1/vector_stores"
  ```

### PA-5: Upload File (P0 e2e)

- **Endpoint:** `POST /v1/files`
- **Request:** `multipart/form-data` with:
  - `file`: a test text file
  - `purpose`: `"assistants"` — the backend rejects `file_search` with a validation error; accepted values are `assistants` or `batch`.
- **Verification:**
  - HTTP 200
  - Response has `id` field (file ID)
  - Response has `filename` field
- **Output:** Save the file `id` for PA-6.
- **curl:**
  ```bash
  # Create test file
  echo "This is a test document for PaaS RAG API testing. It contains information about Oracle Cloud Infrastructure, autonomous databases, and AI-powered document analysis using LlamaStack." > "${DAT_SANDBOX}/api-results/test-doc.txt"

  curl -sk -X POST \
    -F "file=@${DAT_SANDBOX}/api-results/test-doc.txt" \
    -F "purpose=assistants" \
    -o "${DAT_SANDBOX}/api-results/PA-5.json" -w '%{http_code}' \
    "${STARTER_PACK_URL}/v1/files"
  ```

### PA-6: Attach File to Vector Store (P0 e2e)

- **Endpoint:** `POST /v1/vector_stores/{vector_store_id}/files`
- **Request:**
  ```json
  {
    "file_id": "<file_id_from_PA-5>"
  }
  ```
- **Verification:**
  - HTTP 200
  - Response has `id` (file attachment ID) and `status` field
  - Status may be `"in_progress"` or `"completed"`
- **Output:** Save the file attachment `id` for PA-7 and PA-9.
- **curl:**
  ```bash
  VS_ID=$(python3 -c "import json; print(json.load(open('${DAT_SANDBOX}/api-results/PA-4.json'))['id'])")
  FILE_ID=$(python3 -c "import json; print(json.load(open('${DAT_SANDBOX}/api-results/PA-5.json'))['id'])")
  curl -sk -X POST -H 'Content-Type: application/json' \
    -d "{\"file_id\":\"${FILE_ID}\"}" \
    -o "${DAT_SANDBOX}/api-results/PA-6.json" -w '%{http_code}' \
    "${STARTER_PACK_URL}/v1/vector_stores/${VS_ID}/files"
  ```

### PA-7: Poll File Indexing Status (P0 e2e, 3min timeout)

- **Endpoint:** `GET /v1/vector_stores/{vector_store_id}/files/{file_id}`
- **Request:** None (use IDs from PA-4 and PA-6)
- **Verification:**
  - HTTP 200
  - `status` transitions: `in_progress` → `completed` (or `failed`)
  - When `completed`: file is indexed and available for RAG queries
- **Polling:** Check every 2 seconds, up to 90 attempts (3 min).
- **curl:**
  ```bash
  VS_ID=$(python3 -c "import json; print(json.load(open('${DAT_SANDBOX}/api-results/PA-4.json'))['id'])")
  FILE_ATTACH_ID=$(python3 -c "import json; print(json.load(open('${DAT_SANDBOX}/api-results/PA-6.json'))['id'])")
  for i in $(seq 1 90); do
    HTTP_CODE=$(curl -sk -o "${DAT_SANDBOX}/api-results/PA-7.json" -w '%{http_code}' \
      "${STARTER_PACK_URL}/v1/vector_stores/${VS_ID}/files/${FILE_ATTACH_ID}")
    STATUS=$(python3 -c "import json; print(json.load(open('${DAT_SANDBOX}/api-results/PA-7.json')).get('status',''))" 2>/dev/null)
    echo "Attempt $i: status=$STATUS"
    if [ "$STATUS" = "completed" ] || [ "$STATUS" = "failed" ]; then
      break
    fi
    sleep 2
  done
  ```

### PA-8: RAG Chat — Streaming (P0 e2e, 2min timeout)

- **Endpoint:** `POST /v1/responses`
- **Request:**
  ```json
  {
    "model": "<llm_model_id_from_PA-2>",
    "input": "What information is in the test document?",
    "stream": true,
    "instructions": "You are a helpful assistant",
    "temperature": 0.7,
    "tools": [
      {
        "type": "file_search",
        "vector_store_ids": ["<vector_store_id_from_PA-4>"]
      }
    ]
  }
  ```
- **Verification:**
  - HTTP 200
  - Response is SSE stream (`text/event-stream` or chunked)
  - Stream contains `data:` lines with JSON objects
  - At least one event has `type: "response.output_text.delta"` with text content
  - Stream ends with `type: "response.completed"` event
  - Citations may be present in events with `results` array (filename, file_id, score)
- **Note:** The frontend transforms the request format. Use the LlamaStack `/v1/responses` format directly.
- **curl:**
  ```bash
  VS_ID=$(python3 -c "import json; print(json.load(open('${DAT_SANDBOX}/api-results/PA-4.json'))['id'])")
  LLM_MODEL=$(python3 -c "
  import json
  data = json.load(open('${DAT_SANDBOX}/api-results/PA-2.json'))
  models = data.get('data', data) if isinstance(data, dict) else data
  for m in models:
    if m.get('model_type') == 'llm':
      print(m.get('identifier', m.get('id', ''))); break
  ")
  curl -sk -X POST -H 'Content-Type: application/json' -N \
    -d "{\"model\":\"${LLM_MODEL}\",\"input\":\"What information is in the test document?\",\"stream\":true,\"instructions\":\"You are a helpful assistant\",\"temperature\":0.7,\"tools\":[{\"type\":\"file_search\",\"vector_store_ids\":[\"${VS_ID}\"]}]}" \
    -o "${DAT_SANDBOX}/api-results/PA-8.txt" -w '%{http_code}' \
    "${STARTER_PACK_URL}/v1/responses"
  ```
- **Validate stream:**
  ```bash
  # Check stream has content
  grep -c 'data:' "${DAT_SANDBOX}/api-results/PA-8.txt"
  # Check for completion event
  grep 'response.completed' "${DAT_SANDBOX}/api-results/PA-8.txt"
  ```

### PA-9: Delete File from Vector Store (P1 regression)

- **Endpoint:** `DELETE /v1/vector_stores/{vector_store_id}/files/{file_id}`
- **Request:** None
- **Verification:**
  - HTTP 200
  - Subsequent GET `/v1/vector_stores/{id}/files` shows no files (or reduced count)
- **curl:**
  ```bash
  VS_ID=$(python3 -c "import json; print(json.load(open('${DAT_SANDBOX}/api-results/PA-4.json'))['id'])")
  FILE_ATTACH_ID=$(python3 -c "import json; print(json.load(open('${DAT_SANDBOX}/api-results/PA-6.json'))['id'])")
  curl -sk -X DELETE \
    -o "${DAT_SANDBOX}/api-results/PA-9.json" -w '%{http_code}' \
    "${STARTER_PACK_URL}/v1/vector_stores/${VS_ID}/files/${FILE_ATTACH_ID}"
  ```

### PA-10: Delete Vector Store (P1 regression) — DESTRUCTIVE, RUN LAST

- **Endpoint:** `DELETE /v1/vector_stores/{vector_store_id}`
- **Request:** None
- **Verification:**
  - HTTP 200
  - Subsequent GET `/v1/vector_stores` no longer includes `test_collection`
- **Note:** Only delete the test vector store — do NOT delete user-created stores.
- **curl:**
  ```bash
  VS_ID=$(python3 -c "import json; print(json.load(open('${DAT_SANDBOX}/api-results/PA-4.json'))['id'])")
  curl -sk -X DELETE \
    -o "${DAT_SANDBOX}/api-results/PA-10.json" -w '%{http_code}' \
    "${STARTER_PACK_URL}/v1/vector_stores/${VS_ID}"
  ```

### PA-11: Cleanup — Delete Uploaded File and Purge Bucket Objects (P0 cleanup)

**Run this ALWAYS — even if PA-5..PA-10 failed.** The `POST /v1/files` call in PA-5 wrote a real object into the paas_rag Object Storage bucket. If this cleanup is skipped, `terraform destroy` on the app stack will fail with `409-BucketNotEmpty` because OCI won't delete a bucket that still has objects (or object versions) in it.

- **Endpoints:**
  - `DELETE /v1/files/{file_id}` — LlamaStack Files API
  - `oci os bucket list-objects`, `oci os object delete` — raw Object Storage sweep for anything left behind
- **Preconditions:** PA-5 saved `${DAT_SANDBOX}/api-results/PA-5.json` with the file `id`. Bucket name discoverable via `terraform output -raw paas_rag_bucket_name` on the app stack (or via the ORM stack's Application Information tab).
- **Verification:**
  - `DELETE /v1/files/{id}` returns HTTP 200 (or 404 if already gone — treat as success).
  - `oci os object list --bucket-name <bucket>` returns an empty array.
  - `oci os object list-object-versions --bucket-name <bucket>` returns an empty array (versioned buckets retain delete-markers; purge those too).
- **Bash (run unconditionally as teardown):**
  ```bash
  set +e   # Cleanup must NOT abort on earlier non-zero status; keep going.

  # 1) Delete via LlamaStack Files API (best-effort — idempotent).
  if [ -f "${DAT_SANDBOX}/api-results/PA-5.json" ]; then
    FILE_ID=$(python3 -c "import json; print(json.load(open('${DAT_SANDBOX}/api-results/PA-5.json'))['id'])" 2>/dev/null)
    if [ -n "${FILE_ID}" ]; then
      curl -sk -X DELETE \
        -o "${DAT_SANDBOX}/api-results/PA-11-llamastack.json" -w '%{http_code}\n' \
        "${STARTER_PACK_URL}/v1/files/${FILE_ID}"
    fi
  fi

  # 2) Resolve bucket name from the app stack's TF outputs (skip if not available).
  APP_STACK_ID="${APP_STACK_ID:?set APP_STACK_ID to the paas_rag app stack OCID}"
  BUCKET=$(oci resource-manager stack get --stack-id "${APP_STACK_ID}" \
             --query 'data."variables"."starter_pack_deployment_name"' --raw-output 2>/dev/null)-bucket
  # Or read bucket directly from Application Information tab output 'paas_rag_bucket_name'.
  echo "Bucket: ${BUCKET}"

  NAMESPACE=$(oci os ns get --query 'data' --raw-output)

  # 3) Force-delete every current object.
  oci os object bulk-delete --bucket-name "${BUCKET}" --namespace "${NAMESPACE}" \
    --force --include '*' 2>&1 | tail -3

  # 4) Purge object versions + delete-markers (versioned buckets).
  oci os object list-object-versions --bucket-name "${BUCKET}" --namespace "${NAMESPACE}" --all \
    --query 'data.items[*].{name:name, versionId:"version-id"}' --output json 2>/dev/null \
    | python3 -c "
import json, sys, subprocess, os
bucket = os.environ['BUCKET']; ns = os.environ['NAMESPACE']
rows = json.load(sys.stdin) or []
for r in rows:
    subprocess.run(['oci','os','object','delete',
                    '--bucket-name',bucket,'--namespace',ns,
                    '--name',r['name'],'--version-id',r['versionId'],'--force'],
                   check=False, capture_output=True)
print(f'purged {len(rows)} versioned entries')
"

  # 5) Confirm bucket is empty.
  REMAINING=$(oci os object list --bucket-name "${BUCKET}" --namespace "${NAMESPACE}" \
                --query 'length(data.objects)' 2>/dev/null)
  echo "Remaining objects in bucket: ${REMAINING:-unknown}"
  set -e
  ```

**Why the belt-and-suspenders (LlamaStack DELETE + raw OCI object sweep):** `DELETE /v1/files/{id}` removes the file row in LlamaStack's metadata, but the underlying Object Storage blob may not be cleaned up immediately (or may be retained if versioning is enabled). The raw OCI sweep guarantees the bucket is empty regardless of LlamaStack's internal state.

Return the bucket-empty status in your Phase 6c-2 results table. If `PA-11` leaves any object in the bucket, flag it as a teardown failure so the controller can manually clean before `/destroy-stack`.
