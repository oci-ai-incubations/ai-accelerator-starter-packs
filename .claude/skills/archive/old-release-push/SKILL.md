---
name: release-push
description: Post-release validation and publishing — validates zip files for sensitive data, renames to display names, generates Slack announcement, merges release PR, and tags the release. Run after /release-upgrade completes (e.g., /release-push v0.0.4).
user-invocable: true
allowed-tools: Bash, Read, Grep, Glob, Edit, Write, TaskCreate, TaskUpdate, TaskGet, TaskList, AskUserQuestion
argument-hint: [version]
---

# Release Push

Validate, rename, announce, and publish a release after `/release-upgrade` has completed.

## Arguments

- `$0` — Version in semver format (e.g., `v0.0.4`). If not provided, read from `ai-accelerator-tf/AI_ACCELERATOR_STACK_VERSION`.

## Prerequisites

1. Confirm `/release-upgrade` has already been run — check that a "Release \<VERSION\>" commit exists on the current branch, and the necessary files are present to build the slack post
2. Confirm **zip files have been tested** — this skill should only be run after the release test matrix has been executed and all packs have passed testing
3. Confirm zip files exist in `release_test_matrix/` or have them tell you where they are
4. Read the version from `AI_ACCELERATOR_STACK_VERSION` if not provided as argument

## Step 1: Validate Zip Files

For each zip in `release_test_matrix/`:

1. Create a temp directory for inspection
2. Unzip each file into the temp directory
3. Scan for **prohibited content** — fail immediately if any are found:
   - `.terraform/` directories
   - `.terraform.lock.hcl` files
   - `*.tfvars` files (`terraform.tfvars`, `*.auto.tfvars`)
   - `.env` files
   - `__pycache__/` directories
   - `.git/` directories
   - Private keys (`*.pem`, `*.key`, `id_rsa*`)
   - Files containing secrets patterns: API keys, passwords in plaintext, `BEGIN.*PRIVATE KEY`, hardcoded credentials
4. Report exactly what was found and **STOP** if issues exist — do not proceed
5. Clean up temp directory after inspection

## Step 2: Create Release Directory and Rename Zips

1. Compute the release directory number from the version — strip `v` prefix and dots: `v0.0.4` → `004`
2. Create `release-<NUMBER>/` at the repo root (e.g., `release-004/`)
3. Copy and rename each zip using the display-name mapping:

| Category             | Source zip name                    | Target zip name                     |
| -------------------- | ---------------------------------- | ----------------------------------- |
| `enterprise_rag`     | `<version>_enterprise_rag.zip`     | `aiQEnterpriseSearch.zip`           |
| `enterprise_rag_aiq` | `<version>_enterprise_rag_aiq.zip` | `enterpriseAgenticAIStarterKit.zip` |
| `paas_rag`           | `<version>_paas_rag.zip`           | `aiQGenAIPowered.zip`               |
| `cuopt`              | `<version>_cuopt.zip`              | `vehicleRouteOptimizer.zip`         |
| `vss`                | `<version>_vss.zip`                | `videoSearchSummarization.zip`      |

4. Verify all expected zips are present and non-empty in the release directory
5. List the final contents with file sizes for the user to confirm

## Step 3: Generate Slack Announcement

### Gather Changes

**Critical: only announce what is NEW since the last announced release.** Features announced in a prior version's Slack post must not be re-announced.

1. **Ask the user for the release task list.** This is the **primary source of truth** for what to announce — not git commits alone. Many features land on main across multiple release cycles, and commit history alone cannot determine what the team considers to be this release's content. Ask for:
   - The task/feature list for this release (titles, categories, owners)
   - The previous release's Slack announcement text (to avoid re-announcing)

2. **Cross-reference tasks against the previous announcement.** Remove any item that was already covered in the prior Slack post.

3. **Verify each remaining task against the actual code diff** to understand the technical details and write accurate descriptions:
   ```bash
   git diff <last_release_merge_commit>..HEAD --stat -- ai-accelerator-tf/
   ```
   Inspect key files (`blueprint_files.tf`, `vars.tf`, `app-*.tf`, `helm-values/`, `schemas/`) for each task's code changes.

4. **Look at merged PR descriptions** for additional context (if `gh` CLI is available):
   ```bash
   gh pr list --state merged --base main --limit 50 --json title,body,mergedAt
   ```

5. Group changes by starter pack category, matching the task list's category assignments.

### Format the Message

Use this exact Slack format with Slack mrkdwn emoji shortcodes:

```
:rocket: OCI AI Accelerator Packs — <VERSION> is live!

Here's what's new in the latest release:

:package: <Pack Display Name>
• Change description 1
• Change description 2

:package: <Next Pack Display Name>
• Change description 1

:book: Documentation
• Documentation changes if any

Questions or feedback? Ask away, we want to know how to improve these for your use cases!
```

**Display names for the Slack message:**

| Category             | Slack Display Name                                    |
| -------------------- | ----------------------------------------------------- |
| `paas_rag`           | AI.Q: GenAI PaaS RAG                                  |
| `enterprise_rag`     | AI.Q: Enterprise AI Search Agent                      |
| `enterprise_rag_aiq` | Enterprise Agentic AI Starter Kit                     |
| `cuopt`              | Delivery Vehicle Route Optimizer                      |
| `vss`                | Video Search and Summarization for Content Moderation |

### Review

- Present the generated Slack message to the user
- Ask them to review, edit, and confirm
- The user will **manually copy and post** the message in Slack

## Step 4: Merge Release PR and Tag

Only proceed after the user confirms the Slack message has been posted.

1. **Find the open release PR:**

   ```bash
   gh pr list --head release_v<VERSION> --state open --json number,title,url
   ```

   If no PR exists, ask the user to create one first.

2. **Merge the PR:**

   ```bash
   gh pr merge <PR_NUMBER> --merge
   ```

3. **Pull main and tag:**

   ```bash
   git checkout main
   git pull origin main --ff-only
   git tag release_v<VERSION>
   # Use full ref to avoid ambiguity with the branch of the same name
   git push origin refs/tags/release_v<VERSION>
   ```

4. **Verify:**

   ```bash
   git tag --list 'release_v*' --sort=-version:refname | head -5
   gh release view release_v<VERSION> 2>/dev/null || echo "Tag pushed (no GitHub Release created)"
   ```

5. Report success with the tag URL.

## Step 5: Celebrate

Display this ASCII art to celebrate the release:

```
    *       *       *       *       *
  * * *   * * *   * * *   * * *   * * *
    *       *       *       *       *

  =============================================
  |                                           |
  |    RELEASE <VERSION> SHIPPED!             |
  |                                           |
  |    PR merged, tag pushed, Slack posted.   |
  |    Go grab a coffee, you earned it.       |
  |                                           |
  =============================================

    *       *       *       *       *
  * * *   * * *   * * *   * * *   * * *
    *       *       *       *       *
```

## Error Handling

- If zip validation finds prohibited content → stop and show exactly what was found, with file paths
- If the release PR doesn't exist → ask the user to create one
- If PR merge fails (conflicts, failing checks) → report the error and ask for guidance
- If tagging fails → report the error; never force-push
- Never force-merge or bypass required checks
