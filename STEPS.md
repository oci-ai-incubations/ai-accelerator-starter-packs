# Release Steps for v0.0.5

## NEED TO ADD:

1. set the release to "pending" until tested, then set to latest
2. should use the /capacity-quota skill instead of sanjose right out of the bat
3. Need to make sure that we are using the automation-browser tests to confirm the frontend

Detailed steps taken to create the v0.0.5 release from the latest `main` branch.

## Skill Coverage Summary

| Step                            | Covered by Skill? | Skill                                                                                                                                                                                                       |
| ------------------------------- | ----------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Prerequisites                   | Yes               | `/release-upgrade` (Prerequisites section)                                                                                                                                                                  |
| Step 1: Create Release Branch   | Yes               | `/release-upgrade` (Prerequisites: "If not, look for it. If it doesn't exist, create it from latest main.")                                                                                                 |
| Step 2: Bump Version            | Yes               | `/release-upgrade` (Step 2: Update Version Files)                                                                                                                                                           |
| Step 3: Validate Terraform      | Yes               | `/release-upgrade` (Step 3: Validate) + `/lint` (terraform fmt, validate)                                                                                                                                   |
| Step 4: Generate All Schemas    | Yes               | `/release-upgrade` (Step 3: Validate — "regenerate and test") + `/schema-gen` (standalone schema generation)                                                                                                |
| Step 5: Run Schema Tests        | Yes               | `/release-upgrade` (Step 3: Validate — "pytest schemas/tests/ -v")                                                                                                                                          |
| Step 6: Clean Build Artifacts   | Yes               | `/release-upgrade` (Step 3: Validate — "Clean up build artifacts") + `/release-upgrade > ZIP_PACKAGING.md` (Step 3)                                                                                         |
| Step 7: Scan for Sensitive Data | Yes               | `/release-upgrade > ZIP_PACKAGING.md` (Step 2: "Review for personal information") + `/release-push` (Step 1: Validate Zip Files)                                                                            |
| Step 8: Create Per-Pack Zips    | Yes               | `/release-upgrade > ZIP_PACKAGING.md` (Steps 1, 3, 4) + `/zip-tf` (standalone zip creation)                                                                                                                 |
| Step 9: Commit Version Bump     | Yes               | `/release-upgrade` (Step 5: Commit and Push)                                                                                                                                                                |
| Step 10: Push Release Branch    | Yes               | `/release-upgrade` (Step 5: Commit and Push)                                                                                                                                                                |
| Step 11: Create GitHub Release  | **No**            | No skill covers `gh release create`. `/release-push` handles post-release (validate zips, rename, Slack announcement, merge PR, tag) but does not create the GitHub Release itself. This was done manually. |

## Prerequisites

> **Skill:** `/release-upgrade` — Prerequisites section

- Started on `main` branch with a clean working tree (no uncommitted changes)
- Confirmed current version was `v0.0.4` (from `ai-accelerator-tf/AI_ACCELERATOR_STACK_VERSION`)
- Confirmed only existing GitHub release was `v1` from 2025-12-02
- Decided not to update `corrino_image_version` (kept as-is)

## Step 1: Create Release Branch

> **Skill:** `/release-upgrade` — Prerequisites: "Confirm on the correct release branch (`release_v<VERSION>`). If not, look for it. If it doesn't exist, create it from latest main."

```bash
git checkout -b release_v0.0.5
```

Created a new branch `release_v0.0.5` from `main` to isolate the release work.

## Step 2: Bump Version in All Three Files

> **Skill:** `/release-upgrade` — Step 2: Update Version Files
>
> The skill specifies all three files that must be updated together and the exact changes for each:
>
> - (a) `AI_ACCELERATOR_STACK_VERSION` — replace contents with new version
> - (b) `vars.tf` — update `accelerator_pack_stack_version` default
> - (c) `common_schema.yaml` — add new version to TOP of enum, update default

All three files must be updated together — never proceed with partial updates.

### a. `ai-accelerator-tf/AI_ACCELERATOR_STACK_VERSION`

