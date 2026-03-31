# Known Bugs

Ongoing list of bugs discovered during development and testing. Each entry tracks symptoms, root cause, and resolution.

| Status | ID | Title | Severity | Date |
|--------|---------|-------|----------|------|
| Fixed | BUG-001 | cuOpt variables visible in non-cuOpt ORM stacks | Medium | 2026-03-30 |
| Fixed | BUG-002 | blueprint_deploy_id empty tuple for enterprise_rag_aiq | High | 2026-03-30 |

---

### BUG-001: cuOpt variables visible in non-cuOpt ORM stacks

**Status:** Fixed
**Date found:** 2026-03-30
**Date fixed:** 2026-03-30
**Found by:** Grant during enterprise_rag_aiq ORM stack testing
**Severity:** Medium

**Symptoms:**
ORM UI displayed `cuopt_frontend_admin_password`, `cuopt_frontend_admin_username`, and `google_maps_api_key` as raw form fields when creating an `enterprise_rag_aiq` stack. These cuOpt-specific fields should not appear in non-cuOpt categories.

**Root cause:**
The three variables were defined in `vars.tf` (added in PR #92, cuOpt frontend feature) but not listed in `schemas/common_schema.yaml` with `visible: false`. ORM displays ALL Terraform variables not controlled by the schema as raw fields. The variables were only hidden via cuOpt-specific schema visibility conditions (`visible: { and: [cuopt_frontend_enabled] }` in `cuopt_schema.yaml`), which doesn't affect other categories.

**Affected files:**
- `ai-accelerator-tf/vars.tf:631-654` — variables defined here
- `ai-accelerator-tf/schemas/common_schema.yaml` — missing `visible: false` entries
- `ai-accelerator-tf/schemas/cuopt_schema.yaml:89-114` — had visibility overrides but only for cuOpt

**Workaround:**
None — the fields appeared in ORM UI for all non-cuOpt categories.

**Resolution:**
Added `cuopt_frontend_admin_username`, `cuopt_frontend_admin_password`, and `google_maps_api_key` to `common_schema.yaml` with `visible: false`. The cuOpt-specific schema already overrides these with `visible: true` conditionally. Fixed in PR #93, commit `e67bb3c`.

**Verification:** Regenerate schemas (`python3 create_final_schema.py --all`), then verify:
`grep cuopt_frontend_admin schemas/generated/enterprise_rag_aiq_schema.yaml` should show `visible: false`.

**Prevention:** Created `/schema-lint` skill that checks for variables in `vars.tf` missing from `common_schema.yaml`. The core rule: every variable must be `visible: false` in common_schema, then selectively overridden in category-specific schemas.

### BUG-002: blueprint_deploy_id empty tuple for enterprise_rag_aiq

**Status:** Fixed
**Date found:** 2026-03-30
**Date fixed:** 2026-03-30
**Found by:** Grant during ORM plan for enterprise_rag_aiq
**Severity:** High

**Symptoms:**
`terraform plan` fails with:
```
Error: Invalid index
  on vars.tf line 978, in locals:
    random_id.blueprint_deploy_id is empty tuple
```

**Root cause:**
`vars.tf:977` used `var.starter_pack_category != "enterprise_rag"` to gate access to `random_id.blueprint_deploy_id[0].hex`, but `enterprise_rag_aiq` also has this resource at count=0 (both enterprise_rag categories use Helm, not blueprints). The condition only excluded `enterprise_rag`, not `enterprise_rag_aiq`. Pre-existing bug that was masked before because `enterprise_rag_aiq` was added after the original condition was written. The same pattern was repeated for `canonical_blueprint_content` and `starter_pack_blueprint_content`.

**Affected files:**
- `ai-accelerator-tf/vars.tf:977-985` — conditions only checked `!= "enterprise_rag"` instead of `!contains(["enterprise_rag", "enterprise_rag_aiq"], ...)`

**Workaround:**
None — plan fails and blocks deployment.

**Resolution:**
Changed all three conditions in `vars.tf` to use `!contains(["enterprise_rag", "enterprise_rag_aiq"], var.starter_pack_category)`, matching the same logic used by `random_id.blueprint_deploy_id`'s count condition. Also added `&& local.deploy_application` to `starter_pack_deployment_name` to handle infra-only mode. Fixed in PR #93.

**Verification:** `terraform plan` with `starter_pack_category = "enterprise_rag_aiq"` should succeed without the "empty tuple" error.
