# VSS API Tests

16 tests executed via `curl` against `${STARTER_PACK_URL}`. Execute in order — some tests depend on prior results.

**MANDATORY:** Execute ALL tests in order by ascending ID. If a test fails, record the failure and continue. Do NOT skip any test.

---

## Execution Order

| # | ID | Test | Method | Endpoint | P | Type | Timeout | Preconditions |
|---|---|---|---|---|---|---|---|---|
| 1 | VA-1 | Backend config | GET | `/api/vss/config` | P0 | smoke | 10s | Frontend pod Running |
| 2 | VA-5a | List bucket files (valid) | POST | `/api/list-bucket-files` | P1 | smoke | 10s | Valid `VSS_BUCKET_NAME` |
| 3 | VA-5b | List bucket files (invalid) | POST | `/api/list-bucket-files` | P1 | regression | 10s | None |
| 4 | VA-4 | Download & upload file | POST | `/api/download-and-upload` | P0 | e2e | 5min | Valid bucket + object |
| 5 | VA-2 | Video streaming | GET | `/api/vss/video-stream` | P1 | smoke | 10s | Video previously downloaded (VA-4) |
| 6 | VA-3 | Summarize video | POST | `/api/vss/summarize` | P0 | e2e | 35min | File uploaded via VA-4 |
| 7 | VA-9a | List summaries | GET | `/api/videos/summaries` | P0 | smoke | 10s | Frontend pod Running |
| 8 | VA-9b | Summaries pagination | GET | `/api/videos/summaries?page=1&limit=2` | P1 | regression | 10s | None |
| 9 | VA-10 | Get summary detail | GET | `/api/videos/summary` | P0 | smoke | 10s | >=1 summary exists |
| 10 | VA-11 | Create/update summary | POST | `/api/videos/summary` | P1 | regression | 10s | None |
| 11 | VA-6 | List jobs | GET | `/api/jobs` | P1 | smoke | 10s | Frontend pod Running |
| 12 | VA-7 | Enqueue jobs | POST | `/api/jobs` | P1 | e2e | 10s | Valid bucket + objects |
| 13 | VA-8 | Process next job | POST | `/api/jobs/process-next` | P1 | e2e | 35min | Pending job in queue (VA-7) |
| 14 | VA-13 | Get row reviews | GET | `/api/videos/summary/[id]/reviews` | P1 | smoke | 10s | >=1 summary exists |
| 15 | VA-14 | Update row reviews | PUT | `/api/videos/summary/[id]/reviews` | P1 | regression | 10s | >=1 summary exists |
| 16 | VA-12 | Delete summary | DELETE | `/api/videos/summary/[id]` | P1 | regression | 10s | >=1 summary exists |

> **Note:** VA-12 (delete) is last because it's destructive — run after all read tests.

---

## Test Details

### VA-1: Backend Config (P0 smoke)

- **Endpoint:** `GET /api/vss/config`
- **Request:** None
- **Verification:**
  - HTTP 200
  - `success === true`
  - `capabilities` object has `enableAudio` (boolean) and `enableCv` (boolean)
  - Does NOT crash on backend timeout — returns `{ success: true, capabilities: { enableAudio: false, enableCv: false } }` on timeout
- **curl:**
  ```bash
  curl -sk -o "${DAT_SANDBOX}/api-results/VA-1.json" -w '%{http_code}' "${STARTER_PACK_URL}/api/vss/config"
  ```

### VA-5a: List Bucket Files — Valid (P1 smoke)

- **Endpoint:** `POST /api/list-bucket-files`
- **Request:** `{ "bucketName": "${VSS_BUCKET_NAME}" }`
- **Verification:**
  - HTTP 200, `success: true`
  - `files` is array
  - Each file has `name` (string), `size` (number), `timeCreated` (ISO date string)
- **curl:**
  ```bash
  curl -sk -X POST -H 'Content-Type: application/json' \
    -d '{"bucketName":"'"${VSS_BUCKET_NAME}"'"}' \
    -o "${DAT_SANDBOX}/api-results/VA-5a.json" -w '%{http_code}' \
    "${STARTER_PACK_URL}/api/list-bucket-files"
  ```

