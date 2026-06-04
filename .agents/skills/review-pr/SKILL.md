---
name: review-pr
description: Review a GitHub PR — analyze impact on functionality and best practices, check affected frontend repos, then submit review after user approval.
user-invocable: true
allowed-tools: Bash, Read, Glob, Grep, Agent, AskUserQuestion, mcp__github__get_pull_request, mcp__github__get_pull_request_files, mcp__github__get_pull_request_comments, mcp__github__get_pull_request_reviews, mcp__github__get_pull_request_status, mcp__github__create_pull_request_review, mcp__github__list_pull_requests
argument-hint: "[PR number or URL]"
---

# GitHub PR Review Skill

Reviews a PR by analyzing what changed, how it affects existing functionality, whether it follows Terraform/OCI best practices, and whether pack-specific frontend repos would be impacted. Presents findings to the user, then submits a GitHub review after approval.

## Frontend Repos by Pack

| Pack | Frontend Repo |
|------|--------------|
| `vss` | `https://github.com/grantneumanoracle/vss-oracle-ux` |
| `cuopt` | `https://github.com/oci-ai-incubations/vehicle_route_optimizer_frontend` |
| `enterprise_rag` | `https://github.com/oci-ai-incubations/enterprise-rag-frontend` |
| `paas_rag` | `https://github.com/oci-ai-incubations/oraclenet-frontend` |
| `enterprise_rag_aiq` | (no frontend repo yet) |

## Step 0: Resolve PR

- If argument is a URL, extract owner, repo, and PR number.
- If argument is a number, detect owner/repo from `gh repo view --json owner,name`.
- If no argument, list open PRs and ask the user to pick one.

## Step 1: Gather PR Context

Run in parallel:

