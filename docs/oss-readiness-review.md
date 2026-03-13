# OSS Readiness Review

This document is a point-in-time review of the repository's readiness for public open-source release. Items are categorized by severity.

**Reviewed by:** Claude (claude-sonnet-4-6)
**Review date:** 2026-03-09
**Branch:** `oss`

---

## CRITICAL — Must Fix Before Publishing

These issues are blockers. Publishing the repo publicly with these present is a security risk.

### 1. Real API Keys as Default Values in `vars.tf`

**File:** `ai-accelerator-tf/vars.tf` lines 8 and 14

Both `ngc_secret` and `ngc_api_secret` have what appears to be a real NVIDIA NGC API key as their `default` value:

```hcl
variable "ngc_secret" {
  default = "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"
  ...
}
```

**Action required:** Replace both defaults with a clearly fake placeholder:

```hcl
default = "nvapi-replace-with-your-ngc-api-key"
```

If this key has ever been committed to version history, it should be considered compromised regardless of whether it's removed from the current commit. Rotate the key at [ngc.nvidia.com](https://ngc.nvidia.com) and audit its usage.

**Git history note:** If the key exists in git history on this branch, history must be rewritten (e.g., `git filter-repo`) before the repo goes public, or the key must be rotated immediately after publishing.

---
## HIGH -- Highly Recommended Before Publishing

### 2. Copy all docs from https://github.com/oracle-quickstart/oci-ai-blueprints/tree/main/docs/ai_accelerator_packs to docs


## MEDIUM — Recommended Before Publishing

### 3. `terraform.tfvars` in `.gitignore`

Verify that `terraform.tfvars` (which contains real credentials during local development) is properly gitignored. A `terraform.tfvars.example` is present — confirm the real file is not tracked.

```bash
git status ai-accelerator-tf/terraform.tfvars  # should show as untracked or absent
git ls-files ai-accelerator-tf/terraform.tfvars  # should return nothing
```

### 4. `starter_pack_category.auto.tfvars` Not Gitignored

This file is user-specific (it holds the chosen category for the current session). Verify it is gitignored or, if tracked, that its committed value is a sensible default.

### 5. Zip Artifacts in Root Directory

Several `.zip` files appear in the root (cuopt.zip, paas_rag.zip, vss.zip, etc.). These are build artifacts that should be gitignored, not tracked in the repository.

```bash
git ls-files "*.zip"  # should return nothing
```

### 6. `share_data_with_corrino_team_enabled` Variable

```hcl
variable "share_data_with_corrino_team_enabled" {
  description = "Allow this Terraform to send a small registration file to OCI AI Blueprints team."
  default     = true
}
```

This variable defaults to `true` and sends data to the Corrino team. For an OSS release:
- The description should clearly explain *what* data is sent, *where* it goes, and *why*.
- The default should arguably be `false` (opt-in rather than opt-out) for open-source users who are not Oracle customers.
- The registration endpoint in `app-locals.tf` should be documented or pointed at a public API if the team wants community telemetry.

### 7. `corrino_image_version` Hardcoded in `vars.tf`

```hcl
variable "corrino_image_version" {
  default = "v1.0.12-hotfix1"
}
```

This is the version of the internal Corrino backend image. If Corrino images are not publicly accessible, external users cannot deploy the stack at all. This is directly related to issue #2 above — the full picture of which images are public vs. internal needs to be resolved.

---

## LOW — Nice to Have

### 8. No `CODEOWNERS` File

A `.github/CODEOWNERS` file assigns automatic PR reviewers for different parts of the codebase. This is especially useful once external contributors start submitting PRs.

```
# .github/CODEOWNERS
*                   @oracle-devrel/ai-accelerator-maintainers
ai-accelerator-tf/  @oracle-devrel/ai-accelerator-terraform
docs/               @oracle-devrel/ai-accelerator-docs
```

### 9. No Release Automation

Currently there is no GitHub Actions workflow to cut releases or build/publish stack zips automatically. A `release.yml` workflow that:
1. Triggers on version tags (`v*`)
2. Runs `python create_final_schema.py --all`
3. Builds one zip per starter pack category
4. Attaches zips to the GitHub release

...would make it much easier for users to download and deploy without cloning the repo.

### 10. CI Badges in README Point to Hardcoded Org

The README badges reference `oracle-devrel/oci-ai-accelerator`. Confirm this is the final GitHub org/repo path before publishing.

### 11. `docs/TESTING.md` Has Absolute Local Paths

Review `docs/TESTING.md` and any skill files for absolute paths like `/Users/dkennetz/...`. These should use relative paths or repo-root-relative paths so they work for all contributors.

Found in: `.claude/skills/lint/SKILL.md` line 17:
```bash
cd /Users/dkennetz/code/ai-accelerator/ai-accelerator-tf
```
This should be a repo-relative reference, not a hardcoded local path.

---

## GOOD — Already in Place

The following are ready for OSS and require no changes:

| Area | Status | Notes |
|------|--------|-------|
| **License** | Ready | UPL-1.0 is Oracle's standard open-source license. Copyright header is present in Terraform files. |
| **Contributing guide** | Ready | `CONTRIBUTING.md` covers OCA requirement, signed-off-by, PR process, and code of conduct. |
| **Security policy** | Ready | `SECURITY.md` clearly directs reporters to `secalert_us@oracle.com` and away from public GitHub issues. |
| **CI/CD pipelines** | Ready | GitHub Actions for unit tests, linting, and schema tests. Terraform credentials are handled via dummy config — no real secrets in CI. |
| **Unit tests** | Ready | Comprehensive mocked Terraform tests covering all starter packs. No cloud credentials needed to run them. |
| **Schema tests** | Ready | Data-driven pytest suite that validates ORM schema structure. |
| **`.gitignore`** | Ready (verify) | State files, venv, generated schemas, test artifacts, and zip files appear to be gitignored. Verify `terraform.tfvars` is also excluded. |
| **Issue templates** | Ready | Created in this PR: bug report and feature request templates. |
| **PR template** | Ready | Created in this PR with OCA/signoff checklist. |
| **README** | Ready | Created in this PR. Covers deploy methods, configuration, networking, IAM, architecture, and links to all docs. |
| **IAM policy docs** | Ready | Refined in `docs/iam-policies.md` with per-feature breakdowns and verb reference. |
| **Private network docs** | Ready | Created in `docs/private-network-deployment.md` with VCN peering and bring-your-own walkthroughs. |
| **`SOFTWARE_VERSIONS.md`** | Partial | Content is good. Blocked on resolution of issue #2 (internal OCIR images). |
| **Terraform variable validation** | Ready | All key variables have `validation` blocks with clear error messages. |
| **`terraform.tfvars.example`** | Ready | Comprehensive example with all variables documented and grouped. |
| **No hardcoded secrets (except issue #1)** | Ready | The NGC key default is the only secret issue found. Everything else uses variables or Kubernetes secrets managed at runtime. |

---

## Summary

| Category | Count |
|----------|-------|
| Critical (blockers) | 1 |
| High | 0 |
| Medium | 5 |
| Low | 4 |
| Good / Ready | 15+ |

**The single non-negotiable blocker before public release is issue #1**: the real NGC API key default in `vars.tf`. Fix that, resolve the internal image accessibility question (issue #2), and this repository is substantially ready for open-source publication.
