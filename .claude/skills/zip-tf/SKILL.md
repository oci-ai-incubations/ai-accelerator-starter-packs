---
name: zip-tf
description: Creates a clean, timestamped zip archive of ai-accelerator-tf/. Regenerates the ORM schema, excludes build artifacts and sensitive tfvars, verifies the output contains no secrets or disallowed files, and saves to zipped/. Triggers when packaging, zipping, or archiving the Terraform code for sharing or upload.
user-invocable: true
allowed-tools: Bash, Read, AskUserQuestion
---

# Zip Terraform

## Arguments

- `$0` (optional) — Output directory. Default: `zipped/`. Example: `release_test_matrix/`.
- `$1` (optional) — Custom filename without `.zip` extension. Default: `<category>-<timestamp>`. Example: `v0.0.6_cuopt`.

If no arguments are provided, behavior is unchanged (timestamped zip in `zipped/`).

## Workflow

1. Read `ai-accelerator-tf/starter_pack_category.auto.tfvars` to detect the current category
2. Regenerate schema (run from repo root):
   ```bash
   source venv/bin/activate && python3 create_final_schema.py -c <category>
   ```
3. **Ask the user to confirm** before zipping — show the category, output filename, and exclusion list
4. Create the zip
5. Verify the zip contents
6. Report results

## Create the zip

Run from the repo root so `ai-accelerator-tf/` is the top-level directory in the zip:

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

## Verify zip contents

Unzip into a temp directory, validate, then clean up:

```bash
VERIFY_DIR=$(mktemp -d)
unzip -qo "${ZIP_NAME}" -d "$VERIFY_DIR"
FAIL=0

# Must NOT contain
find "$VERIFY_DIR" -type d -name ".terraform" | grep -q . && echo "FAIL: .terraform/ found" && FAIL=1
find "$VERIFY_DIR" -name ".terraform.lock.hcl" | grep -q . && echo "FAIL: .terraform.lock.hcl found" && FAIL=1
BAD_TFVARS=$(find "$VERIFY_DIR" -name "*.tfvars" ! -name "starter_pack_category.auto.tfvars")
[ -n "$BAD_TFVARS" ] && echo "FAIL: disallowed .tfvars: $BAD_TFVARS" && FAIL=1

# Must contain
find "$VERIFY_DIR" -name "starter_pack_category.auto.tfvars" | grep -q . || { echo "FAIL: starter_pack_category.auto.tfvars missing"; FAIL=1; }
find "$VERIFY_DIR" -name "terraform.tfvars.example" | grep -q . || { echo "FAIL: terraform.tfvars.example missing"; FAIL=1; }

# PII / secrets scan — flag but don't auto-fail (user decides)
PII=$(grep -rl -E '(PRIVATE KEY|password\s*=\s*".+"|api_key\s*=\s*".+"|ocid1\.(user|tenancy)\.[a-zA-Z0-9.]+)' "$VERIFY_DIR" --include="*.tf" --include="*.tfvars" --include="*.yaml" --include="*.yml" --include="*.json" 2>/dev/null | grep -v "terraform.tfvars.example" | grep -v "\.example")
[ -n "$PII" ] && echo "WARNING: possible secrets in: $PII"

rm -rf "$VERIFY_DIR"
[ $FAIL -eq 0 ] && echo "ALL CHECKS PASSED" || echo "VERIFICATION FAILED — do not share this zip"
```

If any check fails, stop and alert the user. For PII warnings, show the flagged files and let the user decide.

## Report

Tell the user the zip filename, size, full path, and verification summary.
