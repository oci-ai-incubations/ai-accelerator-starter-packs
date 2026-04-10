# Releasing Skill Consolidation — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Consolidate old-release-upgrade and old-release-push into reference files inside the releasing skill folder, extend /zip-tf with optional args, and slim down the releasing orchestrator to eliminate duplication.

**Architecture:** Two new reference markdown files (RELEASE_BUILD.md, RELEASE_PUBLISH.md) live inside `.claude/skills/releasing/` and are loaded by the orchestrator SKILL.md via progressive disclosure. The /zip-tf skill gains optional arguments for output directory and filename so release builds can reuse it.

**Tech Stack:** Markdown skill files, bash commands in skill instructions

---

### Task 1: Extend /zip-tf with optional arguments

**Files:**
- Modify: `.claude/skills/zip-tf/SKILL.md`

- [ ] **Step 1: Add arguments section to /zip-tf SKILL.md**

Add an Arguments section after the frontmatter and before the Workflow section. Insert this content after line 7 (`# Zip Terraform`) and before line 9 (`## Workflow`):

```markdown
## Arguments

- `$0` (optional) — Output directory. Default: `zipped/`. Example: `release_test_matrix/`.
- `$1` (optional) — Custom filename without `.zip` extension. Default: `<category>-<timestamp>`. Example: `v0.0.6_cuopt`.

If no arguments are provided, behavior is unchanged (timestamped zip in `zipped/`).
```

- [ ] **Step 2: Update the zip creation section to use optional args**

Replace the current "Create the zip" bash block (lines 24-43) with a version that respects the optional arguments:

```bash
CATEGORY=$(grep -oP 'starter_pack_category\s*=\s*"\K[^"]+' ai-accelerator-tf/starter_pack_category.auto.tfvars)

# Use arguments if provided, otherwise use defaults
OUTPUT_DIR="${0:-zipped}"
mkdir -p "$OUTPUT_DIR"

if [ -n "$1" ]; then
  ZIP_NAME="${OUTPUT_DIR}/${1}.zip"
else
  TIMESTAMP=$(date +"%Y-%m-%d-%H%M")
  ZIP_NAME="${OUTPUT_DIR}/${CATEGORY}-${TIMESTAMP}.zip"
fi

zip -r "${ZIP_NAME}" ai-accelerator-tf/ \
  -x 'ai-accelerator-tf/.terraform/*' \
  -x 'ai-accelerator-tf/.terraform.lock.hcl' \
  -x '*.tfvars' \
  -x '*__pycache__/*' \
  -x '*.pytest_cache/*' \
  -x 'ai-accelerator-tf/tests/*' \
  -x 'ai-accelerator-tf/schemas/tests/*' \
  -x 'ai-accelerator-tf/schemas/generated/*'

# *.tfvars catches starter_pack_category.auto.tfvars — add it back
zip "${ZIP_NAME}" ai-accelerator-tf/starter_pack_category.auto.tfvars

ls -lh "${ZIP_NAME}"
```

Note: The three additional exclusions (`tests/*`, `schemas/tests/*`, `schemas/generated/*`) are added unconditionally — these files are never needed in ORM zips regardless of context.

- [ ] **Step 3: Update the verify section paths**

In the verify bash block (lines 48-70), update the unzip command and variable to use `ZIP_NAME` instead of hardcoded paths:

```bash
VERIFY_DIR=$(mktemp -d)
unzip -qo "${ZIP_NAME}" -d "$VERIFY_DIR"
```

And the cleanup at the end:

```bash
rm -rf "$VERIFY_DIR"
```

The existing must-not-contain and must-contain checks remain unchanged — they already work against a relative `verify_tmp`-style directory. Update them to use `$VERIFY_DIR` instead of `verify_tmp`.

- [ ] **Step 4: Verify the updated skill reads correctly**

Read through the entire updated SKILL.md to confirm:
- Arguments section is present between the title and Workflow
- The Workflow section still references step numbers correctly
- The zip command includes all 8 exclusions (original 5 + 3 new)
- The verify section uses the dynamic `ZIP_NAME` variable
- No orphaned references to `zipped/` or hardcoded timestamps remain in the commands

- [ ] **Step 5: Commit**

