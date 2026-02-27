---
name: lint
description: Run all Terraform linting checks - fmt, validate, tflint, and checkov.
user-invocable: true
allowed-tools: Bash, Read
---

# Lint

Run the full linting suite on the Terraform codebase.

## Commands

Run all of these from `ai-accelerator-tf/`:

```bash
cd /Users/dkennetz/code/ai-accelerator/ai-accelerator-tf
terraform fmt -check -diff -recursive
terraform validate
tflint --recursive
checkov -d . --framework terraform --config-file .checkov.yml
```

## On Failure

- **fmt**: Run `terraform fmt -recursive` to auto-fix, then show the diff
- **validate**: Show the error and investigate the referenced files
- **tflint**: Show warnings/errors and suggest fixes
- **checkov**: Check if the finding is already in `.checkov.yml` skip list; if legitimate, suggest a fix; if false positive, suggest adding to skip list
