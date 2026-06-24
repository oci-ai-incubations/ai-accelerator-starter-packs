# Agent Observability — UI Tests (Langfuse dashboard)

14 tests executed via **agent-browser** against the Langfuse web app. Execute in order, in **one** browser context with continuous video recording (see `.claude/rules/playwright.md`).

**MANDATORY:** Execute ALL tests. Wrap each in its own try/catch; on failure, record it, navigate fresh, and continue. **Interact** with elements (click, type, wait for result) — don't just assert presence.

**Setup env:**
```bash
STARTER_PACK_URL="https://langfuse.<fqdn>"   # starter_pack_url output
ADMIN_EMAIL="<corrino_admin_email>"
ADMIN_PASSWORD="<corrino_admin_password>"
# for the live-trace test (AOU-13):
LANGFUSE_PUBLIC_KEY / LANGFUSE_SECRET_KEY     # langfuse_project_* outputs
```
Langfuse signs in by **email**. Public sign-up is **disabled**. Dismiss any cookie/onboarding modal before proceeding.

---

## Execution Order

| # | ID | Test | P | Type |
|---|---|---|---|---|
| 1 | AOU-1 | Login page loads | P0 | smoke |
| 2 | AOU-2 | Public sign-up disabled | P1 | regression |
| 3 | AOU-3 | Admin login succeeds | P0 | smoke |
| 4 | AOU-4 | OIDC SSO button (conditional) | P2 | regression |
| 5 | AOU-5 | Land on "Agent Observability" project | P0 | smoke |
| 6 | AOU-6 | Tracing → Traces lists traces | P0 | smoke |
| 7 | AOU-7 | Open trace → nested observations | P0 | smoke |
| 8 | AOU-8 | Generation shows model + tokens + latency | P1 | regression |
| 9 | AOU-9 | Trace I/O messages render | P1 | regression |
| 10 | AOU-10 | Dashboards render with data | P1 | regression |
| 11 | AOU-11 | Sessions view | P2 | regression |
| 12 | AOU-12 | Prompts page loads | P2 | regression |
| 13 | AOU-13 | Settings → API Keys shows auto key | P1 | regression |
| 14 | AOU-14 | Live trace appears after agent run | P0 | e2e |

---

## Test Details

### AOU-1: Login Page Loads (P0 smoke)
- Navigate to `STARTER_PACK_URL`. Expect redirect to `/auth/sign-in` with email + password fields and a Sign in button. Verify TLS (no cert warning; if the LetsEncrypt IP cert is still issuing, wait and reload).

### AOU-2: Public Sign-up Disabled (P1 regression)
- On the sign-in page, look for a "Sign up" link; if present, click it → expect sign-up to be disabled (no self-registration) because `AUTH_DISABLE_SIGNUP=true`. Record whether a sign-up form is reachable (it should not create accounts).

### AOU-3: Admin Login Succeeds (P0 smoke)
- Enter `ADMIN_EMAIL` / `ADMIN_PASSWORD`, click Sign in. **Verify** redirect to the authenticated app (org/projects view) — URL leaves `/auth/sign-in` and the user avatar/menu appears. Dismiss any onboarding modal.
- **Failure hint:** if login fails, the bootstrap (`LANGFUSE_INIT_USER_*`) didn't run — check langfuse-web env + the `LANGFUSE_INIT_USER_PASSWORD` secret.

### AOU-4: OIDC SSO Button (P2 regression, conditional)
- Only if the stack was deployed with `agent_obs_oidc_issuer` set: on the sign-in page verify a "Sign in with <agent_obs_oidc_name>" (e.g. "Oracle SSO") button is present. (Don't complete the IdP round-trip unless creds are available.) If OIDC was not configured, mark **N/A**.

### AOU-5: Land on "Agent Observability" Project (P0 smoke)
- Navigate to the org → open the **Agent Observability** project (bootstrapped via `LANGFUSE_INIT_PROJECT_*`). Verify the project dashboard loads.

### AOU-6: Tracing → Traces Lists Traces (P0 smoke)
- Open **Tracing → Traces**. Verify the table renders. If traces exist (e.g. from API tests), at least one row is present; click a column header to sort and confirm the table reacts.

### AOU-7: Open Trace → Nested Observations (P0 smoke)
- Click a trace row (e.g. `research-then-summarize-agent`). **Verify** the trace detail opens with a span/observation tree containing nested **generation** entries (the LLM calls). Expand a generation.

### AOU-8: Generation Shows Model + Tokens + Latency (P1 regression)
- In the opened generation, verify it displays the model id (the DAC model, e.g. `Qwen3-6-35B-A3B-endpoint-*`), token usage, and latency. Confirms metadata captured end-to-end.

### AOU-9: Trace I/O Messages Render (P1 regression)
- In the generation/trace detail, verify the **input** (the user/system messages) and **output** (assistant content) are shown. Toggle any "formatted/JSON" view if present.

### AOU-10: Dashboards Render With Data (P1 regression)
- Open **Dashboards** (or the project home charts). Verify charts render (traces over time, latency, cost/tokens). With recent traffic, at least one chart shows non-zero data.

### AOU-11: Sessions View (P2 regression)
- Open **Tracing → Sessions** (or Users). Verify the view loads without error (may be empty if no `session_id` set).

### AOU-12: Prompts Page Loads (P2 regression)
- Open **Prompts**. Verify the prompt-management page loads and a "New prompt" action is available. (Optionally create + delete a throwaway prompt and confirm it persists/removes.)

### AOU-13: Settings → API Keys Shows Auto Key (P1 regression)
- Open **Settings → API Keys**. **Verify** an API key whose public key matches the `langfuse_project_public_key` output (`pk-lf-…`) is listed — i.e. the deploy-time auto-provisioned key exists. (Secret keys are not shown after creation.)

### AOU-14: Live Trace Appears After Agent Run (P0 e2e)
- In a terminal, run the bundled agent against the live stack:
  ```bash
  LLAMASTACK_BASE_URL="$STARTER_PACK_URL/.." ... python3 docs/packs/agent_observability/test_agent.py "ui e2e check"
  ```
  (set `LLAMASTACK_BASE_URL=https://llamastack.<fqdn>/v1`, `LANGFUSE_HOST=$STARTER_PACK_URL`, and the `LANGFUSE_*` keys).
- Then in the UI **Tracing → Traces**, refresh and **verify** a new `research-then-summarize-agent` trace appears within ~30s, with two nested DAC generations. This is the definitive agent→llamastack→DAC→Langfuse end-to-end check.
- **Failure hint:** call succeeds but no trace → worker/ClickHouse issue (see AOA-8) or wrong `LANGFUSE_HOST`/keys.
