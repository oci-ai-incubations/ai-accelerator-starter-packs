# Agent Observability — API Tests

10 tests executed via `curl`. Execute in order.

**MANDATORY:** Execute ALL tests. If a test fails, record the failure and continue.

**Setup env:**
```bash
STARTER_PACK_URL="https://langfuse.<fqdn>"      # starter_pack_url output
LLAMASTACK_URL="https://llamastack.<fqdn>"      # llamastack subdomain, no /v1
LANGFUSE_PUBLIC_KEY="pk-lf-..."                  # langfuse_project_public_key output
LANGFUSE_SECRET_KEY="sk-lf-..."                  # langfuse_project_secret_key output
```
All curls use `-sk` (LetsEncrypt IP cert may still be issuing early). The OpenAI-compat path is `/v1/chat/completions` (NOT `/v1/openai/v1/...`). LlamaStack needs no client API key.

---

## Execution Order

| # | ID | Test | P | Type |
|---|---|---|---|---|
| 1 | AOA-1 | Langfuse health OK | P0 | smoke |
| 2 | AOA-2 | LlamaStack lists models incl. DAC | P0 | smoke |
| 3 | AOA-3 | Chat completion vs DAC model (no token cap) | P0 | smoke |
| 4 | AOA-4 | Reasoning-model token-cap returns 500 | P2 | regression |
| 5 | AOA-5 | Chat completion vs catalog model | P1 | regression |
| 6 | AOA-6 | SSE streaming chat completion | P1 | regression |
| 7 | AOA-7 | Langfuse public API auth works | P0 | smoke |
| 8 | AOA-8 | Trace ingestion → trace readable | P0 | smoke |
| 9 | AOA-9 | Generations recorded with model/usage | P1 | regression |
| 10 | AOA-10 | Bucket receives event blobs | P2 | regression |

---

## Test Details

### AOA-1: Langfuse Health OK (P0 smoke)
```bash
curl -sk "$STARTER_PACK_URL/api/public/health"
```
- **Verify:** `{"status":"OK","version":"3...."}`. A health OK implies Langfuse reached Postgres + ClickHouse (migrations ran) + Redis.
- **Failure hint:** 502 → web still starting (wait); 500 → a backing service (DB/ClickHouse/Redis) connection is broken — check langfuse-web logs.

### AOA-2: LlamaStack Lists Models incl. DAC (P0 smoke)
```bash
curl -sk "$LLAMASTACK_URL/v1/models" \
 | jq '.data[] | select(.custom_metadata.provider_resource_id|test("generativeaiendpoint")) | .id'
```
- **Verify:** returns the DAC model id (e.g. `Qwen3-6-35B-A3B-endpoint-<hex>`). The full list also includes OCI catalog models (`oci/...`).
- **Capture:** save the DAC model id as `$MODEL` for AOA-3/4/6.
- **Failure hint:** empty → llamastack on wrong image (must be `pr-d74b10d`) or `OCI_COMPARTMENT_OCID` not the compartment hosting the endpoint.

### AOA-3: Chat Completion vs DAC Model — No Token Cap (P0 smoke)
```bash
curl -sk -X POST "$LLAMASTACK_URL/v1/chat/completions" -H "Content-Type: application/json" \
 -d "{\"model\":\"$MODEL\",\"messages\":[{\"role\":\"user\",\"content\":\"Say hi in one sentence.\"}]}"
```
- **Verify:** HTTP 200, `choices[0].message.content` non-empty (the DAC Qwen model; a `reasoning_content` field may also be present).
- **CRITICAL:** do NOT include a small `max_tokens`/`max_completion_tokens` (see AOA-4).