### VA-5b: List Bucket Files — Invalid (P1 regression)

- **Endpoint:** `POST /api/list-bucket-files`
- **Request:** `{ "bucketName": "nonexistent-bucket-12345" }`
- **Verification:**
  - Response is NOT 500 (server should handle gracefully)
  - `success: false`
  - `error` string present
- **curl:**
  ```bash
  curl -sk -X POST -H 'Content-Type: application/json' \
    -d '{"bucketName":"nonexistent-bucket-12345"}' \
    -o "${DAT_SANDBOX}/api-results/VA-5b.json" -w '%{http_code}' \
    "${STARTER_PACK_URL}/api/list-bucket-files"
  ```

### VA-4: Download & Upload File (P0 e2e)

- **Endpoint:** `POST /api/download-and-upload`
- **Request:** `{ "bucketName": "${VSS_BUCKET_NAME}", "objectName": "${VSS_OBJECT_KEY}" }`
- **Verification:**
  - HTTP 200, `success: true`
  - `fileId` is a non-empty string (save this — needed for VA-3)
  - `bytes > 0`, `mediaType` matches video MIME type
  - On failure: `{ success: false, error: "<message>" }`
- **curl:**
  ```bash
  curl -sk -X POST -H 'Content-Type: application/json' \
    -d '{"bucketName":"'"${VSS_BUCKET_NAME}"'","objectName":"'"${VSS_OBJECT_KEY}"'"}' \
    -o "${DAT_SANDBOX}/api-results/VA-4.json" -w '%{http_code}' \
    "${STARTER_PACK_URL}/api/download-and-upload"
  ```
- **Output:** Save `fileId` from response for VA-3.

### VA-2: Video Streaming (P1 smoke)

