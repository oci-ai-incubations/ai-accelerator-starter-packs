# Security Errors Fix Checklist

This document explains the Checkov security findings reported by the Terraform Lint workflow (`.github/workflows/terraform-lint.yml`) and how to resolve them.

## Overview

The workflow runs `checkov -d . --framework terraform` in the `ai-accelerator-tf` directory. Checkov exits with code 1 when any checks fail, which causes the CI job to fail. Current status: **98 passed, 85 failed**.

---

## Checklist

### 1. Fix CKV_K8S_21: "The default namespace should not be used"

**What:** Kubernetes resources should not use the `default` namespace (security best practice—default namespace has less isolation).

**Where:** The failure shown in the scan is for:

- **Resource:** `kubernetes_ingress_v1.corrino_cp_ingress[0]`
- **File:** `ai-accelerator-tf/ingress.tf` (lines 74–108)

**Fix:** Add a `namespace` to the `metadata` block. For example, use `local.starter_pack_config.app_namespace` (as in `oci_ai_blueprints_portal_ingress` at line 154) or a dedicated namespace like `cluster-tools`.

```
metadata {
  name      = "corrino-cp-ingress"
  namespace = local.starter_pack_config.app_namespace  # add this line
  annotations = { ... }
}
```

**Other resources using `default` namespace** (likely to trigger similar failures):

- `ai-accelerator-tf/26ai.tf` – multiple resources
- `ai-accelerator-tf/secrets.tf` – lines 6, 23, 40
- `ai-accelerator-tf/rbac.tf` – line 21
- `ai-accelerator-tf/llamastack_config.tf` – line 9

Review each and switch to a non-default namespace (e.g. `cluster-tools`, `app_namespace`, or a specific app namespace) where appropriate.

---

### 2. View all 85 failed checks locally

**What:** The scan output is truncated; only one failure is fully shown.

**Where:** Run Checkov locally to see every failure:

```bash
cd ai-accelerator-tf
pip install checkov
checkov -d . --framework terraform
```

For more structured output:

```bash
checkov -d . --framework terraform --output json
```

---

### 3. Prioritize high-severity findings

**What:** Decide which checks must pass vs. can be suppressed.

**How:**

- Use `checkov -d . --framework terraform --list` to see all policies
- Use `--check` to run only specific checks
- Use `--skip-check` to exclude known-acceptable checks (document why in comments/config)

---

### 4. Fix or suppress remaining failures

**Options:**

**A. Fix the underlying issues**  
Address each failing check in the Terraform resources (namespace, RBAC, secrets handling, etc.). Use the policy guide URLs in the Checkov output (e.g. Prisma Cloud docs).

**B. Soft-fail in CI**  
If you want the workflow to pass while you work through fixes:

```yaml
# In .github/workflows/terraform-lint.yml, change the Checkov step to:
- name: Checkov Security Scan
  working-directory: ai-accelerator-tf
  run: checkov -d . --framework terraform --soft-fail
```

`--soft-fail` makes Checkov exit 0 even when checks fail, so the job does not block PRs.

**C. Use a config file to skip specific checks**  
Create `.checkov.yml` in the repo and explicitly skip checks you’ve decided to accept (document each in the config and/or this doc).

_Implemented:_ The config file is at `ai-accelerator-tf/.checkov.yml`. Each skipped check has an inline comment explaining the reason. To add new skips: run `checkov -d . --framework terraform` from `ai-accelerator-tf`, identify the check ID from the output, then add it to the `skip-check` list in `.checkov.yml` with a comment. The workflow uses `--config-file .checkov.yml` when running Checkov.

---

### 5. Pin Checkov version for reproducible scans

**What:** `pip install checkov` installs the latest version, which can change results over time.

**Where:** `.github/workflows/terraform-lint.yml` (line 24)

**Fix:**

```yaml
- name: Install Checkov
  run: pip install checkov==3.2.501
```

(or another pinned version matching your local run).

---

### 6. Confirm the workflow passes after changes

**What:** Verify the Terraform Lint job succeeds.

**How:**

1. Fix at least the CKV_K8S_21 issue(s) in `ingress.tf` (and any other default-namespace resources you address).
2. Run `checkov -d . --framework terraform` locally until it returns 0 (or you’ve decided to use `--soft-fail`).
3. Push your changes and confirm the workflow is green on your branch.

---

## Summary

| Step | Action                                                     | Location                                                     |
| ---- | ---------------------------------------------------------- | ------------------------------------------------------------ |
| 1    | Add `namespace` to `corrino_cp_ingress` metadata           | `ai-accelerator-tf/ingress.tf:76-82`                         |
| 2    | Run Checkov locally to list all failures                   | `cd ai-accelerator-tf && checkov -d . --framework terraform` |
| 3    | Fix or document/suppress other default-namespace resources | `26ai.tf`, `secrets.tf`, `rbac.tf`, `llamastack_config.tf`   |
| 4    | Fix or suppress remaining Checkov failures                 | Per-checkov output                                           |
| 5    | Pin Checkov version in the workflow                        | `.github/workflows/terraform-lint.yml`                       |
| 6    | Use `--soft-fail` only if you want CI to pass while fixing | `.github/workflows/terraform-lint.yml`                       |
