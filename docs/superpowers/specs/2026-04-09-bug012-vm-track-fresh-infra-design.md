# BUG-012 Fix: VM Tracks Use Fresh Infra Between Rounds

**Date:** 2026-04-09
**Status:** Approved
**Bug:** BUG-012 — Back-to-back pack switch on VMs leaves stale images filling ephemeral storage

## Problem

During v0.0.6 release testing, Track 2 (VM.GPU.A10.2) ran VSS/poc first, then switched to cuopt/poc back-to-back on the same infra. The cuopt NIM pod failed with `Insufficient ephemeral-storage` because cached container images from the VSS deployment remained on the GPU nodes.

The two-stack preserve-infrastructure model exists to avoid the 6-hour bare metal GPU host recycle time. VM shapes provision in minutes — preserving infra provides no time savings while introducing stale state risks:
- Stale container images fill ephemeral storage (this bug)
- Stale taints/labels block scheduling (BUG-009)
- GPU operator state can get confused after pack switches

## Core Rule

> Back-to-back pack switching (destroy app only, preserve infra, re-apply) is **only** for bare metal (BM.\*) tracks. VM tracks (VM.\*) must destroy both stacks and create fresh infra between packs.

## Shape Classification

From `vars.tf` `local.starter_pack_configs`:

| Pack | Size | Shape | Type | Infra Reuse? |
|---|---|---|---|---|
| enterprise_rag | small | BM.GPU4.8 | BM | Yes |
| enterprise_rag_aiq | small | BM.GPU4.8 | BM | Yes |
| cuopt | poc | VM.GPU.A10.2 | VM | No |
| cuopt | small | BM.GPU4.8 | BM | Yes |
| cuopt | medium | BM.GPU.A100-v2.8 | BM | Yes |
| vss | poc | VM.GPU.A10.2 | VM | No |
| vss | small | BM.GPU4.8 | BM | Yes |
| vss | medium | BM.GPU.L40S-NC.4 | BM | Yes |
| paas_rag | small | none (CPU) | CPU | N/A (single round) |

**The decision depends on size, not just pack.** cuopt/poc is VM (no reuse), cuopt/small is BM (reuse OK).

## Changes

### 1. `SKILL.md` — Phase 3b Track Design

**Current text (lines 137-145):**
Static track groupings that always use back-to-back switching for Track 2.

**New behavior:**
When designing tracks in Phase 3b, the releasing agent must check the `worker_node_shape` for each pack/size being tested:
- If the shape starts with `BM.` — eligible for back-to-back switching (preserve infra between rounds)
- If the shape starts with `VM.` — must destroy everything between rounds
- If `none` (CPU only) — single round, no switching needed

Update the example track plan to show this distinction. For the default test matrix (poc/small sizes):

```
Track 1 (BM.GPU4.8):  enterprise_rag/small then enterprise_rag_aiq/small
                       → back-to-back (destroy app, re-apply infra, new app)

Track 2 (VM.GPU.A10.2): vss/poc then cuopt/poc
                         → sequential with full destroy between rounds

Track 3 (CPU only):    paas_rag/small
                       → single round
```

**Phase 4b teammate instructions** — the round 2 instructions for VM tracks change from:

> 1. Destroy the app stack (preserve infra)
> 2. Rebuild zip / Update infra stack / Re-apply infra
> 3. Invoke `/testing-pack` for the app stack

To:

> 1. Destroy both stacks (app first, then infra)
> 2. Clean up resources (customer secret keys, orphaned ADB)
> 3. Invoke `/testing-pack` fresh (creates new infra + app stacks)

### 2. `PARALLEL_TESTING.md` — Back-to-Back Section

**Current:** Lines 119-131 describe one unified back-to-back workflow with no VM/BM distinction.

**Changes:**

1. Add a gate at the top of the "Back-to-Back Pack Switching" section:
   > **This workflow applies only to bare metal (BM.\*) tracks.** For VM tracks, see "VM Track Switching" below.

2. Add a new section "VM Track Switching" after the back-to-back section:
   - Destroy both stacks (app first, then infra)
   - Clean up orphaned resources (customer secret keys, ADB)
   - Create completely fresh stacks for the next pack
   - Rationale: VMs provision in minutes, no benefit to preserving infra

### 3. `BUGS.md` — Mark BUG-012 Fixed

Update status from Open to Fixed. Add resolution section documenting that the fix is in the releasing skill and PARALLEL_TESTING.md — VM tracks now destroy everything between rounds instead of preserving infra.

## Scope

- Three documentation/skill files changed
- No Terraform code changes
- No `/testing-pack` skill changes (the pack-level skill doesn't decide whether to preserve infra — the releasing agent's track design does)
