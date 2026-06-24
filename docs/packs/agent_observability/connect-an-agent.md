# Connect an Agent (DAC model via LlamaStack → traced in Langfuse)

This guide shows how to point an agent at the **Dedicated AI Cluster (DAC) model**
served through the pack's **LlamaStack** OpenAI-compatible gateway, with every call
captured as a **trace in the Langfuse dashboard**. A runnable local script —
[`test_agent.py`](./test_agent.py) — is included.

```
  your laptop                         OKE cluster                         OCI Generative AI
 ┌───────────┐   OpenAI API     ┌──────────────────┐   remote::oci    ┌────────────────────┐
 │ test_agent│ ───────────────▶ │  LlamaStack      │ ───────────────▶ │ DAC endpoint        │
 │  .py      │  /v1/chat/...    │  (OpenAI-compat) │                  │ Qwen3.6-35B-A3B     │
 └─────┬─────┘                  └──────────────────┘                  └────────────────────┘
       │ Langfuse SDK (auto-trace)
       ▼
 ┌───────────────────────┐
 │ Langfuse dashboard     │   traces, generations, latency, tokens, cost
 └───────────────────────┘
```

The agent talks plain OpenAI to LlamaStack; LlamaStack routes to the OCI GenAI dedicated
endpoint via its `remote::oci` provider; the Langfuse SDK wraps the OpenAI client so each
call is recorded. Tracing happens **client-side** (in your agent), so any framework that
emits to Langfuse works — the script uses the Langfuse OpenAI drop-in for zero-config tracing.

## 1. Gather the four values you need

| Value | Where to get it |
|---|---|
| `LLAMASTACK_BASE_URL` | The LlamaStack ingress, **with `/v1`**: `https://llamastack.<fqdn>/v1`. The `<fqdn>` is the host part of the stack's `starter_pack_url` output (e.g. if `starter_pack_url = langfuse.10-0-0-1.nip.io`, use `https://llamastack.10-0-0-1.nip.io/v1`). |
| `LANGFUSE_HOST` | `https://` + the stack's **`starter_pack_url`** output (the Langfuse UI URL). |
| `LANGFUSE_PUBLIC_KEY` | In the Langfuse UI: **Settings → API Keys → Create new API key** → copy the public key (`pk-lf-…`). |
| `LANGFUSE_SECRET_KEY` | Same dialog → secret key (`sk-lf-…`). Shown once. |

> The pack bootstraps an `Agent Observability` project and an admin user (the Administrator
> email/password you set at deploy). Log in, open that project, and create an API key pair.

Confirm the DAC model is being served (it should be backed by a `generativeaiendpoint` OCID):

```bash
curl -sk "$LLAMASTACK_BASE_URL/models" \
  | jq '.data[] | select(.custom_metadata.provider_resource_id | test("generativeaiendpoint")) | {id, endpoint: .custom_metadata.provider_resource_id}'
# -> { "id": "Qwen3-6-35B-A3B-endpoint-xxxxxx", "endpoint": "ocid1.generativeaiendpoint...." }
```

A quick one-shot smoke test (no Langfuse yet) — note there is **no token cap** (see the gotcha below):

```bash
curl -sk -X POST "$LLAMASTACK_BASE_URL/chat/completions" \
  -H "Content-Type: application/json" \
  -d '{"model":"Qwen3-6-35B-A3B-endpoint-xxxxxx","messages":[{"role":"user","content":"Say hi in one sentence."}]}'
```

## 2. Install dependencies

```bash
pip install "langfuse>=3.0.0" "openai>=1.40.0" httpx
```

## 3. Set environment and run the agent

```bash
export LLAMASTACK_BASE_URL="https://llamastack.<fqdn>/v1"
export LANGFUSE_HOST="https://langfuse.<fqdn>"
export LANGFUSE_PUBLIC_KEY="pk-lf-..."
export LANGFUSE_SECRET_KEY="sk-lf-..."
# optional: export MODEL="Qwen3-6-35B-A3B-endpoint-xxxxxx"   # else auto-discovered
# optional: export LLAMASTACK_INSECURE=1                      # if the TLS cert is still issuing

python3 test_agent.py "renewable energy storage"
```

[`test_agent.py`](./test_agent.py) auto-discovers the DAC model, then runs a tiny two-step
agent (`research-then-summarize`) using the **Langfuse OpenAI drop-in** (`from langfuse.openai
import OpenAI`) so both LLM calls are traced automatically and nested under one trace
(`@observe`). It flushes Langfuse before exiting.

## 4. See the traces in Langfuse

Open `LANGFUSE_HOST` → **Tracing → Traces**. You'll see a trace named
`research-then-summarize-agent` containing two nested generations (the two model calls),
each with the input/output messages, the model id, latency, and token usage. Use the same
project's dashboards for aggregate latency/cost over time.

To instrument your **own** agent, the pattern is identical:

```python
from langfuse.openai import OpenAI            # drop-in for `openai`
from langfuse import observe

client = OpenAI(base_url=LLAMASTACK_BASE_URL, api_key="not-needed")

@observe(name="my-agent")                      # groups the calls into one trace
def my_agent(user_input: str) -> str:
    r = client.chat.completions.create(
        model="Qwen3-6-35B-A3B-endpoint-xxxxxx",
        messages=[{"role": "user", "content": user_input}],
    )
    return r.choices[0].message.content
```

Frameworks (CrewAI, LangChain, LlamaIndex, OpenAI Agents SDK, …) all have Langfuse
integrations — set the same `LANGFUSE_*` env vars and point the framework's LLM client at
`LLAMASTACK_BASE_URL`.

## Gotchas

- **Reasoning model — don't cap tokens low.** The default DAC model `Qwen/Qwen3.6-35B-A3B`
  is a *reasoning* model: a small `max_tokens` / `max_completion_tokens` truncates it
  mid-reasoning and the dedicated endpoint returns **HTTP 500**. Omit the cap, or set it
  generously (≥ ~4096). (`max_tokens` is also deprecated in favor of `max_completion_tokens`.)
- **OpenAI-compatible path is `/v1/chat/completions`.** `/v1/openai/v1/...` returns *Not Found*
  on this LlamaStack build.
- **Model id is dynamic.** It's derived from the GenAI endpoint's display name and includes
  the deploy id (e.g. `Qwen3-6-35B-A3B-endpoint-<hex>`), so discover it from `/v1/models`
  rather than hard-coding (the script does this).
- **No client API key needed for LlamaStack.** It authenticates to OCI GenAI via instance
  principal; the OpenAI SDK just needs a non-empty placeholder.
- **Catalog models too.** Besides the DAC model, `/v1/models` also lists OCI GenAI shared-catalog
  models (e.g. `oci/meta.llama-3.3-70b-instruct`) you can target the same way.
