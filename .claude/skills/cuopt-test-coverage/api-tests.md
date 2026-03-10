# cuOpt API Tests

7 tests executed via `curl` against `${STARTER_PACK_URL}`. Execute in order — some tests depend on prior results.

**MANDATORY:** Execute ALL tests in order by ascending ID. If a test fails, record the failure and continue. Do NOT skip any test.

**No authentication required.** The cuOpt frontend has no login.

---

## Execution Order

| # | ID | Test | Method | Endpoint | P | Type | Timeout | Preconditions |
|---|---|---|---|---|---|---|---|---|
| 1 | CA-1 | LLM models list | GET | `/v1/models` | P0 | smoke | 30s | LlamaStack pod Running |
| 2 | CA-2 | cuOpt health readiness | GET | `/cuopt/v2/health/ready` | P0 | smoke | 30s | cuOpt pod Running |
| 3 | CA-3 | cuOpt health liveness | GET | `/cuopt/v2/health/live` | P1 | smoke | 30s | cuOpt pod Running |
| 4 | CA-4 | Submit optimization problem | POST | `/cuopt/request` | P0 | e2e | 30s | cuOpt pod Running |
| 5 | CA-5 | Poll solution | GET | `/cuopt/solution/{reqId}` | P0 | e2e | 5min | CA-4 succeeded |
| 6 | CA-6 | LLM chat completions | POST | `/v1/chat/completions` | P0 | e2e | 60s | CA-1 returned models |
| 7 | CA-7 | LLM chat with function calling | POST | `/v1/chat/completions` | P1 | e2e | 60s | CA-1 returned models |

---

## Test Details

### CA-1: LLM Models List (P0 smoke)

- **Endpoint:** `GET /v1/models`
- **Request:** None
- **Verification:**
  - HTTP 200
  - Response has `data` array with >=1 model object
  - Each model has `id` field (string)
- **Output:** Save first model `id` for CA-6 and CA-7.
- **curl:**
  ```bash
  curl -sk -o "${DAT_SANDBOX}/api-results/CA-1.json" -w '%{http_code}' \
    "${STARTER_PACK_URL}/v1/models"
  ```

### CA-2: cuOpt Health Readiness (P0 smoke)

- **Endpoint:** `GET /cuopt/v2/health/ready`
- **Request:** None
- **Verification:**
  - HTTP 200
  - Response indicates solver is ready (may be empty body or JSON with status)
- **Note:** This is the cuOpt solver's readiness endpoint, proxied through ingress at `/cuopt/`.
- **curl:**
  ```bash
  curl -sk -o "${DAT_SANDBOX}/api-results/CA-2.json" -w '%{http_code}' \
    "${STARTER_PACK_URL}/cuopt/v2/health/ready"
  ```

### CA-3: cuOpt Health Liveness (P1 smoke)

- **Endpoint:** `GET /cuopt/v2/health/live`
- **Request:** None
- **Verification:**
  - HTTP 200
  - Process is alive (does not guarantee models are loaded)
- **curl:**
  ```bash
  curl -sk -o "${DAT_SANDBOX}/api-results/CA-3.json" -w '%{http_code}' \
    "${STARTER_PACK_URL}/cuopt/v2/health/live"
  ```

### CA-4: Submit Optimization Problem (P0 e2e)

- **Endpoint:** `POST /cuopt/request`
- **Request:** A minimal cuOpt problem with 1 depot, 3 deliveries, 1 vehicle:
  ```json
  {
    "cost_matrix_data": {
      "data": {
        "1": [[0,1,2,3],[1,0,1,2],[2,1,0,1],[3,2,1,0]]
      }
    },
    "travel_time_matrix_data": {
      "data": {
        "1": [[0,10,20,30],[10,0,10,20],[20,10,0,10],[30,20,10,0]]
      }
    },
    "fleet_data": {
      "vehicle_locations": [[0,0]],
      "vehicle_ids": ["Car-1"],
      "vehicle_types": [1],
      "capacities": [[50]],
      "vehicle_time_windows": [[0, 480]],
      "vehicle_break_time_windows": null,
      "vehicle_break_durations": null,
      "vehicle_order_match": [],
      "skip_first_trips": [false],
      "drop_return_trips": [false],
      "vehicle_max_costs": [2000],
      "vehicle_max_times": [480],
      "min_vehicles": 1
    },
    "task_data": {
      "task_locations": [1, 2, 3],
      "demand": [[8, 10, 7]],
      "task_time_windows": [[0, 120], [60, 240], [120, 360]],
      "service_times": [3, 4, 3],
      "prizes": [15, 20, 18],
      "order_vehicle_match": []
    },
    "solver_config": {
      "time_limit": 5
    }
  }
  ```
- **Verification:**
  - HTTP 200
  - Response contains `reqId` (string, UUID format)
- **Output:** Save `reqId` for CA-5.
- **curl:**
  ```bash
  curl -sk -X POST -H 'Content-Type: application/json' \
    -d '{"cost_matrix_data":{"data":{"1":[[0,1,2,3],[1,0,1,2],[2,1,0,1],[3,2,1,0]]}},"travel_time_matrix_data":{"data":{"1":[[0,10,20,30],[10,0,10,20],[20,10,0,10],[30,20,10,0]]}},"fleet_data":{"vehicle_locations":[[0,0]],"vehicle_ids":["Car-1"],"vehicle_types":[1],"capacities":[[50]],"vehicle_time_windows":[[0,480]],"vehicle_break_time_windows":null,"vehicle_break_durations":null,"vehicle_order_match":[],"skip_first_trips":[false],"drop_return_trips":[false],"vehicle_max_costs":[2000],"vehicle_max_times":[480],"min_vehicles":1},"task_data":{"task_locations":[1,2,3],"demand":[[8,10,7]],"task_time_windows":[[0,120],[60,240],[120,360]],"service_times":[3,4,3],"prizes":[15,20,18],"order_vehicle_match":[]},"solver_config":{"time_limit":5}}' \
    -o "${DAT_SANDBOX}/api-results/CA-4.json" -w '%{http_code}' \
    "${STARTER_PACK_URL}/cuopt/request"
  ```