```bash
git add .claude/skills/zip-tf/SKILL.md
git commit -m "feat: extend /zip-tf with optional output-dir and filename args

Add optional arguments for custom output directory and filename to
support release packaging. Add test/schema exclusions for ORM zips."
```

---

### Task 2: Create RELEASE_BUILD.md

**Files:**
- Create: `.claude/skills/releasing/RELEASE_BUILD.md`

Source content: `.claude/skills/archive/old-release-upgrade/SKILL.md` (lines 9-98, minus Step 6 test matrix and Step 7 zip packaging, replacing zip with /zip-tf invocation)

- [ ] **Step 1: Write RELEASE_BUILD.md**

Create the file with the following content. This is adapted from old-release-upgrade with these changes:
- No YAML frontmatter (it's a reference file, not a standalone skill)
- Release branch creation moved to Step 2 (before any file changes)
- Step 6 (Test Matrix) dropped entirely
- Step 7 (Zip) replaced with /zip-tf invocation
- OWNERS.md reference removed

```markdown
# Release Build

Build phase of the release lifecycle. Creates the release branch, bumps versions, validates, and creates per-pack ORM zips.

## Arguments

Expects `VERSION` to be set by the calling skill (e.g., `v0.0.6`).

## Step 1: Prerequisites

1. Ensure working directory is clean (`git status`)
2. Read current version from `ai-accelerator-tf/AI_ACCELERATOR_STACK_VERSION`
3. Ask the user if they also want to update `corrino_image_version`

## Step 2: Create Release Branch

Confirm on the correct release branch (`release_v<VERSION>`). If not, look for it. If it doesn't exist, create it from latest main:

` ` `bash
git checkout -b release_v<VERSION> main
` ` `

All subsequent steps happen on this branch.

## Step 3: Validate Version Format

- Must match `vMAJOR.MINOR.PATCH`
- Compare semver components numerically to confirm new version is higher:
  ` ` `
  Split both versions on "." after stripping "v" prefix.
  Compare MAJOR, then MINOR, then PATCH as integers.
  ` ` `

## Step 4: Update Version Files

All three files must be updated together — never proceed with partial updates.

**a. `ai-accelerator-tf/AI_ACCELERATOR_STACK_VERSION`**
- Replace contents with the new version

**b. `ai-accelerator-tf/vars.tf`**
- Update `accelerator_pack_stack_version` default value
- Optionally update `corrino_image_version` if requested in prerequisites

**c. `ai-accelerator-tf/schemas/common_schema.yaml`**
- Add new version to the TOP of the `accelerator_pack_stack_version` enum list
- Update default to new version
- Keep all previous versions for rollback capability

## Step 5: Validate

Run validation with a feedback loop — fix and retry until clean:

` ` `bash
cd ai-accelerator-tf
terraform fmt -recursive
terraform validate
` ` `

Also regenerate and test schemas:
` ` `bash
cd schemas && python3 create_final_schema.py --all
cd .. && pytest schemas/tests/ -v
` ` `

Clean up build artifacts after validation:
` ` `bash
rm -rf .terraform .terraform.lock.hcl
` ` `

If validation fails, fix the issues and re-run. Only proceed when all checks pass.

## Step 6: Display Summary

- Show all files updated
- Display `git diff` of changes
- Ask user to confirm before proceeding

## Step 7: Commit and Push

After user confirmation:

` ` `bash
git add ai-accelerator-tf/AI_ACCELERATOR_STACK_VERSION \
       ai-accelerator-tf/vars.tf \
       ai-accelerator-tf/schemas/common_schema.yaml
git commit -m "Release <VERSION>"
git push -u origin release_v<VERSION>
` ` `

## Step 8: Create Per-Pack Zips

For each category in `enterprise_rag`, `enterprise_rag_aiq`, `paas_rag`, `cuopt`, `vss`:

1. Set category: `echo 'starter_pack_category = "<category>"' > ai-accelerator-tf/starter_pack_category.auto.tfvars`
2. Regenerate schema: `source venv/bin/activate && python3 create_final_schema.py -c <category>`
3. Invoke `/zip-tf release_test_matrix <VERSION>_<category>` to create the zip

After all 5 zips are created, verify:

` ` `bash
ls -la release_test_matrix/
# Expect: <version>_enterprise_rag.zip, <version>_enterprise_rag_aiq.zip,
#         <version>_paas_rag.zip, <version>_cuopt.zip, <version>_vss.zip
` ` `

## Version Conventions

- **MAJOR**: Breaking changes requiring user action
- **MINOR**: New features, backward compatible
- **PATCH**: Bug fixes and minor improvements

## Error Handling

- If any file update fails, stop and report the error
- If validation fails, show errors and suggest fixes
- Never proceed with partial updates — all files must be updated together
```

Note: The triple backticks in the actual file must be real backticks, not the escaped version shown above. The spaces in the code blocks above are only to prevent markdown rendering issues in this plan document.

- [ ] **Step 2: Verify the file**

Read the created file and confirm:
- No YAML frontmatter
- 8 steps covering: prerequisites, branch, version format, version files, validate, summary, commit/push, zips
- Step 8 references `/zip-tf` with release_test_matrix and version naming
- No references to test matrix, OWNERS.md, or ZIP_PACKAGING.md

- [ ] **Step 3: Commit**

```bash
git add .claude/skills/releasing/RELEASE_BUILD.md
git commit -m "feat: add RELEASE_BUILD.md to releasing skill

Consolidated from old-release-upgrade. Drops test matrix step,
delegates zip creation to /zip-tf."
```

---

### Task 3: Create RELEASE_PUBLISH.md

**Files:**
- Create: `.claude/skills/releasing/RELEASE_PUBLISH.md`

Source content: `.claude/skills/archive/old-release-push/SKILL.md` (lines 9-189, all steps kept)

- [ ] **Step 1: Write RELEASE_PUBLISH.md**

Create the file with all content from old-release-push SKILL.md, adapted as a reference file:
- No YAML frontmatter (it's a reference file, not a standalone skill)
- All 6 steps (prerequisites, validate zips, rename, Slack, merge/tag, celebrate) kept intact
- Content is copied from `.claude/skills/archive/old-release-push/SKILL.md` lines 9-189 (everything after the frontmatter closing `---`)
- Change "## Arguments" to note that VERSION comes from the calling skill
- Change any references to `/release-upgrade` to say "the build phase (RELEASE_BUILD.md)"

- [ ] **Step 2: Verify the file**

Read the created file and confirm:
- No YAML frontmatter
- 6 steps: prerequisites, validate zips, create release dir + rename, Slack announcement, merge PR + tag, celebrate
- Display-name mapping table is present (5 entries)
- Slack mrkdwn format template is present
- ASCII art celebration is present
- Error handling section is present

- [ ] **Step 3: Commit**

```bash
git add .claude/skills/releasing/RELEASE_PUBLISH.md
git commit -m "feat: add RELEASE_PUBLISH.md to releasing skill

Consolidated from old-release-push. All steps preserved: validate
zips, rename, Slack announcement, merge PR, tag, celebrate."
```

---

### Task 4: Update releasing SKILL.md

**Files:**
- Modify: `.claude/skills/releasing/SKILL.md`

- [ ] **Step 1: Update the YAML description**

Replace the current description (line 3) which references `/release-upgrade` and `/release-push`:

Old:
```
description: End-to-end release lifecycle orchestrator — builds the release via /release-upgrade, creates a GitHub Release with per-pack zips, plans and executes parallel testing across GPU tracks using agent teams and /testing-pack, handles the bug-fix-rebuild loop, and finalizes via /release-push. Use when cutting a new release, the user says "do a release", "release v0.0.X", or "run the full release process".
```

New:
```
description: End-to-end release lifecycle orchestrator — builds the release (version bump, validate, per-pack zips), creates a GitHub Release, plans and executes parallel testing across GPU tracks using agent teams and /testing-pack, handles the bug-fix-rebuild loop, and finalizes (validate zips, Slack announcement, merge PR, tag). Use when cutting a new release, the user says "do a release", "release v0.0.X", or "run the full release process".
```

- [ ] **Step 2: Update the delegation map table**

Replace the current delegation map (lines 18-27):

Old:
```markdown
| Phase | Delegates to | What it covers |
|---|---|---|
| 1: Build | `/release-upgrade $VERSION` | Branch, version bump, validate, schema gen/test, zip, commit, push |
| 2: GitHub Release | *(this skill)* | `gh release create` with per-pack zip assets |
| 3: Plan Testing | `/checking-capacity` | GPU capacity + quota per track |
| 4: Execute Testing | `/testing-pack` (via agent teams) | Per-pack two-stack deploy + smoke tests |
| 5: Fix & Rebuild | *(this skill)* | Bug fix loop, rebuild zips, re-upload assets |
| 6: Finalize | `/release-push $VERSION` | Validate zips, Slack announcement, merge PR, tag |
```

New:
```markdown
| Phase | Delegates to | What it covers |
|---|---|---|
| 1: Build | [RELEASE_BUILD.md](RELEASE_BUILD.md) | Branch, version bump, validate, schema gen/test, zip via `/zip-tf`, commit, push |
| 2: GitHub Release | *(this skill)* | `gh release create` with per-pack zip assets |
| 3: Plan Testing | `/checking-capacity` | GPU capacity + quota per track |
| 4: Execute Testing | `/testing-pack` (via agent teams) | Per-pack two-stack deploy + smoke tests |
| 5: Fix & Rebuild | *(this skill)* + `/zip-tf` | Bug fix loop, rebuild zips, re-upload assets |
| 6: Finalize | [RELEASE_PUBLISH.md](RELEASE_PUBLISH.md) | Validate zips, Slack announcement, merge PR, tag |
```

- [ ] **Step 3: Replace Phase 1 body**

Replace the current Phase 1 content (lines 30-49, from `## Phase 1: Build Release` through the `If any zip is missing` line) with:

```markdown
## Phase 1: Build Release

Read and follow [RELEASE_BUILD.md](RELEASE_BUILD.md). This handles:
branch creation, version bump, validation, schema gen/tests, commit, push, and per-pack zip creation via `/zip-tf`.

**After build completes**, verify:

` ` `bash
ls -la release_test_matrix/
# Expect: <version>_enterprise_rag.zip, <version>_enterprise_rag_aiq.zip,
#         <version>_paas_rag.zip, <version>_cuopt.zip, <version>_vss.zip
` ` `

If any zip is missing, stop and investigate.
```

- [ ] **Step 4: Replace Phase 5 zip rebuild commands**

In Phase 5, replace the inline zip rebuild commands (Step 5c, lines 226-241) with a reference to /zip-tf:

Old (lines 226-241):
```markdown
### 5c. Rebuild all 5 zips

After all fixes are committed:

` ` `bash
cd ai-accelerator-tf
rm -rf .terraform .terraform.lock.hcl
` ` `

For each category in `enterprise_rag`, `enterprise_rag_aiq`, `paas_rag`, `cuopt`, `vss`:

` ` `bash
source venv/bin/activate
python3 create_final_schema.py -c <category>
cd ai-accelerator-tf
rm -f ../release_test_matrix/${VERSION}_<category>.zip
zip -r ../release_test_matrix/${VERSION}_<category>.zip . \
  -x '*.git*' '*__pycache__*' '*.pytest_cache*' \
  '.terraform/*' '.terraform.lock.hcl' 'terraform.tfvars' \
  'tests/*' 'schemas/tests/*' 'schemas/generated/*'
cd ..
` ` `
```

New:
```markdown
### 5c. Rebuild all 5 zips

After all fixes are committed:

` ` `bash
rm -rf ai-accelerator-tf/.terraform ai-accelerator-tf/.terraform.lock.hcl
` ` `

For each category in `enterprise_rag`, `enterprise_rag_aiq`, `paas_rag`, `cuopt`, `vss`:

1. Set category: `echo 'starter_pack_category = "<category>"' > ai-accelerator-tf/starter_pack_category.auto.tfvars`
2. Regenerate schema: `source venv/bin/activate && python3 create_final_schema.py -c <category>`
3. Delete old zip: `rm -f release_test_matrix/${VERSION}_<category>.zip`
4. Invoke `/zip-tf release_test_matrix ${VERSION}_<category>` to create the new zip
```

- [ ] **Step 5: Replace Phase 6 body**

Replace the current Phase 6 content (lines 276-298) with:

```markdown
## Phase 6: Finalize

Only proceed when all packs pass (or user explicitly decides to ship with known issues).

### 6a. Promote the GitHub Release

If still marked as pre-release, promote it (see Phase 2c).

### 6b. Publish

Read and follow [RELEASE_PUBLISH.md](RELEASE_PUBLISH.md). This handles:
validate zip files, rename to display names, generate Slack announcement, merge release PR, and push release tag.

### 6c. Verify completion

` ` `bash
git tag --list 'release_v*' --sort=-version:refname | head -5
gh release view $VERSION
` ` `
```

- [ ] **Step 6: Update the Reference Files section at the bottom**

Replace the current reference files list (lines 332-333) with:

```markdown
## Reference Files

- **[RELEASE_BUILD.md](RELEASE_BUILD.md)** — Build phase: branch, version bump, validate, zip creation
- **[RELEASE_PUBLISH.md](RELEASE_PUBLISH.md)** — Publish phase: validate zips, rename, Slack, merge PR, tag
- **[PARALLEL_TESTING.md](PARALLEL_TESTING.md)** — Agent teams setup, browser isolation, permissions, back-to-back pack switching
- **[LESSONS_LEARNED.md](LESSONS_LEARNED.md)** — Anti-patterns and pitfalls discovered during real releases
```

- [ ] **Step 7: Verify no duplication**

Read the full updated SKILL.md and check:
- Phase 1 does NOT list the 7 build steps (they're in RELEASE_BUILD.md)
- Phase 5c does NOT have inline zip bash commands (uses /zip-tf)
- Phase 6 does NOT list the 5 publish steps (they're in RELEASE_PUBLISH.md)
- The delegation map references the .md files, not old skill names
- The description does not mention `/release-upgrade` or `/release-push`

- [ ] **Step 8: Commit**

```bash
git add .claude/skills/releasing/SKILL.md
git commit -m "refactor: slim down releasing SKILL.md, delegate to reference files

Replace inline build/publish steps with references to RELEASE_BUILD.md
and RELEASE_PUBLISH.md. Phase 5 zip rebuild uses /zip-tf."
```

---

### Task 5: Final verification

**Files:**
- Read: `.claude/skills/releasing/SKILL.md`
- Read: `.claude/skills/releasing/RELEASE_BUILD.md`
- Read: `.claude/skills/releasing/RELEASE_PUBLISH.md`
- Read: `.claude/skills/zip-tf/SKILL.md`

- [ ] **Step 1: Verify file structure**

```bash
ls -la .claude/skills/releasing/
```

Expected output should show exactly these files:
- `SKILL.md`
- `RELEASE_BUILD.md`
- `RELEASE_PUBLISH.md`
- `PARALLEL_TESTING.md`
- `LESSONS_LEARNED.md`

No ZIP_PACKAGING.md. No OWNERS.md.

- [ ] **Step 2: Verify cross-references resolve**

Check that all markdown links in SKILL.md point to files that exist:

```bash
grep -oP '\[.*?\]\((.*?\.md)\)' .claude/skills/releasing/SKILL.md | grep -oP '\((.*?)\)' | tr -d '()'
```

Each path should correspond to a file in the releasing directory.

- [ ] **Step 3: Verify /zip-tf has the new arguments**

Read `.claude/skills/zip-tf/SKILL.md` and confirm:
- Arguments section exists
- `$0` is output directory (default: `zipped/`)
- `$1` is custom filename (default: `<category>-<timestamp>`)
- Zip command includes the 3 additional exclusions (tests/*, schemas/tests/*, schemas/generated/*)

- [ ] **Step 4: Verify no old skill references remain**

```bash
grep -r "release-upgrade\|release-push" .claude/skills/releasing/
```

Should return zero matches (no references to the old skill names). References to "the build phase" or RELEASE_BUILD.md are fine.

- [ ] **Step 5: Commit verification results (if any fixes were needed)**

If any fixes were made during verification:

```bash
git add -A .claude/skills/
git commit -m "fix: address verification issues in releasing skill consolidation"
```

If no fixes were needed, skip this step.