1. **`mcp__github__get_pull_request`** — title, description, author, base/head branches.
2. **`mcp__github__get_pull_request_files`** — changed files with patches.
3. **`mcp__github__get_pull_request_status`** — CI status.
4. **`mcp__github__get_pull_request_reviews`** — existing reviews (don't duplicate).
5. **`mcp__github__get_pull_request_comments`** — existing inline comments.

Checkout the PR branch locally so files can be read in full.

## Step 2: Analyze the Diff

For each changed file, read the full file and the diff. Focus on two things:

### 2a. Functionality Impact

- What existing behavior does this change affect?
- Could this break any current deployments or workflows?
- If blueprint payloads changed (`blueprint_files.tf`), what fields changed and what would that do to a running deployment? (Remember: deployments are immutable — changes require undeploy/redeploy.)
- If variables changed (`vars.tf`), do existing `terraform.tfvars` files still work? Are defaults backward-compatible?
- If network/security rules changed, could this lock out access or open unintended ports?
- If Helm values or app resources changed, what pods/services are affected?

### 2b. Best Practices

- **Terraform**: proper use of `locals`, `variables`, `outputs`. Validation blocks on new variables. No hardcoded secrets or OCIDs. Resources tagged and named consistently. `terraform fmt` clean.
- **OCI**: minimum IAM permissions (no `manage all-resources`). Proper compartment scoping. Security lists not overly permissive.
- **Kubernetes/Helm**: resource limits set, health checks present, secrets not in plaintext.
- **General**: no dead code, no commented-out blocks left in, clear naming, DRY where appropriate.

## Step 3: Determine Frontend Impact

First, determine if the changes could affect any frontend. Changes that could affect a frontend:
- Blueprint payload changes (`blueprint_files.tf`) — env vars, ports, service URLs passed to backend containers
- Ingress or routing changes (`helm.tf`, ingress resources) — hostnames, paths, TLS config
- App resource changes (`app-*.tf`) — service names, configmaps, API-facing resources
- Variable default changes (`vars.tf`) — deployment names, credentials, URLs that backends expose

Changes that do NOT affect frontends:
- Networking infrastructure (VCN, subnets, security lists, gateways)
- OKE cluster/node pool configuration
- Capacity checks, data sources
- Schema files, test files
- Helm charts for monitoring (prometheus, grafana, DCGM)

**If no frontend-affecting changes are detected, skip to Step 4.**

If frontend-affecting changes are detected:

1. Identify which pack(s) are affected from the diff context.
2. If that pack has a frontend repo (see table above), clone it to `/tmp/pr-review-<pack>`.
3. Search the frontend code for references to the affected endpoints, env vars, service names, or URLs.
4. Determine if the Terraform changes would break the frontend (e.g., renamed API path, changed port, removed env var).
5. Note specific findings with file references from both repos.

## Step 4: Present Summary to User

Present the review in two parts: (A) the analysis for the user, and (B) the GitHub review that will be posted.

### Part A — Analysis (shown to user only, not posted)

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
PR #<number>: <title>
Author: <author> | Branch: <head> → <base>
Files: <count> | CI: ✅ all passing / ❌ <failing checks>
Existing reviews: <summary of prior review decisions>
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

## What Changed
<2-3 sentence plain-English summary of the PR's purpose and scope>

## Functionality Impact

| Area | Impact | Risk |
|------|--------|------|
| <area> | <what changes> | 🔴 High / 🟡 Medium / 🟢 Low |

<detailed explanation of each impact>

## Best Practices

| Issue | File | Severity |
|-------|------|----------|
| <description> | `file:line` | 🔴 Blocking / 🟡 Suggestion / 🔵 Nit |

## Frontend Impact
- **Packs affected**: <list or "none">
- **Frontend checked**: <repo name or "N/A">
- **Result**: <impact details or "No impact — <reason>">

## Prior Review Issues (from existing reviews)
- <reviewer>: <summary of their feedback and current status>
```

### Part B — Proposed GitHub Review

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📋 PROPOSED GITHUB REVIEW
Decision: APPROVE / REQUEST_CHANGES / COMMENT
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

**Review body:**

## PR Review Summary

**Overall**: [APPROVE / REQUEST_CHANGES / COMMENT]

### What this PR does
<1-2 sentence summary>

### Blocking Issues
- [ ] <description> (`file:line`)

### Suggestions
- <description> (`file:line`)

### Strengths
- <what's well done>

### CI Status
<pass/fail>

---
*Reviewed by Codex*

**Inline comments (<count>):**
| File | Line | Comment |
|------|------|---------|
| `<path>` | <line> | <comment text> |
```

Then ask:

> **Submit this review to GitHub?**
> - **yes** — submit as shown
> - **approve / comment / request_changes** — change the decision
> - **edit** — tell me what to change
> - **no** — cancel

**Do NOT submit until the user explicitly approves.**

## Step 5: Submit Review

Try `mcp__github__create_pull_request_review` first. If MCP auth fails, fall back to the `gh` CLI:

```bash
gh api repos/<owner>/<repo>/pulls/<number>/reviews \
  -f event=<EVENT> \
  -f body="<review body>" \
  --jq '.html_url'
```

For inline comments, use:
```bash
gh api repos/<owner>/<repo>/pulls/<number>/comments \
  -f body="<comment>" \
  -f path="<file>" \
  -F line=<line> \
  -f commit_id="$(gh pr view <number> --json headRefOid --jq .headRefOid)"
```

## Step 6: Final Report

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✅ Review submitted
PR #<number>: <title>
Decision: APPROVED / CHANGES_REQUESTED / COMMENTED
Findings: <X blocking, Y suggestions, Z nits>
Frontend: <checked packs or "no impact">
Link: <review URL>
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

## Decision Rules

- **REQUEST_CHANGES**: breaking changes, security issues, hardcoded secrets, overly broad IAM.
- **APPROVE**: clean changes, CI passes, no functional risk.
- **COMMENT**: questions, suggestions, or uncertain impact.
- Never auto-submit. Always wait for user approval.
- Never duplicate issues already raised in existing reviews.
