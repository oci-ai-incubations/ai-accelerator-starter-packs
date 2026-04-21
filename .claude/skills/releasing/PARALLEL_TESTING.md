# Parallel Testing with Agent Teams

Detailed guide for setting up and running parallel test tracks using Claude Code agent teams.

## Prerequisites

Agent teams require the experimental flag:

```json
// ~/.claude/settings.json
{
  "env": {
    "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1"
  }
}
```

Restart Claude Code after adding this.

## Why Agent Teams (Not Background Subagents)

Background subagents (`Agent` tool with `run_in_background: true`) **cannot use `AskUserQuestion`** — the tool call silently auto-denies. This means they cannot:
- Prompt the user for OCI Console sign-in
- Ask for compartment selection
- Request any interactive input

Since `/testing-pack` requires browser authentication and user input, background subagents will fail and fall back to OCI CLI, bypassing the browser-based testing that is the entire point.

**Agent teams** are full interactive Claude sessions. Each teammate can ask questions, open browsers, and use all tools independently.

## Setting Up the Team

### 1. Create team

Use `TeamCreate` to create a team named `<version>-release-test`:

```
Team name: v005-release-test
```

### 2. Create teammates

One teammate per track. Name them descriptively:

| Teammate | Track | Purpose |
|---|---|---|
| `track1-gpu4` | BM.GPU4.8 packs | enterprise_rag + enterprise_rag_aiq |
| `track2-a10` | VM.GPU.A10 packs | vss + cuopt + warehouse_pick_path |
| `track3-cpu` | CPU-only packs | paas_rag |

### 3. Send initial instructions

Each teammate needs a self-contained message with:

```
You are testing starter packs for the <VERSION> release.

Region: <region>
OCI CLI Profile: <profile>
Compartment: <compartment_name> (<compartment_ocid>)
PR_NUMBER: <number>

## Round 1: <category>/<size>

Invoke `/testing-pack <category> <size>`.

When /testing-pack asks for parameters:
- Region: <region>
- OCI CLI Profile: <profile>
- Compartment: <compartment_name>
- PR Number: <number>
- No PR-specific requirements

## Round 2: <category>/<size> (back-to-back)

After Round 1 completes:
1. Destroy the app stack (preserve infra)
2. Rebuild zip with: `python3 create_final_schema.py -c <category2>`
3. Update the infra stack with the new zip via agent-browser
4. Re-apply infra (cluster config changes for new pack)
5. Invoke `/testing-pack <category2> <size2>` for the app stack

After Round 2, destroy both stacks and clean up.
```

## Browser Isolation

Each teammate MUST use a unique, isolated browser session.

### Critical: `--session` vs `--session-name`

| Flag | Behavior | Use for parallel? |
|---|---|---|
| `--session <name>` | **Separate browser instance** — own cookies, storage, navigation | **YES** |
| `--session-name <name>` | Persists cookies under a name but **shares the browser daemon** | **NO** |

Using `--session-name` for parallel tracks causes all teammates to fight over the same browser tab. `/testing-pack` already generates a unique session name and uses `--session`.

## Permissions

Add these to `~/.claude/settings.json` under `allowedTools` to avoid permission prompts blocking teammates:

```
Bash(agent-browser:*), Bash(helm:*), Bash(git worktree:*),
Bash(openssl:*), Bash(sleep:*), Bash(date:*),
Skill(testing-pack), Skill(monitoring-deployment),
Skill(checking-capacity), Skill(diagnosing-stack),
Skill(bug-tracker), Skill(destroy-stack)
```

## Zip Path Isolation

Each teammate MUST use a unique zip file path. The `/testing-pack` skill defines `ZIP_PATH="/tmp/${WORKTREE_NAME}.zip"` — since each worktree has a unique timestamp-based name, zip files won't collide.

**Anti-pattern:** Using a hardcoded path like `/tmp/testing-pack.zip`. When multiple tracks run in parallel, one track's zip overwrites another's before upload, causing the wrong schema to be deployed to ORM (e.g., VSS wizard appearing when deploying enterprise_rag).

## Back-to-Back Pack Switching (Bare Metal Only)

> **This workflow applies only to bare metal (BM.\*) tracks.** For VM tracks, see "VM Track Switching" below.

When a BM track runs multiple packs sequentially:

1. **Destroy app stack first** — this cleans up Helm releases, secrets, configmaps, PVCs
2. **Rebuild zip** with the new pack's schema
3. **Update infra stack** with the new zip via agent-browser
4. **Re-apply infra** — the cluster adapts to the new pack's config:
   - GPU node pools scale up/down (instance pool resize)
   - ADB gets created/removed as needed
   - Worker node shapes change if different between packs
5. **Create new app stack** with the new zip, using `existing_cluster_id` from infra outputs
6. **Apply app stack**

This is the two-stack model — infra persists while app stacks are swapped. It exists to avoid the 6-hour bare metal GPU host recycle time.

## VM Track Switching

VM shapes (VM.GPU.A10.2, etc.) provision in minutes — there is no benefit to preserving infra between packs. Reusing VM infra causes stale container images to fill ephemeral storage (BUG-012) and stale taints/labels to block scheduling (BUG-009).

When a VM track runs multiple packs sequentially:

1. **Destroy both stacks** — app stack first, then infra stack
2. **Clean up orphaned resources** — customer secret keys (quota of 2 per user), orphaned ADB instances
3. **Invoke `/testing-pack` fresh** for the next pack — this creates new infra + app stacks from scratch

## Monitoring Progress

From the main session, use `SendMessage` to check in on teammates:

```
SendMessage(to: "track1-gpu4", message: "What's your current status?")
```

Teammates will report their current phase and any issues.

## Handling Failures

If a teammate reports a failure:

1. Check if it's a code bug or infra issue
2. For code bugs: fix on the release branch, rebuild zip, send teammate the new zip path
3. For infra issues (quota, capacity): may need to switch regions — coordinate across tracks to avoid conflicts
4. For browser issues: have the teammate close and reopen the browser session

## Cleanup

After all tracks complete:

1. Collect test reports from each teammate
2. Verify all stacks are destroyed
3. Remove git worktrees created by `/testing-pack`
4. Close all browser sessions
