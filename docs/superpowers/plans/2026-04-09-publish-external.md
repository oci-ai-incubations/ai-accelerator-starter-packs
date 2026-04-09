# Publish External Skill Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create a user-invocable skill that uploads release zips to the external `oracle-quickstart/oci-ai-blueprints` pre-release, with a swap workaround and PII scan.

**Architecture:** Single skill file (`.claude/skills/releasing/PUBLISH_EXTERNAL.md`) containing step-by-step instructions for Claude to execute. No code files — this is a markdown skill that orchestrates `gh` CLI commands, file copies, and zip inspection via Bash.

**Tech Stack:** gh CLI, Bash (cp, unzip, find, grep), GitHub Releases API

---

## File Structure

| File | Action | Responsibility |
|---|---|---|
| `.claude/skills/releasing/PUBLISH_EXTERNAL.md` | Create | The skill file — all steps, mapping table, error handling |
| `.claude/skills/releasing/SKILL.md` | Modify | Add reference to PUBLISH_EXTERNAL.md as optional post-release step |

---

### Task 1: Write the PUBLISH_EXTERNAL.md skill file (with test tag)

**Files:**
- Create: `.claude/skills/releasing/PUBLISH_EXTERNAL.md`

- [ ] **Step 1: Create the skill file with frontmatter and all 5 steps**

Write `.claude/skills/releasing/PUBLISH_EXTERNAL.md` with the following complete content:

```markdown
---
name: publish-external
description: Upload release zips to the external oracle-quickstart/oci-ai-blueprints pre-release. Renames to console zip names, applies the enterprise_rag/paas_rag swap workaround, scans for PII/secrets, and uploads one-by-one with --clobber. Run after the releasing skill completes and all packs pass testing.
user-invocable: true
allowed-tools: Bash, Read, Glob, Grep, AskUserQuestion
argument-hint: [version]
---

# Publish External

Upload tested release zips to the external-facing pre-release in `oracle-quickstart/oci-ai-blueprints`.

## Arguments

- `$0` — Version in semver format (e.g., `v0.0.6`). Required.

## Constants

- **Target repo:** `oracle-quickstart/oci-ai-blueprints`
- **Release tag:** `starter-packs-test`
- **Staging dir:** `/tmp/publish-external-<version>/`
- **Scan dir:** `/tmp/publish-external-scan-<version>/`

## Step 1: Locate Source Zips

Set `VERSION` from the argument (strip leading `v` if present for file matching, keep it for display).

Verify all 5 zips exist in `release_test_matrix/`:

```bash
ls -la release_test_matrix/${VERSION}_enterprise_rag.zip \
       release_test_matrix/${VERSION}_enterprise_rag_aiq.zip \
       release_test_matrix/${VERSION}_paas_rag.zip \
       release_test_matrix/${VERSION}_cuopt.zip \
       release_test_matrix/${VERSION}_vss.zip
```

If any file is missing, stop and report which ones are absent.

## Step 2: Copy & Rename with Swap

Create the staging directory and copy zips with their console names.

**IMPORTANT — Swap workaround:** The OCI Console has incorrect download links. The button for enterprise_rag (self-hosted) downloads `aiQGenAIPowered.zip` and the button for paas_rag (managed) downloads `aiQEnterpriseSearch.zip`. To compensate, we swap the contents:

```bash
VERSION_PREFIX="${VERSION}"
STAGING="/tmp/publish-external-${VERSION_PREFIX}"
rm -rf "$STAGING" && mkdir -p "$STAGING"

# SWAPPED: enterprise_rag content → aiQGenAIPowered.zip (console wrongly links this for enterprise_rag)
cp "release_test_matrix/${VERSION_PREFIX}_enterprise_rag.zip" "$STAGING/aiQGenAIPowered.zip"

# SWAPPED: paas_rag content → aiQEnterpriseSearch.zip (console wrongly links this for paas_rag)
cp "release_test_matrix/${VERSION_PREFIX}_paas_rag.zip" "$STAGING/aiQEnterpriseSearch.zip"

