# BUG-012 Fix: VM Tracks Use Fresh Infra Between Rounds

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Update releasing skill and PARALLEL_TESTING.md so VM tracks destroy everything between rounds instead of preserving infra.

**Architecture:** Three documentation/skill files are edited. No Terraform code changes. LESSONS_LEARNED.md already contains the rule (lines 82-91) and needs no changes.

**Tech Stack:** Markdown only.

**Spec:** `docs/superpowers/specs/2026-04-09-bug012-vm-track-fresh-infra-design.md`

---

### Task 1: Update SKILL.md Phase 3b — Track Design

**Files:**
- Modify: `.claude/skills/releasing/SKILL.md:137-145`

- [ ] **Step 1: Replace Phase 3b track grouping text**

Replace lines 137-145 (from `Group packs by GPU shape` through the `Key principle` line) with shape-aware grouping logic:

```markdown
Group packs by GPU shape. **Back-to-back infra reuse is only for bare metal (BM.\*) shapes.** VM shapes provision in minutes — destroy everything and start fresh between packs.

Check `worker_node_shape` in `vars.tf` → `local.starter_pack_configs` for each pack/size:
- Shape starts with `BM.` → eligible for back-to-back switching (preserve infra between rounds)
- Shape starts with `VM.` → must destroy both stacks between rounds (fresh infra each pack)
- Shape is `none` (CPU) → single round, no switching needed

For the default test matrix (poc/small sizes):

- **Track 1 (BM.GPU4.8):** enterprise_rag/small then enterprise_rag_aiq/small — back-to-back (destroy app, re-apply infra, new app)
- **Track 2 (VM.GPU.A10.2):** vss/poc then cuopt/poc — sequential with full destroy between rounds
- **Track 3 (CPU only):** paas_rag/small (independent)

Present the track plan to the user and confirm. Adjust if they want different groupings.

**Key principle:** Back-to-back switching only applies when rounds share the same BM worker_node_shape. For BM tracks, re-apply infra every round so the cluster matches the new pack's config. For VM tracks, destroy everything and create fresh stacks — VMs provision in minutes, and preserving infra risks stale container images filling ephemeral storage (BUG-012) and stale taints blocking scheduling (BUG-009).
```

- [ ] **Step 2: Verify the edit**

Read `.claude/skills/releasing/SKILL.md` lines 135-160 and confirm the new text is in place, the surrounding sections (3a above and 3c below) are intact, and there are no formatting issues.

---

### Task 2: Update SKILL.md Phase 4b — Teammate Instructions

**Files:**
- Modify: `.claude/skills/releasing/SKILL.md:191-197`

- [ ] **Step 1: Replace the teammate message instructions**

Replace lines 191-197 (the numbered list starting with "Each teammate message should include:") with VM/BM-aware instructions:

```markdown
Each teammate message should include:
1. The pack category and size to test
2. The region and OCI CLI profile
3. The compartment OCID
4. Instruction to invoke `/testing-pack <category> <size> --zip-path release_test_matrix/<VERSION>_<category>.zip` — this uses the pre-built release zip directly, skipping worktree creation and zip rebuilding. This ensures teammates test the exact zips that will ship to users and avoids race conditions on shared temp files.
5. For **BM tracks** (back-to-back): instruction to destroy the app stack (preserve infra), then invoke `/testing-pack <category2> <size2> --zip-path release_test_matrix/<VERSION>_<category2>.zip` for the second pack
6. For **VM tracks** (sequential fresh): instruction to destroy both stacks (app first, then infra), clean up resources (customer secret keys, orphaned ADB), then invoke `/testing-pack <category2> <size2> --zip-path release_test_matrix/<VERSION>_<category2>.zip` fresh (creates new infra + app stacks)
7. `PR_NUMBER=<number>` — the GitHub PR number for posting test progress and results
```

- [ ] **Step 2: Verify the edit**

Read `.claude/skills/releasing/SKILL.md` lines 188-202 and confirm the BM/VM distinction is present and surrounding text is intact.

---

### Task 3: Update PARALLEL_TESTING.md — Add VM/BM Distinction

**Files:**
- Modify: `.claude/skills/releasing/PARALLEL_TESTING.md:117-131`

- [ ] **Step 1: Replace the Back-to-Back Pack Switching section**

Replace lines 117-131 (from `## Back-to-Back Pack Switching` through `This is the two-stack model`) with a BM-scoped section plus a new VM section:

```markdown
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
```

- [ ] **Step 2: Verify the edit**

Read `.claude/skills/releasing/PARALLEL_TESTING.md` lines 115-155 and confirm both sections are in place, the "Monitoring Progress" section follows immediately after, and formatting is clean.

---

### Task 4: Update BUGS.md — Mark BUG-012 Fixed

**Files:**
- Modify: `BUGS.md:18` (summary table)
- Modify: `BUGS.md:383-406` (detailed entry)

- [ ] **Step 1: Update the summary table**

Change line 18 from:
```
| Open | BUG-012 | Back-to-back pack switch on VMs leaves stale images filling ephemeral storage | Medium | 2026-04-09 |
```
To:
```
| Fixed | BUG-012 | Back-to-back pack switch on VMs leaves stale images filling ephemeral storage | Medium | 2026-04-09 |
```

- [ ] **Step 2: Update the detailed entry**

In the BUG-012 section (starts at line 383), change:
- `**Status:** Open` → `**Status:** Fixed`
- Add `**Date fixed:** 2026-04-09` after the "Found by" line
- Replace the `**Resolution:**` paragraph (line 405-406) with:

```markdown
**Resolution:**
Updated the releasing skill's track design (Phase 3b in SKILL.md) to only use back-to-back pack switching for bare metal (BM.*) shapes. VM tracks now destroy both stacks and create fresh infra between rounds. Updated PARALLEL_TESTING.md to split the back-to-back section into "Bare Metal Only" and "VM Track Switching" sections. LESSONS_LEARNED.md already contained the rule (added during initial diagnosis). Fixed on `release_v0.0.6`.

**Verification:** During next release, VM tracks (e.g., vss/poc → cuopt/poc) should destroy everything between rounds. No `Insufficient ephemeral-storage` errors on the second pack.

**Prevention:** The releasing skill's Phase 3b now explicitly checks `worker_node_shape` prefix (BM.* vs VM.*) when designing tracks. PARALLEL_TESTING.md documents both workflows separately.
```

- [ ] **Step 3: Verify both edits**

Read `BUGS.md` lines 16-19 (summary table) and lines 383-415 (detailed entry) to confirm both are updated correctly.

---

### Task 5: Commit

**Files:** All modified files from Tasks 1-4.

- [ ] **Step 1: Stage and commit**

```bash
git add .claude/skills/releasing/SKILL.md .claude/skills/releasing/PARALLEL_TESTING.md BUGS.md
git commit -m "docs: fix BUG-012 — VM tracks use fresh infra between rounds

Update releasing skill Phase 3b to only use back-to-back pack switching
for bare metal (BM.*) shapes. VM tracks now destroy both stacks between
rounds to avoid stale container images filling ephemeral storage.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```
