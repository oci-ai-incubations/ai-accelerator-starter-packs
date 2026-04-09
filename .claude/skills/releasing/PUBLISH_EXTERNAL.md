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

Set `VERSION` from the argument. The version must include the `v` prefix (e.g., `v0.0.6`) since zip files are named `v0.0.6_enterprise_rag.zip`.

Verify all 5 zips exist in `release_test_matrix/`:

```bash
VERSION="<version from argument>"
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

**Note:** Shell variables do not persist between Bash tool calls. Re-define `VERSION` and `STAGING` at the start of each step.

```bash
VERSION="<version from argument>"
STAGING="/tmp/publish-external-${VERSION}"
rm -rf "$STAGING" && mkdir -p "$STAGING"

# SWAPPED: enterprise_rag content → aiQGenAIPowered.zip (console wrongly links this for enterprise_rag)
cp "release_test_matrix/${VERSION}_enterprise_rag.zip" "$STAGING/aiQGenAIPowered.zip"

# SWAPPED: paas_rag content → aiQEnterpriseSearch.zip (console wrongly links this for paas_rag)
cp "release_test_matrix/${VERSION}_paas_rag.zip" "$STAGING/aiQEnterpriseSearch.zip"

# Normal mappings
cp "release_test_matrix/${VERSION}_enterprise_rag_aiq.zip" "$STAGING/enterpriseAgenticAIStarterKit.zip"
cp "release_test_matrix/${VERSION}_cuopt.zip" "$STAGING/vehicleRouteOptimizer.zip"
cp "release_test_matrix/${VERSION}_vss.zip" "$STAGING/videoSearchSummarization.zip"
```

Verify all 5 renamed zips exist and are non-empty:

```bash
VERSION="<version from argument>"
STAGING="/tmp/publish-external-${VERSION}"
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

**Note:** Shell variables do not persist between Bash tool calls. Re-define `VERSION`, `STAGING`, and `SCAN_DIR` at the start of each step.

```bash
VERSION="<version from argument>"
STAGING="/tmp/publish-external-${VERSION}"
SCAN_DIR="/tmp/publish-external-scan-${VERSION}"
rm -rf "$SCAN_DIR" && mkdir -p "$SCAN_DIR"

for zip in "$STAGING"/*.zip; do
  name=$(basename "$zip" .zip)
  mkdir -p "$SCAN_DIR/$name"
  unzip -q "$zip" -d "$SCAN_DIR/$name"
done
```

Run all scans:

```bash
VERSION="<version from argument>"
SCAN_DIR="/tmp/publish-external-scan-${VERSION}"

# Prohibited directories
find "$SCAN_DIR" -type d \( -name ".terraform" -o -name "__pycache__" -o -name ".git" \) 2>/dev/null

# Prohibited files
find "$SCAN_DIR" -type f \( \
  -name ".terraform.lock.hcl" -o \
  -name "*.tfvars" -o \
  -name "*.tfstate" -o \
  -name "*.tfstate.backup" -o \
  -name ".env" -o \
  -name "*.pem" -o \
  -name "*.key" -o \
  -name "id_rsa*" \
\) 2>/dev/null

# Secrets patterns in non-.tf files only (avoid false positives on Terraform variable descriptions)
find "$SCAN_DIR" -type f ! -name "*.tf" | xargs grep -l "BEGIN.*PRIVATE KEY\|password\s*=\s*\"[^\"]\+\"\|api_key\s*=\s*\"[^\"]\+\"" 2>/dev/null || true
```

If ANY of the above commands produce output, show exactly what was found and **STOP**. Do not proceed to upload.

If clean, remove the scan directory:

```bash
VERSION="<version from argument>"
SCAN_DIR="/tmp/publish-external-scan-${VERSION}"
rm -rf "$SCAN_DIR"
```

## Step 4: Upload One-by-One

Target: `oracle-quickstart/oci-ai-blueprints`, release tag `starter-packs-test`.

Upload each zip with `--clobber` to replace any existing asset of the same name:

```bash
VERSION="<version from argument>"
STAGING="/tmp/publish-external-${VERSION}"
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
VERSION="<version from argument>"
STAGING="/tmp/publish-external-${VERSION}"
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