# Normal mappings
cp "release_test_matrix/${VERSION_PREFIX}_enterprise_rag_aiq.zip" "$STAGING/enterpriseAgenticAIStarterKit.zip"
cp "release_test_matrix/${VERSION_PREFIX}_cuopt.zip" "$STAGING/vehicleRouteOptimizer.zip"
cp "release_test_matrix/${VERSION_PREFIX}_vss.zip" "$STAGING/videoSearchSummarization.zip"
```

Verify all 5 renamed zips exist and are non-empty:

```bash
ls -la "$STAGING"/*.zip
```

Present the mapping to the user for confirmation before proceeding:

```
Rename mapping (with swap):
  enterprise_rag      → aiQGenAIPowered.zip           (SWAPPED)
  paas_rag            → aiQEnterpriseSearch.zip        (SWAPPED)
  enterprise_rag_aiq  → enterpriseAgenticAIStarterKit.zip
  cuopt               → vehicleRouteOptimizer.zip
  vss                 → videoSearchSummarization.zip
```

## Step 3: PII / Secrets Scan

Unzip each file into a **separate** inspection directory and scan for prohibited content. The staging directory with the `.zip` files must NOT be modified — only the scan directory is used for inspection.

```bash
SCAN_DIR="/tmp/publish-external-scan-${VERSION_PREFIX}"
rm -rf "$SCAN_DIR" && mkdir -p "$SCAN_DIR"

for zip in "$STAGING"/*.zip; do
  name=$(basename "$zip" .zip)
  mkdir -p "$SCAN_DIR/$name"
  unzip -q "$zip" -d "$SCAN_DIR/$name"
done
```

Run all scans:

```bash
# Prohibited directories
find "$SCAN_DIR" -type d \( -name ".terraform" -o -name "__pycache__" -o -name ".git" \) 2>/dev/null

# Prohibited files
find "$SCAN_DIR" -type f \( \
  -name ".terraform.lock.hcl" -o \
  -name "*.tfvars" -o \
  -name ".env" -o \
  -name "*.pem" -o \
  -name "*.key" -o \
  -name "id_rsa*" \
\) 2>/dev/null

# Secrets patterns in file contents
grep -rl "BEGIN.*PRIVATE KEY\|password\s*=\s*\"[^\"]\+\"\|api_key\s*=\s*\"[^\"]\+\"" "$SCAN_DIR" 2>/dev/null || true
```

If ANY of the above commands produce output, show exactly what was found and **STOP**. Do not proceed to upload.

If clean, remove the scan directory:

```bash
rm -rf "$SCAN_DIR"
```

## Step 4: Upload One-by-One

Target: `oracle-quickstart/oci-ai-blueprints`, release tag `starter-packs-test`.

Upload each zip with `--clobber` to replace any existing asset of the same name:

```bash
REPO="oracle-quickstart/oci-ai-blueprints"
TAG="starter-packs-test"

for zip in "$STAGING"/*.zip; do
  echo "Uploading $(basename "$zip")..."
  gh release upload "$TAG" "$zip" --repo "$REPO" --clobber
  if [ $? -ne 0 ]; then
    echo "FAILED to upload $(basename "$zip")"
    echo "Assets uploaded so far may be inconsistent. Check the release manually."
    exit 1
  fi
  echo "  ✓ $(basename "$zip") uploaded"
done
```

## Step 5: Verify & Report

Check the release state and report results:

```bash
REPO="oracle-quickstart/oci-ai-blueprints"
TAG="starter-packs-test"

gh release view "$TAG" --repo "$REPO" --json assets,isPrerelease \
  --jq '{prerelease: .isPrerelease, assets: [.assets[] | {name: .name, size: .size, updated: .updatedAt}]}'
```

Confirm:
1. All 5 assets are present with the correct names
2. The release is still marked as pre-release (`isPrerelease: true`)
3. All assets have recent timestamps

Present a summary table to the user.

Clean up:

```bash
rm -rf "$STAGING"
```

## Error Handling

| Situation | Action |
|---|---|
| Missing source zip | Stop with error listing which zips are missing |
| PII/secrets found | Stop with exact findings, do not upload anything |
| `gh release upload --clobber` fails | Report which assets succeeded and which failed |
| Release not found | Stop — the release must already exist |
| Release is not pre-release | Warn user but continue |
```

- [ ] **Step 2: Verify the file was created correctly**

Read the file back and confirm:
- Frontmatter has `name: publish-external`, `user-invocable: true`, `argument-hint: [version]`
- Release tag is `starter-packs-test` (test tag — will be switched to `starter-packs` in Task 5)
- The swap mapping is correct: `enterprise_rag → aiQGenAIPowered.zip`, `paas_rag → aiQEnterpriseSearch.zip`
- All 5 zip names match NAMING.md console names
- Scan directory is separate from staging directory
- `--clobber` is used in upload commands

- [ ] **Step 3: Commit**

```bash
git add .claude/skills/releasing/PUBLISH_EXTERNAL.md
git commit -m "feat: add publish-external skill for uploading to oci-ai-blueprints (test tag)"
```

---

### Task 2: Add reference in releasing SKILL.md

**Files:**
- Modify: `.claude/skills/releasing/SKILL.md`

- [ ] **Step 1: Add PUBLISH_EXTERNAL.md to the Reference Files section**

At the bottom of `.claude/skills/releasing/SKILL.md`, in the `## Reference Files` section, add:

```markdown
- **[PUBLISH_EXTERNAL.md](PUBLISH_EXTERNAL.md)** — Upload release zips to external oracle-quickstart/oci-ai-blueprints pre-release
```

- [ ] **Step 2: Add a note after Phase 6 about the optional external publish**

After the Phase 6 section (Finalize) in SKILL.md, add:

```markdown
---

## Phase 7: Publish to External Repo (Optional)

After the internal release is finalized, optionally publish the zips to the external-facing repo:

```
/publish-external <VERSION>
```

This uploads the release zips to `oracle-quickstart/oci-ai-blueprints` with the console zip names and the enterprise_rag/paas_rag swap workaround. See [PUBLISH_EXTERNAL.md](PUBLISH_EXTERNAL.md) for details.
```

- [ ] **Step 3: Commit**

```bash
git add .claude/skills/releasing/SKILL.md
git commit -m "docs: reference publish-external skill from releasing workflow"
```

---

### Task 3: Create test release and run fresh upload test

**Files:** None (manual testing)

- [ ] **Step 1: Create the test release in oracle-quickstart/oci-ai-blueprints**

```bash
gh release create starter-packs-test \
  --repo oracle-quickstart/oci-ai-blueprints \
  --title "Starter Packs - Test" \
  --prerelease \
  --notes "Temporary release for testing publish-external skill. Safe to delete."
```

Verify it was created:

```bash
gh release view starter-packs-test --repo oracle-quickstart/oci-ai-blueprints --json tagName,isPrerelease
```

Expected: `{"isPrerelease": true, "tagName": "starter-packs-test"}`

- [ ] **Step 2: Run the skill (fresh upload — no existing assets)**

Invoke: `/publish-external v0.0.6`

This is the first run against an empty release, so `--clobber` will just upload without deleting.

- [ ] **Step 3: Verify fresh upload results**

```bash
gh release view starter-packs-test --repo oracle-quickstart/oci-ai-blueprints \
  --json assets --jq '.assets[] | "\(.name) \(.size)"'
```

Verify:
- All 5 assets present: `aiQEnterpriseSearch.zip`, `aiQGenAIPowered.zip`, `enterpriseAgenticAIStarterKit.zip`, `vehicleRouteOptimizer.zip`, `videoSearchSummarization.zip`
- `aiQGenAIPowered.zip` size matches `v0.0.6_enterprise_rag.zip` size (the swap)
- `aiQEnterpriseSearch.zip` size matches `v0.0.6_paas_rag.zip` size (the swap)
- `enterpriseAgenticAIStarterKit.zip` size matches `v0.0.6_enterprise_rag_aiq.zip` size
- `vehicleRouteOptimizer.zip` size matches `v0.0.6_cuopt.zip` size
- `videoSearchSummarization.zip` size matches `v0.0.6_vss.zip` size

Record the asset timestamps for comparison with Run 2.

---

### Task 4: Run clobber test (assets already exist)

**Files:** None (manual testing)

- [ ] **Step 1: Run the skill again (clobber — assets already exist)**

Invoke: `/publish-external v0.0.6`

This is the production scenario — assets already exist from Run 1, so `--clobber` must delete-then-replace each one.

- [ ] **Step 2: Verify clobber results**

```bash
gh release view starter-packs-test --repo oracle-quickstart/oci-ai-blueprints \
  --json assets --jq '.assets[] | "\(.name) \(.size) \(.updatedAt)"'
```

Verify:
- All 5 assets still present with correct names
- Sizes unchanged (same zips uploaded twice)
- **Timestamps are newer** than Run 1 — this proves `--clobber` replaced them

---

### Task 5: Finalize — switch to production tag and clean up

**Files:**
- Modify: `.claude/skills/releasing/PUBLISH_EXTERNAL.md`

- [ ] **Step 1: Switch release tag from test to production**

In `.claude/skills/releasing/PUBLISH_EXTERNAL.md`, replace all occurrences of `starter-packs-test` with `starter-packs`:

- In the Constants section: `**Release tag:** starter-packs`
- In Step 4 upload commands: `TAG="starter-packs"`
- In Step 5 verify commands: `TAG="starter-packs"`

- [ ] **Step 2: Delete the test release and tag**

```bash
gh release delete starter-packs-test \
  --repo oracle-quickstart/oci-ai-blueprints --yes --cleanup-tag
```

Verify it's gone:

```bash
gh release view starter-packs-test --repo oracle-quickstart/oci-ai-blueprints 2>&1
```

Expected: error — release not found.

- [ ] **Step 3: Commit**

```bash
git add .claude/skills/releasing/PUBLISH_EXTERNAL.md
git commit -m "feat: switch publish-external to production starter-packs tag"
```
