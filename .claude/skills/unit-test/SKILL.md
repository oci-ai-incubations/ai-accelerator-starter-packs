---
name: unit-test
description: Run Terraform unit tests (plan-only, mocked providers, no cloud credentials needed).
user-invocable: true
allowed-tools: Bash, Read, Grep
argument-hint: [test-file]
---

# Terraform Unit Tests

Run Terraform unit tests from the `ai-accelerator-tf/` directory.

## Arguments

- `$0` (optional) - Specific test file to run, e.g. `tests/core_plan.tftest.hcl`

## Commands

```bash
cd /Users/dkennetz/code/ai-accelerator/ai-accelerator-tf
terraform init -backend=false
```

If a specific test file is provided:
```bash
terraform test -filter=$0
```

Otherwise run all tests:
```bash
terraform test
```

## Notes

- All providers are mocked — no cloud credentials needed
- Tests are plan-only (`command = plan`)
- Requires Terraform >= 1.7
- Test files must be flat in `tests/` (Terraform does not recurse subdirectories)
- Three OCI data sources (`home_region`, `ads`, `oracle_linux`) require `override_data` blocks in every test file
- See `tests/RULES.md` for test writing guidelines