Replaced the contents from `v0.0.4` to `v0.0.5`. This is the single source of truth for the current version.

### b. `ai-accelerator-tf/vars.tf`

Updated the `accelerator_pack_stack_version` variable default value:

```hcl
# Before
default = "v0.0.4"

# After
default = "v0.0.5"
```

This is at approximately line 403 of `vars.tf`.

### c. `ai-accelerator-tf/schemas/common_schema.yaml`

Updated the `accelerator_pack_stack_version` enum and default:

```yaml
# Before
enum:
  - "v0.0.4"
  - "v0.0.3"
  - "v0.0.2"
  - "v0.0.1"
default: "v0.0.4"

# After
enum:
  - "v0.0.5"
  - "v0.0.4"
  - "v0.0.3"
  - "v0.0.2"
  - "v0.0.1"
default: "v0.0.5"
```

New version is added to the TOP of the enum list. Previous versions are kept for rollback capability.

## Step 3: Validate Terraform Code

> **Skill:** `/release-upgrade` — Step 3: Validate ("Run validation with a feedback loop — fix and retry until clean")
>
> Also covered by `/lint` which defines the full linting suite: `terraform fmt -check -diff -recursive`, `terraform validate`, `tflint --recursive`, `checkov`. We ran a subset (fmt + validate) as prescribed by `/release-upgrade`. The full `/lint` suite also includes tflint and checkov which were not run here.

### a. Format Check

```bash
cd ai-accelerator-tf/
terraform fmt -recursive
```

No formatting changes needed (clean output).

### b. Initialize Terraform

```bash
terraform init -backend=false
```

Used `-backend=false` since no real backend is needed for local validation.

### c. Validate Configuration

```bash
terraform validate
```

Result: `Success! The configuration is valid.`

## Step 4: Generate All Schemas

> **Skill:** `/release-upgrade` — Step 3: Validate ("If schema was updated, also regenerate and test: `python3 create_final_schema.py --all`")
>
> Also available as standalone skill `/schema-gen` which wraps the same `create_final_schema.py` command and notes to run schema tests after generation.

```bash
cd /path/to/repo
source venv/bin/activate
python create_final_schema.py --all
```

This deep-merges `common_schema.yaml` with each category-specific schema (`<category>_schema.yaml`) and outputs to `schemas/generated/`:

- `schemas/generated/cuopt_schema.yaml`
- `schemas/generated/vss_schema.yaml`
- `schemas/generated/paas_rag_schema.yaml`
- `schemas/generated/enterprise_rag_schema.yaml`
- `schemas/generated/enterprise_rag_aiq_schema.yaml`

## Step 5: Run Schema Tests

> **Skill:** `/release-upgrade` — Step 3: Validate ("pytest schemas/tests/ -v")

```bash
source venv/bin/activate
pytest ai-accelerator-tf/schemas/tests/ -v
```

Result: **65 passed in 2.57s**. All tests pass including:

- YAML validity checks
- OCI meta-schema conformance (JSON Schema Draft 7)
- Required keys present
- Starter pack size enums match config
- Output/variable group references valid
- Category-specific expectations (required/absent variables, properties)
- Variable type completeness

## Step 6: Clean Build Artifacts

> **Skill:** `/release-upgrade` — Step 3: Validate ("Clean up build artifacts after validation")
>
> Also specified in `/release-upgrade > ZIP_PACKAGING.md` — Step 3: "Clean build artifacts" with the same commands.

```bash
cd ai-accelerator-tf/
rm -rf .terraform .terraform.lock.hcl
```

Removed `.terraform/` directory and lock file to avoid including them in zip files.

## Step 7: Scan for Sensitive Data

> **Skill:** `/release-upgrade > ZIP_PACKAGING.md` — Step 2: "Review for personal information — Scan the `ai-accelerator-tf/` folder for any personal information (API keys, passwords, personal emails, etc.) — Stop and alert the user if anything is found"
>
> Also covered more thoroughly by `/release-push` — Step 1: Validate Zip Files, which scans for `.terraform/`, `.terraform.lock.hcl`, `*.tfvars`, `.env`, `__pycache__/`, `.git/`, private keys, and secrets patterns. The `/release-push` validation is meant to run post-zip as a second pass.
>
> The `/zip-tf` skill also includes a PII/secrets scan as part of its verification step.

