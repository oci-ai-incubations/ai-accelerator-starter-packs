# Backend Ingress API Tokens

## What

An opt-in bearer-token gate on backend nginx ingresses. When enabled, requests to backend API hostnames (e.g. `cuopt-…nip.io`, `llamastack-…nip.io`) must include `Authorization: Bearer <token>`. Frontend UIs stay open.

Requests to the ingress controller trigger an internal `auth_request` subrequest to a small validator pod (`ingress-api-key-validator` in `cluster-tools`); 200 lets the real request through, 401 rejects it.

## How to deploy

1. On the ORM stack variables page, check **"Protect Backend Ingresses With API Key"**.
2. Leave **"Ingress API Key"** blank to auto-generate a 48-character token, or paste your own (minimum 32 chars).
3. Apply the stack.
4. After apply, the token appears in the ORM outputs panel under **"Ingress API Key"** (sensitive). A ready-to-paste curl example is in the same group.

Example call once deployed:

```bash
curl -H "Authorization: Bearer <token>" https://cuopt-<id>.<lb-ip>.nip.io/v2/health/live
```

## Where it works

- **Dedicated backend ingresses** created by each blueprint deployment — one per backend service (cuopt, llamastack, vss, elasticsearch, neo4j, riva, embedding, rerank, nim-llm). These are the hostnames external integrators should target.

## Where it does NOT work

- **Frontend UIs** (`demo-cuopt.*`, `paas_rag`'s frontend, grafana, prometheus, corrino portal, RAG frontends) — intentionally open so browsers can load them without a token.
- **Backend paths proxied through a frontend ingress.** Some frontends expose convenience paths like `/cuopt` or `/v1` on their own hostname (e.g. `demo-cuopt.*/v1/health`). Those paths are **unprotected** because the frontend ingress itself is unprotected. Use the dedicated backend hostname for token-gated access.
- **In-cluster ClusterIP traffic.** Pod-to-pod calls never traverse the ingress, so the token doesn't apply — which is why the frontend UIs still reach their backends internally.

## How to rotate the token

The token is baked into the validator's nginx config at plan time.

1. Update the `ingress_api_key` variable — either blank it (to force a new auto-generated value) or set a new value.
2. Run apply.
3. Terraform re-renders the ConfigMap, and the Deployment's `checksum/config` annotation changes — the validator pod rolls automatically. No blueprint redeploy needed; ingresses reference the validator by URL, not by key.

## How to turn the feature on or off on an existing stack

Blueprint ingress annotations are baked in at blueprint submission time. So **flipping `add_api_key_to_ingress` on or off requires redeploying affected blueprints** (the cuopt/llamastack/vss and related recipes). Rotation does not — only the initial on/off toggle.
