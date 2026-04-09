# Publish External Skill — Design Spec

**Date:** 2026-04-09
**Status:** Approved

## Purpose

After the releasing skill completes and all packs are tested, this skill uploads the release zips to the external-facing pre-release in `oracle-quickstart/oci-ai-blueprints`. It renames zips to match the OCI Console's expected asset names, applies a swap workaround for two packs, scans for PII/secrets, and uploads one-by-one to the existing `starter-packs` release tag.

## Context

The OCI Console downloads starter pack zips from `oracle-quickstart/oci-ai-blueprints/releases/tag/starter-packs`. This is a static pre-release (not version-tagged) that gets its assets replaced each release cycle.

**The swap workaround:** The OCI Console has incorrect download links — the button for enterprise_rag (self-hosted) downloads `aiQGenAIPowered.zip` and the button for paas_rag (managed) downloads `aiQEnterpriseSearch.zip`. To compensate, we intentionally swap the contents: enterprise_rag content goes into `aiQGenAIPowered.zip` and paas_rag content goes into `aiQEnterpriseSearch.zip`.

## Skill File

**Location:** `.claude/skills/releasing/PUBLISH_EXTERNAL.md`
**Argument:** `[version]` — e.g., `v0.0.6`
**Allowed tools:** `Bash, Read, Glob, Grep, AskUserQuestion`
**User-invocable:** Yes

## Steps

### Step 1: Locate Source Zips

Read version from argument. The version must include the `v` prefix (e.g., `v0.0.6`) since zip files are named `v0.0.6_enterprise_rag.zip`. Find all 5 zips in `release_test_matrix/`:
- `<version>_enterprise_rag.zip`
- `<version>_enterprise_rag_aiq.zip`
- `<version>_paas_rag.zip`
- `<version>_cuopt.zip`
- `<version>_vss.zip`

Fail immediately if any are missing.

### Step 2: Copy & Rename with Swap

Copy to a staging directory (`/tmp/publish-external-<version>/`) using this mapping:

| Source | Target | Note |
|---|---|---|
| `<v>_enterprise_rag.zip` | `aiQGenAIPowered.zip` | **SWAPPED** — console downloads this for enterprise_rag |
| `<v>_paas_rag.zip` | `aiQEnterpriseSearch.zip` | **SWAPPED** — console downloads this for paas_rag |
| `<v>_enterprise_rag_aiq.zip` | `enterpriseAgenticAIStarterKit.zip` | |
| `<v>_cuopt.zip` | `vehicleRouteOptimizer.zip` | |
| `<v>_vss.zip` | `videoSearchSummarization.zip` | |

### Step 3: PII / Secrets Scan

For each of the 5 renamed zips in the staging directory:
1. Unzip into a **separate** temporary inspection directory (`/tmp/publish-external-scan-<version>/`)
2. Scan for prohibited content:
   - `.terraform/` directories
   - `.terraform.lock.hcl` files
   - `*.tfvars` files (`terraform.tfvars`, `*.auto.tfvars`)
   - `*.tfstate` and `*.tfstate.backup` files
   - `.env` files
   - `__pycache__/` directories
   - `.git/` directories
   - Private keys (`*.pem`, `*.key`, `id_rsa*`)
   - Secrets patterns (in non-`.tf` files only, to avoid false positives on Terraform variable descriptions): `BEGIN.*PRIVATE KEY`, hardcoded passwords, API keys
3. If anything is found: show exactly what was found with file paths and **STOP**. Do not upload.
4. Clean up the inspection directory after scanning. The staging directory (`/tmp/publish-external-<version>/`) with the 5 renamed `.zip` files is left untouched — these are what gets uploaded in Step 4.

### Step 4: Upload One-by-One

Target: `oracle-quickstart/oci-ai-blueprints`, release tag `starter-packs`.

For each of the 5 zip files in the staging directory:
1. Upload with `--clobber` to atomically replace the existing asset:
   ```bash
   gh release upload starter-packs /tmp/publish-external-<version>/<name>.zip \
     --repo oracle-quickstart/oci-ai-blueprints --clobber
   ```
   `--clobber` deletes any existing asset with the same name before uploading the new one.
2. Verify the upload succeeded before moving to the next asset

If any upload fails, stop and report which assets have been updated and which haven't, so the user can resume manually.

### Step 5: Verify & Report

1. List all assets on the release: `gh release view starter-packs --repo oracle-quickstart/oci-ai-blueprints --json assets,isPrerelease`
2. Confirm the release is still marked as pre-release
3. Print a summary table:

```
| Asset Name                        | Size    | Updated   |
|-----------------------------------|---------|-----------|
| aiQEnterpriseSearch.zip           | 156 KB  | 2026-04-09|
| aiQGenAIPowered.zip              | 156 KB  | 2026-04-09|
| enterpriseAgenticAIStarterKit.zip | 156 KB  | 2026-04-09|
| vehicleRouteOptimizer.zip        | 156 KB  | 2026-04-09|
| videoSearchSummarization.zip     | 156 KB  | 2026-04-09|
```

4. Clean up the staging directory

## What It Does NOT Do

- Does not change the release from pre-release to published
- Does not modify the release title, notes, or tag
- Does not touch the internal GitHub release in `oci-ai-incubations/ai-accelerator-starter-packs`

## Testing Strategy

During implementation, validate the skill against a temporary test release before touching the real `starter-packs` release.

### Setup: Create test release

```bash
# Create an empty pre-release with a test tag (no assets yet)
gh release create starter-packs-test \
  --repo oracle-quickstart/oci-ai-blueprints \
  --title "Starter Packs - Test" \
  --prerelease \
  --notes "Temporary release for testing publish-external skill. Safe to delete."
```

### Develop & test

1. Hardcode `starter-packs-test` as the release tag in the skill while developing
2. **Run 1 (fresh upload):** Run `/publish-external v0.0.6` against the empty test release
3. Verify all 5 assets appear with correct names and sizes
4. Verify the swap is correct (enterprise_rag content in `aiQGenAIPowered.zip`, paas_rag content in `aiQEnterpriseSearch.zip`)
5. **Run 2 (clobber test):** Run `/publish-external v0.0.6` again — this time assets already exist, so `--clobber` must replace them. This is the production scenario (the real `starter-packs` release always has existing assets).
6. Verify all 5 assets are present with updated timestamps from the second run

### Finalize

1. Switch the hardcoded tag in the skill back to `starter-packs`
2. Delete the test release and tag:
   ```bash
   gh release delete starter-packs-test \
     --repo oracle-quickstart/oci-ai-blueprints --yes --cleanup-tag
   ```

This is a manual implementation-time process, not a permanent feature of the skill.

## Error Handling

| Situation | Action |
|---|---|
| Missing source zip | Stop with error listing which zips are missing |
| PII/secrets found | Stop with exact findings, do not upload anything |
| `gh release upload --clobber` fails | Report which assets succeeded and which failed |
| Release not found | Stop — the `starter-packs` release must already exist |
| Release is not pre-release | Warn user but continue (they may have promoted it) |