### CA-5: Poll Solution (P0 e2e, 5min timeout)

- **Endpoint:** `GET /cuopt/solution/${REQ_ID}`
- **Request:** None (use `reqId` from CA-4)
- **Verification:**
  - HTTP 200
  - Response contains `response.solver_response`
  - `solver_response` has `num_vehicles` (number >= 1)
  - `solver_response` has `vehicle_data` (object with vehicle route details)
  - Each vehicle route has `route` (array of node indices), `arrival_stamp` (array of times), `task_id` (array of stop IDs)
  - `solver_response` has `dropped_tasks` object
  - `response.total_solve_time` is a number
- **Polling:** If first request returns no solution yet, retry every 2 seconds up to 150 times (5 min).
- **curl:**
  ```bash
  # Poll until solution is ready
  for i in $(seq 1 150); do
    HTTP_CODE=$(curl -sk -o "${DAT_SANDBOX}/api-results/CA-5.json" -w '%{http_code}' \
      "${STARTER_PACK_URL}/cuopt/solution/${REQ_ID}")
    if [ "$HTTP_CODE" = "200" ]; then
      # Check if solution is present
      if python3 -c "import json; d=json.load(open('${DAT_SANDBOX}/api-results/CA-5.json')); assert 'response' in d and 'solver_response' in d['response']" 2>/dev/null; then
        echo "Solution received after $i attempts"
        break
      fi
    fi
    sleep 2
  done
  ```

### CA-6: LLM Chat Completions (P0 e2e)

- **Endpoint:** `POST /v1/chat/completions`
- **Request:**
  ```json
  {
    "model": "<model-id-from-CA-1>",
    "messages": [
      { "role": "system", "content": "You are a helpful assistant for vehicle routing optimization." },
      { "role": "user", "content": "What is NVIDIA cuOpt and how does it help with vehicle routing?" }
    ]
  }
  ```
- **Verification:**
  - HTTP 200
  - Response has `choices` array with >=1 entry
  - `choices[0].message.content` is a non-empty string
  - `choices[0].message.role` is `"assistant"`
- **curl:**
  ```bash
  MODEL_ID=$(python3 -c "import json; print(json.load(open('${DAT_SANDBOX}/api-results/CA-1.json'))['data'][0]['id'])")
  curl -sk -X POST -H 'Content-Type: application/json' \
    -d '{"model":"'"${MODEL_ID}"'","messages":[{"role":"system","content":"You are a helpful assistant for vehicle routing optimization."},{"role":"user","content":"What is NVIDIA cuOpt and how does it help with vehicle routing?"}]}' \
    -o "${DAT_SANDBOX}/api-results/CA-6.json" -w '%{http_code}' \
    "${STARTER_PACK_URL}/v1/chat/completions"
  ```

### CA-7: LLM Chat with Function Calling (P1 e2e)

- **Endpoint:** `POST /v1/chat/completions`
- **Request:** Chat message with tool definitions asking to add a vehicle:
  ```json
  {
    "model": "<model-id-from-CA-1>",
    "messages": [
      { "role": "system", "content": "You are a cuOpt assistant. Use the provided tools to modify vehicle routing problems." },
      { "role": "user", "content": "Add a truck to the fleet" }
    ],
    "tools": [
      {
        "type": "function",
        "function": {
          "name": "add_truck",
          "description": "Add a truck with capacity 50 and type 2 to the fleet",
          "parameters": { "type": "object", "properties": {}, "required": [] }
        }
      }
    ],
    "tool_choice": "auto"
  }
  ```
- **Verification:**
  - HTTP 200 (if function calling supported)
  - Response has `choices[0].message.tool_calls` array with >=1 entry, OR
  - Response has `choices[0].message.content` with natural language (fallback mode)
  - If tool_calls present: `tool_calls[0].function.name` should be `"add_truck"`
- **Note:** If the LLM returns 400 (doesn't support tools), record as "fallback mode OK" — the frontend handles this gracefully.
- **curl:**
  ```bash
  MODEL_ID=$(python3 -c "import json; print(json.load(open('${DAT_SANDBOX}/api-results/CA-1.json'))['data'][0]['id'])")
  curl -sk -X POST -H 'Content-Type: application/json' \
    -d '{"model":"'"${MODEL_ID}"'","messages":[{"role":"system","content":"You are a cuOpt assistant. Use the provided tools to modify vehicle routing problems."},{"role":"user","content":"Add a truck to the fleet"}],"tools":[{"type":"function","function":{"name":"add_truck","description":"Add a truck with capacity 50 and type 2 to the fleet","parameters":{"type":"object","properties":{},"required":[]}}}],"tool_choice":"auto"}' \
    -o "${DAT_SANDBOX}/api-results/CA-7.json" -w '%{http_code}' \
    "${STARTER_PACK_URL}/v1/chat/completions"
  ```
