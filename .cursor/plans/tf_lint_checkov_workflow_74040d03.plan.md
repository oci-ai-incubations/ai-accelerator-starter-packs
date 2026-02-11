---
name: TF lint checkov workflow
overview: Add a new GitHub Actions workflow for Terraform linting (fmt, validate, TFLint) and Checkov security scanning, complementing the existing terraform-test.yml and schema-tests.yml workflows.
todos:
  - id: create-workflow
    content: Create .github/workflows/terraform-lint.yml with all steps (checkout, setup terraform, setup tflint, install checkov, fmt check, init, validate, tflint, checkov)
    status: pending
isProject: false
---

# Add Terraform Lint and Checkov Workflow

## Context

Two workflows already exist:

- `[.github/workflows/terraform-test.yml](.github/workflows/terraform-test.yml)` -- runs `terraform init` + `terraform test` on PRs/pushes to `main`
- `[.github/workflows/schema-tests.yml](.github/workflows/schema-tests.yml)` -- runs pytest for schema tests

Neither performs format checking, validation, linting, or security scanning.

## New Workflow: `.github/workflows/terraform-lint.yml`

Create a single new file at `[.github/workflows/terraform-lint.yml](.github/workflows/terraform-lint.yml)` with the following steps:

**Trigger:** Pull requests to all branches (matching the user's example `branches: ['*']`).

**Steps (all scoped to `ai-accelerator-tf/` via `working-directory`):**

1. **Checkout** -- `actions/checkout@v4` (v4 to match existing workflows)
2. **Setup Terraform** -- `hashicorp/setup-terraform@v3` with version `1.9` (matching existing workflow)
3. **Setup TFLint** -- `terraform-linters/setup-tflint@v3`
4. **Install Checkov** -- `pip install checkov`
5. **Terraform Format Check** -- `terraform fmt -check -recursive` (blocking)
6. **Terraform Init** -- `terraform init -backend=false` (needed for validate and tflint)
7. **Terraform Validate** -- `terraform validate` (blocking)
8. **TFLint** -- `tflint --recursive` with `continue-on-error: true` (non-blocking, advisory)
9. **Checkov Security Scan** -- `checkov -d . --framework terraform` with `continue-on-error: true` (non-blocking, advisory)

**Key design decisions:**

- Use `working-directory: ai-accelerator-tf` on steps instead of `cd` commands (cleaner, matches existing workflow style)
- Use `actions/checkout@v4` and `hashicorp/setup-terraform@v3` to stay consistent with the existing `terraform-test.yml`
- Use Terraform 1.9 to match the existing workflow
- No terraform plan or test steps (already covered by `terraform-test.yml`)
- TFLint and Checkov are non-blocking (`continue-on-error: true`) since there's no existing config to tune them, while fmt and validate are blocking
