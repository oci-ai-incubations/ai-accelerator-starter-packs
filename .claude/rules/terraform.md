---
globs: ["ai-accelerator-tf/**/*.tf", "ai-accelerator-tf/schemas/**/*.yaml", "create_final_schema.py"]
---

# Terraform Rules

- All Terraform code lives in `ai-accelerator-tf/`. Never create .tf files outside this directory.
- Run `terraform fmt -recursive` before committing any .tf file changes.
- Never edit `schema.yaml` or files under `schemas/generated/` directly — always regenerate with `create_final_schema.py`.
- Starter pack categories are: `enterprise_rag`, `enterprise_rag_aiq`, `paas_rag`, `cuopt`, `vss`. Adding a new category requires changes in `vars.tf`, `app-locals.tf`, `blueprint_files.tf`, a new schema YAML, `create_final_schema.py`, schema expectations, and a new test file.
- Version is tracked in `AI_ACCELERATOR_STACK_VERSION` and must be kept in sync with `vars.tf` default and `schemas/common_schema.yaml` enum.
- Deployments are immutable — the only way to modify a deployment is to undeploy and redeploy. There is no in-place update.
- `deployment_name` must be unique per blueprint submission.
- When creating ORM zips, TF files must be at the zip root (zip from inside `ai-accelerator-tf/`, not the parent directory).
