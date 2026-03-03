---
globs: ["ai-accelerator-tf/**/*.tf", "ai-accelerator-tf/schemas/**", "create_final_schema.py"]
---

# CI Checks — Pre-commit Workflow

Before every `git commit`, run all checks below and fix any failures. Each check is a separate
Bash call — never chain with `&&` so failures are visible individually.

## Working directory

```bash
cd /Users/dkennetz/code/warehouse_pick_path_optimizer_pack/ai-accelerator-starter-packs/ai-accelerator-tf
```

## 1. Format

```bash
terraform fmt -recursive
terraform fmt -check -diff -recursive   # verify clean
```

## 2. Validate

```bash
terraform init -backend=false
terraform validate
```

## 3. Unit tests

```bash
terraform test
```

## 4. Schema tests (run from repo root)

```bash
cd /Users/dkennetz/code/warehouse_pick_path_optimizer_pack/ai-accelerator-starter-packs
source venv/bin/activate
pytest ai-accelerator-tf/schemas/tests/ -v
```

## 5. Security scan (TFLint + Checkov)

```bash
cd /Users/dkennetz/code/warehouse_pick_path_optimizer_pack/ai-accelerator-starter-packs/ai-accelerator-tf
tflint --recursive
checkov -d . --framework terraform --config-file .checkov.yml
```

## Order and scope

- Always run **Format → Validate → Unit tests** before any commit that touches `.tf` files.
- Always run **Schema tests** before any commit that touches `schemas/` or `create_final_schema.py`.
- Always run **Security scan** before any commit — CI runs it on every PR and failures block merge.
- Fix all failures before committing. Do not suppress TFLint or Checkov rules without a comment
  explaining why.
