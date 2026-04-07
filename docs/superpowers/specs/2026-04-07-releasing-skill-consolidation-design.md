# Releasing Skill Consolidation

**Date:** 2026-04-07
**Status:** Design

## Summary

Consolidate `old-release-upgrade` and `old-release-push` into two reference files inside `.claude/skills/releasing/`. The `/releasing` orchestrator SKILL.md is slimmed down to avoid duplication — it points to the reference files via progressive disclosure instead of inlining their content.

## Motivation

- `old-release-upgrade` and `old-release-push` were standalone skills that `/releasing` delegated to
- They've been prefixed with "old-" because they're outdated
- The test matrix step (Step 6 of old-release-upgrade) is no longer needed
- OWNERS.md is no longer needed (was only used by test matrix)
- The content should live inside the releasing skill folder since it's only invoked from there

## Final File Structure

```
.claude/skills/releasing/
├── SKILL.md                 # Orchestrator (slimmed, no duplication)
├── RELEASE_BUILD.md         # Build steps (from old-release-upgrade, minus test matrix)
├── RELEASE_PUBLISH.md       # Publish steps (from old-release-push, all steps kept)
├── ZIP_PACKAGING.md         # Zip creation details (moved from old-release-upgrade)
├── PARALLEL_TESTING.md      # Agent teams setup (unchanged)
└── LESSONS_LEARNED.md       # Anti-patterns (unchanged)
```

## RELEASE_BUILD.md

Consolidated from `old-release-upgrade` SKILL.md. Steps:

1. **Prerequisites** — clean working tree, confirm current version, ask about corrino_image_version
2. **Create release branch** — `release_v<VERSION>` from main (early, before any changes)
3. **Validate version format** — semver check, must be higher than current
4. **Update version files** — AI_ACCELERATOR_STACK_VERSION, vars.tf, common_schema.yaml (all three together, never partial)
5. **Validate** — terraform fmt -recursive, terraform validate, schema gen (`python3 create_final_schema.py --all`), schema tests (`pytest schemas/tests/ -v`), feedback loop until clean
6. **Display summary** — show `git diff`, ask user to confirm before proceeding
7. **Commit and push** — commit version bump files, push `release_v<VERSION>` branch
8. **Create per-pack zips** — see [ZIP_PACKAGING.md](ZIP_PACKAGING.md) for details. Scan for sensitive data, generate schema per category, zip with exclusions, output to `release_test_matrix/`

**Dropped from old-release-upgrade:**
- Step 6 (Create Test Matrix) — no longer needed
- TEST_MATRIX.md, TEST_MATRIX_FORMAT.md — dropped with test matrix
- OWNERS.md — only used by test matrix

**Reference files:** ZIP_PACKAGING.md (moved from old-release-upgrade, unchanged)

## RELEASE_PUBLISH.md

Consolidated from `old-release-push` SKILL.md. All steps kept:

1. **Prerequisites** — confirm build has been run (release commit exists), confirm zips have been tested, locate zips in `release_test_matrix/`, read version from AI_ACCELERATOR_STACK_VERSION
2. **Validate zip files** — unzip each into temp dir, scan for prohibited content (.terraform, .tfvars, .env, __pycache__, .git, private keys, secrets patterns), stop immediately if issues found
3. **Create release directory and rename zips** — version-based directory (`release-<NNN>/`), copy and rename using display-name mapping:
   - enterprise_rag → aiQEnterpriseSearch.zip
   - enterprise_rag_aiq → enterpriseAgenticAIStarterKit.zip
   - paas_rag → aiQGenAIPowered.zip
   - cuopt → vehicleRouteOptimizer.zip
   - vss → videoSearchSummarization.zip
4. **Generate Slack announcement** — gather changes from user's task list (primary source), cross-reference against previous announcement, verify against code diff, format with Slack mrkdwn and display-name categories
5. **Merge release PR and tag** — find open PR, merge, pull main with ff-only, create and push tag using full ref (`refs/tags/release_v<VERSION>`)
6. **Celebrate** — ASCII art

## SKILL.md Changes

The orchestrator SKILL.md is updated to:

1. **Phase 1:** Replace the 7-line summary with "Read and follow [RELEASE_BUILD.md](RELEASE_BUILD.md)." Keep only the post-build verification (`ls release_test_matrix/`).
2. **Phase 5 (Fix & Rebuild):** The zip rebuild steps reference ZIP_PACKAGING.md instead of inlining the full bash commands. Keep the GitHub Release asset re-upload steps (those are unique to Phase 5).
3. **Phase 6:** Replace the 5-line summary with "Read and follow [RELEASE_PUBLISH.md](RELEASE_PUBLISH.md)." Keep only the final verification commands.
4. **Delegation map:** Update to reference RELEASE_BUILD.md and RELEASE_PUBLISH.md instead of `/release-upgrade` and `/release-push`.
5. **Description:** Update to remove references to `/release-upgrade` and `/release-push`.

## What Does NOT Change

- **Phase 2 (GitHub Release creation)** — stays inline in SKILL.md
- **Phase 3 (Plan Testing)** — stays inline, delegates to `/checking-capacity`
- **Phase 4 (Execute Testing)** — stays inline, references PARALLEL_TESTING.md
- **PARALLEL_TESTING.md** — unchanged
- **LESSONS_LEARNED.md** — unchanged

## Implementation Steps

1. Create RELEASE_BUILD.md from old-release-upgrade content (minus test matrix, minus OWNERS.md)
2. Create RELEASE_PUBLISH.md from old-release-push content (all steps)
3. Move ZIP_PACKAGING.md from old-release-upgrade to releasing folder
4. Update SKILL.md — slim down Phases 1, 5, and 6 to reference the new files
5. Update SKILL.md description/delegation map
6. Verify no duplication remains between SKILL.md and the reference files