Scanned `ai-accelerator-tf/` for hardcoded passwords, API keys, and personal information:

```bash
grep -rn --include="*.tf" --include="*.tfvars" --include="*.yaml" -i "password\s*=\s*\"..." ai-accelerator-tf/
```

Findings:

- `secrets.tf` has `password = "password"` — placeholder defaults, not real credentials
- `blueprint-readiness.tf` references `var.corrino_admin_password` — variable references, safe
- Only tfvars file is `starter_pack_category.auto.tfvars` (contains category name only, no credentials)
- No `terraform.tfvars` present (it's gitignored and contains real credentials)

Conclusion: No sensitive data found. Safe to zip.

## Step 8: Create Per-Pack Zip Files

> **Skill:** `/release-upgrade > ZIP_PACKAGING.md` — Steps 1, 3, 4: Generate schema per category, clean artifacts, create zip with exclusions, repeat for all packs. Specifies the naming convention `<version>_<category>.zip` and the output directory `release_test_matrix/`.
>
> The standalone `/zip-tf` skill covers single-category zip creation with a different naming convention (timestamped, placed in `zipped/`). The release packaging uses version-prefixed names instead. Both share the same core exclusion logic (`.terraform/`, `.terraform.lock.hcl`, sensitive `*.tfvars`, `__pycache__/`, `.pytest_cache/`).

For each of the 5 starter pack categories, generated a category-specific `schema.yaml` and created an ORM-ready zip.

### Why per-pack zips?

OCI Resource Manager reads `schema.yaml` at the zip root to generate its UI form. Each starter pack has different variables, sizes, and visibility rules, so each needs its own merged schema.

### Process (repeated for each category)

For each category in `enterprise_rag`, `enterprise_rag_aiq`, `paas_rag`, `cuopt`, `vss`:

#### a. Generate category-specific schema

```bash
source venv/bin/activate
python create_final_schema.py -c <category>
```

This places the merged schema at `ai-accelerator-tf/schema.yaml` and updates `starter_pack_category.auto.tfvars` with the category name.

#### b. Create zip

```bash
cd ai-accelerator-tf
zip -r ../release_test_matrix/v0.0.5_<category>.zip . \
  -x '*.git*' \
  -x '*__pycache__*' \
  -x '*.pytest_cache*' \
  -x '.terraform/*' \
  -x '.terraform.lock.hcl' \
  -x 'terraform.tfvars' \
  -x 'tests/*' \
  -x 'schemas/tests/*' \
  -x 'schemas/generated/*'
```

Key exclusions:

- `.git*` — git metadata
- `__pycache__`, `.pytest_cache` — Python build artifacts
- `.terraform/`, `.terraform.lock.hcl` — Terraform init artifacts
- `terraform.tfvars` — contains real credentials (if present)
- `tests/` — unit test files (not needed in ORM)
- `schemas/tests/` — schema test files
- `schemas/generated/` — intermediate generated files

Key inclusions:

- All `.tf` files at zip root (required by ORM)
- `schema.yaml` at zip root (category-specific, generated in step a)
- `schemas/*.yaml` — source schema files
- `helm-values/` — Helm value templates
- All other Terraform-related files

### Resulting zip files

| File                            | Size   |
| ------------------------------- | ------ |
| `v0.0.5_enterprise_rag.zip`     | 152 KB |
| `v0.0.5_enterprise_rag_aiq.zip` | 152 KB |
| `v0.0.5_paas_rag.zip`           | 152 KB |
| `v0.0.5_cuopt.zip`              | 153 KB |
| `v0.0.5_vss.zip`                | 152 KB |

### Verification

Verified each zip has:

- `.tf` files at the root level (not nested in a subdirectory)
- A `schema.yaml` at the root (unique per category — different file sizes confirm different schemas)

## Step 9: Commit Version Bump

> **Skill:** `/release-upgrade` — Step 5: Commit and Push (specifies exact files to `git add` and commit message format "Release \<VERSION\>")

```bash
git add ai-accelerator-tf/AI_ACCELERATOR_STACK_VERSION \
       ai-accelerator-tf/vars.tf \
       ai-accelerator-tf/schemas/common_schema.yaml \
       ai-accelerator-tf/starter_pack_category.auto.tfvars

git commit -m "Release v0.0.5

Bump accelerator pack stack version to v0.0.5 in AI_ACCELERATOR_STACK_VERSION,
vars.tf default, and common_schema.yaml enum/default."
```

Files committed:

- `ai-accelerator-tf/AI_ACCELERATOR_STACK_VERSION` — version string
- `ai-accelerator-tf/vars.tf` — variable default
- `ai-accelerator-tf/schemas/common_schema.yaml` — enum list and default
- `ai-accelerator-tf/starter_pack_category.auto.tfvars` — category set to `vss` (side effect of generating last schema)

## Step 10: Push Release Branch

> **Skill:** `/release-upgrade` — Step 5: Commit and Push (`git push -u origin release_v<VERSION>`)

```bash
git push -u origin release_v0.0.5
```

Pushed the branch to the remote. GitHub provided a link to create a PR.

## Step 11: Create GitHub Release

> **Skill:** **None.** No existing skill covers creating a GitHub Release with `gh release create`.
>
> The closest skill is `/release-push`, but it handles a different workflow: validating zips, renaming them to display names (e.g., `aiQEnterpriseSearch.zip`), generating a Slack announcement, merging the release PR, and pushing a git tag. It does not create a GitHub Release with attached assets.
>
> **Gap:** Creating a GitHub Release with zip artifacts attached is not covered by any skill. This was done ad-hoc.

```bash
gh release create v0.0.5 \
  release_test_matrix/v0.0.5_enterprise_rag.zip \
  release_test_matrix/v0.0.5_enterprise_rag_aiq.zip \
  release_test_matrix/v0.0.5_paas_rag.zip \
  release_test_matrix/v0.0.5_cuopt.zip \
  release_test_matrix/v0.0.5_vss.zip \
  --target release_v0.0.5 \
  --title "v0.0.5" \
  --notes "..."
```

Created the release at: https://github.com/oci-ai-incubations/ai-accelerator-starter-packs/releases/tag/v0.0.5

The release:

- Is tagged `v0.0.5`
- Targets the `release_v0.0.5` branch
- Has all 5 starter pack zip files attached as downloadable assets
- Includes release notes listing all changes since v0.0.4

## Post-Release Notes

- The `release_v0.0.5` branch has NOT been merged back to `main` yet. A PR should be created and merged.
- The zip files in `release_test_matrix/` are local build artifacts and are not committed to the repo.
- To use a zip: download it from the GitHub release and upload to OCI Resource Manager to create a new stack.

## Steps Skipped (available in skills but not performed)

| Skipped Step                        | Skill                                         | Why Skipped                                                              |
| ----------------------------------- | --------------------------------------------- | ------------------------------------------------------------------------ |
| Full lint suite (tflint, checkov)   | `/lint`                                       | `/release-upgrade` only prescribes fmt + validate; full lint is optional |
| Test matrix creation                | `/release-upgrade > TEST_MATRIX.md`           | User did not request test matrix — went straight to zipping              |
| Display summary + user confirmation | `/release-upgrade` Step 4                     | Showed git diff but did not pause for explicit confirmation              |
| Zip validation (post-zip scan)      | `/release-push` Step 1, `/zip-tf` verify step | Did pre-zip scan instead; `/release-push` zip validation was not run     |
| Rename zips to display names        | `/release-push` Step 2                        | Uploaded with version-prefixed names directly to GitHub Release          |
| Slack announcement                  | `/release-push` Step 3                        | User did not request Slack announcement                                  |
| Merge release PR + tag              | `/release-push` Step 4                        | Release PR not yet created; merge deferred                               |