- **Endpoint:** `GET /api/vss/video-stream?bucket=${VSS_BUCKET_NAME}&objectName=${VSS_OBJECT_KEY}`
- **Request:** None (query params)
- **Verification:**
  - HTTP 200 (full) or 206 (range) with `Content-Type: video/*`
  - Range requests return 206 with `Content-Range` header
  - 404 if file not cached on FSS (means VA-4 didn't run or failed)
- **curl:**
  ```bash
  curl -sk -o /dev/null -w '%{http_code} %{content_type}' \
    "${STARTER_PACK_URL}/api/vss/video-stream?bucket=${VSS_BUCKET_NAME}&objectName=${VSS_OBJECT_KEY}"
  ```

### VA-3: Summarize Video (P0 e2e, 35min timeout)

- **Endpoint:** `POST /api/vss/summarize`
- **Request:** `{ "fileId": "<from VA-4>" }`
  - Optional params: `prompt`, `model`, `temperature`, `top_p`, `top_k`, `max_tokens`, `seed`, `num_frames_per_chunk`, `vlm_input_width`, `vlm_input_height`, `summarize_temperature`, `summarize_top_p`, `summarize_max_tokens`, `chat_temperature`, `chat_top_p`, `chat_max_tokens`, `notification_temperature`, `notification_top_p`, `notification_max_tokens`, `summarize_batch_size`, `rag_batch_size`, `rag_top_k`, `enable_audio`, `enable_cv_metadata`, `cv_pipeline_prompt`, `chunk_duration`, `caption_summarization_prompt`, `summary_aggregation_prompt`
- **Verification:**
  - HTTP 200 with `success: true`
  - `result.summarization` is a non-empty string
  - Timeline format: lines like `120.0:125.0 | Categories: Violence, Alcohol | Event: ...`
  - On failure: `{ success: false, error: "<message>" }`
- **CRITICAL:** This takes 10-30 minutes. Do NOT timeout early. Use `--max-time 2100`.
- **curl:**
  ```bash
  curl -sk -X POST -H 'Content-Type: application/json' --max-time 2100 \
    -d '{"fileId":"'"${FILE_ID}"'"}' \
    -o "${DAT_SANDBOX}/api-results/VA-3.json" -w '%{http_code}' \
    "${STARTER_PACK_URL}/api/vss/summarize"
  ```

### VA-9a: List Summaries (P0 smoke)

- **Endpoint:** `GET /api/videos/summaries?page=1&limit=50`
- **Verification:**
  - HTTP 200
  - `data` is array, `total` is number
  - `page` and `limit` match query params, `data.length <= limit`
  - Each item has `summaryId`, `videoId`, `bucketName`, `objectKey`, `resultLength`, `updatedAt`
- **curl:**
  ```bash
  curl -sk -o "${DAT_SANDBOX}/api-results/VA-9a.json" -w '%{http_code}' \
    "${STARTER_PACK_URL}/api/videos/summaries?page=1&limit=50"
  ```
- **Output:** Save a `summaryId` from the response for VA-10, VA-13, VA-14, VA-12.

### VA-9b: Summaries Pagination (P1 regression)

- **Endpoint:** `GET /api/videos/summaries?page=1&limit=2`
- **Verification:**
  - HTTP 200
  - `data.length <= 2`, `page === 1`, `limit === 2`
- **curl:**
  ```bash
  curl -sk -o "${DAT_SANDBOX}/api-results/VA-9b.json" -w '%{http_code}' \
    "${STARTER_PACK_URL}/api/videos/summaries?page=1&limit=2"
  ```

### VA-10: Get Summary Detail (P0 smoke)

- **Endpoint:** `GET /api/videos/summary?bucket=${VSS_BUCKET_NAME}&objectKey=${VSS_OBJECT_KEY}`
- **Verification:**
  - HTTP 200 if summary exists; 404 if not
  - `resultText` is the full timeline string
  - `resultLength === resultText.length`
- **curl:**
  ```bash
  curl -sk -o "${DAT_SANDBOX}/api-results/VA-10.json" -w '%{http_code}' \
    "${STARTER_PACK_URL}/api/videos/summary?bucket=${VSS_BUCKET_NAME}&objectKey=${VSS_OBJECT_KEY}"
  ```

### VA-11: Create/Update Summary (P1 regression)

- **Endpoint:** `POST /api/videos/summary`
- **Request:** `{ "bucketName": "${VSS_BUCKET_NAME}", "objectKey": "test-upsert.mp4", "resultText": "0.0:5.0 | Categories: Test | Event: test event", "resultLength": 50 }`
- **Verification:**
  - HTTP 200, returns `videoId` and `summaryId`
  - Upsert: same bucket+objectKey → updates existing record (same videoId)
- **curl:**
  ```bash
  curl -sk -X POST -H 'Content-Type: application/json' \
    -d '{"bucketName":"'"${VSS_BUCKET_NAME}"'","objectKey":"test-upsert.mp4","resultText":"0.0:5.0 | Categories: Test | Event: test event","resultLength":50}' \
    -o "${DAT_SANDBOX}/api-results/VA-11.json" -w '%{http_code}' \
    "${STARTER_PACK_URL}/api/videos/summary"
  ```
- **Output:** Save `summaryId` for VA-12 cleanup.

### VA-6: List Jobs (P1 smoke)

- **Endpoint:** `GET /api/jobs`
- **Verification:**
  - HTTP 200, returns array
  - Each job has `id`, `status` (PENDING/PROCESSING/COMPLETED/FAILED), `bucketName`, `objectKey`, `createdAt`
  - Empty array is valid (no jobs yet)
- **curl:**
  ```bash
  curl -sk -o "${DAT_SANDBOX}/api-results/VA-6.json" -w '%{http_code}' \
    "${STARTER_PACK_URL}/api/jobs"
  ```

### VA-7: Enqueue Jobs (P1 e2e)

- **Endpoint:** `POST /api/jobs`
- **Request:** `{ "bucketName": "${VSS_BUCKET_NAME}", "objectKeys": ["${VSS_OBJECT_KEY}"] }`
- **Verification:**
  - HTTP 200, `jobs` array with one entry per objectKey
  - Each entry has `status: "PENDING"`
- **curl:**
  ```bash
  curl -sk -X POST -H 'Content-Type: application/json' \
    -d '{"bucketName":"'"${VSS_BUCKET_NAME}"'","objectKeys":["'"${VSS_OBJECT_KEY}"'"]}' \
    -o "${DAT_SANDBOX}/api-results/VA-7.json" -w '%{http_code}' \
    "${STARTER_PACK_URL}/api/jobs"
  ```

### VA-8: Process Next Job (P1 e2e, 35min timeout)

- **Endpoint:** `POST /api/jobs/process-next`
- **Request:** None
- **Verification:**
  - HTTP 200
  - `processed: true` means a job was picked up; `false` means no pending jobs
  - When `processed: true`: `jobId` and `status` present
- **CRITICAL:** This triggers summarization — takes 10-30 minutes. Do NOT timeout early.
- **curl:**
  ```bash
  curl -sk -X POST --max-time 2100 \
    -o "${DAT_SANDBOX}/api-results/VA-8.json" -w '%{http_code}' \
    "${STARTER_PACK_URL}/api/jobs/process-next"
  ```

### VA-13: Get Row Reviews (P1 smoke)

- **Endpoint:** `GET /api/videos/summary/${SUMMARY_ID}/reviews`
- **Verification:**
  - HTTP 200
  - `rowEdits` and `rowReviews` are both objects (can be empty `{}`)
- **Note:** Use a `summaryId` from VA-9a.
- **curl:**
  ```bash
  curl -sk -o "${DAT_SANDBOX}/api-results/VA-13.json" -w '%{http_code}' \
    "${STARTER_PACK_URL}/api/videos/summary/${SUMMARY_ID}/reviews"
  ```

### VA-14: Update Row Reviews (P1 regression)

- **Endpoint:** `PUT /api/videos/summary/${SUMMARY_ID}/reviews`
- **Request:**
  ```json
  {
    "rowEdits": { "0": { "event": "Test edit", "categories": ["Violence"], "comment": "Test comment" } },
    "rowReviews": { "0": "approved" }
  }
  ```
- **Verification:**
  - HTTP 200, `{ ok: true }`
  - Subsequent GET (VA-13) returns the same `rowEdits` and `rowReviews` that were PUT
- **curl:**
  ```bash
  curl -sk -X PUT -H 'Content-Type: application/json' \
    -d '{"rowEdits":{"0":{"event":"Test edit","categories":["Violence"],"comment":"Test comment"}},"rowReviews":{"0":"approved"}}' \
    -o "${DAT_SANDBOX}/api-results/VA-14.json" -w '%{http_code}' \
    "${STARTER_PACK_URL}/api/videos/summary/${SUMMARY_ID}/reviews"
  ```

### VA-12: Delete Summary (P1 regression) — DESTRUCTIVE, RUN LAST

- **Endpoint:** `DELETE /api/videos/summary/${SUMMARY_ID}`
- **Verification:**
  - HTTP 200, `{ ok: true }`
  - After delete: GET `/api/videos/summary?bucket=...&objectKey=...` returns 404
  - Row reviews for that summaryId are also deleted (cascade)
- **Note:** Use the `summaryId` from VA-11 (test-upsert.mp4) to avoid deleting real summaries needed by UI tests.
- **curl:**
  ```bash
  curl -sk -X DELETE \
    -o "${DAT_SANDBOX}/api-results/VA-12.json" -w '%{http_code}' \
    "${STARTER_PACK_URL}/api/videos/summary/${UPSERT_SUMMARY_ID}"
  ```

---

## Database Schema Reference

For debugging VA-9 through VA-14 failures:

- **Video:** `id`, `bucketName`, `objectKey` (unique together), `summary?`
- **Summary:** `id`, `videoId` (unique), `resultText`, `resultLength`, `rowReviews[]`
- **RowReview:** `id`, `summaryId`, `rowIndex` (unique together), `status?` ("approved"/"rejected"), `event?`, `categories[]`, `comment?`, `startSec?`, `endSec?`
- **SummarizationJob:** `id`, `status` (PENDING/PROCESSING/COMPLETED/FAILED), `bucketName`, `objectKey`, `fileId?`, `summaryId?`, `error?`, `params?`
