#!/usr/bin/env python3
"""
test_agent.py — connect a traced agent to the Agent Observability pack.

What it does:
  1. Talks to the pack's LlamaStack OpenAI-compatible gateway (which fronts the
     OCI Generative AI Dedicated AI Cluster / DAC model).
  2. Auto-discovers the DAC model in /v1/models (the one backed by a
     `generativeaiendpoint` OCID), or uses $MODEL if you set it.
  3. Wraps the OpenAI client with Langfuse so every call is captured as a trace,
     and runs a tiny 2-step "agent" (@observe) so you see a span tree in Langfuse.

Prerequisites:
  pip install "langfuse>=3.0.0" "openai>=1.40.0" httpx

  Then set these environment variables (see the companion connect-an-agent.md
  for exactly where each value comes from):

    export LLAMASTACK_BASE_URL="https://llamastack.<your-fqdn>/v1"
    export LANGFUSE_HOST="https://langfuse.<your-fqdn>"
    export LANGFUSE_PUBLIC_KEY="pk-lf-..."     # Langfuse UI -> Settings -> API Keys
    export LANGFUSE_SECRET_KEY="sk-lf-..."
    # optional:
    # export MODEL="Qwen3-6-35B-A3B-endpoint-xxxxxx"   # else auto-discovered
    # export LLAMASTACK_INSECURE=1                       # skip TLS verify (e.g. cert still issuing)

Run:
  python3 test_agent.py
"""

import os
import sys
import httpx

try:
    # Langfuse's drop-in OpenAI wrapper: identical API to `openai`, auto-traced.
    from langfuse.openai import OpenAI
    from langfuse import get_client, observe
except ImportError:
    sys.exit("Missing deps. Run: pip install 'langfuse>=3.0.0' 'openai>=1.40.0' httpx")

BASE_URL = os.environ.get("LLAMASTACK_BASE_URL", "").rstrip("/")
if not BASE_URL:
    sys.exit("Set LLAMASTACK_BASE_URL, e.g. https://llamastack.<your-fqdn>/v1")

VERIFY_TLS = os.environ.get("LLAMASTACK_INSECURE", "") not in ("1", "true", "yes")
http_client = httpx.Client(verify=VERIFY_TLS, timeout=120)


def discover_dac_model(base_url: str) -> str:
    """Return the LlamaStack model id backed by a dedicated GenAI endpoint (the DAC)."""
    resp = httpx.get(f"{base_url}/models", verify=VERIFY_TLS, timeout=30)
    resp.raise_for_status()
    for m in resp.json().get("data", []):
        prid = (m.get("custom_metadata") or {}).get("provider_resource_id", "")
        if "generativeaiendpoint" in prid:
            return m["id"]
    sys.exit(
        "No dedicated-endpoint (DAC) model found in /v1/models. "
        "Is the pack in GenAI 'create' mode (or pointed at an endpoint), and is the endpoint ACTIVE?"
    )


MODEL = os.environ.get("MODEL") or discover_dac_model(BASE_URL)
print(f"DAC model: {MODEL}")

# LlamaStack doesn't require a client API key (it auths to OCI via instance principal),
# but the OpenAI SDK needs a non-empty string.
client = OpenAI(base_url=BASE_URL, api_key="not-needed", http_client=http_client)


def ask(prompt: str, system: str = "You are a concise enterprise assistant.") -> str:
    # IMPORTANT: Qwen3.6-35B-A3B is a *reasoning* model. Do NOT set a small
    # max_tokens / max_completion_tokens — it truncates mid-reasoning and the DAC
    # returns HTTP 500. Omit the cap, or set it generously (e.g. 4096+).
    resp = client.chat.completions.create(
        model=MODEL,
        messages=[
            {"role": "system", "content": system},
            {"role": "user", "content": prompt},
        ],
        name="agent-observability-call",  # Langfuse generation name
    )
    return resp.choices[0].message.content


@observe(name="research-then-summarize-agent")
def run_agent(topic: str) -> str:
    """A tiny 2-step agent — both LLM calls nest under one Langfuse trace."""
    facts = ask(f"List 3 concise factual bullet points about: {topic}")
    summary = ask(
        f"Summarize the following into one board-ready sentence:\n\n{facts}",
        system="You translate notes into a single crisp sentence.",
    )
    return summary


if __name__ == "__main__":
    topic = " ".join(sys.argv[1:]) or "LLM/agent observability with Langfuse"
    print(f"\nRunning agent on: {topic!r}\n")
    answer = run_agent(topic)
    print("Agent answer:\n", answer)

    # Flush so the trace is delivered before the process exits.
    get_client().flush()
    print(
        f"\n✅ Trace sent. Open {os.environ.get('LANGFUSE_HOST', '<LANGFUSE_HOST>')} "
        "→ Tracing → Traces to see 'research-then-summarize-agent' with its two nested LLM calls."
    )