### AOA-4: Reasoning-Model Token Cap Returns 500 (P2 regression — documents the gotcha)
```bash
curl -sk -X POST "$LLAMASTACK_URL/v1/chat/completions" -H "Content-Type: application/json" \
 -d "{\"model\":\"$MODEL\",\"messages\":[{\"role\":\"user\",\"content\":\"Say hi.\"}],\"max_tokens\":50}"
```
- **Verify (expected, documented):** HTTP 500 `Internal Server Error` — the reasoning model truncates mid-reasoning under a small cap. This confirms the known behavior; agents must omit the cap or set it ≥ ~4096 (and use `max_completion_tokens`, not the deprecated `max_tokens`).

### AOA-5: Chat Completion vs Catalog Model (P1 regression)
```bash
curl -sk -X POST "$LLAMASTACK_URL/v1/chat/completions" -H "Content-Type: application/json" \
 -d '{"model":"oci/meta.llama-3.3-70b-instruct","messages":[{"role":"user","content":"Say hi."}]}'
```
- **Verify:** HTTP 200 with content. Isolates LlamaStack/OCI-catalog health from the DAC model.

### AOA-6: SSE Streaming Chat Completion (P1 regression)
```bash
curl -sk -N -X POST "$LLAMASTACK_URL/v1/chat/completions" -H "Content-Type: application/json" \
 -d "{\"model\":\"$MODEL\",\"messages\":[{\"role\":\"user\",\"content\":\"Count to 3.\"}],\"stream\":true}"
```
- **Verify:** a stream of `data: {...}` chunks ending with `data: [DONE]`.

### AOA-7: Langfuse Public API Auth Works (P0 smoke)
```bash
curl -sk -u "$LANGFUSE_PUBLIC_KEY:$LANGFUSE_SECRET_KEY" "$STARTER_PACK_URL/api/public/projects"
```
- **Verify:** HTTP 200 JSON listing the `Agent Observability` project. Confirms the **auto-provisioned** API key pair is valid (the key-autogeneration feature).
- **Failure hint:** 401 → keys wrong, or Langfuse didn't init the project key (check langfuse-web env `LANGFUSE_INIT_PROJECT_PUBLIC_KEY` + the secret).

### AOA-8: Trace Ingestion → Readable (P0 smoke)
- Emit a trace, then read it back. Easiest is the bundled script:
  ```bash
  LANGFUSE_HOST="$STARTER_PACK_URL" python3 docs/packs/agent_observability/test_agent.py "api smoke"
  ```
  (or POST to `/api/public/ingestion` directly). Then:
  ```bash
  curl -sk -u "$LANGFUSE_PUBLIC_KEY:$LANGFUSE_SECRET_KEY" "$STARTER_PACK_URL/api/public/traces?limit=5" | jq '.data[].name'
  ```
- **Verify:** the emitted trace (e.g. `research-then-summarize-agent`) appears. Proves the full ingestion → worker → ClickHouse → query path.
- **Failure hint:** trace never appears → check langfuse-worker logs (ClickHouse/Redis) and that the worker pod is Running.

### AOA-9: Generations Recorded with Model + Usage (P1 regression)
```bash
TID=$(curl -sk -u "$LANGFUSE_PUBLIC_KEY:$LANGFUSE_SECRET_KEY" "$STARTER_PACK_URL/api/public/traces?limit=1" | jq -r '.data[0].id')
curl -sk -u "$LANGFUSE_PUBLIC_KEY:$LANGFUSE_SECRET_KEY" "$STARTER_PACK_URL/api/public/observations?traceId=$TID" \
 | jq '.data[] | {type, model, usage: .usageDetails}'
```
- **Verify:** at least one observation of type `GENERATION` with a non-null `model` and token usage. Confirms the DAC call was captured with metadata.

### AOA-10: Bucket Receives Event Blobs (P2 regression)
- After AOA-8, list the bucket:
  ```bash
  oci os object list -bn agent-obs-<hex>-bucket -ns <namespace> --prefix events/ --query 'length(data)'
  ```
- **Verify:** `> 0` — Langfuse persisted event blobs to OCI Object Storage (S3-compat) for the trace. Confirms the S3 integration + customer-secret-key creds work.
